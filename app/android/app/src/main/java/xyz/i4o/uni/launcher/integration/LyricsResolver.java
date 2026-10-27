package xyz.i4o.uni.launcher.integration;

import android.os.Handler;
import android.os.Looper;
import org.json.JSONArray;
import org.json.JSONObject;
import java.io.ByteArrayOutputStream;
import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.net.HttpURLConnection;
import java.net.URL;
import java.net.URLEncoder;
import java.nio.charset.Charset;
import java.security.MessageDigest;
import java.util.Collections;
import java.util.HashMap;
import java.util.LinkedHashMap;
import java.util.Locale;
import java.util.Map;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.regex.Pattern;

/**
 * Most players keep their lyric text in their own window and publish none of it in
 * the MediaSession. Resolve the selected track from the session metadata instead:
 * title, artist and duration identify the recording, and the matched LRC document
 * is cached on disk. Text is bounded, main thread stays free of I/O, and a track
 * that matches nothing stays empty rather than showing a guess.
 */
public final class LyricsResolver {
    static final int MAX_LYRICS = 131072;
    private static final int MAX_RESPONSE = 262144;
    private static final int CONNECT_TIMEOUT_MS = 2500;
    private static final int READ_TIMEOUT_MS = 3000;
    private static final long MISS_TTL_MS = 30L * 60L * 1000L;
    private static final double ACCEPT = 2.0;
    private static final String USER_AGENT = "Mozilla/5.0 (Linux; Android 9) UniLauncher";
    private static final Charset UTF8 = Charset.forName("UTF-8");
    private static final Pattern JOINED = Pattern.compile("\\s*[-–—]\\s+");
    private static final Pattern TRACK = Pattern.compile("^\\s*(?:\\d{1,3}\\s*[-.)、]\\s*|\\d{1,3}\\s+)");
    private static final Pattern BRACKETS = Pattern.compile("[\\[（(【][^\\]）)】]*[\\]）)】]");
    private static final Pattern NOISE = Pattern.compile(
            "(?i)\\b(live|remix|dj|instrumental|acoustic|cover|remaster|version|edit)\\b"
                    + "|伴奏|纯音乐|翻唱|演唱会|官方版");

    private final File dir;
    private final Runnable changed;
    private final Handler main = new Handler(Looper.getMainLooper());
    private final ExecutorService worker = Executors.newSingleThreadExecutor(runnable -> {
        Thread thread = new Thread(runnable, "uni-lyrics-resolver");
        thread.setDaemon(true);
        return thread;
    });
    private final Map<String, String> memory =
            Collections.synchronizedMap(new LinkedHashMap<String, String>(8, 0.75f, true) {
                @Override protected boolean removeEldestEntry(Map.Entry<String, String> eldest) {
                    return size() > 16;
                }
            });
    private final Map<String, Long> misses = Collections.synchronizedMap(new HashMap<String, Long>());
    private String pending = "";
    private long generation;

    public LyricsResolver(File cacheDir, Runnable changed) {
        this.dir = cacheDir;
        this.changed = changed;
        if (dir != null && !dir.exists()) dir.mkdirs();
    }

    /** Already resolved text for this recording, or an empty string. Never blocks. */
    public String cached(String title, String artist, long durationMs) {
        String key = key(title, artist, durationMs);
        if (key.isEmpty()) return "";
        String text = memory.get(key);
        return text == null ? "" : text;
    }

    /** Resolve this recording once in the background; repeated calls are cheap. */
    public void request(String title, String artist, long durationMs) {
        final String key = key(title, artist, durationMs);
        if (key.isEmpty()) return;
        final long token;
        synchronized (this) {
            if (memory.containsKey(key) || missed(key) || key.equals(pending)) return;
            pending = key;
            token = ++generation;
        }
        try {
            worker.execute(() -> resolve(key, title, artist, durationMs, token));
        } catch (RuntimeException shuttingDown) {
            synchronized (this) { if (key.equals(pending)) pending = ""; }
        }
    }

    private void resolve(String key, String title, String artist, long durationMs, long token) {
        try {
            String text = load(key);
            if (text.isEmpty()) text = search(title, artist, durationMs);
            if (text.isEmpty()) {
                misses.put(key, System.currentTimeMillis());
                if (misses.size() > 64) misses.clear();
            } else {
                memory.put(key, text);
                store(key, text);
                if (token == generation && changed != null) main.post(changed);
            }
        } finally {
            synchronized (this) { if (key.equals(pending)) pending = ""; }
        }
    }

