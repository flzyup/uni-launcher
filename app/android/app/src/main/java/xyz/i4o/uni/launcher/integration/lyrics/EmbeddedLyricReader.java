package xyz.i4o.uni.launcher.integration.lyrics;

import java.io.ByteArrayOutputStream;
import java.io.File;
import java.io.FileInputStream;
import java.io.IOException;
import java.io.InputStream;
import java.nio.charset.Charset;
import java.nio.charset.StandardCharsets;
import java.util.Locale;

/**
 * Lyric text stored inside the audio file itself.
 *
 * <p>A local track (USB stick, on-device download) usually ships its lyrics as a tag, and no
 * catalogue can beat that: it is the exact edit the user is listening to, it works offline, and
 * it costs one file read. Four containers cover essentially all of them:
 *
 * <ul>
 *   <li>ID3v2 (MP3): {@code USLT}, {@code SYLT} fallback, plus the {@code TXXX:LYRICS} habit;</li>
 *   <li>FLAC: {@code VORBIS_COMMENT} entry {@code LYRICS} / {@code UNSYNCEDLYRICS};</li>
 *   <li>MP4/M4A: the {@code ©lyr} atom;</li>
 *   <li>Ogg Vorbis: {@code LYRICS=} in the comment header.</li>
 * </ul>
 *
 * <p>Everything is bounded: at most {@link #MAX_SCAN} bytes are touched and only text that
 * looks like a lyric document is returned, so a 200 MB movie file costs one short read.
 */
public final class EmbeddedLyricReader {
    private static final int MAX_SCAN = 2 * 1024 * 1024;
    private static final int MAX_TEXT = 64 * 1024;

    private EmbeddedLyricReader() {
    }

    /** Lyric text inside this file, or "" when it has none (or cannot be opened). */
    public static String read(File file) {
        if (file == null || !file.isFile() || file.length() <= 0) return "";
        try (InputStream stream = new FileInputStream(file)) {
            byte[] head = new byte[(int) Math.min(MAX_SCAN, file.length())];
            int filled = readFully(stream, head);
            if (filled < 8) return "";
            byte[] data = filled == head.length ? head : trim(head, filled);
            String text = detect(data);
            return looksLikeLyrics(text) ? text : "";
        } catch (Exception unreadable) {
            return "";
        }
    }

    private static String detect(byte[] data) {
        if (startsWith(data, "ID3")) return id3(data);
        if (startsWith(data, "fLaC")) return flac(data);
        if (startsWith(data, "OggS")) return ogg(data);
        String mp4 = mp4(data);
        if (!mp4.isEmpty()) return mp4;
        // Some MP3s hide a zero-length ID3 tag in front of the first frame.
        int id3At = indexOf(data, "ID3".getBytes(StandardCharsets.US_ASCII), 0, 4096);
        return id3At > 0 ? id3(slice(data, id3At, data.length)) : "";
    }

    // ---- ID3v2 ----

    private static String id3(byte[] data) {
        if (data.length < 10) return "";
        int major = data[3] & 0xFF;
        boolean syncsafe = major >= 4;
        int size = syncsafe
                ? ((data[6] & 0x7F) << 21) | ((data[7] & 0x7F) << 14) | ((data[8] & 0x7F) << 7)
                        | (data[9] & 0x7F)
                : ((data[6] & 0xFF) << 24) | ((data[7] & 0xFF) << 16) | ((data[8] & 0xFF) << 8)
                        | (data[9] & 0xFF);
        int end = Math.min(data.length, 10 + Math.max(0, size));
        int at = 10;
        String fallback = "";
        while (at + 10 <= end) {
            String id = new String(data, at, 4, StandardCharsets.ISO_8859_1);
            if (id.charAt(0) == 0) break;
            int frameSize = syncsafe
                    ? ((data[at + 4] & 0x7F) << 21) | ((data[at + 5] & 0x7F) << 14)
                            | ((data[at + 6] & 0x7F) << 7) | (data[at + 7] & 0x7F)
                    : ((data[at + 4] & 0xFF) << 24) | ((data[at + 5] & 0xFF) << 16)
                            | ((data[at + 6] & 0xFF) << 8) | (data[at + 7] & 0xFF);
            int body = at + 10;
            int next = body + frameSize;
            if (frameSize <= 0 || next > data.length) break;
            if ("USLT".equals(id) || "SYLT".equals(id)) {
                String text = decodeFrame(data, body, frameSize, "USLT".equals(id));
                if (looksLikeLyrics(text)) return text;
            } else if ("TXXX".equals(id) || "COMM".equals(id)) {
                String text = decodeFrame(data, body, frameSize, false);
                if (looksLikeLyrics(text) && text.length() > fallback.length()) fallback = text;
            }
            at = next;
        }
        return fallback;
    }

