package xyz.i4o.uni.launcher.integration;

import android.os.SystemClock;
import java.lang.reflect.InvocationTargetException;
import java.util.Iterator;
import org.json.JSONArray;
import org.json.JSONObject;

/**
 * Synchronous, read-only sensor helper for an existing OfficialCarReader worker.
 * Takes borrowed SDK Car / VehicleSignalManager objects; never creates, binds,
 * subscribes, disconnects or writes. Do not call on the UI thread.
 *
 * Evidence: audited ecarx.adapterapi.jar SensorImpl.getSensorLatestValue,
 * SensorImpl.isSensorSupported and SensorPaUtil.getValue/getAvailability.
 * PA public data/availability fields prevent SDK fallback zero from becoming a
 * valid sample. BLI battery percentage 4210688 uses data, NOT its level field.
 * XCHvac's PM2.5 resource explicitly labels the value in micrograms/m3.
 *
 * Speed division and distance ranges are known, but their physical units are
 * not established by those method bodies. Defaults expose validated samples
 * with valid=false/UNIT_UNCONFIRMED; a caller may supply explicit vehicle-unit
 * evidence. No fuel percentage or guessed ambient sensor is exported.
 * See docs/OFFICIAL_CAR_API.md for public evidence and integration details.
 */
public final class OfficialVehicleSensors {
    public static final int PM25_INDOOR = 1049344, AQI_INDOOR = 1049856;
    public static final int CAR_SPEED = 1048832, ODOMETER = 1050368;
    public static final int ENDURANCE_MILEAGE = 1050624, MAINTENANCE_MILEAGE = 4206592;
    public static final int PHEV_BATTERY_PERCENTAGE = 4210688;

    private final Object sdkCar, signals;
    private final Units units;

    public OfficialVehicleSensors(Object sdkCar, Object signals) {
        this(sdkCar, signals, Units.unconfirmed());
    }

    /** sdkCar may be null for PA-only reading. signals must be an existing manager. */
    public OfficialVehicleSensors(Object sdkCar, Object signals, Units units) {
        this.sdkCar = sdkCar; this.signals = signals;
        this.units = units == null ? Units.unconfirmed() : units;
    }

    /** Performs fresh synchronous reads, returning connected/fields/errors metadata. */
    public synchronized JSONObject snapshot() {
        JSONObject state = new JSONObject(), fields = new JSONObject();
        JSONArray errors = new JSONArray();
        try {
            state.put("connected", ready(signals)).put("writable", false)
                    .put("source", "官方 SDK / VehicleSignalManager 只读传感器")
                    .put("fields", fields).put("errors", errors);
            Object sensors = null;
            if (sdkCar != null && ready(signals)) {
                try { sensors = call(sdkCar, "getSensorManager"); }
                catch (Exception | LinkageError e) { errors.put("sdkSensors:" + failure(e)); }
            }
            int count = 0;
            for (Spec spec : SPECS) {
                Sample sample = readSample(sensors, signals, spec, units);
                JSONObject field = sample.json();
                fields.put(spec.key, field);
                if (sample.valid) count++;
                else errors.put(spec.key + ":" + sample.reason);
            }
            boolean connected = ready(signals);
            if (!connected) {
                count = 0;
                Iterator<String> keys = fields.keys();
                while (keys.hasNext()) fields.getJSONObject(keys.next()).put("valid", false).put("reason", "SIGNALS_NOT_READY");
            }
            state.put("connected", connected).put("validFieldCount", count)
                    .put("updatedAtMs", System.currentTimeMillis());
        } catch (Exception | LinkageError e) {
            try { state.put("connected", false).put("reason", failure(e)); } catch (Exception ignored) {}
        }
        return state;
    }

    /** Overwrites only this helper's seven owned keys, including invalid samples.
     * Returns the sensor snapshot so the caller can merge errors/connection status.
     * Unrelated HVAC, seat and tyre keys remain untouched.
     */
    public synchronized JSONObject appendTo(JSONObject fields) {
        if (fields == null) throw new IllegalArgumentException("fields must not be null");
        JSONObject result = snapshot();
        try {
            JSONObject added = result.getJSONObject("fields");
            Iterator<String> keys = added.keys();
            while (keys.hasNext()) { String key = keys.next(); fields.put(key, added.get(key)); }
        } catch (Exception e) { throw new IllegalStateException("Cannot append sensor fields", e); }
        return result;
    }

