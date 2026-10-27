package xyz.i4o.uni.launcher.integration;

/** Pure command planning. Has no Android, Binder or SDK dependency. */
final class OfficialCarCommand {
    final String key;
    final int function, zone, intValue;
    final Float temperature;
    final Object expected;

    private OfficialCarCommand(String key, int function, int zone, int value, Float temperature, Object expected) {
        this.key = key; this.function = function; this.zone = zone;
        this.intValue = value; this.temperature = temperature; this.expected = expected;
    }

    static String key(String action, String zone, String mode) {
        if ("temp-up".equals(action) || "temp-down".equals(action))
            return "left".equals(zone) || "right".equals(zone) ? zone : null;
        if ("fan-up".equals(action) || "fan-down".equals(action)) return "fan";
        if ("climate-power".equals(action)) return "power";
        if ("climate-mode".equals(action))
            return "auto".equals(mode) || "ac".equals(mode) || "recirc".equals(mode) || "sync".equals(mode) ? mode : null;
        if ("seat-heat".equals(action))
            return "left".equals(zone) ? "driverHeat" : "right".equals(zone) ? "passengerHeat" : null;
        if ("seat-vent".equals(action) && "left".equals(zone)) return "driverVent";
        return null;
    }

    static OfficialCarCommand plan(String action, String uiZone, String mode, Object current,
                                    int driverZone, double min, double max, double step) {
        String key = key(action, uiZone, mode);
        if (key == null) return null;
        if ("left".equals(key) || "right".equals(key)) {
            if (!(current instanceof Number) || !finite(min) || !finite(max) || !finite(step)
                    || min != 16 || max != 31 || step != 0.5) return null;
            double value = ((Number) current).doubleValue();
            if (!finite(value) || value < min || value > max) return null;
            double target = Math.max(min, Math.min(max, value + ("temp-up".equals(action) ? step : -step)));
            return new OfficialCarCommand(key, OfficialCarContract.TEMP, "left".equals(key) ? 1 : 4,
                    0, (float) target, target);
        }
        if ("fan".equals(key)) {
            if (!(current instanceof Number)) return null; // Never send advertised-but-unmapped AUTO.
            double raw = ((Number) current).doubleValue();
            if (!finite(raw) || raw != Math.rint(raw) || raw < 0 || raw > 7) return null;
            int target = Math.max(0, Math.min(7, (int) raw + ("fan-up".equals(action) ? 1 : -1)));
            return new OfficialCarCommand(key, OfficialCarContract.FAN, 0,
                    target == 0 ? 0 : OfficialCarContract.FAN + target, null, target);
        }
        if (key.endsWith("Heat") || "driverVent".equals(key)) {
            if ((driverZone != 1 && driverZone != 4) || mode == null || mode.length() != 1
                    || mode.charAt(0) < '0' || mode.charAt(0) > '3') return null;
            int function = "driverVent".equals(key) ? OfficialCarContract.VENT : OfficialCarContract.HEAT;
            int zone = "passengerHeat".equals(key) ? (driverZone == 1 ? 4 : 1) : driverZone;
            int level = mode.charAt(0) - '0';
            return new OfficialCarCommand(key, function, zone, level == 0 ? 0 : function + level, null, level);
        }
        if (!(current instanceof Boolean)) return null;
        boolean target = !((Boolean) current);
        int function = "power".equals(key) ? OfficialCarContract.POWER
                : "auto".equals(key) ? OfficialCarContract.AUTO
                : "ac".equals(key) ? OfficialCarContract.AC
                : "sync".equals(key) ? OfficialCarContract.SYNC : OfficialCarContract.CIRCULATION;
        int encoded = function == OfficialCarContract.CIRCULATION
                ? (target ? OfficialCarContract.CIRCULATION_INNER : OfficialCarContract.CIRCULATION_OUTSIDE)
                : (target ? 1 : 0);
        return new OfficialCarCommand(key, function, 0, encoded, null, target);
    }

    static boolean matches(Object actual, Object target) {
        return actual instanceof Number && target instanceof Number
                ? Math.abs(((Number) actual).doubleValue() - ((Number) target).doubleValue()) < 0.01
                : target != null && target.equals(actual);
    }

    private static boolean finite(double value) { return !Double.isNaN(value) && !Double.isInfinite(value); }
}
