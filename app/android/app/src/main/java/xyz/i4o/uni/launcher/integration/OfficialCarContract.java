package xyz.i4o.uni.launcher.integration;

/**
 * DCY11/IP753 contracts, verified against the car's ecarx.adapterapi.jar, SHA256
 * f4704d7d90ad24f8100bcc686b1ca0dba005777466d75b8f65242f2785d597bf.
 *
 * Official Launcher3 CarUtils: analysis/raw/official/bytecode.txt:87019,87194.
 * The actual XCHvac.apk HvacController uses this same Car.create/ICarFunction
 * path. The supplied *.inter.apk files are resource overlays, without DEX.
 * Host analysis and disassembly: /tmp/lynk-vehicle-audit-20261024/.
 *
 * WRITE CONTRACT ONLY; this class never sends a command. ICarFunction signatures:
 * getFunctionValue(int function[, int zone]) -> int;
 * getCustomizeFunctionValue(int function[, int zone]) -> float;
 * setFunctionValue(int function, int value) -> boolean;
 * setFunctionValue(int function, int zone, int value) -> boolean;
 * setCustomizeFunctionValue(int function, int zone, float value) -> boolean.
 * Zone precedes value. Both reads and writes of these vendor properties require
 * android.car.permission.CAR_VENDOR_EXTENSION (signature|privileged). HAL PA
 * state properties are READ, CB command properties are WRITE, always area 0;
 * a function zone is not a HAL area ID. A setter result is not actuator ACK.
 *
 * Functions use 0/1 for switches. Fan writes use FAN + level (1..7), or 0 OFF;
 * FAN + 10 (AUTO) is advertised but rejected by this firmware's write mapper.
 * Heating writes use HEAT + level (1..3), or 0 OFF; ventilation uses VENT +
 * level (1..3), or 0 OFF. Plain 1/2/3 are not SDK seat/fan write values.
 * PA protobuf field 4 is sint32: decode ZigZag before applying any enum map.
 * In particular wire 2/6/14 mean native PA data 1/3/7, not those wire numbers.
 * Temperature is a float in the PA temperature unit, never legacy degrees * 2;
 * this car's cached temperature format is Celsius. TEMP_MIN/MAX/STEP are
 * getCustomizeFunctionValue() queries (16/31/0.5 in the audited framework).
 * Front defrost 0x10040100 is explicitly unsupported; FRONT_MAX is separate.
 * Driver ventilation is restricted by CarConfig[8] (2 = right hand drive).
 *
 * Implementation evidence: CarFunctionValueImpl, CarFunctionCustomizedValueImpl,
 * CarFunctionValueUtil and VehicleSignalManager in that JAR; permission checks:
 * CarService.apk CarPropertyService and PropertyHalServiceIds.insertVendorProperty.
 */
public final class OfficialCarContract {
    private OfficialCarContract() {}

    public static final String PERMISSION = "android.car.permission.CAR_VENDOR_EXTENSION";
    public static final String SDK_CAR = "com.ecarx.xui.adaptapi.car.Car";
    public static final String CONNECTABLE = "com.ecarx.xui.adaptapi.binder.IConnectable";
    public static final String CONNECT_WATCHER = CONNECTABLE + "$IConnectWatcher";
    public static final String FUNCTION_WATCHER =
            "com.ecarx.xui.adaptapi.car.base.ICarFunction$IFunctionValueWatcher";
    public static final String SIGNALS = "se.cevt.vehiclesignals.VehicleSignalManager";
    public static final String SIGNAL_PACKAGE = "se.cevt.vehiclesignals.";

    public static final int LEFT = 1, RIGHT = 4;
    public static final int POWER = 0x10010100, AUTO = 0x10010200;
    public static final int AC = 0x10010300, AC_MAX = 0x10010400;
    public static final int FAN = 0x10020100, CIRCULATION = 0x10030100;
    public static final int FRONT_UNSUPPORTED = 0x10040100;
    public static final int FRONT_MAX = 0x10040200, REAR_DEFROST = 0x10040300;
    public static final int VENT = 0x10050100, HEAT = 0x10050200;
    public static final int TEMP = 0x10060100, TEMP_MAX = 0x10060200;
    public static final int TEMP_MIN = 0x10060300, TEMP_STEP = 0x10060400;
    public static final int SYNC = 0x10060500, TEMP_UNIT = 0x10060600;
    public static final int BLOWING = 0x10070100, ECO = 0x10080100;
    public static final int CIRCULATION_INNER = CIRCULATION + 1;
    public static final int CIRCULATION_OUTSIDE = CIRCULATION + 2;