    /** USLT = encoding(1) language(3) descriptor(NUL) text; SYLT = same preamble + sync data. */
    private static String decodeFrame(byte[] data, int body, int length, boolean unsynced) {
        if (length <= 4) return "";
        int encoding = data[body] & 0xFF;
        int textAt = body + 4;
        int limit = body + length;
        Charset charset = charsetFor(encoding);
        // Skip the content descriptor (terminated by one or two NULs depending on encoding).
        boolean wide = encoding == 1 || encoding == 2;
        int at = textAt;
        while (at < limit - 1) {
            if (data[at] == 0 && (!wide || data[at + 1] == 0)) {
                at += wide ? 2 : 1;
                break;
            }
            at += wide ? 2 : 1;
        }
        byte[] payload = slice(data, Math.min(at, limit), limit);
        String text = new String(payload, charset);
        if (unsynced) return text;
        // SYLT carries (text, time) pairs; the timestamp table is binary and useless here.
        return text.replaceAll("[\\u0000-\\u0008\\u000B-\\u001F]", "\n");
    }

    private static Charset charsetFor(int encoding) {
        switch (encoding) {
            case 1:
            case 2:
                return StandardCharsets.UTF_16;
            case 3:
                return StandardCharsets.UTF_8;
            default:
                return gbkOrLatin1();
        }
    }

    // ---- FLAC ----

    private static String flac(byte[] data) {
        int at = 4;
        while (at + 4 <= data.length) {
            int header = data[at] & 0xFF;
            boolean last = (header & 0x80) != 0;
            int type = header & 0x7F;
            int length = ((data[at + 1] & 0xFF) << 16) | ((data[at + 2] & 0xFF) << 8)
                    | (data[at + 3] & 0xFF);
            int body = at + 4;
            if (body + length > data.length) break;
            if (type == 4) {
                String text = vorbisComment(data, body, length);
                if (!text.isEmpty()) return text;
            }
            if (last) break;
            at = body + length;
        }
        return "";
    }

    private static String ogg(byte[] data) {
        return vorbisComment(data, 0, data.length);
    }

    /** Sequential scan for a {@code LYRICS=}/{@code UNSYNCEDLYRICS=} field in a comment packet. */
    private static String vorbisComment(byte[] data, int from, int length) {
        int end = Math.min(data.length, from + length);
        for (String key : new String[]{"LYRICS=", "UNSYNCEDLYRICS=", "UNSYNCED LYRICS="}) {
            byte[] needle = key.getBytes(StandardCharsets.ISO_8859_1);
            int at = indexOf(data, needle, from, end);
            if (at < 0) continue;
            int start = at + needle.length;
            int stop = start;
            while (stop < end && data[stop] != 0) stop++;
            String text = new String(slice(data, start, stop), StandardCharsets.UTF_8);
            if (looksLikeLyrics(text)) return text;
        }
        return "";
    }

    // ---- MP4 ----

