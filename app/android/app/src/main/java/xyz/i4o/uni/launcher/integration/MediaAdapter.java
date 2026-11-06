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
import xyz.i4o.uni.launcher.integration.lyrics.LyricCast;
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
                pendingPlayStage=1;launchSource(pendingPlaySource);
                handler.postDelayed(this,PLAY_CONFIRM_MS);return;
            }
            clearPlayFallback();
            if(sameSession)sendPlay(controller);
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
        public void onMetadataChanged(MediaMetadata m){artworkDirty=true;noteMetadata(m);choose();changed.run();}
        // choose() already synchronizes the selected source, including switches.
        public void onPlaybackStateChanged(PlaybackState s){choose();changed.run();}
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
        timeline=new LyricTimelineProvider(new File(context.getFilesDir(),"lyric-timeline"));
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
        steeringKeys=new SteeringKeyBridge(context,(action,keyCode)->onSteeringAction("input",action));
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
        // 方控开关关着时不接原车输入通道：方向盘键原样留给原车，桌面完全不参与。
        if(steeringEnabled)steeringKeys.start();
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
        UniLog.i(LogTags.MEDIA,"媒体会话列表已刷新","sessions",observed.size());
        choose();
        // Observe every session: a player's state can change without the
        // active-session list changing, including paused -> playing.
        for(MediaController c:observed)c.registerCallback(callback,handler);
    }
    private void choose(){
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
            if(next==null||controller==null||!next.getSessionToken().equals(controller.getSessionToken())){lastCover=null;coverData="";artworkDirty=true;}
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
        UniLog.done(LogTags.MEDIA,"media/metadata","title",title,"artist",artist,"hasArtwork",artwork);
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
        if(!steeringEnabled)return false;
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
    private void syncSteeringSession(){
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
                if(art!=null&&!art.isRecycled())metadata.putBitmap(MediaMetadata.METADATA_KEY_ALBUM_ART,art);
            }
            steeringSession.setMetadata(metadata.build());
            PlaybackState p=controller.getPlaybackState();
            long actions=PlaybackState.ACTION_PLAY|PlaybackState.ACTION_PAUSE|PlaybackState.ACTION_PLAY_PAUSE;
            if(p!=null)actions|=p.getActions()&(PlaybackState.ACTION_SKIP_TO_NEXT|PlaybackState.ACTION_SKIP_TO_PREVIOUS|PlaybackState.ACTION_SEEK_TO);
            if(NeteaseMediaAdapter.supports(controller))actions|=PlaybackState.ACTION_SKIP_TO_NEXT|PlaybackState.ACTION_SKIP_TO_PREVIOUS|PlaybackState.ACTION_SEEK_TO;
            steeringSession.setPlaybackState(new PlaybackState.Builder().setActions(actions)
                .setState(p==null?PlaybackState.STATE_NONE:p.getState(),p==null?0:Math.max(0,p.getPosition()),p==null?0:p.getPlaybackSpeed(),SystemClock.elapsedRealtime()).build());
            Intent launch=context.getPackageManager().getLaunchIntentForPackage(controller.getPackageName());
            if(launch!=null)steeringSession.setSessionActivity(android.app.PendingIntent.getActivity(context,0,launch.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),android.app.PendingIntent.FLAG_UPDATE_CURRENT));
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
    public JSONObject snapshot(){
        JSONObject j=new JSONObject();try{
            j.put("authorized",authorized).put("available",controller!=null).put("playing",false).put("preferredPackage",preferred).put("sessions",activeSources)
                .put("steeringControlReady",officialBridge.snapshot().optBoolean("registered"))
                .put("steeringEnabled",steeringEnabled)
                .put("instrumentEnabled",instrumentEnabled)
                .put("steeringKeys",steeringKeys.snapshot())
                .put("steeringInject",injector.snapshot().put("kugou",kugou.snapshot()))
                .put("instrumentMetadataReady",officialBridge.snapshot().optBoolean("playbackAccepted"))
                .put("officialMedia",officialBridge.snapshot())
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
                String text=readLyrics(m,controller.getExtras());
                String source=text.isEmpty()?"":"media-session";
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
                LyricTimelineProvider.Result timed=timeline.resolve(title,artist,duration,
                        controller.getPackageName(),text,mediaId(m));
                boolean casting=p!=null&&p.getState()==PlaybackState.STATE_PLAYING;
                // Same sample for the card and for the cast window on another display, so
                // both fill edges come from one clock reading instead of two.
                long castAt=System.currentTimeMillis();
                // The user-tuned offset shifts the clock, not the document: the card and the
                // cast panel both read this position, so a correction applies to both.
                long castPosition=Math.max(0,position(p)+LyricOffset.forTrack(title,artist));
                LyricCast.publish(title,artist,timed.label,timed.timeline,casting,
                        castPosition,castAt,p==null?1f:p.getPlaybackSpeed());
                j.put("lyrics",text).put("lyricsSource",source)
                    .put("durationMs",duration)
                    .put("positionMs",castPosition).put("positionKnown",p!=null&&p.getPosition()>=0)
                    .put("sampledAtMs",castAt)
                    .put("speed",p==null?0:p.getPlaybackSpeed());
                if(!timed.isEmpty())j.put("lyricTimeline",timed.json)
                    .put("lyricTimelineLabel",timed.label)
                    .put("lyricTimelineWords",timed.wordTimed);
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
        }catch(Exception ignored){}return j;
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
        if(m==null){lastCover=null;coverData="";UniLog.skip(LogTags.MEDIA,"media/artwork","reason","no-metadata");return "";}
        Bitmap bitmap=m.getBitmap(MediaMetadata.METADATA_KEY_ALBUM_ART);
        if(bitmap==null)bitmap=m.getBitmap(MediaMetadata.METADATA_KEY_ART);
        if(bitmap==lastCover)return coverData;
        lastCover=bitmap;coverData="";
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
    /** Logs the lyric source only when it changes: the snapshot runs on every
     *  tick, and the source itself does not change between ticks. */
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
        if(path.isEmpty())return "";
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
        boolean wantsPlay="play".equals(action)||("toggle-play".equals(action)
                &&(controller==null||controller.getPlaybackState()==null
                    ||controller.getPlaybackState().getState()!=PlaybackState.STATE_PLAYING));
        if(controller==null){
            // A paused player may destroy its MediaSession while the launcher
            // keeps the last track visible. Play is the one command that can
            // restore the application; transport controls cannot target a
            // disconnected session.
            if("toggle-play".equals(action)||"play".equals(action)){
                boolean launched=launchSavedSource();
                if(launched)UniLog.done(LogTags.MEDIA,"media/transport","action",action,"route","launch-source");
                else UniLog.fail(LogTags.MEDIA,"media/transport","action",action,"route","launch-source","reason","no-launchable-source");
                return launched;
            }
            UniLog.fail(LogTags.MEDIA,"media/transport","action",action,"reason","no-active-session");
            return false;
        }
        if(NeteaseMediaAdapter.supports(controller)){
            boolean accepted=netease.command(action,positionMs);
            if(accepted&&wantsPlay)schedulePlayFallback(controller);
            if(accepted)UniLog.done(LogTags.MEDIA,"media/transport","action",action,"route","netease","source",controller.getPackageName());
            else UniLog.fail(LogTags.MEDIA,"media/transport","action",action,"route","netease","reason","rejected");
            return accepted;
        }
        if(transport(action,positionMs)){if(wantsPlay)schedulePlayFallback(controller);return true;}
        // 播放器没有可用的传输控制，或者根本不暴露 SKIP_TO_NEXT（酷狗车机版）：
        // 先走它自己的广播，再退回按键注入。
        return relayKey(action);
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
    public void stop(){started=false;clearPlayFallback();try{manager.removeOnActiveSessionsChangedListener(sessions);}catch(Exception ignored){}steeringKeys.stop();officialBridge.stop();select(null);steeringSession.setActive(false);UniLog.done(LogTags.MEDIA,"media/session","action","unbind","authorized",authorized);}
}

