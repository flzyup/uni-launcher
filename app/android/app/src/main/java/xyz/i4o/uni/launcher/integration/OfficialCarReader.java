package xyz.i4o.uni.launcher.integration;

import android.content.ComponentName;
import android.content.Context;
import android.content.ServiceConnection;
import android.content.pm.PackageManager;
import android.os.Handler;
import android.os.IBinder;
import android.os.Looper;
import android.os.SystemClock;
import java.lang.reflect.InvocationTargetException;
import java.lang.reflect.InvocationHandler;
import java.lang.reflect.Method;
import java.lang.reflect.Proxy;
import java.lang.ref.WeakReference;
import java.util.ArrayList;
import java.util.List;
import java.util.concurrent.Executors;
import java.util.concurrent.RejectedExecutionException;
import java.util.concurrent.ScheduledExecutorService;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicBoolean;
import java.util.concurrent.atomic.AtomicInteger;
import org.json.JSONArray;
import org.json.JSONObject;

/**
 * DCY11 reader/controller with no OEM binary dependency. Only an explicit UI
 * command() call can enqueue a write. Polling, SDK callbacks and startup are read-only.
 * Usage: construct once, start(), snapshot()/read(), close(). read() starts lazily
 * and returns the latest cached snapshot, without blocking the caller on Binder.
 * An optional changed callback runs on MAIN. All getters and subscriptions run
 * on one worker. This helper does not modify or attach to VehicleTelemetry.
 *
 * Official Car.create/IConnectable controls SDK readiness, support and callbacks.
 * A second, standard android.car.Car property connection preserves the PA bytes,
 * HAL status and timestamp which the SDK getters discard. This is the identical
 * CarPropertyManager transport used by VehicleSignalManager, not the obsolete
 * ecarxcar_service. Unknown raw enums never become a synthetic OFF reading.
 *
 * Field valid means an active, typed, bounded reading. verified remains false
 * until compared with the car UI. Pressure values retain unit=raw: the available
 * unit setting proves a display preference, not the physical PA data unit.
 */
public final class OfficialCarReader implements VehicleAdapter {
    private static final Class<?>[] NONE = new Class<?>[0];
    // This SDK has no unregisterReadyChangedCallback. Register exactly one SDK
    // watcher per process; activity-scoped readers are held only weakly.
    private static Object sharedSdkCar, sharedFunctions, sharedSignals, sharedWatcher;
    private static boolean sharedReady;
    private static final List<WeakReference<OfficialCarReader>> readers = new ArrayList<>();
    private final Context context;
    private final Runnable changed;
    private final Handler main = new Handler(Looper.getMainLooper());
    private final ScheduledExecutorService worker = Executors.newSingleThreadScheduledExecutor();
    private final AtomicBoolean queued = new AtomicBoolean();
    private final AtomicBoolean commandBusy = new AtomicBoolean();
    private final AtomicInteger connectionEpoch = new AtomicInteger();
    private final List<Registration> registrations = new ArrayList<>(); // worker only
    private volatile boolean started, closed, sdkReady;
    private volatile Object sdkCar, functions, signals, androidCar, propertyManager;
    private volatile String setupError = "";
    private volatile String stateJson = "{}";
    private volatile long publishedAtElapsed;
    private boolean subscribed; // worker only
    private volatile boolean writeSignaturesAvailable;
    private volatile String lastCommandJson = "{}";
    private volatile int cameraCapability = -1;
    private long commandSequence;
    private PendingCommand pending; // worker only; never replayed/retried

    public OfficialCarReader(Context context) { this(context, null); }

    public OfficialCarReader(Context context, Runnable changed) {
        this.context = context.getApplicationContext();
        this.changed = changed;
        publishUnavailable("等待官方车辆读取器启动");
    }

    public synchronized void start() {
        if (started || closed) return;
        started = true;
        main.post(new Runnable() { public void run() { initializeOnMain(); } });
        worker.scheduleWithFixedDelay(new Runnable() { public void run() { collectSafely(); } }, 0, 1, TimeUnit.SECONDS);
    }

    public JSONObject read() { start(); return snapshot(); }

    @Override public JSONObject snapshot() {
        try {
            if (publishedAtElapsed > 0 && SystemClock.elapsedRealtime() - publishedAtElapsed > 5000)
                return unavailable("车辆读取已超时，等待服务恢复");
            return new JSONObject(stateJson).put("lastCommand", new JSONObject(lastCommandJson));
        } catch (Exception e) { return new JSONObject(); }
    }

