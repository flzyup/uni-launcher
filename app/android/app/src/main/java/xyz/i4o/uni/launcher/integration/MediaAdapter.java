package xyz.i4o.uni.launcher.integration;

import android.content.ComponentName;
import android.content.Context;
import android.content.Intent;
import android.media.MediaMetadata;
import android.media.session.MediaController;
import android.media.session.MediaSession;
import android.media.session.MediaSessionManager;
import android.media.session.PlaybackState;
import android.os.Handler;
import android.os.Bundle;
import android.os.SystemClock;
import org.json.JSONObject;
import org.json.JSONArray;
import xyz.i4o.uni.launcher.core.MediaSourcePolicy;
import xyz.i4o.uni.launcher.core.MediaTextRetention;
import xyz.i4o.uni.launcher.log.LogTags;
import xyz.i4o.uni.launcher.log.UniLog;
import xyz.i4o.uni.launcher.core.SteeringKeyPolicy;
import xyz.i4o.uni.launcher.core.MediaEffectTracker;
import xyz.i4o.uni.launcher.integration.lyrics.LyricCast;
import xyz.i4o.uni.launcher.integration.lyrics.LyricCatalog;
import java.util.HashMap;
import java.util.Map;
import xyz.i4o.uni.launcher.integration.lyrics.LyricOffset;
import xyz.i4o.uni.launcher.integration.lyrics.LyricTimelineProvider;
import xyz.i4o.uni.launcher.integration.lyrics.EmbeddedLyricReader;
import android.graphics.Bitmap;
import android.util.Base64;
import java.util.LinkedHashMap;
import java.io.ByteArrayOutputStream;
import java.io.File;
import java.util.List;
import java.util.ArrayList;

