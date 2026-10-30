package xyz.i4o.uni.launcher.audio;

import android.Manifest;
import android.content.Context;
import android.content.pm.PackageManager;
import android.media.AudioManager;
import android.media.AudioPlaybackConfiguration;
import android.media.audiofx.Visualizer;
import android.os.Handler;
import android.os.HandlerThread;
import android.os.Looper;
import android.util.Log;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.IdentityHashMap;
import java.util.List;
import java.util.Map;
import io.flutter.embedding.engine.FlutterEngine;
import io.flutter.plugin.common.EventChannel;
import io.flutter.plugin.common.MethodChannel;
import xyz.i4o.uni.launcher.MainActivity;

/** One output-mix Visualizer for all engines, only while visible music widgets
 * request it. No microphone/AudioRecord, raw PCM, disk writes, or general-state
 * broadcasts. FFT data remains a fixed 24-band packet at most 10 Hz. */
public final class SpectrumBridge {
    private static final String TAG="UniSpectrum";

    /**
     * 期望的采集点数（2 的幂）。
     *
     * <p>频率分辨率 = 采样率 / 采集点数。44.1kHz 下：
     *
     * <ul>
     *   <li>512 点 ⇒ bin 间隔 86.1Hz ⇒ 60~149Hz 的低频四段<b>全部塌进同一个 bin</b>
     *       ⇒ 四段功率永远相等 ⇒「取最响的那一段」永远取第 0 段
     *       ⇒ 色相恒为 0°（红）、低频能量饱和 ⇒ 亮度钉死 —— 灯是红的、拉满、一动不动；</li>
     *   <li>1024 点 ⇒ bin 间隔 43.1Hz ⇒ 四段各占不同 bin，色相才能跟着音高走。</li>
     * </ul>
     *
     * <p>实际取值会被夹到设备支持的范围里，设备只支持 512 就还是 512。
     */
    static final int PREFERRED_CAPTURE_SIZE=1024;

    /** 采集点数的兜底值（设备报支持、实际却拒绝时退回这个）。 */
    static final int FALLBACK_CAPTURE_SIZE=512;

    /**
     * 输出混音挂上了却一直没有信号，过这么久就改挂到播放会话上。
     *
     * <p>车机 ROM 上「全局输出混音」有时是空的（拿得到句柄但读不到内容），
     * 这时候退到「挂到正在播放的那个会话」上——这条路径在参照工程上实机验证过。
     */
    static final long SILENT_SWITCH_MS=6000;

    /** 采集失败后隔多久重试（车机上的通道被占、权限迟到都属于暂时性的）。 */
    static final long RETRY_MS=3000;

    private static Broker broker;
    private final Context context;
    private final MethodChannel methods;
    private final EventChannel events;
    private EventChannel.EventSink sink;
    private boolean active,closed;
    private SpectrumBridge(Context context,FlutterEngine engine){
        this.context=context;
        if(broker==null)broker=new Broker(context.getApplicationContext());
        broker.clients.put(this,Boolean.TRUE);
        methods=new MethodChannel(engine.getDartExecutor().getBinaryMessenger(),"xyz.i4o.uni.launcher/spectrum-control");
        events=new EventChannel(engine.getDartExecutor().getBinaryMessenger(),"xyz.i4o.uni.launcher/spectrum");
        methods.setMethodCallHandler((call,result)->{
            if("active".equals(call.method)){active=Boolean.TRUE.equals(call.arguments);broker.sync();result.success(null);}
            else if("status".equals(call.method))result.success(broker.packet(null));
            else if("permission".equals(call.method)){MainActivity.requestAudioSpectrumPermission(this.context);result.success(null);}
            else result.notImplemented();
        });
        events.setStreamHandler(new EventChannel.StreamHandler(){
            public void onListen(Object args,EventChannel.EventSink next){sink=next;sink.success(broker.packet(null));broker.sync();}
            public void onCancel(Object args){sink=null;active=false;broker.sync();}
        });
    }
    public static SpectrumBridge attach(Context context,FlutterEngine engine){return new SpectrumBridge(context,engine);}
    public static void permissionChanged(){if(broker!=null){broker.failed=false;broker.sync();broker.publish(null);}}
    public static Map<String,Object> diagnostics(){return broker==null?new HashMap<>():broker.packet(null);}
    public void close(){
        if(closed)return;closed=true;active=false;sink=null;
        methods.setMethodCallHandler(null);events.setStreamHandler(null);
        broker.clients.remove(this);broker.sync();
    }

