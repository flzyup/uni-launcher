package xyz.i4o.uni.launcher.integration;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.content.IntentFilter;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.os.SystemClock;
import java.util.function.Supplier;
import org.json.JSONArray;
import org.json.JSONObject;
import xyz.i4o.uni.launcher.log.LogTags;
import xyz.i4o.uni.launcher.log.UniLog;

/** One bounded receiver for all launcher engines. All calls run on the main thread. */
public final class AmapTrafficLightAdapter {
    // Conservative initial timeout until the vehicle's real update cadence is measured.
    public static final long TTL_MS=5000;
    private final Context context;
    private final Supplier<String> selected;
    private final Runnable changed;
    private final Handler handler=new Handler(Looper.getMainLooper());
    private JSONArray lights=new JSONArray();
    private boolean started;
    private String sourcePackage="",protocol="",reason="waiting";
    private long receivedAt=-1,sequence;
    // 仅用于日志：一个红绿灯周期（同一组方向/灯色）只记一次。倒计时每秒递减，
    // 逐帧打印会把日志文件刷满。
    private String cycleKey="",cycleChannel="",cycleDetail="";
    private int cycleUpdates;
    // 记过的「广播没有可用灯态」形态，每种只记一次；见 skipBroadcast。
    private final java.util.LinkedHashSet<String> skippedSignatures=new java.util.LinkedHashSet<>();
    private static final int MAX_SKIPPED_SIGNATURES=64;
    private final Runnable expire=this::expireSignal;
    private final BroadcastReceiver receiver=new BroadcastReceiver(){
        @Override public void onReceive(Context ignored,Intent intent){receive(intent);}
    };

    public AmapTrafficLightAdapter(Context context,Supplier<String> selected,Runnable changed){
        this.context=context.getApplicationContext();this.selected=selected;this.changed=changed;
    }
    public void start(){
        if(started)return;
        sourcePackage=selected.get();
        IntentFilter filter=new IntentFilter(AmapTrafficLightProtocol.STANDARD);
        filter.addAction(AmapTrafficLightProtocol.CRUISE);
        context.registerReceiver(receiver,filter);started=true;
        UniLog.i(LogTags.TRAFFIC,"红绿灯广播监听已启动","package",sourcePackage);
    }
    public void stop(){
        if(started){context.unregisterReceiver(receiver);started=false;}
        clear("waiting");
        UniLog.i(LogTags.TRAFFIC,"红绿灯广播监听已停止","package",sourcePackage);
    }
    public void navigationChanged(){
        String next=selected.get();if(next.equals(sourcePackage))return;
        clear("waiting");sourcePackage=next;
        UniLog.i(LogTags.TRAFFIC,"红绿灯来源导航应用已切换","package",next);
    }
    private void clear(String why){
        closeCycle(why);
        handler.removeCallbacks(expire);lights=new JSONArray();protocol="";reason=why;receivedAt=-1;sequence++;
    }
    private void expireSignal(){clear("expired");changed.run();}
    private void receive(Intent intent){
        if(!started||intent==null)return;
        String configured=selected.get();
        // Auto mode can resolve to the official AMap while the owner is driving
        // the yh build. The cruise action is unique to that build, so accept its
        // richer channel for any AMap selection; keep it away from Baidu/Tencent.
        boolean cruise=AmapTrafficLightProtocol.CRUISE.equals(intent.getAction());
        if(!configured.startsWith("com.autonavi.")){skipBroadcast(intent,"当前导航应用不是高德");return;}
        sourcePackage=cruise?AmapTrafficLightProtocol.MODIFIED_PACKAGE:configured;
        // Broadcasts have no verified sender identity. Association filters the
        // protocol family, not a security principal; these are display-only hints.
        if(!sourcePackage.startsWith("com.autonavi.")){skipBroadcast(intent,"广播来源不是高德");return;}
        JSONArray incoming=null;String channel="";
        try{
            if(!cruise){
                Bundle extras=intent.getExtras();if(extras==null){skipBroadcast(intent,"广播没有 extras");return;}
                JSONObject raw=new JSONObject();
                for(String key:new String[]{"KEY_TYPE","dir","trafficLightStatus","redLightCountDownSeconds","waitRound","greenLightLastSecond"}){
                    Object v=extras.get(key);if(v instanceof Number)raw.put(key,v);
                }
                incoming=AmapTrafficLightProtocol.standard(raw);channel="standard";
            }else{
                incoming=AmapTrafficLightProtocol.cruise(intent.getStringExtra("data"));channel="cruise";
            }
        }catch(RuntimeException|org.json.JSONException e){skipBroadcast(intent,"广播解析异常 "+e.getClass().getSimpleName());return;}
        if(incoming==null){skipBroadcast(intent,"广播没有可用的灯态");return;}
        // Prefer the richer, enum-verified yh batch (even one direction) over
        // concurrent standard data whose direction enum is unverified.
        // A cruise empty array always clears; it cannot fall back to stale data.
        if("standard".equals(channel)&&"cruise".equals(protocol)&&lights.length()>0
                &&receivedAt>=0&&SystemClock.elapsedRealtime()-receivedAt<TTL_MS){skipBroadcast(intent,"标准通道数据让位于正在生效的 cruise 批次");return;}
        handler.removeCallbacks(expire);sequence++;
        lights=incoming;protocol=channel;reason=lights.length()==0?"waiting":"live";
        receivedAt=lights.length()==0?-1:SystemClock.elapsedRealtime();
        if(receivedAt>=0)handler.postDelayed(expire,TTL_MS);
        traceCycle(channel,incoming);
        changed.run();
    }
    // 广播没有可用灯态时，把动作与 extras 的键名记下来：维护者照着就能补解析，
    // 不用再跑一趟车。同一种情况只记一次，避免每秒广播刷屏。
    private void skipBroadcast(Intent intent,String why){
        Bundle extras=intent.getExtras();
        // 键名要排序后再拼：keySet() 的 toString 是实例身份哈希（KeySet@344fc936），
        // 每次广播都不一样，拿它做签名等于没有去重，广播一来就刷一行。
        String keys=extras==null?"":sortedKeys(extras);
        String signature=String.valueOf(intent.getAction())+"|"+keys+"|"+why;
        // 记的是**见过的所有**形态，不是最后一个：高德同一个 action 会发好几种
        // extras 键集的广播，只记最后一个的话，另外几种会轮流把这一行刷出来。
        if(!skippedSignatures.add(signature))return;
        // 形态数理论上很少，但厂商乱发的话不能让这个集合无限长。
        if(skippedSignatures.size()>MAX_SKIPPED_SIGNATURES)skippedSignatures.clear();
        UniLog.i(LogTags.TRAFFIC,"红绿灯广播没有可用灯态","action",intent.getAction(),"extrasKeys",keys,"reason",why);
        // 锚点降到 DEBUG：上面那行 INFO 已经带上了可据以修解析的键名，
        // 锚点留着只进 Logcat，免得「没有灯态」这种常态把日志占满。
        UniLog.skipDebug(LogTags.TRAFFIC,"traffic/broadcast","action",intent.getAction(),"extrasKeys",keys,"reason",why);
    }

