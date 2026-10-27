package xyz.i4o.uni.launcher.integration;

import org.json.JSONArray;
import org.json.JSONObject;

/** Local 9.5 APK contracts, not a guessed SDK enum table. No Android dependencies. */
public final class AmapTrafficLightProtocol {
    public static final String STANDARD="AUTONAVI_STANDARD_BROADCAST_SEND";
    public static final String CRUISE="NAVITOOL_CRUISE_TRAFFIC_LIGHTS";
    public static final String MODIFIED_PACKAGE="com.autonavi.amapautp.yh";
    public static final int MAX_LIGHTS=16,MAX_JSON_LENGTH=16384;
    private AmapTrafficLightProtocol(){}

    /** null means unrelated/malformed; an empty array is an explicit clear. */
    public static JSONArray standard(JSONObject extras){
        if(!Integer.valueOf(60073).equals(integer(extras.opt("KEY_TYPE"))))return null;
        Integer direction=integer(extras.opt("dir")),status=integer(extras.opt("trafficLightStatus"));
        if(direction==null||status==null)return null;
        JSONArray result=new JSONArray();
        result.put(light(direction,status,seconds(extras.opt("redLightCountDownSeconds")),
            integer(extras.opt("waitRound")),null));
        // greenLightLastSecond has an unverified meaning and a channel gate.
        // Preserve it for diagnosis; never turn it into a green countdown.
        try{Integer green=integer(extras.opt("greenLightLastSecond"));if(green!=null)result.getJSONObject(0).put("rawGreenLightLastSecond",green);}catch(Exception ignored){}
        return result;
    }

    public static JSONArray cruise(String raw){
        if(raw==null||raw.length()>MAX_JSON_LENGTH)return null;
        try{
            JSONObject data=new JSONObject(raw);JSONArray input=data.optJSONArray("lights");
            if(input==null||input.length()>MAX_LIGHTS)return null;
            JSONArray result=new JSONArray();
            for(int i=0;i<input.length();i++){
                JSONObject item=input.optJSONObject(i);if(item==null)return null;
                Integer direction=integer(item.opt("direction")),status=integer(item.opt("status"));
                if(direction==null||status==null)return null; // Reject the batch, never keep half of it.
                JSONObject signal=light(direction,status,seconds(item.opt("countdown")),
                    integer(item.opt("waitNum")),integer(item.opt("showType")));
                // Verified in this yh APK: CameraLightInfo b/c ->
                // ElecticCameraInfo direction/type -> FloatViewUtils arrays.
                // TYPE_DIRECTIONS=[0,left_night,straight_night,right_night].
                String dir=direction==1?"left":direction==2?"straight":direction==3?"right":"unknown";
                // TYPE_BGS[0]=red_night, [1]=green_night. Index 2 also
                // uses green in that floating UI, but its meaning is not
                // established; do not promote it to a green signal here.
                String lamp=status==0?"red":status==1?"green":"unknown";
                signal.put("direction",dir).put("lamp",lamp)
                    .put("directionVerified",!"unknown".equals(dir))
                    .put("lampVerified",!"unknown".equals(lamp));
                result.put(signal);
            }
            return result;
        }catch(Exception ignored){return null;}
    }

    private static JSONObject light(int direction,int status,Integer seconds,Integer wait,Integer show){
        JSONObject result=new JSONObject();try{
            result.put("rawDirection",direction).put("rawStatus",status)
                .put("direction","unknown").put("lamp","unknown")
                .put("countdownSeconds",seconds==null?JSONObject.NULL:seconds);
            if(wait!=null)result.put("rawWait",wait);
            if(show!=null)result.put("rawShowType",show);
        }catch(Exception ignored){}return result;
    }

    private static Integer seconds(Object value){Integer n=integer(value);return n!=null&&n>=0&&n<=999?n:null;}
    private static Integer integer(Object value){
        // Bundle/JSON numeric types only: never accept strings, booleans or fractions.
        if(!(value instanceof Number))return null;
        double n=((Number)value).doubleValue();
        if(Double.isNaN(n)||Double.isInfinite(n)||n<Integer.MIN_VALUE||n>Integer.MAX_VALUE||n!=Math.rint(n))return null;
        return (int)n;
    }
}
