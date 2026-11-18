package xyz.i4o.uni.launcher.integration.lyrics;

import org.json.JSONArray;
import org.json.JSONObject;

import xyz.i4o.uni.launcher.log.LogTags;
import xyz.i4o.uni.launcher.log.UniLog;

import java.io.ByteArrayOutputStream;
import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.net.HttpURLConnection;
import java.net.URL;
import java.net.URLEncoder;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.util.ArrayList;
import java.util.List;
import java.util.Locale;

import javax.crypto.Cipher;
import javax.crypto.spec.SecretKeySpec;

/**
 * Multi-catalogue lyric lookup.
 *
 * <p>The player session tells us a recording, not lyrics. Six public catalogues hold the
 * same recording under different ids and different containers, and any one of them may be
 * down, region-blocked, or holding a different edit. So the lookup:
 *
 * <ol>
 *   <li>prefers the catalogue that belongs to the playing app (a NetEase track resolves
 *       from NetEase first, which avoids the "same title, different master" problem);</li>
 *   <li>walks the remaining catalogues in a fixed order until one returns a
 *       {@link LyricTimeline#usable() usable} document;</li>
 *   <li>caches the winning document together with its quality score, so a line-only hit
 *       can later be replaced by a word-timed one without the caller noticing.</li>
 * </ol>
 *
 * <p>All I/O happens on the caller's thread; {@link #request} owns the executor so the
 * main thread never waits. Every request is bounded (3 s connect, 4 s read, 256 KB) and
 * every failure degrades to "no lyrics" instead of an error the UI has to handle.
 */
public final class LyricCatalog {
    public static final String NETEASE = "netease";
    public static final String QQ = "qqmusic";
    public static final String KUGOU = "kugou";
    public static final String KUWO = "kuwo";
    public static final String SODA = "soda";
    public static final String MIGU = "migu";

    private static final String[] ORDER = {NETEASE, QQ, KUGOU, KUWO, SODA, MIGU};
    private static final int CONNECT_MS = 3000;
    private static final int READ_MS = 4000;
    private static final int MAX_RESPONSE = 262144;
    private static final long CACHE_VERSION = 2;
    /** 汽水 krc 行头：`[起始毫秒,时长毫秒]剩余逐字标记`。 */
    private static final java.util.regex.Pattern KRC_LINE =
            java.util.regex.Pattern.compile("^\\[(\\d+),(\\d+)\\](.*)$");
    /** 汽水逐字标记：`<行内偏移,字时长,标志>字`。 */
    private static final java.util.regex.Pattern KRC_WORD =
            java.util.regex.Pattern.compile("<(\\d+),(\\d+),(\\d+)>([^<]*)");
    private static final java.util.regex.Pattern KRC_TAG =
            java.util.regex.Pattern.compile("<[^>]*>");
    /** How long the caller waits for the first usable document before showing a miss. */
    private static final long FIRST_WAIT_MS = 2600;
    /** How much longer the workers may keep looking for a better (word-timed) document. */
    private static final long UPGRADE_WINDOW_MS = 6000;

    private static final java.util.concurrent.ExecutorService POOL =
            java.util.concurrent.Executors.newFixedThreadPool(6, new java.util.concurrent.ThreadFactory() {
                @Override
                public Thread newThread(Runnable task) {
                    Thread thread = new Thread(task, "lyric-fetch");
                    thread.setDaemon(true);
                    return thread;
                }
            });
    private static final java.util.concurrent.ExecutorService UPGRADE =
            java.util.concurrent.Executors.newSingleThreadExecutor(new java.util.concurrent.ThreadFactory() {
                @Override
                public Thread newThread(Runnable task) {
                    Thread thread = new Thread(task, "lyric-upgrade");
                    thread.setDaemon(true);
                    return thread;
                }
            });

    private final File dir;

    public LyricCatalog(File cacheDir) {
        this.dir = cacheDir;
        if (dir != null && !dir.isDirectory()) dir.mkdirs();
    }

    /** Provider id for a player package, or "" when the app is not a known catalogue owner. */
    public static String providerForPackage(String pkg) {
        if (pkg == null) return "";
        String value = pkg.toLowerCase(Locale.ROOT);
        if (value.startsWith("com.netease.cloudmusic")) return NETEASE;
        if (value.startsWith("com.tencent.qqmusic")) return QQ;
        if (value.startsWith("com.kugou.")) return KUGOU;
        if (value.startsWith("cn.kuwo.") || value.startsWith("com.shaiban.audioplayer")) return KUWO;
        // 汽水音乐 (qishui) and 咪咕音乐: neither publishes lyrics through the media session,
        // so the owning-catalogue shortcut is all they give us.
        if (value.startsWith("com.luna.music") || value.startsWith("com.ss.android.ugc.aweme.lite")) {
            return SODA;
        }
        if (value.startsWith("cmcc.wsic.car") || value.startsWith("cn.migu.music")
                || value.startsWith("com.migu")) {
            return MIGU;
        }
        return "";
    }

    public static String label(String provider) {
        if (NETEASE.equals(provider)) return "网易云音乐";
        if (QQ.equals(provider)) return "QQ 音乐";
        if (KUGOU.equals(provider)) return "酷狗音乐";
        if (KUWO.equals(provider)) return "酷我音乐";
        if (SODA.equals(provider)) return "汽水音乐";
        if (MIGU.equals(provider)) return "咪咕音乐";
        return provider == null ? "" : provider;
    }

    /** Provider ids in lookup order, for diagnostics and tests. */
    public static String[] order() {
        return ORDER.clone();
    }

    // ---- cache ----

    public LyricTimeline cached(String title, String artist, long durationMs, String provider) {
        File file = file(key(title, artist, durationMs));
        if (file == null || !file.isFile()) return LyricTimeline.EMPTY;
        try (InputStream stream = new FileInputStream(file)) {
            ByteArrayOutputStream buffer = new ByteArrayOutputStream();
            byte[] block = new byte[8192];
            int read;
            while ((read = stream.read(block)) != -1) {
                if (buffer.size() + read > MAX_RESPONSE) return LyricTimeline.EMPTY;
                buffer.write(block, 0, read);
            }
            JSONObject payload = new JSONObject(new String(buffer.toByteArray(),
                    StandardCharsets.UTF_8));
            if (payload.optLong("cv", 0) != CACHE_VERSION) return LyricTimeline.EMPTY;
            String stored = payload.optString("provider", "");
            if (!provider.isEmpty() && !stored.equals(provider)) return LyricTimeline.EMPTY;
            LyricTimeline timeline = fromJson(payload.optJSONObject("timeline"));
            if (!timeline.usable()) return LyricTimeline.EMPTY;
            // Mark the file as used now: the 30-day policy sweeps on lastModified, and a
            // document read every day must never be re-fetched.
            file.setLastModified(System.currentTimeMillis());
            return timeline;
        } catch (Exception unreadable) {
            return LyricTimeline.EMPTY;
        }
    }

