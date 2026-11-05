package xyz.i4o.uni.launcher.integration.lyrics;

import java.io.ByteArrayInputStream;
import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.util.Locale;
import java.util.regex.Matcher;
import java.util.regex.Pattern;
import java.util.zip.InflaterInputStream;

import javax.crypto.Cipher;
import javax.crypto.spec.SecretKeySpec;

/**
 * Catalogue-specific lyric containers, all reduced to the enhanced-LRC body that
 * {@link LyricTimeline#parseEnhanced(String)} consumes:
 * {@code [lineStart,lineDuration](wordStart,wordDuration,0)word ...}
 *
 * <p>Each catalogue ships word timing in its own wrapper:
 *
 * <table>
 *   <tr><th>source</th><th>container</th><th>word marker</th></tr>
 *   <tr><td>kugou</td><td>base64 → XOR → zlib</td><td>{@code <start,dur,0>}</td></tr>
 *   <tr><td>qq</td><td>hex → 3DES → zlib</td><td>{@code text(start,dur)}</td></tr>
 *   <tr><td>kuwo</td><td>{@code tp=content} → zlib → base64 → XOR</td><td>{@code <start,end>}</td></tr>
 *   <tr><td>migu</td><td>hex → block cipher</td><td>{@code text(start,dur)}</td></tr>
 *   <tr><td>local / AWLRC</td><td>plain text</td><td>{@code <offset,dur>}</td></tr>
 * </table>
 *
 * <p>Every decoder is size-capped and silent: an unrecognised or corrupt payload returns
 * an empty string instead of throwing, because a lyric miss must never affect playback.
 */
public final class LyricCodecs {
    private static final int MAX_INFLATED = 10 * 1024 * 1024;

    /** Kugou KRC obfuscation key; the first four bytes of the file are a header. */
    private static final byte[] KRC_KEY = {
            0x40, 0x47, 0x61, 0x77, 0x5E, 0x32, 0x74, 0x47,
            0x51, 0x36, 0x31, 0x2D, (byte) 0xCE, (byte) 0xD2, 0x6E, 0x69
    };
    /** QQ QRC: 3DES (24-byte key) over a zlib stream that starts with a small XML prolog. */
    private static final String QRC_KEY = "!@#)(*$%123ZXC!@!@#)(NHL";
    /** Kuwo word-level lyrics: zlib → base64 → repeating XOR. */
    private static final byte[] KUWO_KEY = "yeelion".getBytes(StandardCharsets.US_ASCII);

    private static final Pattern KRC_LINE = Pattern.compile("^\\[(\\d+)\\s*,\\s*(\\d+)](.*)$");
    private static final Pattern KRC_WORD = Pattern.compile("<(\\d+)\\s*,\\s*(\\d+)\\s*,\\s*\\d+>");
    private static final Pattern QRC_LINE = Pattern.compile("^\\[(\\d+)\\s*,\\s*(\\d+)](.*)$");
    private static final Pattern QRC_WORD = Pattern.compile("([^()\\r\\n]*)\\((\\d+)\\s*,\\s*(\\d+)\\)");
    private static final Pattern QRC_CONTENT =
            Pattern.compile("LyricContent\\s*=\\s*\"([\\s\\S]*?)\"(?=\\s*/?>)");
    private static final Pattern MRC_LINE = Pattern.compile("\\[(\\d+),(\\d+)]");
    private static final Pattern MRC_WORD = Pattern.compile("\\((\\d+),(\\d+)\\)");
    private static final Pattern KUWO_LINE =
            Pattern.compile("^\\[(\\d{1,3}):(\\d{2})(?:[.:](\\d{1,3}))?](.*)$");
    private static final Pattern KUWO_WORD = Pattern.compile("<(-?\\d+),(-?\\d+)(?:,-?\\d+)?>");
    private static final Pattern AWLRC_LINE =
            Pattern.compile("^\\[(\\d{1,3}):(\\d{2})(?:[.:](\\d{1,3}))?](.*)$");
    private static final Pattern AWLRC_WORD = Pattern.compile("<(\\d+),(\\d+)>");

    private LyricCodecs() {
    }

    // ---- kugou ----

