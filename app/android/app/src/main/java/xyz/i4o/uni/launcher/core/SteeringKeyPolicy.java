package xyz.i4o.uni.launcher.core;

/**
 * 方控与中控按键到媒体动作的映射。
 *
 * 领克 05（IP753）的方控**不走** AOSP 的 87/88/85：方向盘按键被系统
 * EcarxInputDispatcherService 派发成 ECARX 自定义码（2000xx / 2100xx 段），
 * 中控面板用 1100xx 段。按键码来源与接口见
 * car-reports/carcontrol/STEERING_KEYS.md。
 *
 * 同一个键可能同时从两条通道到达（原车输入回调 + 原车媒体中心客户端回调，
 * 或者车机直接把媒体键派给当前窗口），所以这里按动作分组折叠重复，
 * 保证一次按键只让桌面媒体控制走一步。
 */
public final class SteeringKeyPolicy {
    /** 方向盘「播放/暂停」（KEYCODE_R_MEDIA_PLAY_PAUSE）。 */
    public static final int R_MEDIA_PLAY_PAUSE=200085;
    /** 方向盘「下一首」（KEYCODE_R_MEDIA_NEXT）。 */
    public static final int R_MEDIA_NEXT=200087;
    /** 方向盘「上一首」（KEYCODE_R_MEDIA_PREVIOUS）。 */
    public static final int R_MEDIA_PREVIOUS=200088;
    /** 方向盘「快进/下一个」（KEYCODE_R_SEEK_NEXT）。 */
    public static final int R_SEEK_NEXT=210005;
    /** AOSP 标准媒体键：方控不走，但车机注入、蓝牙 AVRCP 和原车媒体中心会用。 */
    public static final int MEDIA_PLAY_PAUSE=85, MEDIA_NEXT=87, MEDIA_PREVIOUS=88, MEDIA_PLAY=126, MEDIA_PAUSE=127;
    /**
     * 中控实体 HOME。
     *
     * <p>领克 05（IP753，192.168.22.198）那颗带指纹的圆形键不走内核输入设备
     * （{@code getevent} 一条都没有），而是由 VHAL 直接注入标准 HOME：
     * {@code VHAL.InputHandler injectKeyCode(0, 3, 0)} / {@code (1, 3, 0)}。
     * 注入是真的发生了，但事件到不了窗口 —— 被原车输入派发层截走（OEM 桌面
     * 那条路），所以要在原车输入通道里把它申请回来。
     */
    public static final int KEY_HOME=3;
    /** ECARX 输入服务里的 HOME 私有码（300001），和中控面板那颗键一起出现。 */
    public static final int PANEL_HOME=300001;
    /** 300001 旁边那颗私有键（实车上和 HOME 一起出现），先只计数不映射，等实车核对。 */
    public static final int PANEL_AUX=300002;

    private SteeringKeyPolicy(){}

    /** 需要向原车输入通道申请监听的键。 */
    public static int[] interceptKeys(){
        // 申请范围放宽：领克 05 的方控「上一首/下一首」在这台车上不一定派发 200087/200088，
        // 实测按了连一条都没有；原车对未知码是「能给的给、不能给的不给」，所以整批申请
        // 再多也能拿到交集，真正收到的是什么码看日志 granted= 那一行。
        int[] base=new int[]{R_MEDIA_PLAY_PAUSE,R_MEDIA_NEXT,R_MEDIA_PREVIOUS,R_SEEK_NEXT,
            MEDIA_PLAY_PAUSE,MEDIA_PLAY,MEDIA_PAUSE,MEDIA_NEXT,MEDIA_PREVIOUS,
            KEY_HOME,PANEL_HOME,PANEL_AUX};
        int[][] ranges={{200000,200064},{210000,210016},{300000,300064},{110000,110016}};
        int extra=0;
        for(int[] r:ranges)extra+=r[1]-r[0];
        int[] all=new int[base.length+extra];
        int n=0;
        for(int code:base)all[n++]=code;
        for(int[] r:ranges)for(int code=r[0];code<r[1];code++)all[n++]=code;
        return all;
    }