    private void store(String key, String provider, LyricTimeline timeline) {
        File file = file(key);
        if (file == null || !timeline.usable()) return;
        try (OutputStream stream = new FileOutputStream(file)) {
            JSONObject payload = new JSONObject();
            payload.put("cv", CACHE_VERSION);
            payload.put("provider", provider);
            payload.put("quality", timeline.qualityScore());
            payload.put("timeline", timeline.toJson());
            stream.write(payload.toString().getBytes(StandardCharsets.UTF_8));
        } catch (Exception unwritable) {
            // A read-only cache directory still serves this session from memory.
        }
    }

    private File file(String key) {
        if (dir == null || key.isEmpty()) return null;
        try {
            byte[] digest = MessageDigest.getInstance("SHA-1")
                    .digest(key.getBytes(StandardCharsets.UTF_8));
            StringBuilder hex = new StringBuilder(digest.length * 2);
            for (byte b : digest) {
                hex.append(Character.forDigit((b >> 4) & 0xF, 16))
                        .append(Character.forDigit(b & 0xF, 16));
            }
            return new File(dir, hex + ".lyric.json");
        } catch (Exception unavailable) {
            return null;
        }
    }

    // ---- identity ----

    /** Recording identity: title, artist and whole seconds of duration. */
    public static String key(String title, String artist, long durationMs) {
        String name = normalize(strip(title));
        if (name.isEmpty()) return "";
        return name + '|' + normalize(strip(artist)) + '|'
                + (durationMs > 0 ? durationMs / 1000 : 0);
    }

    static String strip(String value) {
        if (value == null) return "";
        String text = value.replaceAll("[\\[（(【][^\\]）)】]*[\\]）)】]", " ");
        text = text.replaceAll("(?i)\\b(live|remix|dj|instrumental|acoustic|cover|remaster|"
                + "version|edit)\\b|伴奏|纯音乐|翻唱|演唱会|官方版", " ");
        return text.replaceAll("\\s+", " ").trim();
    }

    static String normalize(String value) {
        if (value == null) return "";
        String text = value.toLowerCase(Locale.ROOT);
        StringBuilder out = new StringBuilder(text.length());
        for (int i = 0; i < text.length(); i++) {
            char c = text.charAt(i);
            if (Character.isLetterOrDigit(c)) out.append(c);
        }
        return out.toString();
    }

    /** Query words handed to a catalogue search; metadata often packs both fields into one. */
    static String query(String title, String artist) {
        String name = strip(title);
        String singer = strip(artist);
        if (singer.isEmpty()) {
            String[] parts = name.split("\\s*[-–—]\\s+", 2);
            if (parts.length == 2 && !parts[0].isEmpty() && !parts[1].isEmpty()) {
                singer = parts[0];
                name = parts[1];
            }
        }
        String joined = (name + " " + singer).trim();
        return joined.isEmpty() ? strip(title) : joined;
    }

    /** 0 = different recording. At or above 3 the candidate is accepted. */
    static double score(String title, String artist, String candidateTitle, String candidateArtist,
                        long durationMs, long candidateDurationMs) {
        String want = normalize(strip(title));
        String got = normalize(strip(candidateTitle));
        if (want.isEmpty() || got.isEmpty()) return 0;
        double value;
        if (got.equals(want)) value = 3;
        else if (got.contains(want) || want.contains(got)) value = 2;
        else return 0;
        String wantArtist = normalize(artist);
        String gotArtist = normalize(candidateArtist);
        if (!wantArtist.isEmpty() && !gotArtist.isEmpty()) {
            if (gotArtist.equals(wantArtist)) value += 1.5;
            else if (gotArtist.contains(wantArtist) || wantArtist.contains(gotArtist)) value += 0.8;
            else value -= 3;
        } else {
            value += 0.3;
        }
        if (durationMs > 0 && candidateDurationMs > 0) {
            long difference = Math.abs(durationMs - candidateDurationMs);
            if (difference <= 3000) value += 1;
            else if (difference <= 10000) value += 0.2;
            else return 0;
        }
        return value;
    }

    private static final double ACCEPT = 3.0;

    // ---- lookup ----

    /** Told when a better document for the same recording arrives after the first answer. */
    public interface Upgrade {
        void onBetter(Result result);
    }

    /** Blocking lookup. Returns an empty timeline when no catalogue has this recording. */
    public Result load(String title, String artist, long durationMs, String owner) {
        return load(title, artist, durationMs, owner, "", null);
    }

    /**
     * Race every catalogue at once, hand back the first usable document, then keep looking.
     *
     * <p>A sequential walk waited for NetEase to time out before QQ was even asked, so a cold
     * track took four seconds and a dead catalogue took twelve. Racing them costs one extra
     * request per catalogue and yields the first usable answer in about the time of the fastest
     * one. The slower catalogues are not abandoned: whatever they return within
     * {@link #UPGRADE_WINDOW_MS} that scores higher (word timing instead of plain lines) is
     * pushed through {@code upgrade}, so the panel starts with plain lines and quietly turns
     * karaoke a moment later.
     */
    public Result load(String title, String artist, long durationMs, String owner, String mediaId,
                       final Upgrade upgrade) {
        final String cacheKey = key(title, artist, durationMs);
        if (cacheKey.isEmpty()) return Result.EMPTY;
        LyricTimeline cached = cached(title, artist, durationMs, "");
        if (!cached.isEmpty()) {
            return new Result(cached, "", "本地缓存", true, cached.qualityScore());
        }
        final String directId = mediaId == null ? "" : mediaId.trim();
        final java.util.concurrent.BlockingQueue<Result> queue =
                new java.util.concurrent.LinkedBlockingQueue<Result>();
        String[] providers = plan(owner);
        final int total = providers.length;
        for (final String provider : providers) {
            POOL.execute(new Runnable() {
                @Override
                public void run() {
                    Result result = Result.EMPTY;
                    try {
                        // A media id from the playing app's own session skips search entirely.
                        LyricTimeline hit = direct(provider, directId, title, artist, durationMs);
                        if (hit == null || !hit.usable()) {
                            hit = fetch(provider, title, artist, durationMs);
                        }
                        if (hit != null && hit.usable()) {
                            store(cacheKey, provider, hit);
                            result = new Result(hit, provider, label(provider), false,
                                    hit.qualityScore());
                        }
                    } catch (Exception offline) {
                        // A dead catalogue is not a lyric failure the UI sees — but it used to be
                        // invisible too, which is why "歌在放，歌词一直不出来" had no trace to
                        // follow. Keep the last reason per provider for the diagnostics line.
                        recordFailure(provider, offline);
                    }
                    queue.offer(result);
                }
            });
        }
        Result best = Result.EMPTY;
        long deadline = System.currentTimeMillis() + FIRST_WAIT_MS;
        int answered = 0;
        while (answered < total) {
            long left = deadline - System.currentTimeMillis();
            if (left <= 0) break;
            Result result;
            try {
                result = queue.poll(left, java.util.concurrent.TimeUnit.MILLISECONDS);
            } catch (InterruptedException interrupted) {
                Thread.currentThread().interrupt();
                break;
            }
            if (result == null) break;
            answered++;
            if (result.betterThan(best)) best = result;
            if (best.score > 0) break;
        }
        if (upgrade != null && answered < total) {
            final Result first = best;
            final int already = answered;
            UPGRADE.execute(new Runnable() {
                @Override
                public void run() {
                    Result current = first;
                    int left = total - already;
                    long deadline = System.currentTimeMillis() + UPGRADE_WINDOW_MS;
                    while (left > 0) {
                        long wait = deadline - System.currentTimeMillis();
                        if (wait <= 0) break;
                        Result result;
                        try {
                            result = queue.poll(wait, java.util.concurrent.TimeUnit.MILLISECONDS);
                        } catch (InterruptedException interrupted) {
                            Thread.currentThread().interrupt();
                            return;
                        }
                        if (result == null) break;
                        left--;
                        if (result.betterThan(current)) {
                            current = result;
                            upgrade.onBetter(result);
                        }
                    }
                }
            });
        }
        return best;
    }