    /** UI entry only. true means queued, not executed/confirmed. Observe lastCommand.
     * No intent/receiver/background task calls this method. One command at a time.
     */
    @Override public synchronized boolean command(final String action, final String zone, final String mode) {
        boolean acquired = false;
        final String key = OfficialCarCommand.key(action, zone, mode);
        if (key == null || closed || !started || !sdkReady || propertyManager == null || !permitted()) return false;
        try {
            JSONObject state = snapshot();
            JSONObject field = state.getJSONObject("fields").optJSONObject(key);
            if (!writeSignaturesAvailable || !freshWritable(field)) return false;
            if (OfficialCarCommand.plan(action, zone, mode, field.opt("value"), state.optInt("driverZone"), 16, 31, 0.5) == null) return false;
            if (!commandBusy.compareAndSet(false, true)) return false;
            acquired = true;
            final long id = ++commandSequence, requestedAt = SystemClock.elapsedRealtime();
            final int epoch = connectionEpoch.get();
            commandStatus(id, key, "queued", "等待发送");
            worker.execute(new Runnable() { public void run() { executeUiCommand(id, key, action, zone, mode, requestedAt, epoch); } });
            return true;
        } catch (Exception e) { if (acquired) commandBusy.set(false); return false; }
    }

    /** Latest official PAC camera gate: -1 disconnected/unknown, otherwise
     * PAC_CAMERA_NONE / REARONLY / 360AM. Refreshed with every poll. */
    public int cameraCapability() { return cameraCapability; }

    private boolean permitted() {
        return context.checkSelfPermission(OfficialCarContract.PERMISSION) == PackageManager.PERMISSION_GRANTED;
    }

    private final ServiceConnection propertyConnection = new ServiceConnection() {
        @Override public void onServiceConnected(ComponentName name, IBinder binder) {
            if (closed) return;
            try {
                propertyManager = call(androidCar, "getCarManager", new Class<?>[]{String.class}, "property");
                if (propertyManager == null) setupError = "PROPERTY_MANAGER_ABSENT";
            } catch (Exception | LinkageError e) { setupError = failure(e); }
            refreshSoon();
        }
        @Override public void onServiceDisconnected(ComponentName name) {
            connectionEpoch.incrementAndGet();
            propertyManager = null;
            refreshSoon();
        }
    };

    private void initializeOnMain() {
        if (closed) return;
        if (!permitted()) { publishUnavailable("车辆厂商读取权限未授权"); return; }
        try {
            attachSharedSdk();
            try {
                functions.getClass().getMethod("setFunctionValue", int.class, int.class);
                functions.getClass().getMethod("setFunctionValue", int.class, int.class, int.class);
                functions.getClass().getMethod("setCustomizeFunctionValue", int.class, int.class, float.class);
                writeSignaturesAvailable = true;
            } catch (NoSuchMethodException missingWriteContract) { writeSignaturesAvailable = false; }
            // Public Android 9 signature confirmed in the actual android.car.jar.
            androidCar = Class.forName("android.car.Car")
                    .getMethod("createCar", Context.class, ServiceConnection.class)
                    .invoke(null, context, propertyConnection);
            if (androidCar == null) throw new IllegalStateException("ANDROID_CAR_ABSENT");
            call(androidCar, "connect", NONE);
        } catch (Exception | LinkageError e) {
            setupError = failure(e);
            publishUnavailable("官方车辆接口初始化失败：" + setupError);
        }
    }

    private void attachSharedSdk() throws Exception {
        synchronized (OfficialCarReader.class) {
            if (sharedSdkCar == null) {
                Object car = Class.forName(OfficialCarContract.SDK_CAR).getMethod("create", Context.class).invoke(null, context);
                if (car == null) throw new IllegalStateException("SDK_CAR_ABSENT");
                Object function = call(car, "getICarFunction", NONE);
                Object signal = Class.forName(OfficialCarContract.SIGNALS).getMethod("getInstance", Context.class).invoke(null, context);
                Class<?> type = Class.forName(OfficialCarContract.CONNECT_WATCHER);
                Object watcher = proxy(type, new Callback() { public void event(String name, Object[] args) { dispatchSharedConnection(name); } });
                call(car, "registerConnectWatcher", new Class<?>[]{type}, watcher);
                sharedSdkCar = car; sharedFunctions = function; sharedSignals = signal; sharedWatcher = watcher;
            }
            sdkCar = sharedSdkCar; functions = sharedFunctions; signals = sharedSignals;
            sdkReady = sharedReady;
            readers.add(new WeakReference<>(this));
        }
    }

