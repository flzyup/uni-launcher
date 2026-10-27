package xyz.i4o.uni.launcher.integration;

import android.content.*;
import android.os.*;
import org.json.JSONArray;
import org.json.JSONObject;
import java.io.*;
import java.net.*;
import java.nio.charset.StandardCharsets;
import java.util.Calendar;
import java.util.Iterator;
import java.util.concurrent.*;
import java.util.regex.*;

/** Read-only XCHome V2023-08-03 callback contract, verified from installed APK.
 * Current conditions always remain OEM values. The optional public forecast is
 * stored in separate fields and never writes to or impersonates the OEM source. */
public final class OfficialWeatherAdapter {
    private static final String SERVICE="ecarx.home.IWeatherCallback", CALLBACK="ecarx.home.IWeatherInfo";
    private static final String[] CONDITIONS={"晴","多云","阴","阵雨","雷阵雨","雷阵雨伴冰雹","雨夹雪","小雨","中雨","大雨","暴雨","大暴雨","特大暴雨","阵雪","小雪","中雪","大雪","暴雪","雾","冻雨","沙尘暴","小到中雨","中到大雨","大到暴雨","暴雨到大暴雨","大暴雨到特大暴雨","小到中雪","中到大雪","大到暴雪","浮尘","扬沙","强沙尘暴"};
    private final Context context;
    private final Runnable changed;
    private final Handler main=new Handler(Looper.getMainLooper());
    private boolean bound,connected;
    private String reason="等待原车天气服务";
    private JSONObject data=new JSONObject();
    private JSONObject forecast=new JSONObject();
    private final ExecutorService forecastWorker=Executors.newSingleThreadExecutor();
    private String forecastCity="",forecastReason="";
    private boolean forecastLoading;
    private long forecastAttemptMs;
    private final Runnable retryForecast=()->requestForecast(data.optString("city",""),data.optString("region",""),false);
    private final Binder callback=new Binder(){
        @Override protected boolean onTransact(int code,Parcel in,Parcel out,int flags)throws RemoteException{
            if(code==INTERFACE_TRANSACTION){if(out!=null)out.writeString(CALLBACK);return true;}
            if(code==1){
                in.enforceInterface(CALLBACK);final String raw=in.readString();
                if(raw!=null&&raw.length()<=8192)main.post(()->receive(raw));
                if(out!=null)out.writeNoException();return true;
            }return super.onTransact(code,in,out,flags);
        }
    };
    private final ServiceConnection connection=new ServiceConnection(){
        public void onServiceConnected(ComponentName name,IBinder service){
            Parcel in=Parcel.obtain(),out=Parcel.obtain();
            try{
                if(!SERVICE.equals(service.getInterfaceDescriptor()))throw new IllegalStateException("Weather service identity mismatch");
                in.writeInterfaceToken(SERVICE);in.writeStrongBinder(callback);
                if(!service.transact(1,in,out,0))throw new IllegalStateException("Weather callback unsupported");
                out.readException();connected=out.readInt()!=0;
                reason=connected?"等待原车天气回调":"原车天气注册未完成";
            }catch(Exception e){connected=false;reason="原车天气连接暂不可用";android.util.Log.w("UniWeather","Unable to register OEM weather callback",e);}
            finally{in.recycle();out.recycle();}
            changed.run();
        }
        public void onServiceDisconnected(ComponentName name){connected=false;reason="原车天气服务已断开";changed.run();}
    };
    public OfficialWeatherAdapter(Context context,Runnable changed){this.context=context;this.changed=changed;}
    public void start(){
        if(bound)return;
        try{
            context.getPackageManager().getApplicationInfo("com.ecarx.smartcloud",0);
            Intent intent=new Intent("ecarx.intent.action.smartcloud.core.service")
                .setComponent(new ComponentName("com.ecarx.smartcloud","ecarx.home.service.CoreService"));
            bound=context.bindService(intent,connection,Context.BIND_AUTO_CREATE);
            if(!bound)reason="原车天气服务未就绪";
        }catch(Exception e){reason="此设备未提供原车天气服务";}
    }
    private void receive(String raw){
        try{
            JSONObject packet=new JSONObject(raw);String temp=packet.optString("temprature","").replace('−','-').trim();
            Matcher match=Pattern.compile("^[+-]?[0-9]+(?:\\.[0-9]+)?").matcher(temp);
            String city=packet.optString("city",""),area=packet.optString("area",""),code=packet.optString("code","");
            if(!match.find()||(city.isEmpty()&&area.isEmpty())||code.isEmpty()){reason="原车天气暂未返回当前城市数据";changed.run();return;}
            double degrees=Double.parseDouble(match.group());
            if(degrees< -90||degrees>70||city.length()>80||area.length()>80||code.length()>8)return;
            int numeric=-1;try{numeric=Integer.parseInt(code);}catch(NumberFormatException ignored){}
            String description=numeric>=0&&numeric<CONDITIONS.length?CONDITIONS[numeric]:numeric==53?"霾":"未知";
            data=new JSONObject().put("available",true).put("city",area.isEmpty()?city:area).put("region",city)
                .put("temperature",degrees==Math.rint(degrees)?(Object)(int)degrees:degrees)
                .put("code",code).put("condition",description).put("description",description)
                .put("source","原车天气").put("sourcePackage","com.ecarx.smartcloud")
                .put("syncedAtMs",System.currentTimeMillis());
            reason="";changed.run();requestForecast(area.isEmpty()?city:area,city,false);
        }catch(Exception e){reason="原车天气数据格式暂不支持";changed.run();}
    }
    public void refreshForecast(){
        String city=data.optString("city","");
        if(city.isEmpty()){forecastReason="等待原车返回当前城市";changed.run();return;}
        requestForecast(city,data.optString("region",""),true);
    }
    private void requestForecast(String city,String region,boolean force){
        long now=System.currentTimeMillis();
        if(city==null||city.trim().isEmpty())return;
        city=city.trim();
        final String requestedCity=city+"|"+region;
        if(forecastLoading&&requestedCity.equals(forecastCity))return;
        boolean sameCity=requestedCity.equals(forecastCity);
        long interval=forecast.optJSONArray("forecasts")==null?60_000L:30*60*1000L;
        if(!force&&sameCity&&now-forecastAttemptMs<interval)return;
        if(!sameCity)forecast=new JSONObject();
        main.removeCallbacks(retryForecast);
        forecastCity=requestedCity;forecastAttemptMs=now;forecastLoading=true;forecastReason="正在获取未来天气";changed.run();
        final String area=city,requestedRegion=region;
        forecastWorker.execute(()->{
            try{
                JSONObject next=downloadForecast(area,requestedRegion);
                main.post(()->{
                    if(!requestedCity.equals(forecastCity))return;
                    forecast=next;forecastLoading=false;forecastReason="";changed.run();
                });
            }catch(Exception e){
                android.util.Log.w("UniWeather","Unable to load forecast for "+requestedCity,e);
                main.post(()->{
                    if(!requestedCity.equals(forecastCity))return;
                    forecastLoading=false;
                    forecastReason=forecast.optJSONArray("forecasts")!=null
                        ?"未来天气更新失败，正在显示上次数据"
                        :e instanceof WeatherLocationResolver.NotFound?"未找到当前地区的预报位置"
                        :e instanceof SocketTimeoutException?"天气服务响应超时，请稍后刷新"
                        :e instanceof UnknownHostException?"无法连接天气服务，请检查网络"
                        :"未来天气加载失败，请稍后刷新";
                    main.postDelayed(retryForecast,60_000);
                    changed.run();
                });
            }
        });
    }
    private static java.util.List<WeatherLocationResolver.Place> searchPlaces(String query)throws Exception{
        String name=URLEncoder.encode(query,StandardCharsets.UTF_8.name());
        JSONObject places=readJson("https://geocoding-api.open-meteo.com/v1/search?name="+name+"&count=20&language=zh&format=json&countryCode=CN");
        JSONArray results=places.optJSONArray("results");
        java.util.List<WeatherLocationResolver.Place> list=new java.util.ArrayList<>();
        if(results!=null)for(int i=0;i<results.length();i++){
            JSONObject p=results.getJSONObject(i);
            list.add(new WeatherLocationResolver.Place(p.optString("name"),p.optString("country_code"),p.optString("admin1"),p.optString("admin2"),p.optString("admin3"),p.optString("feature_code"),p.optDouble("latitude",Double.NaN),p.optDouble("longitude",Double.NaN),p.optLong("population",0)));
        }return list;
    }
    private static String romanize(String text){
        try{
            Class<?> type=Class.forName("android.icu.text.Transliterator");
            Object transliterator=type.getMethod("getInstance",String.class).invoke(null,"Han-Latin; Latin-ASCII");
            return (String)type.getMethod("transliterate",String.class).invoke(transliterator,text);
        }catch(Exception|LinkageError e){return text;}
    }
    private static JSONObject downloadForecast(String city,String region)throws Exception{
        WeatherLocationResolver.Location location=WeatherLocationResolver.resolve(city,region,OfficialWeatherAdapter::searchPlaces,OfficialWeatherAdapter::romanize);
        double latitude=location.place.latitude,longitude=location.place.longitude;
        String url="https://api.open-meteo.com/v1/forecast?latitude="+latitude+"&longitude="+longitude
            +"&current=relative_humidity_2m,apparent_temperature,wind_speed_10m,wind_direction_10m"
            +"&daily=weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max,wind_speed_10m_max"
            +"&timezone=auto&forecast_days=7";
        JSONObject response=readJson(url),current=response.optJSONObject("current"),daily=response.optJSONObject("daily");
        if(daily==null)throw new IOException("Forecast missing daily values");
        JSONArray dates=daily.optJSONArray("time"),codes=daily.optJSONArray("weather_code"),maximum=daily.optJSONArray("temperature_2m_max"),minimum=daily.optJSONArray("temperature_2m_min"),precipitation=daily.optJSONArray("precipitation_probability_max"),wind=daily.optJSONArray("wind_speed_10m_max");
        if(dates==null||codes==null||maximum==null||minimum==null)throw new IOException("Forecast arrays incomplete");
        JSONArray days=new JSONArray();int count=Math.min(7,dates.length());
        for(int i=0;i<count;i++){
            JSONObject day=new JSONObject().put("date",dates.optString(i,"")).put("wmoCode",codes.optInt(i,-1));
            putNumber(day,"maximum",maximum,i);putNumber(day,"minimum",minimum,i);
            putNumber(day,"precipitation",precipitation,i);putNumber(day,"windSpeed",wind,i);days.put(day);
        }
        JSONObject value=new JSONObject().put("forecasts",days).put("forecastSource","Open-Meteo")
            .put("forecastUpdatedAtMs",System.currentTimeMillis()).put("forecastLatitude",latitude).put("forecastLongitude",longitude)
            .put("forecastLocation",location.label).put("forecastCityFallback",location.cityFallback);
        if(current!=null){
            putNumber(value,"humidity",current,"relative_humidity_2m");
            putNumber(value,"apparentTemperature",current,"apparent_temperature");
            putNumber(value,"windSpeed",current,"wind_speed_10m");
            putNumber(value,"windDirection",current,"wind_direction_10m");
        }
        return value;
    }
    private static void putNumber(JSONObject target,String key,JSONArray values,int index)throws Exception{
        if(values!=null&&index<values.length()&&!values.isNull(index))target.put(key,values.getDouble(index));
    }
    private static void putNumber(JSONObject target,String key,JSONObject values,String source)throws Exception{
        if(values.has(source)&&!values.isNull(source))target.put(key,values.getDouble(source));
    }
    private static JSONObject readJson(String url)throws Exception{
        HttpURLConnection connection=(HttpURLConnection)new URL(url).openConnection();
        connection.setConnectTimeout(7000);connection.setReadTimeout(9000);connection.setUseCaches(false);
        connection.setRequestProperty("Accept","application/json");connection.setRequestProperty("User-Agent","UNI-Launcher/0.6");
        try{
            int status=connection.getResponseCode();if(status<200||status>=300)throw new IOException("HTTP "+status);
            try(InputStream input=connection.getInputStream();ByteArrayOutputStream output=new ByteArrayOutputStream()){
                byte[] buffer=new byte[8192];int read,total=0;
                while((read=input.read(buffer))!=-1){total+=read;if(total>512*1024)throw new IOException("Weather response too large");output.write(buffer,0,read);}
                return new JSONObject(output.toString(StandardCharsets.UTF_8.name()));
            }
        }finally{connection.disconnect();}
    }
    public JSONObject snapshot(){
        try{
            Calendar time=Calendar.getInstance();int minute=time.get(Calendar.HOUR_OF_DAY)*60+time.get(Calendar.MINUTE);
            JSONObject value=new JSONObject(data.toString());
            Iterator<String> keys=forecast.keys();while(keys.hasNext()){String key=keys.next();value.put(key,forecast.get(key));}
            return value.put("connected",connected).put("reason",reason).put("forecastReason",forecastReason)
                .put("forecastLoading",forecastLoading)
                .put("night",minute<360||minute>1080).put("available",data.optBoolean("available",false));
        }catch(Exception e){return new JSONObject();}
    }
}