    private static final class Broker {
        final Context context;
        final Handler main=new Handler(Looper.getMainLooper());
        final IdentityHashMap<SpectrumBridge,Boolean> clients=new IdentityHashMap<>();
        Handler worker;
        Visualizer visualizer;
        byte[] fft;
        double[] previous=new double[SpectrumBands.COUNT];
        volatile boolean running;
        volatile int generation;
        boolean failed;
        volatile String reason="idle";
        /** 失败原因（人话），诊断包里原样带给界面。 */
        volatile String detail="";
        /** 采集来源：output-mix / session / none。 */
        volatile String source="none";
        /** 当前播放会话 id（次选路径用）。 */
        volatile int sessionId;
        /** 当前 Visualizer 挂在哪个会话上（0 = 全局输出混音）。 */
        volatile int attachedSessionId;
        /** 这一轮采集有没有出现过信号。 */
        volatile boolean signalSeen;
        volatile long sequence,signalFrames,frames;
        double peakLevel;
        volatile int captureSize,sampleRate;
        long startedAt;
        Runnable poll;
        AudioManager audioManager;
        boolean sessionWarned;

        Broker(Context context){this.context=context;}

        boolean granted(){return context.checkSelfPermission(Manifest.permission.RECORD_AUDIO)==PackageManager.PERMISSION_GRANTED
            &&context.checkSelfPermission(Manifest.permission.MODIFY_AUDIO_SETTINGS)==PackageManager.PERMISSION_GRANTED;}
        int demand(){int n=0;for(SpectrumBridge c:clients.keySet())if(c.active&&c.sink!=null&&!c.closed)n++;return n;}

        Map<String,Object> packet(double[] levels){
            Map<String,Object> data=new HashMap<>();
            data.put("granted",granted());data.put("available",running&&!failed&&"listening".equals(reason));
            data.put("running",running);data.put("source",source);
            data.put("status",!granted()?"permission-required":reason);
            data.put("detail",detail);
            data.put("hiddenApi",xyz.i4o.uni.launcher.platform.HiddenApiCompat.status());
            data.put("activeConsumers",demand());data.put("clients",clients.size());
            data.put("captureSize",captureSize);data.put("sampleRateHz",sampleRate);
            data.put("sequence",sequence);data.put("captureHz",10);
            data.put("peakLevel",running?peakLevel:0d);data.put("signalFrames",signalFrames);data.put("frames",frames);
            if(levels!=null){ArrayList<Double> values=new ArrayList<>(levels.length);for(double v:levels)values.add(v);data.put("levels",values);}
            return data;
        }

        void publish(double[] levels){
            Map<String,Object> data=packet(levels);
            for(SpectrumBridge c:new ArrayList<>(clients.keySet()))if(c.sink!=null&&!c.closed&&(levels==null||c.active))c.sink.success(data);
        }

        /**
         * 状态一变就把状态推出去。
         *
         * <p>以前只有「采到信号」才推包，于是「采集已经跑起来了但此刻没声音」
         * 和「根本没采到」在界面上长得一模一样——都显示成「等待音乐播放」。
         * 静音的帧现在照样推，界面才分得清。
         */
        void publishState(){publish(null);}

        void sync(){
            boolean needed=demand()>0&&granted();
            if(needed&&!running&&!failed){
                startCapture();
            }else if(!needed&&running){
                stopCapture();
            }else if(!needed){
                failed=false;reason="idle";source="none";detail="";
            }
        }

        void stopCapture(){
            running=false;reason="idle";source="none";signalSeen=false;peakLevel=0;generation++;
            if(worker!=null)worker.post(this::releaseVisualizer);
            publishState();
        }

        void startCapture(){
            running=true;reason="starting";detail="";signalSeen=false;startedAt=System.currentTimeMillis();
            int epoch=++generation;
            ensureWorker();
            watchPlayback();
            worker.post(()->attachOutputMix(epoch));
        }

        void ensureWorker(){
            if(worker!=null)return;
            HandlerThread thread=new HandlerThread("uni-audio-spectrum",android.os.Process.THREAD_PRIORITY_BACKGROUND);
            thread.start();worker=new Handler(thread.getLooper());
        }

        /** 挂到全局输出混音上（主路径）。 */
        void attachOutputMix(int epoch){
            if(!running||epoch!=generation)return;
            try{
                openVisualizer(0);
                source="output-mix";
                reason="listening";detail="";
                publishState();
                schedulePoll(epoch);
            }catch(RuntimeException error){
                // 主路径挂不上就退到播放会话（参照工程实机验证过的次选路径）。
                int id=currentSessionId();
                if(id>0){attachSession(id,epoch);return;}
                fail(epoch,error);
            }
        }

