package xyz.i4o.uni.launcher.integration;

import android.content.Context;
import android.os.IBinder;
import java.lang.reflect.Method;
import org.json.JSONObject;
import org.json.JSONArray;
import xyz.i4o.uni.launcher.core.VehicleValues;
import xyz.i4o.uni.launcher.log.LogTags;
import xyz.i4o.uni.launcher.log.UniLog;

/** D01–D05 compatibility READS only. No CB_* invocation, guessed property IDs,
 * copied OEM SDK or optimistic state. One failed getter does not poison others.
 */
public final class LegacyVehicleReader {
    private final Context context;
    private IBinder binder;
    private Object car,climate,vfmisc,signal;
    public LegacyVehicleReader(Context context){this.context=context.getApplicationContext();}
    private static Object get(Object receiver,String name)throws Exception{
        Method method=receiver.getClass().getMethod(name);method.setAccessible(true);return method.invoke(receiver);
    }
    private void connect()throws Exception{
        if(context.checkSelfPermission("android.car.permission.CAR_VENDOR_EXTENSION")!=android.content.pm.PackageManager.PERMISSION_GRANTED){
            UniLog.i(LogTags.VEHICLE,"车辆厂商读取权限未授权","permission","android.car.permission.CAR_VENDOR_EXTENSION","source","legacy");
            throw new SecurityException("Vehicle vendor permission is required before creating the SDK client");
        }
        if(binder!=null&&binder.isBinderAlive()&&car!=null)return;
        UniLog.enter(LogTags.VEHICLE,"vehicle/connect","source","legacy");
        try{
            car=climate=vfmisc=signal=null;
            binder=(IBinder)Class.forName("android.os.ServiceManager").getMethod("getService",String.class).invoke(null,"ecarxcar_service");
            if(binder==null)throw new UnsupportedOperationException("ECARX_BINDER_ABSENT");
            Class<?> api=Class.forName("ecarx.car.IECarXCar");
            Object remote=Class.forName("ecarx.car.IECarXCar$Stub").getMethod("asInterface",IBinder.class).invoke(null,binder);
            car=Class.forName("ecarx.car.ECarXCar").getMethod("createCar",Context.class,api).invoke(null,context,remote);
            Object attributes=car.getClass().getMethod("getCarManager",String.class).invoke(car,"car_publicattribute");
            try{climate=get(attributes,"getECarXCarClimateManager");}catch(Exception ignored){}
            try{vfmisc=get(attributes,"getECarXCarVfmiscManager");}catch(Exception ignored){}
            try{signal=car.getClass().getMethod("getCarManager",String.class).invoke(car,"car_signal");}catch(Exception ignored){}
            UniLog.done(LogTags.VEHICLE,"vehicle/connect","source","legacy","climate",climate!=null,"vfmisc",vfmisc!=null,"signal",signal!=null);
        }catch(Exception e){
            UniLog.fail(LogTags.VEHICLE,"vehicle/connect","source","legacy","error",e.getClass().getSimpleName());
            throw e;
        }catch(Error e){
            UniLog.fail(LogTags.VEHICLE,"vehicle/connect","source","legacy","error",e.getClass().getSimpleName());
            throw e;
        }
    }
    public JSONObject read(){
        JSONObject state=new JSONObject(),fields=new JSONObject(),values=new JSONObject(),seats=new JSONObject();JSONArray errors=new JSONArray();
        UniLog.enter(LogTags.VEHICLE,"vehicle/read","source","legacy");
        try{
            state.put("connected",false).put("writable",false).put("source","官方探测 + ECARX 只读兼容层")
                .put("fields",fields).put("climate",values).put("seatCapabilities",seats).put("errors",errors)
                .put("updatedAtMs",System.currentTimeMillis());
            connect();state.put("connected",true).put("reason","已读取候选车辆字段；数值与单位待上车比对");
            String[][] items={
                {"left","getPA_CL_LeftTemp"},{"right","getPA_CL_RightTemp"},{"fan","getPA_CL_FanLevel"},
                {"auto","getPA_CL_Auto"},{"ac","getPA_CL_AC"},{"power","getPA_CL_ClimateOn"},
                {"sync","getPA_CL_Sync"},{"recirc","getPA_CL_Recirc"},
                {"driverHeat","getPA_SHC_LeSts"},{"driverVent","getPA_SVC_Sts"},{"passengerHeat","getPA_SHC_RiSts"},
                {"pressureFrontLeft","getPA_dTPMS_TirePressureFrntLe"},{"pressureFrontRight","getPA_dTPMS_TirePressureFrntRi"},
                {"pressureRearLeft","getPA_dTPMS_TirePressureReLe"},{"pressureRearRight","getPA_dTPMS_TirePressureReRi"}};
            // The getter loop runs on every read: keep one summary line per cycle
            // instead of one line per item, and keep the raw value next to the reason.
            int failed=0;StringBuilder detail=new StringBuilder();
            for(String[] item:items){
                String key=item[0],method=item[1];JSONObject field=new JSONObject().put("method",method).put("source","ecarxcar_service").put("verified",false).put("valid",false);
                fields.put(key,field);
                try{
                    Object manager=key.startsWith("pressure")?vfmisc:climate;
                    Object payload=get(manager,method);Object data=get(payload,"getData");
                    if(!(data instanceof Number))throw new IllegalStateException("Non-numeric data");
                    Number raw=(Number)data;field.put("raw",raw);
                    Object value;
                    if("auto".equals(key)||"ac".equals(key)||"power".equals(key)||"sync".equals(key)||"recirc".equals(key))value=VehicleValues.flag(key,raw);
                    else value=VehicleValues.decode(key,raw);
                    field.put("valid",value!=null).put("unit",key.startsWith("pressure")?"bar":("left".equals(key)||"right".equals(key))?"°C":"");
                    if(value!=null){field.put("value",value).put("updatedAtMs",System.currentTimeMillis());if(!key.startsWith("pressure"))values.put(key,value);}
                    else{failed++;if(detail.length()>0)detail.append(';');detail.append(key).append("(raw=").append(raw).append(",reason=DECODE_NULL)");}
                }catch(Exception e){errors.put(method+":"+e.getClass().getSimpleName());failed++;if(detail.length()>0)detail.append(';');detail.append(key).append("(reason=").append(e.getClass().getSimpleName()).append(')');}
            }
            if(failed>0)UniLog.w(LogTags.VEHICLE,"部分兼容字段未取得读数","source","legacy","failed",failed,"total",items.length,"details",detail.toString());
            for(String key:new String[]{"driverHeat","driverVent","passengerHeat"})
                seats.put(key,new JSONObject().put("supported",fields.optJSONObject(key).optBoolean("valid")).put("readable",fields.optJSONObject(key).optBoolean("valid")).put("writable",false));
            if(signal!=null)try{state.put("twilightRaw",get(signal,"getTwliBriSts"));}catch(Exception ignored){}
            int count=0;java.util.Iterator<String> keys=fields.keys();while(keys.hasNext())if(fields.getJSONObject(keys.next()).optBoolean("valid"))count++;
            state.put("validFieldCount",count).put("updatedAtMs",System.currentTimeMillis());
            if(count==0){state.put("reason","车辆服务可连接；尚未获得有效字段");UniLog.w(LogTags.VEHICLE,"车辆服务可连接但没有有效字段","source","legacy","total",items.length);}
            UniLog.done(LogTags.VEHICLE,"vehicle/read","source","legacy","valid",count,"failed",failed);
        }catch(Throwable e){try{state.put("connected",false).put("reason",e instanceof UnsupportedOperationException?"当前固件未提供此车辆读取接口":"原车只读接口未就绪或权限不足").put("connectionError",e.getClass().getSimpleName());}catch(Exception ignored){}
            UniLog.fail(LogTags.VEHICLE,"vehicle/read","source","legacy","error",e.getClass().getSimpleName());}
        return state;
    }
    public void close(){car=climate=vfmisc=signal=null;binder=null;UniLog.i(LogTags.VEHICLE,"兼容读取器已关闭","source","legacy");}
}
