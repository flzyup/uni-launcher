package xyz.i4o.uni.launcher.core;

/** Input boundary shared by the simulator and future verified vehicle adapter. */
public final class CommandPolicy {
    private CommandPolicy() {}
    /** Routing only. Seat writes require the corresponding seatCapabilities entry, not climate writable. */
    public static boolean isClimateAction(String action) {
        return "temp-up".equals(action) || "temp-down".equals(action) || "fan-up".equals(action)
            || "fan-down".equals(action) || "climate-power".equals(action) || "climate-mode".equals(action)
            || isSeatAction(action);
    }
    public static boolean isSeatAction(String action) {
        return "seat-heat".equals(action) || "seat-vent".equals(action);
    }
    /** Per-control capability key; null means the action/zone pair is unsupported. */
    public static String seatControl(String action, String zone) {
        if ("seat-heat".equals(action)) {
            if ("left".equals(zone)) return "driverHeat";
            if ("right".equals(zone)) return "passengerHeat";
        } else if ("seat-vent".equals(action) && "left".equals(zone)) return "driverVent";
        return null;
    }
    public static boolean validSeatLevel(String value) {
        return value != null && value.length() == 1 && value.charAt(0) >= '0' && value.charAt(0) <= '3';
    }
    public static boolean validZone(String zone) { return "left".equals(zone) || "right".equals(zone); }
    public static boolean validMode(String mode) {
        return "auto".equals(mode) || "ac".equals(mode) || "sync".equals(mode) || "recirc".equals(mode);
    }
    public static double temperature(double value) { return Math.max(16, Math.min(30, Math.round(value * 2) / 2.0)); }
    public static int fan(int value) { return Math.max(1, Math.min(7, value)); }
}
