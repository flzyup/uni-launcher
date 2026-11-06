package xyz.i4o.uni.launcher.integration.lyrics;

import android.content.Context;
import android.content.SharedPreferences;

import java.util.HashMap;
import java.util.Locale;
import java.util.Map;

/**
 * How far the lyrics should be nudged to match what the listener actually hears.
 *
 * <p>No two audio paths have the same latency: Bluetooth adds 150–400 ms, a USB DAC a few
 * milliseconds, the car's own head unit somewhere in between, and some catalogues master the
 * track a fraction of a second early. One global offset plus a per-track correction covers both
 * the constant part and the stragglers; the value is applied to the playback clock before any
 * lyric consumer sees it, so the desktop card and the cast panel stay in step automatically.
 */
public final class LyricOffset {
    public static final int LIMIT_MS = 3000;
    private static final String PREFS = "lyric-offset";
    private static final String GLOBAL = "globalMs";
    private static final String TRACK_PREFIX = "track:";

    private static volatile int globalMs;
    private static volatile Map<String, Integer> perTrack = new HashMap<>();

    private LyricOffset() {
    }

    /** Positive shifts the lyrics later, negative earlier. Clamped to ±{@link #LIMIT_MS}. */
    public static int clamp(int value) {
        return Math.max(-LIMIT_MS, Math.min(LIMIT_MS, value));
    }

    /** Offset that applies to this recording: the global value plus any per-track correction. */
    public static int forTrack(String title, String artist) {
        int total = globalMs;
        Map<String, Integer> snapshot = perTrack;
        Integer track = snapshot.get(key(title, artist));
        if (track != null) total += track;
        return clamp(total);
    }

    public static int globalMs() {
        return globalMs;
    }

    /** Per-track correction only, without the global part; 0 when this track has none. */
    public static int trackMs(String title, String artist) {
        Map<String, Integer> snapshot = perTrack;
        Integer value = snapshot.get(key(title, artist));
        return value == null ? 0 : value;
    }

    /** Load both values from disk; safe to call repeatedly. */
    public static void load(Context context) {
        if (context == null) return;
        SharedPreferences prefs;
        try {
            prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE);
        } catch (RuntimeException unavailable) {
            return;
        }
        Map<String, Integer> tracks = new HashMap<>();
        for (Map.Entry<String, ?> entry : prefs.getAll().entrySet()) {
            if (!entry.getKey().startsWith(TRACK_PREFIX)) continue;
            Object value = entry.getValue();
            if (value instanceof Integer) {
                tracks.put(entry.getKey().substring(TRACK_PREFIX.length()),
                        clamp((Integer) value));
            }
        }
        perTrack = tracks;
        globalMs = clamp(prefs.getInt(GLOBAL, 0));
    }

    /** Persist a new global offset and, when {@code trackTitle} is given, that track's own. */
    public static void save(Context context, int global, String trackTitle, String trackArtist,
                            int track) {
        globalMs = clamp(global);
        if (context == null) return;
        SharedPreferences prefs;
        try {
            prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE);
        } catch (RuntimeException unavailable) {
            return;
        }
        SharedPreferences.Editor editor = prefs.edit().putInt(GLOBAL, globalMs);
        String trackKey = key(trackTitle, trackArtist);
        if (!trackKey.isEmpty()) {
            int value = clamp(track);
            Map<String, Integer> copy = new HashMap<>(perTrack);
            if (value == 0) {
                editor.remove(TRACK_PREFIX + trackKey);
                copy.remove(trackKey);
            } else {
                editor.putInt(TRACK_PREFIX + trackKey, value);
                copy.put(trackKey, value);
            }
            perTrack = copy;
        }
        editor.apply();
    }

    /** Apply an already-persisted pair without touching disk (used by the settings channel). */
    public static void configure(int global, String trackTitle, String trackArtist, int track) {
        globalMs = clamp(global);
        String trackKey = key(trackTitle, trackArtist);
        if (trackKey.isEmpty()) {
            perTrack = new HashMap<>();
            return;
        }
        Map<String, Integer> copy = new HashMap<>(perTrack);
        if (track == 0) copy.remove(trackKey);
        else copy.put(trackKey, clamp(track));
        perTrack = copy;
    }

    static String key(String title, String artist) {
        String name = title == null ? "" : title.trim().toLowerCase(Locale.ROOT);
        if (name.isEmpty()) return "";
        String who = artist == null ? "" : artist.trim().toLowerCase(Locale.ROOT);
        return name + "|" + who;
    }
}