    private static void dispatchSharedConnection(String name) {
        synchronized (OfficialCarReader.class) {
            if ("onConnected".equals(name)) sharedReady = true;
            else if ("onDisConnected".equals(name)) sharedReady = false;
            else return;
            java.util.Iterator<WeakReference<OfficialCarReader>> iterator = readers.iterator();
            while (iterator.hasNext()) {
                OfficialCarReader reader = iterator.next().get();
                if (reader == null || reader.closed) { iterator.remove(); continue; }
                reader.sdkReady = sharedReady;
                if (!sharedReady) reader.connectionEpoch.incrementAndGet();
                reader.refreshSoon();
            }
        }
    }

    private void refreshSoon() {
        if (!started || closed || !queued.compareAndSet(false, true)) return;
        try {
            worker.execute(new Runnable() { public void run() {
                queued.set(false);
                collectSafely();
            } });
        } catch (RejectedExecutionException e) { queued.set(false); }
    }

    private void collectSafely() {
        if (closed) return;
        if (pending != null && SystemClock.elapsedRealtime() > pending.deadline) finishCommand("timeout", "未在5秒内获得目标状态读回");
        if (!permitted()) { publishUnavailable("车辆厂商读取权限未授权"); return; }
        if (!sdkReady || propertyManager == null) {
            if (pending != null) finishCommand("failed", "车辆服务已断开；命令不重放");
            publishUnavailable(setupError.isEmpty() ? "等待官方车辆服务连接" : setupError);
            return;
        }
        try {
            JSONObject state = base();
            JSONObject fields = state.getJSONObject("fields"), climate = state.getJSONObject("climate");
            JSONArray errors = state.getJSONArray("errors");
            subscribe(errors);
            int driverZone = driverZone(errors);
            state.put("driverZone", driverZone);
            add(fields, readField("left", OfficialCarContract.PA_LEFT_TEMP, OfficialCarContract.TEMP, 1, "temp"), "left");
            add(fields, readField("right", OfficialCarContract.PA_RIGHT_TEMP, OfficialCarContract.TEMP, 4, "temp"), "right");
            add(fields, readField("fan", OfficialCarContract.PA_FAN, OfficialCarContract.FAN, 0, "fan"), "fan");
            add(fields, readField("auto", OfficialCarContract.PA_AUTO, OfficialCarContract.AUTO, 0, "switch"), "auto");
            add(fields, readField("ac", OfficialCarContract.PA_AC, OfficialCarContract.AC, 0, "switch"), "ac");
            add(fields, readField("power", OfficialCarContract.PA_POWER, OfficialCarContract.POWER, 0, "switch"), "power");
            add(fields, readField("sync", OfficialCarContract.PA_SYNC, OfficialCarContract.SYNC, 0, "switch"), "sync");
            add(fields, readField("recirc", OfficialCarContract.PA_RECIRC, OfficialCarContract.CIRCULATION, 0, "switch"), "recirc");
            add(fields, readField("frontDefrostMax", OfficialCarContract.PA_FRONT_MAX, OfficialCarContract.FRONT_MAX, 0, "switch"), "frontDefrostMax");
            add(fields, readField("rearDefrost", OfficialCarContract.PA_REAR_DEFROST, OfficialCarContract.REAR_DEFROST, 0, "switch"), "rearDefrost");
            add(fields, readField("blowing", OfficialCarContract.PA_BLOWING, OfficialCarContract.BLOWING, 0, "blowing"), "blowing");
            JSONObject leftHeat = readField("leftSeatHeat", OfficialCarContract.PA_LEFT_HEAT, OfficialCarContract.HEAT, 1, "seat");
            JSONObject rightHeat = readField("rightSeatHeat", OfficialCarContract.PA_RIGHT_HEAT, OfficialCarContract.HEAT, 4, "seat");
            add(fields, leftHeat, "leftSeatHeat"); add(fields, rightHeat, "rightSeatHeat");
            if (driverZone != 0) {
                add(fields, copy(driverZone == 1 ? leftHeat : rightHeat), "driverHeat");
                add(fields, copy(driverZone == 1 ? rightHeat : leftHeat), "passengerHeat");
                add(fields, readField("driverVent", OfficialCarContract.PA_VENT, OfficialCarContract.VENT, driverZone, "seat"), "driverVent");
            } else {
                add(fields, invalid("驾驶位配置尚未确认"), "driverHeat");
                add(fields, invalid("驾驶位配置尚未确认"), "passengerHeat");
                add(fields, invalid("驾驶位配置尚未确认"), "driverVent");
                add(fields, readField("seatVentilation", OfficialCarContract.PA_VENT, 0, 0, "seat"), "seatVentilation");
            }
            add(fields, readField("pressureFrontLeft", OfficialCarContract.PA_PRESSURE_FL, 0, 0, "pressure"), "pressureFrontLeft");
            add(fields, readField("pressureFrontRight", OfficialCarContract.PA_PRESSURE_FR, 0, 0, "pressure"), "pressureFrontRight");
            add(fields, readField("pressureRearLeft", OfficialCarContract.PA_PRESSURE_RL, 0, 0, "pressure"), "pressureRearLeft");
            add(fields, readField("pressureRearRight", OfficialCarContract.PA_PRESSURE_RR, 0, 0, "pressure"), "pressureRearRight");
            add(fields, readField("pressureUnitPreference", OfficialCarContract.PA_PRESSURE_UNIT, 0, 0, "pressureUnit"), "pressureUnitPreference");
            // Owner-confirmed on 2026-10-25: the original UI shows driving range
            // in km. Speed stays unconfirmed until a moving comparison.
            JSONObject extraSensors=new OfficialVehicleSensors(sdkCar,signals,
                    OfficialVehicleSensors.Units.confirmed(null, "km", "owner confirmed original UI range km 2026-10-25")).appendTo(fields);
            new OfficialHybridReader(propertyManager).appendTo(fields);
            int capability = -1;
            try {
                Object value = call(functions, "getFunctionValue", new Class<?>[]{int.class}, OfficialCarContract.PAC_CAMERA_CAPABILITY);
                if (value instanceof Number) capability = ((Number) value).intValue();
            } catch (Exception | LinkageError ignored) {}
            cameraCapability = capability;
            state.put("cameraCapability", capability);
            JSONArray sensorErrors=extraSensors.optJSONArray("errors");
            if(sensorErrors!=null)for(int i=0;i<sensorErrors.length();i++)errors.put(sensorErrors.get(i));
            int validCount = 0;
            java.util.Iterator<String> keys = fields.keys();
            while (keys.hasNext()) {
                String key = keys.next(); JSONObject field = fields.getJSONObject(key);
                if (field.optBoolean("valid")) {
                    validCount++;
                    if (!key.startsWith("pressure")) climate.put(key, field.get("value"));
                } else errors.put(key + ":" + field.optString("reason"));
            }
            JSONObject seats = state.getJSONObject("seatCapabilities");
            for (String key : new String[]{"driverHeat", "driverVent", "passengerHeat"}) {
                JSONObject field = fields.getJSONObject(key);
                seats.put(key, new JSONObject().put("supported", field.optBoolean("supported"))
                        .put("readable", field.optBoolean("valid")).put("writable", freshWritable(field))
                        .put("reason", field.optBoolean("valid") ? "官方接口已读取" : field.optString("reason")));
            }
            JSONObject capabilities = new JSONObject(); boolean anyWritable = false;
            for (String key : new String[]{"left", "right", "fan", "power", "auto", "ac", "recirc", "sync"}) {
                JSONObject field = fields.getJSONObject(key); boolean writable = freshWritable(field);
                anyWritable |= writable;
                capabilities.put(key, new JSONObject().put("supported", field.optBoolean("supported"))
                        .put("readable", field.optBoolean("valid")).put("writable", writable));
            }
            checkPending(fields);
            state.put("writable", anyWritable).put("readOnly", false).put("climateCapabilities", capabilities);
            state.put("connected", true).put("validFieldCount", validCount)
                    .put("reason", validCount > 0 ? "已读取官方车辆状态；按各项能力接受用户操作" : "服务已连接，字段尚无有效读数");
            publish(state);
        } catch (Exception | LinkageError e) { publishUnavailable("官方车辆读取失败：" + failure(e)); }
    }

