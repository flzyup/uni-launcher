package xyz.i4o.uni.launcher.integration;

import android.content.Context;
import android.net.Uri;
import android.os.Handler;
import android.os.Looper;
import android.os.SystemClock;

import java.lang.reflect.Method;
import java.lang.reflect.Proxy;

import org.json.JSONObject;

import xyz.i4o.uni.launcher.log.LogTags;
import xyz.i4o.uni.launcher.log.UniLog;

/**
 * 仪表（DIM）媒体通道：桌面自己的播放状态写进仪表自带的媒体控件，仪表上按的键收回桌面。
 *
 * <p>平台给的是 {@code com.ecarx.xui.adaptapi.diminteraction}（与方向盘那套 adaptapi 同族，
 * jar 在 {@code /system/framework} 的 boot classpath 上，反射直接可见）：
 * {@code DimInteraction.create(context)} → {@code getMediaInteraction()} 拿到
 * {@code IMediaInteraction}，三个入口够用：{@code updatePlaybackInfo(IPlaybackInfo)}、
 * {@code updateCurrentSourceType(int)}、{@code setMediaInteractionCallback(callback)}。
 *
 * <p>关键约束，都是从 {@code MediaInteraction} 实现里读出来的，不是猜的：
 * <ul>
 *   <li>{@code convertPlaybackInfo} 只取三样：播放状态（0 暂停 / 1 播放）、时长、队列位置。
 *       标题封面歌词不在这一路（它们走原车媒体中心，见 {@code OfficialMediaBridge}），
 *       所以这里不重复推文案。</li>
 *   <li>音源类型用 6（在线音乐），{@code getListType(6)} = 0，不会踩到
 *       「Source type does not exist」那条 {@code IndexOutOfBoundsException}。</li>
 *   <li>{@code updateCurrentProgress(long)} 平台侧是 {@code (position/duration)*100} 的整除，
 *       除满一整首之外恒为 0，是个坏接口。进度由媒体中心那条链路负责，这里不调它。</li>
 *   <li>仪表上的按键不是独立回调：{@code onPlaybackAction} 被翻译成
 *       {@code onUpdateMediaStatusRequest(数据类型)}（5 下一首 / 6 上一首 / 7 播放 / 8 暂停 /
 *       11 停止），选音源翻译成 {@code onSourceSelected(音源)}。</li>
 * </ul>
 *
 * <p>{@code getMediaInteraction()} 内部会立刻向 {@code dim_support_service} 注册回调并开始心跳，
 * 服务没绑上时构造就可能抛，所以失败只记原因、退避重试，绝不影响桌面其它功能。
 */
final class DimMediaBridge{
    interface Sink{
        /** 仪表上按了播放/暂停/上一首/下一首。 */
        void onDimKey(String action);
        /** 仪表把音源选成了 {@code sourceType}。 */
        void onDimSource(int sourceType);
    }
    private static final String ENTRY="com.ecarx.xui.adaptapi.diminteraction.DimInteraction";
    /** IMediaInteraction.SOURCE_TYPE_ONLINE。 */
    static final int SOURCE_ONLINE=6;
    private static final long RETRY_MS=3000;
    private final Context context;
    private final Sink sink;
    private final Handler main=new Handler(Looper.getMainLooper());
    private volatile boolean running;
    private volatile Object media;
    private Method updatePlaybackInfo,updateSourceType,setCallback,unsetCallback;
    private String mode="",reason="未启动";
    private long lastAttempt;
    private boolean sourceMarked;
    private int pushes,keyEvents,sourceEvents,mediaEvents,lastDataType=-1,lastSourceType=-1;
    private int pushedStatus=-1;
    private long pushedDuration=-1;
    private String pushedTrack="";

    DimMediaBridge(Context context,Sink sink){
        this.context=context;
        this.sink=sink;
    }

    boolean started(){return running;}

    /** 接入仪表媒体通道。重复调用无副作用；接入失败后每次调用按退避重试。 */
    void start(){
        if(running)return;
        running=true;
        ensure();
    }

    void stop(){
        running=false;
        Object instance=media;
        Object handler=callbackObject;
        Method off=unsetCallback;
        media=null;callbackObject=null;
        updatePlaybackInfo=null;updateSourceType=null;setCallback=null;unsetCallback=null;
        sourceMarked=false;
        if(instance!=null&&handler!=null&&off!=null){
            try{off.invoke(instance,handler);}catch(Throwable ignored){}
        }
        mode="";
        reason="已停止";
    }

