package xyz.i4o.uni.launcher.integration;

import android.app.PendingIntent;
import android.content.Context;
import android.content.Intent;
import android.content.ComponentName;
import android.content.ServiceConnection;
import android.graphics.Bitmap;
import android.net.Uri;
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
import xyz.i4o.uni.launcher.log.LogTags;
import xyz.i4o.uni.launcher.log.UniLog;

/** MediaCenter registration: DIM source selection and wheel callbacks do
 * not use Android MediaSession. Publish the selected supported player or the
 * active platform Bluetooth session; radio and USB remain with their owners.
 * OEM Binder calls run off the UI thread; synchronous getters use an immutable
 * cached sample and never wait for that same UI thread. */
public final class OfficialMediaBridge {
    public interface Commands { boolean send(String action,String source); }
    private static final int ONLINE=6;
    private static final int BLUETOOTH=2;
    private final Context context;
    private final Commands commands;
    private final Runnable changed;
    private final Handler main=new Handler(Looper.getMainLooper());
    private final ExecutorService worker=Executors.newSingleThreadExecutor();
    private volatile Sample sample=Sample.EMPTY;
    private volatile boolean running,registered,playbackAccepted,playClaimed,apiReady;
    private volatile String reason="未连接原车媒体中心";
    /** 设置页「仪表同步」的开关，默认开。关掉即反注册解绑，仪表交回原车播放器。 */
    private volatile boolean enabled=true;
    private volatile int callbackCount;
    private volatile String lastCallback="";
    private volatile int generation;
    private volatile String onlineSource="";
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
    private int registeredType=-1;
    private long lastProgressAt;
    /** 上次推给原车的封面版本：封面晚到（播放器后补图）时也要立刻重推一次。 */
    private int lastArtVersion;
    /**
     * 抢占保底。原车媒体中心的焦点会被别的客户端抢走，而本地链路一个状态都没变，
     * {@link #publish} 因此不会重发，仪表上的卡片就悄悄换人了。
     * 只补不抢：焦点还在自己手上时什么都不做，丢了才重新 requestPlay。
     */
    private static final long CLAIM_KEEPALIVE_MS=25_000;
    private volatile String focusOwner="";
    private final Runnable keepalive=()->{
        if(!running||!registered||token==null)return;
        worker.execute(this::reclaim);
    };