        /** 挂到某个播放会话上（次选路径）。 */
        void attachSession(int id,int epoch){
            if(id<=0||worker==null)return;
            // 句柄的创建与释放必须和采集轮询串行，所以一律排到采集线程上。
            worker.post(()->{
                if(!running||epoch!=generation)return;
                // 先放掉旧的句柄：同一个会话只能挂一个 Visualizer，
                // 不放就会占着通道，新句柄反而挂不上。
                releaseVisualizer();
                try{
                    openVisualizer(id);
                    sessionId=id;source="session";
                    reason="listening";detail="";
                    publishState();
                    schedulePoll(epoch);
                }catch(RuntimeException error){
                    detail="播放会话挂载失败："+message(error);
                    try{
                        openVisualizer(0);source="output-mix";reason="listening";
                        publishState();schedulePoll(epoch);
                    }catch(RuntimeException second){fail(epoch,second);}
                }
            });
        }

        /**
         * 打开一个 Visualizer：设采集点数、启用。
         *
         * @throws RuntimeException 车机 ROM 不支持 / 权限不足 / 通道被占
         */
        void openVisualizer(int id) throws RuntimeException{
            Visualizer v=new Visualizer(id);
            try{
                int[] range=Visualizer.getCaptureSizeRange();
                int size=Math.max(range[0],Math.min(PREFERRED_CAPTURE_SIZE,range[1]));
                if(v.setCaptureSize(size)!=Visualizer.SUCCESS){
                    // 设备报支持却实际拒绝时退回兜底点数，别整个采集起不来。
                    // 「采集起不来」比「低频分辨不出来」严重得多。
                    int fallback=Math.max(range[0],Math.min(FALLBACK_CAPTURE_SIZE,range[1]));
                    if(fallback==size||v.setCaptureSize(fallback)!=Visualizer.SUCCESS)throw new IllegalStateException("capture-size");
                    size=fallback;
                }
                captureSize=size;
                fft=new byte[captureSize];
                sampleRate=resolveSampleRate(v);
                if(v.setEnabled(true)!=Visualizer.SUCCESS)throw new IllegalStateException("capture-enable");
                visualizer=v;
                attachedSessionId=id;
                // 每次挂上都重新计时：「挂了多久还没声音」是从这次挂上算的。
                startedAt=System.currentTimeMillis();
            }catch(RuntimeException error){
                try{v.release();}catch(RuntimeException ignored){}
                throw error;
            }
        }

        /**
         * The sample rate for the frequency axis.
         *
         * <p>Three sources, in order: what the Visualizer reports, the output
         * sample rate of the audio manager, and finally the default.
         *
         * <p>Without the fallbacks a rate of 0 makes every band decode to
         * zero. The spectrum would then be silent for good and nothing would
         * say why — the light would simply never react.
         */
        int resolveSampleRate(Visualizer v){
            int fromVisualizer=SpectrumBands.normalizeSampleRate(v.getSamplingRate());
            if(SpectrumBands.isPlausibleSampleRate(fromVisualizer))return fromVisualizer;
            int fromManager=SpectrumBands.normalizeSampleRate(outputSampleRate());
            if(SpectrumBands.isPlausibleSampleRate(fromManager))return fromManager;
            return SpectrumBands.DEFAULT_SAMPLE_RATE;
        }

        /** The output sample rate of the audio manager, or 0. */
        int outputSampleRate(){
            // 刻意不写进 audioManager 字段：那个字段是「播放配置监听已注册」的
            // 标志，这里借用它会让监听注册被跳过。
            AudioManager manager=(AudioManager)context.getSystemService(Context.AUDIO_SERVICE);
            if(manager==null)return 0;
            try{
                String property=manager.getProperty(AudioManager.PROPERTY_OUTPUT_SAMPLE_RATE);
                if(property==null)return 0;
                return Integer.parseInt(property.trim());
            }catch(Throwable error){return 0;}
        }

        void schedulePoll(int epoch){
            poll=()->capture(epoch);worker.post(poll);
        }

        void capture(int epoch){
            if(!running||epoch!=generation||visualizer==null)return;
            try{
                if(visualizer.getFft(fft)!=Visualizer.SUCCESS)throw new IllegalStateException("fft-unavailable");
                double[] values=SpectrumBands.decode(fft,sampleRate);
                for(int i=0;i<values.length;i++){values[i]=Math.max(values[i],previous[i]*.70);previous[i]=values[i];}
                main.post(()->{if(running&&epoch==generation){
                    peakLevel=0;for(double value:values)peakLevel=Math.max(peakLevel,value);
                    frames++;
                    if(peakLevel>.02){signalFrames++;signalSeen=true;}
                    sequence++;
                    // 静音的帧也要推：不然界面分不清「在采但没声音」和「没在采」，
                    // 而且灯也不会按快起慢落慢慢暗下去。
                    publish(values);
                    maybeSwitchToSession(epoch);
                }});
                worker.postDelayed(poll,100);
            }catch(RuntimeException error){fail(epoch,error);}
        }

