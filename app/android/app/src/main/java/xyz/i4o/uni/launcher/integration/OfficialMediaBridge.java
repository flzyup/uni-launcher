package xyz.i4o.uni.launcher.integration;

import android.app.PendingIntent;
import android.content.Context;
import android.content.Intent;
import android.content.ComponentName;
import android.content.ServiceConnection;
import android.os.IBinder;
import android.content.pm.PackageManager;
import android.media.MediaMetadata;
import android.media.session.MediaController;
import android.media.session.PlaybackState;
import android.os.Handler;
import android.os.Looper;
import java.lang.reflect.Method;
import java.lang.reflect.Proxy;
import java.util.Collections;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import org.json.JSONObject;

/** IP753 MediaCenter registration: DIM source selection and wheel callbacks do
 * not use Android MediaSession. Only the selected third-party online source is
 * registered here; OEM radio/USB/BT clients retain ownership of their sources.
 * OEM Binder calls run off the UI thread; synchronous getters use an immutable
 * cached sample and never wait for that same UI thread. */
public final class OfficialMediaBridge {
    public interface Commands { boolean send(String action,String source); }
    private static final int ONLINE=6;
    private final Context context;
    private final Commands commands;
    private final Runnable changed;
    private final Handler main=new Handler(Looper.getMainLooper());
    private final ExecutorService worker=Executors.newSingleThreadExecutor();
    private volatile Sample sample=Sample.EMPTY;
    private volatile boolean running,registered,playbackAccepted,playClaimed,apiReady;
    private volatile String reason="未连接原车媒体中心";
    private volatile int callbackCount;
    private volatile String lastCallback="";
    private volatile int generation;
    private Object api,client,playback,wireClient,wirePlayback,mediaInfo;
    private Class<?> mediaInfoType;
    private String lastTrack="";
    private boolean waitingForSource;
    private final Runnable emptySource=()->{waitingForSource=false;sample=Sample.EMPTY;if(running)worker.execute(()->publish(Sample.EMPTY));};
    private volatile boolean bound;
    private ServiceConnection connection;
    private volatile Object token;
    private Class<?> apiType,clientType,playbackType;
    private boolean initialized;
    private String lastSource="";
    private boolean lastPlaying;
    private long lastProgressAt;

