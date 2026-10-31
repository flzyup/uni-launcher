package xyz.i4o.uni.launcher;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.content.IntentFilter;
import android.content.SharedPreferences;
import android.content.res.Configuration;
import android.os.Build;
import android.os.Handler;
import android.os.Looper;
import android.widget.Toast;
import java.util.IdentityHashMap;
import java.util.Map;
import java.util.concurrent.Callable;
import java.util.concurrent.ExecutionException;
import java.util.concurrent.FutureTask;
import org.json.JSONObject;
import org.json.JSONArray;
import xyz.i4o.uni.launcher.core.ClimateState;
import xyz.i4o.uni.launcher.core.CommandPolicy;
import xyz.i4o.uni.launcher.integration.*;

/** One Application-scoped native data source for all Flutter engines.
 * Adapter access and listener delivery are serialized on Android's main thread.
 */
public final class LauncherRuntime {
    private static volatile LauncherRuntime instance;
    private static final Handler main=new Handler(Looper.getMainLooper());
    /** Upper bound of telemetry packets per second; 80ms is faster than a frame
     * budget but slow enough that a burst of source callbacks costs one rebuild. */
    private static final long PUBLISH_INTERVAL_MS=80;
    private final Context context;
    private final SharedPreferences prefs;
    private final AppRepository apps;
    private final OfficialCatalog catalog;
    private final MediaAdapter media;
    private final VehicleTelemetry vehicle;
    private final NavigationApps navigation;
    private final AmapTrafficLightAdapter trafficLights;
    private final OfficialWeatherAdapter weather;
    private final SystemStatusAdapter systemStatus;
    private final SystemCalendarAdapter calendar;
    private final SystemSettingsRepository systemSettings;
    private final NavigationAudioAdapter navigationAudio;
    private final LanTransfer transfer;
    private final ClimateState simulator=new ClimateState();
    private final Map<Object,Runnable> listeners=new IdentityHashMap<>();
    private JSONArray installed;
    private boolean homeVisible;
    private boolean desktopContent=true;
    private boolean demoPlaying=true;
    private boolean bootAutoPlayScheduled;
    /** 每个窗口的静态分组游标：图标、布局、媒体资源、设置目录各自独立，
     *  只补发发生变化的部分，不再因为一首歌或一次布局保存重发全部图标。 */
    public static final class StaticCursor {
        public int apps=-1, design=-1, media=-1, settings=-1;
    }
    private int appsRevision=0, designRevision=0, mediaRevision=0, settingsRevision=0;
    private String designFingerprint="", mediaFingerprint="";
    private final Runnable appsRefreshTask=()->refreshAppsInBackground();
    private boolean appsRefreshQueued;
    private final java.util.concurrent.atomic.AtomicInteger appsRefreshGeneration=new java.util.concurrent.atomic.AtomicInteger();
    private boolean publishScheduled;
    private long publishedAt;
    private int demoTrack;
    private long demoPositionMs,demoSampleAt=android.os.SystemClock.elapsedRealtime();
    private final BroadcastReceiver packages=new BroadcastReceiver(){
        @Override public void onReceive(Context c,Intent i){
            scheduleAppsRefresh();
            new Thread(()->{systemSettings.refresh();main.post(()->{settingsRevision++;trafficLights.navigationChanged();publish();});},"uni-packages").start();
        }
    };

    public static LauncherRuntime get(Context context){
        LauncherRuntime current=instance;
        if(current!=null)return current;
        Context application=context.getApplicationContext();
        if(application==null)throw new IllegalArgumentException("Application context required");
        return onMain(()->{
            if(instance==null)instance=new LauncherRuntime(application);
            return instance;
        });
    }