    public static final int PA_LEFT_TEMP = 0x21701107, PA_RIGHT_TEMP = 0x21701108;
    public static final int PA_FAN = 0x21701106, PA_AUTO = 0x21701102;
    public static final int PA_AC = 0x21701101, PA_POWER = 0x21701116;
    public static final int PA_RECIRC = 0x21701103, PA_SYNC = 0x21701111;
    public static final int PA_FRONT_MAX = 0x2170110b, PA_REAR_DEFROST = 0x21701110;
    public static final int PA_BLOWING = 0x21701104;
    public static final int PA_LEFT_HEAT = 0x2170111f, PA_RIGHT_HEAT = 0x21701120;
    public static final int PA_VENT = 0x2170111b;
    public static final int PA_PRESSURE_FL = 0x21701053, PA_PRESSURE_FR = 0x21701054;
    public static final int PA_PRESSURE_RL = 0x21701055, PA_PRESSURE_RR = 0x21701056;
    public static final int PA_PRESSURE_UNIT = 0x21701057;
    public static final int CAR_CONFIG = 0x21415114;
    public static final int TIRE_PRESSURE_UNIT = 0x25010500;

    /** Official Launcher3 CarUtils camera gate (bytecode 86965..87470). The
     * firmware ships both parking activities component-disabled; the HOME
     * launcher reads this capability, enables exactly one component and starts
     * it. Values are SDK-mapped function values, not raw PA data. */
    public static final int PAC_CAMERA_CAPABILITY = 0x23050080;
    public static final int PAC_CAMERA_NONE = 0;
    public static final int PAC_CAMERA_REARONLY = 587400449; // 0x23050081
    public static final int PAC_CAMERA_360AM = 587400450;    // 0x23050082

    // Command IDs are evidence for future implementation, never invoked here.
    public static final int CB_LEFT_TEMP = 0x21602106, CB_RIGHT_TEMP = 0x21602107;
    public static final int CB_FAN = 0x21402101, CB_AUTO = 0x2140210c;
    public static final int CB_AC = 0x21402110, CB_POWER = 0x21402124;
    public static final int CB_RECIRC = 0x21402102, CB_SYNC = 0x21402105;
    public static final int CB_LEFT_HEAT = 0x21402117, CB_RIGHT_HEAT = 0x21402118;
    public static final int CB_VENT = 0x21402113;
    public static final int CB_FRONT_MAX = 0x21402126, CB_REAR_DEFROST = 0x21402127;

    public static final int[] WATCHED_FUNCTIONS = {
        POWER, AUTO, AC, FAN, CIRCULATION, SYNC, TEMP, HEAT, VENT,
        FRONT_MAX, REAR_DEFROST, BLOWING
    };

    static boolean switchValue(int raw) { return raw == 0 || raw == 1; }
    static boolean seatLevel(int raw) { return raw >= 0 && raw <= 3; }
    static boolean fanLevel(int raw) { return raw >= 0 && raw <= 8; }

    /** Unit setting is a display preference; it does not prove PA pressure units. */
    static String pressurePreference(int raw) {
        switch (raw) {
            case 0: return "kPa";
            case 1: return "psi";
            case 2: return "bar";
            default: return null;
        }
    }

    static String blowingMode(int raw) {
        switch (raw) {
            case 0: return "floor";
            case 1: return "face";
            case 2: return "defrost";
            case 3: return "floor-defrost";
            case 4: return "floor-face";
            case 5: return "face-defrost";
            case 6: return "all";
            case 7: return "auto";
            default: return null;
        }
    }

    static int blowingSdkValue(int raw) {
        switch (raw) {
            case 0: return BLOWING + 2;
            case 1: return BLOWING + 1;
            case 2: return BLOWING + 4;
            case 3: return BLOWING + 6;
            case 4: return BLOWING + 3;
            case 5: return BLOWING + 5;
            case 6: return BLOWING + 7;
            case 7: return BLOWING + 8;
            default: return -1;
        }
    }
}