    /** Base64 KRC body → enhanced LRC body. */
    public static String kugou(String base64) {
        if (base64 == null || base64.isEmpty()) return "";
        byte[] raw = base64(base64);
        if (raw == null || raw.length <= 4) return "";
        byte[] plain = new byte[raw.length - 4];
        for (int i = 0; i < plain.length; i++) {
            plain[i] = (byte) (raw[i + 4] ^ KRC_KEY[i % KRC_KEY.length]);
        }
        String text = inflateUtf8(plain);
        if (text == null || text.isEmpty()) return "";
        String language = kugouLanguage(text);
        if (!language.isEmpty()) {
            // Language tags feed the display language selector, not the renderer.
            text = text.replaceAll("(?m)^\\[language:[^]]+\\]\\s*$", "");
        }
        return krcToEnhanced(text);
    }

    /** KRC language tag, e.g. {@code [language:chinese]} — appears only in word-timed KRC. */
    public static String kugouLanguage(String krc) {
        if (krc == null) return "";
        Matcher matcher = Pattern.compile("(?m)^\\[language:([^]]+)]\\s*$").matcher(krc);
        return matcher.find() ? matcher.group(1).trim() : "";
    }

    static String krcToEnhanced(String krc) {
        if (krc == null || krc.isEmpty()) return "";
        StringBuilder out = new StringBuilder();
        for (String raw : krc.split("\\r?\\n")) {
            Matcher line = KRC_LINE.matcher(raw.trim());
            if (!line.matches()) continue;
            long start = parse(line.group(1));
            long duration = parse(line.group(2));
            String body = line.group(3);
            String enhanced = wordsToEnhanced(body, KRC_WORD, start, true);
            if (enhanced.isEmpty()) continue;
            out.append('[').append(start).append(',').append(duration).append(']')
                    .append(enhanced).append('\n');
        }
        return out.toString();
    }

    /**
     * Kugou translation, when the server offers one, arrives as a JSON document whose
     * {@code type == 1} content array runs parallel to the word-timed lines.
     */
    public static String kugouTranslation(String krc, String translationJson) {
        if (krc == null || krc.isEmpty() || translationJson == null || translationJson.isEmpty()) {
            return "";
        }
        java.util.List<Long> starts = new java.util.ArrayList<>();
        for (String raw : krc.split("\\r?\\n")) {
            Matcher line = KRC_LINE.matcher(raw.trim());
            if (line.matches()) starts.add(parse(line.group(1)));
        }
        if (starts.isEmpty()) return "";
        try {
            org.json.JSONArray content = new org.json.JSONObject(translationJson)
                    .optJSONArray("content");
            if (content == null) return "";
            org.json.JSONArray parallel = null;
            for (int i = 0; i < content.length(); i++) {
                org.json.JSONObject item = content.optJSONObject(i);
                if (item != null && item.optInt("type", -1) == 1) {
                    parallel = item.optJSONArray("lyricContent");
                    break;
                }
            }
            if (parallel == null || parallel.length() != starts.size()) return "";
            StringBuilder out = new StringBuilder();
            for (int i = 0; i < parallel.length(); i++) {
                org.json.JSONArray row = parallel.optJSONArray(i);
                if (row == null) continue;
                StringBuilder text = new StringBuilder();
                for (int c = 0; c < row.length(); c++) text.append(row.optString(c, ""));
                String trimmed = text.toString().trim();
                if (trimmed.isEmpty() || "//".equals(trimmed)) continue;
                out.append(lrcStamp(starts.get(i))).append(trimmed).append('\n');
            }
            return out.toString();
        } catch (Exception malformed) {
            return "";
        }
    }

    // ---- qq ----

    /** QRC hex payload (optionally wrapped in the lyrics XML) → enhanced LRC body. */
    public static String qq(String payload) {
        if (payload == null || payload.isEmpty()) return "";
        String hex = payload.trim();
        String cdata = cdata(hex);
        if (!cdata.isEmpty()) hex = cdata;
        String plain;
        if (looksLikeHex(hex)) {
            byte[] decoded = decrypt3Des(hex);
            if (decoded == null) return "";
            plain = inflateUtf8(decoded);
            if (plain == null) return "";
            Matcher content = QRC_CONTENT.matcher(plain);
            if (content.find()) plain = content.group(1);
        } else {
            // Already decrypted (the qrc=1 branch of lyric_download returns plain text).
            plain = entities(hex);
        }
        return qrcToEnhanced(plain);
    }

