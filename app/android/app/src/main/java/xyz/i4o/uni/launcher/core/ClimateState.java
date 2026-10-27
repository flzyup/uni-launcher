package xyz.i4o.uni.launcher.core;

/** Explicit simulator state. Never treated as a vehicle observation. */
public final class ClimateState {
    public double left = 22.5, right = 22.5;
    public int fan = 3;
    public int driverHeat = 0, driverVent = 0, passengerHeat = 0;
    public boolean power = true, auto = true, ac = true, sync = false, recirc = false;
    public boolean apply(String action, String zone, String value) {
        if ("temp-up".equals(action) || "temp-down".equals(action)) {
            if (!CommandPolicy.validZone(zone)) return false;
            double next = CommandPolicy.temperature(("left".equals(zone) ? left : right) + ("temp-up".equals(action) ? .5 : -.5));
            if ("left".equals(zone)) left = next; else right = next;
            if (sync) left = right = next;
        } else if ("fan-up".equals(action) || "fan-down".equals(action)) {
            fan = CommandPolicy.fan(fan + ("fan-up".equals(action) ? 1 : -1));
        } else if ("climate-power".equals(action)) power = !power;
        else if ("climate-mode".equals(action)) {
            if (!CommandPolicy.validMode(value)) return false;
            if ("auto".equals(value)) auto = !auto;
            if ("ac".equals(value)) ac = !ac;
            if ("recirc".equals(value)) recirc = !recirc;
            if ("sync".equals(value)) { sync = !sync; if (sync) right = left; }
        } else if (CommandPolicy.isSeatAction(action)) {
            String control = CommandPolicy.seatControl(action, zone);
            if (control == null || !CommandPolicy.validSeatLevel(value)) return false;
            int level = value.charAt(0) - '0';
            // Demo rule only: local D02/D03 evidence does not establish a vehicle interlock.
            if ("driverHeat".equals(control)) {
                driverHeat = level;
                if (level > 0) driverVent = 0;
            } else if ("driverVent".equals(control)) {
                driverVent = level;
                if (level > 0) driverHeat = 0;
            } else passengerHeat = level;
        } else return false;
        return true;
    }
}
