package xyz.i4o.uni.launcher;

import xyz.i4o.uni.launcher.log.LogTags;
import xyz.i4o.uni.launcher.log.UniLog;

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
    public static void set(boolean value){
        // 只在状态变化时记一条：可见性被高频轮询，逐次落盘会淹没日志文件。
        boolean changed=visible!=value;
        visible=value;
        if(changed)UniLog.i(LogTags.APP,"桌面可见性变化","visible",value);
    }
    public static boolean visible(){return visible;}
}