    private JSONObject readField(String key, int property, int function, int zone, String kind) throws Exception {
        JSONObject field = invalid("尚未获得有效读数").put("propertyId", property)
                .put("propertyHex", String.format("0x%08x", property)).put("areaId", 0)
                .put("functionId", function).put("zone", zone).put("encoding", "GeelyProto.PublicAttrValue");
        field.put("kind", kind).put("source", "官方 CarPropertyManager PA");
        try {
            Object value = call(propertyManager, "getProperty", new Class<?>[]{Class.class, int.class, int.class}, byte[].class, property, 0);
            if (value == null) throw new IllegalStateException("PROPERTY_VALUE_ABSENT");
            int halStatus = ((Number) call(value, "getStatus", NONE)).intValue();
            field.put("halStatus", halStatus).put("sourceTimestampNanos", call(value, "getTimestamp", NONE));
            if (halStatus != 0) throw new IllegalStateException("HAL_STATUS_" + halStatus);
            OfficialCarPayload pa = OfficialCarPayload.parse((byte[]) call(value, "getValue", NONE));
            field.put("availabilityRaw", pa.availability).put("formatRaw", pa.format)
                    .put("statusRaw", pa.status).put("raw", pa.data).put("wireInt32", pa.int32Wire).put("levelRaw", pa.level);
            field.put("supported", pa.availability != null && pa.availability != 0);
            if (!pa.active()) throw new IllegalStateException("PA_NOT_ACTIVE_" + pa.availability);
            if (function != 0) {
                Object support = zone == 0
                        ? call(functions, "isFunctionSupported", new Class<?>[]{int.class}, function)
                        : call(functions, "isFunctionSupported", new Class<?>[]{int.class, int.class}, function, zone);
                String status = String.valueOf(support);
                field.put("supportStatus", status);
                if (!"active".equals(status)) {
                    field.put("supported", !"notavailable".equals(status) && !"error".equals(status));
                    throw new IllegalStateException("FUNCTION_" + status);
                }
            }
            Object decoded = decode(pa, kind, field);
            if ("pressureUnit".equals(kind)) {
                try { field.put("sdkMappedValue", call(functions, "getFunctionValue", new Class<?>[]{int.class}, OfficialCarContract.TIRE_PRESSURE_UNIT)); }
                catch (Exception e) { field.put("sdkReadError", failure(e)); }
            }
            if (decoded == null) throw new IllegalStateException("UNKNOWN_ENUM_OR_RANGE");
            boolean mappingConsistent = checkSdkMapping(function, zone, kind, pa, field);
            field.put("valid", true).put("value", decoded).put("updatedAtMs", System.currentTimeMillis())
                    .put("updatedAtElapsedMs", SystemClock.elapsedRealtime())
                    .put("reason", "");
            boolean control = function == OfficialCarContract.TEMP || function == OfficialCarContract.FAN
                    || function == OfficialCarContract.POWER || function == OfficialCarContract.AUTO
                    || function == OfficialCarContract.AC || function == OfficialCarContract.CIRCULATION
                    || function == OfficialCarContract.SYNC || function == OfficialCarContract.HEAT || function == OfficialCarContract.VENT;
            field.put("writable", control && writeSignaturesAvailable && permitted()
                    && mappingConsistent
                    && (!"temp".equals(kind) || "°C".equals(field.optString("sourceUnit")))
                    && (!"fan".equals(kind) || !field.optBoolean("automatic")));
        } catch (Exception | LinkageError e) { field.put("reason", failure(e)); }
        return field;
    }