    private LauncherRuntime(Context application){
        long traceStart=android.os.SystemClock.uptimeMillis();
        context=application;
        prefs=context.getSharedPreferences("launcher",Context.MODE_PRIVATE);
        // Only initialize a brand-new install; upgrades retain explicit preferences.
        if(prefs.getAll().isEmpty())prefs.edit().putBoolean("globalDockEnabled",true).apply();
        if(!prefs.contains("demo"))prefs.edit().putBoolean("demo",Build.FINGERPRINT.contains("generic")||Build.MODEL.contains("sdk_gphone")||Build.MODEL.contains("Android SDK")).apply();
        long afterPrefs=android.os.SystemClock.uptimeMillis();
        apps=new AppRepository(context);catalog=new OfficialCatalog(context);
        long afterRepos=android.os.SystemClock.uptimeMillis();
        vehicle=new VehicleTelemetry(context,this::publish);navigation=new NavigationApps(context,prefs);
        long afterTelemetry=android.os.SystemClock.uptimeMillis();
        trafficLights=new AmapTrafficLightAdapter(context,navigation::selected,this::publish);
        media=new MediaAdapter(context,this::publish);weather=new OfficialWeatherAdapter(context,this::publish);systemStatus=new SystemStatusAdapter(context,this::publish);calendar=new SystemCalendarAdapter(context,this::publish);
        long afterAdapters=android.os.SystemClock.uptimeMillis();
        systemSettings=new SystemSettingsRepository(context);navigationAudio=new NavigationAudioAdapter(context);
        transfer=new LanTransfer(context,this::publish);
        long afterSettings=android.os.SystemClock.uptimeMillis();
        // setPreferredPackage() starts MediaAdapter; defer it until the first owner.
        // 应用列表在后台构建，第一帧不被图标扫描/压缩阻塞；完成后主线程替换并补发。
        installed=new JSONArray();
        refreshAppsInBackground();
        long afterApps=android.os.SystemClock.uptimeMillis();
        android.util.Log.i("UNI-Startup","runtime split: prefs="+(afterPrefs-traceStart)
            +" repos="+(afterRepos-afterPrefs)+" telemetry="+(afterTelemetry-afterRepos)
            +" adapters="+(afterAdapters-afterTelemetry)+" settings="+(afterSettings-afterAdapters)
            +" apps="+(afterApps-afterSettings)+" runtime="+(afterApps-traceStart));
        IntentFilter filter=new IntentFilter();
        filter.addAction(Intent.ACTION_PACKAGE_ADDED);filter.addAction(Intent.ACTION_PACKAGE_REMOVED);filter.addAction(Intent.ACTION_PACKAGE_CHANGED);filter.addDataScheme("package");
        // One Application-lifetime package receiver/cache, independent of windows.
        context.registerReceiver(packages,filter);
        // The settings catalogue and the OEM audio probe are only needed by the
        // settings panel; warm them after the first frame, then publish so the
        // catalog reaches the window without ever blocking the bootstrap snapshot.
        new android.os.Handler(android.os.Looper.getMainLooper()).postDelayed(
            ()->new Thread(()->{systemSettings.prewarm();navigationAudio.prewarm();main.post(()->{settingsRevision++;publish();});},"uni-warmup").start(),
            1500);
        android.util.Log.i("UNI-Startup","runtime ready after receiver: "
            +(android.os.SystemClock.uptimeMillis()-traceStart));
    }

    public SharedPreferences prefs(){return prefs;}

    /** 普通快照：按游标只补发变化的分组，不携带设置目录（Dock/面板用）。 */
    public JSONObject snapshot(StaticCursor cursor){return onMain(()->buildSnapshot(cursor,false));}

    /** 主窗口快照：除分组增量外，设置目录预热完成后也按游标补发一次。 */
    public JSONObject snapshotWithSettings(StaticCursor cursor){return onMain(()->buildSnapshot(cursor,true));}

    public boolean saveDesign(String raw){return onMain(()->saveDesignOnMain(raw));}

    /** true means recognized, including input rejected by the original gates. */
    public boolean handle(JSONObject request)throws Exception{return callOnMain(()->handleOnMain(request));}

