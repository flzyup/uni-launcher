package xyz.i4o.uni.launcher.core;

/**
 * 「传输控制说成功、播放器没动」的判定。
 *
 * <p>车机播放器有一类通病：{@code ACTION_PLAY} 声明了，{@code play()} 也没抛，
 * 声音就是不来（会话刚建还没 ready、播放器把自己的会话撤了只剩一个壳、酷狗车机版那种
 * 只认自己广播的）。传输控制没有回执，唯一的证据是播放状态自己变了没有。
 *
 * <p>所以每条指令出手时留一份指纹，下一个播放状态回调或下一次同类按键来结账：
 * 指纹变了算落地；过了 {@link #WINDOW_MS} 还是原样，下一次同类按键就不再走同一条通道，
 * 直接换执行器（按键注入），不吃第二遍白按。
 *
 * <p>不排队、不挂定时器：结账只发生在状态回调和下一次按键上，空闲时不占线程、不碰主线程
 * Handler，也就不会和「播放拉起重试」抢同一个回调槽。
 */
public final class MediaEffectTracker{
    /** 播放器从收到传输控制到回写状态的时间上限，超过就当这一路没落地。 */
    public static final long WINDOW_MS=900;
    private String action="",fingerprint="";
    private long armedAt;
    private boolean armed;
    private int confirmed,missed,escalated;

    /** 指纹只取能证明「真的动了」的东西：播放状态、两秒粒度位置、曲目、时长。 */
    public static String fingerprint(int state,long positionMs,String title,long durationMs){
        return state+"|"+(positionMs<0?0:positionMs/2000)+"|"+(title==null?"":title)+"|"+durationMs;
    }

    /** 指令刚送出去：记住它该证明什么。同一条通道连按会覆盖上一把（以最后一次为准）。 */
    public void arm(String action,String fingerprint,long nowMs){
        if(action==null||action.isEmpty())return;
        this.action=action;
        this.fingerprint=fingerprint==null?"":fingerprint;
        this.armedAt=nowMs;
        this.armed=true;
    }

    public void clear(){
        armed=false;action="";fingerprint="";
    }

    /**
     * 播放状态回调进来。指纹变了说明这条指令确实落地了。
     *
     * @return 这次回调结掉了一条还没结果的指令
     */
    public boolean observe(String currentFingerprint){
        if(!armed)return false;
        if(fingerprint.equals(currentFingerprint))return false;
        clear();
        confirmed++;
        return true;
    }

    /**
     * 下一次同类按键开口前问一句：上一把到底动没动。
     *
     * @return true 表示上一把超时没动，这次别再走同一条通道
     */
    public boolean shouldEscalate(String action,long nowMs){
        if(!armed||action==null||!action.equals(this.action))return false;
        if(nowMs-armedAt<WINDOW_MS)return false;
        clear();
        missed++;
        return true;
    }

    /** 换了执行器再记账：升级过就按升级后的结果走，不再等原通道自己好。 */
    public void noteEscalated(){
        escalated++;
    }

    public boolean armed(){return armed;}
    public String action(){return action;}
    public int confirmed(){return confirmed;}
    public int missed(){return missed;}
    public int escalated(){return escalated;}
}