    private Object callbackObject;

    /** 反射建链。失败只记原因，下次按键/发布再试。 */
    private boolean ensure(){
        if(updatePlaybackInfo!=null)return true;
        long now=SystemClock.uptimeMillis();
        if(lastAttempt!=0&&now-lastAttempt<RETRY_MS)return false;
        lastAttempt=now;
        try{
            Class<?> entry=Class.forName(ENTRY,true,context.getClassLoader());
            Object dim=entry.getMethod("create",Context.class).invoke(null,context);
            if(dim==null){reason="仪表接口未创建实例";return false;}
            Object interaction=entry.getMethod("getMediaInteraction").invoke(dim);
            if(interaction==null){reason="仪表未提供媒体通道";return false;}
            Method push=method(interaction,"updatePlaybackInfo",1);
            Method source=method(interaction,"updateCurrentSourceType",1);
            Method on=method(interaction,"setMediaInteractionCallback",1);
            Method off=method(interaction,"unsetMediaInteractionCallback",1);
            if(push==null){reason="仪表媒体通道没有 updatePlaybackInfo";return false;}
            if(on!=null){
                Class<?> callbackType=on.getParameterTypes()[0];
                Object handler=Proxy.newProxyInstance(callbackType.getClassLoader(),new Class<?>[]{callbackType},
                    (proxy,m,args)->callbackValue(proxy,m,args));
                on.invoke(interaction,handler);
                callbackObject=handler;
            }
            media=interaction;updatePlaybackInfo=push;updateSourceType=source;setCallback=on;unsetCallback=off;
            mode="diminteraction";
            reason=on==null?"已接入仪表媒体通道（只写不回读）":"已接入仪表媒体通道";
            sourceMarked=false;pushedStatus=-1;pushedDuration=-1;
            UniLog.done(LogTags.MEDIA,"media/dim","mode",mode,"callback",on!=null);
            return true;
        }catch(Throwable e){
            reason="仪表媒体通道不可用："+name(e);
            UniLog.fail(LogTags.MEDIA,"media/dim","reason","unavailable","error",name(e));
            return false;
        }
    }

    /**
     * 把当前播放状态写进仪表。状态（播放/暂停）或时长没变就不重复写。
     *
     * @param playing   现在是不是在放
     * @param durationMs 曲目时长，拿不到给 -1
     * @param queueIndex 队列位置，没有给 0
     * @return 这一次真的写了
     */
    boolean push(boolean playing,long durationMs,int queueIndex,String title,String artist,String album,String uuid){
        if(!running)return false;
        if(!ensure())return false;
        int status=playing?1:0;
        String track=title+"\u0000"+artist+"\u0000"+uuid;
        // 状态和时长常常不变（换歌也可能时长正好相同），只比这两个会把新歌直接吞掉，
        // 表现就是「仪表歌名慢一拍」。
        if(status==pushedStatus&&durationMs==pushedDuration&&track.equals(pushedTrack))return false;
        Method write=updatePlaybackInfo;
        Object instance=media;
        if(write==null||instance==null)return false;
        try{
            Class<?> infoType=write.getParameterTypes()[0];
            Object info=Proxy.newProxyInstance(infoType.getClassLoader(),new Class<?>[]{infoType},
                (proxy,m,args)->infoValue(proxy,m,args,status,durationMs,queueIndex,title,artist,album,uuid));
            write.invoke(instance,info);
            if(!sourceMarked&&updateSourceType!=null)try{updateSourceType.invoke(instance,SOURCE_ONLINE);sourceMarked=true;}
            catch(Throwable ignored){}
            pushes++;pushedStatus=status;pushedDuration=durationMs;pushedTrack=track;
            return true;
        }catch(Throwable e){
            // 服务被重启过：丢掉这条链，下一轮重新反射。
            reason="写仪表失败："+name(e);
            media=null;updatePlaybackInfo=null;sourceMarked=false;pushedStatus=-1;pushedDuration=-1;pushedTrack="";
            return false;
        }
    }

