package xyz.i4o.uni.launcher.integration;

import org.json.JSONArray;
import org.json.JSONObject;

/** PA samples stay diagnostic until open/closed enums and seat side are verified. */
final class OfficialBodySignals {
    private OfficialBodySignals() {}

    static void append(JSONObject fields, JSONObject probe, int driverZone) throws Exception {
        JSONArray entries = probe.optJSONArray("properties");
        String[] names = {"doorFrontLeft", "doorFrontRight", "doorRearLeft", "doorRearRight", "tailgateOpen", "hoodOpen"};
        int[] indexes = driverZone == 1 ? new int[]{0, 2, 1, 3, 4, -1}
                : driverZone == 4 ? new int[]{2, 0, 3, 1, 4, -1}
                : new int[]{-1, -1, -1, -1, 4, -1};
        for (int i = 0; i < names.length; i++) {
            JSONObject source = entries != null && indexes[i] >= 0 ? entries.optJSONObject(indexes[i]) : null;
            JSONObject field = new JSONObject().put("valid", false).put("verified", false)
                    .put("writable", false).put("source", "Geely PA 只读")
                    .put("reason", indexes[i] < 0 ? (i == 5 ? "机舱盖信号未确认" : "驾驶位方向未确认") : "开关状态待实车验证")
                    .put("updatedAtMs", probe.optLong("observedAtMs", 0));
            if (source != null) {
                for (String key : new String[]{"propertyId", "raw", "active", "halStatus", "availabilityRaw", "formatRaw", "statusRaw", "sourceTimestampNanos"})
                    if (source.has(key) && !source.isNull(key)) field.put(key, source.get(key));
                if (source.has("reason")) field.put("reason", source.optString("reason"));
            }
            fields.put(names[i], field);
        }
    }
}