    /** The playing app's own catalogue first, then everyone else. */
    /**
     * Last failure per provider, for the diagnostics line.
     *
     * <p>Catalogue errors stay invisible to the UI on purpose (a dead source must not turn into a
     * lyric error banner), but a silent swallow makes "no lyrics at all" impossible to diagnose
     * from a log — which is exactly how the 汽水/咪咕 outage of this pipeline stayed hidden.
     */
    private static final java.util.Map<String, String> FAILURES =
            new java.util.concurrent.ConcurrentHashMap<String, String>();

    static void recordFailure(String provider, Throwable error) {
        String detail = error == null ? "unknown" : error.getClass().getSimpleName()
                + (error.getMessage() == null ? "" : (": " + error.getMessage()));
        if (detail.length() > 160) detail = detail.substring(0, 160);
        FAILURES.put(String.valueOf(provider), detail);
    }

    /** Diagnostics: {@code "netease=SocketTimeoutException; kugou=..."}, or "" for no failures. */
    public static String describeFailures() {
        if (FAILURES.isEmpty()) return "";
        StringBuilder out = new StringBuilder();
        for (java.util.Map.Entry<String, String> entry : FAILURES.entrySet()) {
            if (out.length() > 0) out.append("; ");
            out.append(entry.getKey()).append('=').append(entry.getValue());
        }
        return out.toString();
    }

    static String[] plan(String owner) {
        String preferred = providerForPackage(owner);
        if (owner != null) {
            for (String provider : ORDER) {
                if (provider.equals(owner)) preferred = owner;
            }
        }
        if (preferred.isEmpty()) return ORDER.clone();
        String[] out = new String[ORDER.length];
        out[0] = preferred;
        int index = 1;
        for (String provider : ORDER) {
            if (!provider.equals(preferred)) out[index++] = provider;
        }
        return out;
    }

    /**
     * Search spellings worth trying for one recording.
     *
     * <p>Chinese catalogue titles carry the drama name, the Live/伴奏 marker and the featured
     * artist inside the title ("飞 (Live)"、"某某 - 电视剧《…》主题曲"), and every catalogue
     * spells them differently. One cleaned query therefore misses often enough to matter; the
     * list is ordered from most specific to most forgiving and the caller stops at the first
     * document that scores.
     */
    static List<String[]> variants(String title, String artist) {
        List<String[]> out = new ArrayList<>();
        addVariant(out, title, artist);
        String stripped = strip(title);
        addVariant(out, stripped, artist);
        int cut = subtitleCut(stripped);
        if (cut > 1) addVariant(out, stripped.substring(0, cut).trim(), artist);
        String noFeature = stripped
                .replaceAll("(?i)\\s*(feat\\.?|ft\\.?|featuring)\\s+.*$", "")
                .replaceAll("(?i)\\s*[-–—]\\s*(live|remix|dj|inst\\.?|伴奏|纯音乐).*$", "");
        addVariant(out, noFeature, artist);
        return out;
    }

    private static void addVariant(List<String[]> out, String title, String artist) {
        String name = title == null ? "" : title.trim();
        if (name.isEmpty()) return;
        String key = normalize(name) + "|" + normalize(artist);
        for (String[] existing : out) {
            if ((normalize(existing[0]) + "|" + normalize(existing[1])).equals(key)) return;
        }
        out.add(new String[]{name, artist == null ? "" : artist});
    }

    /** Index of the first subtitle separator (" - ", "（", "《", "["), or -1. */
    private static int subtitleCut(String value) {
        if (value == null) return -1;
        int best = -1;
        String[] marks = {" - ", " – ", "（", "(", "《", "[", "【"};
        for (String mark : marks) {
            int at = value.indexOf(mark);
            if (at > 1 && (best < 0 || at < best)) best = at;
        }
        return best;
    }

    /** Every query variant against one catalogue, stopping at the first usable document. */
    private LyricTimeline fetch(String provider, String title, String artist, long durationMs) {
        LyricTimeline best = LyricTimeline.EMPTY;
        for (String[] variant : variants(title, artist)) {
            try {
                LyricTimeline timeline = fetchOne(provider, variant[0], variant[1], durationMs);
                if (timeline != null && timeline.usable()) {
                    if (timeline.qualityScore() > best.qualityScore()) best = timeline;
                    if (best.hasWordTiming()) return best;
                }
            } catch (Exception offline) {
                // Try the next spelling; a dead catalogue is handled by the caller.
            }
        }
        return best;
    }

    /**
     * Fetch by the id the playing app already knows, skipping the search round trip.
     *
     * <p>The media session id is only usable when it belongs to the same catalogue (a NetEase
     * song id means nothing to QQ), so this is a fast path, never the only path.
     */
    private LyricTimeline direct(String provider, String mediaId, String title, String artist,
                                 long durationMs) throws Exception {
        if (mediaId == null || mediaId.isEmpty()) return LyricTimeline.EMPTY;
        if (NETEASE.equals(provider)) {
            long id = numeric(mediaId);
            if (id > 0) return neteaseById(id, "");
        } else if (KUWO.equals(provider)) {
            String rid = mediaId.replace("MUSIC_", "");
            if (numeric(rid) > 0) return kuwoById(rid);
        } else if (QQ.equals(provider)) {
            if (mediaId.matches("[0-9A-Za-z]{10,16}")) return qqByMid(mediaId);
        } else if (SODA.equals(provider)) {
            // 汽水的 PC 搜索接口匿名调用必空，会话里的 MEDIA_ID 就是 track_id，直接用 id 取词。
            if (mediaId.matches("\\d{10,20}")) {
                LyricTimeline byId = sodaById(mediaId.trim());
                if (byId.usable()) return byId;
            }
        }
        return LyricTimeline.EMPTY;
    }

    private static long numeric(String value) {
        if (value == null) return -1;
        String digits = value.trim();
        if (digits.isEmpty() || digits.length() > 18) return -1;
        for (int i = 0; i < digits.length(); i++) {
            if (!Character.isDigit(digits.charAt(i))) return -1;
        }
        try {
            return Long.parseLong(digits);
        } catch (NumberFormatException tooBig) {
            return -1;
        }
    }