    static String qrcToEnhanced(String qrc) {
        if (qrc == null || qrc.isEmpty()) return "";
        StringBuilder out = new StringBuilder();
        for (String raw : qrc.split("\\r?\\n")) {
            Matcher line = QRC_LINE.matcher(raw.trim());
            if (!line.matches()) continue;
            long start = parse(line.group(1));
            long duration = parse(line.group(2));
            String body = line.group(3);
            Matcher word = QRC_WORD.matcher(body);
            StringBuilder words = new StringBuilder();
            while (word.find()) {
                String text = word.group(1);
                if (text.isEmpty()) continue;
                words.append('(').append(word.group(2)).append(',')
                        .append(word.group(3)).append(",0)").append(text);
            }
            if (words.length() == 0) continue;
            out.append('[').append(start).append(',').append(duration).append(']')
                    .append(words).append('\n');
        }
        return out.toString();
    }

    /** The QQ plain-LRC endpoint returns XML entities instead of raw punctuation. */
    public static String entities(String value) {
        if (value == null) return "";
        return value.replace("&#58;", ":").replace("&#46;", ".")
                .replace("&#39;", "'").replace("&apos;", "'").replace("&quot;", "\"")
                .replace("&lt;", "<").replace("&gt;", ">").replace("&amp;", "&");
    }

    // ---- kuwo ----

    /**
     * Kuwo word-level response: an ASCII {@code tp=content} prolog, a blank line, then a
     * zlib stream whose inflated body is base64 of a XOR-obfuscated text.
     */
    public static String kuwoWord(byte[] body) {
        if (body == null || body.length < 15) return "";
        if (!"tp=content".equalsIgnoreCase(
                new String(body, 0, Math.min(10, body.length), StandardCharsets.US_ASCII))) {
            return "";
        }
        int start = -1;
        for (int i = 0; i + 3 < body.length; i++) {
            if (body[i] == '\r' && body[i + 1] == '\n' && body[i + 2] == '\r' && body[i + 3] == '\n') {
                start = i + 4;
                break;
            }
        }
        if (start < 0) return "";
        byte[] packed = inflate(body, start, body.length - start);
        if (packed == null || packed.length == 0) return "";
        byte[] decoded = base64(new String(packed, StandardCharsets.ISO_8859_1));
        if (decoded == null) return "";
        for (int i = 0; i < decoded.length; i++) {
            decoded[i] = (byte) (decoded[i] ^ KUWO_KEY[i % KUWO_KEY.length]);
        }
        return kuwoToEnhanced(new String(decoded, StandardCharsets.UTF_8).replace("\ufeff", ""));
    }

    /**
     * Kuwo word tags are {@code <wordStart,wordEnd>} offsets from the line start, and the
     * marker follows the word it describes, so the text is sliced between markers.
     */
    static String kuwoToEnhanced(String kuwo) {
        if (kuwo == null || kuwo.isEmpty()) return "";
        StringBuilder out = new StringBuilder();
        for (String raw : kuwo.split("\\r?\\n")) {
            Matcher line = KUWO_LINE.matcher(raw.trim());
            if (!line.matches()) continue;
            long start = parse(line.group(1)) * 60000L + parse(line.group(2)) * 1000L
                    + fractionMillis(line.group(3));
            Block block = textBeforeMarkers(line.group(4), KUWO_WORD, start);
            if (block.words.isEmpty()) continue;
            out.append('[').append(start).append(',').append(Math.max(0, block.end - start))
                    .append(']').append(block.words).append('\n');
        }
        return out.toString();
    }

    // ---- migu ----

    /** Migu MRC → 增强 LRC：{@link #mrcText} 解出明文，再交给 {@link #miguToEnhanced}。 */
    public static String migu(String hex) {
        return miguToEnhanced(mrcText(hex));
    }