    private static String mp4(byte[] data) {
        byte[] atom = {(byte) 0xA9, 'l', 'y', 'r'};
        int at = indexOf(data, atom, 0, data.length);
        if (at < 4) return "";
        int size = ((data[at - 4] & 0xFF) << 24) | ((data[at - 3] & 0xFF) << 16)
                | ((data[at - 2] & 0xFF) << 8) | (data[at - 1] & 0xFF);
        if (size <= 8) return "";
        int limit = Math.min(data.length, at + 4 + size);
        int body = at + 4;
        // Inside the ©lyr atom: `data` box (size, 'data', version/flags, reserved, text).
        int dataAt = indexOf(data, "data".getBytes(StandardCharsets.ISO_8859_1), body, limit);
        int textAt = dataAt > 0 ? dataAt + 12 : body + 4;
        if (textAt >= limit) textAt = body;
        String text = new String(slice(data, textAt, limit), StandardCharsets.UTF_8);
        return text.replaceAll("[\\u0000-\\u0008\\u000B-\\u001F]", "\n");
    }

    // ---- shared ----

    /**
     * A lyric document, not just any tag.
     *
     * <p>Timestamps are the giveaway; a tag with no timestamps is accepted only when it is long
     * enough to be a lyric sheet rather than a comment field.
     */
    private static boolean looksLikeLyrics(String text) {
        if (text == null) return false;
        String body = text.trim();
        if (body.length() < 12) return false;
        if (body.length() > MAX_TEXT) return false;
        if (body.indexOf('[') >= 0 && body.indexOf(':') > 0) return true;
        int lines = 0;
        for (int i = 0; i < body.length(); i++) {
            if (body.charAt(i) == '\n') lines++;
        }
        return lines >= 3;
    }

    private static Charset gbkOrLatin1() {
        try {
            return Charset.forName("GBK");
        } catch (Exception unavailable) {
            return StandardCharsets.ISO_8859_1;
        }
    }

    private static boolean startsWith(byte[] data, String magic) {
        byte[] needle = magic.getBytes(StandardCharsets.ISO_8859_1);
        if (data.length < needle.length) return false;
        for (int i = 0; i < needle.length; i++) {
            if (data[i] != needle[i]) return false;
        }
        return true;
    }

    private static int indexOf(byte[] data, byte[] needle, int from, int to) {
        int limit = Math.min(data.length, to) - needle.length;
        for (int i = Math.max(0, from); i <= limit; i++) {
            boolean hit = true;
            for (int j = 0; j < needle.length; j++) {
                if (data[i + j] != needle[j]) {
                    hit = false;
                    break;
                }
            }
            if (hit) return i;
        }
        return -1;
    }

    private static byte[] slice(byte[] data, int from, int to) {
        int start = Math.max(0, Math.min(from, data.length));
        int end = Math.max(start, Math.min(to, data.length));
        byte[] out = new byte[end - start];
        System.arraycopy(data, start, out, 0, out.length);
        return out;
    }

    private static byte[] trim(byte[] data, int length) {
        byte[] out = new byte[length];
        System.arraycopy(data, 0, out, 0, length);
        return out;
    }

    private static int readFully(InputStream stream, byte[] target) throws IOException {
        ByteArrayOutputStream buffer = new ByteArrayOutputStream(target.length);
        byte[] block = new byte[16384];
        int read;
        while (buffer.size() < target.length && (read = stream.read(block)) != -1) {
            buffer.write(block, 0, read);
        }
        byte[] bytes = buffer.toByteArray();
        int length = Math.min(bytes.length, target.length);
        System.arraycopy(bytes, 0, target, 0, length);
        return length;
    }

    /** Test seam: identify the container from a handful of bytes. */
    static String describe(byte[] data) {
        if (startsWith(data, "ID3")) return "id3";
        if (startsWith(data, "fLaC")) return "flac";
        if (startsWith(data, "OggS")) return "ogg";
        if (indexOf(data, new byte[]{(byte) 0xA9, 'l', 'y', 'r'}, 0, data.length) > 0) return "mp4";
        return "";
    }


}