/** Standard MediaSession is explicitly labeled; OEM source parity still needs car verification. */
public final class MediaAdapter {
    private final Context context;
    private final MediaSessionManager manager;
    private final MediaSession steeringSession;
    private final SteeringKeyBridge steeringKeys;
    private final SteeringKeyPolicy.Debounce steeringDedupe=new SteeringKeyPolicy.Debounce();
    /** 仪表（DIM）自带媒体控件那条链路：只写状态/时长，按键从仪表收回来。 */
    private final DimMediaBridge dim;
    /** 传输控制「说成功但没动」的记账：下一次同类按键直接换执行器。 */
    private final MediaEffectTracker effects=new MediaEffectTracker();
    /** 设置页「仪表媒体通道」的开关，默认关：写仪表是可选项，先看着仪表再打开。 */
    private volatile boolean dimClusterEnabled;
    /** 桌面没在观察会话时到达的按键数，只做诊断。 */
    private int idleDrops;
    /** 设置页「方向盘控制音乐」的开关，默认开。关掉后不接原车输入、也不处理任何方控键。 */
    private volatile boolean steeringEnabled=true;
    /** 设置页「仪表同步」的开关，默认开。关掉后不再向原车媒体中心注册/上报。 */
    private volatile boolean instrumentEnabled=true;
    private final SteeringKeyInjector injector;
    private final KugouKeyRelay kugou;
    /** 注入下去的键会从原车输入回调或标准会话再回来一次：这个窗口内同一动作只认第一次。 */
    private static final long INJECT_ECHO_MS=250;
    private long lastInjectAt=Long.MIN_VALUE/2;
    private String lastInjectKind="";
    private final OfficialMediaBridge officialBridge;
    private final ComponentName listener;
    private final Runnable changed;
    private final NeteaseMediaAdapter netease;
    private final LyricsResolver lyrics;
 private final LyricTimelineProvider timeline;
    private final Handler handler=new Handler();
    private MediaController controller;
    private boolean authorized;
    /** Whether the session listener is currently registered; see {@link #started()}. */
    private boolean started;
    private String preferred="auto";
    private String lastSource="";
    private final android.content.SharedPreferences lastTrackPrefs;
    private String savedTrackKey="";
    private long lastTrackWriteAt;
    private final MediaTextRetention retainedTrack=new MediaTextRetention();
    private Bitmap lastCover;
    private String coverData="";
    private boolean artworkDirty=true;
    private boolean steeringMetaDirty=true;
    private JSONArray activeSources=new JSONArray();
    private final List<MediaController> observed=new ArrayList<>();
    /** The package of the session that is currently selected (logging only). */
    private String loggedSource="";
    /** Whether the mirrored steering session is active (logging only). */
    private boolean steeringActive;
    /** The lyric source last reported (logging only): the snapshot runs on
     *  every tick, so the change is logged once and not per tick. */
    private String lastLyricSource="";
    private String lastLyricTrack="";
    /** Resolved once per source package: an OEM player can publish a session
     *  without a launcher entry, and then the UI has no app row to read a label
     *  from. Cached so a position tick never costs an IPC. */
    private String labelPackage,labelValue="";
    /** A transport callback can be accepted then ignored by a background player.
     * Remember only a play request; pause cancels the wake check. */
    private static final long PLAY_CONFIRM_MS=800;
    /** A wheel source selection must not launch an app; retry its live session. */
    private static final long ONLINE_SWITCH_RETRY_MS=400;
    private static final int ONLINE_SWITCH_RETRIES=10;
    private Object pendingPlayToken;
    private String pendingPlaySource="";
    private int pendingPlayStage;
    private final Runnable playFallback=new Runnable(){
        public void run(){
            Object token=pendingPlayToken;if(token==null)return;
            PlaybackState state=controller==null?null:controller.getPlaybackState();
            boolean sameSession=controller!=null&&token.equals(controller.getSessionToken())
                    &&pendingPlaySource.equals(controller.getPackageName());
            if(sameSession&&state!=null&&state.getState()==PlaybackState.STATE_PLAYING){clearPlayFallback();return;}
            // Buffering/connecting is genuine progress from a live receiver.
            if(sameSession&&state!=null&&(state.getState()==6||state.getState()==8)){
                handler.postDelayed(this,PLAY_CONFIRM_MS);return;
            }
            if(pendingPlayStage==0){
                // 第一层补偿：重发一次 play，再走系统媒体键。
                //
                // 这一步以前是 launchSource()，等于「点了播放没立刻响，就把播放器
                // 整个拉到桌面前面」—— 导航看不见了，用户只是想续播。媒体键落到
                // 的是 MediaButtonReceiver（广播/服务），播放器自己决定要不要露脸，
                // 桌面这边不会被抢走。
                pendingPlayStage=1;
                if(sameSession)sendPlay(controller);
                relayKey("play");
                handler.postDelayed(this,PLAY_CONFIRM_MS);return;
            }
            clearPlayFallback();
        }
    };
    private MediaController onlineSwitchController;
    private String onlineSwitchSource="";
    private int onlineSwitchAttempts;
    private final Runnable onlineSwitchRetry=new Runnable(){
        public void run(){
            MediaController target=onlineSwitchController;
            if(target==null)return;
            PlaybackState state=target.getPlaybackState();
            if(state!=null&&(state.getState()==PlaybackState.STATE_PLAYING||state.getState()==6||state.getState()==8)){
                if(state.getState()==PlaybackState.STATE_PLAYING)clearOnlineSwitch(true);
                else handler.postDelayed(this,ONLINE_SWITCH_RETRY_MS);
                return;
            }
            if(onlineSwitchAttempts++>=ONLINE_SWITCH_RETRIES){clearOnlineSwitch(false);return;}
            dispatchOnlinePlay(target);
            handler.postDelayed(this,ONLINE_SWITCH_RETRY_MS);
        }
    };
    private String sourceLabel(String pkg){
        if(pkg==null)return "";
        if(pkg.equals(labelPackage))return labelValue;
        labelPackage=pkg;labelValue="";
        try{
            android.content.pm.PackageManager pm=context.getPackageManager();
            CharSequence label=pm.getApplicationLabel(pm.getApplicationInfo(pkg,0));
            if(label!=null)labelValue=label.toString();
        }catch(Exception ignored){
            // The lookup happens once per package, so the raw failure is
            // worth keeping: the app row would show no label at all.
            UniLog.w(LogTags.MEDIA,"播放器名称取不到","package",pkg,"error",ignored.getClass().getSimpleName(),"reason",String.valueOf(ignored.getMessage()));
        }
        return labelValue;
    }
    public void setPreferredPackage(String value){preferred=value==null||value.isEmpty()?"auto":value;start();}
    private final MediaController.Callback callback=new MediaController.Callback(){
        public void onMetadataChanged(MediaMetadata m){
            artworkDirty=true;steeringMetaDirty=true;
            // 只有「换了一首」或「这首的封面才到」才让原车那边重新取图：metadata 回调很频繁，
            // 每次都失效会不停写新文件、原车跟着反复下载同一张图。
            String key=coverKey(m);
            boolean hasArt=m!=null&&(m.containsKey(MediaMetadata.METADATA_KEY_ALBUM_ART)||m.containsKey(MediaMetadata.METADATA_KEY_ART));
            if(!key.equals(metaKey)||hasArt!=metaArt){metaKey=key;metaArt=hasArt;OfficialMediaBridge.invalidateArtwork();}
            noteMetadata(m);choose();changed.run();
        }
        // choose() already synchronizes the selected source, including switches.
        public void onPlaybackStateChanged(PlaybackState s){
            // 传输控制到底有没有落地，唯一的证据就在这条回调里。
            if(effects.observe(fingerprint()))UniLog.i(LogTags.MEDIA,"传输控制已落地","source",controller==null?"":controller.getPackageName());
            choose();changed.run();
        }
        public void onExtrasChanged(Bundle extras){syncSteeringSession();changed.run();}
        public void onSessionDestroyed(){
            try{select(manager.getActiveSessions(listener));}catch(SecurityException e){authorized=false;select(null);}
            changed.run();
        }
    };
    private final MediaSessionManager.OnActiveSessionsChangedListener sessions=new MediaSessionManager.OnActiveSessionsChangedListener(){
        public void onActiveSessionsChanged(List<MediaController> list){select(list);changed.run();}
    };
    public MediaAdapter(Context context,Runnable changed){
        this.context=context;this.changed=changed;netease=new NeteaseMediaAdapter(changed);manager=(MediaSessionManager)context.getSystemService(Context.MEDIA_SESSION_SERVICE);
        lastTrackPrefs=context.getSharedPreferences("uni_last_track",Context.MODE_PRIVATE);
        lastSource=lastTrackPrefs.getString("source", "");
        lyrics=new LyricsResolver(new File(context.getFilesDir(),"media-lyrics"),changed);
        // The catalogue answers on a worker thread a second or two later. Until now nothing
        // re-ran the snapshot on arrival, so the card kept the empty state it painted while the
        // request was in flight until some unrelated playback event happened — the "song is
        // playing but no lyrics ever appear" report. Hop to the main thread and republish.
        timeline=new LyricTimelineProvider(new File(context.getFilesDir(),"lyric-timeline"),
                ()->handler.post(changed));
        listener=new ComponentName(context,MediaAccessService.class);
        officialBridge=new OfficialMediaBridge(context,(action,source)->{
            if("select-online".equals(action))return selectOnline(source);
            if("select-bluetooth".equals(action))return selectBluetooth();
            if(controller==null||!source.equals(controller.getPackageName()))return false;
            // 原车媒体中心的传输回调也算一条外部通道：和方控输入回调折叠，
            // 同一次按键不会既被输入通道切一次、又被媒体中心切回去。
            if("play".equals(action)||"pause".equals(action)||"next".equals(action)||"previous".equals(action)){
                onSteeringAction("oem",action);return true;
            }
            return command(action);
        },changed);
        String savedOnline=lastTrackPrefs.getString("lastOnlineSource", "");
        if(!isOnlinePlayer(savedOnline)&&isOnlinePlayer(lastSource))savedOnline=lastSource;
        officialBridge.setOnlineSource(isOnlinePlayer(savedOnline)?savedOnline:"");
        steeringSession=new MediaSession(context,"UNI steering media bridge");
        steeringSession.setFlags(MediaSession.FLAG_HANDLES_MEDIA_BUTTONS|MediaSession.FLAG_HANDLES_TRANSPORT_CONTROLS);
        steeringSession.setCallback(new MediaSession.Callback(){
            // 标准会话回调同样走外部通道：系统媒体键路由和原车派发的是同一次按键。
            @Override public void onPlay(){onSteeringAction("session","play");}
            @Override public void onPause(){onSteeringAction("session","pause");}
            @Override public void onSkipToNext(){onSteeringAction("session","next");}
            @Override public void onSkipToPrevious(){onSteeringAction("session","previous");}
            @Override public void onSeekTo(long position){command("seek",position);}
        },handler);
        steeringKeys=new SteeringKeyBridge(context,(action,keyCode)->{
            // 中控那颗圆键（带指纹）由 VHAL 注入 KEYCODE_HOME，被原车输入派发层截住；
            // 我们把它申请回来了，所以「回桌面」在这里落地，不进媒体动作。
            if(SteeringKeyPolicy.isHome(action)){xyz.i4o.uni.launcher.MainActivity.requestHomeFirst("input");return;}
            onSteeringAction("input",action);
        });
        dim=new DimMediaBridge(context,new DimMediaBridge.Sink(){
            @Override public void onDimKey(String action){
                // 仪表上按的播放键和方控是同一件事：走同一条外部通道，靠通道折叠去重。
                onSteeringAction("dim",action);
            }
            @Override public void onDimSource(int sourceType){
                // 仪表把音源切成在线音乐：把焦点要回当前播放器，仪表和桌面还是同一首。
                if(sourceType==DimMediaBridge.SOURCE_ONLINE&&controller!=null)officialBridge.claimCurrent();
                changed.run();
            }
        });
        injector=new SteeringKeyInjector(context);
        kugou=new KugouKeyRelay(context);
    }
    public void start(){
        stop();
        UniLog.enter(LogTags.MEDIA,"media/session","action","bind");
        started=true;
        try{manager.addOnActiveSessionsChangedListener(sessions,listener,handler);select(manager.getActiveSessions(listener));authorized=true;
            UniLog.done(LogTags.MEDIA,"media/session","authorized",true,"sessions",observed.size());}
        catch(SecurityException e){authorized=false;select(null);
            UniLog.fail(LogTags.MEDIA,"media/session","reason","media-access-not-authorized","error",e.getClass().getSimpleName());}
        officialBridge.start();
        steeringDedupe.reset();
        effects.clear();
        UniLog.d(LogTags.MEDIA,"媒体适配启动","steering",steeringEnabled,"dim",dimClusterEnabled);
        // 方控开关关着时不接原车输入通道：方向盘键原样留给原车，桌面完全不参与。
        if(steeringEnabled)steeringKeys.start();
        if(dimClusterEnabled)dim.start();
    }
    /** 设置页「方向盘控制」：默认开。关掉即反注册原车输入，之后到达的键一律不处理。 */
    public void setSteeringEnabled(boolean enabled){
        steeringEnabled=enabled;
        if(!enabled)steeringKeys.stop();
        else if(started)steeringKeys.start();
    }
    /**
     * 设置页「仪表同步」：默认开。关掉即反注册并解绑原车媒体中心，仪表跟回原车播放器，
     * 桌面不再往上写曲目、封面和进度；重新打开按当前音源重新注册。
     */
    public void setInstrumentEnabled(boolean enabled){
        instrumentEnabled=enabled;
        officialBridge.setEnabled(enabled);
    }
    /**
     * 设置页「仪表媒体通道」：默认关。
     *
     * <p>关掉时一次都不往仪表写，仪表继续跟原车播放器；打开后接上
     * {@code DimInteraction.getMediaInteraction()}，写播放状态与时长，并把仪表上按的
     * 播放键收回桌面（这条路和原车媒体中心是两条链路，所以单独一个开关）。
     */
    public void setDimClusterEnabled(boolean enabled){
        dimClusterEnabled=enabled;
        if(enabled)dim.start();
        else dim.stop();
    }

    /**
     * True while the adapter is observing sessions.
     *
     * <p>Publishing a snapshot is not the same thing as being subscribed: a surface that paints
     * outside the launcher window (the lyric cast on the cluster display) has to know whether
     * it needs to start the adapter itself, because the launcher only starts it while a Flutter
     * listener exists.
     */
    public boolean started(){
        return started;
    }
    private void select(List<MediaController> list){
        for(MediaController c:observed)c.unregisterCallback(callback);
        observed.clear();
        activeSources=new JSONArray();
        if(list!=null)for(MediaController c:list)if(!context.getPackageName().equals(c.getPackageName()))observed.add(c);
        preferControllable();
        UniLog.i(LogTags.MEDIA,"媒体会话列表已刷新","sessions",observed.size());
        choose();
        // Observe every session: a player's state can change without the
        // active-session list changing, including paused -> playing.
        for(MediaController c:observed)c.registerCallback(callback,handler);
    }