    private LyricTimeline fetchOne(String provider, String title, String artist, long durationMs)
            throws Exception {
        String words = encode(query(title, artist));
        if (NETEASE.equals(provider)) return netease(title, artist, durationMs, words);
        if (QQ.equals(provider)) return qq(title, artist, durationMs, words);
        if (KUGOU.equals(provider)) return kugou(title, artist, durationMs, words);
        if (KUWO.equals(provider)) return kuwo(title, artist, durationMs, words);
        if (SODA.equals(provider)) return soda(title, artist, durationMs, words);
        if (MIGU.equals(provider)) return migu(title, artist, durationMs, words);
        return LyricTimeline.EMPTY;
    }

    // ---- netease ----

    private LyricTimeline netease(String title, String artist, long durationMs, String words)
            throws Exception {
        String search = post("https://music.163.com/api/search/get/web",
                "s=" + words + "&type=1&limit=20&offset=0", "https://music.163.com/", null);
        JSONObject result = new JSONObject(search).optJSONObject("result");
        JSONArray songs = result == null ? null : result.optJSONArray("songs");
        if (songs == null) return LyricTimeline.EMPTY;
        double best = 0;
        long id = -1;
        for (int i = 0; i < songs.length(); i++) {
            JSONObject song = songs.optJSONObject(i);
            if (song == null) continue;
            JSONObject first = first(song.optJSONArray("artists"));
            double value = score(title, artist, song.optString("name"),
                    first == null ? "" : first.optString("name"),
                    durationMs, song.optLong("duration", 0));
            if (value > best) {
                best = value;
                id = song.optLong("id", -1);
            }
        }
        if (best < ACCEPT || id <= 0) return LyricTimeline.EMPTY;
        return neteaseById(id, "");
    }

    /** eapi lyric document for one known song id (the only endpoint that also returns yrc). */
    private LyricTimeline neteaseById(long id, String ignored) throws Exception {
        String body = eapiBody(id);
        String payload = post("https://interface3.music.163.com/eapi/song/lyric/v1", body,
                "https://music.163.com/", "os=pc; appver=2.9.7;");
        JSONObject lyric = new JSONObject(payload);
        if (lyric.optInt("code", 0) != 200) return LyricTimeline.EMPTY;
        return LyricTimeline.parse(
                value(lyric, "lrc"),
                value(lyric, "tlyric"),
                value(lyric, "yrc"),
                value(lyric, "yromalrc").isEmpty() ? value(lyric, "romalrc")
                        : value(lyric, "yromalrc"));
    }

    private static String value(JSONObject lyric, String field) {
        JSONObject node = lyric.optJSONObject(field);
        return node == null ? "" : node.optString("lyric", "");
    }

    /**
     * EAPI envelope: the parameters are AES-ECB encrypted under a fixed client key, with an
     * MD5 digest binding the path to the payload so a stale request cannot be replayed onto
     * another endpoint.
     */
    static String eapiBody(long songId) throws Exception {
        String path = "/api/song/lyric/v1";
        String json = "{\"id\":" + songId + ",\"cp\":false,\"tv\":0,\"lv\":0,\"rv\":0,\"kv\":0,"
                + "\"yv\":0,\"ytv\":0,\"yrv\":0}";
        String digest = md5Hex("nobody" + path + "use" + json + "md5forencrypt")
                .toLowerCase(Locale.ROOT);
        String plain = path + "-36cd479b6b5-" + json + "-36cd479b6b5-" + digest;
        Cipher cipher = Cipher.getInstance("AES/ECB/PKCS5Padding");
        cipher.init(Cipher.ENCRYPT_MODE, new SecretKeySpec(
                "e82ckenh8dichen8".getBytes(StandardCharsets.US_ASCII), "AES"));
        byte[] encrypted = cipher.doFinal(plain.getBytes(StandardCharsets.UTF_8));
        StringBuilder hex = new StringBuilder(encrypted.length * 2);
        for (byte b : encrypted) {
            hex.append(Character.forDigit((b >> 4) & 0xF, 16))
                    .append(Character.forDigit(b & 0xF, 16));
        }
        return "params=" + hex.toString().toUpperCase(Locale.ROOT);
    }

    private static String md5Hex(String value) throws Exception {
        byte[] digest = MessageDigest.getInstance("MD5")
                .digest(value.getBytes(StandardCharsets.UTF_8));
        StringBuilder hex = new StringBuilder(digest.length * 2);
        for (byte b : digest) {
            hex.append(Character.forDigit((b >> 4) & 0xF, 16))
                    .append(Character.forDigit(b & 0xF, 16));
        }
        return hex.toString();
    }

    // ---- qq ----

    private LyricTimeline qq(String title, String artist, long durationMs, String words)
            throws Exception {
        String search = get("https://c.y.qq.com/soso/fcgi-bin/client_search_cp?p=1&n=10&w=" + words
                + "&format=json&cr=1&new_json=1", "https://y.qq.com/");
        JSONObject data = new JSONObject(search).optJSONObject("data");
        JSONObject song = data == null ? null : data.optJSONObject("song");
        JSONArray list = song == null ? null : song.optJSONArray("list");
        if (list == null) return LyricTimeline.EMPTY;
        double best = 0;
        String mid = "";
        long songId = -1;
        for (int i = 0; i < list.length(); i++) {
            JSONObject item = list.optJSONObject(i);
            if (item == null) continue;
            JSONObject first = first(item.optJSONArray("singer"));
            String name = item.optString("name", item.optString("songname", ""));
            double value = score(title, artist, name,
                    first == null ? "" : first.optString("name"),
                    durationMs, item.optLong("interval", 0) * 1000L);
            if (value > best) {
                best = value;
                mid = item.optString("mid", item.optString("songmid", ""));
                songId = item.optLong("id", -1);
            }
        }
        if (best < ACCEPT) return LyricTimeline.EMPTY;
        if (songId > 0) {
            String qrc = get("https://c.y.qq.com/qqmusic/fcgi-bin/lyric_download.fcg?version=15"
                    + "&miniversion=82&lrctype=4&musicid=" + songId, "https://y.qq.com/");
            String enhanced = LyricCodecs.qq(qrc);
            String translation = LyricCodecs.entities(cdata(qrc, "contentts"));
            if (!enhanced.isEmpty()) {
                return LyricTimeline.parse(
                        LyricCodecs.enhancedToPlain(enhanced), translation, enhanced, "");
            }
        }
        if (mid.isEmpty()) return LyricTimeline.EMPTY;
        return qqByMid(mid);
    }

    /** Plain QQ lyric document for one known songmid. */
    private LyricTimeline qqByMid(String mid) throws Exception {
        String plain = get("https://c.y.qq.com/lyric/fcgi-bin/fcg_query_lyric_new.fcg?songmid="
                + encode(mid) + "&format=json&nobase64=1", "https://y.qq.com/");
        JSONObject lyric = new JSONObject(plain);
        return LyricTimeline.parse(LyricCodecs.entities(lyric.optString("lyric", "")),
                LyricCodecs.entities(lyric.optString("trans", "")), "", "");
    }

