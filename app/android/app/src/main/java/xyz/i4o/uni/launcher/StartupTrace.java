package xyz.i4o.uni.launcher;

import android.os.SystemClock;

/** Wall-clock split of a HOME cold start, logged once per process.
 *
 * Every cost on this head unit has to be attributed before it can be removed.
 * Zygote fork and engine creation belong to the platform; the runtime build and
 * the first frame are ours. All stamps use uptimeMillis, the same clock
 * `am start -W` reports TotalTime against, so the numbers line up.
 *
 * Read with: adb logcat -s UNI-Startup
 */
public final class StartupTrace {
    private static final long processStart = android.os.Process.getStartUptimeMillis();
    private static long onCreate, runtime, window;
    private StartupTrace(){}

    public static long mark(){ return SystemClock.uptimeMillis(); }

    /** Called with the stamp taken on onCreate entry. */
    public static void began(long at){ onCreate=at; }

    /** Called once the launcher runtime exists (icon and design work included). */
    public static void runtime(long at){ runtime=at; }

    /** Called once the window and its content view are in place. */
    public static void window(long at){ window=at; }

    public static void firstDraw(){
        long now=SystemClock.uptimeMillis();
        android.util.Log.i("UNI-Startup","host total="+(now-processStart)
            +" onCreate="+since(onCreate)+" runtime="+since(runtime)
            +" window="+since(window)+" firstDraw="+since(now));
    }

    private static long since(long at){ return at==0?-1:at-processStart; }
}
