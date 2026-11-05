package xyz.i4o.uni.launcher.integration;

import android.content.Context;
import org.json.JSONObject;
import xyz.i4o.uni.launcher.log.LogTags;
import xyz.i4o.uni.launcher.log.UniLog;

/** Official CarUtils path: Car.create -> getICarFunction. Read-only capability probe.
 * The official APK delegates HVAC to another app; it provides no verified climate write contract.
 */
public final class OfficialVehicleAdapter implements VehicleAdapter {
    private final JSONObject state = new JSONObject();
    public OfficialVehicleAdapter(Context context) {
        UniLog.enter(LogTags.VEHICLE, "vehicle/connect", "source", "official-adapter");
        try {
            state.put("connected", false).put("writable", false).put("source", "官方 ECARX 适配层");
            JSONObject seats = new JSONObject();
            for (String control : new String[]{"driverHeat", "driverVent", "passengerHeat"}) {
                seats.put(control, new JSONObject().put("supported", false).put("writable", false).put("reason", "待车辆确认"));
            }
            state.put("seatCapabilities", seats);
            boolean allowed=context.checkSelfPermission("android.car.permission.CAR_VENDOR_EXTENSION")==android.content.pm.PackageManager.PERMISSION_GRANTED;
            state.put("vendorPermissionGranted",allowed);
            if(!allowed){
                UniLog.i(LogTags.VEHICLE,"车辆读取权限未授权","permission","android.car.permission.CAR_VENDOR_EXTENSION","source","official-adapter");
                UniLog.fail(LogTags.VEHICLE,"vehicle/connect","source","official-adapter","reason","PERMISSION_DENIED");
                state.put("reason","车辆读取权限未授权");return;}
            Class<?> api = Class.forName("com.ecarx.xui.adaptapi.car.Car");
            Object car = api.getMethod("create", Context.class).invoke(null, context);
            if (car == null) {
                UniLog.fail(LogTags.VEHICLE,"vehicle/connect","source","official-adapter","reason","SERVICE_NOT_READY");
                state.put("reason", "车辆服务尚未就绪"); return; }
            state.put("frameworkPresent", true);
            Object functions = car.getClass().getMethod("getICarFunction").invoke(car);
            Object camera = functions.getClass().getMethod("getFunctionValue", int.class).invoke(functions, 587400448);
            state.put("cameraConfiguration", camera).put("probeAvailable",true);
            UniLog.i(LogTags.VEHICLE,"相机能力探测","raw",String.valueOf(camera),"source","official-adapter");
            try{Object sensors=car.getClass().getMethod("getSensorManager").invoke(car);Object supported=sensors.getClass().getMethod("isSensorSupported",int.class).invoke(sensors,1049344);state.put("pm25SupportRaw",String.valueOf(supported));UniLog.i(LogTags.VEHICLE,"PM2.5 传感器探测","raw",String.valueOf(supported),"source","official-adapter");}catch(Exception ignored){}
            state.put("reason", "框架可访问；空调与车辆字段待实车核对");
            UniLog.done(LogTags.VEHICLE,"vehicle/connect","source","official-adapter","camera",String.valueOf(camera));
        } catch (ClassNotFoundException e) {
            putReason("当前设备没有原车框架");
            UniLog.w(LogTags.VEHICLE,"当前设备没有原车框架",e,"source","official-adapter");
            UniLog.fail(LogTags.VEHICLE,"vehicle/connect","source","official-adapter","reason","FRAMEWORK_ABSENT");
        } catch (LinkageError e) {
            putReason("原车框架版本不兼容");
            UniLog.w(LogTags.VEHICLE,"原车框架版本不兼容",e,"source","official-adapter");
            UniLog.fail(LogTags.VEHICLE,"vehicle/connect","source","official-adapter","reason","FRAMEWORK_INCOMPATIBLE");
        } catch (Exception e) {
            putReason("原车服务未连接或访问权限不足");
            UniLog.i(LogTags.VEHICLE, "OEM 探测不可用", "tag", "UniVehicle", "error", e.getClass().getSimpleName());
            UniLog.fail(LogTags.VEHICLE,"vehicle/connect","source","official-adapter","reason","PROBE_FAILED","error",e.getClass().getSimpleName());
        }
    }
    private void putReason(String reason) {try {state.put("reason", reason);} catch (Exception ignored) {}}
    public JSONObject snapshot() { return state; }
    public boolean command(String action, String zone, String mode) { return false; }
    public void close() {}
}