    /** IPlaybackInfo 的取值：平台实现只读状态、时长、队列位置，其余按接口补齐。 */
    private Object infoValue(Object proxy,Method method,Object[] args,int status,long durationMs,int queueIndex,
                             String title,String artist,String album,String uuid){
        String function=method.getName();
        Class<?> type=method.getReturnType();
        // 仪表到底会问哪些字段（尤其封面叫什么名字）只能靠它自己调过来时记一笔。
        if(asked.add("info."+function))
            UniLog.d(LogTags.MEDIA,"仪表问字段","name",function,"type",type.getSimpleName());
        if("getPlaybackStatus".equals(function))return status;
        if("getDuration".equals(function))return Math.max(0,durationMs);
        if("getPlayingItemPositionInQueue".equals(function))return Math.max(0,queueIndex);
        if("getSourceType".equals(function))return SOURCE_ONLINE;
        if("getTitle".equals(function))return title==null?"":title;
        if("getArtist".equals(function))return artist==null?"":artist;
        if("getAlbum".equals(function))return album==null?"":album;
        if("getUUID".equals(function))return uuid==null?"":uuid;
        if(type==Uri.class)return null;
        if("hashCode".equals(function))return System.identityHashCode(proxy);
        if("equals".equals(function))return args!=null&&args.length>0&&proxy==args[0];
        if("toString".equals(function))return "UNI dim playback info";
        if(type==boolean.class)return Boolean.FALSE;
        if(type==int.class)return 0;
        if(type==long.class)return 0L;
        if(type==float.class)return 0f;
        return null;
    }

    /** 仪表侧回调：按键翻译成动作，选音源翻译成源类型。Binder 线程，统一切回主线程。 */
    private Object callbackValue(Object proxy,Method method,Object[] args){
        String function=method.getName();
        if("onUpdateMediaStatusRequest".equals(function)){
            int type=number(args,0);
            lastDataType=type;
            keyEvents++;
            String action=dataTypeAction(type);
            if(!action.isEmpty()&&running){
                main.post(()->{if(running&&sink!=null)sink.onDimKey(action);});
            }
            return null;
        }
        if("onSourceSelected".equals(function)){
            int source=number(args,0);
            lastSourceType=source;
            sourceEvents++;
            if(running)main.post(()->{if(running&&sink!=null)sink.onDimSource(source);});
            return null;
        }
        if("onMediaSelected".equals(function)||"onMediaHighlighted".equals(function)){
            mediaEvents++;
            return null;
        }
        if("hashCode".equals(function))return System.identityHashCode(proxy);
        if("equals".equals(function))return args!=null&&args.length>0&&proxy==args[0];
        if("toString".equals(function))return "UNI dim media callback";
        return null;
    }

    /** 数据类型 → 桌面动作；不归桌面管的（快进快退、静音、收藏）返回空串。 */
    static String dataTypeAction(int type){
        switch(type){
            case 5:return "next";
            case 6:return "previous";
            case 7:return "play";
            case 8:return "pause";
            case 11:return "pause";
            default:return "";
        }
    }

    /** 诊断：接入方式、写了多少条、仪表按下过什么。 */
    JSONObject snapshot(){
        JSONObject out=new JSONObject();
        try{
            out.put("installed",updatePlaybackInfo!=null).put("mode",mode).put("reason",reason)
                .put("pushes",pushes).put("status",pushedStatus).put("duration",pushedDuration)
                .put("keyEvents",keyEvents).put("sourceEvents",sourceEvents).put("mediaEvents",mediaEvents)
                .put("lastDataType",lastDataType).put("lastSourceType",lastSourceType)
                .put("sourceMarked",sourceMarked);
        }catch(Exception ignored){}
        return out;
    }

    private final java.util.Set<String> asked=java.util.Collections.synchronizedSet(new java.util.TreeSet<>());
    private static Method method(Object target,String name,int argc){
        for(Method candidate:target.getClass().getMethods()){
            if(candidate.getName().equals(name)&&candidate.getParameterTypes().length==argc)return candidate;
        }
        return null;
    }

    private static int number(Object[] args,int index){
        if(args==null||args.length<=index||!(args[index] instanceof Number))return -1;
        return ((Number)args[index]).intValue();
    }

    private static String name(Throwable e){
        while(e.getCause()!=null&&e.getCause()!=e)e=e.getCause();
        return e.getClass().getSimpleName();
    }
}
