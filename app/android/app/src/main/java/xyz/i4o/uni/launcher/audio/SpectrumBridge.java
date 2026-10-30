package xyz.i4o.uni.launcher.audio;

import android.Manifest;
import android.content.Context;
import android.content.pm.PackageManager;
import android.media.audiofx.Visualizer;
import android.os.Handler;
import android.os.HandlerThread;
import android.os.Looper;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.IdentityHashMap;
import java.util.Map;
import io.flutter.embedding.engine.FlutterEngine;
import io.flutter.plugin.common.EventChannel;
import io.flutter.plugin.common.MethodChannel;
import xyz.i4o.uni.launcher.MainActivity;

/** One output-mix Visualizer for all engines, only while visible music widgets
 * request it. No microphone/AudioRecord, raw PCM, disk writes, or general-state
 * broadcasts. FFT data remains a fixed 24-band packet at most 10 Hz. */
public final class SpectrumBridge {
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
        long sequence,signalFrames;
        double peakLevel;
        volatile int captureSize,sampleRate;
        Runnable poll;
        Broker(Context context){this.context=context;}
        boolean granted(){return context.checkSelfPermission(Manifest.permission.RECORD_AUDIO)==PackageManager.PERMISSION_GRANTED
            &&context.checkSelfPermission(Manifest.permission.MODIFY_AUDIO_SETTINGS)==PackageManager.PERMISSION_GRANTED;}
        int demand(){int n=0;for(SpectrumBridge c:clients.keySet())if(c.active&&c.sink!=null&&!c.closed)n++;return n;}
        Map<String,Object> packet(double[] levels){
            Map<String,Object> data=new HashMap<>();
            data.put("granted",granted());data.put("available",running&&!failed&&"listening".equals(reason));
            data.put("running",running);data.put("source","output-mix");
            data.put("status",!granted()?"permission-required":reason);
            data.put("activeConsumers",demand());data.put("clients",clients.size());
            data.put("captureSize",captureSize);data.put("sampleRateHz",sampleRate);
            data.put("sequence",sequence);data.put("captureHz",10);
            data.put("peakLevel",running?peakLevel:0d);data.put("signalFrames",signalFrames);
            if(levels!=null){ArrayList<Double> values=new ArrayList<>(levels.length);for(double v:levels)values.add(v);data.put("levels",values);}
            return data;
        }
        void publish(double[] levels){
            Map<String,Object> data=packet(levels);
            for(SpectrumBridge c:new ArrayList<>(clients.keySet()))if(c.sink!=null&&!c.closed&& (levels==null||c.active))c.sink.success(data);
        }
        void sync(){
            boolean needed=demand()>0&&granted();
            if(needed&&!running&&!failed){
                running=true;reason="starting";int epoch=++generation;
                if(worker==null){HandlerThread thread=new HandlerThread("uni-audio-spectrum",android.os.Process.THREAD_PRIORITY_BACKGROUND);thread.start();worker=new Handler(thread.getLooper());}
                worker.post(()->start(epoch));
            }else if(!needed&&running){
                running=false;reason="idle";peakLevel=0;generation++;
                worker.post(this::release);
                publish(new double[SpectrumBands.COUNT]);
            }else if(!needed){failed=false;reason="idle";}
        }
        void release(){
            if(poll!=null)worker.removeCallbacks(poll);poll=null;
            if(visualizer!=null){try{visualizer.setEnabled(false);}catch(RuntimeException ignored){}visualizer.release();visualizer=null;}
            fft=null;previous=new double[SpectrumBands.COUNT];
        }
        void start(int epoch){
            if(!running||epoch!=generation)return;
            release();
            try{
                visualizer=new Visualizer(0);
                int[] range=Visualizer.getCaptureSizeRange();
                captureSize=Math.max(range[0],Math.min(PREFERRED_CAPTURE_SIZE,range[1]));
                if(visualizer.setCaptureSize(captureSize)!=Visualizer.SUCCESS){
                    // 设备报支持却实际拒绝时退回兜底点数，别整个采集起不来。
                    // 「采集起不来」比「低频分辨不出来」严重得多。
                    int fallback=Math.max(range[0],Math.min(FALLBACK_CAPTURE_SIZE,range[1]));
                    if(fallback==captureSize||visualizer.setCaptureSize(fallback)!=Visualizer.SUCCESS)throw new IllegalStateException("capture-size");
                    captureSize=fallback;
                }
                // 车机 ROM 报的是毫赫兹（48000000），标准设备报的是赫兹（44100），
                // 归一成赫兹再用，频率轴才不会被差 1000 倍。
                sampleRate=SpectrumBands.normalizeSampleRate(visualizer.getSamplingRate());fft=new byte[captureSize];
                if(visualizer.setEnabled(true)!=Visualizer.SUCCESS)throw new IllegalStateException("capture-enable");
                reason="listening";
                poll=()->capture(epoch);worker.post(poll);
            }catch(RuntimeException error){fail(epoch);}
        }
        void capture(int epoch){
            if(!running||epoch!=generation||visualizer==null)return;
            try{
                if(visualizer.getFft(fft)!=Visualizer.SUCCESS)throw new IllegalStateException("fft-unavailable");
                double[] values=SpectrumBands.decode(fft,sampleRate);
                for(int i=0;i<values.length;i++){values[i]=Math.max(values[i],previous[i]*.70);previous[i]=values[i];}
                main.post(()->{if(running&&epoch==generation){
                    peakLevel=0;for(double value:values)peakLevel=Math.max(peakLevel,value);
                    if(peakLevel>.02)signalFrames++;sequence++;publish(values);
                }});
                worker.postDelayed(poll,100);
            }catch(RuntimeException error){fail(epoch);}
        }
        void fail(int epoch){
            release();main.post(()->{if(epoch==generation){failed=true;running=false;peakLevel=0;reason="unavailable";publish(new double[SpectrumBands.COUNT]);}});
        }
    }
}
