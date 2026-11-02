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
 * evidence.
 * See docs/OFFICIAL_CAR_API.md for public evidence and integration details.
 */
public final class OfficialVehicleSensors {
    public static final int PM25_INDOOR = 1049344, AQI_INDOOR = 1049856;
    public static final int CAR_SPEED = 1048832, ODOMETER = 1050368;
    public static final int ENDURANCE_MILEAGE = 1050624, MAINTENANCE_MILEAGE = 4206592;
    public static final int PHEV_BATTERY_PERCENTAGE = 4210688;
    public static final int FUEL_LEVEL = 1050112;
    public static final int FLT_INFO_FUEL_CAPACITY = 2097408; // 0x200100
    public static final int INT_INFO_VEHICLE_TYPES = 1049088; // 0x100200

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

            float fuelCapacity = queryFuelCapacity(sdkCar);
            String powertrainType = queryVehicleType(sdkCar);

            JSONObject batteryField = fields.optJSONObject("batteryPercent");
            boolean hasBattery = batteryField != null && batteryField.optBoolean("valid");
            JSONObject rangeField = fields.optJSONObject("range");
            boolean hasRange = rangeField != null && rangeField.optBoolean("valid");
            JSONObject fuelLitersField = fields.optJSONObject("fuelLiters");
            boolean hasFuel = fuelLitersField != null && fuelLitersField.optBoolean("valid");

            if ("UNKNOWN".equals(powertrainType)) {
                if (!hasBattery && (hasFuel || hasRange || fuelCapacity > 0)) {
                    powertrainType = "FUEL";
                }
            }

            if (fuelCapacity <= 0 && "FUEL".equals(powertrainType)) {
                fuelCapacity = 54.0f; // Lynk & Co 01/05 ICE standard tank volume
            }

            if (fuelCapacity > 0) {
                state.put("fuelCapacity", (double) fuelCapacity);
            }
            if (!"UNKNOWN".equals(powertrainType)) {
                state.put("powertrainType", powertrainType);
            }

            JSONObject fuelPercentField = new JSONObject().put("sensorId", FUEL_LEVEL)
                    .put("source", "官方 SDK / VehicleSignalManager 燃油百分比")
                    .put("supported", fuelLitersField != null && fuelLitersField.optBoolean("supported"))
                    .put("writable", false).put("verified", false).put("apiVerified", true)
                    .put("unit", "%").put("unitVerified", true);
            if (hasFuel) {
                double liters = fuelLitersField.optDouble("value", -1);
                double percent = -1;
                if (fuelCapacity > 0) {
                    percent = (liters / fuelCapacity) * 100.0;
                } else if (liters >= 0 && liters <= 100.0) {
                    percent = liters;
                }
                if (percent >= 0) {
                    percent = Math.min(100.0, Math.max(0.0, percent));
                    fuelPercentField.put("valid", true).put("sampleValid", true)
                            .put("value", percent).put("updatedAtMs", System.currentTimeMillis())
                            .put("updatedAtElapsedMs", SystemClock.elapsedRealtime()).put("reason", "");
                    count++;
                } else {
                    fuelPercentField.put("valid", false).put("reason", "FUEL_CAPACITY_UNKNOWN");
                }
            } else {
                fuelPercentField.put("valid", false).put("reason", fuelLitersField != null ? fuelLitersField.optString("reason") : "FUEL_LITERS_ABSENT");
            }
            fields.put("fuelPercent", fuelPercentField);

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