    private boolean missed(String key) {
        Long at = misses.get(key);
        return at != null && System.currentTimeMillis() - at < MISS_TTL_MS;
    }

    // ---- identity ----

    /** Title and artist as they should be queried: metadata may pack both into one field. */
    static String[] cleanQuery(String title, String artist) {
        String name = stripNoise(title);
        String singer = stripNoise(artist);
        if (singer.isEmpty()) {
            String[] parts = JOINED.split(name, 2);
            if (parts.length == 2 && !parts[0].isEmpty() && !parts[1].isEmpty()) {
                singer = parts[0].trim();
                name = parts[1].trim();
            }
        }
        String withoutIndex = TRACK.matcher(name).replaceFirst("");
        if (!withoutIndex.isEmpty()) name = withoutIndex;
        return new String[]{name, singer};
    }

    static String stripNoise(String value) {
        if (value == null) return "";
        String text = BRACKETS.matcher(value).replaceAll(" ");
        text = NOISE.matcher(text).replaceAll(" ");
        return text.replaceAll("\\s+", " ").trim();
    }

    static String normalize(String value) {
        if (value == null) return "";
        return letters(stripNoise(value));
    }

    /** Keeps bracketed aliases: "冯沁苑(买辣椒也用券)" also matches "买辣椒也用券". */
    static String normalizeFull(String value) {
        return value == null ? "" : letters(value);
    }

    private static String letters(String value) {
        String text = value.toLowerCase(Locale.ROOT);
        StringBuilder out = new StringBuilder(text.length());
        for (int i = 0; i < text.length(); i++) {
            char c = text.charAt(i);
            if (Character.isLetterOrDigit(c)) out.append(c);
        }
        return out.toString();
    }

    static String key(String title, String artist, long durationMs) {
        String[] query = cleanQuery(title, artist);
        String name = normalize(query[0]);
        if (name.isEmpty()) return "";
        long seconds = durationMs > 0 ? Math.round(durationMs / 1000.0) : 0;
        return name + "|" + normalize(query[1]) + "|" + seconds;
    }

