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
    }
    public void stop(){
        if(started){context.unregisterReceiver(receiver);started=false;}
        clear("waiting");
    }
    public void navigationChanged(){
        String next=selected.get();if(next.equals(sourcePackage))return;
        clear("waiting");sourcePackage=next;
    }
    private void clear(String why){
        handler.removeCallbacks(expire);lights=new JSONArray();protocol="";reason=why;receivedAt=-1;sequence++;
    }
    private void expireSignal(){clear("expired");changed.run();}
    private void receive(Intent intent){
        if(!started||intent==null)return;
        navigationChanged();
        // Broadcasts have no verified sender identity. Association filters the
        // protocol family, not a security principal; these are display-only hints.
        if(!sourcePackage.startsWith("com.autonavi."))return;
        JSONArray incoming=null;String channel="";
        try{
            if(AmapTrafficLightProtocol.STANDARD.equals(intent.getAction())){
                Bundle extras=intent.getExtras();if(extras==null)return;
                JSONObject raw=new JSONObject();
                for(String key:new String[]{"KEY_TYPE","dir","trafficLightStatus","redLightCountDownSeconds","waitRound","greenLightLastSecond"}){
                    Object v=extras.get(key);if(v instanceof Number)raw.put(key,v);
                }
                incoming=AmapTrafficLightProtocol.standard(raw);channel="standard";
            }else if(AmapTrafficLightProtocol.CRUISE.equals(intent.getAction())
                    &&AmapTrafficLightProtocol.MODIFIED_PACKAGE.equals(sourcePackage)){
                incoming=AmapTrafficLightProtocol.cruise(intent.getStringExtra("data"));channel="cruise";
            }
        }catch(RuntimeException|org.json.JSONException ignored){return;}
        if(incoming==null)return;
        // Prefer the richer, enum-verified yh batch (even one direction) over
        // concurrent standard data whose direction enum is unverified.
        // A cruise empty array always clears; it cannot fall back to stale data.
        if("standard".equals(channel)&&"cruise".equals(protocol)&&lights.length()>0
                &&receivedAt>=0&&SystemClock.elapsedRealtime()-receivedAt<TTL_MS)return;
        handler.removeCallbacks(expire);sequence++;
        lights=incoming;protocol=channel;reason=lights.length()==0?"waiting":"live";
        receivedAt=lights.length()==0?-1:SystemClock.elapsedRealtime();
        if(receivedAt>=0)handler.postDelayed(expire,TTL_MS);
        changed.run();
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
