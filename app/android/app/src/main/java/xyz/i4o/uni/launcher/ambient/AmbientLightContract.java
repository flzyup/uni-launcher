package xyz.i4o.uni.launcher.ambient;

/**
 * Ambient light contract for the DCY11 / IP753 head unit.
 *
 * The ambience light is a group of {@code SETTING_FUNC_AMBIENCE_LIGHT_*}
 * setting functions in the same vendor SDK the climate path already uses
 * ({@code Car.create -> ICarFunction}). Writes use the same call shape as the
 * HVAC properties: {@code setFunctionValue(function, zone, value)}.
 *
 * | intent | function name | value |
 * | --- | --- | --- |
 * | switch the strip | {@link #FUNC_INTERACTIVE_EFFECT} | 1 on / 0 off |
 * | colour source = custom | {@link #FUNC_MAIN_COLOR} | {@link #VALUE_MAIN_COLOR_SET_COLOR} |
 * | colour | {@link #FUNC_COLOR_SET} | packed 0xRRGGBB |
 * | driving brightness | {@link #FUNC_BRIGHTNESS_DRIVING} | {@link #VALUE_BRIGHTNESS_HIGH} / {@link #VALUE_BRIGHTNESS_LOW} / 0 |
 * | stationary brightness | {@link #FUNC_BRIGHTNESS_STATIONARY} | {@link #VALUE_STATIONARY_HIGH} / {@link #VALUE_STATIONARY_LOW} / 0 |
 * | light the main zone | {@link #FUNC_MAIN_ZONES} | 1 |
 * | light the top zone | {@link #FUNC_TOP_ZONES} | 1 |
 * | light the bottom zone | {@link #FUNC_BOT_ZONES} | 1 |
 * | experience = custom | {@link #FUNC_EXPERIENCE} | {@link #VALUE_EXPERIENCE_CUSTOM} |
 *
 * The "interactive effect" switch is the vendor's music reaction mode. The
 * main colour is set to the custom colour so the colour we compute from the
 * spectrum is what the strip shows.
 *
 * <h3>Zones are three separate functions</h3>
 * The vendor exposes main / top / bottom as three independent function ids.
 * Writing the main zone does not light the top or bottom zone, so all three
 * are written when the strip is switched on.
 *
 * <h3>Brightness has two ladders</h3>
 * Driving and stationary brightness are different function ids with different
 * constants ({@code BRIGHTNESS_DRIVING_LOW} is not
 * {@code BRIGHTNESS_STATIONARY_LOW}). Writing only the driving ladder leaves
 * the brightness frozen while the car is parked.
 *
 * <h3>Zero means OFF, not the dimmest step</h3>
 * The vendor maps 0 to {@code OFF}. Passing 0 as "lowest brightness" switches
 * the strip off, so brightness 0 is deliberately treated as off here.
 *
 * <h3>Values are resolved by name</h3>
 * The ids live in the head unit jar, which this project never links against.
 * Every constant is therefore resolved reflectively by name through
 * {@link AmbientLightResolver}; a name that does not resolve is never guessed
 * into a different function. The numeric fallbacks below are the audited jar
 * values and are only used when the class is present but the field cannot be
 * read.
 */
public final class AmbientLightContract {
    private AmbientLightContract() {}

    /** Ambience light main colour source (theme / driver mode / set colour). */
    public static final String FUNC_MAIN_COLOR = "SETTING_FUNC_AMBIENCE_LIGHT_MAINCOLOR";

    /** Ambience light interactive effect switch, the vendor's music reaction. */
    public static final String FUNC_INTERACTIVE_EFFECT = "SETTING_FUNC_AMBIENCE_LIGHT_INTERACTIVE_EFFECT";

    /** Ambience light colour, written as a packed 0xRRGGBB value. */
    public static final String FUNC_COLOR_SET = "SETTING_FUNC_AMBIENCE_LIGHT_COLOR_SET";

    /** Ambience light brightness while driving. */
    public static final String FUNC_BRIGHTNESS_DRIVING = "SETTING_FUNC_AMBIENCE_LIGHT_BRIGHTNESS_DRIVING";

    /** Ambience light brightness while parked. */
    public static final String FUNC_BRIGHTNESS_STATIONARY = "SETTING_FUNC_AMBIENCE_LIGHT_BRIGHTNESS_STATIONARY";

    /** Ambience light main zone switch. */
    public static final String FUNC_MAIN_ZONES = "SETTING_FUNC_AMBIENCE_LIGHT_MAINZONES";

    /** Ambience light top zone switch. */
    public static final String FUNC_TOP_ZONES = "SETTING_FUNC_AMBIENCE_LIGHT_TOPZONES";

    /** Ambience light bottom zone switch. */
    public static final String FUNC_BOT_ZONES = "SETTING_FUNC_AMBIENCE_LIGHT_BOTZONES";

    /** Ambience light experience mode, separate from the main colour source. */
    public static final String FUNC_EXPERIENCE = "SETTING_FUNC_AMBIENCE_LIGHT_EXPERIENCE";

    /** Main colour source value: use the colour written by the app. */
    public static final String VALUE_MAIN_COLOR_SET_COLOR = "AMBIENCE_LIGHT_MAINCOLOR_SETCOLOR";

    /** Experience mode value: custom. */
    public static final String VALUE_EXPERIENCE_CUSTOM = "AMBIENCE_LIGHT_EXPERIENCE_CUSTOM";

    /** Experience mode value: full. */
    public static final String VALUE_EXPERIENCE_FULL = "AMBIENCE_LIGHT_EXPERIENCE_FULL";

