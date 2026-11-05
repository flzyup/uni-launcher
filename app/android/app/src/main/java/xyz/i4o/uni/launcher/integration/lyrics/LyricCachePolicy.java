package xyz.i4o.uni.launcher.integration.lyrics;

import android.content.Context;
import android.content.SharedPreferences;

import java.io.File;
import java.util.Arrays;
import java.util.Comparator;
import java.util.Locale;

/**
 * What happens to cached lyric documents over time.
 *
 * <p>A lyric document is 4–40 KB and a heavy listener accumulates thousands of them, so the
 * cache needs a policy rather than an accident. Three are offered, because the trade-off is
 * genuinely personal:
 *
 * <ul>
 *   <li>{@link #FOREVER} — never delete; a lyric is fetched once, ever. Best for a fixed
 *       library and a car with a big data plan.</li>
 *   <li>{@link #DAYS30} — drop anything not read for a month (the default). Keeps the cache
 *       warm for the tracks in rotation without growing without bound.</li>
 *   <li>{@link #CAPACITY} — keep the most recently written documents under a size ceiling.</li>
 * </ul>
 *
 * <p>The sweep runs on a worker thread at startup, never on the main thread, and a directory
 * that cannot be trimmed is left alone: a cache is an optimisation, not a source of truth.
 */
public final class LyricCachePolicy {
    public static final String FOREVER = "forever";
    public static final String DAYS30 = "30d";
    public static final String CAPACITY = "capacity";
    public static final String DEFAULT = DAYS30;

    private static final String PREFS = "lyric-cache";
    private static final String POLICY = "policy";
    private static final String LIMIT_MB = "limitMb";
    private static final long DAY_MS = 24L * 60 * 60 * 1000;
    private static final int MAX_UNREAD_DAYS = 30;
    private static final int DEFAULT_LIMIT_MB = 24;

    private LyricCachePolicy() {
    }

    public static String policy(Context context) {
        return normalise(read(context).getString(POLICY, DEFAULT));
    }

    public static int limitMb(Context context) {
        return Math.max(1, Math.min(512, read(context).getInt(LIMIT_MB, DEFAULT_LIMIT_MB)));
    }

    public static void save(Context context, String policy, int limitMb) {
        if (context == null) return;
        read(context).edit()
                .putString(POLICY, normalise(policy))
                .putInt(LIMIT_MB, Math.max(1, Math.min(512, limitMb)))
                .apply();
    }

    public static String normalise(String policy) {
        if (policy == null) return DEFAULT;
        String value = policy.trim().toLowerCase(Locale.ROOT);
        if (FOREVER.equals(value) || DAYS30.equals(value) || CAPACITY.equals(value)) return value;
        return DEFAULT;
    }

    public static String label(String policy) {
        String value = normalise(policy);
        if (FOREVER.equals(value)) return "永久保留";
        if (CAPACITY.equals(value)) return "按容量";
        return "30 天未用即清理";
    }

    /** Directories the lyric pipeline writes to, in the order they were added. */
    public static File[] directories(File filesDir) {
        if (filesDir == null) return new File[0];
        return new File[]{
                new File(filesDir, "media-lyrics"),
                new File(filesDir, "lyric-timeline"),
        };
    }

    /** Apply the policy to every lyric directory. Safe to call from any thread. */
    public static int sweep(Context context, long now) {
        if (context == null) return 0;
        String policy = policy(context);
        File[] dirs = directories(filesDir(context));
        int removed = 0;
        for (File dir : dirs) removed += sweep(dir, policy, limitMb(context), now);
        return removed;
    }

    /**
     * @return how many files were removed; 0 for {@link #FOREVER} and for a missing directory
     */
    public static int sweep(File dir, String policy, int limitMb, long now) {
        String mode = normalise(policy);
        if (FOREVER.equals(mode)) return 0;
        File[] files = dir == null ? null : dir.listFiles();
        if (files == null || files.length == 0) return 0;
        int removed = 0;
        if (CAPACITY.equals(mode)) {
            removed += trimToBytes(files, Math.max(1, limitMb) * 1024L * 1024L);
        } else {
            long cutoff = now - MAX_UNREAD_DAYS * DAY_MS;
            for (File file : files) {
                if (!file.isFile()) continue;
                // lastModified is refreshed on every cache hit, so it is "last used".
                if (file.lastModified() >= cutoff) continue;
                if (delete(file)) removed++;
            }
        }
        return removed;
    }

    /** Delete oldest-written files until the directory fits under {@code limitBytes}. */
    static int trimToBytes(File[] files, long limitBytes) {
        long total = 0;
        for (File file : files) {
            if (file.isFile()) total += file.length();
        }
        if (total <= limitBytes) return 0;
        File[] ordered = files.clone();
        Arrays.sort(ordered, new Comparator<File>() {
            @Override
            public int compare(File left, File right) {
                long a = left.lastModified();
                long b = right.lastModified();
                if (a == b) return 0;
                return a < b ? -1 : 1;   // oldest first
            }
        });
        int removed = 0;
        for (File file : ordered) {
            if (total <= limitBytes) break;
            long size = file.length();
            if (!file.isFile()) continue;
            if (delete(file)) {
                total -= size;
                removed++;
            }
        }
        return removed;
    }

    private static boolean delete(File file) {
        try {
            return file.delete();
        } catch (RuntimeException refused) {
            return false;
        }
    }


    private static SharedPreferences read(Context context) {
        return context.getSharedPreferences(PREFS, Context.MODE_PRIVATE);
    }

    private static File filesDir(Context context) {
        try {
            return context.getFilesDir();
        } catch (RuntimeException unavailable) {
            return null;
        }
    }
}