    /**
     * Migu MRC 明文：每 16 个十六进制字符是一个 {@code long}，整块跑一遍 XXTEA 反混合，再按
     * UTF-16LE 读出来。已经是明文 LRC（以 {@code [} 开头）或太短（&lt; 32）的原样返回。
     */
    public static String mrcText(String hex) {
        if (hex == null) return "";
        String trimmed = hex.trim();
        if (trimmed.length() < 32) return entities(trimmed);
        if (trimmed.charAt(0) == '[') return entities(trimmed);
        int blocks = trimmed.length() / 16;
        if (blocks < 2 || blocks > 65536) return "";
        long[] data = new long[blocks];
        for (int i = 0; i < blocks; i++) {
            try {
                data[i] = new java.math.BigInteger(trimmed.substring(i * 16, i * 16 + 16), 16)
                        .longValue();
            } catch (NumberFormatException invalid) {
                return "";
            }
        }
        long delta = 2654435769L;
        long[] key = {
                27303562373562475L, 18014862372307051L, 22799692160172081L, 34058940340699235L,
                30962724186095721L, 27303523720101991L, 27303523720101998L, 31244139033526382L,
                28992395054481524L
        };
        long value = data[0];
        for (long sum = ((52 / blocks) + 6) * delta; sum != 0; sum -= delta) {
            int shift = (int) ((sum >>> 2) & 3);
            int last = blocks - 1;
            long previous = value;
            for (int i = last; i > 0; i--) {
                long mixed = (data[i] - mix(previous, data[i - 1], sum, key[(i & 3) ^ shift]));
                data[i] = mixed;
                previous = mixed;
            }
            value = data[0] - mix(previous, data[last], sum, key[shift]);
            data[0] = value;
        }
        byte[] utf16 = new byte[blocks * 8];
        for (int i = 0; i < blocks; i++) {
            long word = data[i];
            for (int b = 0; b < 8; b++) {
                utf16[i * 8 + b] = (byte) ((word >>> (8 * b)) & 0xFF);
            }
        }
        return new String(utf16, StandardCharsets.UTF_16LE)
                .replace("\u0000", "").replace("\ufeff", "");
    }

    private static long mix(long a, long b, long sum, long key) {
        return ((sum ^ a) + (key ^ b)) ^ (((b >> 5) ^ (a << 2)) + ((a >> 3) ^ (b << 4)));
    }

    /**
     * {@code [start,dur]} 开一行、{@code (start,dur)} 收一个音节 → 增强 LRC。
     *
     * <p>真实 MRC 不带整齐的换行：字段之间是 {@code \r\n} 混 {@code \u2028}，文件头还挂着
     * {@code [ti:]} / {@code [ar:]}，所以不按行切 —— 直接拿 {@code [数字,数字]} 当分隔符。
     *
     * <p>词标记是<b>跟在音节后面</b>的（{@code 起(0,0)风(0,0)了}）：每个标记关掉它前面那段文字。
     * 当成“标记在前”解析会把每行第一个字整段丢掉（{@code 起风了} → {@code 风了}）。
     */
    static String miguToEnhanced(String mrc) {
        if (mrc == null || mrc.isEmpty()) return "";
        // 一份词标记都没有的文档不是词级文档：返回空串，让调用方退回行级 lrcUrl。
        if (!MRC_WORD.matcher(mrc).find()) return "";
        Matcher line = MRC_LINE.matcher(mrc);
        StringBuilder out = new StringBuilder(mrc.length() + 32);
        int bodyStart = -1;
        long start = 0;
        long duration = 0;
        while (line.find()) {
            if (bodyStart >= 0) {
                appendMiguLine(out, start, duration, mrc.substring(bodyStart, line.start()));
            }
            bodyStart = line.end();
            start = parse(line.group(1));
            duration = parse(line.group(2));
        }
        if (bodyStart >= 0) {
            appendMiguLine(out, start, duration, mrc.substring(bodyStart));
        }
        return out.toString();
    }

    private static void appendMiguLine(StringBuilder out, long start, long duration, String raw) {
        String body = trimmed(raw);
        if (body.isEmpty()) return;
        out.append('[').append(start).append(',').append(duration).append(']');
        Matcher word = MRC_WORD.matcher(body);
        int cursor = 0;
        while (word.find()) {
            out.append('(').append(parse(word.group(1))).append(',')
                    .append(parse(word.group(2))).append(",0)")
                    .append(body, cursor, word.start());
            cursor = word.end();
        }
        out.append(body, cursor, body.length()).append('\n');
    }

    /** 去掉行首行尾的空白与各种换行/段落分隔符（{@code \u2028} 也算），中间的空格要留。 */
    private static String trimmed(String raw) {
        int start = 0;
        int stop = raw.length();
        while (start < stop && filler(raw.charAt(start))) start++;
        while (stop > start && filler(raw.charAt(stop - 1))) stop--;
        return raw.substring(start, stop);
    }

    private static boolean filler(char c) {
        return c <= ' ' || c == '\u2028' || c == '\u2029' || c == '\u0085';
    }

    // ---- local / awlrc ----

