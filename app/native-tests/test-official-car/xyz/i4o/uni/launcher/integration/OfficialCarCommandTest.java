package xyz.i4o.uni.launcher.integration;

/** Offline command encoding regression tests; no Android/SDK/Binder involved. */
public final class OfficialCarCommandTest {
    private static void check(boolean ok, String name) { if (!ok) throw new AssertionError(name); }
    private static OfficialCarCommand plan(String action, String zone, String mode, Object current) {
        return OfficialCarCommand.plan(action, zone, mode, current, 1, 16, 31, 0.5);
    }
    public static void main(String[] args) {
        OfficialCarCommand command = plan("temp-up", "left", "", 22.5);
        check(command.function == 0x10060100 && command.zone == 1 && command.temperature == 23f, "left temperature float");
        check(plan("temp-down", "right", "", 22.5).zone == 4, "right physical zone");
        check(plan("temp-up", "left", "", 31).temperature == 31f, "temperature upper bound");
        check(plan("temp-down", "left", "", 16).temperature == 16f, "temperature lower bound");
        check(OfficialCarCommand.plan("temp-up", "left", "", 22.5, 1, 16, 30, 0.5) == null, "reject different framework range");
        check(plan("fan-up", "", "", 2).intValue == 0x10020103, "SDK fan value is encoded");
        check(plan("fan-down", "", "", 1).intValue == 0, "fan OFF");
        check(plan("fan-up", "", "", 7).intValue == 0x10020107, "fan cap 7");
        check(plan("fan-up", "", "", "auto") == null, "AUTO has no manual increment source");
        check(plan("fan-up", "", "", 8) == null, "never write advertised-but-unmapped AUTO");
        check(plan("climate-power", "", "", false).intValue == 1, "power ON");
        OfficialCarCommand restoreLeft = OfficialCarCommand.restore("left", 22.5, 1);
        check(restoreLeft.function == 0x10060100 && restoreLeft.zone == 1
                && restoreLeft.temperature == 22.5f, "restore left temperature");
        check(OfficialCarCommand.restore("fan", 3, 1).intValue == 0x10020103,
                "restore encoded fan level");
        check(OfficialCarCommand.restore("recirc", true, 1).intValue == 0x10030101,
                "restore inner circulation");
        check(OfficialCarCommand.restore("power", true, 1) == null,
                "power itself is not part of the saved profile");
        check(plan("climate-mode", "", "auto", true).function == 0x10010200, "auto function");
        check(plan("climate-mode", "", "ac", true).intValue == 0, "AC OFF");
        check(plan("climate-mode", "", "sync", false).function == 0x10060500, "sync function");
        check(plan("climate-mode", "", "recirc", false).intValue == 0x10030101, "inner enum");
        check(plan("climate-mode", "", "recirc", true).intValue == 0x10030102, "outside enum");
        check(plan("climate-power", "", "", 2) == null, "unknown power never coerces to false");
        check(plan("seat-heat", "left", "2", 0).intValue == 0x10050202, "driver heat SDK enum");
        check(plan("seat-heat", "right", "3", 0).zone == 4, "passenger heat zone");
        check(plan("seat-vent", "left", "3", 0).intValue == 0x10050103, "driver vent SDK enum");
        check(plan("seat-vent", "left", "0", 3).intValue == 0, "seat OFF");
        check(plan("seat-vent", "right", "1", 0) == null, "no passenger vent contract");
        check(plan("seat-heat", "left", "4", 0) == null, "seat range");
        check(plan("seat-heat", "left", "01", 0) == null, "strict seat input");
        check(OfficialCarCommand.plan("seat-heat", "left", "1", 0, 4, 16, 31, 0.5).zone == 4, "right hand driver");
        check(OfficialCarCommand.plan("seat-heat", "left", "1", 0, 0, 16, 31, 0.5) == null, "unknown driver side");
        check(plan("temp-up", "bad", "", 22.5) == null, "invalid temperature zone");
        check(plan("climate-mode", "", "bad", false) == null, "invalid mode");
        check(plan("pressure-set", "left", "1", 0) == null, "no tyre writes");
        check(OfficialCarCommand.matches(22.5f, 22.5d), "numeric readback");
        check(!OfficialCarCommand.matches(false, 0), "no enum/boolean conflation");
        // 记忆配置：驾驶模式与自动启停（写入函数 + 读回目标值）
        OfficialCarCommand pure = OfficialCarCommand.driveMode("PURE");
        check(pure.function == 0x22010100 && pure.zone == 0 && pure.intValue == 0x22010106
                && "PURE".equals(pure.expected), "drive mode selection");
        check(OfficialCarCommand.driveMode("INDIVIDUAL").intValue == 0x22010140, "INDIVIDUAL selection");
        check(OfficialCarCommand.driveMode("RACE").intValue == 0x22010115
                && "RACE".equals(OfficialCarCommand.driveMode("RACE").expected), "RACE maps to SPORT_PLUS");
        check(OfficialCarCommand.driveMode("SPORT_PLUS") == null, "SDK-only alias is not an input");
        check(OfficialCarCommand.driveMode("CUSTOM") == null, "SDK-only alias is not an input");
        check(OfficialCarCommand.driveMode("pure") == null, "case sensitive drive mode");
        check(OfficialCarCommand.driveMode("") == null && OfficialCarCommand.driveMode(null) == null,
                "empty drive mode");
        OfficialCarCommand on = OfficialCarCommand.startStop("on");
        check(on.function == 0x20020100 && on.zone == 0 && on.intValue == 1
                && Boolean.TRUE.equals(on.expected), "start-stop ON");
        OfficialCarCommand off = OfficialCarCommand.startStop("off");
        check(off.intValue == 0 && Boolean.FALSE.equals(off.expected), "start-stop OFF");
        check(OfficialCarCommand.startStop("1") == null && OfficialCarCommand.startStop("") == null,
                "strict start-stop input");
        check("driveMode".equals(OfficialCarCommand.key("drive-mode", "", "PURE")), "drive mode field key");
        check("startStop".equals(OfficialCarCommand.key("start-stop", "", "on")), "start-stop field key");
        check(OfficialCarCommand.isSetting("drive-mode") && OfficialCarCommand.isSetting("start-stop")
                && !OfficialCarCommand.isSetting("climate-mode"), "setting routing");
        check("RACE".equals(OfficialCarContract.driveModeNameForSelection(0x22010115)), "selection to DID name");
        check(OfficialCarContract.driveModeSelection("COMFORT_HEV") == 0x22010111, "DID name to selection");
        check(OfficialCarContract.driveModeName(7).equals("PURE"), "DID name table");
        System.out.println("OfficialCarCommandTest passed (47 offline command/encoding/readback checks)");
    }
}
