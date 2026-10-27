package xyz.i4o.uni.launcher.integration;

import android.content.Context;
import org.json.JSONObject;

/** Lifecycle owner for the audited official DCY11 transport.
 * The reader performs getters, subscriptions and writes on its own worker;
 * Flutter only receives immutable cached snapshots. No obsolete service poll.
 */
public final class VehicleTelemetry implements VehicleAdapter {
    private final Context context;
    private final Runnable changed;
    private volatile OfficialCarReader reader;
    public VehicleTelemetry(Context context,Runnable changed){this.context=context.getApplicationContext();this.changed=changed;}
    public synchronized void start(){
        if(reader!=null)return;
        reader=new OfficialCarReader(context,changed);reader.start();
    }
    public JSONObject snapshot(){
        OfficialCarReader current=reader;
        if(current!=null)return current.snapshot();
        JSONObject result=new JSONObject();try{result.put("connected",false).put("writable",false)
            .put("reason","车辆数据读取已暂停").put("fields",new JSONObject())
            .put("climate",new JSONObject()).put("seatCapabilities",new JSONObject());}catch(Exception ignored){}
        return result;
    }
    public boolean command(String action,String zone,String mode){OfficialCarReader current=reader;return current!=null&&current.command(action,zone,mode);}
    /** -1 while disconnected; otherwise the official PAC camera gate value. */
    public int cameraCapability(){OfficialCarReader current=reader;return current==null?-1:current.cameraCapability();}
    public synchronized void stop(){OfficialCarReader old=reader;reader=null;if(old!=null)old.close();}
    public void close(){stop();}
}
