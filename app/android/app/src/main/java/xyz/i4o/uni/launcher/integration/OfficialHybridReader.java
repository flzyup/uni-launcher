package xyz.i4o.uni.launcher.integration;

import java.lang.reflect.InvocationTargetException;
import org.json.JSONObject;
import xyz.i4o.uni.launcher.log.LogTags;
import xyz.i4o.uni.launcher.log.UniLog;

/** IP753 PHEV properties, borrowed from the existing reader worker.
 * Uses original HAL values: SDK enum helpers silently replace unknown values.
 * The class itself never writes and never opens a connection; the two settings
 * with a write channel (drive mode, engine start-stop) are written by
 * {@link OfficialCarReader} only when the user or the startup profile asked for
 * exactly that value.
 */
final class OfficialHybridReader {
    static final int DRIVE_MODE = OfficialCarContract.PA_DRIVE_MODE;
    static final int START_STOP = OfficialCarContract.PA_START_STOP;
    static final int HYBRID_SELECTED = 0x21701042;
    static final int ENERGY_FLOW = 0x21701052, ELECTRIC_RANGE = 0x21701069;
    private static final String[] KEYS = {"driveMode", "hybridSelected", "energyFlow", "electricRange"};
    private final Object properties;
    OfficialHybridReader(Object properties) { this.properties = properties; }

    void appendTo(JSONObject fields) throws Exception {
        fields.put("driveMode", read(DRIVE_MODE).json());
        fields.put("startStop", read(START_STOP).json());
        fields.put("hybridSelected", read(HYBRID_SELECTED).json());
        fields.put("energyFlow", read(ENERGY_FLOW).json());
        fields.put("electricRange", read(ELECTRIC_RANGE).json());
        // The four reads run on every poll: one summary line per cycle keeps the
        // log readable, and the raw value stays next to the reason.
        int valid = 0;
        StringBuilder detail = new StringBuilder();
        for (String key : KEYS) {
            JSONObject field = fields.optJSONObject(key);
            if (field != null && field.optBoolean("valid")) { valid++; continue; }
            if (detail.length() > 0) detail.append(';');
            detail.append(key).append('(').append(field == null ? "FIELD_ABSENT" : field.optString("reason"))
                    .append(",raw=").append(field == null ? null : field.opt("raw"))
                    .append(",avail=").append(field == null ? null : field.opt("availabilityRaw"))
                    .append(",status=").append(field == null ? null : field.opt("statusRaw")).append(')');
        }
        UniLog.done(LogTags.SIGNAL, "hybrid/read", "valid", valid, "invalid", KEYS.length - valid,
                "details", detail.toString());
    }

    Sample read(int property) {
        Sample s = new Sample(property);
        s.writeChannel = property == DRIVE_MODE ? OfficialCarContract.CB_DRIVE_MODE
                : property == START_STOP ? OfficialCarContract.CB_START_STOP : 0;
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
                if (property == START_STOP) {
                    // CbSsActivationValue / PaSsActivationData are OFF(0)/ON(1). The SDK
                    // mappers ignore the value and always answer ON, so it is decoded
                    // here from the PA payload instead.
                    s.value = s.raw != null && (s.raw == 0 || s.raw == 1) ? Boolean.valueOf(s.raw == 1) : null;
                }
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

    static String driveMode(Integer raw) { return OfficialCarContract.driveModeName(raw); }
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
        /** HAL command property paired with this state property; 0 when read-only. */
        int writeChannel;
        Sample(int property) { this.property = property; }
        JSONObject json() throws Exception {
            JSONObject j = new JSONObject().put("propertyId", property).put("areaId", 0)
                    .put("source", "官方 CarPropertyManager / IP753 PHEV")
                    .put("valid", valid)
                    // writable describes the HAL channel (access 0x2 on this car), not
                    // whether the caller holds the permission or the SDK write contract.
                    .put("writable", writeChannel != 0)
                    .put("writeChannel", writeChannel).put("verified", false)
                    .put("apiVerified", true).put("halStatus", halStatus)
                    .put("sourceTimestampNanos", timestamp).put("raw", raw)
                    .put("availabilityRaw", availability).put("formatRaw", format)
                    .put("statusRaw", status).put("unit", unit).put("reason", reason);
            if (valid) j.put("value", value).put("updatedAtMs", System.currentTimeMillis())
                    .put("updatedAtElapsedMs", android.os.SystemClock.elapsedRealtime());
            return j;
        }
    }
    private static Object call(Object object, String method) throws Exception {
        return object.getClass().getMethod(method).invoke(object);
    }
}