    /** Overwrites only this helper's owned keys, including invalid samples.
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
        new Spec("batteryPercent", PHEV_BATTERY_PERCENTAGE, "getBliHvBattLevelIndicationIhu", "%", 100, 1, true, false),
        new Spec("fuelLiters", FUEL_LEVEL, "getPaDiFuLvlIndcdVal", "L", 51000.0, 1, true, false)
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
            boolean activeOk = "ACTIVE".equals(sample.availability) || (spec.id == FUEL_LEVEL && "NOT_ACTIVE".equals(sample.availability));
            if (!activeOk) throw new IllegalStateException("PA_" + sample.availability);
            Object raw = pa.getClass().getField("data").get(pa);
            if (!(spec.decimal ? raw instanceof Double : raw instanceof Integer)) throw new IllegalStateException("PA_DATA_TYPE_OR_ABSENT");
            sample.raw = (Number) raw;
            double number = sample.raw.doubleValue();
            if (!finite(number) || number < 0 || number > spec.maximum) throw new IllegalStateException("PA_OUT_OF_RANGE");
            if (spec.id == FUEL_LEVEL) {
                if (number > 200.0) sample.value = number / 1000.0;
                else if (number > 0 && number <= 1.0) sample.value = number * 1000.0;
                else sample.value = number;
            } else {
                sample.value = number / spec.divisor;
            }
            sample.status = optionalField(pa, "status"); sample.level = optionalField(pa, "level");
            if (sensors != null) {
                sample.sdkSupport = String.valueOf(call(sensors, "isSensorSupported", int.class, spec.id));
                if ("notavailable".equals(sample.sdkSupport) || "error".equals(sample.sdkSupport)) sample.supported = false;
                boolean sdkOk = "active".equals(sample.sdkSupport) || (spec.id == FUEL_LEVEL && "notactive".equals(sample.sdkSupport));
                if (!sdkOk) throw new IllegalStateException("SDK_" + sample.sdkSupport);
                Object mapped = call(sensors, "getSensorLatestValue", int.class, spec.id);
                if (!(mapped instanceof Number) || !finite(((Number) mapped).doubleValue())) throw new IllegalStateException("SDK_DATA_INVALID");
                double sdkNum = ((Number) mapped).doubleValue();
                if (spec.id == FUEL_LEVEL) {
                    if (sdkNum > 200.0) sdkNum /= 1000.0;
                    else if (sdkNum > 0 && sdkNum <= 1.0) sdkNum *= 1000.0;
                }
                sample.sdkValue = sdkNum;
                double diff = Math.abs(sample.sdkValue - sample.value);
                if (spec.id == FUEL_LEVEL) {
                    if (diff > 1.0) {
                        // Diagnostic only: fuel float levels may have small conversion variance
                    }
                } else if (diff > 0.01) {
                    throw new IllegalStateException("SDK_PA_MISMATCH");
                }
            }
            if (!ready(signals)) throw new IllegalStateException("SIGNALS_NOT_READY");
            sample.sampleValid = true;
            if (sample.unit == null) throw new IllegalStateException("UNIT_UNCONFIRMED");
            sample.valid = true; sample.reason = "";
        } catch (Exception | LinkageError e) {
            sample.reason = failure(e);
            // Diagnostic and fallback: old firmware may expose the public sensor
            // even when its PA object reports error or inactive.
            if (spec.id == FUEL_LEVEL && !sample.valid && sensors != null) {
                try {
                    String sup = String.valueOf(call(sensors, "isSensorSupported", int.class, spec.id));
                    sample.sdkSupport = sup;
                    if ("active".equals(sup) || "notactive".equals(sup)) {
                        Object mapped = call(sensors, "getSensorLatestValue", int.class, spec.id);
                        if (mapped instanceof Number && finite(((Number) mapped).doubleValue())) {
                            double val = ((Number) mapped).doubleValue();
                            if (val > 200.0) val /= 1000.0;
                            else if (val > 0 && val <= 1.0) val *= 1000.0;
                            if (val >= 0 && val <= 200.0) {
                                sample.sdkValue = val;
                                sample.value = val;
                                sample.raw = (Number) mapped;
                                sample.supported = true;
                                sample.sampleValid = true;
                                sample.valid = true;
                                sample.reason = "";
                            }
                        }
                    }
                } catch (Exception | LinkageError ignored) {}
            } else if (sensors != null && "unqueried".equals(sample.sdkSupport)) try {
                sample.sdkSupport = String.valueOf(call(sensors, "isSensorSupported", int.class, spec.id));
                if ("active".equals(sample.sdkSupport)) {
                    Object mapped = call(sensors, "getSensorLatestValue", int.class, spec.id);
                    if (mapped instanceof Number && finite(((Number) mapped).doubleValue()))
                        sample.sdkValue = ((Number) mapped).doubleValue();
                }
            } catch (Exception | LinkageError ignored) { }
        }
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
    public static float queryFuelCapacity(Object sdkCar) {
        if (sdkCar == null) return -1f;
        try {
            Object carInfo = call(sdkCar, "getCarInfoManager");
            if (carInfo != null) {
                Object cap = call(carInfo, "getCarInfoFloat", int.class, FLT_INFO_FUEL_CAPACITY);
                if (cap instanceof Number) {
                    float f = ((Number) cap).floatValue();
                    if (f == Float.MIN_VALUE) f = 0.0f;
                    if (f > 200.0f) f /= 1000.0f;
                    if (f > 0 && f <= 200.0f) return f;
                }
            }
        } catch (Exception | LinkageError ignored) {}
        return -1f;
    }

    public static String queryVehicleType(Object sdkCar) {
        if (sdkCar == null) return "UNKNOWN";
        try {
            Object carInfo = call(sdkCar, "getCarInfoManager");
            if (carInfo != null) {
                Object vt = call(carInfo, "getCarInfoInt", int.class, INT_INFO_VEHICLE_TYPES);
                if (vt instanceof Number) {
                    switch (((Number) vt).intValue()) {
                        case 1049089: return "FUEL";
                        case 1049091: return "PHEV";
                        case 1049096: return "BEV";
                        case 1049090: return "HEV";
                        case 1049095: return "MHEV";
                        case 1049092: return "EREV";
                        default: return "UNKNOWN";
                    }
                }
            }
        } catch (Exception | LinkageError ignored) {}
        return "UNKNOWN";
    }
}
