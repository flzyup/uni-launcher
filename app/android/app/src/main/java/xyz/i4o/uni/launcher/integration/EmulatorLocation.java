package xyz.i4o.uni.launcher.integration;

import android.content.Context;
import android.content.SharedPreferences;
import android.location.Criteria;
import android.location.Location;
import android.location.LocationManager;
import android.location.LocationProvider;
import android.os.*;
import java.util.HashSet;
import java.util.Set;
import org.json.JSONObject;

/** Stationary WGS84 fix. Never installs a test provider on physical hardware. */
public final class EmulatorLocation {
    // WGS84: 6 m before OSM signal node 601145301, eastbound Renmin Avenue.
    // The road runs north-east here; follow its actual bearing rather than 90°.
    public static final double LATITUDE=31.233055,LONGITUDE=121.471748;
    public static final float BEARING=54.86f;
    public static final String LABEL="人民大道 × 西藏中路 · 西向东";
    private static final String OWNED="uniSimulationProviders";
    private final Context context;
    private final SharedPreferences prefs;
    private final Runnable changed;
    private final Handler main=new Handler(Looper.getMainLooper());
    private Handler worker;
    private Boolean requested;
    private volatile boolean active;
    private volatile String reason="";
    private LocationManager locations;
    private final Set<String> owned=new HashSet<>();
    public EmulatorLocation(Context context,SharedPreferences prefs,Runnable changed){
        this.context=context;this.prefs=prefs;this.changed=changed;
    }
    public static boolean supported(){
        return "ranchu".equals(Build.HARDWARE)||"goldfish".equals(Build.HARDWARE);
    }
    public synchronized void configure(boolean enabled){
        enabled=enabled&&supported();
        if(Boolean.valueOf(enabled).equals(requested)&&(!enabled||active))return;
        requested=enabled;
        if(worker==null){
            if(!enabled&&prefs.getStringSet(OWNED,java.util.Collections.emptySet()).isEmpty())return;
            if(!supported())return;
            HandlerThread thread=new HandlerThread("uni-sim-location");thread.start();worker=new Handler(thread.getLooper());
        }
        final boolean enable=enabled;
        worker.removeCallbacks(tick);
        worker.post(()->{
            cleanup();
            reason="";
            if(enable)try{
                locations=(LocationManager)context.getSystemService(Context.LOCATION_SERVICE);
                for(String provider:new String[]{LocationManager.GPS_PROVIDER,LocationManager.NETWORK_PROVIDER}){
                    locations.addTestProvider(provider,false,false,false,false,true,true,true,Criteria.POWER_LOW,Criteria.ACCURACY_FINE);
                    owned.add(provider);prefs.edit().putStringSet(OWNED,new HashSet<>(owned)).apply();
                    locations.setTestProviderEnabled(provider,true);
                    locations.setTestProviderStatus(provider,LocationProvider.AVAILABLE,null,SystemClock.elapsedRealtime());
                }
                inject();active=true;worker.postDelayed(tick,2000);
            }catch(RuntimeException error){
                cleanup();reason=error instanceof SecurityException?"请允许 UNI 桌面模拟位置":"模拟定位不可用："+error.getClass().getSimpleName();
            }
            main.post(changed);
        });
    }
    private final Runnable tick=new Runnable(){public void run(){
        if(!active)return;
        try{inject();worker.postDelayed(this,2000);}
        catch(RuntimeException error){cleanup();reason="模拟定位已停止："+error.getClass().getSimpleName();main.post(changed);}
    }};
    private void inject(){
        for(String provider:owned){
            Location fix=new Location(provider);fix.setLatitude(LATITUDE);fix.setLongitude(LONGITUDE);
            fix.setAccuracy(3);fix.setAltitude(5);fix.setSpeed(0);fix.setBearing(BEARING);
            fix.setTime(System.currentTimeMillis());fix.setElapsedRealtimeNanos(SystemClock.elapsedRealtimeNanos());
            locations.setTestProviderLocation(provider,fix);
        }
    }
    private void cleanup(){
        if(worker!=null)worker.removeCallbacks(tick);
        active=false;
        if(locations==null)locations=(LocationManager)context.getSystemService(Context.LOCATION_SERVICE);
        owned.addAll(prefs.getStringSet(OWNED,java.util.Collections.emptySet()));
        Set<String> remaining=new HashSet<>();
        for(String provider:owned)try{locations.removeTestProvider(provider);}catch(IllegalArgumentException absent){}
            catch(RuntimeException unavailable){remaining.add(provider);}
        owned.clear();owned.addAll(remaining);
        prefs.edit().putStringSet(OWNED,new HashSet<>(remaining)).apply();
    }
    public JSONObject snapshot(){
        JSONObject value=new JSONObject();try{value.put("supported",supported()).put("locationActive",active).put("reason",reason)
            .put("locationLabel",LABEL).put("latitude",LATITUDE).put("longitude",LONGITUDE).put("bearing",BEARING).put("coordinateSystem","WGS84");}catch(Exception ignored){}
        return value;
    }
}
