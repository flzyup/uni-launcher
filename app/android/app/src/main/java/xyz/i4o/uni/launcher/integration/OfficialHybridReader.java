package xyz.i4o.uni.launcher.integration;

import java.lang.reflect.InvocationTargetException;
import org.json.JSONObject;

/** Read-only IP753 PHEV properties, borrowed from the existing reader worker.
 * Uses original HAL values: SDK enum helpers silently replace unknown values.
 * No charging command, drive-mode setter, connection or subscription is created.
 */
final class OfficialHybridReader {
    static final int DRIVE_MODE = 0x21403018, HYBRID_SELECTED = 0x21701042;
    static final int ENERGY_FLOW = 0x21701052, ELECTRIC_RANGE = 0x21701069;
    private final Object properties;
    OfficialHybridReader(Object properties) { this.properties = properties; }

    void appendTo(JSONObject fields) throws Exception {
        fields.put("driveMode", read(DRIVE_MODE).json());
        fields.put("hybridSelected", read(HYBRID_SELECTED).json());
        fields.put("energyFlow", read(ENERGY_FLOW).json());
        fields.put("electricRange", read(ELECTRIC_RANGE).json());
    }

    Sample read(int property) {
        Sample s = new Sample(property);
        try {
            Class<?> type = property == DRIVE_MODE ? Integer.class : byte[].class;
            Object hal = properties.getClass().getMethod("getProperty", Class.class, int.class, int.class)
                    .invoke(properties, type, property, 0);
            if (hal == null) throw new IllegalStateException("HAL_ABSENT");
            s.halStatus = ((Number) call(hal, "getStatus")).intValue();
            s.timestamp = ((Number) call(hal, "getTimestamp")).longValue();
            if (s.halStatus != 0) throw new IllegalStateException("HAL_UNAVAILABLE");
            Object raw = call(hal, "getValue");
            if (property == DRIVE_MODE) {
                if (!(raw instanceof Integer)) throw new IllegalStateException("HAL_TYPE");
                s.raw = (Integer) raw; s.value = driveMode(s.raw);
            } else {
                if (!(raw instanceof byte[])) throw new IllegalStateException("HAL_TYPE");
                OfficialCarPayload pa = OfficialCarPayload.parse((byte[]) raw);
                s.availability = pa.availability; s.format = pa.format; s.status = pa.status;
                if (!pa.active()) throw new IllegalStateException("PA_NOT_ACTIVE");
                s.raw = pa.integerData();
                if (property == HYBRID_SELECTED) s.value = hybridSelected(s.raw);
                if (property == ENERGY_FLOW) s.value = energyFlow(s.raw);
                if (property == ELECTRIC_RANGE) {
                    s.unit = pa.format != null && pa.format == 0 ? "km"
                            : pa.format != null && pa.format == 1 ? "mi" : "unconfirmed";
                    // Getter and format are proven, but the sentinel/domain and
                    // status meanings have not been confirmed for this vehicle.
                    throw new IllegalStateException("RANGE_DOMAIN_UNCONFIRMED");
                }
            }
            if (s.value == null) throw new IllegalStateException("UNKNOWN_ENUM");
            s.valid = true; s.reason = "";
        } catch (Exception | LinkageError e) {
            Throwable failure = e;
            while (failure instanceof InvocationTargetException && failure.getCause() != null)
                failure = failure.getCause();
            s.reason = failure.getClass().getSimpleName() + ":" + failure.getMessage();
        }
        return s;
    }

    static String driveMode(Integer raw) {
        String[] values = {"ECO", "COMFORT", "DYNAMIC", "INDIVIDUAL", "XC", "HDC",
                "PURE", "HYBRID", "POWER", "RACE", "ECO_HEV_PHEV", "COMFORT_HEV"};
        return raw != null && raw >= 1 && raw <= values.length ? values[raw - 1] : null;
    }
    static Boolean hybridSelected(Integer raw) {
        return raw != null && (raw == 0 || raw == 1) ? raw == 1 : null;
    }
    static String energyFlow(Integer raw) {
        String[] values = {"NOT_READY", "MAIN_CHARGING", "BOOST", "EAWD", "ENGINE_ONLY",
                "ENGINE_ONLY_AND_CHARGE", "ELECTRIC_DRIVE", "STANDSTILL_ENGINE_OFF",
                "STANDSTILL_ENGINE_ON", "STANDSTILL_ENGINE_ON_CHARGE", "ENGINE_OFF_REGEN_BRAKE",
                "ENGINE_ON_REGEN_BRAKE", "ENGINE_ON_REGEN_BRAKE_CHARGE"};
        return raw != null && raw >= 0 && raw < values.length ? values[raw] : null;
    }

    static final class Sample {
        final int property;
        boolean valid;
        int halStatus = -1;
        long timestamp;
        Integer raw, availability, format, status;
        Object value;
        String reason = "UNAVAILABLE", unit = "";
        Sample(int property) { this.property = property; }
        JSONObject json() throws Exception {
            JSONObject j = new JSONObject().put("propertyId", property).put("areaId", 0)
                    .put("source", "官方 CarPropertyManager / IP753 PHEV")
                    .put("valid", valid).put("writable", false).put("verified", false)
                    .put("apiVerified", true).put("halStatus", halStatus)
                    .put("sourceTimestampNanos", timestamp).put("raw", raw)
                    .put("availabilityRaw", availability).put("formatRaw", format)
                    .put("statusRaw", status).put("unit", unit).put("reason", reason);
            if (valid) j.put("value", value).put("updatedAtMs", System.currentTimeMillis());
            return j;
        }
    }
    private static Object call(Object object, String method) throws Exception {
        return object.getClass().getMethod(method).invoke(object);
    }
}
