package xyz.i4o.uni.launcher.integration;

import android.content.Context;
import org.json.JSONObject;

/** Official CarUtils path: Car.create -> getICarFunction. Read-only capability probe.
 * The official APK delegates HVAC to another app; it provides no verified climate write contract.
 */
public final class OfficialVehicleAdapter implements VehicleAdapter {
    private final JSONObject state = new JSONObject();
    public OfficialVehicleAdapter(Context context) {
        try {
            state.put("connected", false).put("writable", false).put("source", "官方 ECARX 适配层");
            JSONObject seats = new JSONObject();
            for (String control : new String[]{"driverHeat", "driverVent", "passengerHeat"}) {
                seats.put(control, new JSONObject().put("supported", false).put("writable", false).put("reason", "待车辆确认"));
            }
            state.put("seatCapabilities", seats);
            boolean allowed=context.checkSelfPermission("android.car.permission.CAR_VENDOR_EXTENSION")==android.content.pm.PackageManager.PERMISSION_GRANTED;
            state.put("vendorPermissionGranted",allowed);
            if(!allowed){state.put("reason","车辆读取权限未授权");return;}
            Class<?> api = Class.forName("com.ecarx.xui.adaptapi.car.Car");
            Object car = api.getMethod("create", Context.class).invoke(null, context);
            if (car == null) { state.put("reason", "车辆服务尚未就绪"); return; }
            state.put("frameworkPresent", true);
            Object functions = car.getClass().getMethod("getICarFunction").invoke(car);
            Object camera = functions.getClass().getMethod("getFunctionValue", int.class).invoke(functions, 587400448);
            state.put("cameraConfiguration", camera).put("probeAvailable",true);
            try{Object sensors=car.getClass().getMethod("getSensorManager").invoke(car);Object supported=sensors.getClass().getMethod("isSensorSupported",int.class).invoke(sensors,1049344);state.put("pm25SupportRaw",String.valueOf(supported));}catch(Exception ignored){}
            state.put("reason", "框架可访问；空调与车辆字段待实车核对");
        } catch (ClassNotFoundException e) {
            putReason("当前设备没有原车框架");
        } catch (LinkageError e) {
            putReason("原车框架版本不兼容");
        } catch (Exception e) {
            putReason("原车服务未连接或访问权限不足");
            android.util.Log.i("UniVehicle", "OEM probe unavailable: " + e.getClass().getSimpleName());
        }
    }
    private void putReason(String reason) {try {state.put("reason", reason);} catch (Exception ignored) {}}
    public JSONObject snapshot() { return state; }
    public boolean command(String action, String zone, String mode) { return false; }
    public void close() {}
}
