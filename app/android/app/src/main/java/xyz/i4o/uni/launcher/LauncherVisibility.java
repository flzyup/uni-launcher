package xyz.i4o.uni.launcher;

/** Cheap, non-blocking answer to "is anything we render actually on screen?".
 *
 * The launcher is a HOME app, so the only cheap evidence is whether our activity
 * is resumed. Pollers use it to back off instead of waking the OEM car bus at
 * full rate while the user is in another app. Deliberately a plain volatile
 * field: it must be readable from worker threads without touching the main
 * looper.
 */
public final class LauncherVisibility {
    private static volatile boolean visible=true;
    private LauncherVisibility(){}
    public static void set(boolean value){visible=value;}
    public static boolean visible(){return visible;}
}
