package xyz.i4o.uni.launcher.integration;

/** HAL/PA contract doubles only; no SDK binary, Android methods or device. */
public final class OfficialHybridReaderTest {
    public static final class Hal {
        Object value; int status;
        Hal(Object value) { this.value = value; }
        public int getStatus() { return status; }
        public long getTimestamp() { return 123; }
        public Object getValue() { return value; }
    }
    public static final class Manager {
        Hal hal; Class<?> requested; int property;
        public Hal getProperty(Class<?> type, int property, int area) {
            this.requested = type; this.property = property;
            if (area != 0) throw new AssertionError("area");
            return hal;
        }
    }
    static int checks;
    static void check(boolean test) { checks++; if (!test) throw new AssertionError("check " + checks); }
    public static void main(String[] args) {
        Manager m = new Manager(); OfficialHybridReader r = new OfficialHybridReader(m);
        m.hal = new Hal(7);
        check(r.read(OfficialHybridReader.DRIVE_MODE).value.equals("PURE"));
        check(m.requested == Integer.class && m.property == 0x21403018);
        check(OfficialHybridReader.driveMode(8).equals("HYBRID"));
        check(OfficialHybridReader.driveMode(9).equals("POWER"));
        check(OfficialHybridReader.driveMode(11).equals("ECO_HEV_PHEV"));
        check(OfficialHybridReader.driveMode(12).equals("COMFORT_HEV"));
        for (Integer n : new Integer[]{null, -1, 0, 13, Integer.MAX_VALUE}) check(OfficialHybridReader.driveMode(n) == null);
        m.hal.status = 1; check(!r.read(OfficialHybridReader.DRIVE_MODE).valid);
        m.hal = new Hal("7"); check(!r.read(OfficialHybridReader.DRIVE_MODE).valid);
        m.hal = null; check(!r.read(OfficialHybridReader.DRIVE_MODE).valid);
        m.hal = new Hal(new byte[]{8, 1, 32, 2}); // ACTIVE, ZigZag1
        check(Boolean.TRUE.equals(r.read(OfficialHybridReader.HYBRID_SELECTED).value));
        check(m.requested == byte[].class);
        check(Boolean.FALSE.equals(OfficialHybridReader.hybridSelected(0)));
        check(OfficialHybridReader.hybridSelected(2) == null);
        m.hal.value = new byte[]{8, 2, 32, 0}; check(!r.read(OfficialHybridReader.HYBRID_SELECTED).valid);
        m.hal.value = new byte[]{8, 1}; check(!r.read(OfficialHybridReader.HYBRID_SELECTED).valid);
        m.hal.value = new byte[]{8, 1, 32, 12};
        check(r.read(OfficialHybridReader.ENERGY_FLOW).value.equals("ELECTRIC_DRIVE"));
        check(OfficialHybridReader.energyFlow(1).equals("MAIN_CHARGING"));
        check(OfficialHybridReader.energyFlow(5).equals("ENGINE_ONLY_AND_CHARGE"));
        check(OfficialHybridReader.energyFlow(12).equals("ENGINE_ON_REGEN_BRAKE_CHARGE"));
        for (Integer n : new Integer[]{null, -1, 13, Integer.MAX_VALUE}) check(OfficialHybridReader.energyFlow(n) == null);
        m.hal.value = new byte[]{8, 1, 32, 26}; check(!r.read(OfficialHybridReader.ENERGY_FLOW).valid);
        m.hal.value = new byte[]{8, 1, 16, 0, 32, 100}; // known format, unconfirmed range domain
        OfficialHybridReader.Sample range = r.read(OfficialHybridReader.ELECTRIC_RANGE);
        check(!range.valid && range.value == null && range.raw == 50 && "km".equals(range.unit));
        m.hal.value = new byte[]{8, 1, 16, 99, 32, 0};
        check("unconfirmed".equals(r.read(OfficialHybridReader.ELECTRIC_RANGE).unit));
        System.out.println("OfficialHybridReaderTest passed (" + checks + " HAL/type/enum/PA/range checks; no device)");
    }
}
