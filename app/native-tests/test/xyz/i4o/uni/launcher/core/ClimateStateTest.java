package xyz.i4o.uni.launcher.core;

public final class ClimateStateTest {
    private static int checks;
    private static void check(boolean b,String message){checks++;if(!b)throw new AssertionError(message);}
    private static String climateValues(ClimateState c) {
        return c.left + "/" + c.right + "/" + c.fan + "/" + c.power + "/" + c.auto
            + "/" + c.ac + "/" + c.sync + "/" + c.recirc;
    }
    private static String snapshot(ClimateState c) {
        return climateValues(c) + "/" + c.driverHeat + "/" + c.driverVent + "/" + c.passengerHeat;
    }
    private static void seats(ClimateState c, int heat, int vent, int passenger, String message) {
        check(c.driverHeat == heat && c.driverVent == vent && c.passengerHeat == passenger, message);
    }
    private static void reject(ClimateState c, String action, String zone, String value) {
        String before = snapshot(c);
        String message = action + "/" + zone + "/" + value;
        check(!c.apply(action, zone, value), "reject " + message);
        check(before.equals(snapshot(c)), "rejection preserves all state: " + message);
    }
    private static void seatPolicy() {
        check(CommandPolicy.isClimateAction("seat-heat"), "route seat heat through shared command boundary");
        check(CommandPolicy.isClimateAction("seat-vent"), "route seat vent through shared command boundary");
        check(CommandPolicy.isSeatAction("seat-heat") && CommandPolicy.isSeatAction("seat-vent"), "identify seat actions separately");
        check("driverHeat".equals(CommandPolicy.seatControl("seat-heat", "left")), "driver heat capability");
        check("driverVent".equals(CommandPolicy.seatControl("seat-vent", "left")), "driver vent capability");
        check("passengerHeat".equals(CommandPolicy.seatControl("seat-heat", "right")), "passenger heat capability");
        check(CommandPolicy.seatControl("seat-vent", "right") == null, "no passenger vent capability");
        for (String action : new String[]{"temp-up", "temp-down", "fan-up", "fan-down", "climate-power", "climate-mode"}) {
            check(CommandPolicy.isClimateAction(action), "preserve climate routing: " + action);
            check(!CommandPolicy.isSeatAction(action), "climate action is not seat authorization: " + action);
            check(CommandPolicy.seatControl(action, "left") == null, "climate action has no seat capability: " + action);
        }
    }
    private static void seatLevels() {
        seats(new ClimateState(), 0, 0, 0, "seats initially off");
        for (int level = 0; level <= 3; level++) {
            String value = Integer.toString(level);
            check(CommandPolicy.validSeatLevel(value), "accept seat level " + value);
            ClimateState c = new ClimateState();
            c.apply("seat-vent", "left", "3");
            c.apply("seat-heat", "right", "2");
            String hvac = climateValues(c);
            check(c.apply("seat-heat", "left", value), "set driver heat " + value);
            seats(c, level, level == 0 ? 3 : 0, 2, "positive heat disables vent; zero preserves vent");
            String before = snapshot(c);
            check(c.apply("seat-heat", "left", value), "repeat driver heat");
            check(before.equals(snapshot(c)), "driver heat is an explicit idempotent setting");
            check(c.apply("seat-vent", "left", value), "set driver vent " + value);
            seats(c, 0, level, 2, "positive vent disables heat");
            before = snapshot(c);
            check(c.apply("seat-vent", "left", value), "repeat driver vent");
            check(before.equals(snapshot(c)), "driver vent is an explicit idempotent setting");
            check(c.apply("seat-heat", "right", value), "set passenger heat " + value);
            seats(c, 0, level, level, "passenger heat leaves driver vent unchanged");
            before = snapshot(c);
            check(c.apply("seat-heat", "right", value), "repeat passenger heat");
            check(before.equals(snapshot(c)), "passenger heat is an explicit idempotent setting");
            check(hvac.equals(climateValues(c)), "seat controls leave all HVAC fields unchanged");
        }
    }
    private static void seatIndependence() {
        ClimateState c = new ClimateState();
        c.apply("seat-heat", "left", "2");
        c.apply("seat-heat", "right", "3");
        check(c.apply("seat-vent", "left", "0"), "disable inactive vent");
        seats(c, 2, 0, 3, "zero vent leaves driver and passenger heat active");
        c.apply("climate-mode", "", "sync");
        c.apply("temp-up", "right", "");
        c.apply("fan-down", "", "");
        c.apply("climate-power", "", "");
        for (String mode : new String[]{"auto", "ac", "recirc"}) c.apply("climate-mode", "", mode);
        seats(c, 2, 0, 3, "HVAC sync, power, modes, temperature and fan preserve seat settings");
        String hvac = climateValues(c);
        c.apply("seat-heat", "right", "0");
        seats(c, 2, 0, 0, "passenger off leaves driver heat active even with sync");
        c.apply("seat-heat", "left", "0");
        seats(c, 0, 0, 0, "zero heat turns off driver heat");
        c.apply("seat-vent", "left", "1");
        c.apply("seat-heat", "right", "2");
        seats(c, 0, 1, 2, "passenger heat coexists with driver vent under HVAC sync");
        c.apply("seat-vent", "left", "0");
        seats(c, 0, 0, 2, "zero vent turns off driver vent only");
        c.apply("seat-heat", "left", "1");
        seats(c, 1, 0, 2, "driver heat does not synchronize passenger heat");
        check(hvac.equals(climateValues(c)), "seat settings do not change HVAC even while powered off");
    }
    private static void invalidSeatCommands() {
        ClimateState c = new ClimateState();
        c.apply("seat-heat", "left", "2");
        c.apply("seat-heat", "right", "3");
        c.apply("climate-mode", "", "sync");
        c.apply("climate-power", "", "");
        String[] actions = {"seat-heat", "seat-heat", "seat-vent"};
        String[] zones = {"left", "right", "left"};
        for (String value : new String[]{null, "", "-1", "4", "999999999999999999999", "1.0", "1e0",
                "01", "+1", " 1", "1 ", "1\n", "\u0661", "\uff13", "true", "toggle", "NaN"}) {
            check(!CommandPolicy.validSeatLevel(value), "reject noncanonical seat level " + value);
            for (int i = 0; i < actions.length; i++) reject(c, actions[i], zones[i], value);
        }
        for (String zone : new String[]{null, "", "rear", "Left", "driver", "passenger", "left ", "both"}) {
            for (String action : new String[]{"seat-heat", "seat-vent"}) {
                check(CommandPolicy.seatControl(action, zone) == null, "no capability for invalid zone");
                reject(c, action, zone, "0");
                reject(c, action, zone, "3");
            }
        }
        for (int level = 0; level <= 3; level++) reject(c, "seat-vent", "right", Integer.toString(level));
        for (String action : new String[]{null, "", "seat-toggle", "seat-heat-up", "seat-vent-down", "SEAT-HEAT", "write-property"}) {
            check(!CommandPolicy.isClimateAction(action), "unknown action is not routed");
            check(!CommandPolicy.isSeatAction(action), "unknown action is not a seat action");
            check(CommandPolicy.seatControl(action, "left") == null, "unknown action has no seat capability");
            reject(c, action, "left", "3");
        }
        // Repeat with ventilation active to detect a premature interlock mutation on rejected heat.
        c.apply("seat-vent", "left", "3");
        reject(c, "seat-heat", "left", "4");
        reject(c, "seat-heat", "rear", "1");
    }
    public static void main(String[] args){
        ClimateState c=new ClimateState();
        for(int i=0;i<100;i++)c.apply("temp-up","left","");
        check(c.left==30,"upper limit");check(c.right==22.5,"independent zones");
        for(int i=0;i<100;i++)c.apply("temp-down","left","");
        check(c.left==16,"lower limit");
        c.apply("climate-mode","","sync");check(c.right==16,"sync aligns right");
        c.apply("temp-up","right","");check(c.left==16.5&&c.right==16.5,"sync both directions");
        for(int i=0;i<30;i++)c.apply("fan-up","","");check(c.fan==7,"fan upper bound");
        for(int i=0;i<30;i++)c.apply("fan-down","","");check(c.fan==1,"fan lower bound");
        check(!c.apply("temp-up","rear",""),"reject unknown zone");
        check(!c.apply("climate-mode","","defrost"),"reject unverified modes");
        check(!c.apply("write-property","",""),"reject unknown command");
        check(!CommandPolicy.isClimateAction("set-can"),"no arbitrary transport");
        check(MediaSourcePolicy.select("qq",new String[]{"system","qq"},new boolean[]{true,false})==1,"explicit player wins");
        check(MediaSourcePolicy.select("missing",new String[]{"system"},new boolean[]{true})==-1,"missing chosen session never falls back");
        check(MediaSourcePolicy.select("auto",new String[]{"system","qq"},new boolean[]{false,true})==1,"auto prefers playing source");
        check(MediaSourcePolicy.select("auto",new String[]{},new boolean[]{})==-1,"empty sessions");
        check(VehicleValues.decode("left",45).doubleValue()==22.5,"temperature evidenced x2 conversion");
        check(VehicleValues.decode("left",65535)==null,"reject temperature sentinel");
        check(VehicleValues.decode("driverHeat",4)==null,"reject unknown seat status");
        check(VehicleValues.decode("pressureFrontLeft",Float.NaN)==null,"reject NaN pressure");
        check(VehicleValues.decode("pressureFrontLeft",0)==null,"zero pressure is not an invented reading");
        check(Math.abs(VehicleValues.decode("pressureFrontLeft",246).doubleValue()-2.46)<0.001,"pressure x0.01 bar conversion");
        check(VehicleValues.bool(2)==null,"unknown boolean enum stays unknown");
        check(VehicleValues.bool(1),"one maps to on");
        check(VehicleValues.flag("ac",1),"AC uses evidenced boolean encoding");
        for(int raw=0;raw<=2;raw++)check(VehicleValues.flag("sync",raw)==null,"tri-state sync is not coerced to boolean");
        seatPolicy();
        seatLevels();
        seatIndependence();
        invalidSeatCommands();
        System.out.println("ClimateState: "+checks+" checks passed");
    }
}