    /** extras 的键名，逗号分隔且有序。 */
    private static String sortedKeys(Bundle extras){
        // 不用 String.join：那是 API 26 才有的，minSdk 24 上会 NoSuchMethodError。
        java.util.TreeSet<String> names=new java.util.TreeSet<>(extras.keySet());
        StringBuilder sb=new StringBuilder();
        for(String name:names){
            if(sb.length()>0)sb.append(',');
            sb.append(name);
        }
        return sb.toString();
    }
    // 一个周期 = 同一组「方向/灯色」；倒计时递减不算新周期。
    private void traceCycle(String channel,JSONArray incoming){
        if(incoming.length()==0){
            closeCycle("广播显式清空");
            UniLog.i(LogTags.TRAFFIC,"红绿灯广播显式清空","channel",channel,"package",sourcePackage);
            return;
        }
        String key=channel+"|"+signalKey(incoming);
        if(!key.equals(cycleKey)){
            closeCycle("灯态变化");
            cycleKey=key;cycleChannel=channel;cycleUpdates=1;cycleDetail=signalDetail(incoming);
            UniLog.enter(LogTags.TRAFFIC,"traffic/broadcast","channel",channel,"package",sourcePackage,"lights",incoming.length(),"signals",signalKey(incoming));
            UniLog.i(LogTags.TRAFFIC,"红绿灯信号已解析","channel",channel,"package",sourcePackage,"signals",cycleDetail);
            return;
        }
        cycleUpdates++;cycleDetail=signalDetail(incoming);
    }
    // 周期结束：连这一轮收到的次数和最后的倒计时一起记下来。
    private void closeCycle(String why){
        if(cycleKey.isEmpty())return;
        UniLog.i(LogTags.TRAFFIC,"红绿灯信号周期结束","reason",why,"channel",cycleChannel,"updates",cycleUpdates,"signals",cycleDetail);
        UniLog.done(LogTags.TRAFFIC,"traffic/broadcast","channel",cycleChannel,"updates",cycleUpdates,"signals",cycleDetail,"reason",why);
        cycleKey="";cycleChannel="";cycleDetail="";cycleUpdates=0;
    }
    // 标准通道没有方向/灯色枚举，这里保留原厂原始值，方便和实车日志对照。
    private static String signalKey(JSONArray lights){
        StringBuilder sb=new StringBuilder();
        for(int i=0;i<lights.length();i++){
            JSONObject light=lights.optJSONObject(i);if(light==null)continue;
            if(sb.length()>0)sb.append(',');
            sb.append(directionOf(light)).append('/').append(lampOf(light));
        }
        return sb.length()==0?"empty":sb.toString();
    }
    private static String signalDetail(JSONArray lights){
        StringBuilder sb=new StringBuilder();
        for(int i=0;i<lights.length();i++){
            JSONObject light=lights.optJSONObject(i);if(light==null)continue;
            if(sb.length()>0)sb.append(',');
            sb.append(directionOf(light)).append('/').append(lampOf(light)).append('@').append(light.optInt("countdownSeconds",-1));
        }
        return sb.length()==0?"empty":sb.toString();
    }
    private static String directionOf(JSONObject light){
        String dir=light.optString("direction","");
        return "unknown".equals(dir)?String.valueOf(light.optInt("rawDirection",-1)):dir;
    }
    private static String lampOf(JSONObject light){
        String lamp=light.optString("lamp","");
        return "unknown".equals(lamp)?String.valueOf(light.optInt("rawStatus",-1)):lamp;
    }
    public JSONObject snapshot(){
        JSONObject result=new JSONObject();try{
            long age=receivedAt<0?0:Math.max(0,SystemClock.elapsedRealtime()-receivedAt);
            boolean available=receivedAt>=0&&age<TTL_MS&&lights.length()>0;
            result.put("available",available).put("reason",receivedAt>=0&&!available?"expired":reason)
                .put("package",sourcePackage).put("protocol",protocol).put("sequence",sequence)
                .put("ageMs",age).put("ttlMs",TTL_MS).put("enumVerified",false)
                .put("lights",available?new JSONArray(lights.toString()):new JSONArray());
        }catch(Exception ignored){}return result;
    }
}