    private long demoPosition(){return demoPositionMs+(demoPlaying?Math.max(0,android.os.SystemClock.elapsedRealtime()-demoSampleAt):0);}
    private JSONObject buildSnapshot(StaticCursor cursor, boolean includeSettings){
        JSONObject state=new JSONObject();try{
            JSONObject climate=new JSONObject().put("left",simulator.left).put("right",simulator.right).put("fan",simulator.fan).put("power",simulator.power)
                .put("auto",simulator.auto).put("ac",simulator.ac).put("sync",simulator.sync).put("recirc",simulator.recirc)
                .put("driverHeat",simulator.driverHeat).put("driverVent",simulator.driverVent).put("passengerHeat",simulator.passengerHeat);
            JSONObject telemetry=vehicle.snapshot();
            if(!prefs.getBoolean("demo",false))climate=telemetry.optJSONObject("climate")==null?new JSONObject():telemetry.getJSONObject("climate");
            state.put("systemStatus",systemStatus.snapshot()).put("weather",weather.snapshot()).put("calendar",calendar.snapshot()).put("navigation",navigation.snapshot()).put("integrationPreferences",new JSONObject().put("mediaPackage",prefs.getString("mediaPackage","auto")).put("mapTextureScale",prefs.getBoolean("mapTextureScale",false)).put("autoPlayMusic",prefs.getBoolean("autoPlayMusic",false)));
            state.put("demo",prefs.getBoolean("demo",false)).put("hideNavigation",prefs.getBoolean("hideNavigation",false))
                .put("globalNavigation",prefs.getBoolean("globalNavigation",false))
                .put("globalNavigationGranted",context.checkSelfPermission("android.permission.WRITE_SECURE_SETTINGS")==android.content.pm.PackageManager.PERMISSION_GRANTED)
                .put("dark",(context.getResources().getConfiguration().uiMode&Configuration.UI_MODE_NIGHT_MASK)==Configuration.UI_MODE_NIGHT_YES)
                .put("climate",climate).put("vehicle",telemetry).put("version",xyz.i4o.uni.launcher.BuildConfig.VERSION_NAME+"-flutter");
            state.put("desktopSelected",homeVisible&&desktopContent);
            state.put("trafficLights",trafficLights.snapshot());
            JSONObject mediaState=prefs.getBoolean("demo",false)?demoMedia():media.snapshot().put("preferredPackage",prefs.getString("mediaPackage","auto"));
            JSONObject appNames=storedAppNames();
            String design=prefs.getString("savedDesign","");
            trackDesign(design,appNames);
            trackMedia(mediaState);

            // 分组版本：图标、布局、媒体资源各自独立，只补发发生变化的部分。
            boolean wantApps=cursor.apps!=appsRevision;
            boolean wantDesign=cursor.design!=designRevision;
            boolean wantMedia=cursor.media!=mediaRevision;
            boolean wantSettings=includeSettings&&systemSettings.isWarmed()&&cursor.settings!=settingsRevision;

            if(wantApps)state.put("apps",installed);
            if(wantDesign){state.put("savedDesign",design).put("appNames",appNames);}
            if(!wantMedia){mediaState.remove("artwork");mediaState.remove("lyrics");}
            if(wantSettings){
                JSONArray entries=systemSettings.snapshot();
                if(entries!=null)state.put("systemSettings",new JSONObject().put("entries",entries).put("navigationAudio",navigationAudio.snapshot()));
            }
            state.put("runtimeOwnerCount",listeners.size()).put("media",mediaState)
                .put("transfer",transfer.snapshot())
                .put("partial",!(wantApps&&wantDesign&&wantMedia));

            if(wantApps)cursor.apps=appsRevision;
            if(wantDesign)cursor.design=designRevision;
            if(wantMedia)cursor.media=mediaRevision;
            if(wantSettings)cursor.settings=settingsRevision;
        }catch(Exception e){android.util.Log.e("UniState","Snapshot failed",e);}return state;
    }

    /** 布局指纹按内容计算：即使键数或字符串长度不变，内容变化也会推进 designRevision。 */
    private void trackDesign(String design,JSONObject names){
        String fingerprint=design.hashCode()+":"+names.toString().hashCode();
        if(!fingerprint.equals(designFingerprint)){designFingerprint=fingerprint;designRevision++;}
    }
    private void trackMedia(JSONObject media){
        String fingerprint=media.optString("artwork","").hashCode()+":"+media.optString("lyrics","").hashCode();
        if(!fingerprint.equals(mediaFingerprint)){mediaFingerprint=fingerprint;mediaRevision++;}
    }

