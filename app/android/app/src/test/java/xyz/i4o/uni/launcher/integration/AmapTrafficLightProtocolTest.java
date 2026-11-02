package xyz.i4o.uni.launcher.integration;

import org.json.JSONArray;
import org.json.JSONObject;
import org.junit.Test;
import static org.junit.Assert.*;

public class AmapTrafficLightProtocolTest {
    private JSONObject standard()throws Exception{
        return new JSONObject().put("KEY_TYPE",60073).put("dir",8).put("trafficLightStatus",2).put("redLightCountDownSeconds",60);
    }
    @Test public void standardRetainsRawEnumsAndDoesNotGuess()throws Exception{
        JSONObject item=AmapTrafficLightProtocol.standard(standard().put("greenLightLastSecond",28)).getJSONObject(0);
        assertEquals(8,item.getInt("rawDirection"));assertEquals(2,item.getInt("rawStatus"));
        assertEquals("unknown",item.getString("direction"));assertEquals("unknown",item.getString("lamp"));
        assertEquals(60,item.getInt("countdownSeconds"));assertEquals(28,item.getInt("rawGreenLightLastSecond"));
    }
    @Test public void noLightCountOrUnrelatedDataCanBecomeCountdown()throws Exception{
        assertNull(AmapTrafficLightProtocol.standard(new JSONObject().put("KEY_TYPE",10001).put("TRAFFIC_LIGHT_NUM",10)));
        assertNull(AmapTrafficLightProtocol.standard(standard().put("KEY_TYPE","60073")));
        assertNull(AmapTrafficLightProtocol.standard(standard().put("dir",true)));
        assertNull(AmapTrafficLightProtocol.standard(standard().put("trafficLightStatus",1.5)));
        for(Object invalid:new Object[]{-1,1000,"60",true,JSONObject.NULL}){
            assertTrue(AmapTrafficLightProtocol.standard(standard().put("redLightCountDownSeconds",invalid)).getJSONObject(0).isNull("countdownSeconds"));
        }
    }
    @Test public void cruiseIsAtomicAndEmptyBatchClears()throws Exception{
        String raw="{\"ts\":0,\"lights\":[{\"direction\":1,\"status\":2,\"countdown\":60},{\"direction\":8,\"status\":4,\"countdown\":24}]}";
        JSONArray items=AmapTrafficLightProtocol.cruise(raw);
        assertEquals(2,items.length());assertEquals(24,items.getJSONObject(1).getInt("countdownSeconds"));
        assertEquals("green",items.getJSONObject(0).getString("lamp"));
        assertTrue(items.getJSONObject(0).getBoolean("lampVerified"));
        assertEquals(0,AmapTrafficLightProtocol.cruise("{\"lights\":[]}").length());
        assertNull(AmapTrafficLightProtocol.cruise("{\"lights\":[{\"direction\":1,\"status\":2},{}]}"));
        assertNull(AmapTrafficLightProtocol.cruise("{\"lights\":\"bad\"}"));
        assertNull(AmapTrafficLightProtocol.cruise("broken"));
        JSONArray large=new JSONArray();for(int i=0;i<17;i++)large.put(new JSONObject().put("direction",8).put("status",2));
        assertNull(AmapTrafficLightProtocol.cruise(new JSONObject().put("lights",large).toString()));
        assertNull(AmapTrafficLightProtocol.cruise(new String(new char[16385]).replace('\0','x')));
    }
    @Test public void yhUsesItsOwnVerifiedDirectionAndLampTables()throws Exception{
        JSONArray lights=AmapTrafficLightProtocol.cruise("{\"lights\":[{\"direction\":1,\"status\":0,\"countdown\":60},{\"direction\":2,\"status\":1,\"countdown\":24},{\"direction\":3,\"status\":2,\"countdown\":5},{\"direction\":99,\"status\":99}]}" );
        assertEquals("left",lights.getJSONObject(0).getString("direction"));
        assertEquals("red",lights.getJSONObject(0).getString("lamp"));
        assertEquals("straight",lights.getJSONObject(1).getString("direction"));
        assertEquals("green",lights.getJSONObject(1).getString("lamp"));
        assertEquals("right",lights.getJSONObject(2).getString("direction"));
        assertEquals("green",lights.getJSONObject(2).getString("lamp"));
        assertTrue(lights.getJSONObject(2).getBoolean("lampVerified"));
        assertFalse(lights.getJSONObject(3).getBoolean("directionVerified"));
        assertEquals(4,lights.length());
    }
}