    private static String cdata(String xml, String tag) {
        java.util.regex.Matcher matcher = java.util.regex.Pattern
                .compile("<" + java.util.regex.Pattern.quote(tag) + "[^>]*>.*?<!\\[CDATA\\[(.*?)]]>",
                        java.util.regex.Pattern.DOTALL)
                .matcher(xml);
        return matcher.find() ? matcher.group(1).trim() : "";
    }

    // ---- kugou ----

    private LyricTimeline kugou(String title, String artist, long durationMs, String words)
            throws Exception {
        String search = get("https://songsearch.kugou.com/song_search_v2?keyword=" + words
                + "&page=1&pagesize=10&userid=-1&clientver=&platform=WebFilter&filter=2"
                + "&iscorrection=1&privilege_filter=0", "https://www.kugou.com/");
        JSONObject data = new JSONObject(search).optJSONObject("data");
        JSONArray list = data == null ? null : data.optJSONArray("lists");
        if (list == null) return LyricTimeline.EMPTY;
        double best = 0;
        String hash = "";
        for (int i = 0; i < list.length(); i++) {
            JSONObject item = list.optJSONObject(i);
            if (item == null) continue;
            double value = score(title, artist, item.optString("SongName"),
                    item.optString("SingerName"), durationMs,
                    item.optLong("Duration", 0) * 1000L);
            if (value > best) {
                best = value;
                hash = item.optString("FileHash", "");
            }
        }
        if (best < ACCEPT || hash.isEmpty()) return LyricTimeline.EMPTY;
        String candidates = get("https://lyrics.kugou.com/search?ver=1&man=yes&client=pc"
                + "&hash=" + encode(hash), "https://www.kugou.com/");
        JSONArray found = new JSONObject(candidates).optJSONArray("candidates");
        if (found == null || found.length() == 0) return LyricTimeline.EMPTY;
        JSONObject first = found.optJSONObject(0);
        if (first == null) return LyricTimeline.EMPTY;
        String id = first.optString("id", "");
        String accessKey = first.optString("accesskey", "");
        if (id.isEmpty() || accessKey.isEmpty()) return LyricTimeline.EMPTY;
        String download = get("https://lyrics.kugou.com/download?ver=1&client=pc&fmt=krc"
                + "&charset=utf8&id=" + encode(id) + "&accesskey=" + encode(accessKey),
                "https://www.kugou.com/");
        String enhanced = LyricCodecs.kugou(new JSONObject(download).optString("content", ""));
        if (enhanced.isEmpty()) return LyricTimeline.EMPTY;
        return LyricTimeline.parseEnhanced(enhanced);
    }

    // ---- kuwo ----

    private LyricTimeline kuwo(String title, String artist, long durationMs, String words)
            throws Exception {
        String search = get("https://search.kuwo.cn/r.s?all=" + words
                + "&ft=music&itemset=web_2013&client=kt&pn=0&rn=10&rformat=json&encoding=utf8"
                + "&vipver=1", "https://www.kuwo.cn/");
        JSONArray list = new JSONObject(search).optJSONArray("abslist");
        if (list == null) return LyricTimeline.EMPTY;
        double best = 0;
        String rid = "";
        for (int i = 0; i < list.length(); i++) {
            JSONObject item = list.optJSONObject(i);
            if (item == null) continue;
            String musicId = item.optString("MUSICRID", "").replace("MUSIC_", "");
            double value = score(title, artist, item.optString("SONGNAME"),
                    item.optString("ARTIST"), durationMs,
                    item.optLong("DURATION", 0) * 1000L);
            if (value > best && !musicId.isEmpty()) {
                best = value;
                rid = musicId;
            }
        }
        if (best < ACCEPT || rid.isEmpty()) return LyricTimeline.EMPTY;
        return kuwoById(rid);
    }

    /** Kuwo word-timed document first, then the plain h5 lyric list, for one known rid. */
    private LyricTimeline kuwoById(String rid) throws Exception {
        // Word timing first: it is what makes the karaoke fill possible.
        byte[] word = body("http://mlyric.kuwo.cn/mobi.s?f=web&type=lyric&lrcx=1&rid=MUSIC_" + rid,
                "https://www.kuwo.cn/");
        String enhanced = LyricCodecs.kuwoWord(word);
        if (!enhanced.isEmpty()) {
            String plain = get("https://m.kuwo.cn/newh5/singles/songinfoandlrc?musicId=" + rid,
                    "https://www.kuwo.cn/");
            return LyricTimeline.parse(kuwoPlain(plain), "", enhanced, "");
        }
        String plain = get("https://m.kuwo.cn/newh5/singles/songinfoandlrc?musicId=" + rid,
                "https://www.kuwo.cn/");
        return LyricTimeline.parse(kuwoPlain(plain), "", "", "");
    }

    /** Kuwo returns `{time: "12.34", lineLyric: "..."}` rows rather than an LRC document. */
    static String kuwoPlain(String json) {
        try {
            JSONObject data = new JSONObject(json).optJSONObject("data");
            JSONArray rows = data == null ? null : data.optJSONArray("lrclist");
            if (rows == null) return "";
            StringBuilder out = new StringBuilder();
            for (int i = 0; i < rows.length(); i++) {
                JSONObject row = rows.optJSONObject(i);
                if (row == null) continue;
                String text = row.optString("lineLyric", "").trim();
                if (text.isEmpty()) continue;
                double seconds = row.optDouble("time", -1);
                if (seconds < 0) continue;
                long millis = Math.round(seconds * 1000);
                out.append(String.format(Locale.ROOT, "[%02d:%02d.%03d]", millis / 60000,
                        (millis / 1000) % 60, millis % 1000)).append(text).append('\n');
            }
            return out.toString();
        } catch (Exception malformed) {
            return "";
        }
    }

    // ---- soda (汽水音乐 / qishui) ----

    /**
     * Soda publishes no public lyric API; the share page carries the document.
     *
     * <p>Search returns track ids, and `www.qishui.com/share/track?track_id=…` embeds a
     * `window._ROUTER_DATA` blob whose `loaderData.track_page.audioWithLyricsOption.lyrics`
     * holds `sentences[]` with `startMs/endMs/text/translation/words[]`. That is the only
     * word-timed source available for this catalogue, so it is worth the HTML hop.
     */
    private LyricTimeline soda(String title, String artist, long durationMs, String words)
            throws Exception {
        String search = get("https://api.qishui.com/luna/pc/search/track?q=" + words
                + "&cursor=0&search_method=input&aid=386088&device_platform=web&channel=pc_web",
                "https://www.qishui.com/");
        if (search.trim().isEmpty()) return LyricTimeline.EMPTY;
        JSONArray groups = new JSONObject(search).optJSONArray("result_groups");
        if (groups == null) return LyricTimeline.EMPTY;
        double best = 0;
        String trackId = "";
        for (int i = 0; i < groups.length(); i++) {
            JSONObject group = groups.optJSONObject(i);
            JSONArray rows = group == null ? null : group.optJSONArray("data");
            if (rows == null) continue;
            for (int j = 0; j < rows.length(); j++) {
                JSONObject row = rows.optJSONObject(j);
                JSONObject entity = row == null ? null : row.optJSONObject("entity");
                JSONObject track = entity == null ? null : entity.optJSONObject("track");
                if (track == null) continue;
                double value = score(title, artist, track.optString("name", ""),
                        sodaArtists(track.optJSONArray("artists")), durationMs,
                        track.optLong("duration", 0));
                if (value > best) {
                    best = value;
                    trackId = track.optString("id", "");
                }
            }
        }
        if (best < ACCEPT || trackId.isEmpty()) return LyricTimeline.EMPTY;
        String page = get("https://www.qishui.com/share/track?track_id=" + encode(trackId),
                "https://www.qishui.com/");
        return sodaPage(page);
    }