    /** Compare native PA with the real official mapper, rather than visual icon guesses.
     * A transient change between two reads is diagnostic and disables only that write.
     */
    private boolean checkSdkMapping(int function, int zone, String kind, OfficialCarPayload pa, JSONObject field) throws Exception {
        if (function == 0) return true;
        try {
            Number expected;
            if ("temp".equals(kind)) expected = pa.doubleData();
            else if ("seat".equals(kind)) expected = pa.integerData() == 0 ? 0 : function + pa.integerData();
            else if ("fan".equals(kind)) expected = field.getInt("sdkValue");
            else if ("blowing".equals(kind)) expected = OfficialCarContract.blowingSdkValue(pa.integerData());
            else if (function == OfficialCarContract.CIRCULATION)
                expected = pa.integerData() == 1 ? OfficialCarContract.CIRCULATION_INNER : OfficialCarContract.CIRCULATION_OUTSIDE;
            else expected = pa.integerData();
            String getter = "temp".equals(kind) ? "getCustomizeFunctionValue" : "getFunctionValue";
            Object actual = zone == 0 ? call(functions, getter, new Class<?>[]{int.class}, function)
                    : call(functions, getter, new Class<?>[]{int.class, int.class}, function, zone);
            boolean consistent = OfficialCarCommand.matches(actual, expected);
            field.put("sdkExpectedValue", expected).put("sdkMappedValue", actual).put("sdkMappingConsistent", consistent);
            return consistent;
        } catch (Exception e) { field.put("sdkReadError", failure(e)).put("sdkMappingConsistent", false); return false; }
    }

    private boolean freshWritable(JSONObject field) {
        if (field == null || !field.optBoolean("valid") || !field.optBoolean("supported") || !field.optBoolean("writable")) return false;
        long age = SystemClock.elapsedRealtime() - field.optLong("updatedAtElapsedMs", -1);
        return age >= 0 && age <= 2500 && "active".equals(field.optString("supportStatus"));
    }