    /** Labels the SDK-normalized samples; does not silently convert between units.
     * Pass null for an unconfirmed dimension. Evidence must describe a real source
     * or same-time comparison, not merely the user's preferred display units.
     */
    public static final class Units {
        final String speed, distance, evidence;
        private Units(String speed, String distance, String evidence) {
            this.speed = speed; this.distance = distance; this.evidence = evidence;
        }
        public static Units unconfirmed() { return new Units(null, null, ""); }
        public static Units confirmed(String speed, String distance, String evidence) {
            if (speed != null && !"m/s".equals(speed) && !"km/h".equals(speed) && !"mph".equals(speed))
                throw new IllegalArgumentException("Unsupported speed unit");
            if (distance != null && !"km".equals(distance) && !"mi".equals(distance))
                throw new IllegalArgumentException("Unsupported distance unit");
            if ((speed == null && distance == null) || evidence == null || evidence.trim().isEmpty())
                throw new IllegalArgumentException("Confirmed units require evidence");
            return new Units(speed, distance, evidence);
        }
    }

    static final class Spec {
        final String key, getter, unit;
        final int id;
        final double maximum, divisor;
        final boolean decimal, distance;
        Spec(String key, int id, String getter, String unit, double maximum, double divisor, boolean decimal, boolean distance) {
            this.key = key; this.id = id; this.getter = getter; this.unit = unit;
            this.maximum = maximum; this.divisor = divisor; this.decimal = decimal; this.distance = distance;
        }
    }

    static final Spec[] SPECS = {
        new Spec("pm25", PM25_INDOOR, "getPaClAqInsideRaw", "µg/m³", 1023, 1, false, false),
        new Spec("aqi", AQI_INDOOR, "getPaClAqInsideIndex", "", 1023, 1, false, false),
        new Spec("speed", CAR_SPEED, "getPaNaviVehSpeed", null, 12500, 100, false, false),
        new Spec("odometer", ODOMETER, "getPaDiDstTrVld", null, 2000000, 1, false, true),
        new Spec("range", ENDURANCE_MILEAGE, "getPaDiDstToEmpty", null, 4095, 1, false, true),
        new Spec("maintenanceMileage", MAINTENANCE_MILEAGE, "getPaDiDstToSrv", null, 32000, 1, false, true),
        new Spec("batteryPercent", PHEV_BATTERY_PERCENTAGE, "getBliHvBattLevelIndicationIhu", "%", 100, 1, true, false)
    };

