package xyz.i4o.uni.launcher.core;

public final class SteeringKeyPolicyTest {
  static void expect(boolean value,String label){if(!value)throw new AssertionError(label);}
  public static void main(String[] args){
    // 方控（R 段）与中控：只有媒体动作归桌面，音量和媒体源不接管。
    expect("toggle-play".equals(SteeringKeyPolicy.action(200085)),"wheel play/pause");
    expect("next".equals(SteeringKeyPolicy.action(200087)),"wheel next");
    expect("previous".equals(SteeringKeyPolicy.action(200088)),"wheel previous");
    expect("next".equals(SteeringKeyPolicy.action(210005)),"wheel seek next maps to next");
    expect("".equals(SteeringKeyPolicy.action(110003)),"center media/source key stays with the OEM");
    expect("".equals(SteeringKeyPolicy.action(210003)),"wheel media source stays with the OEM");
    expect("".equals(SteeringKeyPolicy.action(200024)),"volume up is not a transport key");
    expect("".equals(SteeringKeyPolicy.action(210009)),"knob tune stays with the OEM");
    // AOSP 标准码：方控不走，但系统注入/AVRCP 会用。
    expect("toggle-play".equals(SteeringKeyPolicy.action(85)),"aosp play/pause");
    expect("play".equals(SteeringKeyPolicy.action(126)),"aosp play keeps direction");
    expect("pause".equals(SteeringKeyPolicy.action(127)),"aosp pause keeps direction");
    expect("next".equals(SteeringKeyPolicy.action(87)),"aosp next");
    expect("previous".equals(SteeringKeyPolicy.action(88)),"aosp previous");
    int[] keys=SteeringKeyPolicy.interceptKeys();
    boolean hasWheel=false,hasVolume=false;
    for(int code:keys){if(code==200085)hasWheel=true;if(code==200024||code==210007)hasVolume=true;}
    expect(hasWheel,"wheel play/pause is requested");
    expect(!hasVolume,"volume keys are never intercepted");
    // 动作分组与折叠窗口。
    expect("playback".equals(SteeringKeyPolicy.kind("toggle-play")),"toggle groups as playback");
    expect("playback".equals(SteeringKeyPolicy.kind("pause")),"pause groups as playback");
    expect("next".equals(SteeringKeyPolicy.kind("next")),"next groups alone");
    expect("".equals(SteeringKeyPolicy.kind("")),"unknown action has no group");
    SteeringKeyPolicy.Debounce d=new SteeringKeyPolicy.Debounce();
    expect(d.accept("input","toggle-play",1000),"first key always passes");
    expect(!d.accept("oem","play",1200),"second channel within the window is folded");
    expect(d.accept("input","toggle-play",1300),"same channel repeats are real presses");
    expect(d.accept("oem","pause",1900),"other channel after the window passes");
    expect(d.accept("input","next",1950),"next uses its own group");
    expect(!d.accept("oem","next",2000),"squeezed duplicate next is folded");
    expect(d.accept("input","next",2200),"next past its shorter window passes");
    expect(!d.accept("input","",3000),"unmapped action never dispatches");
    d.reset();
    expect(d.accept("oem","toggle-play",3200),"reset clears the fold");
    System.out.println("SteeringKeyPolicyTest passed");
  }
}