    /** The sole SDK setter call site. Only command() can schedule this method. */
    private void executeUiCommand(long id, String key, String action, String zone, String mode, long requestedAt, int epoch) {
        try {
            requireCommandConnection(requestedAt, epoch);
            JSONObject snapshot = snapshot();
            JSONObject previous = snapshot.getJSONObject("fields").getJSONObject(key);
            if (!freshWritable(previous)) throw new IllegalStateException("STALE_OR_UNSUPPORTED");
            JSONObject fresh = readField(key, previous.getInt("propertyId"), previous.getInt("functionId"), previous.getInt("zone"), previous.getString("kind"));
            if (!freshWritable(fresh)) throw new IllegalStateException("TARGET_READ_INVALID:" + fresh.optString("reason"));
            int driver = snapshot.optInt("driverZone");
            if (("seat-heat".equals(action) || "seat-vent".equals(action)) && driver != driverZone(new JSONArray()))
                throw new IllegalStateException("DRIVER_ZONE_CHANGED");
            double min = 16, max = 31, step = 0.5;
            if ("temp-up".equals(action) || "temp-down".equals(action)) {
                min = ((Number) call(functions, "getCustomizeFunctionValue", new Class<?>[]{int.class}, OfficialCarContract.TEMP_MIN)).doubleValue();
                max = ((Number) call(functions, "getCustomizeFunctionValue", new Class<?>[]{int.class}, OfficialCarContract.TEMP_MAX)).doubleValue();
                step = ((Number) call(functions, "getCustomizeFunctionValue", new Class<?>[]{int.class}, OfficialCarContract.TEMP_STEP)).doubleValue();
            }
            OfficialCarCommand plan = OfficialCarCommand.plan(action, zone, mode, fresh.opt("value"), driver, min, max, step);
            if (plan == null) throw new IllegalArgumentException("COMMAND_VALUE_OR_RANGE");
            if (OfficialCarCommand.matches(fresh.opt("value"), plan.expected)) {
                commandStatus(id, key, "unchanged", "目标已达到，无需发送"); commandBusy.set(false); return;
            }
            requireCommandConnection(requestedAt, epoch);
            Object accepted;
            if (plan.temperature != null) {
                accepted = call(functions, "setCustomizeFunctionValue", new Class<?>[]{int.class, int.class, float.class}, plan.function, plan.zone, plan.temperature);
            } else if (plan.zone != 0) {
                accepted = call(functions, "setFunctionValue", new Class<?>[]{int.class, int.class, int.class}, plan.function, plan.zone, plan.intValue);
            } else {
                accepted = call(functions, "setFunctionValue", new Class<?>[]{int.class, int.class}, plan.function, plan.intValue);
            }
            if (!Boolean.TRUE.equals(accepted)) throw new IllegalStateException("SDK_REJECTED");
            pending = new PendingCommand(id, key, plan.expected, fresh.optLong("sourceTimestampNanos"), epoch);
            commandStatus(id, key, "sent", "已发送，等待状态读回");
            refreshSoon();
        } catch (Exception | LinkageError e) {
            pending = null; commandStatus(id, key, "failed", failure(e)); commandBusy.set(false);
        }
    }

    private void requireCommandConnection(long requestedAt, int epoch) {
        if (closed || !sdkReady || propertyManager == null || !permitted() || epoch != connectionEpoch.get())
            throw new IllegalStateException("CONNECTION_CHANGED");
        if (SystemClock.elapsedRealtime() - requestedAt > 2000) throw new IllegalStateException("COMMAND_EXPIRED");
    }

    private void checkPending(JSONObject fields) {
        if (pending == null) return;
        if (pending.epoch != connectionEpoch.get()) { finishCommand("failed", "车辆服务曾断开；命令不重放"); return; }
        JSONObject field = fields.optJSONObject(pending.key);
        if (field != null && field.optBoolean("valid")
                && field.optLong("updatedAtElapsedMs") >= pending.sentAt
                && (pending.sourceTimestamp <= 0 || field.optLong("sourceTimestampNanos") > pending.sourceTimestamp)
                && OfficialCarCommand.matches(field.opt("value"), pending.expected))
            finishCommand("confirmed", "目标状态已读回");
        else if (SystemClock.elapsedRealtime() > pending.deadline) finishCommand("timeout", "未在5秒内获得目标状态读回");
    }

    private void finishCommand(String status, String reason) {
        if (pending != null) commandStatus(pending.id, pending.key, status, reason);
        pending = null; commandBusy.set(false);
    }