    public OfficialMediaBridge(Context context,Commands commands,Runnable changed){
        this.context=context.getApplicationContext();this.commands=commands;this.changed=changed;
    }
    public void update(MediaController controller){
        Sample next=Sample.from(context,controller);
        if(!next.available&&running&&sample.available){
            if(!waitingForSource){waitingForSource=true;main.postDelayed(emptySource,2500);}return;
        }
        main.removeCallbacks(emptySource);waitingForSource=false;sample=next;
        if(!running)return;
        worker.execute(()->publish(next));
    }
    public void start(){running=true;worker.execute(()->{initialize();publish(sample);});}
    public void stop(){
        running=false;generation++;main.removeCallbacks(emptySource);waitingForSource=false;sample=Sample.EMPTY;worker.execute(()->{
            release();
            if(bound&&connection!=null)try{context.unbindService(connection);}catch(RuntimeException ignored){}
            bound=false;apiReady=false;initialized=false;api=null;connection=null;
        });
    }
    private void notifyChanged(){main.post(changed);}
    private void initialize(){
        if(initialized||!running)return;
        initialized=true;
        try{
            if(context.checkSelfPermission("ecarx.oem.permission.OPENAPI_MEDIACENTER_PERMISSION")!=PackageManager.PERMISSION_GRANTED){reason="原车媒体中心权限未授予";return;}
            ClassLoader loader=context.getClassLoader();
            try{apiType=Class.forName("com.ecarx.sdk.mediacenter.MediaCenterAPI",true,loader);}
            catch(ClassNotFoundException e){loader=context.createPackageContext("com.ecarx.systemui.plugin",Context.CONTEXT_INCLUDE_CODE|Context.CONTEXT_IGNORE_SECURITY).getClassLoader();apiType=Class.forName("com.ecarx.sdk.mediacenter.MediaCenterAPI",true,loader);}
            loader=apiType.getClassLoader();
            clientType=Class.forName("com.ecarx.sdk.mediacenter.IMusicClient",true,loader);
            playbackType=Class.forName("com.ecarx.sdk.mediacenter.IMusicPlaybackInfo",true,loader);
            mediaInfoType=Class.forName("com.ecarx.sdk.mediacenter.IMediaInfo",true,loader);
            final int session=generation;
            playback=Proxy.newProxyInstance(loader,new Class<?>[]{playbackType},(p,m,a)->session==generation?playbackValue(p,m,a):defaultValue(m.getReturnType()));
            mediaInfo=Proxy.newProxyInstance(loader,new Class<?>[]{mediaInfoType},(p,m,a)->session==generation?playbackValue(p,m,a):defaultValue(m.getReturnType()));
            client=Proxy.newProxyInstance(loader,new Class<?>[]{clientType},(p,m,a)->session==generation?clientValue(p,m,a):defaultValue(m.getReturnType()));
            // IP753 declares the SDK's legacy IMusicClient wrapper constructor
            // package-private, although the wrapper itself is public.
            java.lang.reflect.Constructor<?> wrapClient=Class.forName("com.ecarx.sdk.mediacenter.MusicClientWrapper",true,loader).getDeclaredConstructor(clientType);
            wrapClient.setAccessible(true);wireClient=wrapClient.newInstance(client);
            wirePlayback=Class.forName("com.ecarx.sdk.mediacenter.PlaybackInfoWrapper",true,loader).getConstructor(playbackType).newInstance(playback);
            final ClassLoader serviceLoader=loader;
            connection=new ServiceConnection(){
                @Override public void onServiceConnected(ComponentName name,IBinder binder){
                    worker.execute(()->{
                        if(!running||session!=generation)return;
                        try{
                            apiType=Class.forName("ecarx.xsf.mediacenter.IMediaCenterSvc",true,serviceLoader);
                            api=Class.forName("ecarx.xsf.mediacenter.IMediaCenterSvc$Stub",true,serviceLoader).getMethod("asInterface",IBinder.class).invoke(null,binder);
                            apiReady=api!=null;register();publish(sample);
                        }catch(Exception|LinkageError e){reason="原车媒体Binder连接失败："+root(e).getClass().getSimpleName();android.util.Log.w("UniOemMedia",reason,e);notifyChanged();}
                    });
                }
                @Override public void onServiceDisconnected(ComponentName name){
                    if(session!=generation)return;
                    apiReady=false;registered=false;playbackAccepted=false;playClaimed=false;token=null;reason="原车媒体服务已断开";notifyChanged();
                }
            };
            reason="正在连接原车媒体中心";
            bound=context.bindService(new Intent("ecarx.xsf.MEDIA_CENTER_SERVICE").setComponent(new ComponentName("ecarx.xsf.mediacenter","ecarx.xsf.mediacenter.MediaCenterService")),connection,Context.BIND_AUTO_CREATE);
            if(!bound){reason="原车媒体中心未接受服务绑定";notifyChanged();}
        }catch(Exception|LinkageError e){reason="原车媒体接入失败："+root(e).getClass().getSimpleName();android.util.Log.w("UniOemMedia",reason,e);notifyChanged();}
    }
    private void register(){
        if(!running||!sample.available||registered||api==null)return;
        try{
            token=invoke("registerMusic",wireClient);
            registered=token!=null;
            reason=registered?"":"原车媒体注册未返回令牌";
            if(registered)invoke("updateMediaSourceTypeList",token,new int[]{ONLINE});
            android.util.Log.i("UniOemMedia","Registered="+registered);
        }catch(Exception|LinkageError e){reason="原车媒体注册失败："+root(e).getClass().getSimpleName();android.util.Log.w("UniOemMedia",reason,e);}
        notifyChanged();
    }
    private void publish(Sample next){
        if(!running)return;
        if(!next.available){if(registered)release();return;}
        if(!initialized)initialize();
        if(!registered&&apiReady)register();
        if(!registered)return;
        try{
            boolean stateChanged=next.playing!=lastPlaying;
            boolean acquire=next.playing&&(!lastPlaying||!next.source.equals(lastSource));
            lastSource=next.source;lastPlaying=next.playing;
            if(acquire){
                playClaimed=Boolean.TRUE.equals(invoke("requestPlay",token));
                if(playClaimed)invoke("updateCurrentSourceType",token,ONLINE);
            }
            String track=next.source+"\n"+next.title+"\n"+next.artist+"\n"+next.duration;
            boolean trackChanged=!track.equals(lastTrack);
            if(trackChanged){
                java.lang.reflect.Method wrap=Class.forName("com.ecarx.sdk.mediacenter.MediaBeanHelper",true,clientType.getClassLoader()).getDeclaredMethod("getIMediaList",java.util.List.class);
                wrap.setAccessible(true);
                Object queue=wrap.invoke(null,Collections.singletonList(mediaInfo));
                invoke("updatePlaylist",token,ONLINE,queue);lastTrack=track;
            }
            if(trackChanged||stateChanged||acquire)playbackAccepted=Boolean.TRUE.equals(invoke("updateMusicPlaybackState",token,wirePlayback));
            long now=android.os.SystemClock.elapsedRealtime();
            if(now-lastProgressAt>=1000){lastProgressAt=now;invoke("updateCurrentProgress",token,next.position);}
            reason=playbackAccepted?"":"原车媒体未接受播放信息";
            android.util.Log.d("UniOemMedia","Playback accepted="+playbackAccepted+", claimed="+playClaimed);
        }catch(Exception|LinkageError e){reason="原车媒体同步失败："+root(e).getClass().getSimpleName();android.util.Log.w("UniOemMedia",reason,e);}
    }
    private Object clientValue(Object proxy,Method method,Object[] args){
        Object object=objectMethod(proxy,method,args);if(object!=null)return object;
        Sample current=sample;
        switch(method.getName()){
            case "getCurrentProgress":return current.position;
            case "getCurrentSourceType":return current.available?ONLINE:-1;
            case "getMediaSourceTypeList":return new int[]{ONLINE};
            case "getMusicPlaybackInfo":return playback;
            // The standard session exposes a real current item, not necessarily the
            // player's complete queue. Supply only that item to DIM.
            case "getPlaylist":return current.available&&args!=null&&args.length>0&&args[0] instanceof Number&&((Number)args[0]).intValue()==ONLINE?Collections.singletonList(mediaInfo):Collections.emptyList();
            case "onNext":return dispatch("next");
            case "onPrevious":return dispatch("previous");
            case "onPlay":return dispatch("play");
            case "onPause":return dispatch("pause");
            case "onSourceSelected":return args!=null&&args.length>0&&args[0] instanceof Number&&((Number)args[0]).intValue()==ONLINE&&dispatch("play");
            default:return defaultValue(method.getReturnType());
        }
    }
    private boolean dispatch(String action){
        if(!running||!sample.available)return false;
        callbackCount++;lastCallback=action;
        android.util.Log.i("UniOemMedia","OEM transport callback="+action);
        String source=sample.source;int session=generation;
        main.post(()->{if(running&&session==generation&&sample.available&&source.equals(sample.source)){commands.send(action,source);changed.run();}});return true;
    }
    private Object playbackValue(Object proxy,Method method,Object[] args){
        Object object=objectMethod(proxy,method,args);if(object!=null)return object;
        Sample s=sample;
        switch(method.getName()){
            case "getTitle":return s.title;
            case "getArtist":return s.artist;
            case "getAlbum":return s.album;
            case "getDuration":return s.duration;
            case "getPlayingItemPositionInQueue":return 0;
            case "getSourceType":return ONLINE;
            case "getPlaybackStatus":return s.playing?1:0;
            case "getLaunchIntent":return s.launch;
            case "getCurrentLyricSentence":case "getLyricContent":case "getRadioFrequency":case "getRadioStationName":return "";
            default:return defaultValue(method.getReturnType());
        }
    }
    private void release(){
        try{if(api!=null&&token!=null)invoke("unregister",token);}catch(Exception|LinkageError ignored){}
        token=null;registered=false;playbackAccepted=false;playClaimed=false;lastSource="";lastTrack="";lastPlaying=false;
    }
    private Object invoke(String name,Object... args)throws Exception{
        for(Method method:apiType.getMethods()){
            if(!name.equals(method.getName())||method.getParameterTypes().length!=args.length)continue;
            Class<?>[] types=method.getParameterTypes();boolean match=true;
            for(int i=0;i<types.length;i++){
                if(args[i]==null)continue;
                if(types[i]==int.class&&args[i] instanceof Integer||types[i]==long.class&&args[i] instanceof Long)continue;
                if(!types[i].isInstance(args[i])){match=false;break;}
            }
            if(match)return method.invoke(api,args);
        }
        throw new NoSuchMethodException(name);
    }
    public JSONObject snapshot(){
        JSONObject out=new JSONObject();try{out.put("registered",registered).put("playbackAccepted",playbackAccepted).put("playClaimed",playClaimed)
            .put("bound",bound).put("sourceType",sample.available?ONLINE:-1).put("callbackCount",callbackCount).put("lastCallback",lastCallback).put("reason",reason);}catch(Exception ignored){}return out;
    }
    static Object defaultValue(Class<?> type){
        if(type==boolean.class)return false;if(type==int.class)return 0;if(type==long.class)return 0L;if(type==float.class)return 0f;if(type==double.class)return 0d;return null;
    }
    private static Object objectMethod(Object proxy,Method method,Object[] args){
        if("hashCode".equals(method.getName()))return System.identityHashCode(proxy);
        if("equals".equals(method.getName()))return args!=null&&args.length>0&&proxy==args[0];
        if("toString".equals(method.getName()))return "UNI official media client";return null;
    }
    private static Throwable root(Throwable e){while(e.getCause()!=null&&e.getCause()!=e)e=e.getCause();return e;}
    private static final class Sample {
        static final Sample EMPTY=new Sample(false,false,"","","","",0,0,null);
        final boolean available,playing;final String source,title,artist,album;final long position,duration;final PendingIntent launch;
        Sample(boolean available,boolean playing,String source,String title,String artist,String album,long position,long duration,PendingIntent launch){this.available=available;this.playing=playing;this.source=source;this.title=title;this.artist=artist;this.album=album;this.position=position;this.duration=duration;this.launch=launch;}
        static Sample from(Context context,MediaController c){
            if(c==null)return EMPTY;
            String pkg=c.getPackageName();
            // These are the installed external online players already handled by
            // our controller. Never pose as the original radio/BT/USB owner.
            if(!"com.netease.cloudmusic.iot".equals(pkg)&&!"com.tencent.qqmusiccar".equals(pkg)&&!"com.tencent.qqmusic".equals(pkg))return EMPTY;
            try{
                MediaMetadata m=c.getMetadata();PlaybackState p=c.getPlaybackState();
                Intent intent=context.getPackageManager().getLaunchIntentForPackage(pkg);
                PendingIntent launch=intent==null?null:PendingIntent.getActivity(context,1,intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),PendingIntent.FLAG_UPDATE_CURRENT);
                return new Sample(p!=null,p!=null&&p.getState()==PlaybackState.STATE_PLAYING,pkg,text(m,MediaMetadata.METADATA_KEY_TITLE),text(m,MediaMetadata.METADATA_KEY_ARTIST),text(m,MediaMetadata.METADATA_KEY_ALBUM),p==null?0:Math.max(0,p.getPosition()),m==null?0:Math.max(0,m.getLong(MediaMetadata.METADATA_KEY_DURATION)),launch);
            }catch(RuntimeException e){return EMPTY;}
        }
        private static String text(MediaMetadata m,String key){String value=m==null?null:m.getString(key);return value==null?"":value;}
    }
}