    /**
     * Enhanced LRC found next to a local file (and in a few catalogue responses):
     * {@code [mm:ss.xx]word<offset,dur>word<offset,dur>}. Offsets are relative to the line
     * start and the marker follows the word it describes.
     */
    public static String awlrc(String text) {
        if (text == null || text.isEmpty()) return "";
        StringBuilder out = new StringBuilder();
        for (String raw : text.split("\\r?\\n")) {
            Matcher line = AWLRC_LINE.matcher(raw.trim());
            if (!line.matches()) continue;
            long start = parse(line.group(1)) * 60000L + parse(line.group(2)) * 1000L
                    + fractionMillis(line.group(3));
            Block block = textBeforeMarkers(line.group(4), AWLRC_WORD, start);
            if (block.words.isEmpty()) continue;
            out.append('[').append(start).append(',').append(Math.max(0, block.end - start))
                    .append(']').append(block.words).append('\n');
        }
        return out.toString();
    }

    /**
     * Enhanced-LRC body → plain LRC. Used when a catalogue only ships word timing and the
     * translation document still has to be aligned against line timestamps.
     */
    public static String enhancedToPlain(String enhanced) {
        if (enhanced == null || enhanced.isEmpty()) return "";
        StringBuilder out = new StringBuilder();
        for (String raw : enhanced.split("\\r?\\n")) {
            Matcher line = QRC_LINE.matcher(raw.trim());
            if (!line.matches()) continue;
            long start = parse(line.group(1));
            String text = line.group(3).replaceAll("\\(\\d+,\\d+,\\d+\\)", "").trim();
            if (text.isEmpty()) continue;
            out.append(lrcStamp(start)).append(text).append('\n');
        }
        return out.toString();
    }

    // ---- shared helpers ----

    /** Decoded words of one line plus where the line ends, in absolute milliseconds. */
    private static final class Block {
        String words = "";
        long end = -1;
    }

    /**
     * Slice a line whose markers come <em>after</em> the word they describe
     * ({@code 你<0,500>好<500,1000>}). The text between two markers belongs to the second
     * marker; text whose marker is degenerate (kuwo terminates a line with {@code <-1,-1>})
     * is kept at the end of the line with no timing rather than dropped, because the line
     * text is rebuilt by concatenating the words.
     */
    private static Block textBeforeMarkers(String body, Pattern marker, long lineStart) {
        Block out = new Block();
        Matcher word = marker.matcher(body);
        StringBuilder words = new StringBuilder();
        StringBuilder untimed = new StringBuilder();
        StringBuilder pending = new StringBuilder();
        int cursor = 0;
        long lastEnd = lineStart;
        boolean any = false;
        while (word.find()) {
            pending.append(body, cursor, word.start());
            cursor = word.end();
            long from = parse(word.group(1));
            long to = parse(word.group(2));
            if (pending.length() == 0) continue;
            if (to <= from) {
                untimed.append(pending);
                pending.setLength(0);
                continue;
            }
            long start = lineStart + Math.max(0, from);
            long duration = to - from;
            words.append('(').append(start).append(',').append(duration).append(",0)")
                    .append(pending);
            pending.setLength(0);
            lastEnd = Math.max(lastEnd, start + duration);
            any = true;
        }
        pending.append(body.substring(cursor));
        untimed.append(pending);
        if (!untimed.toString().isEmpty()) {
            words.append('(').append(lastEnd).append(",0,0)").append(untimed);
            any = true;
        }
        out.words = words.toString();
        out.end = any ? lastEnd : -1;
        return out;
    }

    private static String wordsToEnhanced(String body, Pattern marker, long lineStart,
                                          boolean absolute) {
        Matcher word = marker.matcher(body);
        StringBuilder words = new StringBuilder();
        int previousEnd = -1;
        long wordStart = -1;
        long wordDuration = 0;
        while (word.find()) {
            if (previousEnd >= 0) {
                words.append('(').append(absolute ? lineStart + wordStart : wordStart)
                        .append(',').append(wordDuration).append(",0)")
                        .append(body, previousEnd, word.start());
            }
            wordStart = parse(word.group(1));
            wordDuration = parse(word.group(2));
            previousEnd = word.end();
        }
        if (previousEnd < 0) return "";
        words.append('(').append(absolute ? lineStart + wordStart : wordStart)
                .append(',').append(wordDuration).append(",0)")
                .append(body.substring(previousEnd));
        return words.toString();
    }

    private static String lrcStamp(long millis) {
        return String.format(Locale.ROOT, "[%02d:%02d.%03d]", millis / 60000,
                (millis / 1000) % 60, millis % 1000);
    }