    /**
     * 汽水：媒体会话只给 track_id，PC 搜索接口匿名调用必空 —— 冷门歌就是死在这一步。
     *
     * <p>分享页的 `_ROUTER_DATA` 里带 `audioWithLyricsOption.lyrics.sentences`（逐字时间），
     * 拿不到时退回 H5 `seo_track` 的 krc 文本。两条都不需要登录态。
     */
    private LyricTimeline sodaById(String trackId) throws Exception {
        String page = get("https://www.qishui.com/share/track?track_id=" + encode(trackId),
                "https://www.qishui.com/");
        LyricTimeline timeline = sodaPage(page);
        UniLog.d(LogTags.LYRIC, "lyric/soda", "id", trackId, "shareLen", page.length(),
                "shareSentences", timeline.lineCount());
        if (timeline.usable()) return timeline;
        String json = get("https://api.qishui.com/luna/h5/seo_track?track_id=" + encode(trackId),
                "https://www.qishui.com/");
        LyricTimeline krc = sodaKrc(json);
        UniLog.d(LogTags.LYRIC, "lyric/soda-krc", "id", trackId, "seoLen", json.length(),
                "lines", krc.lineCount());
        return krc;
    }

    /** 汽水的 krc：每行 `[start,dur]<off,dur,flag>字…`，逐字时间直接换算成增强时间轴。 */
    static LyricTimeline sodaKrc(String json) {
        if (json == null || json.isEmpty()) return LyricTimeline.EMPTY;
        try {
            JSONObject lyric = new JSONObject(json).optJSONObject("lyric");
            String content = lyric == null ? "" : lyric.optString("content", "");
            if (content.isEmpty()) return LyricTimeline.EMPTY;
            StringBuilder plain = new StringBuilder();
            StringBuilder enhanced = new StringBuilder();
            for (String row : content.split("\n")) {
                java.util.regex.Matcher head = KRC_LINE.matcher(row.trim());
                if (!head.find()) continue;
                long at = Long.parseLong(head.group(1));
                long until = at + Long.parseLong(head.group(2));
                String body = head.group(3);
                String text = KRC_TAG.matcher(body).replaceAll("").trim();
                if (text.isEmpty()) continue;
                plain.append(lrcLine(at, text));
                String words = krcWords(body, at, until);
                if (!words.isEmpty()) {
                    enhanced.append('[').append(at).append(',').append(Math.max(1, until - at))
                            .append(']').append(words).append('\n');
                }
            }
            if (plain.length() == 0) return LyricTimeline.EMPTY;
            return LyricTimeline.parse(plain.toString(), "", enhanced.toString(), "");
        } catch (Exception malformed) {
            return LyricTimeline.EMPTY;
        }
    }

    private static String krcWords(String body, long lineStart, long lineEnd) {
        java.util.regex.Matcher word = KRC_WORD.matcher(body);
        StringBuilder out = new StringBuilder();
        while (word.find()) {
            String text = word.group(4);
            if (text.trim().isEmpty()) continue;
            long at = lineStart + Long.parseLong(word.group(1));
            long duration = Math.max(60, Long.parseLong(word.group(2)));
            if (at >= lineEnd) break;
            out.append('(').append(at).append(',').append(duration).append(",0)").append(text);
        }
        return out.toString();
    }

    private static String sodaArtists(JSONArray artists) {
        if (artists == null) return "";
        StringBuilder out = new StringBuilder();
        for (int i = 0; i < artists.length(); i++) {
            JSONObject item = artists.optJSONObject(i);
            if (item == null) continue;
            if (out.length() > 0) out.append("/");
            out.append(item.optString("name", ""));
        }
        return out.toString();
    }

    /** Pull the sentence list out of a Soda share page and turn it into an enhanced timeline. */
    static LyricTimeline sodaPage(String html) {
        if (html == null || html.isEmpty()) return LyricTimeline.EMPTY;
        int marker = html.indexOf("_ROUTER_DATA");
        if (marker < 0) return LyricTimeline.EMPTY;
        int start = html.indexOf('{', marker);
        int end = matchingBrace(html, start);
        if (start < 0 || end <= start) return LyricTimeline.EMPTY;
        try {
            JSONObject root = new JSONObject(html.substring(start, end + 1));
            JSONObject loader = root.optJSONObject("loaderData");
            JSONObject page = loader == null ? null : loader.optJSONObject("track_page");
            JSONObject option = page == null ? null : page.optJSONObject("audioWithLyricsOption");
            JSONObject lyrics = option == null ? null : option.optJSONObject("lyrics");
            JSONArray sentences = lyrics == null ? null : lyrics.optJSONArray("sentences");
            if (sentences == null) return LyricTimeline.EMPTY;
            StringBuilder plain = new StringBuilder();
            StringBuilder translated = new StringBuilder();
            StringBuilder enhanced = new StringBuilder();
            for (int i = 0; i < sentences.length(); i++) {
                JSONObject sentence = sentences.optJSONObject(i);
                if (sentence == null) continue;
                long at = sentence.optLong("startMs", -1);
                if (at < 0) continue;
                long until = Math.max(at, sentence.optLong("endMs", at));
                String text = sentence.optString("text", "").trim();
                if (text.isEmpty()) text = sodaWordText(sentence.optJSONArray("words"));
                if (text.isEmpty()) continue;
                plain.append(lrcLine(at, text));
                String translation = sentence.optString("translation",
                        sentence.optString("translatedText", "")).trim();
                if (!translation.isEmpty()) translated.append(lrcLine(at, translation));
                String words = sodaWords(sentence.optJSONArray("words"), at, until);
                if (!words.isEmpty()) {
                    enhanced.append('[').append(at).append(',').append(until - at).append(']')
                            .append(words).append('\n');
                }
            }
            if (plain.length() == 0) return LyricTimeline.EMPTY;
            return LyricTimeline.parse(plain.toString(), translated.toString(),
                    enhanced.toString(), "");
        } catch (Exception malformed) {
            return LyricTimeline.EMPTY;
        }
    }

    private static String lrcLine(long at, String text) {
        return String.format(Locale.ROOT, "[%02d:%02d.%03d]%s%n", at / 60000,
                (at / 1000) % 60, at % 1000, text);
    }

    private static String sodaWordText(JSONArray words) {
        if (words == null) return "";
        StringBuilder out = new StringBuilder();
        for (int i = 0; i < words.length(); i++) {
            JSONObject word = words.optJSONObject(i);
            if (word != null) out.append(word.optString("text", ""));
        }
        return out.toString().trim();
    }

