package xyz.i4o.uni.launcher.overlay;
public final class WorkspaceCompatibilityPolicyTest {
    private static void check(boolean value){if(!value)throw new AssertionError();}
    public static void main(String[]args){
        String[] stack={"app.one/.Main", "any.app/.Video"};
        check(WorkspaceCompatibilityPolicy.isImmersiveTask(stack,"any.app"));
        check(!WorkspaceCompatibilityPolicy.isImmersiveTask(stack,"app.one"));
        check(!WorkspaceCompatibilityPolicy.isImmersiveTask(stack,"any"));
        check(!WorkspaceCompatibilityPolicy.isImmersiveTask(stack,""));
        check(!WorkspaceCompatibilityPolicy.isImmersiveTask(null,"any.app"));
        check(!WorkspaceCompatibilityPolicy.isImmersiveTask(new String[0],"any.app"));
        check(!WorkspaceCompatibilityPolicy.isImmersiveTask(new String[]{null},"any.app"));
        System.out.println("WorkspaceCompatibilityPolicyTest passed (generic immersive workspace)");
    }
}