    private void commandStatus(long id, String key, String status, String reason) {
        try { lastCommandJson = new JSONObject().put("id", id).put("field", key).put("status", status)
                .put("reason", reason).put("updatedAtMs", System.currentTimeMillis()).toString(); }
        catch (Exception ignored) {}
        notifyChanged();
    }

    private static final class PendingCommand {
        final long id, sourceTimestamp, sentAt = SystemClock.elapsedRealtime(), deadline = sentAt + 5000;
        final String key;
        final Object expected;
        final int epoch;
        PendingCommand(long id, String key, Object expected, long sourceTimestamp, int epoch) {
            this.id = id; this.key = key; this.expected = expected; this.sourceTimestamp = sourceTimestamp; this.epoch = epoch;
        }
    }

    private static Object decode(OfficialCarPayload pa, String kind, JSONObject field) throws Exception {
        if ("temp".equals(kind)) {
            Double raw = pa.doubleData();
            if (raw == null || pa.format == null || (pa.format != 0 && pa.format != 1)) return null;
            double celsius = pa.format == 0 ? raw : (raw - 32) * 5 / 9;
            // Actual framework constants: 16.0, 31.0, 0.5. No legacy x2 decoding.
            if (celsius < 16 || celsius > 31 || Math.abs(celsius * 2 - Math.rint(celsius * 2)) > 0.01) return null;
            field.put("unit", "°C").put("sourceUnit", pa.format == 0 ? "°C" : "°F");
            return celsius;
        }
        if ("pressure".equals(kind)) {
            Double raw = pa.doubleData();
            field.put("unit", "bar").put("unitVerified", true).put("scale", 0.01);
            return raw != null && raw > 0 && raw <= 1000 ? raw / 100.0 : null;
        }
        Integer raw = pa.integerData();
        if (raw == null) return null;
        field.put("unit", "");
        if ("switch".equals(kind)) return OfficialCarContract.switchValue(raw) ? raw == 1 : null;
        if ("seat".equals(kind)) { field.put("unit", "档"); return OfficialCarContract.seatLevel(raw) ? raw : null; }
        if ("fan".equals(kind)) {
            if (!OfficialCarContract.fanLevel(raw)) return null;
            field.put("automatic", raw == 8).put("sdkValue", raw == 0 ? 0 : OfficialCarContract.FAN + (raw == 8 ? 10 : raw));
            // AUTO is a mode, not a ninth manual fan level.
            return raw == 8 ? "auto" : raw;
        }
        if ("pressureUnit".equals(kind)) {
            String preference = OfficialCarContract.pressurePreference(raw);
            if (preference == null) field.put("sdkFallback", "kPa").put("unitVerified", false);
            return preference;
        }
        if ("blowing".equals(kind)) {
            field.put("sdkValue", OfficialCarContract.blowingSdkValue(raw));
            return OfficialCarContract.blowingMode(raw);
        }
        return null;
    }

    private int driverZone(JSONArray errors) {
        try {
            Object value = call(propertyManager, "getProperty", new Class<?>[]{Class.class, int.class, int.class}, Integer[].class, OfficialCarContract.CAR_CONFIG, 0);
            if (value == null || ((Number) call(value, "getStatus", NONE)).intValue() != 0) return 0;
            Integer[] config = (Integer[]) call(value, "getValue", NONE);
            if (config == null || config.length <= 8 || config[8] == null) return 0;
            // Framework CarFunctionValueImpl.isSteeringwheelRight uses index 8 == 2.
            return config[8] == 1 ? 1 : config[8] == 2 ? 4 : 0;
        } catch (Exception | LinkageError e) { errors.put("driverZone:" + failure(e)); return 0; }
    }

    private void subscribe(JSONArray errors) {
        if (subscribed) return;
        subscribed = true;
        try {
            Class<?> type = Class.forName(OfficialCarContract.FUNCTION_WATCHER);
            Object listener = proxy(type, new Callback() { public void event(String name, Object[] args) { refreshSoon(); } });
            Object registered = call(functions, "registerFunctionValueWatcher", new Class<?>[]{int[].class, type}, OfficialCarContract.WATCHED_FUNCTIONS.clone(), listener);
            if (!Boolean.TRUE.equals(registered)) throw new IllegalStateException("WATCHER_REJECTED");
            registrations.add(new Registration(functions, type, listener, "unregisterFunctionValueWatcher"));
        } catch (Exception | LinkageError e) { errors.put("functionCallback:" + failure(e)); }
        for (String prefix : new String[]{"PaDTpmsTirePressureFrntLe", "PaDTpmsTirePressureFrntRi", "PaDTpmsTirePressureReLe", "PaDTpmsTirePressureReRi", "PaDTpmsUnitSetting"}) {
            try {
                Class<?> type = Class.forName(OfficialCarContract.SIGNAL_PACKAGE + prefix + "ChangedCallback");
                Object listener = proxy(type, new Callback() { public void event(String name, Object[] args) { refreshSoon(); } });
                call(signals, "registerSignalChangedCallback", new Class<?>[]{type}, listener);
                registrations.add(new Registration(signals, type, listener, "unregisterSignalChangedCallback"));
            } catch (Exception | LinkageError e) { errors.put(prefix + ":" + failure(e)); }
        }
    }

