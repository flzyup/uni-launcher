package xyz.i4o.uni.launcher.overlay;

import xyz.i4o.uni.launcher.log.LogTags;
import xyz.i4o.uni.launcher.log.UniLog;

/** Limit the Android 9 immersive-layout workaround to a single-app stack. */
public final class WorkspaceCompatibilityPolicy {
    private static final String TARGET = "com.netease.cloudmusic.iot/";
    private WorkspaceCompatibilityPolicy() {}
    public static boolean shouldResize(boolean visible, String[] tasks) {
        if (!visible || tasks == null || tasks.length == 0) return false;
        for (String task : tasks) if (task == null || !task.startsWith(TARGET)) return false;
        // 这个判断每秒被问一次，只有放行时才留痕：那就是唯一值得追的特例。
        UniLog.d(LogTags.SYS, "兼容模式放行任务缩放", "target", TARGET);
        return true;
    }
}