    static Sample readSample(Object sensors, Object signals, Spec spec, Units units) {
        Sample sample = new Sample(spec);
        sample.unit = spec.unit != null ? spec.unit : spec.distance ? units.distance : units.speed;
        sample.unitEvidence = spec.unit != null ? "官方接口/原厂资源" : units.evidence;
        sample.sdkAvailable = sensors != null;
        try {
            if (!ready(signals)) throw new IllegalStateException("SIGNALS_NOT_READY");
            Object pa = call(signals, spec.getter);
            if (pa == null) throw new IllegalStateException("PA_ABSENT");
            Object availability = pa.getClass().getField("availability").get(pa);
            sample.availability = availability instanceof Enum<?> ? ((Enum<?>) availability).name() : String.valueOf(availability);
            sample.supported = "ACTIVE".equals(sample.availability) || "NOT_ACTIVE".equals(sample.availability);
            if (!"ACTIVE".equals(sample.availability)) throw new IllegalStateException("PA_" + sample.availability);
            Object raw = pa.getClass().getField("data").get(pa);
            if (!(spec.decimal ? raw instanceof Double : raw instanceof Integer)) throw new IllegalStateException("PA_DATA_TYPE_OR_ABSENT");
            sample.raw = (Number) raw;
            double number = sample.raw.doubleValue();
            if (!finite(number) || number < 0 || number > spec.maximum) throw new IllegalStateException("PA_OUT_OF_RANGE");
            sample.value = number / spec.divisor;
            sample.status = optionalField(pa, "status"); sample.level = optionalField(pa, "level");
            if (sensors != null) {
                sample.sdkSupport = String.valueOf(call(sensors, "isSensorSupported", int.class, spec.id));
                if ("notavailable".equals(sample.sdkSupport) || "error".equals(sample.sdkSupport)) sample.supported = false;
                if (!"active".equals(sample.sdkSupport)) throw new IllegalStateException("SDK_" + sample.sdkSupport);
                Object mapped = call(sensors, "getSensorLatestValue", int.class, spec.id);
                if (!(mapped instanceof Number) || !finite(((Number) mapped).doubleValue())) throw new IllegalStateException("SDK_DATA_INVALID");
                sample.sdkValue = ((Number) mapped).doubleValue();
                if (Math.abs(sample.sdkValue - sample.value) > 0.01) throw new IllegalStateException("SDK_PA_MISMATCH");
            }
            if (!ready(signals)) throw new IllegalStateException("SIGNALS_NOT_READY");
            sample.sampleValid = true;
            if (sample.unit == null) throw new IllegalStateException("UNIT_UNCONFIRMED");
            sample.valid = true; sample.reason = "";
        } catch (Exception | LinkageError e) { sample.reason = failure(e); }
        sample.observedAtMs = System.currentTimeMillis();
        return sample;
    }

    static final class Sample {
        final Spec spec;
        boolean supported, valid, sampleValid, sdkAvailable;
        String availability = "unknown", sdkSupport = "unqueried", reason = "UNKNOWN", unit, unitEvidence;
        Number raw;
        Double value, sdkValue;
        Object status, level;
        long observedAtMs;
        Sample(Spec spec) { this.spec = spec; }
        JSONObject json() throws Exception {
            JSONObject result = new JSONObject().put("sensorId", spec.id).put("method", spec.getter)
                    .put("source", "官方 SDK / VehicleSignalManager PA").put("supported", supported)
                    .put("valid", valid).put("sampleValid", sampleValid).put("writable", false)
                    .put("verified", false).put("apiVerified", true).put("availabilityRaw", availability)
                    .put("supportStatus", sdkAvailable ? sdkSupport : availability)
                    .put("sdkAvailable", sdkAvailable).put("raw", raw).put("sdkValue", sdkValue)
                    .put("statusRaw", status == null ? null : status.toString()).put("levelRaw", level)
                    .put("sampleValue", value).put("unit", unit == null ? "unconfirmed" : unit)
                    .put("unitVerified", unit != null).put("unitEvidence", unitEvidence)
                    .put("sourceTimestampAvailable", false).put("observedAtMs", observedAtMs).put("reason", reason);
            if (valid) result.put("value", value).put("updatedAtMs", observedAtMs)
                    .put("updatedAtElapsedMs", SystemClock.elapsedRealtime());
            return result;
        }
    }

    private static Object optionalField(Object object, String name) {
        try { return object.getClass().getField(name).get(object); } catch (Exception ignored) { return null; }
    }
    private static boolean ready(Object signals) {
        try { return signals != null && Boolean.TRUE.equals(call(signals, "isReady")); }
        catch (Exception | LinkageError e) { return false; }
    }
    private static Object call(Object receiver, String name) throws Exception { return receiver.getClass().getMethod(name).invoke(receiver); }
    private static Object call(Object receiver, String name, Class<?> type, Object value) throws Exception {
        return receiver.getClass().getMethod(name, type).invoke(receiver, value);
    }
    private static boolean finite(double value) { return !Double.isNaN(value) && !Double.isInfinite(value); }
    private static String failure(Throwable error) {
        while (error instanceof InvocationTargetException && error.getCause() != null) error = error.getCause();
        return error.getClass().getSimpleName() + (error.getMessage() == null ? "" : ":" + error.getMessage());
    }
}