    /** Driving brightness value: high. */
    public static final String VALUE_BRIGHTNESS_HIGH = "BRIGHTNESS_DRIVING_HIGH";

    /** Driving brightness value: low. */
    public static final String VALUE_BRIGHTNESS_LOW = "BRIGHTNESS_DRIVING_LOW";

    /** Stationary brightness value: high. */
    public static final String VALUE_STATIONARY_HIGH = "BRIGHTNESS_STATIONARY_HIGH";

    /** Stationary brightness value: low. */
    public static final String VALUE_STATIONARY_LOW = "BRIGHTNESS_STATIONARY_LOW";

    /** The three zone function ids, in main / top / bottom order. */
    public static final String[] ZONE_FUNCTIONS = {
        FUNC_MAIN_ZONES, FUNC_TOP_ZONES, FUNC_BOT_ZONES
    };

    /**
     * Every name this feature resolves, for the diagnostics dump.
     *
     * <p>The dump lists which of them do not resolve on this head unit, so a
     * missing id can be told apart from a missing vehicle handle.
     */
    public static final String[] ALL_NAMES = {
        FUNC_MAIN_COLOR, FUNC_INTERACTIVE_EFFECT, FUNC_COLOR_SET,
        FUNC_BRIGHTNESS_DRIVING, FUNC_BRIGHTNESS_STATIONARY,
        FUNC_MAIN_ZONES, FUNC_TOP_ZONES, FUNC_BOT_ZONES, FUNC_EXPERIENCE,
        VALUE_MAIN_COLOR_SET_COLOR, VALUE_EXPERIENCE_CUSTOM,
        VALUE_BRIGHTNESS_HIGH, VALUE_BRIGHTNESS_LOW,
        VALUE_STATIONARY_HIGH, VALUE_STATIONARY_LOW
    };

    /** The ambience light functions do not use a zone. */
    public static final int ZONE = 0;

    /** Switch value for on. */
    public static final int ON = 1;

    /** Switch value for off. */
    public static final int OFF = 0;

    /**
     * Audited driving brightness fallback (the jar value of
     * {@code IVehicle.BRIGHTNESS_DRIVING_HIGH}).
     */
    public static final int FALLBACK_BRIGHTNESS_HIGH = 537528066;

    /**
     * Audited driving brightness fallback (the jar value of
     * {@code IVehicle.BRIGHTNESS_DRIVING_LOW}).
     */
    public static final int FALLBACK_BRIGHTNESS_LOW = 537528065;

    /**
     * Audited stationary brightness fallback (the jar value of
     * {@code IVehicle.BRIGHTNESS_STATIONARY_HIGH}).
     */
    public static final int FALLBACK_STATIONARY_HIGH = 537527810;

    /**
     * Audited stationary brightness fallback (the jar value of
     * {@code IVehicle.BRIGHTNESS_STATIONARY_LOW}).
     */
    public static final int FALLBACK_STATIONARY_LOW = 537527809;

    /**
     * Classes that host the ambience light constants, most likely first.
     *
     * <p>The audited jar places {@code SETTING_FUNC_AMBIENCE_LIGHT_*} in
     * {@code com.ecarx.xui.adaptapi.car.vehicle.IAmbienceLight} and the
     * {@code AMBIENCE_LIGHT_*} / {@code BRIGHTNESS_*} values in
     * {@code com.ecarx.xui.adaptapi.car.vehicle.IVehicle}. Both are plain
     * constant interfaces.
     *
     * <p>The remaining entries are the names the vendor jar is known to use
     * elsewhere. They are a fallback only: a class that is not on the head
     * unit is simply skipped and the lookup continues with the next one.
     */
    public static final String[] CONSTANT_CLASSES = {
        // —— jar 实测确认的常量宿主 ——
        "com.ecarx.xui.adaptapi.car.vehicle.IAmbienceLight",
        "com.ecarx.xui.adaptapi.car.vehicle.IVehicle",
        "com.ecarx.xui.adaptapi.car.vehicle.IBcm",
        "com.ecarx.xui.adaptapi.vehicle.VehicleDoor",
        "com.ecarx.xui.adaptapi.vehicle.VehicleWindow",
        // —— 早期按惯例猜的候选（保留作兜底）——
        "com.ecarx.xui.adaptapi.car.Car",
        "com.ecarx.xui.adaptapi.car.ICarFunction",
        "com.ecarx.xui.adaptapi.car.CarFunction",
        "com.ecarx.xui.adaptapi.car.CarFunctionId",
        "com.ecarx.xui.adaptapi.car.CarFunctionIds",
        "com.ecarx.xui.adaptapi.car.CarFunc",
        "com.ecarx.xui.adaptapi.car.CarZone",
        "com.ecarx.xui.adaptapi.car.CarZones",
        "com.ecarx.xui.adaptapi.car.CarArea",
        "com.ecarx.xui.adaptapi.car.CarAreas",
        "com.ecarx.xui.adaptapi.car.CarConstant",
        "com.ecarx.xui.adaptapi.car.CarConstants",
        "com.ecarx.xui.adaptapi.car.BcmFunc",
        "com.ecarx.xui.adaptapi.car.BcmFuncId",
        "com.ecarx.xui.adaptapi.car.CarBcm",
        "com.ecarx.xui.adaptapi.car.CarProperty",
        "com.ecarx.xui.adaptapi.car.CarProperties",
        "com.ecarx.xui.adaptapi.ICarFunction",
        "com.ecarx.xui.adaptapi.Car",
        "com.ecarx.xui.adaptapi.FunctionId",
        "com.ecarx.xui.adaptapi.FunctionIds",
        "com.ecarx.xui.adaptapi.Constants",
    };
}
