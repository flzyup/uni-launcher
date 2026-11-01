package xyz.i4o.uni.launcher.integration;
import org.json.*;

public final class OfficialBodySignalsTest {
    private static void check(boolean ok) { if (!ok) throw new AssertionError(); }
    public static void main(String[] args) throws Exception {
        JSONArray properties = new JSONArray();
        for (int i = 0; i < 5; i++) properties.put(new JSONObject().put("propertyId", 560993300 + i).put("raw", i).put("active", true).put("halStatus", 0));
        JSONObject probe = new JSONObject().put("properties", properties).put("observedAtMs", 1234);
        JSONObject left = new JSONObject(); OfficialBodySignals.append(left, probe, 1);
        check(left.getJSONObject("doorFrontLeft").getInt("raw") == 0);
        check(left.getJSONObject("doorFrontRight").getInt("raw") == 2);
        check(left.getJSONObject("doorRearLeft").getInt("raw") == 1);
        check(left.getJSONObject("doorRearRight").getInt("raw") == 3);
        check(left.getJSONObject("tailgateOpen").getInt("raw") == 4);
        for (String key : new String[]{"doorFrontLeft", "doorFrontRight", "doorRearLeft", "doorRearRight", "tailgateOpen", "hoodOpen"})
            check(!left.getJSONObject(key).getBoolean("writable"));
        check(!left.getJSONObject("doorFrontLeft").getBoolean("valid"));
        check(left.getJSONObject("doorFrontRight").getBoolean("valid") && !left.getJSONObject("doorFrontRight").getBoolean("value"));
        check(left.getJSONObject("doorRearLeft").getBoolean("valid") && left.getJSONObject("doorRearLeft").getBoolean("value"));
        check(!left.getJSONObject("doorRearRight").getBoolean("valid"));
        properties.getJSONObject(0).put("raw", 1);
        JSONObject verified = new JSONObject(); OfficialBodySignals.append(verified, probe, 1);
        check(verified.getJSONObject("doorFrontLeft").getBoolean("verified"));
        check(!verified.getJSONObject("doorRearLeft").getBoolean("verified"));
        properties.getJSONObject(0).put("active", false);
        JSONObject inactive = new JSONObject(); OfficialBodySignals.append(inactive, probe, 1);
        check(!inactive.getJSONObject("doorFrontLeft").getBoolean("valid"));
        properties.getJSONObject(0).put("raw", 0).put("active", true);
        JSONObject right = new JSONObject(); OfficialBodySignals.append(right, probe, 4);
        check(right.getJSONObject("doorFrontRight").getInt("raw") == 0);
        check(right.getJSONObject("doorFrontLeft").getInt("raw") == 2);
        JSONObject unknown = new JSONObject(); OfficialBodySignals.append(unknown, probe, 0);
        check(!unknown.getJSONObject("doorFrontLeft").has("raw"));
        check(unknown.getJSONObject("tailgateOpen").getInt("raw") == 4);
        System.out.println("OfficialBodySignalsTest passed");
    }
}