    private JSONObject demoMedia(){try{
        return new JSONObject().put("available",true).put("playing",demoPlaying)
                .put("title",demoTrack%2==0?"向海而行":"山海之间").put("artist",demoTrack%2==0?"Coastline":"Northbound").put("collection","晨间驾驶歌单").put("source","simulator").put("canNext",true).put("canPrevious",true).put("canToggle",true).put("canSeek",true)
                .put("lyrics","[00:00.00]晨光沿着海岸慢慢亮起\n[00:03.00]风把远方带进了呼吸\n[00:06.00]穿过山与海的交界\n[00:09.00]每一程都有新的风景\n[00:12.00]跟着潮声向前去\n[00:15.00]让今天从容开启")
                .put("lyricsSource","demo").put("durationMs",258000).put("positionMs",demoPosition()).put("positionKnown",true)
                .put("sampledAtMs",System.currentTimeMillis()).put("speed",1);
    }catch(Exception e){android.util.Log.e("UniState","Demo media failed",e);return new JSONObject();}}
    private boolean saveDesignOnMain(String raw){
            if(raw==null||raw.length()>65536)return false;
            try{
                JSONObject data=new JSONObject(raw);JSONObject p=data.getJSONObject("preferences");
                int version=data.optInt("version");
                if((version<4||version>6)||!p.optString("custom").matches("#[0-9a-fA-F]{6}"))return false;
                String mode=p.optString("mode"),palette=p.optString("palette");
                String themeStyle=p.optString("themeStyle","classic");
                if(!"classic".equals(themeStyle)&&!"blueGlass".equals(themeStyle))return false;
                String effect=p.optString("pageTransition","none");
                if(!"none".equals(effect)&&!"fade".equals(effect)&&!"slide".equals(effect)&&!"zoom".equals(effect)&&!"depth".equals(effect))return false;
                if(!"smart".equals(mode)&&!"system".equals(mode)&&!"dark".equals(mode)&&!"light".equals(mode))return false;
                String wallpaper=p.optString("wallpaper","gradient");
                if(!"gradient".equals(wallpaper)&&!"coastal".equals(wallpaper)&&!"graphite".equals(wallpaper)&&!"dawn".equals(wallpaper)&&!"neon".equals(wallpaper)&&!"precision".equals(wallpaper)&&!"terrain".equals(wallpaper)&&!"custom".equals(wallpaper))return false;
                if(p.optString("wallpaperPath","").length()>1024)return false;
                if(p.has("wallpaperLuminance")){
                    double luminance=p.optDouble("wallpaperLuminance",Double.NaN);
                    if(Double.isNaN(luminance)||luminance<0||luminance>1)return false;
                }
                if(p.has("dockMusicProgressBackground")&&!(p.get("dockMusicProgressBackground") instanceof Boolean))return false;
                if(!"small".equals(p.optString("dockSize","medium"))&&!"medium".equals(p.optString("dockSize"))&&!"large".equals(p.optString("dockSize")))return false;
                if(!"mint".equals(palette)&&!"blue".equals(palette)&&!"violet".equals(palette)&&!"amber".equals(palette)&&!"rose".equals(palette)&&!"custom".equals(palette))return false;
                int radius=p.getInt("radius"),pages=data.getInt("pageCount");
                if(radius<0||radius>40||pages<1||pages>20)return false;
                JSONArray cards=data.getJSONArray("cards");if(cards.length()>200)return false;
                for(int i=0;i<cards.length();i++){
                    JSONObject c=cards.getJSONObject(i);int x=c.getInt("x"),y=c.getInt("y"),w=c.getInt("w"),h=c.getInt("h"),page=c.getInt("page");
                    if(x<0||y<0||w<1||h<1||x+w>12||y+h>6||page<0||page>=pages)return false;
                }
                if(version>=5&&data.has("appNames")){
                    JSONObject names=data.getJSONObject("appNames");
                    if(names.length()>300)return false;
                    java.util.Iterator<String> keys=names.keys();
                    while(keys.hasNext()){
                        String key=keys.next(),name=names.optString(key,"");
                        if(key.length()==0||key.length()>255||name.length()>96||name.indexOf('\n')>=0||name.indexOf('\r')>=0)return false;
                    }
                }
                SharedPreferences.Editor editor=prefs.edit().putString("savedDesign",raw);
                if(data.has("appNames"))editor.putString("appNames",data.getJSONObject("appNames").toString());
                // 异步写盘：内存立即生效，不阻塞主线程等待磁盘提交；布局变更由
                // trackDesign 的内容指纹在下次快照时推进 designRevision。
                editor.apply();
            }catch(Exception e){return false;}
            publish();return true;
        }
    private boolean handleOnMain(JSONObject request)throws Exception{
        String action=request.optString("action"),value=request.optString("value"),zone=request.optString("zone");
        // 车机上没有调试器，出问题时先看这一行有没有出现，就能分清「没点到」还是「动作失败」。
        if(action.startsWith("transfer-"))android.util.Log.i("UniTransfer","action "+action+(value.isEmpty()?"":" "+value));
        if("rename-app".equals(action)){
            if(zone.length()==0||zone.length()>255||zone.indexOf('\n')>=0||zone.indexOf('\r')>=0||value.length()>96||value.indexOf('\n')>=0||value.indexOf('\r')>=0)return true;
            JSONObject names=storedAppNames();
            if(value.isEmpty())names.remove(zone);else names.put(zone,value);
            prefs.edit().putString("appNames",names.toString()).apply();publish();return true;
        }
        if("desktop-page".equals(action)){
            setDesktopContent("0".equals(value));return true;
        }
        if("demo-mode".equals(action)){
            prefs.edit().putBoolean("demo",request.optBoolean("enabled",false)).apply();publish();return true;
        }
        if("select-player".equals(action)||"select-navigation".equals(action)){
            if(!"auto".equals(value)&&context.getPackageManager().getLaunchIntentForPackage(value)==null){toast("所选应用未安装或不可启动");return true;}
            String key="select-player".equals(action)?"mediaPackage":"navigationPackage";
            prefs.edit().putString(key,value).apply();
            if("select-player".equals(action)&&!listeners.isEmpty())media.setPreferredPackage(value);
            if("select-navigation".equals(action))trafficLights.navigationChanged();
            publish();return true;
        }
        if("embed-navigation".equals(action)){prefs.edit().putBoolean("embedNavigation",request.optBoolean("enabled",true)).apply();publish();return true;}
        if("map-texture-scale".equals(action)){prefs.edit().putBoolean("mapTextureScale",request.optBoolean("enabled",false)).apply();publish();return true;}
        if("auto-play-music".equals(action)){prefs.edit().putBoolean("autoPlayMusic",request.optBoolean("enabled",false)).apply();publish();return true;}
        if("refresh-system-settings".equals(action)){new Thread(()->{systemSettings.refresh();navigationAudio.refresh();main.post(()->{settingsRevision++;publish();});},"uni-settings").start();return true;}
        if("open-system-setting".equals(action)){if(!systemSettings.open(value))toast("系统设置入口不可用或权限不足");return true;}
        if("navigation-audio-mode".equals(action)){if(navigationAudio.setMode(value))settingsRevision++;else toast("导航混音模式不可用或原车未确认变更");publish();return true;}
        if("calendar-refresh".equals(action)){calendar.refresh();publish();return true;}
        if("weather-forecast-refresh".equals(action)){weather.refreshForecast();return true;}
        if("launch-navigation".equals(action)){if(!navigation.launchFullscreen())toast("请选择已安装的导航应用");return true;}
        if("launch-player".equals(action)){
            String selected=prefs.getString("mediaPackage","auto");
            if("auto".equals(selected))selected=media.snapshot().optString("source","ecarx.xsf.mediacenter");
            if(!apps.launchPackage(selected))toast("请选择已安装的音乐播放器");return true;
        }
        if("refresh".equals(action)){refreshAppsInBackground();if(!listeners.isEmpty()){media.start();vehicle.stop();vehicle.start();}publish();return true;}
        if("app-info".equals(action)){if(!apps.showInfo(value))toast("无法打开应用信息");return true;}
        if("request-uninstall".equals(action)){if(!apps.requestUninstall(value))toast("该应用不可卸载");return true;}
        if("launch-app".equals(action)){if(!apps.launch(value))toast("应用未安装或无法启动");return true;}
        if("media-access".equals(action)){try{context.startActivity(new Intent("android.settings.ACTION_NOTIFICATION_LISTENER_SETTINGS").addFlags(Intent.FLAG_ACTIVITY_NEW_TASK));}catch(Exception e){toast("系统没有提供媒体授权入口");}return true;}
        if("transfer-start".equals(action)){transfer.start();publish();return true;}
        if("transfer-stop".equals(action)){transfer.stop();publish();return true;}
        if("transfer-install".equals(action)){if(!transfer.install(value))toast("未找到可安装的文件，或系统未允许安装");publish();return true;}
        if("transfer-delete".equals(action)){transfer.delete(value);publish();return true;}
        // 手机只负责把地址交上来；下载由车机上的点击触发，避免车机被外部驱动流量。
        if("transfer-link-download".equals(action)){if(!transfer.downloadLink(value))toast("链接无效或任务已不存在");publish();return true;}
        if("transfer-link-remove".equals(action)){transfer.removeLink(value);publish();return true;}
        if("official-widget".equals(action)){
            if(catalog.providers(value).isEmpty()){toast("没有对应的原厂卡片");return true;}
            context.startActivity(new Intent(context,OfficialWidgetActivity.class).putExtra("type",value).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK));return true;
        }
        if("open-official".equals(action)){
            if("camera".equals(value)){
                if(!apps.launchOfficialCamera(vehicle.cameraCapability())){
                    toast("当前车辆未提供原车全景入口");GlobalDockService.resumeAfterCameraLaunchFailure();
                }
                return true;
            }
            if(!apps.launchPackage(catalog.packageFor(value)))toast("此设备未安装对应原车应用");return true;
        }
        if(CommandPolicy.isClimateAction(action)){
            boolean demo=prefs.getBoolean("demo",false);
            boolean ok=demo?simulator.apply(action,request.optString("zone"),value):vehicle.command(action,request.optString("zone"),value);
            if(!ok)toast("尚未连接空调，可从空调面板打开原车应用");publish();return true;
        }
        if("seek".equals(action)){
            long position;try{position=Long.parseLong(value);}catch(NumberFormatException e){return true;}
            if(position<0)return true;
            if(prefs.getBoolean("demo",false)){demoPositionMs=Math.min(258000,position);demoSampleAt=android.os.SystemClock.elapsedRealtime();}
            else if(!media.command(action,position))toast("当前音源不支持调整进度");
            publish();return true;
        }
        if("toggle-play".equals(action)||"previous".equals(action)||"next".equals(action)){
            if(prefs.getBoolean("demo",false)){if("toggle-play".equals(action)){demoPositionMs=demoPosition();demoPlaying=!demoPlaying;}
                else {demoTrack+="previous".equals(action)?-1:1;demoPositionMs=0;}
                demoSampleAt=android.os.SystemClock.elapsedRealtime();publish();return true;}
            if(media.command(action)){publish();return true;}
            // 没有媒体会话时，「播放」等于启动播放器，让主界面一键把音乐放起来。
            if("toggle-play".equals(action)){
                String selected=prefs.getString("mediaPackage","auto");
                if("auto".equals(selected))selected=media.snapshot().optString("source","ecarx.xsf.mediacenter");
                if(apps.launchPackage(selected)){publish();return true;}
                toast("请选择已安装的音乐播放器");
            }else toast("当前音源不支持此操作，或尚未授权媒体访问");
            publish();return true;
        }
        return false;
    }

    public void addListener(Object owner,Runnable listener){
        if(owner==null||listener==null)throw new IllegalArgumentException("Owner and listener required");
        onMain(()->{
            boolean first=listeners.isEmpty();
            listeners.put(owner,listener);
            if(first){media.setPreferredPackage(prefs.getString("mediaPackage","auto"));vehicle.start();weather.start();systemStatus.start();calendar.start();trafficLights.start();}
            publish();return null;
        });
    }

    public void removeListener(Object owner){
        onMain(()->{
            if(listeners.remove(owner)!=null&&listeners.isEmpty()){media.stop();vehicle.stop();weather.stop();systemStatus.stop();calendar.stop();trafficLights.stop();}
            return null;
        });
    }

    /** Climate, media and status sources each publish on their own callback. A burst
     * of them must reach the window as one packet: coalesce per looper turn and cap
     * the rate so a chatty source cannot force a rebuild on every single event. */
    public void publish(){
        onMain(()->{
            if(publishScheduled)return null;
            publishScheduled=true;
            long wait=PUBLISH_INTERVAL_MS-(android.os.SystemClock.elapsedRealtime()-publishedAt);
            if(wait<=0)main.post(deliver);else main.postDelayed(deliver,wait);
            return null;
        });
    }

    private final Runnable deliver=()->{
        publishScheduled=false;
        publishedAt=android.os.SystemClock.elapsedRealtime();
        // An owner may remove itself/another owner during notification.
        for(Map.Entry<Object,Runnable> entry:new IdentityHashMap<>(listeners).entrySet()){
            if(listeners.get(entry.getKey())!=entry.getValue())continue;
            try{entry.getValue().run();}
            catch(RuntimeException e){android.util.Log.w("UniState","Listener failed",e);}
        }
    };

    public void setDesktopContent(boolean selected){
        onMain(()->{if(desktopContent!=selected){desktopContent=selected;publish();}return null;});
    }
    public void setDesktopContentSilently(boolean selected){
        onMain(()->{desktopContent=selected;return null;});
    }
    public boolean homeVisible(){return onMain(()->homeVisible);}

    public void setHomeVisible(boolean visible){
        onMain(()->{if(homeVisible!=visible){homeVisible=visible;publish();}return null;});
    }

    /** 开机后若开启「开机自动播放音乐」，恢复上次音源；只处理启动后 5 分钟内，
     *  避免白天重新打开桌面时被误触发。 */
    public void scheduleBootAutoPlay(){
        onMain(()->{
            if(bootAutoPlayScheduled||!prefs.getBoolean("autoPlayMusic",false))return null;
            bootAutoPlayScheduled=true;
            if(android.os.SystemClock.elapsedRealtime()>5*60*1000)return null;
            main.postDelayed(this::autoPlayMusic,12000);
            return null;
        });
    }

    private void autoPlayMusic(){
        if(!prefs.getBoolean("autoPlayMusic",false))return;
        JSONObject state=media.snapshot();
        if(state.optBoolean("available")){
            // 已有媒体会话：只补一次「播放」，绝不把播放器拉到前台。
            if(!state.optBoolean("playing"))media.command("toggle-play");
        }else{
            // 播放器尚未建立会话：先拉起它（后台自建会话），随后回到桌面。
            String selected=prefs.getString("mediaPackage","auto");
            if("auto".equals(selected))selected=state.optString("source","ecarx.xsf.mediacenter");
            if(apps.launchPackage(selected))main.postDelayed(this::backToLauncher,4000);
        }
        publish();
    }

    private void backToLauncher(){
        try{context.startActivity(new Intent(context,MainActivity.class)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK|Intent.FLAG_ACTIVITY_REORDER_TO_FRONT));}
        catch(RuntimeException ignored){}
    }

    /** 包事件合并：连续安装/卸载/变更在 600ms 内只触发一次后台刷新。 */
    private void scheduleAppsRefresh(){
        onMain(()->{
            if(appsRefreshQueued)return null;
            appsRefreshQueued=true;
            main.postDelayed(appsRefreshTask,600);
            return null;
        });
    }

    /** 后台构建应用列表，完成后在主线程替换结果并补发；只保留最后一次请求的结果。 */
    private void refreshAppsInBackground(){
        appsRefreshQueued=false;
        final int gen=appsRefreshGeneration.incrementAndGet();
        new Thread(()->{
            try{
                AppRepository.Refresh next=apps.refresh();
                main.post(()->{
                    if(gen!=appsRefreshGeneration.get())return;
                    applyApps(next);
                    publish();
                });
            }catch(RuntimeException e){android.util.Log.w("UniApps","App refresh failed",e);}
        },"uni-apps").start();
    }

    private void applyApps(AppRepository.Refresh refresh){
        apps.applyAllowed(refresh.allowed);
        installed=refresh.apps;
        appsRevision++;
    }

    private void toast(String text){Toast.makeText(context,text,Toast.LENGTH_SHORT).show();}

    private JSONObject storedAppNames(){
        try{
            String raw=prefs.getString("appNames","");
            if(raw!=null&&!raw.isEmpty())return new JSONObject(raw);
            JSONObject design=new JSONObject(prefs.getString("savedDesign","{}"));
            JSONObject migrated=design.optJSONObject("appNames");
            if(migrated!=null){prefs.edit().putString("appNames",migrated.toString()).apply();return new JSONObject(migrated.toString());}
        }catch(Exception ignored){}
        return new JSONObject();
    }

    private static <T> T callOnMain(Callable<T> call)throws Exception{
        if(Looper.myLooper()==Looper.getMainLooper())return call.call();
        FutureTask<T> task=new FutureTask<>(call);
        if(!main.post(task))throw new IllegalStateException("Main looper unavailable");
        try{return task.get();}
        catch(InterruptedException e){Thread.currentThread().interrupt();throw e;}
        catch(ExecutionException e){
            Throwable cause=e.getCause();
            if(cause instanceof Exception)throw (Exception)cause;
            if(cause instanceof Error)throw (Error)cause;
            throw new IllegalStateException(cause);
        }
    }

    private static <T> T onMain(Callable<T> call){
        try{return callOnMain(call);}
        catch(RuntimeException e){throw e;}
        catch(Exception e){throw new IllegalStateException(e);}
    }
}
