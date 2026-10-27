import android.content.Context;
import org.json.*;
import xyz.i4o.uni.launcher.integration.*;
public class SettingsProbe {
 public static void main(String[] args)throws Exception{
  android.os.Looper.prepareMainLooper();
  Class<?> thread=Class.forName("android.app.ActivityThread");
  Object at=thread.getMethod("systemMain").invoke(null);
  Context context=(Context)thread.getMethod("getSystemContext").invoke(at);
  SystemSettingsRepository repo=new SystemSettingsRepository(context);
  JSONArray entries=repo.snapshot();
  if(entries.length()==0)throw new AssertionError("no settings");
  java.util.Set<String> ids=new java.util.HashSet<>();
  for(int i=0;i<entries.length();i++){
   JSONObject e=entries.getJSONObject(i);
   if(e.getString("label").trim().isEmpty()||e.getString("source").trim().isEmpty())throw new AssertionError("empty label/source");
   if(!ids.add(e.getString("id")))throw new AssertionError("duplicate id");
   for(String key:new String[]{"label","source","package","activity","action"})e.getString(key);
  }
  String cached=repo.snapshot().toString();entries.getJSONObject(0).put("label","mutated");
  if(!cached.equals(repo.snapshot().toString()))throw new AssertionError("snapshot mutated cache");
  if(repo.open("invalid"))throw new AssertionError("unknown entry opened");
  NavigationAudioAdapter audio=new NavigationAudioAdapter(context);
  for(String invalid:new String[]{"0","3","-1","01","abc","2147483648"})if(audio.setMode(invalid))throw new AssertionError("undefined mode accepted");
  try {
  Class<?> api=Class.forName("com.ecarx.xui.adaptapi.audio.audiofx.Audio");
  Object impl=api.getMethod("create",Context.class).invoke(null,context);
  Object state=api.getMethod("getAudioState").invoke(impl);
  System.out.println("OEM_CLASS="+impl.getClass().getName()+" STATE="+state.getClass().getName());
  } catch(ClassNotFoundException missing) { System.out.println("OEM_CLASS=absent"); }
  try {
  Class<?> manager=Class.forName("android.car.media.CarAudioManager");
  for(java.lang.reflect.Method m:manager.getMethods())if(m.getName().toLowerCase().matches(".*(duck|mix|focus).*"))System.out.println("CAR_AUDIO_API="+m);
  } catch(ClassNotFoundException missing) { System.out.println("CAR_AUDIO_API=absent"); }
  System.out.println("NATIVE_TEST_PASS entries="+repo.snapshot().length());
  System.out.println(new JSONObject().put("entries",repo.snapshot()).put("navigationAudio",audio.snapshot()));
 }
}
