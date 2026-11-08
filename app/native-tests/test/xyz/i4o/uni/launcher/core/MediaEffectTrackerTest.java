package xyz.i4o.uni.launcher.core;

public final class MediaEffectTrackerTest {
  static void expect(boolean value,String label){if(!value)throw new AssertionError(label);}
  static final String PAUSED="2|50|Track A|180000";
  static final String PLAYING="3|50|Track A|180000";
  public static void main(String[] args){
    // 指纹只认能证明「真的动了」的东西：状态变了算，位置跨过两秒也算，标题或时长变了同样算。
    expect(MediaEffectTracker.fingerprint(3,4100,"T",180000).equals(MediaEffectTracker.fingerprint(3,5900,"T",180000)),"position is bucketed to two seconds");
    expect(!MediaEffectTracker.fingerprint(3,4100,"T",180000).equals(MediaEffectTracker.fingerprint(3,6100,"T",180000)),"two-second bucket boundary moves the fingerprint");
    expect(!MediaEffectTracker.fingerprint(2,0,"T",180000).equals(MediaEffectTracker.fingerprint(3,0,"T",180000)),"play state is part of the fingerprint");
    expect(!MediaEffectTracker.fingerprint(3,0,"A",180000).equals(MediaEffectTracker.fingerprint(3,0,"B",180000)),"title change is proof of effect");
    expect(MediaEffectTracker.fingerprint(3,-1,null,0).equals(MediaEffectTracker.fingerprint(3,-1,"",0)),"missing values never throw");

    MediaEffectTracker tracker=new MediaEffectTracker();
    // 什么都没送出时不能凭空判「没落地」，也不能误结账。
    expect(!tracker.armed(),"fresh tracker is idle");
    expect(!tracker.observe(PLAYING),"nothing armed, nothing to settle");
    expect(!tracker.shouldEscalate("playback",1000),"nothing armed, no escalation");
    expect(tracker.confirmed()==0&&tracker.missed()==0,"idle tracker keeps zero counters");

    // 播放器当场回写了状态：这条指令算落地，不该再升级通道。
    tracker.arm("playback",PAUSED,1000);
    expect(tracker.armed(),"armed after a command");
    expect(tracker.observe(PLAYING),"state change settles the command");
    expect(!tracker.armed(),"settled commands are no longer pending");
    expect(tracker.confirmed()==1&&tracker.missed()==0,"confirmed counted once");
    expect(!tracker.shouldEscalate("playback",5000),"a landed command never escalates later");

    // 超时没动：下一次同类按键改走注入。窗口内不动声色。
    tracker.arm("next",PAUSED,1000);
    expect(!tracker.shouldEscalate("next",1000+MediaEffectTracker.WINDOW_MS-1),"inside the window the ladder waits");
    expect(tracker.shouldEscalate("next",1000+MediaEffectTracker.WINDOW_MS),"past the window the ladder escalates");
    expect(tracker.missed()==1,"miss counted");
    expect(!tracker.armed(),"escalation clears the pending command");
    expect(!tracker.shouldEscalate("next",999999),"escalation only happens once per command");
    tracker.noteEscalated();
    expect(tracker.escalated()==1,"escalation recorded for diagnostics");

    // 不同动作分开记账：换歌没动不该把播放也判成坏的。
    tracker.arm("previous",PAUSED,2000);
    expect(!tracker.shouldEscalate("playback",9000),"another kind never settles this one");
    expect(tracker.armed(),"a mismatched kind leaves the command pending");
    expect(tracker.observe(PLAYING),"its own state change still settles it");

    // 同一条通道连按：以最后一次为准，只有一次结账。
    tracker.arm("playback",PAUSED,3000);
    tracker.arm("playback",PAUSED,3100);
    expect(!tracker.shouldEscalate("playback",3000+MediaEffectTracker.WINDOW_MS),"the latest command resets the window");
    expect(tracker.shouldEscalate("playback",3100+MediaEffectTracker.WINDOW_MS),"the latest command decides escalation");
    expect(tracker.missed()==2,"second miss counted");

    // 空动作/空指纹不记账，避免把内部同步当成用户指令。
    tracker.clear();
    tracker.arm("",PAUSED,4000);
    expect(!tracker.armed(),"empty action never arms");
    tracker.arm("playback",PAUSED,4000);
    tracker.clear();
    expect(!tracker.armed()&&tracker.action().isEmpty(),"clear drops the pending command");

    System.out.println("MediaEffectTrackerTest passed");
  }
}