    private static String sodaWords(JSONArray words, long lineStart, long lineEnd) {
        if (words == null || words.length() == 0) return "";
        StringBuilder out = new StringBuilder();
        for (int i = 0; i < words.length(); i++) {
            JSONObject word = words.optJSONObject(i);
            if (word == null) continue;
            String text = word.optString("text", "");
            if (text.trim().isEmpty()) continue;
            long at = Math.max(lineStart, word.optLong("startMs", lineStart));
            long end = Math.max(at, Math.min(lineEnd, word.optLong("endMs", at)));
            if (end == at) end = at + 120;
            out.append('(').append(at).append(',').append(end - at).append(",0)").append(text);
        }
        return out.toString();
    }

    private static int matchingBrace(String text, int start) {
        if (start < 0) return -1;
        int depth = 0;
        boolean quoted = false;
        for (int i = start; i < text.length(); i++) {
            char c = text.charAt(i);
            if (quoted) {
                if (c == '\\') i++;
                else if (c == '"') quoted = false;
                continue;
            }
            if (c == '"') quoted = true;
            else if (c == '{') depth++;
            else if (c == '}') {
                depth--;
                if (depth == 0) return i;
            }
        }
        return -1;
    }

    // ---- migu (咪咕音乐) ----

    /**
     * Migu needs a signed request: {@code md5(text + SALT + timestamp)} plus the app headers.
     *
     * <p>Word timing lives in the {@code mrcUrl} container ({@link LyricCodecs#migu}); the
     * line-level {@code lrcUrl} is the fallback when a track has no MRC or the container is empty.
     */
    private LyricTimeline migu(String title, String artist, long durationMs, String words)
            throws Exception {
        String text = artist == null || artist.trim().isEmpty()
                ? title.trim() : title.trim() + " " + artist.trim();
        LyricTimeline byId = miguSearch(text, title, artist, durationMs);
        return byId;
    }

    private LyricTimeline miguSearch(String text, String title, String artist, long durationMs)
            throws Exception {
        long stamp = System.currentTimeMillis();
        String sign = miguSign(text, stamp);
        String switchJson = "{\"song\":1,\"album\":0,\"singer\":0,\"tagSong\":1,\"mv\":0,"
                + "\"bestShow\":1,\"songlist\":0,\"lyricSong\":0}";
        String address = "https://jadeite.migu.cn/music_search/v3/search/searchAll"
                + "?isCorrect=0&isCopyright=1&searchSwitch=" + encode(switchJson)
                + "&pageSize=20&text=" + encode(text) + "&pageNo=1&sort=0&sid=USS";
        String payload = signed(address, "https://app.c.nf.migu.cn/", stamp, sign);
        JSONObject root = new JSONObject(payload);
        if (!"000000".equals(root.optString("code"))) return LyricTimeline.EMPTY;
        JSONObject data = root.optJSONObject("songResultData");
        JSONArray groups = data == null ? null : data.optJSONArray("resultList");
        if (groups == null) return LyricTimeline.EMPTY;
        double best = 0;
        String contentId = "";
        String copyrightId = "";
        for (int i = 0; i < groups.length(); i++) {
            JSONArray rows = groups.optJSONArray(i);
            if (rows == null) continue;
            for (int j = 0; j < rows.length(); j++) {
                JSONObject song = rows.optJSONObject(j);
                if (song == null) continue;
                String id = song.optString("copyrightId", "").trim();
                String resource = song.optString("contentId", "").trim();
                if (id.isEmpty() && resource.isEmpty()) continue;
                double value = score(title, artist, song.optString("name", ""),
                        miguSinger(song.optJSONArray("singerList")),
                        durationMs, miguDuration(song.optLong("duration", 0)));
                if (value > best) {
                    best = value;
                    contentId = resource;
                    copyrightId = id;
                }
            }
        }
        if (best < ACCEPT || (contentId.isEmpty() && copyrightId.isEmpty())) {
            return LyricTimeline.EMPTY;
        }
        return miguLyric(contentId, copyrightId);
    }

    /**
     * 咪咕搜索结果里的 {@code duration} 是<b>秒</b>（例如 256），偶尔是毫秒。当成毫秒用会让时长比对
     * 差出三个数量级，{@link #score} 直接判 0 —— 结果就是“所有歌都查不到歌词”。
     */
    static long miguDuration(long raw) {
        return raw > 0 && raw < 20000 ? raw * 1000 : raw;
    }

    private static String miguSinger(JSONArray singers) {
        if (singers == null) return "";
        StringBuilder out = new StringBuilder();
        for (int i = 0; i < singers.length(); i++) {
            JSONObject item = singers.optJSONObject(i);
            if (item == null) continue;
            if (out.length() > 0) out.append("/");
            out.append(item.optString("name", ""));
        }
        return out.toString();
    }

    /**
     * {@code resourceinfo.do} 只认 {@code contentId}：用 {@code copyrightId} 查会拿到
     * {@code code=000000} 但 {@code resource=[]}，看起来像“这歌没歌词”。实测两个 id 都试一遍最稳。
     */
    private LyricTimeline miguLyric(String contentId, String copyrightId) throws Exception {
        String referer = "https://app.c.nf.migu.cn/";
        JSONObject first = miguResource(contentId, referer);
        if (first == null && !copyrightId.isEmpty() && !copyrightId.equals(contentId)) {
            first = miguResource(copyrightId, referer);
        }
        if (first == null) return LyricTimeline.EMPTY;
        String lrcUrl = first.optString("lrcUrl", "");
        String trcUrl = first.optString("trcUrl", "");
        String mrcUrl = first.optString("mrcUrl", "");
        // Word timing lives in the MRC container; it is the same lyric as lrcUrl, just decrypted.
        String enhanced = mrcUrl.isEmpty() ? ""
                : LyricCodecs.miguToEnhanced(LyricCodecs.mrcText(get(mrcUrl, referer)));
        String lrc = lrcUrl.isEmpty() ? "" : get(lrcUrl, referer);
        boolean hasLine = !lrc.trim().isEmpty();
        if (enhanced.isEmpty() && !hasLine) return LyricTimeline.EMPTY;
        String translation = trcUrl.isEmpty() ? "" : get(trcUrl, referer);
        return LyricTimeline.parse(lrc, translation, enhanced, "");
    }

    private JSONObject miguResource(String resourceId, String referer) throws Exception {
        if (resourceId == null || resourceId.isEmpty()) return null;
        String info = post(
                "https://c.musicapp.migu.cn/MIGUM2.0/v1.0/content/resourceinfo.do?resourceType=2",
                "resourceId=" + encode(resourceId), referer, null);
        JSONArray resources = new JSONObject(info).optJSONArray("resource");
        return resources == null || resources.length() == 0 ? null : resources.optJSONObject(0);
    }

    /** {@code md5(text + salt + timestamp)}, lower-case hex — Migu's own request signature. */
    static String miguSign(String text, long stamp) throws Exception {
        return md5Hex((text == null ? "" : text) + MIGU_SALT + stamp);
    }