        /**
         * 输出混音挂上了却一直没有信号，而车机上确实有东西在播：
         * 改挂到那个播放会话上。
         */
        void maybeSwitchToSession(int epoch){
            if(signalSeen||!"output-mix".equals(source))return;
            if(System.currentTimeMillis()-startedAt<SILENT_SWITCH_MS)return;
            int id=sessionId>0?sessionId:currentSessionId();
            if(id<=0)return;
            attachSession(id,epoch);
        }

        void fail(int epoch,RuntimeException error){
            releaseVisualizer();
            failed=true;running=false;signalSeen=false;peakLevel=0;
            reason=isPermissionError(error)?"permission-required":"unavailable";
            detail=message(error);
            main.post(()->{if(epoch==generation){publish(new double[SpectrumBands.COUNT]);scheduleRetry(epoch);}});
        }

        /** 失败不是终局：过几秒重试一次（通道被占、权限迟到都是暂时性的）。 */
        void scheduleRetry(int epoch){
            if(worker==null)return;
            worker.postDelayed(()->{
                if(epoch!=generation)return;
                if(demand()>0&&granted()&&failed){failed=false;startCapture();}
            },RETRY_MS);
        }

        void releaseVisualizer(){
            if(poll!=null&&worker!=null)worker.removeCallbacks(poll);poll=null;
            if(visualizer!=null){try{visualizer.setEnabled(false);}catch(RuntimeException ignored){}visualizer.release();visualizer=null;}
            fft=null;previous=new double[SpectrumBands.COUNT];
        }

        // ------------------------------------------------------------ 播放会话（次选路径）

        void watchPlayback(){
            // 播放配置监听是 API 26 才有的；低版本上直接没有次选路径。
            if(android.os.Build.VERSION.SDK_INT<26)return;
            if(audioManager!=null)return;
            audioManager=(AudioManager)context.getSystemService(Context.AUDIO_SERVICE);
            if(audioManager==null)return;
            try{
                audioManager.registerAudioPlaybackCallback(new AudioManager.AudioPlaybackCallback(){
                    @Override public void onPlaybackConfigChanged(List<AudioPlaybackConfiguration> configs){
                        int found=0;
                        if(configs!=null&&!configs.isEmpty())found=sessionIdOf(configs.get(0));
                        final int session=found;
                        main.post(()->onPlaybackSession(session));
                    }
                },main);
            }catch(Throwable error){Log.w(TAG,"注册播放配置监听失败（不影响输出混音主路径）",error);}
        }

        void onPlaybackSession(int id){
            sessionId=id;
            if(!running)return;
            if("session".equals(source)){
                // 已经挂在会话上了：换了一个会话就得跟着换，
                // 否则句柄一直挂在一个已经不播的会话上，等于什么都听不到。
                if(id>0&&id!=attachedSessionId)attachSession(id,generation);
                return;
            }
            if(signalSeen||!"output-mix".equals(source))return;
            if(id<=0)return;
            attachSession(id,generation);
        }

        /** 当前正在播放的会话 id。 */
        int currentSessionId(){
            if(audioManager==null||android.os.Build.VERSION.SDK_INT<26)return 0;
            try{
                List<AudioPlaybackConfiguration> configs=audioManager.getActivePlaybackConfigurations();
                if(configs==null||configs.isEmpty())return 0;
                return sessionIdOf(configs.get(0));
            }catch(Throwable error){return 0;}
        }

        /**
         * 反射拿 audioSessionId。
         *
         * <p>公开 SDK 里没有这个方法（{@code AudioPlaybackConfiguration} 只暴露
         * {@code getAudioAttributes()}），只能反射；调不到就当「没有活动会话」，
         * 不影响输出混音主路径。
         */
        int sessionIdOf(AudioPlaybackConfiguration config){
            if(config==null)return 0;
            try{
                java.lang.reflect.Method method=config.getClass().getMethod("getAudioSessionId");
                Object value=method.invoke(config);
                return value instanceof Integer?((Integer)value).intValue():0;
            }catch(Throwable error){
                if(!sessionWarned){sessionWarned=true;Log.w(TAG,"取 audioSessionId 失败（隐藏 API 没放开？）",error);}
                return 0;
            }
        }

        static boolean isPermissionError(Throwable error){
            if(error instanceof SecurityException)return true;
            String msg=error==null?"":String.valueOf(error.getMessage());
            return msg.contains("permission")||msg.contains("Permission Denial");
        }

        static String message(Throwable error){
            if(error==null)return "";
            String msg=error.getMessage();
            return msg==null||msg.isEmpty()?error.getClass().getSimpleName():msg;
        }
    }
}
