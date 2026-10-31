package xyz.i4o.uni.launcher.integration;
import org.json.*;

public final class OfficialBodySignalsTest {
    private static void check(boolean ok) { if (!ok) throw new AssertionError(); }
    public static void main(String[] args) throws Exception {
        JSONArray properties = new JSONArray();
        for (int i = 0; i < 5; i++) properties.put(new JSONObject().put("propertyId", 560993300 + i).put("raw", i).put("active", true));
        JSONObject probe = new JSONObject().put("properties", properties).put("observedAtMs", 1234);
        JSONObject left = new JSONObject(); OfficialBodySignals.append(left, probe, 1);
        check(left.getJSONObject("doorFrontLeft").getInt("raw") == 0);
        check(left.getJSONObject("doorFrontRight").getInt("raw") == 2);
        check(left.getJSONObject("doorRearLeft").getInt("raw") == 1);
        check(left.getJSONObject("doorRearRight").getInt("raw") == 3);
        check(left.getJSONObject("tailgateOpen").getInt("raw") == 4);
        for (String key : new String[]{"doorFrontLeft", "doorFrontRight", "doorRearLeft", "doorRearRight", "tailgateOpen", "hoodOpen"})
            check(!left.getJSONObject(key).getBoolean("valid") && !left.getJSONObject(key).getBoolean("writable"));
        JSONObject right = new JSONObject(); OfficialBodySignals.append(right, probe, 4);
        check(right.getJSONObject("doorFrontRight").getInt("raw") == 0);
        check(right.getJSONObject("doorFrontLeft").getInt("raw") == 2);
        JSONObject unknown = new JSONObject(); OfficialBodySignals.append(unknown, probe, 0);
        check(!unknown.getJSONObject("doorFrontLeft").has("raw"));
        check(unknown.getJSONObject("tailgateOpen").getInt("raw") == 4);
        System.out.println("OfficialBodySignalsTest passed");
    }
}
