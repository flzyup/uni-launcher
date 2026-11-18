package xyz.i4o.uni.launcher.overlay;
public final class ImmersiveWindowStateTest {
    static String window(String id,String pkg,int display,String flags,boolean visible){return "  Window #1 Window{"+id+" u0 "+pkg+"/.Main}:\n    mDisplayId="+display+" stackId=1\n    package="+pkg+" appop=NONE\n    mViewVisibility=0x0 mHaveFrame=true\n    mSystemUiVisibility=0x"+flags+"\n    isOnScreen="+visible+"\n";}
    static void check(boolean ok,String name){if(!ok)throw new AssertionError(name);}
    public static void main(String[]args){
        for(String flags:new String[]{"1006","f06","1706","2","802","1500","900","1000","800"})check(ImmersiveWindowState.parse(window("a","fixture",0,flags,true),"fixture").immersive,"nav/immersive flags "+flags);
        check(!ImmersiveWindowState.parse(window("a","fixture",0,"404",true),"fixture").immersive,"status-only fullscreen");
        check(!ImmersiveWindowState.parse(window("a","fixture",0,"500",true),"fixture").immersive,"stable fullscreen layout is not immersive");
        check(!ImmersiveWindowState.parse(window("a","fixture",0,"700",true),"fixture").immersive,"edge-to-edge layout is not immersive");
        check(!ImmersiveWindowState.parse(window("a","fixture",0,"0",true),"fixture").immersive,"global forced immersive is not app intent");
        check(!ImmersiveWindowState.parse(window("a","fixture",4,"1006",true),"fixture").known,"virtual display ignored");
        check(!ImmersiveWindowState.parse(window("a","fixture",0,"1006",false),"fixture").known,"hidden window ignored");
        String dump=window("a","fixture",0,"1006",true)+window("b","fixture",0,"0",true)+"mCurrentFocus=Window{b u0 fixture/.Main}\n";
        check(!ImmersiveWindowState.parse(dump,"fixture").immersive,"focused dialog restores nav");
        check(!ImmersiveWindowState.parse("Permission Denial: can't dump WindowManager", "fixture").known,"permission fail not normal");
        check(!ImmersiveWindowState.parse(window("a","fixture.other",0,"1006",true),"fixture").known,"exact package");
        System.out.println("ImmersiveWindowStateTest passed");
    }
}