    private static long fractionMillis(String fraction) {
        if (fraction == null || fraction.isEmpty()) return 0;
        long digits = parse(fraction);
        if (fraction.length() == 1) return digits * 100;
        if (fraction.length() == 2) return digits * 10;
        if (fraction.length() > 3) return digits / (long) Math.pow(10, fraction.length() - 3);
        return digits;
    }

    private static long parse(String value) {
        try {
            return Long.parseLong(value);
        } catch (NumberFormatException ignored) {
            return 0;
        }
    }

    private static String cdata(String payload) {
        Matcher matcher = Pattern.compile("<!\\[CDATA\\[(.*?)]]>", Pattern.DOTALL).matcher(payload);
        return matcher.find() ? matcher.group(1).trim() : "";
    }

    private static boolean looksLikeHex(String value) {
        if (value.isEmpty() || (value.length() & 1) != 0) return false;
        for (int i = 0; i < value.length(); i++) {
            if (Character.digit(value.charAt(i), 16) < 0) return false;
        }
        return true;
    }

    private static byte[] decrypt3Des(String hex) {
        int length = hex.length() / 2;
        byte[] data = new byte[length];
        for (int i = 0; i < length; i++) {
            int high = Character.digit(hex.charAt(i * 2), 16);
            int low = Character.digit(hex.charAt(i * 2 + 1), 16);
            data[i] = (byte) ((high << 4) | low);
        }
        byte[] key = QRC_KEY.getBytes(StandardCharsets.US_ASCII);
        // QRC bodies are padded by the server; a strict unpad can fail on the tail block,
        // and the zlib trailer is the real end marker, so fall back to NoPadding.
        for (String transformation : new String[]{
                "DESede/ECB/PKCS5Padding", "DESede/ECB/NoPadding"}) {
            try {
                Cipher cipher = Cipher.getInstance(transformation);
                cipher.init(Cipher.DECRYPT_MODE, new SecretKeySpec(key, "DESede"));
                return cipher.doFinal(data);
            } catch (Exception ignored) {
                // Try the next transformation.
            }
        }
        return null;
    }

    private static byte[] inflate(byte[] source, int offset, int length) {
        InflaterInputStream stream = new InflaterInputStream(
                new ByteArrayInputStream(source, offset, length));
        try {
            ByteArrayOutputStream out = new ByteArrayOutputStream();
            byte[] block = new byte[4096];
            while (true) {
                int read = stream.read(block);
                if (read < 0) return out.toByteArray();
                if (read == 0) continue;
                if (out.size() + read > MAX_INFLATED) return null;
                out.write(block, 0, read);
            }
        } catch (IOException truncated) {
            return null;
        } finally {
            try {
                stream.close();
            } catch (IOException ignored) {
            }
        }
    }

    private static String inflateUtf8(byte[] source) {
        byte[] inflated = inflate(source, 0, source.length);
        if (inflated == null) return null;
        return new String(inflated, StandardCharsets.UTF_8).replace("\ufeff", "");
    }

    /** Minimal standard-alphabet base64 decode; {@code java.util.Base64} needs API 26. */
    static byte[] base64(String value) {
        if (value == null) return null;
        StringBuilder clean = new StringBuilder(value.length());
        for (int i = 0; i < value.length(); i++) {
            char c = value.charAt(i);
            if (c == '\r' || c == '\n' || c == ' ' || c == '\t') continue;
            if (c == '=') break;
            if (c == '+' || c == '/' || (c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z')
                    || (c >= '0' && c <= '9')) {
                clean.append(c);
            } else {
                return null;
            }
        }
        int length = clean.length();
        if (length % 4 == 1) return null;
        byte[] out = new byte[length * 3 / 4];
        int written = 0;
        int buffer = 0;
        int bits = 0;
        for (int i = 0; i < length; i++) {
            char c = clean.charAt(i);
            int value6;
            if (c >= 'A' && c <= 'Z') value6 = c - 'A';
            else if (c >= 'a' && c <= 'z') value6 = c - 'a' + 26;
            else if (c >= '0' && c <= '9') value6 = c - '0' + 52;
            else if (c == '+') value6 = 62;
            else value6 = 63;
            buffer = (buffer << 6) | value6;
            bits += 6;
            if (bits >= 8) {
                bits -= 8;
                out[written++] = (byte) ((buffer >>> bits) & 0xFF);
            }
        }
        if (written == out.length) return out;
        byte[] trimmed = new byte[written];
        System.arraycopy(out, 0, trimmed, 0, written);
        return trimmed;
    }
}
