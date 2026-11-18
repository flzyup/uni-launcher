package xyz.i4o.uni.launcher.overlay;

/** Workspace selection follows the top app's actual window request, not a
 * package allowlist. Task arrays are ordered bottom to top by ActivityManager. */
public final class WorkspaceCompatibilityPolicy {
    private WorkspaceCompatibilityPolicy() {}
    public static boolean isImmersiveTask(String[] tasks,String immersivePackage) {
        if(tasks==null||tasks.length==0||immersivePackage==null||immersivePackage.isEmpty())return false;
        String top=tasks[tasks.length-1];
        return top!=null&&top.startsWith(immersivePackage+"/");
    }
}
