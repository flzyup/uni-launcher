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
import java.util.concurrent.TimeUnit;
import java.util.concurrent.TimeoutException;
import org.json.JSONObject;
import org.json.JSONArray;
import xyz.i4o.uni.launcher.core.ClimateState;
import xyz.i4o.uni.launcher.core.CommandPolicy;
import xyz.i4o.uni.launcher.core.SteeringKeyPolicy;
import xyz.i4o.uni.launcher.integration.*;
import xyz.i4o.uni.launcher.log.LogTags;
import xyz.i4o.uni.launcher.log.UniLog;

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
    private final QuarkPan quark;
    private final StorageCleaner cleaner;
    private final DebugBridge debugBridge;
    /** 开机自启动计划：锚定开机秒数，进程内每计划只启动一次。 */
    private final BootLaunch bootLaunch;
    private final WirelessAdb wirelessAdb;
    /**
     * 需要 Activity 才能弹系统权限框的能力。面板窗口没有 Activity，统一借用主窗口。
     * 没接上（例如只有底栏在跑）时清理器自己降级，不会卡住。
     */
    public interface PermissionHost { void requestStoragePermission(); }
    private volatile PermissionHost permissionHost;

    public void attachPermissionHost(PermissionHost host){permissionHost=host;}
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
        /** 已经拿到的 apps 组是否带图标；只拿过 package/label 投影时为 false。 */
        public boolean icons;
        public String projectedSource="";
        void reset(){apps=design=media=settings=-1;icons=false;projectedSource="";}
    }
    private int appsRevision=0, designRevision=0, mediaRevision=0, settingsRevision=0;
    private String designFingerprint="", mediaFingerprint="";
    private boolean inDeliver;
    private TurnSnapshot activeTurn;

    private static final class TurnSnapshot {
        JSONObject climate, telemetry, systemStatus, weather, calendar, navigation,
            integrationPreferences, debugBridge, vehicleMemory, bootLaunch,
            wirelessAdb, trafficLights, fullMedia, strippedMedia, appNames,
            transfer, quark, cleaner;
        String design, projectedKey;
        JSONArray projectedApps;
        boolean demo, hideNavigation, globalNavigation, globalNavigationGranted, dark;
    }
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
        bootLaunch=new BootLaunch(context,prefs,apps,main,this::publish);
        wirelessAdb=new WirelessAdb(context,prefs,main,this::publish);
        long afterRepos=android.os.SystemClock.uptimeMillis();
        vehicle=new VehicleTelemetry(context,this::publish);navigation=new NavigationApps(context,prefs);
        long afterTelemetry=android.os.SystemClock.uptimeMillis();
        trafficLights=new AmapTrafficLightAdapter(context,navigation::selected,this::publish);
        media=new MediaAdapter(context,this::publish);weather=new OfficialWeatherAdapter(context,this::publish);systemStatus=new SystemStatusAdapter(context,this::publish);calendar=new SystemCalendarAdapter(context,this::publish);
        long afterAdapters=android.os.SystemClock.uptimeMillis();
        systemSettings=new SystemSettingsRepository(context);navigationAudio=new NavigationAudioAdapter(context);
        transfer=new LanTransfer(context,this::publish);
        quark=new QuarkPan(context,this::publish);transfer.attach(quark);
        // 清理器只持有 Application 上下文和自己的后台线程；主窗口与面板窗口共用一份。
        cleaner=new StorageCleaner(context,this::publish);
        // 夸克会话落盘在 filesDir/quark/session.json，读盘与静默刷新都推后到首帧之后。
        main.postDelayed(()->new Thread(quark::restore,"uni-quark-restore").start(),2500);
        debugBridge=new DebugBridge(context,prefs,this::publish);
        main.postDelayed(debugBridge::startup,3000);
        long afterSettings=android.os.SystemClock.uptimeMillis();
        // setPreferredPackage() starts MediaAdapter; defer it until the first owner.
        // 应用列表在后台构建，第一帧不被图标扫描/压缩阻塞；完成后主线程替换并补发。
        installed=new JSONArray();
        refreshAppsInBackground();
        long afterApps=android.os.SystemClock.uptimeMillis();
        // 分段耗时必须落盘：冷启动慢的时候，诊断包里要能直接看出是哪一段。
        UniLog.i(LogTags.APP,"运行时构建分段",
            "prefsMs",(afterPrefs-traceStart),
            "reposMs",(afterRepos-afterPrefs),
            "telemetryMs",(afterTelemetry-afterRepos),
            "adaptersMs",(afterAdapters-afterTelemetry),
            "settingsMs",(afterSettings-afterAdapters),
            "appsMs",(afterApps-afterSettings),
            "runtimeMs",(afterApps-traceStart));
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
        UniLog.i(LogTags.APP,"运行时就绪",
            "elapsedMs",(android.os.SystemClock.uptimeMillis()-traceStart));
    }

    public SharedPreferences prefs(){return prefs;}

    /**
     * Live subsystem states for the diagnostic package.
     *
     * <p>Read-only: it must never write to the head unit. The vehicle adapter
     * is only asked for what it already cached, so exporting a package cannot
     * change the car state.
     *
     * <p>Every section is guarded on its own: one broken adapter must not hide
     * the state of the others, and a failing read is reported instead of
     * silently producing an empty section.
     *
     * <p>The read runs on the main thread, like the regular snapshot does.
     * The export happens on a background thread, and the adapter snapshots
     * touch binder-backed state (the media controller, the vehicle reader);
     * reading them off the main thread would race with the normal publish
     * path.
     *
     * <p>The wait is bounded: the export must never hang because the main
     * thread is busy. A timeout is reported as a note instead.
     */
    public String describeAdapters(){
        if(Looper.myLooper()==Looper.getMainLooper())return describeAdaptersOnMain();
        FutureTask<String> task=new FutureTask<>(this::describeAdaptersOnMain);
        if(!main.post(task))return "(主线程不可用，无法读取子系统状态)\n";
        try{return task.get(2,TimeUnit.SECONDS);}
        catch(TimeoutException e){task.cancel(true);return "(读取子系统状态超时：主线程繁忙)\n";}
        catch(InterruptedException e){Thread.currentThread().interrupt();return "(读取子系统状态被中断)\n";}
        catch(ExecutionException e){return "(读取子系统状态失败: "+e.getCause()+")\n";}
    }

    private String describeAdaptersOnMain(){
        StringBuilder sb=new StringBuilder();
        section(sb,"车辆",()->vehicle.snapshot());
        section(sb,"媒体",()->media.snapshot());
        section(sb,"导航",()->navigation.snapshot());
        section(sb,"红绿灯",()->trafficLights.snapshot());
        section(sb,"天气",()->weather.snapshot());
        section(sb,"系统状态",()->systemStatus.snapshot());
        section(sb,"日历",()->calendar.snapshot());
        section(sb,"局域网传输",()->transfer.snapshot());
        section(sb,"调试桥",()->debugBridge.snapshot());
        return sb.toString();
    }

    /** One labelled snapshot section; a failing read is reported, not swallowed. */
    private static void section(StringBuilder sb,String label,Supplier snapshot){
        sb.append(label).append(": ");
        try{sb.append(String.valueOf(snapshot.get()));}
        catch(Throwable t){sb.append("读取失败: ").append(t.getMessage()==null?t.getClass().getSimpleName():t.getMessage());}
        sb.append('\n');
    }

    /** A snapshot supplier that may fail; the section reports the failure. */
    private interface Supplier{Object get() throws Exception;}

    /**
     * Live subsystem states, or a note when the runtime was never created.
     *
     * <p>The diagnostic package can be exported before the launcher window
     * exists (for example from the boot receiver); in that case there is
     * nothing to describe and the caller gets an explicit line.
     */
    public static String describeAdaptersIfAlive(Context context){
        LauncherRuntime current=instance;
        if(current==null)return "(运行时尚未创建，无子系统状态)\n";
        try{return current.describeAdapters();}
        catch(Throwable t){return "(读取子系统状态失败: "+t.getMessage()+")\n";}
    }
    /** 普通快照：按游标只补发变化的分组，不携带设置目录（Dock/面板用）。 */
    public JSONObject snapshot(StaticCursor cursor){return onMain(()->buildSnapshot(cursor,false,false));}

    /**
     * Dock/面板快照。
     *
     * <p>{@code includeApps} 为 false 时可以连图标分组都不发：底栏本身只画媒体
     * 和空调，把几百个图标的 base64 解码进常驻内存是纯支出。只有真的会列应用的
     * 页面（全部应用、导航选择、播放器选择）才要它，那时游标会让下一包整组补上。
     */
    public JSONObject snapshot(StaticCursor cursor,boolean includeApps){
        return onMain(()->buildSnapshot(cursor,false,includeApps));
    }

    /** 主窗口快照：除分组增量外，设置目录预热完成后也按游标补发一次。 */
    public JSONObject snapshotWithSettings(StaticCursor cursor){return onMain(()->buildSnapshot(cursor,true,true));}

    /**
     * 首帧快速通道：只读偏好里的外观和布局，不构造任何适配器快照。
     *
     * <p>窗口第一帧只需要主题与卡片；车辆、媒体、天气这些要等适配器就绪的内容
     * 晚一包没关系。把它们挡在首帧之外，白屏时间才只跟一次 prefs 读有关。
     */
    public JSONObject prelude(){
        JSONObject packet=new JSONObject();
        try{
            packet.put("savedDesign",prefs.getString("savedDesign",""))
                .put("appNames",storedAppNames())
                .put("dark",(context.getResources().getConfiguration().uiMode&Configuration.UI_MODE_NIGHT_MASK)==Configuration.UI_MODE_NIGHT_YES);
        }catch(Exception ignored){}
        return packet;
    }

    public boolean saveDesign(String raw){return onMain(()->saveDesignOnMain(raw));}

    /**
     * Sample the media block for a surface that lives outside the launcher window.
     *
     * <p>{@code MainActivity.publish()} deliberately skips snapshot construction when no Flutter
     * sink is attached, which is correct for the launcher and wrong for the lyric cast: the cast
     * window sits on another display while the user is in the music app, so its only source of
     * lyric state would go silent exactly when it matters. This entry point reads the media
     * block alone — no app scan, no settings catalogue — and, if the adapter was stopped when the
     * last listener went away, restarts it first.
     */
    public void pumpMediaCast(){
        onMain(()->{
            try{
                if(!media.started())media.start();
                media.snapshot();
            }catch(RuntimeException|LinkageError ignored){
                // A media service that died mid-read must not take the cast feed down with it.
            }
            return null;
        });
    }

    /** Release the media subscription the cast feed started, when casting is switched off. */
    public void releaseMediaCast(){
        onMain(()->{
            if(listeners.isEmpty()&&media.started())media.stop();
            return null;
        });
    }

    /** true means recognized, including input rejected by the original gates. */
    public boolean handle(JSONObject request)throws Exception{return callOnMain(()->handleOnMain(request));}

    private long demoPosition(){return demoPositionMs+(demoPlaying?Math.max(0,android.os.SystemClock.elapsedRealtime()-demoSampleAt):0);}
    private TurnSnapshot obtainTurnSnapshot(){
        if(inDeliver&&activeTurn!=null)return activeTurn;
        TurnSnapshot t=new TurnSnapshot();
        try{
            t.demo=prefs.getBoolean("demo",false);
            t.hideNavigation=prefs.getBoolean("hideNavigation",false);
            t.globalNavigation=prefs.getBoolean("globalNavigation",false);
            t.globalNavigationGranted=context.checkSelfPermission("android.permission.WRITE_SECURE_SETTINGS")==android.content.pm.PackageManager.PERMISSION_GRANTED;
            t.dark=(context.getResources().getConfiguration().uiMode&Configuration.UI_MODE_NIGHT_MASK)==Configuration.UI_MODE_NIGHT_YES;
            JSONObject climate=new JSONObject().put("left",simulator.left).put("right",simulator.right).put("fan",simulator.fan).put("power",simulator.power)
                .put("auto",simulator.auto).put("ac",simulator.ac).put("sync",simulator.sync).put("recirc",simulator.recirc)
                .put("driverHeat",simulator.driverHeat).put("driverVent",simulator.driverVent).put("passengerHeat",simulator.passengerHeat);
            t.telemetry=vehicle.snapshot();
            if(!t.demo)climate=t.telemetry.optJSONObject("climate")==null?new JSONObject():t.telemetry.getJSONObject("climate");
            t.climate=climate;
            t.systemStatus=systemStatus.snapshot();
            t.weather=weather.snapshot();
            t.calendar=calendar.snapshot();
            t.navigation=navigation.snapshot();
            t.integrationPreferences=new JSONObject()
                .put("mediaPackage",prefs.getString("mediaPackage","auto"))
                .put("mapTextureScale",prefs.getBoolean("mapTextureScale",false))
                .put("navigationCardTitleHidden",prefs.getBoolean("navigationCardTitleHidden",true))
                .put("autoPlayMusic",prefs.getBoolean("autoPlayMusic",false))
                .put("steeringKeysEnabled",prefs.getBoolean("steeringKeysEnabled",true))
                .put("instrumentSyncEnabled",prefs.getBoolean("instrumentSyncEnabled",true));
            t.debugBridge=debugBridge.snapshot();
            JSONObject memory=new JSONObject();
            try{
                memory.put("driveModeEnabled",prefs.getBoolean("memoryDriveModeEnabled",false))
                    .put("driveMode",prefs.getString("memoryDriveMode",""))
                    .put("startStopEnabled",prefs.getBoolean("memoryStartStopEnabled",false))
                    .put("startStop",prefs.getBoolean("memoryStartStop",true))
                    .put("driveModes",new JSONArray(java.util.Arrays.asList(CommandPolicy.DRIVE_MODES)))
                    .put("demo",t.demo);
            }catch(Exception ignored){}
            t.vehicleMemory=memory;
            t.bootLaunch=bootLaunch.snapshot();
            t.wirelessAdb=wirelessAdb.snapshot();
            t.trafficLights=trafficLights.snapshot();
            t.fullMedia=t.demo?demoMedia():media.snapshot().put("preferredPackage",prefs.getString("mediaPackage","auto"));
            t.strippedMedia=stripMediaPayload(t.fullMedia);
            t.appNames=storedAppNames();
            t.design=prefs.getString("savedDesign","");
            trackDesign(t.design,t.appNames);
            trackMedia(t.fullMedia);
            t.projectedKey=t.fullMedia.optString("source")+"|"+prefs.getString("mediaPackage","auto");
            t.transfer=transfer.snapshot();
            t.quark=quark.snapshot();
            t.cleaner=cleaner.snapshot();
        }catch(Exception e){UniLog.e(LogTags.APP,"快照构建失败",e);}
        if(inDeliver)activeTurn=t;
        return t;
    }

    private static JSONObject stripMediaPayload(JSONObject full){
        JSONObject copy=new JSONObject();
        if(full==null)return copy;
        java.util.Iterator<String> keys=full.keys();
        while(keys.hasNext()){
            String k=keys.next();
            if("artwork".equals(k)||"lyrics".equals(k)||"lyricTimeline".equals(k)
                ||"lyricTimelineLabel".equals(k)||"lyricTimelineWords".equals(k))continue;
            try{copy.put(k,full.opt(k));}catch(Exception ignored){}
        }
        return copy;
    }

    private JSONObject buildSnapshot(StaticCursor cursor, boolean includeSettings, boolean includeApps){
        JSONObject state=new JSONObject();try{
            TurnSnapshot t=obtainTurnSnapshot();
            state.put("systemStatus",t.systemStatus).put("weather",t.weather).put("calendar",t.calendar).put("navigation",t.navigation).put("integrationPreferences",t.integrationPreferences);
            state.put("debugBridge",t.debugBridge);
            state.put("demo",t.demo).put("hideNavigation",t.hideNavigation)
                .put("globalNavigation",t.globalNavigation)
                .put("globalNavigationGranted",t.globalNavigationGranted)
                .put("dark",t.dark)
                .put("climate",t.climate).put("vehicle",t.telemetry).put("version",xyz.i4o.uni.launcher.BuildConfig.VERSION_NAME+"-flutter");
            state.put("vehicleMemory",t.vehicleMemory);
            state.put("bootLaunch",t.bootLaunch);
            state.put("wirelessAdb",t.wirelessAdb);
            state.put("desktopSelected",homeVisible&&desktopContent);
            state.put("trafficLights",t.trafficLights);

            // 分组版本：图标、布局、媒体资源各自独立，只补发发生变化的部分。
            // 只想画底栏的窗口用「package/label 投影」代替整份 apps：查显示名
            // 不需要图标，几百个图标的 base64 没必要过一遍 JSON。真会列出应用的
            // 页面（全部应用/导航选择/播放器选择）传 includeApps=true，游标会
            // 靠 icons 位把整组补上。
            String projectedKey=t.projectedKey;
            boolean wantApps=(includeApps&&(cursor.apps!=appsRevision||!cursor.icons))||(cursor.icons&&cursor.apps!=appsRevision);
            boolean wantLabels=!includeApps&&!cursor.icons&&(cursor.apps!=appsRevision||!projectedKey.equals(cursor.projectedSource));
            boolean wantDesign=cursor.design!=designRevision;
            boolean wantMedia=cursor.media!=mediaRevision;
            boolean wantSettings=includeSettings&&systemSettings.isWarmed()&&cursor.settings!=settingsRevision;

            if(wantApps)state.put("apps",installed);
            else if(wantLabels){
                if(t.projectedApps==null)t.projectedApps=appProjection(installed,
                    t.fullMedia.optString("source"),prefs.getString("mediaPackage","auto"));
                state.put("apps",t.projectedApps);
            }
            if(wantDesign){state.put("savedDesign",t.design).put("appNames",t.appNames);}
            if(wantSettings){
                JSONArray entries=systemSettings.snapshot();
                if(entries!=null)state.put("systemSettings",new JSONObject().put("entries",entries).put("navigationAudio",navigationAudio.snapshot()));
            }
            state.put("runtimeOwnerCount",listeners.size()).put("media",wantMedia?t.fullMedia:t.strippedMedia)
                .put("transfer",t.transfer)
                .put("quark",t.quark)
                .put("cleaner",t.cleaner)
                .put("partial",!(wantApps&&wantDesign&&wantMedia));

            if(wantApps){cursor.apps=appsRevision;cursor.icons=true;cursor.projectedSource=projectedKey;}
            else if(wantLabels){cursor.apps=appsRevision;cursor.icons=false;cursor.projectedSource=projectedKey;}
            if(wantDesign)cursor.design=designRevision;
            if(wantMedia)cursor.media=mediaRevision;
            if(wantSettings)cursor.settings=settingsRevision;
        }catch(Exception e){UniLog.e(LogTags.APP,"快照构建失败",e);}return state;
    }

    /** apps 组投影：默认只给 package/label/id；正在播放（或用户指定）的播放器
     *  额外保留整行，好让底栏那条来源徽标还能画出它的图标。 */
    private static JSONArray appProjection(JSONArray apps,String source,String preferred){
        JSONArray out=new JSONArray();
        if(apps==null)return out;
        for(int i=0;i<apps.length();i++){
            JSONObject app=apps.optJSONObject(i);
            if(app==null)continue;
            String pkg=app.optString("package");
            if(pkg!=null&&(pkg.equals(source)||pkg.equals(preferred))){out.put(app);continue;}
            JSONObject row=new JSONObject();
            try{
                row.put("package",pkg).put("label",app.optString("label"));
                if(app.has("id"))row.put("id",app.opt("id"));
            }catch(Exception ignored){continue;}
            out.put(row);
        }
        return out;
    }

    /** 布局指纹按内容计算：即使键数或字符串长度不变，内容变化也会推进 designRevision。 */
    private void trackDesign(String design,JSONObject names){
        String fingerprint=design.hashCode()+":"+names.toString().hashCode();
        if(!fingerprint.equals(designFingerprint)){designFingerprint=fingerprint;designRevision++;}
    }
    private void trackMedia(JSONObject media){
        String fingerprint=media.optString("artwork","").hashCode()+":"
            +media.optString("lyrics","").hashCode()+":"
            +media.optString("lyricTimeline","").hashCode()+":"
            +media.optString("lyricTimelineLabel","");
        if(!fingerprint.equals(mediaFingerprint)){mediaFingerprint=fingerprint;mediaRevision++;}
    }

    private JSONObject demoMedia(){try{
        return new JSONObject().put("available",true).put("playing",demoPlaying)
                .put("title",demoTrack%2==0?"向海而行":"山海之间").put("artist",demoTrack%2==0?"Coastline":"Northbound").put("collection","晨间驾驶歌单").put("source","simulator").put("canNext",true).put("canPrevious",true).put("canToggle",true).put("canSeek",true)
                .put("lyrics","[00:00.00]晨光沿着海岸慢慢亮起\n[00:03.00]风把远方带进了呼吸\n[00:06.00]穿过山与海的交界\n[00:09.00]每一程都有新的风景\n[00:12.00]跟着潮声向前去\n[00:15.00]让今天从容开启")
                .put("lyricsSource","demo").put("durationMs",258000).put("positionMs",demoPosition()).put("positionKnown",true)
                .put("sampledAtMs",System.currentTimeMillis()).put("speed",1);
    }catch(Exception e){UniLog.e(LogTags.MEDIA,"演示媒体状态失败",e);return new JSONObject();}}
    private boolean saveDesignOnMain(String raw){
            if(raw==null||raw.length()>65536)return false;
            try{
                JSONObject data=new JSONObject(raw);JSONObject p=data.getJSONObject("preferences");
                int version=data.optInt("version");
                if((version<4||version>6)||!p.optString("custom").matches("#[0-9a-fA-F]{6}"))return false;
                String mode=p.optString("mode"),palette=p.optString("palette");
                String themeStyle=p.optString("themeStyle","classic");
                if(!"classic".equals(themeStyle)&&!"blueGlass".equals(themeStyle)&&!"nocturne".equals(themeStyle))return false;
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
                if(p.has("wallpaperOverlay")&&!(p.get("wallpaperOverlay") instanceof Boolean))return false;
                if(!"small".equals(p.optString("dockSize","large"))&&!"medium".equals(p.optString("dockSize"))&&!"large".equals(p.optString("dockSize"))&&!"extraLarge".equals(p.optString("dockSize")))return false;
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
                // 异步写盘：内存立即生效，不阻塞主线程等待磁盘提交；布局变更由
                // trackDesign 的内容指纹在下次快照时推进 designRevision。
                editor.apply();
            }catch(Exception e){return false;}
            publish();return true;
        }
    private boolean handleOnMain(JSONObject request)throws Exception{
        String action=request.optString("action"),value=request.optString("value"),zone=request.optString("zone");
        // 车机上没有调试器，出问题时先看这一行有没有出现，就能分清「没点到」还是「动作失败」。
        if(action.startsWith("transfer-"))UniLog.i(LogTags.TRANSFER,"传输动作","action",action,"value",value);
        if("rename-app".equals(action)){
            if(zone.length()==0||zone.length()>255||zone.indexOf('\n')>=0||zone.indexOf('\r')>=0||value.length()>96||value.indexOf('\n')>=0||value.indexOf('\r')>=0)return true;
            JSONObject names=storedAppNames();
            if(value.isEmpty())names.remove(zone);else names.put(zone,value);
            if(!prefs.edit().putString("appNames",names.toString()).commit()){
                toast("应用名称保存失败");return false;
            }
            publish();return true;
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
        if("navigation-card-title-hidden".equals(action)){prefs.edit().putBoolean("navigationCardTitleHidden",request.optBoolean("enabled",true)).apply();publish();return true;}
        // 方向盘控制：默认开。关掉立刻反注册原车输入通道，方向盘键原样留给原车。
        if("steering-keys".equals(action)){
            boolean on=request.optBoolean("enabled",true);
            prefs.edit().putBoolean("steeringKeysEnabled",on).apply();
            media.setSteeringEnabled(on);
            publish();return true;
        }
        // 仪表同步：默认开。关掉立刻反注册解绑原车媒体中心，仪表跟回原车播放器。
        if("instrument-sync".equals(action)){
            boolean on=request.optBoolean("enabled",true);
            prefs.edit().putBoolean("instrumentSyncEnabled",on).apply();
            media.setInstrumentEnabled(on);
            publish();return true;
        }
        if("auto-play-music".equals(action)){prefs.edit().putBoolean("autoPlayMusic",request.optBoolean("enabled",false)).apply();publish();return true;}
        // 记忆配置：只记录偏好，真正写入由启动流程或用户点「立即应用」触发。
        if("memory-drive-mode-enabled".equals(action)){
            prefs.edit().putBoolean("memoryDriveModeEnabled",request.optBoolean("enabled",false)).apply();publish();return true;
        }
        if("memory-drive-mode-target".equals(action)){
            if(!CommandPolicy.validDriveMode(value)){toast("该驾驶模式不可用于记忆");return true;}
            prefs.edit().putString("memoryDriveMode",value).apply();publish();return true;
        }
        if("memory-start-stop-enabled".equals(action)){
            prefs.edit().putBoolean("memoryStartStopEnabled",request.optBoolean("enabled",false)).apply();publish();return true;
        }
        if("memory-start-stop-target".equals(action)){
            if(!"on".equals(value)&&!"off".equals(value)){toast("启停记忆值无效");return true;}
            prefs.edit().putBoolean("memoryStartStop","on".equals(value)).apply();publish();return true;
        }
        if("memory-apply-now".equals(action)){
            if(prefs.getBoolean("demo",false)){toast("演示模式不写入车辆设置");return true;}
            boolean any=false;
            if(("driveMode".equals(value)||"all".equals(value))&&prefs.getBoolean("memoryDriveModeEnabled",false)){
                any=true;
                if(!vehicle.command("drive-mode","",prefs.getString("memoryDriveMode","")))toast("车辆未连接或不支持该驾驶模式");
            }
            if(("startStop".equals(value)||"all".equals(value))&&prefs.getBoolean("memoryStartStopEnabled",false)){
                any=true;
                if(!vehicle.command("start-stop","",prefs.getBoolean("memoryStartStop",true)?"on":"off"))toast("车辆未连接或不支持启停设置");
            }
            if(!any)toast("请先开启要应用的记忆项");
            publish();return true;
        }
        // 开机自启动计划：只记录计划；真正启动由开机落点窗口里的排程执行。
        if("boot-launch-enabled".equals(action)){
            bootLaunch.setEnabled(request.optBoolean("enabled",false));publish();return true;
        }
        if("boot-launch-add".equals(action)){
            int delay=-1;
            try{delay=Integer.parseInt(zone==null?"0":zone.trim());}catch(Exception ignored){}
            if(delay<0||delay>BootLaunch.MAX_DELAY){toast("启动秒数需在 0 到 "+BootLaunch.MAX_DELAY+" 之间");return true;}
            if(!bootLaunch.add(value,delay)){
                toast("计划已存在或已达到 "+BootLaunch.MAX_PLANS+" 条上限");
            }
            publish();return true;
        }
        if("boot-launch-remove".equals(action)){
            if(!bootLaunch.remove(value))toast("计划已不存在");
            publish();return true;
        }
        if("boot-launch-clear".equals(action)){
            bootLaunch.clear();publish();return true;
        }
        if("boot-launch-run".equals(action)){
            if(prefs.getBoolean("demo",false)){toast("演示模式不启动应用");return true;}
            if(!bootLaunch.runNow(value))toast("计划已不存在");
            publish();return true;
        }
        if("wireless-adb-enabled".equals(action)){
            wirelessAdb.setEnabled(request.optBoolean("enabled",false));publish();return true;
        }
        if("wireless-adb-run".equals(action)){
            wirelessAdb.ensureNow();publish();return true;
        }
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
        if("debug-refresh".equals(action)){debugBridge.refresh();return true;}
        if("debug-adb".equals(action)||"debug-network".equals(action)){
            debugBridge.change("debug-network".equals(action),request.optBoolean("enabled",false));return true;
        }
        if("app-info".equals(action)){if(!apps.showInfo(value))toast("无法打开应用信息");return true;}
        if("app-enable".equals(action)||"app-disable".equals(action)){
            if(!apps.setEnabled(value,"app-enable".equals(action)))toast("无法修改应用状态");
            refreshAppsInBackground();return true;
        }
        if("request-uninstall".equals(action)){if(!apps.requestUninstall(value))toast("该应用不可卸载");return true;}
        if("launch-app".equals(action)){if(!apps.launch(value))toast("应用未安装或无法启动");return true;}
        if("media-access".equals(action)){try{context.startActivity(new Intent("android.settings.ACTION_NOTIFICATION_LISTENER_SETTINGS").addFlags(Intent.FLAG_ACTIVITY_NEW_TASK));}catch(Exception e){toast("系统没有提供媒体授权入口");}return true;}
        // 垃圾清理：扫描与清理都在 StorageCleaner 的后台线程，这里只做派发。
        // value 是逗号分隔的类目 id，长度与白名单由 StorageCleaner 再校验一次。
        if("cleaner-scan".equals(action)){cleaner.scan();return true;}
        if("cleaner-clean".equals(action)){cleaner.clean(value);return true;}
        if("cleaner-cancel".equals(action)){cleaner.cancel();return true;}
        // 面板打开时自动要权限：能直接拿到就重扫，拿不到由 Activity 弹一次系统框。
        if("cleaner-grant".equals(action)){
            PermissionHost host=permissionHost;
            if(host!=null)host.requestStoragePermission();else cleaner.refreshPermission();
            return true;
        }
        if("cleaner-permission".equals(action)){cleaner.refreshPermission();return true;}
        if("transfer-start".equals(action)){transfer.start();publish();return true;}        if("transfer-stop".equals(action)){transfer.stop();publish();return true;}
        if("transfer-install".equals(action)){if(!transfer.install(value))toast("未找到可安装的文件，或系统未允许安装");publish();return true;}
        if("transfer-delete".equals(action)){transfer.delete(value);publish();return true;}
        // 手机只负责把地址交上来；下载由车机上的点击触发，避免车机被外部驱动流量。
        if("transfer-link-download".equals(action)){if(!transfer.downloadLink(value))toast("链接无效或任务已不存在");publish();return true;}
        if("transfer-link-remove".equals(action)){transfer.removeLink(value);publish();return true;}
        // 手机发来的文本：复制在 Dart 侧做（剪贴板），这里只负责增删。
        if("transfer-text-remove".equals(action)){transfer.removeText(value);publish();return true;}
        if("transfer-text-clear".equals(action)){transfer.clearTexts();publish();return true;}
        // ---- 夸克网盘：扫码登录、列目录，真正下载仍由车机点「下载」触发 ----
        if("quark-login".equals(action)||"quark-login-refresh".equals(action)){quark.startLogin();publish();return true;}
        if("quark-logout".equals(action)){quark.logout();publish();return true;}
        if("quark-open".equals(action)){
            String raw=value==null?"":value;
            int sep=raw.indexOf('|');
            quark.open(sep>=0?raw.substring(0,sep):raw,sep>=0?raw.substring(sep+1):"");
            publish();return true;
        }
        if("quark-list".equals(action)){quark.open(value,"");publish();return true;}
        if("quark-more".equals(action)){quark.more();publish();return true;}
        if("quark-enqueue".equals(action)){
            if(quark.enqueue(value,transfer)==0)toast("没有可下载的文件，或夸克登录已失效");
            publish();return true;
        }
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
        if(CommandPolicy.isSettingAction(action)){
            if(prefs.getBoolean("demo",false)){toast("演示模式不写入车辆设置");return true;}
            if(!vehicle.command(action,"",value))toast("车辆未连接或未确认该设置值");publish();return true;
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
            if(first){media.setSteeringEnabled(prefs.getBoolean("steeringKeysEnabled",true));media.setInstrumentEnabled(prefs.getBoolean("instrumentSyncEnabled",true));media.setPreferredPackage(prefs.getString("mediaPackage","auto"));vehicle.start();weather.start();systemStatus.start();calendar.start();trafficLights.start();}
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
            activeTurn=null;
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
        inDeliver=true;
        activeTurn=null;
        try{
            // An owner may remove itself/another owner during notification.
            for(Map.Entry<Object,Runnable> entry:new IdentityHashMap<>(listeners).entrySet()){
                if(listeners.get(entry.getKey())!=entry.getValue())continue;
                try{entry.getValue().run();}
                catch(RuntimeException e){UniLog.w(LogTags.APP,"快照监听器异常",e);}
            }
        }finally{
            inDeliver=false;
            activeTurn=null;
        }
    };

    public void setDesktopContent(boolean selected){
        onMain(()->{if(desktopContent!=selected){desktopContent=selected;publish();}return null;});
    }
    public void setDesktopContentSilently(boolean selected){
        onMain(()->{desktopContent=selected;return null;});
    }
    public boolean homeVisible(){return onMain(()->homeVisible);}

    /**
     * 车机把媒体键当普通按键派给桌面窗口时的入口（没走 MediaSession 路由）。
     * 与方控输入通道共用同一套折叠，返回 true 表示这个键归桌面媒体控制、已消费。
     */
    public boolean dispatchSteeringKey(int keyCode,String channel){
        String action=SteeringKeyPolicy.action(keyCode);
        if(action.isEmpty())return false;
        onMain(()->{media.onSteeringAction(channel,action);return null;});
        return true;
    }

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

    /** 开机自启动：只在开机窗口内按计划排程，桌面进程重启不会重放同一条计划。 */
    public void scheduleBootLaunch(){
        onMain(()->{
            bootLaunch.schedule();
            return null;
        });
    }

    /** 开机自动启动无线 adb：只在开关打开时动手，失败会按 20 秒间隔重试几次。 */
    public void scheduleWirelessAdb(){
        onMain(()->{
            if(wirelessAdb.enabled())wirelessAdb.schedule();
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
            }catch(RuntimeException e){UniLog.w(LogTags.APPS,"应用列表刷新失败",e);}
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
