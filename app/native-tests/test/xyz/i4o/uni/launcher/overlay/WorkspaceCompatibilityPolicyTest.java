package xyz.i4o.uni.launcher.overlay;

public final class WorkspaceCompatibilityPolicyTest {
    private static void check(boolean value) { if (!value) throw new AssertionError(); }
    public static void main(String[] args) {
        String netease = "com.netease.cloudmusic.iot/com.netease.cloudmusic.activity.CloudMusicRNActivity";
        String qq = "com.tencent.qqmusiccar/.MainActivity";
        check(WorkspaceCompatibilityPolicy.shouldResize(true, new String[]{netease}));
        check(WorkspaceCompatibilityPolicy.shouldResize(true, new String[]{netease, netease}));
        check(!WorkspaceCompatibilityPolicy.shouldResize(false, new String[]{netease}));
        check(!WorkspaceCompatibilityPolicy.shouldResize(true, new String[]{netease, qq}));
        check(!WorkspaceCompatibilityPolicy.shouldResize(true, new String[]{qq}));
        check(!WorkspaceCompatibilityPolicy.shouldResize(true, new String[0]));
        check(!WorkspaceCompatibilityPolicy.shouldResize(true, null));
        check(!WorkspaceCompatibilityPolicy.shouldResize(true, new String[]{null}));
        System.out.println("WorkspaceCompatibilityPolicyTest passed");
    }
}
