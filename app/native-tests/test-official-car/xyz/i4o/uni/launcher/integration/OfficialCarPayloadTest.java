package xyz.i4o.uni.launcher.integration;

import java.io.IOException;

/** Regression cases from read-only car_service HAL event cache, 2026-10-24.
 * Runs separately on the host JVM; does not load the OEM SDK or connect to any car.
 */
public final class OfficialCarPayloadTest {
    private static void check(boolean ok, String message) {
        if (!ok) throw new AssertionError(message);
    }
    private static OfficialCarPayload pa(int... data) throws IOException {
        byte[] bytes = new byte[data.length];
        for (int i = 0; i < data.length; i++) bytes[i] = (byte) data[i];
        return OfficialCarPayload.parse(bytes);
    }
    private static void malformed(int... data) throws IOException {
        try { pa(data); } catch (IOException expected) { return; }
        throw new AssertionError("Malformed PA was accepted");
    }
    public static void main(String[] args) throws Exception {
        // Both front temperature properties: active, Celsius, idle, 22.5.
        OfficialCarPayload temperature = pa(8,1,16,0,24,0,41,0,0,0,0,0,128,54,64);
        check(temperature.active(), "active temperature");
        check(temperature.format == 0 && temperature.status == 0, "format/status");
        check(temperature.doubleData() == 22.5, "temperature must not be divided by 2");
        check(temperature.integerData() == null, "double cannot masquerade as enum");

        // Real wire values are ZigZag sint32, not native PA enum values.
        OfficialCarPayload power = pa(8,1,32,2), vent = pa(8,1,32,6);
        check(power.integerData() == 1 && power.int32Wire == 2 && OfficialCarContract.switchValue(power.integerData()), "power wire 2 is ON");
        check(vent.integerData() == 3 && vent.int32Wire == 6 && OfficialCarContract.seatLevel(vent.integerData()), "vent wire 6 is LVL3");
        check(pa(8,1,32,2).integerData() == 1, "sync wire 2 is ON");
        check("auto".equals(OfficialCarContract.blowingMode(pa(8,1,32,14).integerData())), "blowing wire 14 is AUTO");
        check(OfficialCarContract.blowingSdkValue(7) == 0x10070108, "official blowing AUTO mapper");
        check(pa(8,1,32,2).integerData() == 1, "fan wire 2 is LVL1, not LVL2");
        check(pa(8,1,32,4).integerData() == 2 && !OfficialCarContract.switchValue(2), "genuine unknown switch retained");
        check(pa(8,1,32,12).integerData() == 6 && !OfficialCarContract.seatLevel(6), "genuine unknown seat retained");
        check(pa(8,1,32,1).integerData() == -1 && OfficialCarContract.pressurePreference(-1) == null, "unit wire1 is -1, never PSI");
        check(pa(8,1,32,255,255,255,255,15).integerData() == Integer.MIN_VALUE, "sint32 minimum");
        check(pa(8,1,32,254,255,255,255,15).integerData() == Integer.MAX_VALUE, "sint32 maximum");
        check(OfficialCarContract.seatLevel(pa(8,1,32,0).integerData()), "active seat OFF is valid");
        check(!pa(32,0).active(), "missing availability is not active");
        check(!pa(8,2,32,0).active(), "inactive OFF is not a valid current state");
        check(!pa(8,0,32,0).active(), "not available is not active");

        // Preserve tyre raw doubles and the separate unit preference.
        OfficialCarPayload pressure = pa(8,1,41,0,0,0,0,0,192,109,64); // 238.0, synthetic only
        check(pressure.doubleData() == 238, "pressure double");
        check("kPa".equals(OfficialCarContract.pressurePreference(0)), "unit preference 0");
        check("psi".equals(OfficialCarContract.pressurePreference(1)), "unit preference 1");
        check("bar".equals(OfficialCarContract.pressurePreference(2)), "unit preference 2");
        check(OfficialCarContract.pressurePreference(3) == null, "unknown unit");
        check(OfficialCarContract.fanLevel(8), "read-side fan AUTO exists");

        // Unknown fields can be skipped; missing/wrong numeric types stay missing.
        check(pa(8,1,32,6,82,2,1,2).integerData() == 3, "skip unknown field");
        check(pa(8,1,32,3,50,0).data == null, "oneof string replaces integer");
        check(pa(8,1,32,0,41,0,0,0,0,0,128,54,64).doubleData() == 22.5, "oneof last wins");
        check(pa(8,1,41,0,0,0,0,0,0,248,127).doubleData() == null, "reject NaN");
        malformed(0); malformed(8); malformed(10,0); malformed(41,0);
        malformed(82,127,1); malformed(11); malformed(8,129,128,128,128,16);
        malformed(128,128,128,128,128,128,128,128,128,128,0);
        malformed(32,128,128,128,128,16);
        System.out.println("OfficialCarPayloadTest passed (recorded PA samples + protocol/enum regression cases)");
    }
}
