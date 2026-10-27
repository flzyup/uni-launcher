package xyz.i4o.uni.launcher.integration;

import android.content.Context;
import dalvik.system.DexClassLoader;
import java.io.File;
import java.lang.reflect.Method;
import org.json.JSONArray;
import org.json.JSONObject;

/** Cached, fail-closed OEM navigation mixing control; call refresh explicitly.
 * Evidence: car-reports/20261026-066/ecarx.adapterapi.jar:
 * IAudioState.NAVI_VOICE_MIX_AUTO=1, NAVI_VOICE_MIX_DIRECTLY=2.
 * Audioimpl.setNaviVoiceMixMode is a no-op and AudioStateimpl always returns 2.
 * oem-settings/bytecode.txt AudioSupport.isNaviVoiceMixAutoMode confirms 1.
 * No duck/pause/mute semantics have been established for either value.
 */
public final class NavigationAudioAdapter {
    private static final String API="com.ecarx.xui.adaptapi.audio.audiofx.";
    private final Context context;
    private Object audio;
    private Method setter;
    private int mode=-1;
    private boolean available;
    private String reason="尚未读取";

    public NavigationAudioAdapter(Context context){this.context=context;refresh();}

    public void refresh(){
        available=false;mode=-1;audio=null;setter=null;
        try{
            Class<?> api=loadAudioClass();
            Class<?> stateApi=Class.forName(API+"IAudioState",true,api.getClassLoader());
            if(stateApi.getField("NAVI_VOICE_MIX_AUTO").getInt(null)!=1
                    ||stateApi.getField("NAVI_VOICE_MIX_DIRECTLY").getInt(null)!=2){
                reason="原车混音模式定义不兼容";return;
            }
            Object candidate=api.getMethod("create",Context.class).invoke(null,context);
            if(candidate==null){reason="原车音频服务未连接";return;}
            Method write=candidate.getClass().getMethod("setNaviVoiceMixMode",int.class);
            Object state=api.getMethod("getAudioState").invoke(candidate);
            if(state==null){reason="原车音频状态不可用";return;}
            Method read=state.getClass().getMethod("getNaviVoiceMixMode");
            if((API+"Audioimpl").equals(write.getDeclaringClass().getName())
                    ||(API+"AudioStateimpl").equals(read.getDeclaringClass().getName())){
                reason="原车混音接口为空实现；暂不支持导航播报时音乐保持原音量（不压低、不暂停）";return;
            }
            int current=((Number)stateApi.getMethod("getNaviVoiceMixMode").invoke(state)).intValue();
            if(current!=1&&current!=2){reason="原车返回未定义混音模式";return;}
            audio=candidate;setter=api.getMethod("setNaviVoiceMixMode",int.class);
            mode=current;available=true;reason="";
        }catch(ReflectiveOperationException|RuntimeException|LinkageError e){reason="原车音频接口不可用或权限不足";}
    }

    private Class<?> loadAudioClass()throws ClassNotFoundException{
        try{return Class.forName(API+"Audio");}
        catch(ClassNotFoundException missing){
            // Only immutable system framework code, never an APK or writable path.
            File jar=new File("/system/framework/ecarx.adapterapi.jar");
            if(!jar.isFile()||!jar.canRead())throw missing;
            ClassLoader loader=new DexClassLoader(jar.getPath(),context.getCodeCacheDir().getPath(),null,context.getClassLoader());
            return Class.forName(API+"Audio",true,loader);
        }
    }

    public boolean setMode(String value){
        // Reject undefined, malformed and overflowing values before any OEM access.
        if(!"1".equals(value)&&!"2".equals(value))return false;
        refresh();
        if(!available)return false;
        int requested=Integer.parseInt(value);
        try{
            setter.invoke(audio,requested);
            refresh();
            if(available&&mode==requested)return true;
            available=false;reason="原车未确认混音模式变更";return false;
        }catch(ReflectiveOperationException|RuntimeException|LinkageError e){
            available=false;mode=-1;audio=null;setter=null;reason="原车拒绝混音模式变更";return false;
        }
    }

    public JSONObject snapshot(){
        JSONObject result=new JSONObject();
        try{
            JSONArray modes=new JSONArray();
            if(available){
                modes.put(new JSONObject().put("value",1).put("label","自动混音"));
                modes.put(new JSONObject().put("value",2).put("label","直接混音"));
            }
            result.put("available",available).put("mode",mode).put("modes",modes).put("reason",reason).put("busy",false);
        }catch(org.json.JSONException ignored){}
        return result;
    }
}