    private JSONObject base() throws Exception {
        return new JSONObject().put("connected", false).put("writable", false).put("readOnly", true)
                .put("source", "官方 Car.create / CarPropertyManager PA 只读")
                .put("fields", new JSONObject()).put("climate", new JSONObject())
                .put("seatCapabilities", new JSONObject()).put("errors", new JSONArray())
                .put("updatedAtMs", System.currentTimeMillis());
    }

    private JSONObject unavailable(String reason) {
        try { return base().put("reason", reason); }
        catch (Exception e) { return new JSONObject(); }
    }

    private static JSONObject invalid(String reason) throws Exception {
        return new JSONObject().put("valid", false).put("verified", false).put("apiVerified", true)
                .put("supported", false).put("writable", false).put("reason", reason);
    }

    private static JSONObject copy(JSONObject value) throws Exception { return new JSONObject(value.toString()); }
    private static void add(JSONObject fields, JSONObject value, String key) throws Exception { fields.put(key, value); }
    private void publishUnavailable(String reason) { cameraCapability = -1; publish(unavailable(reason)); }
    private void publish(JSONObject state) {
        if (closed) return;
        stateJson = state.toString();
        publishedAtElapsed = SystemClock.elapsedRealtime();
        notifyChanged();
    }

    private void notifyChanged() {
        if (changed != null) main.post(new Runnable() { public void run() { if (!closed) changed.run(); } });
    }

    private interface Callback { void event(String name, Object[] args); }
    private static Object proxy(final Class<?> type, final Callback callback) {
        return Proxy.newProxyInstance(type.getClassLoader(), new Class<?>[]{type}, new InvocationHandler() {
          public Object invoke(Object instance, Method method, Object[] args) {
            if (method.getDeclaringClass() == Object.class) {
                if ("hashCode".equals(method.getName())) return System.identityHashCode(instance);
                if ("equals".equals(method.getName())) return args != null && instance == args[0];
                return "OfficialCarReader:" + type.getSimpleName();
            }
            callback.event(method.getName(), args);
            return null;
          }
        });
    }

    private static Object call(Object receiver, String name, Class<?>[] types, Object... args) throws Exception {
        if (receiver == null) throw new IllegalStateException("RECEIVER_ABSENT_" + name);
        Method method = receiver.getClass().getMethod(name, types);
        return method.invoke(receiver, args);
    }

    private static String failure(Throwable error) {
        while (error instanceof InvocationTargetException && error.getCause() != null) error = error.getCause();
        String message = error.getMessage();
        return error.getClass().getSimpleName() + (message == null ? "" : ":" + message);
    }

    @Override public synchronized void close() {
        if (closed) return;
        closed = true; sdkReady = false;
        stateJson = unavailable("官方车辆读取器已关闭").toString();
        publishedAtElapsed = SystemClock.elapsedRealtime();
        worker.execute(new Runnable() { public void run() {
            if (pending != null) finishCommand("cancelled", "读取器已关闭");
            for (Registration item : registrations) {
                try { call(item.receiver, item.remove, new Class<?>[]{item.type}, item.listener); }
                catch (Exception | LinkageError ignored) { /* Local listener release is best effort. */ }
            }
            registrations.clear();
        } });
        worker.shutdown();
        main.post(new Runnable() { public void run() {
            synchronized (OfficialCarReader.class) {
                java.util.Iterator<WeakReference<OfficialCarReader>> iterator = readers.iterator();
                while (iterator.hasNext()) {
                    OfficialCarReader reader = iterator.next().get();
                    if (reader == null || reader == OfficialCarReader.this) iterator.remove();
                }
            }
            try { if (androidCar != null) call(androidCar, "disconnect", NONE); }
            catch (Exception | LinkageError ignored) {}
            propertyManager = null;
        } });
    }

    private static final class Registration {
        final Object receiver, listener;
        final Class<?> type;
        final String remove;
        Registration(Object receiver, Class<?> type, Object listener, String remove) {
            this.receiver = receiver; this.type = type; this.listener = listener; this.remove = remove;
        }
    }
}
