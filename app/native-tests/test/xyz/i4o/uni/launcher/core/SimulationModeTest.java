package xyz.i4o.uni.launcher.core;
public final class SimulationModeTest {
    private static void check(boolean value,String name){if(!value)throw new AssertionError(name);}
    public static void main(String[]args){
        SimulationMode high=SimulationMode.resolve("highFidelity",false,true);
        check(high.vehicleDemo&&!high.mediaDemo&&high.mockLocation,"hybrid routing");
        check(SimulationMode.resolve("highFidelity",true,false)==SimulationMode.LIVE,"no physical mock location");
        check(SimulationMode.resolve("",true,true)==SimulationMode.DEMO,"legacy demo retained");
        check(SimulationMode.resolve("",false,true)==SimulationMode.LIVE,"legacy explicit live retained");
        check(SimulationMode.resolve("live",true,true)==SimulationMode.LIVE,"explicit mode beats legacy");
        check(SimulationMode.DEMO.vehicleDemo&&SimulationMode.DEMO.mediaDemo&&!SimulationMode.DEMO.mockLocation,"pure demo isolation");
        check(!SimulationMode.LIVE.vehicleDemo&&!SimulationMode.LIVE.mediaDemo&&!SimulationMode.LIVE.mockLocation,"live isolation");
        System.out.println("SimulationModeTest passed");
    }
}
