package xyz.i4o.uni.launcher.integration;

import android.content.Context;
import android.content.SharedPreferences;
import android.provider.Settings;
import org.json.JSONObject;
import java.net.InetSocketAddress;
import java.net.Socket;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import xyz.i4o.uni.launcher.log.LogTags;
import xyz.i4o.uni.launcher.log.UniLog;

/** Read back ADB state; all property writes and daemon restarts run off the UI thread. */
public final class DebugBridge {
    private final Context context;
    private final SharedPreferences prefs;
    private final Runnable changed;
    private final ExecutorService worker=Executors.newSingleThreadExecutor();
    private volatile boolean usb,network,busy;
    private volatile String detail="";
    public DebugBridge(Context context,SharedPreferences prefs,Runnable changed){
        this.context=context.getApplicationContext();this.prefs=prefs;this.changed=changed;
    }
    private static String prop(String key)throws Exception{
        return (String)Class.forName("android.os.SystemProperties").getMethod("get",String.class).invoke(null,key);
    }
    private static void set(String key,String value)throws Exception{
        Class.forName("android.os.SystemProperties").getMethod("set",String.class,String.class).invoke(null,key,value);
    }
    private static boolean listening(){
        try(Socket socket=new Socket()){socket.connect(new InetSocketAddress("127.0.0.1",5555),300);return true;}
        catch(Exception e){return false;}
    }
    private void read(){
        usb=Settings.Global.getInt(context.getContentResolver(),"adb_enabled",0)==1;
        try{
            String port=prop("service.adb.tcp.port");
            if(port.isEmpty())port=prop("persist.adb.tcp.port");
            network="5555".equals(port)&&listening();
        }catch(Exception e){network=false;}
    }
    private void notifyChange(){new android.os.Handler(android.os.Looper.getMainLooper()).post(changed);}
    public JSONObject snapshot(){
        JSONObject result=new JSONObject();try{result.put("adb",usb).put("network",network).put("busy",busy).put("detail",detail);}catch(Exception ignored){}return result;
    }
    public void refresh(){UniLog.enter(LogTags.DEBUG,"debug/refresh");worker.execute(()->{read();notifyChange();UniLog.done(LogTags.DEBUG,"debug/refresh","usb",usb,"network",network);});}
    public void startup(){
        UniLog.enter(LogTags.DEBUG,"debug/startup");
        worker.execute(()->{
            read();
            if(prefs.getBoolean("debugAdbDesired",true)&&!usb)writeAdb(true);
            read();
            if(prefs.getBoolean("debugNetworkDesired",true)&&!network)writeNetwork(true);
            read();notifyChange();
            UniLog.done(LogTags.DEBUG,"debug/startup","usb",usb,"network",network);
        });
    }
    public void change(boolean isNetwork,boolean enabled){
        prefs.edit().putBoolean(isNetwork?"debugNetworkDesired":"debugAdbDesired",enabled).apply();
        busy=true;notifyChange();
        worker.execute(()->{if(isNetwork)writeNetwork(enabled);else writeAdb(enabled);read();busy=false;notifyChange();});
    }
    private void writeAdb(boolean enabled){
        UniLog.enter(LogTags.DEBUG,"debug/write","target","usb","enabled",enabled);
        try{
            if(!Settings.Global.putInt(context.getContentResolver(),"adb_enabled",enabled?1:0))throw new IllegalStateException("系统未接受 ADB 设置");
            if((Settings.Global.getInt(context.getContentResolver(),"adb_enabled",0)==1)!=enabled)throw new IllegalStateException("ADB 回读不一致");
            detail="";
            UniLog.done(LogTags.DEBUG,"debug/write","target","usb","enabled",enabled);
        }catch(Exception e){
            detail="ADB 设置失败："+message(e);
            UniLog.fail(LogTags.DEBUG,"debug/write","target","usb","enabled",enabled,"error",detail);
        }
    }
    private void writeNetwork(boolean enabled){
        String changedKey=null,oldValue=null;
        UniLog.enter(LogTags.DEBUG,"debug/write","target","network","enabled",enabled);
        try{
            String service=prop("service.adb.tcp.port"),persist=prop("persist.adb.tcp.port");
            String target=enabled?"5555":"-1";
            try{set("service.adb.tcp.port",target);changedKey="service.adb.tcp.port";oldValue=service;}
            catch(Exception denied){
                if(!service.isEmpty())throw denied;
                set("persist.adb.tcp.port",target);
                changedKey="persist.adb.tcp.port";oldValue=persist;
            }
            String effective=prop("service.adb.tcp.port");
            if(effective.isEmpty())effective=prop("persist.adb.tcp.port");
            if(!target.equals(effective))throw new IllegalStateException("网络 ADB 端口回读不一致");
            try{set("ctl.restart","adbd");}
            catch(Exception denied){
                if(context.checkSelfPermission("android.permission.MANAGE_USB")!=0)throw denied;
                Object manager=context.getSystemService(Context.USB_SERVICE);
                long original=((Long)manager.getClass().getMethod("getCurrentFunctions").invoke(manager)).longValue();
                java.lang.reflect.Method change=manager.getClass().getMethod("setCurrentFunctions",long.class);
                try{change.invoke(manager,original==4L?0L:4L);Thread.sleep(1500);}finally{change.invoke(manager,original);}
            }
            boolean matched=false;
            for(int i=0;i<16;i++){if(listening()==enabled){matched=true;break;}Thread.sleep(350);}
            if(!matched)throw new IllegalStateException("网络 ADB 服务状态未达到预期");
            detail="";
            UniLog.done(LogTags.DEBUG,"debug/write","target","network","enabled",enabled,"port",enabled?"5555":"-1");
        }catch(Exception e){
            if(changedKey!=null)try{set(changedKey,oldValue);}catch(Exception rollback){e.addSuppressed(rollback);}
            detail="网络 ADB 设置失败："+message(e);
            UniLog.fail(LogTags.DEBUG,"debug/write","target","network","enabled",enabled,"port",enabled?"5555":"-1","error",detail);
        }
    }
    private static String message(Throwable e){
        while(e.getCause()!=null)e=e.getCause();
        return e.getMessage()==null?e.getClass().getSimpleName():e.getMessage();
    }
}