    public OfficialMediaBridge(Context context,Commands commands,Runnable changed){
        this.context=context.getApplicationContext();this.commands=commands;this.changed=changed;
    }
    public void setOnlineSource(String source){
        String next=source==null?"":source;
        if(next.equals(onlineSource))return;
        onlineSource=next;
        if(running)worker.execute(()->publish(sample));
    }
    /** Claim the current sample's source without fabricating playback state. */
    public void claimCurrent(){
        if(!running||!enabled)return;
        worker.execute(()->{claim();scheduleKeepalive();});
    }
    /** 断言"当前音源是我"，并把播放信息重新推一遍。OEM Binder 调用，跑在 worker 上。 */
    private void claim(){
        if(!running||!registered||token==null||!sample.available)return;
        try{
            playClaimed=Boolean.TRUE.equals(invoke("requestPlay",token));
            if(playClaimed){
                invoke("updateCurrentSourceType",token,sample.type);
                playbackAccepted=Boolean.TRUE.equals(invoke("updateMusicPlaybackState",token,wirePlayback));
            }
            reason=playbackAccepted?"":"原车媒体未接受音源切换";
            notifyChanged();
        }catch(Exception|LinkageError e){reason="原车音源切换失败："+root(e).getClass().getSimpleName();android.util.Log.w("UniOemMedia",reason,e);}
    }
    /** 保底心跳：焦点丢了才重新抢占，一秒不多抢。 */
    private void reclaim(){
        if(!running||!enabled||!registered||token==null)return;
        try{
            String owner=focusOwner();
            if(!owner.isEmpty()&&owner.contains(context.getPackageName())){scheduleKeepalive();return;}
            android.util.Log.i("UniOemMedia","claim keepalive focus="+(owner.isEmpty()?"unknown":owner));
            claim();
        }finally{scheduleKeepalive();}
    }
    private void scheduleKeepalive(){
        main.removeCallbacks(keepalive);
        if(running&&registered)main.postDelayed(keepalive,CLAIM_KEEPALIVE_MS);
    }
    /**
     * 当前霸占原车媒体焦点的客户端。这辆车的 SDK 不一定有这个方法，
     * 查不到就返回空串——按"未知"处理，照样补抢。
     */
    private String focusOwner(){
        if(token==null)return "";
        try{focusOwner=String.valueOf(invoke("queryCurrentFocusClient",token));}
        catch(Exception|LinkageError ignored){focusOwner="";}
        return focusOwner;
    }
    private int[] sourceTypes(Sample current){
        if(!current.available)return new int[0];
        return !onlineSource.isEmpty()?new int[]{BLUETOOTH,ONLINE}:new int[]{current.type};
    }
    private String sourceTypesKey(Sample current){return java.util.Arrays.toString(sourceTypes(current));}
    private String registeredTypes="";
    public void update(MediaController controller){
        if(!enabled)return;
        Sample next=Sample.from(context,controller);
        if(!next.available&&running&&sample.available){
            if(!waitingForSource){waitingForSource=true;main.postDelayed(emptySource,2500);}return;
        }
        main.removeCallbacks(emptySource);waitingForSource=false;sample=next;
        UniLog.d(LogTags.MEDIA,"原车媒体取样","available",next.available,"playing",next.playing,"source",next.source,"title",next.title,"running",running,"registered",registered);
        if(!running)return;
        worker.execute(()->publish(next));
    }
    /**
     * 设置页「仪表同步」开关：关掉后立刻反注册并解绑原车媒体中心，仪表跟回原车播放器，
     * 桌面不再往上写曲目/封面/进度。重新打开时按当前音源重新注册。
     */
    public void setEnabled(boolean next){
        if(enabled==next)return;
        enabled=next;
        if(!next){stop();reason="仪表同步已关闭";notifyChanged();}
        else start();
    }
    public boolean enabled(){return enabled;}
    public void start(){
        if(!enabled)return;
        running=true;worker.execute(()->{initialize();publish(sample);});
    }
    public void stop(){
        running=false;generation++;
        main.removeCallbacks(keepalive);main.removeCallbacks(emptySource);waitingForSource=false;sample=Sample.EMPTY;worker.execute(()->{
            release();
            if(bound&&connection!=null)try{context.unbindService(connection);}catch(RuntimeException ignored){}
            bound=false;apiReady=false;initialized=false;api=null;connection=null;
        });
        UniLog.done(LogTags.MEDIA,"media/oem-session","action","unbind","tag","UniOemMedia");
    }
    private void notifyChanged(){main.post(changed);}
    private final java.util.Set<String> askedMethods=java.util.Collections.synchronizedSet(new java.util.TreeSet<>());
    private void initialize(){
        if(initialized||!running)return;
        initialized=true;
        UniLog.enter(LogTags.MEDIA,"media/oem-session","action","bind","tag","UniOemMedia");
        try{
            if(context.checkSelfPermission("ecarx.oem.permission.OPENAPI_MEDIACENTER_PERMISSION")!=PackageManager.PERMISSION_GRANTED){
                reason="原车媒体中心权限未授予";
                UniLog.fail(LogTags.MEDIA,"media/oem-session","reason","oem-permission-denied","permission","ecarx.oem.permission.OPENAPI_MEDIACENTER_PERMISSION");
                return;
            }
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
            // 原车到底会问封面相关的哪些方法，只能靠它自己调过来时记一笔。
            for(Method m:playbackType.getMethods())askedMethods.add("info."+m.getName());
            for(Method m:clientType.getMethods())askedMethods.add("client."+m.getName());
            // 原车究竟暴露了哪些字段（尤其封面叫什么）只能从运行时摸，编译期没有 SDK。
            StringBuilder info=new StringBuilder(),cli=new StringBuilder();
            for(Method m:playbackType.getMethods())info.append(info.length()==0?"":",").append(m.getName()).append(':').append(m.getReturnType().getSimpleName());
            for(Method m:clientType.getMethods())cli.append(cli.length()==0?"":",").append(m.getName());
            UniLog.i(LogTags.MEDIA,"原车媒体接口清单","info",info.toString(),"client",cli.toString());
            UniLog.d(LogTags.MEDIA,"原车媒体接口方法","playback",playbackType.getMethods().length,"client",clientType.getMethods().length);
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
                        }catch(Exception|LinkageError e){reason="原车媒体Binder连接失败："+root(e).getClass().getSimpleName();UniLog.w(LogTags.MEDIA,reason,e,"tag","UniOemMedia","stage","binder-connect");UniLog.fail(LogTags.MEDIA,"media/oem-session","reason","binder-connect-failed","error",root(e).getClass().getSimpleName());notifyChanged();}
                    });
                }
                @Override public void onServiceDisconnected(ComponentName name){
                    if(session!=generation)return;
apiReady=false;registered=false;registeredType=-1;registeredTypes="";playbackAccepted=false;playClaimed=false;token=null;reason="原车媒体服务已断开";
                    UniLog.fail(LogTags.MEDIA,"media/oem-session","reason","service-disconnected","component",name==null?"":name.getPackageName());
                    notifyChanged();
                }
            };
            reason="正在连接原车媒体中心";
            bound=context.bindService(new Intent("ecarx.xsf.MEDIA_CENTER_SERVICE").setComponent(new ComponentName("ecarx.xsf.mediacenter","ecarx.xsf.mediacenter.MediaCenterService")),connection,Context.BIND_AUTO_CREATE);
            if(!bound){reason="原车媒体中心未接受服务绑定";UniLog.fail(LogTags.MEDIA,"media/oem-session","reason","bind-refused","component","ecarx.xsf.mediacenter");notifyChanged();}
            else UniLog.done(LogTags.MEDIA,"media/oem-session","action","bind","bound",true,"tag","UniOemMedia");
        }catch(Exception|LinkageError e){reason="原车媒体接入失败："+root(e).getClass().getSimpleName();UniLog.w(LogTags.MEDIA,reason,e,"tag","UniOemMedia","stage","initialize");UniLog.fail(LogTags.MEDIA,"media/oem-session","reason","initialize-failed","error",root(e).getClass().getSimpleName());notifyChanged();}
    }
    private void register(){
        if(!running||!enabled||!sample.available||registered||api==null){
            UniLog.d(LogTags.MEDIA,"原车媒体跳过注册","running",running,"enabled",enabled,
                "available",sample.available,"registered",registered,"api",api!=null,"apiReady",apiReady);
            return;
        }
        try{
            token=invoke("registerMusic",wireClient);
            registered=token!=null;
            reason=registered?"":"原车媒体注册未返回令牌";
if(registered){registeredType=sample.type;invoke("updateMediaSourceTypeList",token,sourceTypes(sample));registeredTypes=sourceTypesKey(sample);}
            UniLog.i(LogTags.MEDIA,"原车媒体注册结果","tag","UniOemMedia","registered",registered,"token",token!=null,"sourceType",registeredType);
            if(registered)UniLog.done(LogTags.MEDIA,"media/oem-session","action","register","sourceType",registeredType);
            else UniLog.fail(LogTags.MEDIA,"media/oem-session","action","register","reason","no-token");
            // 25 秒保底心跳：只在焦点已经不在自己手上时才重新抢占，见 requestPlay。
            if(registered)scheduleKeepalive();
        }catch(Exception|LinkageError e){reason="原车媒体注册失败："+root(e).getClass().getSimpleName();UniLog.w(LogTags.MEDIA,reason,e,"tag","UniOemMedia","stage","register");UniLog.fail(LogTags.MEDIA,"media/oem-session","action","register","reason","register-failed","error",root(e).getClass().getSimpleName());}
        notifyChanged();
    }
    private void publish(Sample next){
        if(!running||!enabled)return;
        if(!next.available){if(registered)release();return;}
        if(!initialized)initialize();
        if(!registered&&apiReady)register();
        if(!registered)return;
        try{
            String types=sourceTypesKey(next);
            if(registeredType!=next.type||!registeredTypes.equals(types)){invoke("updateMediaSourceTypeList",token,sourceTypes(next));registeredType=next.type;registeredTypes=types;}
            boolean stateChanged=next.playing!=lastPlaying;
            boolean acquire=next.playing&&(!lastPlaying||!next.source.equals(lastSource));
            lastSource=next.source;lastPlaying=next.playing;
            if(acquire){
                playClaimed=Boolean.TRUE.equals(invoke("requestPlay",token));
                if(playClaimed)invoke("updateCurrentSourceType",token,next.type);
            }
            String track=next.source+"\n"+next.title+"\n"+next.artist+"\n"+next.duration;
            boolean trackChanged=!track.equals(lastTrack);
            if(trackChanged){
                java.lang.reflect.Method wrap=Class.forName("com.ecarx.sdk.mediacenter.MediaBeanHelper",true,clientType.getClassLoader()).getDeclaredMethod("getIMediaList",java.util.List.class);
                wrap.setAccessible(true);
                Object queue=wrap.invoke(null,Collections.singletonList(mediaInfo));
                invoke("updatePlaylist",token,next.type,queue);lastTrack=track;
            }
            boolean push=trackChanged||stateChanged||acquire||lastArtVersion!=artworkVersion.get();
            if(push)lastArtVersion=artworkVersion.get();
            if(push)UniLog.enter(LogTags.MEDIA,"media/oem-playback","source",next.source,"trackChanged",trackChanged,"stateChanged",stateChanged,"acquire",acquire);
            if(push)playbackAccepted=Boolean.TRUE.equals(invoke("updateMusicPlaybackState",token,wirePlayback));
            long now=android.os.SystemClock.elapsedRealtime();
            if(now-lastProgressAt>=1000){lastProgressAt=now;invoke("updateCurrentProgress",token,next.position);}
            reason=playbackAccepted?"":"原车媒体未接受播放信息";
            if(push){
                if(playbackAccepted)UniLog.done(LogTags.MEDIA,"media/oem-playback","source",next.source,"claimed",playClaimed);
                else UniLog.fail(LogTags.MEDIA,"media/oem-playback","reason","oem-rejected-playback","source",next.source);
            }
            UniLog.d(LogTags.MEDIA,"原车媒体播放信息同步","tag","UniOemMedia","playbackAccepted",playbackAccepted,"claimed",playClaimed);
        }catch(Exception|LinkageError e){reason="原车媒体同步失败："+root(e).getClass().getSimpleName();UniLog.w(LogTags.MEDIA,reason,e,"tag","UniOemMedia","stage","publish");UniLog.fail(LogTags.MEDIA,"media/oem-playback","reason","publish-failed","error",root(e).getClass().getSimpleName());}
    }
    private Object clientValue(Object proxy,Method method,Object[] args){
        Object object=objectMethod(proxy,method,args);if(object!=null)return object;
        Sample current=sample;
        switch(method.getName()){
            case "getCurrentProgress":return current.position;
            case "getCurrentSourceType":return current.available?current.type:-1;
            case "getMediaSourceTypeList":return sourceTypes(current);
            case "getMusicPlaybackInfo":return playback;
            // The standard session exposes a real current item, not necessarily the
            // player's complete queue. Supply only that item to DIM.
            case "getPlaylist":return current.available&&args!=null&&args.length>0&&args[0] instanceof Number&&((Number)args[0]).intValue()==current.type?Collections.singletonList(mediaInfo):Collections.emptyList();
            case "onNext":return dispatch("next");
            case "onPrevious":return dispatch("previous");
            case "onPlay":return dispatch("play");
            case "onPause":return dispatch("pause");
            case "onSourceSelected":
                if(!current.available||args==null||args.length==0||!(args[0] instanceof Number))return false;
                int selected=((Number)args[0]).intValue();
                if(selected==current.type)return dispatch("play");
                if(selected==ONLINE&&current.type==BLUETOOTH&&!onlineSource.isEmpty()){
                    String source=onlineSource;int session=generation;
                    main.post(()->{if(running&&session==generation&&source.equals(onlineSource))commands.send("select-online",source);});
                    return true;
                }
                if(selected==BLUETOOTH&&current.type==ONLINE&&!onlineSource.isEmpty()){
                    int session=generation;
                    main.post(()->{if(running&&session==generation)commands.send("select-bluetooth","com.android.bluetooth");});
                    return true;
                }
                return false;
            default:return defaultValue(method.getReturnType());
        }
    }
    private boolean dispatch(String action){
        if(!running||!sample.available)return false;
        callbackCount++;lastCallback=action;
        UniLog.event(LogTags.MEDIA,"原车媒体透传播放控制","action",action,"tag","UniOemMedia","source",sample.source);
        UniLog.enter(LogTags.MEDIA,"media/oem-transport","action",action,"source",sample.source);
        String source=sample.source;int session=generation;
        main.post(()->{if(running&&session==generation&&sample.available&&source.equals(sample.source)){
            boolean accepted=commands.send(action,source);
            if(accepted)UniLog.done(LogTags.MEDIA,"media/oem-transport","action",action,"source",source);
            else UniLog.fail(LogTags.MEDIA,"media/oem-transport","action",action,"source",source,"reason","not-accepted");
            changed.run();}});return true;
    }
    /** 当前封面从哪来（MediaAdapter 注入）；原车要的是 URI，这里负责落盘 + 授权。 */
    private static volatile java.util.function.Supplier<Bitmap> artworkSupplier;
    /** 这张封面属于哪一首（标题|歌手|mediaId）：桥自己的 sample 可能落后半拍，命名以它为准。 */
    private static volatile java.util.function.Supplier<String> artworkOwner;
    static void artworkSource(java.util.function.Supplier<Bitmap> supplier,java.util.function.Supplier<String> owner){
        artworkSupplier=supplier;artworkOwner=owner;
    }
    /** 曲目或封面换了一份：让下一次 getArtwork 重新落盘，别把旧图当新的发出去。 */
    private static final java.util.concurrent.atomic.AtomicInteger artworkVersion=new java.util.concurrent.atomic.AtomicInteger(1);
    static void invalidateArtwork(){artworkVersion.incrementAndGet();}
    /** 可能来取封面的进程：原车媒体中心、仪表服务。 */
    private static final String[] ARTWORK_READERS={"ecarx.xsf.mediacenter","se.cevt.dimsupportservice","ecarx.launcher3"};
    private String artworkKey="";
    private Uri artworkUri;
    private Uri artworkUri(){
        java.util.function.Supplier<Bitmap> supplier=artworkSupplier;
        Bitmap bitmap=null;
        try{bitmap=supplier==null?null:supplier.get();}catch(RuntimeException|OutOfMemoryError ignored){}
        if(bitmap==null||bitmap.isRecycled())return null;
        // 注意：不能拿位图的 identityHashCode 当 key —— MediaMetadata.getBitmap() 每次
        // 都新建一个 Bitmap，那样每次都会写出新文件、原车跟着重新下载同一张图。
        String owner="";
        try{owner=artworkOwner==null?"":String.valueOf(artworkOwner.get());}catch(RuntimeException ignored){}
        if(owner.isEmpty())owner=sample.title+"\u0000"+sample.artist;
        String key=owner+"\u0000"+artworkVersion.get();
        if(artworkUri!=null&&key.equals(artworkKey))return artworkUri;
        try{
            java.io.File dir=ArtworkFileProvider.dir(context);
            pruneArtwork(dir);
            String name="cover_"+Math.abs(key.hashCode())+".png";
            java.io.File file=new java.io.File(dir,name);
            if(!file.isFile()||file.length()==0){
                // 原车读图的进程流量不大，但没必要塞原尺寸图：512px 已经足够清楚。
                Bitmap scaled=bitmap;
                int longest=Math.max(bitmap.getWidth(),bitmap.getHeight());
                if(longest>512){
                    float ratio=512f/longest;
                    scaled=Bitmap.createScaledBitmap(bitmap,Math.max(1,(int)(bitmap.getWidth()*ratio)),Math.max(1,(int)(bitmap.getHeight()*ratio)),true);
                }
                java.io.ByteArrayOutputStream bytes=new java.io.ByteArrayOutputStream();
                scaled.compress(Bitmap.CompressFormat.PNG,100,bytes);
                if(scaled!=bitmap)scaled.recycle();
                java.io.FileOutputStream out=new java.io.FileOutputStream(file);
                try{out.write(bytes.toByteArray());}finally{out.close();}
            }
            Uri uri=ArtworkFileProvider.uriFor(name);
            for(String reader:ARTWORK_READERS)
                try{context.grantUriPermission(reader,uri,Intent.FLAG_GRANT_READ_URI_PERMISSION);}catch(RuntimeException ignored){}
            artworkUri=uri;artworkKey=key;
            UniLog.i(LogTags.MEDIA,"封面 URI 已就绪","name",name,"title",sample.title,"bytes",file.length());
            return uri;
        }catch(Exception|OutOfMemoryError e){
            UniLog.w(LogTags.MEDIA,"封面 URI 生成失败","title",sample.title,"error",e.getClass().getSimpleName());
            return null;
        }
    }
    /** 当前歌词（MediaAdapter 注入）；原车 getLyric 要文件 URI，getLyricContent 要文本。 */
    private static volatile java.util.function.Supplier<String> lyricSupplier;
    static void lyricSource(java.util.function.Supplier<String> supplier){lyricSupplier=supplier;}
    private String lyricKey="";
    private Uri lyricUri;
    private Uri lyricUri(){
        java.util.function.Supplier<String> supplier=lyricSupplier;
        String text=null;
        try{text=supplier==null?null:supplier.get();}catch(RuntimeException ignored){}
        if(text==null||text.isEmpty())return null;
        String key=text.length()+"\u0000"+text.hashCode();
        if(lyricUri!=null&&key.equals(lyricKey))return lyricUri;
        try{
            java.io.File dir=ArtworkFileProvider.dir(context);
            String name="lyric_"+Math.abs(key.hashCode())+".lrc";
            java.io.File file=new java.io.File(dir,name);
            if(!file.isFile()||file.length()==0){
                java.io.FileOutputStream out=new java.io.FileOutputStream(file);
                try{out.write(text.getBytes("UTF-8"));}finally{out.close();}
            }
            Uri uri=ArtworkFileProvider.uriFor(name);
            for(String reader:ARTWORK_READERS)
                try{context.grantUriPermission(reader,uri,Intent.FLAG_GRANT_READ_URI_PERMISSION);}catch(RuntimeException ignored){}
            lyricUri=uri;lyricKey=key;
            UniLog.i(LogTags.MEDIA,"歌词 URI 已就绪","name",name,"chars",text.length());
            return uri;
        }catch(Exception e){
            UniLog.w(LogTags.MEDIA,"歌词 URI 生成失败","error",e.getClass().getSimpleName());
            return null;
        }
    }
    /** 每换一首/每换一张图就是一个文件，顺手把旧封面清掉，别把缓存堆满。 */
    private static void pruneArtwork(java.io.File dir){
        java.io.File[] files=dir.listFiles();
        if(files==null||files.length<24)return;
        java.util.Arrays.sort(files,(a,b)->Long.compare(a.lastModified(),b.lastModified()));
        for(int i=0;i<files.length-16;i++)if(files[i].isFile()&&!files[i].delete())break;
    }
    private Object playbackValue(Object proxy,Method method,Object[] args){
        Object object=objectMethod(proxy,method,args);if(object!=null)return object;
        Sample s=sample;
        // 仪表/原车要封面时会调到这里来；把真实被调用的方法名记下来（每个只记一次），
        // 用来确定 IMusicPlaybackInfo 上封面字段到底叫什么，而不是靠猜。
        if(askedMethods.add("called."+method.getName()))
            UniLog.d(LogTags.MEDIA,"原车媒体问字段","name",method.getName(),"type",method.getReturnType().getSimpleName());
        switch(method.getName()){
            case "getTitle":return s.title;
            case "getArtist":return s.artist;
            case "getAlbum":return s.album;
            case "getDuration":return s.duration;
            case "getPlayingItemPositionInQueue":return 0;
            case "getSourceType":return s.type;
            case "getPlaybackStatus":return s.playing?1:0;
            case "getLaunchIntent":return s.launch;
            case "getCurrentLyricSentence":case "getRadioFrequency":case "getRadioStationName":return "";
            case "getLyricContent":{java.util.function.Supplier<String> supplier=lyricSupplier;
                String text=null;try{text=supplier==null?null:supplier.get();}catch(RuntimeException ignored){}
                return text==null?"":text;}
            case "getLyric":return lyricUri();
            // 原车要的是 URI：getArtwork/getNextArtwork/getPreviousArtwork 全部指到同一张
            // content:// 上（当前只有一张封面），由 ArtworkFileProvider 只读提供，
            // 被读时会在日志里留下调用方包名。
            case "getArtwork":case "getNextArtwork":case "getPreviousArtwork":return artworkUri();
            default:return defaultValue(method.getReturnType());
        }
    }
    private void release(){
        main.removeCallbacks(keepalive);
        try{if(api!=null&&token!=null)invoke("unregister",token);}catch(Exception|LinkageError ignored){}
        token=null;registered=false;registeredType=-1;registeredTypes="";playbackAccepted=false;playClaimed=false;lastSource="";lastTrack="";lastPlaying=false;
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
            .put("bound",bound).put("sourceType",sample.available?sample.type:-1).put("callbackCount",callbackCount).put("lastCallback",lastCallback)
            .put("focusOwner",focusOwner).put("keepaliveMs",CLAIM_KEEPALIVE_MS).put("enabled",enabled).put("reason",reason);}catch(Exception ignored){}return out;
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
        final boolean available,playing;final String source,title,artist,album;final long position,duration;final PendingIntent launch;final int type;
        Sample(boolean available,boolean playing,String source,String title,String artist,String album,long position,long duration,PendingIntent launch){this.available=available;this.playing=playing;this.source=source;this.title=title;this.artist=artist;this.album=album;this.position=position;this.duration=duration;this.launch=launch;this.type="com.android.bluetooth".equals(source)?BLUETOOTH:ONLINE;}
        static Sample from(Context context,MediaController c){
            if(c==null)return EMPTY;
            String pkg=c.getPackageName();
            // 以前这里只放行蓝牙 / 网易云 / QQ 音乐三家，其它播放器一律 EMPTY，
            // 结果洛雪（cn.toside.music.*）这类第三方播放器根本不会去原车媒体中心注册，
            // 仪表就没有媒体卡片、方控换歌也还在原车那边空转。现在除蓝牙按 BLUETOOTH
            // 处理，别的都按 sourceType=6（自定义源）注册，和 HY 的做法一致。
            if("".equals(pkg))return EMPTY;
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