    /**
     * 同一个播放器可能同时挂多个会话，而系统给的顺序不保证哪个能控制。
     *
     * <p>LX Music 就是现成的例子：`TrackPlayer` 声明了 PLAY / PAUSE / SKIP
     * （actions=311），旁边还挂着一个 `LXMusicMediaSession`（actions=0）的空壳。
     * 两个会话都是 STATE_PLAYING、都有元数据，{@link MediaSourcePolicy#selectSessions}
     * 在这两项上分不出差别，于是可能选中空壳 —— 底栏的上一首 / 暂停 / 下一首
     * 全变灰，可播放器本身完全可控。
     *
     * <p>只在**同一个包内部**把可控的会话往前挪一格，跨包的优先级（哪个应用
     * 在播就用哪个）一点不动。
     */
    private void preferControllable(){
        for(int i=0;i<observed.size();i++){
            MediaController first=observed.get(i);
            if(controllable(first))continue;
            for(int j=i+1;j<observed.size();j++){
                MediaController other=observed.get(j);
                if(other.getPackageName().equals(first.getPackageName())&&controllable(other)){
                    observed.set(j,first);observed.set(i,other);break;
                }
            }
        }
    }

    /** 会话是否声明了我们画在底栏上的任何一个传输动作；actions=0 的空壳返回 false。 */
    private static boolean controllable(MediaController c){
        PlaybackState p=c.getPlaybackState();
        long actions=p==null?0:p.getActions();
        return (actions&(PlaybackState.ACTION_PLAY|PlaybackState.ACTION_PAUSE|PlaybackState.ACTION_PLAY_PAUSE
                |PlaybackState.ACTION_SKIP_TO_NEXT|PlaybackState.ACTION_SKIP_TO_PREVIOUS))!=0;
    }
    private void choose(){
            UniLog.d(LogTags.MEDIA,"选择音源","observed",observed.size());
            activeSources=new JSONArray();
            String[] packages=new String[observed.size()];boolean[] playing=new boolean[observed.size()];
            boolean[] metadata=new boolean[observed.size()],current=new boolean[observed.size()];
            for(int i=0;i<observed.size();i++){
                MediaController c=observed.get(i);PlaybackState p=c.getPlaybackState();
                packages[i]=c.getPackageName();playing[i]=p!=null&&p.getState()==PlaybackState.STATE_PLAYING;
                MediaMetadata m=c.getMetadata();String title=m==null?null:m.getString(MediaMetadata.METADATA_KEY_TITLE);
                metadata[i]=title!=null&&!title.trim().isEmpty();
                current[i]=controller!=null&&controller.getSessionToken().equals(c.getSessionToken());
                try{activeSources.put(new JSONObject().put("package",packages[i]).put("playing",playing[i]));}catch(Exception ignored){}
            }
            int selected=MediaSourcePolicy.selectSessions(preferred,lastSource,packages,playing,metadata,current);
            MediaController next=selected>=0?observed.get(selected):null;
            MediaController switching=onlineSwitchController;
            if(switching!=null){
                MediaController live=null;
                for(MediaController candidate:observed)if(candidate.getSessionToken().equals(switching.getSessionToken())){live=candidate;break;}
                if(live==null){clearOnlineSwitch(false);}
                else{
                    next=live;
                    PlaybackState state=live.getPlaybackState();
                    if(state!=null&&state.getState()==PlaybackState.STATE_PLAYING)clearOnlineSwitch(true);
                }
            }
            if(!isOnlinePlayer(lastTrackPrefs.getString("lastOnlineSource", ""))){
                String only="";
                for(String pkg:packages)if(isOnlinePlayer(pkg)){
                    if(only.isEmpty())only=pkg;
                    else if(!only.equals(pkg)){only="";break;}
                }
                if(!only.isEmpty()){
                    lastTrackPrefs.edit().putString("lastOnlineSource",only).apply();
                    officialBridge.setOnlineSource(only);
                }
            }
            if(next!=null)lastSource=next.getPackageName();
if(next!=null&&isOnlinePlayer(next.getPackageName())){
                String source=next.getPackageName();
                if(!source.equals(lastTrackPrefs.getString("lastOnlineSource", "")))lastTrackPrefs.edit().putString("lastOnlineSource",source).apply();
                officialBridge.setOnlineSource(source);
            }
            noteSource(next==null?"":next.getPackageName(),observed.size());
            if(next==null||controller==null||!next.getSessionToken().equals(controller.getSessionToken())){lastCover=null;lastCoverKey="";coverData="";artworkDirty=true;steeringMetaDirty=true;}
            controller=next;
            netease.setController(controller);
            syncSteeringSession();
    }
    /** Logs the selected session only when it changes: choose() also runs on
     *  every playback state change of the observed sessions. */
    private void noteSource(String source,int sessions){
        if(source.equals(loggedSource))return;
        String previous=loggedSource;
        loggedSource=source;
        if(source.isEmpty())UniLog.i(LogTags.MEDIA,"媒体会话已断开","previous",previous);
        else UniLog.i(LogTags.MEDIA,"媒体会话已连接","source",source,"previous",previous,"sessions",sessions);
    }
    /** Logs the metadata of the session that reported it. */
    private void noteMetadata(MediaMetadata m){
        String title=m==null?"":nullToEmpty(m.getString(MediaMetadata.METADATA_KEY_TITLE));
        String artist=m==null?"":nullToEmpty(m.getString(MediaMetadata.METADATA_KEY_ARTIST));
        boolean artwork=m!=null&&(m.getBitmap(MediaMetadata.METADATA_KEY_ALBUM_ART)!=null||m.getBitmap(MediaMetadata.METADATA_KEY_ART)!=null);
        UniLog.done(LogTags.MEDIA,"media/metadata","title",title,"artist",artist,"hasArtwork",artwork,
            "mediaId",m==null?"":nullToEmpty(m.getString(MediaMetadata.METADATA_KEY_MEDIA_ID)));
        // 有的播放器（汽水这类）会把歌词塞进 metadata 的私有键里。键名不可枚举就先打出来，
        // 命中 lyric/lrc 的连内容一起看，省得为每个播放器单独猜。
        if(m!=null){
            StringBuilder keys=new StringBuilder();
            for(String key:m.keySet()){
                if(keys.length()>0)keys.append(',');
                keys.append(key);
                String lower=key.toLowerCase(java.util.Locale.ROOT);
                if(lower.contains("lyric")||lower.contains("lrc")){
                    Object value=m.getText(key);
                    if(value==null)value=m.getString(key);
                    if(value!=null){
                        String text=String.valueOf(value);
                        UniLog.i(LogTags.MEDIA,"会话里带歌词","key",key,"chars",text.length(),
                            "head",text.substring(0,Math.min(60,text.length())).replace('\n','|'));
                    }
                }
            }
            UniLog.d(LogTags.MEDIA,"会话 metadata 键","keys",keys.toString(),"size",m.size());
        }
    }
    private static String nullToEmpty(String value){return value==null?"":value;}
    /** 外部按键/回调要求的播放方向：状态已经对了就不发命令，免得把「播放」执行成「暂停」。 */
    private boolean setPlaying(boolean play){
        PlaybackState state=controller==null?null:controller.getPlaybackState();
        boolean playing=state!=null&&state.getState()==PlaybackState.STATE_PLAYING;
        if(play==playing)return false;
        return command("toggle-play");
    }
    /**
     * 方控、中控按键、原车媒体中心回调、系统媒体键路由的唯一入口。
     * 一次按键可能从两条通道先后到达（输入回调 + 媒体中心 onPlay），这里按动作分组
     * 折叠成一步，然后立刻刷新桌面媒体控制的状态。
     */
    public boolean onSteeringAction(String channel,String action){
        // 方控到底从哪个通道来的、被识别成什么动作：区分「按键」和「滑动」只能靠这条。
        UniLog.d(LogTags.MEDIA,"方控动作","channel",channel,"action",action);
        if(!steeringEnabled)return false;
        // 桌面这一轮没在观察会话（Flutter 侧一个监听都没有）：按键只计数不执行。
        // 原车本来就会把这颗键路由给播放器，我们再动一次就成了双重动作；
        // 而按键通道本身是常驻的，不跟着会话生命周期反注册，所以这里必须挡住。
        if(!started){idleDrops++;return false;}
        if(injectedEcho(action))return true;
        if(!steeringDedupe.accept(channel,action,SystemClock.elapsedRealtime()))return false;
        boolean accepted="play".equals(action)||"pause".equals(action)?setPlaying("play".equals(action)):command(action);
        changed.run();
        return accepted;
    }
    /** 我们自己刚注入的键正在从别的通道回来：这一步已经做过了。 */
    private boolean injectedEcho(String action){
        String kind=SteeringKeyPolicy.kind(action);
        return !kind.isEmpty()&&kind.equals(lastInjectKind)&&SystemClock.elapsedRealtime()-lastInjectAt<INJECT_ECHO_MS;
    }
    private void markInjected(String action){
        lastInjectKind=SteeringKeyPolicy.kind(action);
        lastInjectAt=SystemClock.elapsedRealtime();
    }
    private static boolean isOnlinePlayer(String source){
        return NeteaseMediaAdapter.PACKAGE.equals(source)||"com.tencent.qqmusiccar".equals(source)||"com.tencent.qqmusic".equals(source);
    }
    private boolean selectOnline(String source){
        if(!isOnlinePlayer(source))return false;
        clearOnlineSwitch(false);
        for(MediaController candidate:observed){
            if(!source.equals(candidate.getPackageName()))continue;
            onlineSwitchController=candidate;onlineSwitchSource=source;onlineSwitchAttempts=0;
            controller=candidate;netease.setController(candidate);lastSource=source;
            officialBridge.update(candidate);officialBridge.claimCurrent();
            dispatchOnlinePlay(candidate);
            handler.removeCallbacks(onlineSwitchRetry);
            handler.postDelayed(onlineSwitchRetry,ONLINE_SWITCH_RETRY_MS);
            changed.run();
            return true;
        }
        return false;
    }
    private boolean selectBluetooth(){
        for(MediaController candidate:observed){
            if(!"com.android.bluetooth".equals(candidate.getPackageName()))continue;
            MediaController previous=controller;
            if(previous!=null&&isOnlinePlayer(previous.getPackageName()))pauseController(previous);
            clearOnlineSwitch(false);
            onlineSwitchController=candidate;onlineSwitchSource=candidate.getPackageName();onlineSwitchAttempts=0;
            controller=candidate;netease.setController(candidate);lastSource=candidate.getPackageName();
            officialBridge.update(candidate);officialBridge.claimCurrent();
            dispatchOnlinePlay(candidate);
            handler.removeCallbacks(onlineSwitchRetry);
            handler.postDelayed(onlineSwitchRetry,ONLINE_SWITCH_RETRY_MS);
            changed.run();
            return true;
        }
        return false;
    }
    private void pauseController(MediaController target){
        try{
            target.getTransportControls().pause();
        }catch(RuntimeException ignored){}
    }
    private void dispatchOnlinePlay(MediaController target){
        try{
            if(NeteaseMediaAdapter.supports(target)){
                NeteaseMediaAdapter adapter=new NeteaseMediaAdapter(()->{});
                adapter.setController(target);adapter.command("play");adapter.stop();
            }else{
                PlaybackState state=target.getPlaybackState();
                if(state==null||(state.getActions()&(PlaybackState.ACTION_PLAY|PlaybackState.ACTION_PLAY_PAUSE))==0)return;
                target.getTransportControls().play();
            }
        }catch(RuntimeException ignored){}
    }
    private void clearOnlineSwitch(boolean keepSelection){
        handler.removeCallbacks(onlineSwitchRetry);
        onlineSwitchController=null;onlineSwitchSource="";onlineSwitchAttempts=0;
        if(!keepSelection)choose();
    }
    /** Mirror the selected source into a standard active MediaSession. The
     * steering-wheel dispatcher can now target transport callbacks and the
     * instrument cluster can consume the same title/artist/playback state. */
    /** 当前曲目的歌词文本，供原车 getLyric/getLyricContent 使用。 */
    private volatile String clusterLyric="";
    /** 缓存封面属于哪一首：标题|歌手|mediaId，换了歌就不再复用。 */
    private String lastCoverKey="";
    /** 上一次 metadata 的曲目键 / 是否带封面，用来判断该不该让原车重新取图。 */
    private String metaKey="";
    private boolean metaArt;
    private static String coverKey(MediaMetadata m){
        if(m==null)return "";
        CharSequence title=m.getText(MediaMetadata.METADATA_KEY_TITLE);
        CharSequence artist=m.getText(MediaMetadata.METADATA_KEY_ARTIST);
        String id=m.getString(MediaMetadata.METADATA_KEY_MEDIA_ID);
        return (title==null?"":title)+"\u0000"+(artist==null?"":artist)+"\u0000"+(id==null?"":id);
    }
    private void syncSteeringSession(){
        // 原车 IMusicPlaybackInfo.getArtwork() 要 URI：把当前封面（没有就用占位图）
        // 交给桥去落盘授权，原车来问的时候才拿得到图。
        OfficialMediaBridge.artworkSource(()->{
            MediaController current=controller;
            MediaMetadata meta=current==null?null:current.getMetadata();
            if(meta==null)return stubCover();
            String key=coverKey(meta);
            Bitmap fromMeta=meta.getBitmap(MediaMetadata.METADATA_KEY_ALBUM_ART);
            if(fromMeta==null)fromMeta=meta.getBitmap(MediaMetadata.METADATA_KEY_ART);
            if(fromMeta!=null&&!fromMeta.isRecycled())return fromMeta;
            // 缓存的那张只在「还属于当前这首」时才用，否则仪表会出现上一首的图。
            if(lastCover!=null&&!lastCover.isRecycled()&&key.equals(lastCoverKey))return lastCover;
            return stubCover();
        },()->{
            MediaController current=controller;
            return current==null?"":coverKey(current.getMetadata());
        });
        OfficialMediaBridge.lyricSource(()->clusterLyric);
        // The platform's A2DP sink owns the Bluetooth transport. Mirroring it
        // creates a competing media-button session and can steal wheel keys
        // after the phone reconnects. Respect an actively playing Bluetooth
        // session even when the UI is pinned to a paused online player.
        boolean bluetoothSelected=controller!=null&&"com.android.bluetooth".equals(controller.getPackageName());
        boolean bluetoothPlaying=false;
        for(MediaController candidate:observed){
            if(!"com.android.bluetooth".equals(candidate.getPackageName()))continue;
            PlaybackState state=candidate.getPlaybackState();
            if(state!=null&&state.getState()==PlaybackState.STATE_PLAYING){bluetoothPlaying=true;break;}
        }
        PlaybackState selectedState=controller==null?null:controller.getPlaybackState();
        if(bluetoothSelected){
            officialBridge.update(controller);
            steeringSession.setActive(false);
            return;
        }
        boolean onlineSwitchActive=onlineSwitchController!=null;
        if(!onlineSwitchActive&&bluetoothPlaying&&(selectedState==null||selectedState.getState()!=PlaybackState.STATE_PLAYING)){
            officialBridge.update(null);
            steeringSession.setActive(false);
            return;
        }
        officialBridge.update(controller);
        if(controller==null){steeringSession.setActive(false);noteSteering(false);return;}
        try{
            if(steeringMetaDirty){
                steeringMetaDirty=false;
                MediaMetadata source=controller.getMetadata();
                MediaMetadata.Builder metadata=new MediaMetadata.Builder();
                if(source!=null){
                    copyText(source,metadata,MediaMetadata.METADATA_KEY_TITLE);
                    copyText(source,metadata,MediaMetadata.METADATA_KEY_ARTIST);
                    copyText(source,metadata,MediaMetadata.METADATA_KEY_ALBUM);
                    copyText(source,metadata,MediaMetadata.METADATA_KEY_DISPLAY_TITLE);
                    copyText(source,metadata,MediaMetadata.METADATA_KEY_DISPLAY_SUBTITLE);
                    copyText(source,metadata,MediaMetadata.METADATA_KEY_MEDIA_ID);
                    long duration=source.getLong(MediaMetadata.METADATA_KEY_DURATION);if(duration>0)metadata.putLong(MediaMetadata.METADATA_KEY_DURATION,duration);
                    Bitmap art=source.getBitmap(MediaMetadata.METADATA_KEY_ALBUM_ART);if(art==null)art=source.getBitmap(MediaMetadata.METADATA_KEY_ART);
                    boolean fromPlayer=art!=null&&!art.isRecycled();
                    // 缓存的那张只在还属于当前这首时才用，避免会话里挂着上一首的图。
                    if(!fromPlayer&&lastCover!=null&&!lastCover.isRecycled()&&coverKey(source).equals(lastCoverKey)){art=lastCover;fromPlayer=true;}
                    // 会话里不塞占位图：实测仪表不读这条会话，占位图只会污染系统媒体面板。
                    if(art!=null&&!art.isRecycled())metadata.putBitmap(MediaMetadata.METADATA_KEY_ALBUM_ART,art);
                    if(coverTrace!=fromPlayer){coverTrace=fromPlayer;
                        UniLog.i(LogTags.MEDIA,"方向盘媒体会话封面","fromPlayer",fromPlayer,"has",art!=null);}
                    if(PROBE_MARKER){
                        CharSequence probeTitle=source.getText(MediaMetadata.METADATA_KEY_TITLE);
                        if(probeTitle!=null)metadata.putText(MediaMetadata.METADATA_KEY_TITLE,probeTitle+"·UNI");
                        CharSequence probeDisplay=source.getText(MediaMetadata.METADATA_KEY_DISPLAY_TITLE);
                        metadata.putText(MediaMetadata.METADATA_KEY_DISPLAY_TITLE,(probeDisplay!=null?probeDisplay:probeTitle)+"·UNI");
                    }
                }
                steeringSession.setMetadata(metadata.build());
                Intent launch=context.getPackageManager().getLaunchIntentForPackage(controller.getPackageName());
                if(launch!=null)steeringSession.setSessionActivity(android.app.PendingIntent.getActivity(context,0,launch.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),android.app.PendingIntent.FLAG_UPDATE_CURRENT));
            }
            PlaybackState p=controller.getPlaybackState();
            long actions=PlaybackState.ACTION_PLAY|PlaybackState.ACTION_PAUSE|PlaybackState.ACTION_PLAY_PAUSE;
            if(p!=null)actions|=p.getActions()&(PlaybackState.ACTION_SKIP_TO_NEXT|PlaybackState.ACTION_SKIP_TO_PREVIOUS|PlaybackState.ACTION_SEEK_TO);
            if(NeteaseMediaAdapter.supports(controller))actions|=PlaybackState.ACTION_SKIP_TO_NEXT|PlaybackState.ACTION_SKIP_TO_PREVIOUS|PlaybackState.ACTION_SEEK_TO;
            steeringSession.setPlaybackState(new PlaybackState.Builder().setActions(actions)
                .setState(p==null?PlaybackState.STATE_NONE:p.getState(),p==null?0:Math.max(0,p.getPosition()),p==null?0:p.getPlaybackSpeed(),SystemClock.elapsedRealtime()).build());
            // 仪表那条链路只吃「播放状态 + 时长」，文案封面走原车媒体中心；开关关着时一次都不写。
            // 状态/时长没变时 DimMediaBridge 自己会跳过，所以这里跟着状态回调走不会刷屏。
            MediaMetadata clusterMeta=controller.getMetadata();
            if(dimClusterEnabled)dim.push(p!=null&&p.getState()==PlaybackState.STATE_PLAYING,
                clusterMeta==null?-1:clusterMeta.getLong(MediaMetadata.METADATA_KEY_DURATION),0,
                clusterMeta==null?"":clusterMeta.getString(MediaMetadata.METADATA_KEY_TITLE),
                clusterMeta==null?"":clusterMeta.getString(MediaMetadata.METADATA_KEY_ARTIST),
                clusterMeta==null?"":clusterMeta.getString(MediaMetadata.METADATA_KEY_ALBUM),
                clusterMeta==null?"":clusterMeta.getString(MediaMetadata.METADATA_KEY_MEDIA_ID));
            steeringSession.setActive(true);
            noteSteering(true);
        }catch(Exception|LinkageError e){UniLog.w(LogTags.MEDIA,"Unable to synchronize steering media session",e,"tag","UniMedia");steeringSession.setActive(false);noteSteering(false);}
    }
    /** Logs the mirrored steering session only when its state flips. */
    private void noteSteering(boolean active){
        if(steeringActive==active)return;
        steeringActive=active;
        UniLog.i(LogTags.MEDIA,active?"方向盘媒体会话已发布":"方向盘媒体会话已撤下","active",active);
    }
    private static void copyText(MediaMetadata source,MediaMetadata.Builder target,String key){
        CharSequence value=source.getText(key);if(value!=null&&value.length()>0)target.putText(key,value);
    }
    private String anchorTrackKey="";
    private boolean anchorPlaying,anchorPositionKnown;
    private float anchorSpeed;
    private long anchorPositionMs=-1,anchorSampledAtMs=-1;

    /** 传输控制落地率：确认落地 / 超时没动 / 直接改注入 各多少次。 */
    private JSONObject effectSnapshot(){
        JSONObject out=new JSONObject();
        try{
            out.put("confirmed",effects.confirmed()).put("missed",effects.missed())
                .put("escalated",effects.escalated()).put("pending",effects.armed())
                .put("action",effects.action());
        }catch(Exception ignored){}
        return out;
    }
    public JSONObject snapshot(){
        JSONObject j=new JSONObject();try{
            JSONObject official=officialBridge.snapshot();
            j.put("authorized",authorized).put("available",controller!=null).put("playing",false).put("preferredPackage",preferred).put("sessions",activeSources)
                .put("steeringControlReady",official.optBoolean("registered"))
                .put("steeringEnabled",steeringEnabled)
                .put("instrumentEnabled",instrumentEnabled)
                .put("steeringKeys",steeringKeys.snapshot())
                .put("steeringIdleDrops",idleDrops)
                .put("dimClusterEnabled",dimClusterEnabled)
                .put("dimCluster",dim.snapshot())
                .put("transportEffect",effectSnapshot())
                .put("steeringInject",injector.snapshot().put("kugou",kugou.snapshot()))
                .put("instrumentMetadataReady",official.optBoolean("playbackAccepted"))
                .put("officialMedia",official)
                .put("reason",!authorized?"请授权媒体访问":controller==null?"所选播放器尚未建立媒体会话":"");
            if(controller!=null){
                MediaMetadata m=controller.getMetadata();PlaybackState p=controller.getPlaybackState();
                String title=m==null?"":m.getString(MediaMetadata.METADATA_KEY_TITLE);
                String artist=m==null?"":m.getString(MediaMetadata.METADATA_KEY_ARTIST);
                long duration=m==null?0:Math.max(0,m.getLong(MediaMetadata.METADATA_KEY_DURATION));
                boolean missingTitle=title==null||title.trim().isEmpty();
                MediaTextRetention.Track track=retainedTrack.update(controller.getSessionToken(),
                    p!=null&&p.getState()==PlaybackState.STATE_PAUSED,
                    new MediaTextRetention.Track(title,artist,m==null?"":m.getString(MediaMetadata.METADATA_KEY_ALBUM),duration));
                boolean restored=false;
                if(!track.known()&&missingTitle&&p!=null&&p.getState()==PlaybackState.STATE_PAUSED
                        &&controller.getPackageName().equals(lastTrackPrefs.getString("source", ""))){
                    MediaTextRetention.Track saved=new MediaTextRetention.Track(lastTrackPrefs.getString("title", ""),
                        lastTrackPrefs.getString("artist", ""),lastTrackPrefs.getString("album", ""),lastTrackPrefs.getLong("duration",0));
                    if(saved.known()){track=saved;restored=true;}
                }
                title=track.title;artist=track.artist;duration=track.durationMs;
                if(track.known()&&!missingTitle)saveTrack(controller.getPackageName(),track,position(p));
                j.put("source",controller.getPackageName()).put("sourceLabel",sourceLabel(controller.getPackageName())).put("title",title).put("artist",artist)
                    .put("collection",track.album)
                    .put("cached",restored)
                    .put("playing",p!=null&&p.getState()==PlaybackState.STATE_PLAYING);
                long actions=p==null?0:p.getActions();
                j.put("canNext",(actions&PlaybackState.ACTION_SKIP_TO_NEXT)!=0)
                    .put("canSeek",(actions&PlaybackState.ACTION_SEEK_TO)!=0)
                    .put("canPrevious",(actions&PlaybackState.ACTION_SKIP_TO_PREVIOUS)!=0)
                    .put("canToggle",p!=null&&(actions&(p.getState()==PlaybackState.STATE_PLAYING?(PlaybackState.ACTION_PAUSE|PlaybackState.ACTION_PLAY_PAUSE):(PlaybackState.ACTION_PLAY|PlaybackState.ACTION_PLAY_PAUSE)))!=0)
                    .put("artwork",missingTitle&&track.known()&&!coverData.isEmpty()?coverData:artwork(m));
                // Android has no universal lyrics contract. Take an explicit text payload
                // when the source publishes one; otherwise identify the recording from the
                // session metadata. An unmatched track stays empty, it is never guessed.
                String text;
                String source;
                if(NeteaseMediaAdapter.supports(controller)){
                    text=netease.getLyrics();
                    source=netease.getLyricsSource();
                }else{
                    text=readLyrics(m,controller.getExtras());
                    source=text.isEmpty()?"":"media-session";
                }
                if(text.isEmpty()){
                    // A local audio file carries its own lyrics; that beats every catalogue.
                    text=localLyrics(m,controller.getExtras());
                    if(!text.isEmpty())source="embedded";
                }
                if(text.isEmpty()){
                    text=lyrics.cached(title,artist,duration);
                    source=text.isEmpty()?"":"lyrics-resolver";
                    if(text.isEmpty())lyrics.request(title,artist,duration);
                }
                noteLyricSource(source,title,artist,duration);
                // 原车 getLyric()/getLyricContent() 也吃这份歌词：仪表那边就不用自己找了。
                clusterLyric=text;
                LyricTimelineProvider.Result timed=timeline.resolve(title,artist,duration,
                        controller.getPackageName(),text,mediaId(m));
                // Change-only diagnostic: the snapshot runs several times a second, and "the card
                // says 当前音源未提供歌词" is the report this pipeline gets. One line per distinct
                // answer is enough to tell "no document" apart from "document never reached Dart".
                String lyricTrace=timed.key+"\u0000"+timed.isEmpty()+"\u0000"+timed.label
                        +"\u0000"+timed.timeline.lineCount();
                if(!lyricTrace.equals(lastLyricTrace)){
                    lastLyricTrace=lyricTrace;
                    UniLog.i(LogTags.MEDIA,"lyric/document","title",title,"textLen",text.length(),
                        "mediaId",mediaId(m),"duration",duration,"docKey",timed.key,
                        "words",timed.wordTimed,"lines",timed.timeline.lineCount(),
                        "label",timed.label,"catalogFailures",LyricCatalog.describeFailures());
                }
                boolean casting=p!=null&&p.getState()==PlaybackState.STATE_PLAYING;
                // The document must belong to the track being painted. Every cache on the way here
                // is keyed by title|artist|seconds, but a single slip — a retained track, a
                // catalog answer that lands after the user skipped — would put the previous
                // song's words on the glass, which reads as a lyric engine that is one track
                // behind. Refuse the mismatch and say so in the log instead.
                String wantKey=LyricCatalog.key(title,artist,duration);
                boolean docOwned=timed.key.isEmpty()||timed.key.equals(wantKey);
                if(!docOwned)UniLog.fail(LogTags.LYRIC,"lyric/mismatch","want",wantKey,"got",timed.key,"title",title,"artist",artist);
                LyricTimelineProvider.Result timed2=docOwned?timed:LyricTimelineProvider.Result.EMPTY;
                // Same sample for the card and for the cast window on another display, so
                // both fill edges come from one clock reading instead of two.
                long castAt=System.currentTimeMillis();
                // The user-tuned offset shifts the clock, not the document: the card and the
                // cast panel both read this position, so a correction applies to both.
                long offsetMs=LyricOffset.forTrack(title,artist);
                long castPosition=Math.max(0,position(p)+offsetMs);
                LyricCast.publish(title,artist,timed2.label,timed2.timeline,casting,
                        castPosition,castAt,p==null?1f:p.getPlaybackSpeed());
                boolean positionKnown=p!=null&&p.getPosition()>=0;
                float speed=p==null?0f:p.getPlaybackSpeed();
                String trackKey=controller.getPackageName()+"\u0000"+title+"\u0000"+artist+"\u0000"+duration+"\u0000"+offsetMs;
                long expectedPos=anchorPositionMs;
                if(anchorPlaying&&anchorSampledAtMs>0&&castAt>=anchorSampledAtMs){
                    expectedPos+=Math.round((castAt-anchorSampledAtMs)*anchorSpeed);
                }
                if(!trackKey.equals(anchorTrackKey)||casting!=anchorPlaying||positionKnown!=anchorPositionKnown
                        ||Math.abs(speed-anchorSpeed)>0.001f||anchorSampledAtMs<=0||Math.abs(castPosition-expectedPos)>250){
                    anchorTrackKey=trackKey;
                    anchorPlaying=casting;
                    anchorPositionKnown=positionKnown;
                    anchorSpeed=speed;
                    anchorPositionMs=castPosition;
                    anchorSampledAtMs=castAt;
                }
                j.put("lyrics",text).put("lyricsSource",source)
                    .put("durationMs",duration)
                    // 发锚点，不发本次原始采样：两次快照之间 Dart 侧按 speed 外推，
                    // 歌词与进度才不会每 80ms 跳一下。anchor* 就是上面刚算出来的那组。
                    .put("positionMs",anchorPositionMs).put("positionKnown",positionKnown)
                    .put("sampledAtMs",anchorSampledAtMs)
                    .put("speed",speed);
                // 一定要写这三项，哪怕空。以前是「有文档才 put」，Dart 侧读到的仍是上一首的
                // JSON，换到一首没词源的歌就整首停在上一首的词上 —— 看起来像歌词全错。
                j.put("lyricTimeline",timed2.isEmpty()?"":timed2.json)
                    .put("lyricTimelineLabel",timed2.isEmpty()?"":timed2.label)
                    .put("lyricTimelineWords",!timed2.isEmpty()&&timed2.wordTimed);
                netease.augmentSnapshot(j);
                if(!text.isEmpty())j.put("lyricsReason","");
            } else {
                String savedSource=lastTrackPrefs.getString("source", "");
                String savedTitle=lastTrackPrefs.getString("title", "");
                boolean accepts="auto".equals(preferred)||preferred.equals(savedSource);
                if(accepts&&!savedSource.isEmpty()&&!savedTitle.isEmpty()){
                    j.put("source",savedSource).put("sourceLabel",sourceLabel(savedSource))
                        .put("title",savedTitle).put("artist",lastTrackPrefs.getString("artist", ""))
                        .put("collection",lastTrackPrefs.getString("album", ""))
                        .put("durationMs",lastTrackPrefs.getLong("duration",0))
                        .put("positionMs",lastTrackPrefs.getLong("position",0))
                        .put("positionKnown",false).put("cached",true)
                        .put("reason","播放器未连接，显示上次播放");
                }
            }
        }catch(Exception failed){
            // A snapshot that dies halfway is the worst kind: the UI keeps the title it already
            // received and shows "当前音源未提供歌词" for a track whose lyrics were fine, with
            // nothing in the log to say why. Name the failure and the stage it reached.
            String trace=android.util.Log.getStackTraceString(failed);
            if(trace.length()>700)trace=trace.substring(0,700);
            UniLog.fail(LogTags.MEDIA,"media/snapshot fail","error",
                failed.getClass().getSimpleName(),"title",j.optString("title"),
                "hasLyrics",j.has("lyrics"),"hasTimeline",j.has("lyricTimeline"),
                "trace",trace.replace('\n',' '));
        }return j;
    }
    private void saveTrack(String source,MediaTextRetention.Track track,long position){
        String key=source+"\u0000"+track.title+"\u0000"+track.artist;
        long now=SystemClock.elapsedRealtime();
        if(key.equals(savedTrackKey)&&now-lastTrackWriteAt<30_000)return;
        savedTrackKey=key;lastTrackWriteAt=now;
        lastTrackPrefs.edit().putString("source",source).putString("title",track.title)
            .putString("artist",track.artist).putString("album",track.album)
            .putLong("duration",track.durationMs).putLong("position",Math.max(0,position)).apply();
        UniLog.d(LogTags.MEDIA,"已缓存上次播放的曲目","source",source,"title",track.title,"artist",track.artist);
    }
    private String artwork(MediaMetadata m){
        if(!artworkDirty)return coverData;artworkDirty=false;
        if(m==null){lastCover=null;lastCoverKey="";coverData="";UniLog.skip(LogTags.MEDIA,"media/artwork","reason","no-metadata");return "";}
        Bitmap bitmap=m.getBitmap(MediaMetadata.METADATA_KEY_ALBUM_ART);
        if(bitmap==null)bitmap=m.getBitmap(MediaMetadata.METADATA_KEY_ART);
        if(bitmap==lastCover)return coverData;
        lastCover=bitmap;lastCoverKey=coverKey(m);coverData="";
        if(bitmap!=null&&!bitmap.isRecycled())try{
            float scale=Math.min(1f,256f/Math.max(bitmap.getWidth(),bitmap.getHeight()));
            Bitmap small=Bitmap.createScaledBitmap(bitmap,Math.max(1,(int)(bitmap.getWidth()*scale)),Math.max(1,(int)(bitmap.getHeight()*scale)),true);
            ByteArrayOutputStream bytes=new ByteArrayOutputStream();small.compress(Bitmap.CompressFormat.JPEG,80,bytes);
            coverData=Base64.encodeToString(bytes.toByteArray(),Base64.NO_WRAP);
            if(small!=bitmap)small.recycle();
        }catch(RuntimeException ignored){
            // The raw failure is worth keeping: the cover stays empty and
            // nobody would know whether the player sent one at all.
            UniLog.w(LogTags.MEDIA,"封面压缩失败","error",ignored.getClass().getSimpleName(),"reason",String.valueOf(ignored.getMessage()));
        }
        if(coverData.isEmpty())UniLog.skip(LogTags.MEDIA,"media/artwork","reason",bitmap==null?"no-artwork":"compress-failed");
        else UniLog.done(LogTags.MEDIA,"media/artwork","bytes",coverData.length());
        return coverData;
    }
    /** 播放器这首没给封面时的中性占位图（深色底 + 音符），不抢眼也不像报错。 */
    private Bitmap stubCover(){
        if(stub!=null&&!stub.isRecycled())return stub;
        try{
            int size=256;
            Bitmap bitmap=Bitmap.createBitmap(size,size,Bitmap.Config.ARGB_8888);
            android.graphics.Canvas canvas=new android.graphics.Canvas(bitmap);
            android.graphics.Paint paint=new android.graphics.Paint(android.graphics.Paint.ANTI_ALIAS_FLAG);
            paint.setShader(new android.graphics.LinearGradient(0,0,size,size,0xFF17222B,0xFF233543,android.graphics.Shader.TileMode.CLAMP));
            canvas.drawRect(0,0,size,size,paint);
            paint.setShader(null);
            paint.setColor(0x3320D5C4);paint.setStyle(android.graphics.Paint.Style.STROKE);paint.setStrokeWidth(3);
            canvas.drawCircle(size/2f,size/2f,size*0.32f,paint);
            paint.setColor(0xFF20D5C4);paint.setStyle(android.graphics.Paint.Style.FILL);
            paint.setTextAlign(android.graphics.Paint.Align.CENTER);
            paint.setTextSize(size*0.42f);
            paint.setTypeface(android.graphics.Typeface.DEFAULT_BOLD);
            android.graphics.Paint.FontMetrics metrics=paint.getFontMetrics();
            canvas.drawText("♪",size/2f,size/2f-(metrics.ascent+metrics.descent)/2f,paint);
            stub=bitmap;
        }catch(Throwable e){UniLog.w(LogTags.MEDIA,"占位封面创建失败",e);}
        return stub;
    }
    private Bitmap stub;
    /** 临时探针：给方向盘的会话标题加后缀，用来判断仪表读的是不是我们这条会话。 */
    /** 临时探针（已出结论：仪表不读我们这个会话，它读播放器自己的会话）。 */
    private static final boolean PROBE_MARKER=false;
    private boolean coverTrace=true;
    /** Logs the lyric source only when it changes: the snapshot runs on every
     *  tick, and the source itself does not change between ticks. */
    private String lastLyricTrace="";
    private void noteLyricSource(String source,String title,String artist,long durationMs){
        String track=title+"|"+artist;
        if(source.equals(lastLyricSource)&&track.equals(lastLyricTrack))return;
        lastLyricSource=source;lastLyricTrack=track;
        if(source.isEmpty())UniLog.i(LogTags.LYRIC,"当前曲目没有歌词来源","title",title,"artist",artist,"durationMs",durationMs);
        else UniLog.i(LogTags.LYRIC,"歌词来源已切换","source",source,"title",title,"artist",artist,"durationMs",durationMs);
    }
    /** The id the playing app uses for this recording; only meaningful to that catalogue. */
    /** Embedded lyric text per file path; a small map because tracks change rarely. */
    private static final Map<String,String> localTexts=new LinkedHashMap<String,String>();
    private static String mediaId(MediaMetadata metadata){
        try{
            String value=metadata==null?null:metadata.getString(MediaMetadata.METADATA_KEY_MEDIA_ID);
            if(value!=null&&!value.isEmpty()&&value.length()<=64)return value;
        }catch(RuntimeException ignored){}
        return "";
    }
    /**
     * Lyrics stored inside the audio file itself. A local track beats any catalogue: it is the
     * exact edit being played, it works offline, and it costs one bounded file read.
     */
    private static String localLyrics(MediaMetadata metadata,Bundle extras){
        String path=audioPath(metadata,extras);
        // audioPath answers null for every streamed track, and every netease/QQ/汽水 session is
        // streamed. The null check used to be missing, so the snapshot died in here with an NPE
        // the moment a player published no lyric text of its own — the catalogue was never asked,
        // and the card fell back to "当前音源未提供歌词" for songs whose lyrics resolve fine.
        if(path==null||path.isEmpty())return "";
        String cached=localTexts.get(path);
        if(cached!=null)return cached;
        String text="";
        try{text=EmbeddedLyricReader.read(new java.io.File(path));}catch(RuntimeException ignored){}
        if(localTexts.size()>8)localTexts.clear();
        localTexts.put(path,text);
        return text;
    }
    private static String audioPath(MediaMetadata metadata,Bundle extras){
        try{
            String raw=metadata==null?null:metadata.getString(MediaMetadata.METADATA_KEY_MEDIA_URI);
            if(raw!=null&&raw.startsWith("file://"))return raw.substring(7);
            String[] keys={"_data","path","file","android.media.metadata.PATH"};
            for(String key:keys){
                Object value=extras==null?null:extras.get(key);
                if(value instanceof CharSequence){
                    String value2=value.toString();
                    if(value2.startsWith("/"))return value2;
                    if(value2.startsWith("file://"))return value2.substring(7);
                }
            }
        }catch(RuntimeException ignored){}
        return null;
    }
    private static String readLyrics(MediaMetadata metadata,Bundle extras){
        String[] keys={"android.media.metadata.LYRICS","android.media.metadata.LYRIC","lyrics","lyric","lrc"};
        for(String key:keys){
            try{CharSequence value=metadata==null?null:metadata.getText(key);
                if(value!=null&&value.length()>0&&value.length()<=131072)return value.toString();
            }catch(RuntimeException ignored){}
            try{Object value=extras==null?null:extras.get(key);
                if(value instanceof CharSequence&&((CharSequence)value).length()>0&&((CharSequence)value).length()<=131072)return value.toString();
            }catch(RuntimeException ignored){}
        }
        return "";
    }
    private static long position(PlaybackState p){
        if(p==null||p.getPosition()<0)return 0;
        long value=p.getPosition();
        if(p.getState()==PlaybackState.STATE_PLAYING&&p.getLastPositionUpdateTime()>0)
            value+=(long)(Math.max(0,SystemClock.elapsedRealtime()-p.getLastPositionUpdateTime())*p.getPlaybackSpeed());
        return Math.max(0,value);
    }
    public boolean command(String action){
        return command(action,-1);
    }
    public boolean command(String action,long positionMs){
        clearPlayFallback();
        // 上一把同类指令超时没落地（传输控制回了没动）：这次直接换执行器，不再白按一遍。
        if(escalate(action))return true;
        boolean wantsPlay="play".equals(action)||("toggle-play".equals(action)
                &&(controller==null||controller.getPlaybackState()==null
                    ||controller.getPlaybackState().getState()!=PlaybackState.STATE_PLAYING));
        if(controller==null){
            // A paused player may destroy its MediaSession while the launcher
            // keeps the last track visible. Play is the one command that can
            // restore the application; transport controls cannot target a
            // disconnected session.
            if("toggle-play".equals(action)||"play".equals(action)){
                // 还有别的播放器会话在，媒体键落得到实处，就不必把界面翻上来。
                // 一个会话都没有时（播放器自己把 session 撤了，只剩系统里那枚
                // 残留的 MediaButtonReceiver）注入只是空响：没有人会起播。
                // 这时拉起应用就是唯一能让用户听到声音的动作。
                if(!observed.isEmpty()&&relayKey(action)){
                    UniLog.done(LogTags.MEDIA,"media/transport","action",action,"route","media-key","reason","no-active-session");
                    return true;
                }
                boolean launched=launchSavedSource();
                if(launched)UniLog.done(LogTags.MEDIA,"media/transport","action",action,"route","launch-source","reason","no-active-session");
                else UniLog.fail(LogTags.MEDIA,"media/transport","action",action,"route","launch-source","reason","no-launchable-source");
                return launched;
            }
            UniLog.fail(LogTags.MEDIA,"media/transport","action",action,"reason","no-active-session");
            return false;
        }
        if(NeteaseMediaAdapter.supports(controller)){
            boolean accepted=netease.command(action,positionMs);
            if(accepted)armEffect(action);
            if(accepted&&wantsPlay)schedulePlayFallback(controller);
            if(accepted)UniLog.done(LogTags.MEDIA,"media/transport","action",action,"route","netease","source",controller.getPackageName());
            else UniLog.fail(LogTags.MEDIA,"media/transport","action",action,"route","netease","reason","rejected");
            return accepted;
        }
        if(transport(action,positionMs)){armEffect(action);if(wantsPlay)schedulePlayFallback(controller);return true;}
        // 播放器没有可用的传输控制，或者根本不暴露 SKIP_TO_NEXT（酷狗车机版）：
        // 先走它自己的广播，再退回按键注入。
        return relayKey(action);
    }
    /**
     * 同一类指令上一把超时没动：这次直接换按键注入，不再走传输控制。
     *
     * <p>播放类、换歌类分开记账（{@link SteeringKeyPolicy#kind}），所以「上一首没动」
     * 不会把「播放」也判成坏的。
     */
    private boolean escalate(String action){
        String kind=SteeringKeyPolicy.kind(action);
        if(kind.isEmpty())return false;
        if(!effects.shouldEscalate(kind,SystemClock.elapsedRealtime()))return false;
        if(!relayKey(action))return false;
        effects.noteEscalated();
        UniLog.i(LogTags.MEDIA,"上一把传输控制没落地，改走按键注入","action",action,"kind",kind);
        return true;
    }
    /** 指令送出后记一笔：由播放状态回调，或下一次同类按键结账。 */
    private void armEffect(String action){
        String kind=SteeringKeyPolicy.kind(action);
        if(kind.isEmpty())return;
        effects.arm(kind,fingerprint(),SystemClock.elapsedRealtime());
    }
    /** 「真的动了」的证据：播放状态 + 两秒粒度位置 + 曲目 + 时长。 */
    private String fingerprint(){
        MediaController target=controller;
        if(target==null)return"";
        PlaybackState p=target.getPlaybackState();
        MediaMetadata m=target.getMetadata();
        return MediaEffectTracker.fingerprint(
            p==null?0:p.getState(),
            p==null?-1:position(p),
            m==null?"":m.getString(MediaMetadata.METADATA_KEY_TITLE),
            m==null?0:m.getLong(MediaMetadata.METADATA_KEY_DURATION));
    }
    /** 标准传输控制。拿不到对应能力时返回 false，由 {@link #relayKey} 接手。 */
    private boolean transport(String action,long positionMs){
        PlaybackState p=controller.getPlaybackState();
        if(p==null){
            UniLog.fail(LogTags.MEDIA,"media/transport","action",action,"reason","no-playback-state");
            return false;
        }
        long actions=p.getActions();MediaController.TransportControls t=controller.getTransportControls();
        if("next".equals(action)){
            if((actions&PlaybackState.ACTION_SKIP_TO_NEXT)==0)return false;
            t.skipToNext();return true;
        }
        if("previous".equals(action)){
            if((actions&PlaybackState.ACTION_SKIP_TO_PREVIOUS)==0)return false;
            t.skipToPrevious();return true;
        }
        if("seek".equals(action)){
            if(positionMs<0||(actions&PlaybackState.ACTION_SEEK_TO)==0)return false;
            MediaMetadata m=controller.getMetadata();long duration=m==null?0:m.getLong(MediaMetadata.METADATA_KEY_DURATION);
            t.seekTo(duration>0?Math.min(positionMs,duration):positionMs);return true;
        }
        if("toggle-play".equals(action)){
            if(p.getState()==PlaybackState.STATE_PLAYING){
                if((actions&(PlaybackState.ACTION_PAUSE|PlaybackState.ACTION_PLAY_PAUSE))==0){
                    UniLog.fail(LogTags.MEDIA,"media/transport","action",action,"reason","action-not-supported","actions",actions);
                    return false;
                }
                t.pause();UniLog.done(LogTags.MEDIA,"media/transport","action",action,"route","standard","source",controller.getPackageName());return true;
            }
            if((actions&(PlaybackState.ACTION_PLAY|PlaybackState.ACTION_PLAY_PAUSE))==0){
                UniLog.fail(LogTags.MEDIA,"media/transport","action",action,"reason","action-not-supported","actions",actions);
                return false;
            }
            t.play();UniLog.done(LogTags.MEDIA,"media/transport","action",action,"route","standard","source",controller.getPackageName());return true;
        }
        if("play".equals(action)){
            if((actions&(PlaybackState.ACTION_PLAY|PlaybackState.ACTION_PLAY_PAUSE))==0){
                UniLog.fail(LogTags.MEDIA,"media/transport","action",action,"reason","action-not-supported","actions",actions);
                return false;
            }
            t.play();UniLog.done(LogTags.MEDIA,"media/transport","action",action,"route","standard","source",controller.getPackageName());return true;
        }
        return false;
    }
    /**
     * 传输控制不可用时的兜底。酷狗车机版只认它自己的广播；其余播放器由系统注入
     * AOSP 媒体键，落点是当前焦点窗口。注入前先记一笔，回环会被
     * {@link #injectedEcho} 挡掉，同一次按键不会走两步。
     */
    private boolean relayKey(String action){
        int key=SteeringKeyPolicy.keyCode(action);
        if(key<0)return false;
        String source=controller==null?"":controller.getPackageName();
        if(kugou.send(source,key)){markInjected(action);return true;}
        if(injector.inject(key)){
            markInjected(action);
            UniLog.i(LogTags.MEDIA,"方控按键注入","key",key,"action",action,"source",source);
            return true;
        }
        return false;
    }
    private void schedulePlayFallback(MediaController target){
        pendingPlayToken=target.getSessionToken();pendingPlaySource=target.getPackageName();pendingPlayStage=0;
        handler.removeCallbacks(playFallback);handler.postDelayed(playFallback,PLAY_CONFIRM_MS);
    }
    private void clearPlayFallback(){
        handler.removeCallbacks(playFallback);pendingPlayToken=null;pendingPlaySource="";pendingPlayStage=0;
    }
    private boolean sendPlay(MediaController target){
        if(target==null)return false;
        if(NeteaseMediaAdapter.supports(target))return netease.command("play");
        PlaybackState state=target.getPlaybackState();
        if(state==null||(state.getActions()&(PlaybackState.ACTION_PLAY|PlaybackState.ACTION_PLAY_PAUSE))==0)return false;
        target.getTransportControls().play();return true;
    }
    private boolean launchSavedSource(){
        String saved=lastTrackPrefs.getString("source","");
        return launchSource("auto".equals(preferred)||preferred.isEmpty()?saved:preferred);
    }
    private boolean launchSource(String source){
        if(source==null||source.isEmpty())return false;
        try{
            Intent launch=context.getPackageManager().getLaunchIntentForPackage(source);
            if(launch==null)return false;
            context.startActivity(launch.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK));
            return true;
        }catch(RuntimeException e){return false;}
    }
    /**
     * 只撤「观察与上报」这一层，方控输入通道留在原地。
     *
     * <p>原车输入回调是原车给的授权，反注册以后要重新申请：中间那段窗口里按键是死的，
     * 而且下一轮 {@link #start()} 还得重走一遍 {@code requestKeysInterception}。
     * 桌面在后台、只剩底栏在跑的时候也会走到这里，那时候方向盘键照样该归桌面管，
     * 所以通道常驻、动作由 {@link #onSteeringAction} 的 {@code started} 判断把关。
     */
    public void stop(){
        started=false;clearPlayFallback();effects.clear();
        try{manager.removeOnActiveSessionsChangedListener(sessions);}catch(Exception ignored){}
        dim.stop();officialBridge.stop();select(null);steeringSession.setActive(false);
        UniLog.done(LogTags.MEDIA,"media/session","action","unbind","authorized",authorized,"steeringKeys",steeringKeys.installed());
    }
}

