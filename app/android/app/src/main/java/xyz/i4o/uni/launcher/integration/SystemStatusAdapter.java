package xyz.i4o.uni.launcher.integration;

import android.content.*;
import android.os.*;
import android.bluetooth.BluetoothAdapter;
import android.bluetooth.BluetoothProfile;
import android.net.*;
import android.net.wifi.*;
import android.telephony.*;
import android.provider.Settings;
import org.json.*;
import java.lang.reflect.*;
import java.util.*;

/** Read-only sources used by XCSystemUIPlugin's seven right-hand icon slots.
 * Does not register a second system status bar or replace its service callbacks. */
public final class SystemStatusAdapter {
    private final Context context;private final Runnable changed;
    private final Handler main=new Handler(Looper.getMainLooper());
    private HandlerThread thread;private Handler worker;private volatile boolean running;private volatile int generation;
    private volatile String state="{}";
    private final Map<String,Object> apis=new HashMap<>();private ClassLoader oemLoader;
    private volatile int signalLevel=-1;
    private volatile boolean userReady;
    private Object userCallback,wifiApCallback;
    private volatile int apClients=-1;
    private volatile String userInitState="CREATING";
    private volatile boolean apCallbackRegistered;
    private final PhoneStateListener phoneListener=new PhoneStateListener(){
        @Override public void onSignalStrengthsChanged(SignalStrength s){signalLevel=s==null?-1:s.getLevel();refreshSoon();}
        @Override public void onDataConnectionStateChanged(int value,int type){refreshSoon();}
    };
    private final BroadcastReceiver receiver=new BroadcastReceiver(){public void onReceive(Context c,Intent i){refreshSoon();}};
    private final Runnable poll=new Runnable(){public void run(){
        if(!running)return;final int token=generation;final Handler owner=worker;
        final JSONObject next=new JSONObject();
        try{next.put("bluetooth",bluetooth()).put("network",network()).put("usb",usb());}catch(Exception|LinkageError ignored){}
        try{next.put("charging",charging());}catch(Exception|LinkageError ignored){}
        try{next.put("dvr",dvr());}catch(Exception|LinkageError ignored){}
        try{next.put("messages",messages());}catch(Exception|LinkageError ignored){}
        try{next.put("account",account());}catch(Exception|LinkageError ignored){}
        try{
            android.app.ActivityManager.MemoryInfo memory=new android.app.ActivityManager.MemoryInfo();
            ((android.app.ActivityManager)context.getSystemService(Context.ACTIVITY_SERVICE)).getMemoryInfo(memory);
            next.put("memory",new JSONObject().put("totalBytes",memory.totalMem).put("usedBytes",memory.totalMem-memory.availMem));
        }catch(Exception|LinkageError ignored){}
        if(!running||token!=generation||owner!=worker)return;
        String raw=next.toString();if(!raw.equals(state)){state=raw;main.post(()->{if(running)changed.run();});}
        if(running)worker.postDelayed(this,2000);
    }};
    public SystemStatusAdapter(Context context,Runnable changed){this.context=context;this.changed=changed;}
    public void start(){
        if(running)return;running=true;generation++;
        if(thread==null){thread=new HandlerThread("uni-system-status");thread.start();worker=new Handler(thread.getLooper());}
        IntentFilter f=new IntentFilter();for(String a:new String[]{BluetoothAdapter.ACTION_STATE_CHANGED,BluetoothAdapter.ACTION_CONNECTION_STATE_CHANGED,
            "android.bluetooth.a2dp-sink.profile.action.CONNECTION_STATE_CHANGED","android.bluetooth.headsetclient.profile.action.CONNECTION_STATE_CHANGED",
            WifiManager.NETWORK_STATE_CHANGED_ACTION,WifiManager.RSSI_CHANGED_ACTION,"android.net.wifi.WIFI_AP_STATE_CHANGED",ConnectivityManager.CONNECTIVITY_ACTION})f.addAction(a);
        context.registerReceiver(receiver,f);
        try{TelephonyManager t=(TelephonyManager)context.getSystemService(Context.TELEPHONY_SERVICE);t.listen(phoneListener,PhoneStateListener.LISTEN_SIGNAL_STRENGTHS|PhoneStateListener.LISTEN_DATA_CONNECTION_STATE);}catch(Exception|LinkageError ignored){}
        worker.post(poll);
    }
    public void stop(){
        if(!running)return;running=false;generation++;
        try{context.unregisterReceiver(receiver);}catch(Exception|LinkageError ignored){}
        try{((TelephonyManager)context.getSystemService(Context.TELEPHONY_SERVICE)).listen(phoneListener,PhoneStateListener.LISTEN_NONE);}catch(Exception|LinkageError ignored){}
        if(worker!=null)worker.removeCallbacksAndMessages(null);
    }
    private void refreshSoon(){Handler h=worker;if(running&&h!=null){h.removeCallbacks(poll);h.post(poll);}}
    public JSONObject snapshot(){try{return new JSONObject(state);}catch(Exception e){return new JSONObject();}}
    private JSONObject bluetooth(){
        JSONObject j=new JSONObject();try{
            BluetoothAdapter a=BluetoothAdapter.getDefaultAdapter();if(a==null)return j.put("known",true).put("enabled",false);
            boolean audio=a.getProfileConnectionState(11)==BluetoothProfile.STATE_CONNECTED;
            boolean phone=a.getProfileConnectionState(16)==BluetoothProfile.STATE_CONNECTED;
            return j.put("known",true).put("enabled",a.isEnabled()).put("audio",audio).put("phone",phone).put("connected",audio||phone);
        }catch(Exception|LinkageError e){return unavailable(j,e);}
    }
    private JSONObject network(){
        JSONObject j=new JSONObject();
        try{
            ConnectivityManager c=(ConnectivityManager)context.getSystemService(Context.CONNECTIVITY_SERVICE);
            NetworkInfo wi=c.getNetworkInfo(ConnectivityManager.TYPE_WIFI);boolean connected=wi!=null&&wi.isConnected();
            WifiManager w=(WifiManager)context.getApplicationContext().getSystemService(Context.WIFI_SERVICE);
            WifiInfo info=w.getConnectionInfo();j.put("wifiKnown",true).put("wifi",connected)
                .put("wifiLevel",connected&&info!=null?WifiManager.calculateSignalLevel(info.getRssi(),5):-1);
            boolean hotspot=(Boolean)w.getClass().getMethod("isWifiApEnabled").invoke(w);j.put("hotspot",hotspot);
            if(hotspot)try{Object a=api("com.ecarx.xui.adaptapi.wifiap.WifiAp","create");Object clients=call(a,"getWifiApClients");j.put("clientsCallbackRegistered",apCallbackRegistered);if(apClients>=0)j.put("clients",apClients);else if(clients instanceof List&&!((List<?>)clients).isEmpty())j.put("clients",((List<?>)clients).size());}catch(Exception|LinkageError ignored){}
        }catch(Exception|LinkageError ignored){}
        try{
            TelephonyManager t=(TelephonyManager)context.getSystemService(Context.TELEPHONY_SERVICE);
            int type=t.getDataNetworkType();int level=signalLevel;
            if(Build.VERSION.SDK_INT>=28&&level<0){SignalStrength signal=t.getSignalStrength();if(signal!=null)level=signal.getLevel();}
            j.put("mobileKnown",true).put("mobileEnabled",Settings.Global.getInt(context.getContentResolver(),"mobile_data",255)==1)
                .put("mobileLevel",level).put("mobileType",type).put("mobileLabel",networkLabel(type));
        }catch(Exception|LinkageError ignored){}return j;
    }
    private String networkLabel(int type){
        switch(type){case 1:case 2:case 4:case 7:case 11:return "2G";
            case 3:case 5:case 6:case 8:case 9:case 10:case 12:case 14:case 15:return "3G";
            case 13:case 19:return "4G";case 20:return "5G";default:return "";}
    }
    private JSONObject usb(){
        JSONObject j=new JSONObject();try{
            android.os.storage.StorageManager m=(android.os.storage.StorageManager)context.getSystemService(Context.STORAGE_SERVICE);int count=0;
            for(android.os.storage.StorageVolume v:m.getStorageVolumes())if(v.isRemovable()&&(Environment.MEDIA_MOUNTED.equals(v.getState())||Environment.MEDIA_MOUNTED_READ_ONLY.equals(v.getState())))count++;
            return j.put("known",true).put("count",count).put("visible",count>0);
        }catch(Exception|LinkageError e){return unavailable(j,e);}
    }
    private JSONObject charging(){
        JSONObject j=new JSONObject();try{
            Object w=api("com.ecarx.xui.adaptapi.wpc.WPC","create");int mode=((Number)call(w,"getWorkingMode")).intValue(),status=((Number)call(w,"getChargingStatus")).intValue();
            boolean enabled=mode==2,visible=enabled&&status!=1&&status!=Integer.MIN_VALUE+1&&status!=10&&status!=7&&status!=6;
            return j.put("known",true).put("mode",mode).put("status",status).put("visible",visible).put("error",status==2||status==3);
        }catch(Exception|LinkageError e){return unavailable(j,e);}
    }
    private JSONObject dvr(){
        JSONObject j=new JSONObject();try{
            Object device=api("com.ecarx.xui.adaptapi.device.Device","create");
            if(!Boolean.TRUE.equals(call(device,"isDVRCameraConfigured")))return j.put("known",true).put("visible",false);
            Object operation=call(api("com.ecarx.xui.adaptapi.dvr.Dvr","create"),"getOperation");int mode=((Number)call(operation,"getCurrentMode")).intValue();
            return j.put("known",true).put("mode",mode).put("visible",mode==1018||mode==4).put("recording",mode==1018);
        }catch(Exception|LinkageError e){return unavailable(j,e);}
    }
    private JSONObject messages(){
        JSONObject j=new JSONObject();
        if(context.getPackageManager().resolveContentProvider("ecarx.xsf.notificationcenter.provider",0)==null)return j;
        try(android.database.Cursor c=context.getContentResolver().query(Uri.parse("content://ecarx.xsf.notificationcenter.provider/count"),null,null,null,"id asc")){
            if(c!=null&&c.moveToFirst()){int i=c.getColumnIndex("unread_count");if(i>=0)return j.put("known",true).put("count",Math.max(0,c.getInt(i)));}
        }catch(Exception|LinkageError ignored){}return j;
    }
    private JSONObject account(){
        JSONObject j=new JSONObject();try{
            Object userApi=api("com.ecarx.sdk.user.UserAPI","createUserAPI");
            if(userApi==null)return j.put("known",false).put("reason","FACTORY_NULL");
            if(!userReady){
                JSONObject legacy=accountFromProvider();
                if(legacy!=null)return legacy;
                return j.put("known",false).put("reason",userInitState).put("apiVersion",call(userApi,"getVersionInt")).put("implementation",userApi.getClass().getName());
            }
            boolean logged=Boolean.TRUE.equals(call(userApi,"hasLogin"));
            j.put("known",true).put("loggedIn",logged).put("source","user-api");
            if(logged){Object user=call(userApi,"getLoginUser");Object name=call(user,"getNickName");if(name instanceof String)j.put("name",((String)name).substring(0,Math.min(40,((String)name).length())));}
        }catch(Exception|LinkageError ignored){}return j;
    }
    /** The installed member centre's exported legacy SDK provider. Only login
     * state, row identity, display name, avatar and membership level are consumed, never tokens/contact
     * fields. This firmware ignores projection, so no cursor is logged/serialized. */
    private JSONObject accountFromProvider(){
        if(context.getPackageManager().resolveContentProvider("com.ecarx.userProvider",0)==null)return null;
        Uri uri=Uri.parse("content://com.ecarx.userProvider/user");
        try{
            String id;
            try(android.database.Cursor c=context.getContentResolver().query(uri,new String[]{"isLogin","userId"},"isLogin",null,null)){
                if(c==null||!c.moveToFirst())return null;
                int login=c.getColumnIndex("isLogin"),key=c.getColumnIndex("userId");
                if(login<0)return null;
                if(c.getInt(login)!=1)return new JSONObject().put("known",true).put("loggedIn",false).put("source","member-provider");
                if(key<0)return null;id=c.getString(key);if(id==null||id.isEmpty())return null;
            }
            try(android.database.Cursor c=context.getContentResolver().query(uri,new String[]{"userName","userId","avatarUrl","level","levelName"},"User",null,null)){
                if(c==null)return null;int name=c.getColumnIndex("userName"),key=c.getColumnIndex("userId"),avatar=c.getColumnIndex("avatarUrl"),level=c.getColumnIndex("level"),levelName=c.getColumnIndex("levelName");
                if(name<0||key<0)return null;
                while(c.moveToNext())if(id.equals(c.getString(key))){
                    String label=c.getString(name);if(label==null||label.trim().isEmpty())return null;
                    JSONObject result=new JSONObject().put("known",true).put("loggedIn",true).put("name",label.substring(0,Math.min(40,label.length()))).put("source","member-provider");
                    if(avatar>=0&&!c.isNull(avatar)){String value=c.getString(avatar);if(value!=null&&(value.startsWith("https://")||value.startsWith("http://")))result.put("avatarUrl",value.substring(0,Math.min(2048,value.length())));}
                    if(level>=0&&!c.isNull(level))result.put("memberLevel",Math.max(0,c.getInt(level)));
                    if(levelName>=0&&!c.isNull(levelName)){String value=c.getString(levelName);if(value!=null&&!value.trim().isEmpty())result.put("memberLevelName",value.substring(0,Math.min(40,value.length())));}
                    return result;
                }
            }
        }catch(Exception|LinkageError ignored){}return null;
    }
    private JSONObject unavailable(JSONObject j,Throwable error){
        try{j.put("known",false).put("reason",error.getClass().getSimpleName());}catch(Exception ignored){}return j;
    }
    private Object api(String name,String factory)throws Exception{
        if(apis.containsKey(name))return apis.get(name);
        Class<?> type;
        try{type=Class.forName(name);}catch(ClassNotFoundException e){
            if(oemLoader==null)oemLoader=context.createPackageContext("com.ecarx.systemui.plugin",Context.CONTEXT_INCLUDE_CODE|Context.CONTEXT_IGNORE_SECURITY).getClassLoader();
            type=Class.forName(name,true,oemLoader);
        }
        Object value=type.getMethod(factory,Context.class).invoke(null,context);
        if(value!=null){
            apis.put(name,value);
            if("com.ecarx.xui.adaptapi.wifiap.WifiAp".equals(name)){
                Class<?> callback=Class.forName("com.ecarx.xui.adaptapi.wifiap.IWifiApClientCallback",true,type.getClassLoader());
                wifiApCallback=java.lang.reflect.Proxy.newProxyInstance(callback.getClassLoader(),new Class<?>[]{callback},(proxy,m,args)->{
                    if("onWifiApClientChanged".equals(m.getName())){apClients=args!=null&&args.length>0&&args[0] instanceof List?((List<?>)args[0]).size():0;refreshSoon();}
                    if("hashCode".equals(m.getName()))return System.identityHashCode(proxy);
                    if("equals".equals(m.getName()))return args!=null&&args.length>0&&proxy==args[0];
                    if("toString".equals(m.getName()))return "UNI hotspot observer";
                    return null;
                });
                apCallbackRegistered=Boolean.TRUE.equals(type.getMethod("setWifiApClientCallback",callback).invoke(value,wifiApCallback));
            }
            if("com.ecarx.sdk.user.UserAPI".equals(name)){
                int version=((Number)call(value,"getVersionInt")).intValue();
                if(version<330){userReady=true;return value;}
                userInitState="WAITING_CALLBACK";
                Class<?> callback=Class.forName("com.ecarx.sdk.openapi.ECarXApiClient$Callback",true,type.getClassLoader());
                userCallback=java.lang.reflect.Proxy.newProxyInstance(callback.getClassLoader(),new Class<?>[]{callback},(proxy,m,args)->{
                    if("onAPIReady".equals(m.getName())){userReady=args!=null&&args.length>0&&Boolean.TRUE.equals(args[0]);userInitState=userReady?"READY":"API_NOT_READY";refreshSoon();}
                    if("onAPIDisconnected".equals(m.getName())||"onAPIConnectionFailed".equals(m.getName())){userReady=false;userInitState="API_DISCONNECTED";}
                    if("hashCode".equals(m.getName()))return System.identityHashCode(proxy);
                    if("equals".equals(m.getName()))return args!=null&&args.length>0&&proxy==args[0];
                    if("toString".equals(m.getName()))return "UNI status observer";
                    return null;
                });
                type.getMethod("init",Context.class,callback).invoke(value,context,userCallback);
            }
        }return value;
    }
    private Object call(Object target,String method)throws Exception{if(target==null)throw new IllegalStateException("not ready");Method m=target.getClass().getMethod(method);m.setAccessible(true);return m.invoke(target);}
}
