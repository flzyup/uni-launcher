package xyz.i4o.uni.launcher.core;

/** Decode only mappings evidenced in the supplied Dudu Lynk adapter. */
public final class VehicleValues {
    public static Number decode(String key,Number raw){
        if(raw==null||Double.isNaN(raw.doubleValue())||Double.isInfinite(raw.doubleValue()))return null;
        double v=raw.doubleValue();
        if("left".equals(key)||"right".equals(key))return v>=24&&v<=72?v/2.0:null;
        if("fan".equals(key))return v>=0&&v<=15&&v==Math.rint(v)?raw.intValue():null;
        if("driverHeat".equals(key)||"driverVent".equals(key)||"passengerHeat".equals(key))return v>=0&&v<=3&&v==Math.rint(v)?raw.intValue():null;
        if(key.startsWith("pressure"))return v>0&&v<=1000?v/100.0:null;
        return null;
    }
    public static Boolean bool(Number raw){return raw!=null&&(raw.doubleValue()==0||raw.doubleValue()==1)?raw.intValue()==1:null;}
    public static Boolean flag(String key,Number raw){
        // PA_CL_Sync cycles through 0/1/2 in the supplied adapter. Preserve raw
        // until this car's enum is verified instead of treating it as boolean.
        return "auto".equals(key)||"ac".equals(key)||"power".equals(key)||"recirc".equals(key)?bool(raw):null;
    }
}