    /** 0 means "different recording"; anything at or above ACCEPT is a match. */
    static double score(String title, String artist, String candidateTitle,
                        String candidateArtist, long durationMs, long candidateDurationMs) {
        String want = normalize(title);
        String got = normalize(candidateTitle);
        if (want.isEmpty() || got.isEmpty()) return 0;
        double value;
        if (got.equals(want)) value = 3;
        else if (got.contains(want) || want.contains(got)) value = 2;
        else return 0;
        String wantArtist = normalizeFull(artist);
        String gotArtist = normalizeFull(candidateArtist);
        if (!wantArtist.isEmpty() && !gotArtist.isEmpty()) {
            if (gotArtist.equals(wantArtist)) value += 1.5;
            else if (gotArtist.contains(wantArtist) || wantArtist.contains(gotArtist)) value += 0.8;
            else value -= 3; // A different singer with the same title is another recording.
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

    // ---- catalogue queries ----

    private String search(String title, String artist, long durationMs) {
        String[] query = cleanQuery(title, artist);
        if (query[0].isEmpty()) return "";
        String words = encode((query[0] + " " + query[1]).trim());
        try {
            long songId = pickNeteaseId(fetch("https://music.163.com/api/search/get/web?s=" + words
                    + "&type=1&limit=10&offset=0", "https://music.163.com/"), query[0], query[1], durationMs);
            if (songId > 0) {
                String text = neteaseLyrics(fetch("https://music.163.com/api/song/lyric?id=" + songId
                        + "&lv=-1&kv=-1&tv=-1", "https://music.163.com/"));
                if (!text.isEmpty()) return text;
            }
            String mid = pickQqMid(fetch("https://c.y.qq.com/soso/fcgi-bin/client_search_cp?p=1&n=10&w="
                    + words + "&format=json", "https://y.qq.com/"), query[0], query[1], durationMs);
            if (!mid.isEmpty()) {
                String text = qqLyrics(fetch("https://c.y.qq.com/lyric/fcgi-bin/fcg_query_lyric_new.fcg?songmid="
                        + encode(mid) + "&format=json&nobase64=1", "https://y.qq.com/"));
                if (!text.isEmpty()) return text;
            }
            String hash = pickKugouHash(fetch("https://songsearch.kugou.com/song_search_v2?keyword=" + words
                    + "&page=1&pagesize=10&userid=-1&clientver=&platform=WebFilter", "https://www.kugou.com/"),
                    query[0], query[1], durationMs);
            if (hash.isEmpty()) return "";
            String candidate = pickKugouCandidate(fetch("https://lyrics.kugou.com/search?ver=1&man=yes"
                    + "&client=pc&hash=" + encode(hash), "https://www.kugou.com/"));
            int cut = candidate.indexOf('\u0000');
            if (cut < 0) return "";
            return kugouLyrics(fetch("https://lyrics.kugou.com/download?ver=1&client=pc&id="
                    + encode(candidate.substring(0, cut)) + "&accesskey=" + encode(candidate.substring(cut + 1))
                    + "&fmt=lrc&charset=utf8", "https://www.kugou.com/"));
        } catch (Exception unreachableCatalogue) {
            return "";
        }
    }

    static long pickNeteaseId(String searchJson, String title, String artist, long durationMs) {
        try {
            JSONObject result = new JSONObject(searchJson).optJSONObject("result");
            JSONArray songs = result == null ? null : result.optJSONArray("songs");
            if (songs == null) return -1;
            double best = 0;
            long id = -1;
            for (int i = 0; i < songs.length(); i++) {
                JSONObject song = songs.optJSONObject(i);
                if (song == null) continue;
                JSONObject first = first(song.optJSONArray("artists"));
                double value = score(title, artist, song.optString("name"),
                        first == null ? "" : first.optString("name"), durationMs, song.optLong("duration", 0));
                if (value > best) {
                    best = value;
                    id = song.optLong("id", -1);
                }
            }
            return best >= ACCEPT ? id : -1;
        } catch (Exception malformed) {
            return -1;
        }
    }

    static String neteaseLyrics(String lyricJson) {
        try {
            JSONObject lrc = new JSONObject(lyricJson).optJSONObject("lrc");
            return lrc == null ? "" : limit(lrc.optString("lyric"));
        } catch (Exception malformed) {
            return "";
        }
    }

    static String pickQqMid(String searchJson, String title, String artist, long durationMs) {
        try {
            JSONObject song = new JSONObject(searchJson).optJSONObject("data");
            song = song == null ? null : song.optJSONObject("song");
            JSONArray list = song == null ? null : song.optJSONArray("list");
            if (list == null) return "";
            double best = 0;
            String mid = "";
            for (int i = 0; i < list.length(); i++) {
                JSONObject item = list.optJSONObject(i);
                if (item == null) continue;
                JSONObject first = first(item.optJSONArray("singer"));
                double value = score(title, artist, item.optString("songname"),
                        first == null ? "" : first.optString("name"), durationMs,
                        item.optLong("interval", 0) * 1000L);
                if (value > best) {
                    best = value;
                    mid = item.optString("songmid");
                }
            }
            return best >= ACCEPT ? mid : "";
        } catch (Exception malformed) {
            return "";
        }
    }

    static String qqLyrics(String lyricJson) {
        try {
            return limit(decodeEntities(new JSONObject(lyricJson).optString("lyric")));
        } catch (Exception malformed) {
            return "";
        }
    }

    static String pickKugouHash(String searchJson, String title, String artist, long durationMs) {
        try {
            JSONObject data = new JSONObject(searchJson).optJSONObject("data");
            JSONArray list = data == null ? null : data.optJSONArray("lists");
            if (list == null) return "";
            double best = 0;
            String hash = "";
            for (int i = 0; i < list.length(); i++) {
                JSONObject item = list.optJSONObject(i);
                if (item == null) continue;
                double value = score(title, artist, item.optString("SongName"), item.optString("SingerName"),
                        durationMs, item.optLong("Duration", 0) * 1000L);
                if (value > best) {
                    best = value;
                    hash = item.optString("FileHash");
                }
            }
            return best >= ACCEPT ? hash : "";
        } catch (Exception malformed) {
            return "";
        }
    }

    /** Returns {@code id\0accesskey} for the first candidate, or an empty string. */
    static String pickKugouCandidate(String candidateJson) {
        try {
            JSONArray candidates = new JSONObject(candidateJson).optJSONArray("candidates");
            JSONObject first = candidates == null ? null : candidates.optJSONObject(0);
            if (first == null) return "";
            String id = first.optString("id");
            String accesskey = first.optString("accesskey");
            return id.isEmpty() || accesskey.isEmpty() ? "" : id + "\u0000" + accesskey;
        } catch (Exception malformed) {
            return "";
        }
    }

    static String kugouLyrics(String downloadJson) {
        try {
            String content = new JSONObject(downloadJson).optString("content");
            if (content.isEmpty()) return "";
            byte[] raw = android.util.Base64.decode(content, android.util.Base64.DEFAULT);
            return limit(new String(raw, UTF8).replace("\ufeff", "").trim());
        } catch (Exception malformed) {
            return "";
        }
    }

    static String decodeEntities(String value) {
        if (value == null) return "";
        return value.replace("&#58;", ":").replace("&#46;", ".").replace("&#39;", "'")
                .replace("&apos;", "'").replace("&quot;", "\"").replace("&lt;", "<")
                .replace("&gt;", ">").replace("&amp;", "&");
    }

    private static JSONObject first(JSONArray array) {
        return array == null || array.length() == 0 ? null : array.optJSONObject(0);
    }

    private static String limit(String text) {
        if (text == null) return "";
        String trimmed = text.trim();
        return trimmed.length() > MAX_LYRICS ? "" : trimmed;
    }

    private static String encode(String value) {
        try {
            return URLEncoder.encode(value, "UTF-8");
        } catch (java.io.UnsupportedEncodingException impossible) {
            return "";
        }
    }

    private static String fetch(String address, String referer) {
        HttpURLConnection connection = null;
        try {
            connection = (HttpURLConnection) new URL(address).openConnection();
            connection.setConnectTimeout(CONNECT_TIMEOUT_MS);
            connection.setReadTimeout(READ_TIMEOUT_MS);
            connection.setInstanceFollowRedirects(true);
            connection.setRequestProperty("User-Agent", USER_AGENT);
            connection.setRequestProperty("Accept", "application/json,text/plain,*/*");
            if (referer != null) connection.setRequestProperty("Referer", referer);
            if (connection.getResponseCode() / 100 != 2) return "";
            InputStream stream = connection.getInputStream();
            try {
                ByteArrayOutputStream buffer = new ByteArrayOutputStream();
                byte[] block = new byte[8192];
                int read;
                while ((read = stream.read(block)) != -1) {
                    if (buffer.size() + read > MAX_RESPONSE) return "";
                    buffer.write(block, 0, read);
                }
                return new String(buffer.toByteArray(), UTF8);
            } finally {
                stream.close();
            }
        } catch (Exception offline) {
            return "";
        } finally {
            if (connection != null) connection.disconnect();
        }
    }

    // ---- disk cache ----

    String load(String key) {
        if (dir == null) return "";
        File file = file(key);
        if (!file.isFile()) return "";
        try (InputStream stream = new FileInputStream(file)) {
            ByteArrayOutputStream buffer = new ByteArrayOutputStream();
            byte[] block = new byte[8192];
            int read;
            while ((read = stream.read(block)) != -1) {
                if (buffer.size() + read > MAX_LYRICS) return "";
                buffer.write(block, 0, read);
            }
            return new String(buffer.toByteArray(), UTF8);
        } catch (IOException unreadable) {
            return "";
        }
    }

    void store(String key, String text) {
        if (dir == null || text == null || text.isEmpty() || text.length() > MAX_LYRICS) return;
        if (!dir.exists() && !dir.mkdirs()) return;
        try (FileOutputStream stream = new FileOutputStream(file(key))) {
            stream.write(text.getBytes(UTF8));
        } catch (IOException unwritable) {
            /* Read-only cache directory: the in-memory copy still serves this session. */
        }
    }

    private File file(String key) {
        return new File(dir, digest(key) + ".lrc");
    }

    private static String digest(String value) {
        try {
            byte[] hash = MessageDigest.getInstance("SHA-1").digest(value.getBytes(UTF8));
            StringBuilder hex = new StringBuilder(hash.length * 2);
            for (byte b : hash) hex.append(Character.forDigit((b >> 4) & 0xf, 16))
                    .append(Character.forDigit(b & 0xf, 16));
            return hex.toString();
        } catch (Exception unavailable) {
            return Integer.toHexString(value.hashCode());
        }
    }
}
