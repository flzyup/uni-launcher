package xyz.i4o.uni.launcher.core;

/** Vehicle and media simulation are independent in high-fidelity mode. */
public enum SimulationMode {
    LIVE("live",false,false,false),
    DEMO("demo",true,true,false),
    HIGH_FIDELITY("highFidelity",true,false,true);
    public final String key;
    public final boolean vehicleDemo,mediaDemo,mockLocation;
    SimulationMode(String key,boolean vehicleDemo,boolean mediaDemo,boolean mockLocation){
        this.key=key;this.vehicleDemo=vehicleDemo;this.mediaDemo=mediaDemo;this.mockLocation=mockLocation;
    }
    public static SimulationMode resolve(String key,boolean legacyDemo,boolean emulator){
        if(HIGH_FIDELITY.key.equals(key))return emulator?HIGH_FIDELITY:LIVE;
        if(DEMO.key.equals(key))return DEMO;
        if(LIVE.key.equals(key))return LIVE;
        return legacyDemo?DEMO:LIVE;
    }
}
