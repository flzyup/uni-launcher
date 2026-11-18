package xyz.i4o.uni.launcher.integration;

import org.json.JSONObject;

/** Synthetic vehicle envelopes, never stored as a real observation. */
public final class SimulatorTelemetry {
    private SimulatorTelemetry(){}
    public static JSONObject snapshot(JSONObject climate){
        JSONObject result=new JSONObject(),fields=new JSONObject();
        try{
            long now=System.currentTimeMillis();
            String[] keys={"speed","odometer","range","maintenanceMileage","batteryPercent","fuelPercent","fuelLiters","aqi","pm25",
                "pressureFrontLeft","pressureFrontRight","pressureRearLeft","pressureRearRight",
                "doorFrontLeft","doorFrontRight","doorRearLeft","doorRearRight","tailgateOpen","hoodOpen",
                "driveMode","energyFlow","hybridSelected"};
            Object[] values={0,48620,418,7530,76,56,28,25,12,2.42,2.43,2.45,2.44,
                false,false,false,false,false,false,"HYBRID","STANDSTILL_ENGINE_OFF",true};
            String[] units={"km/h","km","km","km","%","%","L","","µg/m³","bar","bar","bar","bar","","","","","","","","",""};
            for(int i=0;i<keys.length;i++)field(fields,keys[i],values[i],units[i],now);
            java.util.Iterator<String> names=climate.keys();
            while(names.hasNext()){String key=names.next();field(fields,key,climate.get(key),"",now);}
            result.put("connected",true).put("writable",false).put("simulated",true).put("source","simulator")
                .put("reason","车辆演示数据").put("fields",fields).put("climate",climate);
        }catch(Exception ignored){}
        return result;
    }
    private static void field(JSONObject fields,String key,Object value,String unit,long now)throws Exception{
        fields.put(key,new JSONObject().put("value",value).put("valid",true).put("unit",unit).put("unitVerified",true)
            .put("updatedAtMs",now).put("source","simulator").put("simulated",true));
    }
}