    private static String signed(String address, String referer, long stamp, String sign)
            throws Exception {
        HttpURLConnection connection = null;
        try {
            connection = (HttpURLConnection) new URL(address).openConnection();
            connection.setConnectTimeout(CONNECT_MS);
            connection.setReadTimeout(READ_MS);
            connection.setRequestProperty("User-Agent", "Mozilla/5.0 (Linux; Android 9) UniLauncher");
            connection.setRequestProperty("Accept", "application/json,text/plain,*/*");
            connection.setRequestProperty("Referer", referer);
            connection.setRequestProperty("uiVersion", "A_music_3.6.1");
            connection.setRequestProperty("deviceId", MIGU_DEVICE);
            connection.setRequestProperty("timestamp", String.valueOf(stamp));
            connection.setRequestProperty("sign", sign);
            connection.setRequestProperty("channel", "0146921");
            if (connection.getResponseCode() / 100 != 2) return "";
            try (InputStream stream = connection.getInputStream()) {
                return new String(read(stream), StandardCharsets.UTF_8);
            }
        } finally {
            if (connection != null) connection.disconnect();
        }
    }

    private static final String MIGU_SALT =
            "6cdc72a439cef99a3418d2a78aa28c73yyapp2d16148780a1dcc7408e06336b98cfd50"
                    + "963B7AA0D21511ED807EE5846EC87D20";
    private static final String MIGU_DEVICE = "963B7AA0D21511ED807EE5846EC87D20";

    // ---- http ----

    private static String get(String address, String referer) throws Exception {
        return new String(body(address, referer), StandardCharsets.UTF_8);
    }

    private static String post(String address, String form, String referer, String cookie)
            throws Exception {
        return new String(exchange("POST", address, form, referer, cookie),
                StandardCharsets.UTF_8);
    }

    private static byte[] body(String address, String referer) throws Exception {
        return exchange("GET", address, null, referer, null);
    }

    private static byte[] exchange(String method, String address, String form, String referer,
                                   String cookie) throws Exception {
        HttpURLConnection connection = null;
        try {
            connection = (HttpURLConnection) new URL(address).openConnection();
            connection.setRequestMethod(method);
            connection.setConnectTimeout(CONNECT_MS);
            connection.setReadTimeout(READ_MS);
            connection.setInstanceFollowRedirects(true);
            connection.setRequestProperty("User-Agent",
                    "Mozilla/5.0 (Linux; Android 9) UniLauncher");
            connection.setRequestProperty("Accept", "application/json,text/plain,*/*");
            if (referer != null) {
                connection.setRequestProperty("Referer", referer);
                connection.setRequestProperty("Origin", referer);
            }
            if (cookie != null) connection.setRequestProperty("Cookie", cookie);
            if (form != null) {
                byte[] payload = form.getBytes(StandardCharsets.UTF_8);
                connection.setDoOutput(true);
                connection.setRequestProperty("Content-Type",
                        "application/x-www-form-urlencoded; charset=UTF-8");
                connection.setFixedLengthStreamingMode(payload.length);
                try (OutputStream out = connection.getOutputStream()) {
                    out.write(payload);
                }
            }
            if (connection.getResponseCode() / 100 != 2) return new byte[0];
            try (InputStream stream = connection.getInputStream()) {
                ByteArrayOutputStream buffer = new ByteArrayOutputStream();
                byte[] block = new byte[8192];
                int read;
                while ((read = stream.read(block)) != -1) {
                    if (buffer.size() + read > MAX_RESPONSE) return new byte[0];
                    buffer.write(block, 0, read);
                }
                return buffer.toByteArray();
            }
        } finally {
            if (connection != null) connection.disconnect();
        }
    }

    /** Read at most {@link #MAX_RESPONSE} bytes; anything longer is treated as a refusal. */
    private static byte[] read(InputStream stream) throws IOException {
        ByteArrayOutputStream buffer = new ByteArrayOutputStream();
        byte[] block = new byte[8192];
        int read;
        while ((read = stream.read(block)) != -1) {
            if (buffer.size() + read > MAX_RESPONSE) return new byte[0];
            buffer.write(block, 0, read);
        }
        return buffer.toByteArray();
    }

    private static String encode(String value) throws Exception {
        return URLEncoder.encode(value == null ? "" : value, StandardCharsets.UTF_8.name());
    }

    private static JSONObject first(JSONArray array) {
        return array == null || array.length() == 0 ? null : array.optJSONObject(0);
    }

    // ---- result ----

    public static final class Result {
        public static final Result EMPTY =
                new Result(LyricTimeline.EMPTY, "", "", false, 0);
        public final LyricTimeline timeline;
        public final String provider;
        public final String sourceLabel;
        public final boolean fromCache;
        /** {@link LyricTimeline#qualityScore()} of {@link #timeline}; 0 means "no document". */
        public final int score;

        Result(LyricTimeline timeline, String provider, String sourceLabel, boolean fromCache) {
            this(timeline, provider, sourceLabel, fromCache, 0);
        }

        Result(LyricTimeline timeline, String provider, String sourceLabel, boolean fromCache,
               int score) {
            this.timeline = timeline == null ? LyricTimeline.EMPTY : timeline;
            this.provider = provider == null ? "" : provider;
            this.sourceLabel = sourceLabel == null ? "" : sourceLabel;
            this.fromCache = fromCache;
            // Any usable document scores at least 1; qualityScore() alone returns 0 for a
            // plain line document (it only counts words, translations and romaji), and a plain
            // hit must never be mistaken for a miss.
            this.score = this.timeline.usable() ? Math.max(1, score + 1) : 0;
        }

        public boolean isEmpty() {
            return timeline.isEmpty();
        }

        /** A later catalogue answer is worth swapping in only when it really is richer. */
        public boolean betterThan(Result other) {
            if (other == null) return score > 0;
            if (score > other.score) return true;
            return score == other.score && score > 0 && other.timeline.isEmpty();
        }
    }

    /** Rebuilds a timeline from the cached JSON body. */
    static LyricTimeline fromJson(JSONObject payload) {
        if (payload == null) return LyricTimeline.EMPTY;
        JSONArray rows = payload.optJSONArray("lines");
        if (rows == null) return LyricTimeline.EMPTY;
        List<LyricTimeline.Line> lines = new ArrayList<>(rows.length());
        for (int i = 0; i < rows.length(); i++) {
            JSONObject row = rows.optJSONObject(i);
            if (row == null) continue;
            List<LyricTimeline.Word> words = new ArrayList<>();
            JSONArray raw = row.optJSONArray("w");
            if (raw != null) {
                for (int w = 0; w < raw.length(); w++) {
                    JSONArray item = raw.optJSONArray(w);
                    if (item == null || item.length() < 3) continue;
                    words.add(new LyricTimeline.Word(item.optLong(0), item.optLong(1),
                            item.optString(2, "")));
                }
            }
            lines.add(new LyricTimeline.Line(row.optLong("t"), row.optLong("d"),
                    row.optString("x", ""), row.optString("tr", ""), row.optString("ro", ""),
                    words));
        }
        return LyricTimeline.fromLines(lines);
    }
}