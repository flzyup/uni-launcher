package xyz.i4o.uni.launcher.overlay;

/** Limit the Android 9 immersive-layout workaround to a single-app stack. */
public final class WorkspaceCompatibilityPolicy {
    private static final String TARGET = "com.netease.cloudmusic.iot/";
    private WorkspaceCompatibilityPolicy() {}
    public static boolean shouldResize(boolean visible, String[] tasks) {
        if (!visible || tasks == null || tasks.length == 0) return false;
        for (String task : tasks) if (task == null || !task.startsWith(TARGET)) return false;
        return true;
    }
}