    /** 只申请媒体键：整批（含 HOME）被拒时的退路，保证方控不受牵连。 */
    public static int[] mediaKeys(){
        return new int[]{R_MEDIA_PLAY_PAUSE,R_MEDIA_NEXT,R_MEDIA_PREVIOUS,R_SEEK_NEXT,
            MEDIA_PLAY_PAUSE,MEDIA_PLAY,MEDIA_PAUSE,MEDIA_NEXT,MEDIA_PREVIOUS};
    }

    /**
     * 按键码对应的媒体动作，空串表示这个键不归桌面媒体控制。
     *
     * 中控的 110003（KEYCODE_MEDIA）按反编译语义是「媒体源」而不是播放/暂停，
     * 因此默认不接管：它的实际派发要等实车按下后在
     * {@code dumpsys --uni-state} 的 media.steeringKeys.seen 里核对，确认后再加一行。
     */
    public static String action(int keyCode){
        switch(keyCode){
            case R_MEDIA_PLAY_PAUSE: case MEDIA_PLAY_PAUSE: return "toggle-play";
            case MEDIA_PLAY: return "play";
            case MEDIA_PAUSE: return "pause";
            case R_MEDIA_NEXT: case R_SEEK_NEXT: case MEDIA_NEXT: return "next";
            case R_MEDIA_PREVIOUS: case MEDIA_PREVIOUS: return "previous";
            case PANEL_HOME: case KEY_HOME: return "home";
            default: return "";
        }
    }

    /** 这个动作是不是「回桌面」，由运行时直接交给 HOME 处理，不进媒体适配层。 */
    public static boolean isHome(String action){return "home".equals(action);}

    /**
     * 动作对应的 AOSP 媒体键码，供按键注入与专用广播旁路使用。
     *
     * <p>注入必须用标准码：原车码 200085/200087 只有在原车输入通道里才被认识，
     * {@code injectInputEvent} 与 {@code input keyevent} 送下去的是 AOSP 事件。
     *
     * @return -1 表示这个动作没有对应按键（例如 seek 只能走传输控制）
     */
    public static int keyCode(String action){
        switch(action==null?"":action){
            case "next":return MEDIA_NEXT;
            case "previous":return MEDIA_PREVIOUS;
            case "play":return MEDIA_PLAY;
            case "pause":return MEDIA_PAUSE;
            case "toggle-play":return MEDIA_PLAY_PAUSE;
            default:return -1;
        }
    }

    /** 动作分组：播放/暂停是一类，换歌各是一类。 */
    public static String kind(String action){
        if("play".equals(action)||"pause".equals(action)||"toggle-play".equals(action))return "playback";
        if("next".equals(action))return "next";
        if("previous".equals(action))return "previous";
        return "";
    }

    /** 折叠窗口：播放/暂停留足两条通道的到达差，换歌只折叠几乎同时的那一次。 */
    public static long windowMs(String kind){
        return "playback".equals(kind)?450:150;
    }

    /**
     * 通道内不折叠（同一个键连续按两次是用户真的按了两次），
     * 只有**不同通道**在同一分组、窗口内先后到达时才折叠。
     */
    public static final class Debounce {
        private long lastAt=Long.MIN_VALUE/2;
        private String lastKind="", lastChannel="";

        public synchronized boolean accept(String channel,String action,long nowMs){
            String kind=kind(action);
            if(kind.isEmpty())return false;
            String from=channel==null?"":channel;
            if(kind.equals(lastKind)&&!from.equals(lastChannel)&&nowMs-lastAt<windowMs(kind))return false;
            lastKind=kind;lastChannel=from;lastAt=nowMs;
            return true;
        }

        public synchronized void reset(){
            lastAt=Long.MIN_VALUE/2;lastKind="";lastChannel="";
        }
    }
}
