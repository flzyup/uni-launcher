package xyz.i4o.uni.launcher.integration;

/** Host-only fake SDK/PA tests. No Android methods, SDK binary, device or writes. */
public final class OfficialVehicleSensorsTest {
    public enum Availability { ACTIVE, NOT_ACTIVE, NOT_AVAILABLE, ERROR }
    public static final class Pa {
        public final Availability availability;
        public final Object data;
        public final Integer level = 99;
        public Pa(Availability availability, Object data) { this.availability = availability; this.data = data; }
    }
    public static final class Signals {
        boolean ready = true;
        Pa pa = new Pa(Availability.ACTIVE, 0);
        public boolean isReady() { return ready; }
        public Pa getPaClAqInsideRaw() { return pa; }
        public Pa getPaClAqInsideIndex() { return pa; }
        public Pa getPaNaviVehSpeed() { return pa; }
        public Pa getPaDiDstTrVld() { return pa; }
        public Pa getPaDiDstToEmpty() { return pa; }
        public Pa getPaDiDstToSrv() { return pa; }
        public Pa getBliHvBattLevelIndicationIhu() { return pa; }
    }
    public static final class Sensors {
        String support = "active";
        double value;
        public String isSensorSupported(int id) { return support; }
        public float getSensorLatestValue(int id) { return (float) value; }
    }
    private static void check(boolean value, String reason) { if (!value) throw new AssertionError(reason); }
    private static OfficialVehicleSensors.Sample read(Signals signals, Sensors sdk, int index, OfficialVehicleSensors.Units units) {
        return OfficialVehicleSensors.readSample(sdk, signals, OfficialVehicleSensors.SPECS[index], units);
    }
    public static void main(String[] args) {
        Signals signals = new Signals(); Sensors sdk = new Sensors();
        OfficialVehicleSensors.Units unknown = OfficialVehicleSensors.Units.unconfirmed();
        OfficialVehicleSensors.Units proven = OfficialVehicleSensors.Units.confirmed("m/s", "km", "synthetic test fixture only");
        check(read(signals, sdk, 0, unknown).valid, "active real PA zero is valid");
        signals.pa = null;
        check(!read(signals, sdk, 0, unknown).valid, "SDK zero cannot replace absent PA");
        signals.pa = new Pa(Availability.NOT_ACTIVE, 0);
        check(!read(signals, sdk, 0, unknown).valid, "inactive zero");
        signals.pa = new Pa(Availability.ACTIVE, 1050);
        check(!read(signals, sdk, 0, unknown).valid, "PM25 SDK sentinel fallback rejected");
        signals.pa = new Pa(Availability.ACTIVE, 500); sdk.value = 500;
        check(read(signals, sdk, 1, unknown).valid, "AQI is independent from PM25");
        sdk.support = "notavailable";
        check(!read(signals, sdk, 1, unknown).valid && !read(signals, sdk, 1, unknown).supported, "SDK support checked separately");
        sdk.support = "active"; sdk.value = 499;
        check(!read(signals, sdk, 1, unknown).valid, "SDK/PA mismatch");
        signals.pa = new Pa(Availability.ACTIVE, 1250); sdk.value = 12.5;
        check(read(signals, sdk, 2, unknown).sampleValid && !read(signals, sdk, 2, unknown).valid, "speed unit unconfirmed");
        check(read(signals, sdk, 2, proven).value == 12.5, "speed divide100 exactly once");
        signals.pa = new Pa(Availability.ACTIVE, 0); sdk.value = 0;
        check(read(signals, sdk, 3, proven).valid, "zero odometer");
        signals.pa = new Pa(Availability.ACTIVE, 4096); sdk.value = 0;
        check(!read(signals, sdk, 4, proven).valid, "range bound prevents fabricated zero");
        signals.pa = new Pa(Availability.ACTIVE, 32001);
        check(!read(signals, sdk, 5, proven).valid, "maintenance bound");
        signals.pa = new Pa(Availability.ACTIVE, 37.5d); sdk.value = 37.5;
        OfficialVehicleSensors.Sample battery = read(signals, sdk, 6, unknown);
        check(battery.valid && battery.value == 37.5 && battery.level.equals(99), "battery uses data, not level");
        check(battery.spec.id == 4210688 && "%".equals(battery.unit), "PHEV exact ID and percent unit");
        signals.pa = new Pa(Availability.ACTIVE, 0d); sdk.value = 0;
        check(read(signals, sdk, 6, unknown).valid, "active battery0 is valid");
        signals.pa = new Pa(Availability.ACTIVE, 101d);
        check(!read(signals, sdk, 6, unknown).valid, "battery upper bound");
        signals.pa = new Pa(Availability.ACTIVE, Double.NaN);
        check(!read(signals, sdk, 6, unknown).valid, "battery NaN");
        signals.pa = new Pa(Availability.ACTIVE, 37); sdk.value = 37;
        check(!read(signals, sdk, 6, unknown).valid, "battery PA data type");
        signals.pa = new Pa(Availability.ACTIVE, 37d); signals.ready = false;
        check(!read(signals, sdk, 6, unknown).valid, "disconnected");
        signals.ready = true;
        check(read(signals, null, 6, unknown).valid, "PA-only borrowed manager");
        try { OfficialVehicleSensors.Units.confirmed("km/h", "km", ""); throw new AssertionError("missing unit proof"); }
        catch (IllegalArgumentException expected) {}
        System.out.println("OfficialVehicleSensorsTest passed (PA availability, SDK fallback, range, units and PHEV percentage)");
    }
}
