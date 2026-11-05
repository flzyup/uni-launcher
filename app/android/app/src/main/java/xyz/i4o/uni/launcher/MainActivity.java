package xyz.i4o.uni.launcher;

import android.content.Intent;
import android.app.Activity;
import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import android.net.Uri;
import android.content.pm.PackageManager;
import android.content.res.Configuration;
import android.os.Bundle;
import android.view.View;
import android.view.WindowInsets;
import android.view.WindowManager;
import android.widget.Toast;
import io.flutter.embedding.android.FlutterActivity;
import io.flutter.embedding.engine.FlutterEngine;
import io.flutter.plugin.common.EventChannel;
import io.flutter.plugin.common.MethodChannel;
import java.io.File;
import java.io.FileOutputStream;
import java.io.InputStream;
import java.util.HashMap;
import java.util.Map;
import org.json.JSONObject;
import xyz.i4o.uni.launcher.integration.NavigationChrome;
import xyz.i4o.uni.launcher.log.LogTags;
import xyz.i4o.uni.launcher.log.UniLog;
import xyz.i4o.uni.launcher.overlay.SystemNavigationPolicy;
import xyz.i4o.uni.launcher.platform.LiveNavigationHost;

/** Home window and Flutter bridge; shared integrations live in LauncherRuntime. */
public final class MainActivity extends FlutterActivity {
    private static java.lang.ref.WeakReference<MainActivity> active=new java.lang.ref.WeakReference<>(null);

    /** 存储权限的请求码：导出诊断包要往公共目录写文件。 */
    private static final int REQUEST_STORAGE=4107;

    /** 等存储权限结果的回调；系统弹窗是异步的，结果要等回调。 */
    private static java.util.function.Consumer<Boolean> pendingStorage;

    /**
     * 申请导出诊断包需要的存储权限。
     *
     * <p>Android 9 及以下要往公共 Download 目录写文件，没有
     * {@code WRITE_EXTERNAL_STORAGE} 会直接失败；Android 10+ 走 MediaStore，
     * 不需要任何权限，所以直接算「已授予」。
     *
     * <p>读权限一并申请：清理旧诊断包要读 MediaStore 集合才能列出自己导出的包。
     * 但**导出能不能做只看写权限** —— 读权限被拒不该连累导出。
     *
     * @param done 回调：true 表示可以导出
     */
    public static void requestStoragePermission(android.content.Context context, java.util.function.Consumer<Boolean> done){
        if(android.os.Build.VERSION.SDK_INT>=29){done.accept(true);return;}
        MainActivity owner=active.get();
        if(owner==null||!owner.hasWindowFocus()){done.accept(false);return;}
        if(storageWritable(owner)){done.accept(true);return;}
        pendingStorage=done;
        owner.requestPermissions(new String[]{
                android.Manifest.permission.WRITE_EXTERNAL_STORAGE,
                android.Manifest.permission.READ_EXTERNAL_STORAGE},REQUEST_STORAGE);
    }

    /** 写外部存储权限是否已授予（能不能往公共目录写文件）。 */
    public static boolean storageWritable(android.content.Context context){
        if(android.os.Build.VERSION.SDK_INT>=29)return true;
        return context.checkSelfPermission(android.Manifest.permission.WRITE_EXTERNAL_STORAGE)==PackageManager.PERMISSION_GRANTED;
    }

    /** 读外部存储权限是否已授予（能不能列出 MediaStore 里自己导出的包）。 */
    public static boolean storageReadable(android.content.Context context){
        if(android.os.Build.VERSION.SDK_INT>=33)return true;
        return context.checkSelfPermission(android.Manifest.permission.READ_EXTERNAL_STORAGE)==PackageManager.PERMISSION_GRANTED;
    }

    public static void requestBootUpdateCheck(){
        MainActivity a=active.get();
        if(a!=null)a.runOnUiThread(()->{if(a.otaEvents!=null)a.otaEvents.invokeMethod("boot-check",null);});
    }
    public static void refreshNavigationChrome(boolean systemNavHidden){
        MainActivity a=active.get();
        if(a!=null)a.runOnUiThread(()->{
            if(a.chrome!=null)a.chrome.apply();
            if(!systemNavHidden)a.recreate(); // Android 9 keeps the resized app bounds unless the activity is rebuilt.
            a.publish();
        });
    }
    private LauncherRuntime rt;
    private xyz.i4o.uni.launcher.audio.SpectrumBridge spectrumBridge;
    private xyz.i4o.uni.launcher.ambient.AmbientLightBridge ambientBridge;
    private NavigationChrome chrome;
    private LiveNavigationHost mapHost;
    private int reservedBottomPx;
    private boolean initialSettings;
    private EventChannel events;
    private MethodChannel channel;
    private MethodChannel otaEvents;
    private MethodChannel.Result wallpaperResult;
    private static final int PICK_WALLPAPER=4206;

    /**
     * 主引擎是进程级的（见 {@link #provideFlutterEngine}），所以凡是「镜像 Dart
     * isolate 内部状态」的东西都必须挂在引擎上、而不是窗口上：活动因为导航栏或
     * 配置改变重建时，新窗口要接着用同一套分组游标、同一份快照缓存和同一条事件
     * 流，否则已经在跑的那份 Dart 界面就再也收不到更新。
     */
    private static final class EngineState {
        String cached="{}";
        JSONObject flutterViewport=new JSONObject();
        final LauncherRuntime.StaticCursor cursor=new LauncherRuntime.StaticCursor();
        /** Last signature handed to the sink; see emit(). */
        String sentSignature;
        EventChannel.EventSink sink;
        void reset(){cached="{}";sentSignature=null;sink=null;flutterViewport=new JSONObject();
            cursor.apps=cursor.design=cursor.media=cursor.settings=-1;}
    }
    /** 共享引擎的那一份；「一窗一引擎」的退路各自新建一份，互不干扰。 */
    private static EngineState sharedState=new EngineState();
    private EngineState engineState=sharedState;
    private static FlutterEngine sharedEngine;
    /** false 表示本窗口挂在共享引擎上，销毁窗口时不能连引擎一起带走。 */
    private boolean ownsEngine=true;
    /** true 表示接着用的是一份已经在跑的 Dart isolate（窗口重建）。 */
    private boolean engineWasWarm;

    /** Called by the new version on startup, after Android has finished install. */
    private void cleanupInstalledOta(File dir){
        File apk=new File(dir,"update.apk");
        if(!apk.isFile())return;
        try{
            android.content.pm.PackageInfo installed=getPackageManager().getPackageInfo(getPackageName(),PackageManager.GET_SIGNATURES);
            android.content.pm.PackageInfo cached=getPackageManager().getPackageArchiveInfo(apk.getAbsolutePath(),PackageManager.GET_SIGNATURES);
            if(cached!=null&&getPackageName().equals(cached.packageName)
                &&cached.versionCode<=installed.versionCode&&cached.signatures!=null&&installed.signatures!=null
                &&java.util.Arrays.equals(cached.signatures,installed.signatures)){
                if(!apk.delete())UniLog.w(LogTags.OTA,"已安装的更新缓存无法删除");
            }
        }catch(RuntimeException|PackageManager.NameNotFoundException e){
            UniLog.w(LogTags.OTA,"无法检查更新缓存",e);
        }
    }

    /**
     * 主窗口引擎在进程内复用。
     *
     * <p>导航栏策略变更会让 Activity {@code recreate()}，其它配置变化也会重建
     * 窗口。以前每次都跟着新建引擎，于是 Dart 的引导（bootstrap 快照、布局解析、
     * 图标解码）要在「切一下导航栏」里重跑一遍。窗口重建并没有换进程，Dart
     * isolate 也还活着：把引擎留给下一个窗口接管，重建就只剩一次 attach。
     *
     * <p>Flutter 只允许一个窗口挂在同一个引擎上。本 ROM 偶尔会在旧 HOME 还没
     * 销毁时再起一个实例（见 onCreate 里的 previous.finish），那种情况退回
     * 「一窗一引擎」，行为与改动前一致；只有旧窗口已经 onDestroy、{@link #active}
     * 被清空时才复用。
     */
    @Override public FlutterEngine provideFlutterEngine(android.content.Context context){
        if(active.get()!=null){
            ownsEngine=true;
            engineWasWarm=false;
            engineState=new EngineState();
            return LauncherEngines.create(context,"main",true);
        }
        FlutterEngine engine=sharedEngine;
        engineWasWarm=engine!=null;
        if(engine==null){
            engine=LauncherEngines.create(context,"main",true);
            sharedEngine=engine;
            final FlutterEngine created=engine;
            engine.addEngineLifecycleListener(new FlutterEngine.EngineLifecycleListener(){
                public void onPreEngineRestart(){}
                public void onEngineWillDestroy(){
                    synchronized(MainActivity.class){
                        if(sharedEngine!=created)return;
                        sharedEngine=null;sharedState=new EngineState();
                    }
                }
            });
        }
        engineState=sharedState;
        ownsEngine=false;
        return engine;
    }
    @Override public boolean shouldDestroyEngineWithHost(){return ownsEngine;}

    @Override public void onTrimMemory(int level){
        super.onTrimMemory(level);
        if(mapHost!=null)mapHost.trimMemory(level);
    }

    @Override public void onLowMemory(){
        super.onLowMemory();
        if(mapHost!=null)mapHost.trimMemory(android.content.ComponentCallbacks2.TRIM_MEMORY_RUNNING_CRITICAL);
    }

    @Override public void configureFlutterEngine(FlutterEngine engine){
        super.configureFlutterEngine(engine);
        spectrumBridge=xyz.i4o.uni.launcher.audio.SpectrumBridge.attach(this,engine);
        ambientBridge=xyz.i4o.uni.launcher.ambient.AmbientLightBridge.attach(this,engine);
        // 日志通道：让 Dart 侧的日志与原生侧落进同一个文件。
        xyz.i4o.uni.launcher.log.LogBridge.attach(this,engine);
        if(rt==null)rt=LauncherRuntime.get(this);
        mapHost=new LiveNavigationHost(this,engine.getDartExecutor().getBinaryMessenger(),engine.getRenderer());
        channel=new MethodChannel(engine.getDartExecutor().getBinaryMessenger(),"xyz.i4o.uni.launcher/platform");
        otaEvents=new MethodChannel(engine.getDartExecutor().getBinaryMessenger(),"xyz.i4o.uni.launcher/ota-events");
        channel.setMethodCallHandler((call,result)->{
            try{
                if("snapshot".equals(call.method)){
                    updateSnapshot();result.success(engineState.cached);
                    // Bootstrap consumes the fallback once. Events must not consume
                    // it before Dart has installed its method handler.
                    initialSettings=false;
                }
                else if("prelude".equals(call.method)){
                    // 首帧快速通道：只有外观与布局，不碰任何适配器/扫描。
                    // Dart 拿到就能用正确的主题画出第一帧，完整快照随后跟上。
                    result.success(preludeSnapshot());
                    initialSettings=false;
                }
                else if("otaInfo".equals(call.method)){
                    android.content.pm.PackageInfo info=getPackageManager().getPackageInfo(getPackageName(),0);
                    File dir=new File(getFilesDir(),"ota"); if(!dir.isDirectory()&&!dir.mkdirs()) throw new IllegalStateException("ota directory");
                    cleanupInstalledOta(dir);
                    Map<String,Object> data=new HashMap<>();data.put("versionName",info.versionName);data.put("versionCode",(long)info.versionCode);data.put("sdk",android.os.Build.VERSION.SDK_INT);data.put("abis",java.util.Arrays.asList(android.os.Build.SUPPORTED_ABIS));data.put("directory",dir.getAbsolutePath());data.put("enabled",getPreferences(0).getBoolean("otaEnabledV2",false));data.put("intervalMinutes",getPreferences(0).getInt("otaIntervalMinutes",30));data.put("dismissedVersion",getPreferences(0).getInt("otaDismissedVersion",0));data.put("dismissedAt",getPreferences(0).getLong("otaDismissedAt",0));result.success(data);
                }
                else if("otaDismiss".equals(call.method)){if(call.arguments instanceof Number)getPreferences(0).edit().putInt("otaDismissedVersion",((Number)call.arguments).intValue()).putLong("otaDismissedAt",System.currentTimeMillis()).apply();result.success(null);}
                else if("otaEnabled".equals(call.method)){getPreferences(0).edit().putBoolean("otaEnabledV2",Boolean.TRUE.equals(call.arguments)).apply();result.success(null);}
                else if("otaInterval".equals(call.method)){int minutes=call.arguments instanceof Number?((Number)call.arguments).intValue():30;if(minutes!=30&&minutes!=120&&minutes!=720&&minutes!=1440)throw new IllegalArgumentException("Invalid interval");getPreferences(0).edit().putInt("otaIntervalMinutes",minutes).apply();result.success(null);}
                else if("otaCanInstall".equals(call.method)){result.success(android.os.Build.VERSION.SDK_INT<26||getPackageManager().canRequestPackageInstalls());}
                else if("otaInstall".equals(call.method)){
                    File f=new File(new File(getFilesDir(),"ota"),"update.apk");
                    android.content.pm.PackageInfo installed=getPackageManager().getPackageInfo(getPackageName(),PackageManager.GET_SIGNATURES);
                    android.content.pm.PackageInfo candidate=getPackageManager().getPackageArchiveInfo(f.getAbsolutePath(),PackageManager.GET_SIGNATURES);
                    if(candidate==null||!getPackageName().equals(candidate.packageName)||candidate.versionCode<=installed.versionCode||installed.signatures==null||candidate.signatures==null||!java.util.Arrays.equals(installed.signatures,candidate.signatures))throw new SecurityException("package identity");
                    if(android.os.Build.VERSION.SDK_INT>=26&&!getPackageManager().canRequestPackageInstalls()){
                        Intent settings=new Intent(android.provider.Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,Uri.parse("package:"+getPackageName()));startActivity(settings);result.success("permission");
                    }else{
                        Intent install=new Intent(Intent.ACTION_INSTALL_PACKAGE).setData(Uri.parse("content://xyz.i4o.uni.launcher.ota/update.apk"));install.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION);startActivity(install);result.success("started");
                    }
                }
                else if("saveDesign".equals(call.method))result.success(rt.saveDesign((String)call.arguments));
                else if("pickWallpaper".equals(call.method)){
                    if(wallpaperResult!=null){result.error("busy","图片选择器已打开",null);return;}
                    Intent pick=new Intent(this,WallpaperPickerActivity.class);
                    wallpaperResult=result;
                    try{startActivityForResult(pick,PICK_WALLPAPER);}catch(RuntimeException e){wallpaperResult=null;throw e;}
                }
                else if("desktopPage".equals(call.method)){
                    int page=call.arguments instanceof Number?((Number)call.arguments).intValue():0;
                    if(mapHost!=null)mapHost.preparePageChange();
                    engineState.flutterViewport.put("page",page);
                    rt.setDesktopContentSilently(page==0);result.success(null);
                }
                else if("viewport".equals(call.method)){engineState.flutterViewport=new JSONObject((String)call.arguments);
                    rt.setDesktopContent(!engineState.flutterViewport.optBoolean("settings")&&engineState.flutterViewport.optInt("page")==0);result.success(null);}
                else if("action".equals(call.method)){
                    String raw=(String)call.arguments;
                    if(raw==null||raw.length()>8192){result.error("invalid","Invalid request",null);return;}
                    handle(new JSONObject(raw));result.success(null);
                }
                else if("clusterLyricsDisplays".equals(call.method)){
                    result.success(xyz.i4o.uni.launcher.integration.display.ClusterLyricsService.displays(this));}
                else if("clusterLyricsStatus".equals(call.method)){
                    result.success(xyz.i4o.uni.launcher.integration.display.ClusterLyricsService.status(this));}
                else if("clusterLyricsApply".equals(call.method)){
                    java.util.Map<?,?> m=call.arguments instanceof java.util.Map?(java.util.Map<?,?>)call.arguments:java.util.Collections.emptyMap();
                    // The whole configuration crosses the channel as-is: position, width, rows,
                    // accent and style all live in one place, so the preview in settings and the
                    // panel on the cluster can never disagree about a value.
                    java.util.Map<String,Object> values=new java.util.LinkedHashMap<>();
                    for(java.util.Map.Entry<?,?> entry:m.entrySet())
                        if(entry.getKey()!=null)values.put(String.valueOf(entry.getKey()),entry.getValue());
                    xyz.i4o.uni.launcher.integration.display.ClusterLyricsService.apply(this,values);
                    result.success(xyz.i4o.uni.launcher.integration.display.ClusterLyricsService.status(this));}
                else if("lyricTuningStatus".equals(call.method)){
                    // One round trip for both halves: the settings page needs the offsets and
                    // the cache policy together, and it must know which track the per-track
                    // value belongs to — that is whatever the cast panel is showing.
                    xyz.i4o.uni.launcher.integration.lyrics.LyricCast.State cast =
                            xyz.i4o.uni.launcher.integration.lyrics.LyricCast.state();
                    java.util.Map<String,Object> out=new java.util.LinkedHashMap<>();
                    out.put("globalMs",xyz.i4o.uni.launcher.integration.lyrics.LyricOffset.globalMs());
                    out.put("trackMs",xyz.i4o.uni.launcher.integration.lyrics.LyricOffset
                            .trackMs(cast.title,cast.artist));
                    out.put("title",cast.title);
                    out.put("artist",cast.artist);
                    out.put("policy",xyz.i4o.uni.launcher.integration.lyrics.LyricCachePolicy
                            .policy(this));
                    out.put("limitMb",xyz.i4o.uni.launcher.integration.lyrics.LyricCachePolicy
                            .limitMb(this));
                    result.success(out);}
                else if("lyricTuning".equals(call.method)){
                    // Global and per-track lyric offset, persisted where the playback clock
                    // reads it so a correction survives a restart of the launcher.
                    java.util.Map<?,?> m=call.arguments instanceof java.util.Map?(java.util.Map<?,?>)call.arguments:java.util.Collections.emptyMap();
                    int global=number(m.get("globalMs"),0);
                    int track=number(m.get("trackMs"),0);
                    String title=m.get("title")==null?null:String.valueOf(m.get("title"));
                    String artist=m.get("artist")==null?null:String.valueOf(m.get("artist"));
                    xyz.i4o.uni.launcher.integration.lyrics.LyricOffset.save(this,global,title,artist,track);
                    result.success(new java.util.LinkedHashMap<String,Object>(){{put("globalMs",xyz.i4o.uni.launcher.integration.lyrics.LyricOffset.globalMs());}});}
                else if("lyricCache".equals(call.method)){
                    java.util.Map<?,?> m=call.arguments instanceof java.util.Map?(java.util.Map<?,?>)call.arguments:java.util.Collections.emptyMap();
                    xyz.i4o.uni.launcher.integration.lyrics.LyricCachePolicy.save(this,
                            m.get("policy")==null?null:String.valueOf(m.get("policy")),
                            number(m.get("limitMb"),
                                    xyz.i4o.uni.launcher.integration.lyrics.LyricCachePolicy.limitMb(this)));
                    result.success(xyz.i4o.uni.launcher.integration.lyrics.LyricCachePolicy.policy(this));}
                else result.notImplemented();
            }catch(Exception e){result.error("unavailable","操作暂不可用",null);}
        });
        events=new EventChannel(engine.getDartExecutor().getBinaryMessenger(),"xyz.i4o.uni.launcher/events");
        events.setStreamHandler(new EventChannel.StreamHandler(){
            public void onListen(Object args,EventChannel.EventSink events){engineState.sink=events;engineState.sentSignature=null;publish();}
            public void onCancel(Object args){
                engineState.sink=null;engineState.sentSignature=null;
                // The next subscriber is a fresh Dart controller with no cached
                // groups, so the first packet must carry every group again.
                engineState.cursor.apps=-1;engineState.cursor.design=-1;engineState.cursor.media=-1;engineState.cursor.settings=-1;
            }
        });
        // 共享引擎被新窗口接管时 Dart 不会重发 listen：订阅属于 isolate，还在。
        // 这里把上次的 sink 接回来，并作废签名强制补发一包，让新窗口的尺寸/
        // 安全区立刻生效（否则界面会停在重建前的几何上）。
        if(engineWasWarm&&engineState.sink!=null)engineState.sentSignature=null;
        if(engineState.sink!=null)publish();
        // 平台视图（实时地图）归上一个窗口所有，已经随它一起关掉了；Dart 那份
        // 组件树还活着，所以让它把原生地图整体重建一次，而不是抱着一个死 id。
        if(engineWasWarm)channel.invokeMethod("rehost",null);
    }

    @Override protected void onCreate(Bundle saved){
        StartupTrace.mark("onCreate");
        StartupTrace.install(this);
        UniLog.init(this);
        UniLog.enter(LogTags.APP,"launcher/onCreate");
        rt=LauncherRuntime.get(this);
        // 垃圾清理要读写公开存储：面板一打开就由这里申请权限，界面上没有「去授权」这一步。
        rt.attachPermissionHost(this::requestStoragePermission);
        rt.scheduleBootAutoPlay();
        StartupTrace.mark("runtime");
        rt.scheduleBootLaunch();rt.scheduleWirelessAdb();
        // 歌词投屏是常驻窗口，进程被杀或车机重启后没有任何东西会把它带回来：开关会显示
        // 「已开启」而屏幕上什么都没有。启动时按已存的偏好重新拉起一次服务。
        if(xyz.i4o.uni.launcher.integration.display.ClusterLyricsService.enabled(this))
            xyz.i4o.uni.launcher.integration.display.ClusterLyricsService.refresh(this);
        // Lyric offset + cache policy, then the cache sweep on a worker: neither touches the
        // main thread and both must be in place before the first track reports a position.
        xyz.i4o.uni.launcher.integration.lyrics.LyricOffset.load(this);
        new Thread(() -> {
            long now=System.currentTimeMillis();
            try{xyz.i4o.uni.launcher.integration.lyrics.LyricCachePolicy.sweep(this,now);}
            catch(RuntimeException ignored){}
        },"lyric-cache-sweep").start();
        initialSettings=isSettingsIntent(getIntent());
        super.onCreate(saved);getWindow().addFlags(WindowManager.LayoutParams.FLAG_FULLSCREEN);
        // 隐藏 API 豁免：频谱的次选路径要反射 audioSessionId（公开 SDK 里没有）。
        UniLog.i(LogTags.APP,"隐藏 API 豁免",xyz.i4o.uni.launcher.platform.HiddenApiCompat.tryExempt());
        // Android can create a separate HOME task after a regular app launch.
        // Keep one host/engine so hidden instances cannot retain map displays.
        MainActivity previous=active.get();active=new java.lang.ref.WeakReference<>(this);
        if(previous!=null&&previous!=this&&!previous.isFinishing())previous.finish();
        chrome=new NavigationChrome(this,rt.prefs());
        findViewById(android.R.id.content).addOnLayoutChangeListener((v,l,t,r,b,ol,ot,orr,ob)->{
            if(r-l!=orr-ol||b-t!=ob-ot)v.post(this::publish);
        });
        // 共享引擎接管时 Dart 还在原状态（第几页、设置页都留着），再发一次 home
        // 会把用户正在看的页面打回第一页；只有设置入口和权限请求要重新投递。
        final Intent launchIntent=getIntent();
        if(!engineWasWarm||isSettingsIntent(launchIntent)
            ||launchIntent.getBooleanExtra("uniSpectrumPermission",false))
            dispatchIntent(launchIntent);
        publish();
        StartupTrace.mark("window");
        final android.view.View traceRoot=getWindow().getDecorView();
        traceRoot.getViewTreeObserver().addOnPreDrawListener(new android.view.ViewTreeObserver.OnPreDrawListener(){
            public boolean onPreDraw(){
                traceRoot.getViewTreeObserver().removeOnPreDrawListener(this);
                StartupTrace.mark("firstDraw");
                StartupTrace.summary();
                UniLog.done(LogTags.APP,"launcher/onCreate","settings",initialSettings);
                return true;
            }
        });
    }

    private void updateSnapshot(){
        int a=engineState.cursor.apps,d=engineState.cursor.design,
            m=engineState.cursor.media,s=engineState.cursor.settings;
        // 主窗口始终走带设置目录的快照：设置目录预热完成后由游标补发一次，其余
        // 时间只发分组增量，绝不触发同步扫描。
        JSONObject packet=rt.snapshotWithSettings(engineState.cursor);
        // The settings catalogue is a legitimate large payload; without its cursor
        // here, its first delivery looked like a leak and hid real ones.
        boolean staticIncluded=a!=engineState.cursor.apps||d!=engineState.cursor.design
            ||m!=engineState.cursor.media||s!=engineState.cursor.settings;
        decorate(packet);
        engineState.cached=packet.toString();
        // Invariant: a telemetry-only packet must stay small. If a payload key ever
        // leaks back into the delta pack, say so instead of silently stalling frames.
        if(!staticIncluded&&engineState.cached.length()>65536)
            UniLog.w(LogTags.APP,"遥测包过大，疑似负载泄漏进增量包","chars",engineState.cached.length());
    }

    /** dumpsys --uni-state 专用：用全新游标强制携带全部分组与设置目录。 */
    private void updateSnapshotFull(){
        JSONObject packet=rt.snapshotWithSettings(new LauncherRuntime.StaticCursor());
        decorate(packet);
        engineState.cached=packet.toString();
    }

    /**
     * 首帧快速通道：只读偏好，不构造任何适配器快照。
     *
     * <p>第一帧要的只有外观和卡片布局。以前这一步排在整份 bootstrap 后面，
     * 窗口白屏一直等到快照打包完；现在 Dart 先拿这一包把正确的主题和布局画出来，
     * 完整快照随后补齐车辆、媒体、天气这些随时间变的内容。
     */
    private JSONObject preludeSnapshot(){
        JSONObject packet=rt.prelude();
        try{packet.put("initialSettings",initialSettings);}catch(Exception ignored){}
        return packet;
    }

    private void decorate(JSONObject state){
        try{
            View content=findViewById(android.R.id.content),decor=getWindow().getDecorView();
            WindowInsets insets=decor.getRootWindowInsets();
            boolean alreadyInset=content!=null&&insets!=null&&insets.getSystemWindowInsetBottom()>0&&content.getHeight()>0
                &&content.getHeight()+insets.getSystemWindowInsetBottom()<=decor.getHeight()+1;
            state.put("contentReservesSystemBars",alreadyInset);
            // This firmware sometimes expands content behind its persistent
            // 136px OEM bar after a virtual-display focus change. Stable insets
            // retain the reservation even when content/system insets become 0.
            if(insets!=null&&insets.getStableInsetBottom()>0)reservedBottomPx=insets.getStableInsetBottom();
            if(content!=null&&content.getHeight()>0){
                int usable=content.getHeight();
                android.util.DisplayMetrics real=new android.util.DisplayMetrics();getWindowManager().getDefaultDisplay().getRealMetrics(real);
                if(!rt.prefs().getBoolean("hideNavigation",false)&&!rt.prefs().getBoolean("systemNavigationHidden",false)
                    &&real.heightPixels>reservedBottomPx)
                    usable=Math.min(usable,real.heightPixels-reservedBottomPx);
                if(rt.prefs().getBoolean("globalDockEnabled",false)){
                    usable=Math.min(usable,xyz.i4o.uni.launcher.overlay.WorkspacePolicy.dockTop(this,rt.prefs()));
                }
                state.put("contentHeightPx",content.getHeight()).put("viewportHeightPx",usable).put("reservedBottomPx",reservedBottomPx);
            }
            state.put("initialSettings",initialSettings)
                .put("systemNavigationHidden",rt.prefs().getBoolean("systemNavigationHidden",false))
                .put("systemNavigationGranted",SystemNavigationPolicy.granted(this))
                .put("globalDock",GlobalDockService.snapshot(this));
        }catch(Exception e){UniLog.e(LogTags.APP,"窗口快照失败",e);}
    }

    private void handle(JSONObject request)throws Exception{
        if(GlobalDockService.handleCommand(this,request)){
            if(chrome!=null)chrome.apply();
            publish();return;
        }
        String action=request.optString("action");
        if("calendar-access".equals(action)){
            if(android.os.Build.VERSION.SDK_INT>=23&&checkSelfPermission(android.Manifest.permission.READ_CALENDAR)!=PackageManager.PERMISSION_GRANTED)
                requestPermissions(new String[]{android.Manifest.permission.READ_CALENDAR},4105);
            else rt.publish();
            return;
        }
        if("launch-navigation".equals(action)&&mapHost!=null)mapHost.setVisible(false);
        if("hide-navigation".equals(action)||"global-navigation".equals(action)){
            if("global-navigation".equals(action)&&request.optBoolean("enabled",false)
                &&checkSelfPermission("android.permission.WRITE_SECURE_SETTINGS")!=PackageManager.PERMISSION_GRANTED){
                toast("全局隐藏需要系统授权，当前窗口隐藏仍可使用");return;
            }
            String key="hide-navigation".equals(action)?"hideNavigation":"globalNavigation";
            rt.prefs().edit().putBoolean(key,request.optBoolean("enabled",false)).apply();
            chrome.apply();rt.publish();return;
        }
        // 设置刷新/混音模式由 rt.handle 在后台刷新完成后自行发布；这里不再同步
        // 触发设置目录快照，避免把包扫描搬回主线程。
        rt.handle(request);
    }

    private void publish(){
        if(rt==null)return;
        // updateSnapshot() advances this window's group cursors, so a packet that
        // no sink can receive must not be built at all. Dart only subscribes to
        // the events channel after its bootstrap snapshot, and the deferred app
        // scan usually finishes inside that gap: building the delta there marked
        // apps as delivered, so the badge fell back to the raw package name and
        // the whole app grid stayed empty for the rest of the session.
        if(engineState.sink==null)return;
        updateSnapshot();emit();
    }

    /** Snapshot timestamps are restamped on every read, so a packet would look new
     *  even when nothing moved. Ignoring them keeps the launcher at 0fps while it
     *  is idle instead of rebuilding the whole tree at the publish rate. */
    private static String signature(String packet){
        if(packet==null)return null;
        return packet.replaceAll("\"([A-Za-z]*AtMs|[A-Za-z]*AtElapsedMs)\":-?\\d+","\"t\":0");
    }

    private void emit(){
        if(engineState.sink==null||engineState.cached==null)return;
        String sig=signature(engineState.cached);
        if(sig.equals(engineState.sentSignature))return;
        engineState.sentSignature=sig;
        engineState.sink.success(engineState.cached);
    }

    @Override public void dump(String prefix,java.io.FileDescriptor fd,java.io.PrintWriter writer,String[] args){
        if(args!=null)for(String arg:args)if("--uni-state".equals(arg)){
            // dumpsys is already restricted to Android DUMP callers. Exclude
            // artwork, song text and app icons from this read-only diagnostic.
            try{
                updateSnapshotFull();JSONObject full=new JSONObject(engineState.cached),report=new JSONObject();
                for(String key:new String[]{"version","demo","hideNavigation","systemNavigationHidden","systemNavigationGranted","contentReservesSystemBars","contentHeightPx","viewportHeightPx","reservedBottomPx","desktopSelected","systemStatus","weather","calendar","navigation","vehicle","trafficLights"})report.put(key,full.opt(key));
                JSONObject m=full.optJSONObject("media"),safe=new JSONObject();
                if(m!=null)for(String key:new String[]{"available","authorized","playing","source","preferredPackage","sessions","reason","canToggle","canNext","canPrevious","canSeek","controlSource","lyricsSource","durationMs","positionMs","steeringControlReady","steeringKeys","steeringInject","steeringEnabled","instrumentEnabled","instrumentMetadataReady"})safe.put(key,m.opt(key));
                if(m!=null)safe.put("lyricsAvailable",!m.optString("lyrics").isEmpty()).put("artworkAvailable",!m.optString("artwork").isEmpty()).put("officialMedia",m.optJSONObject("officialMedia"));
                report.put("audioSpectrum",new JSONObject(xyz.i4o.uni.launcher.audio.SpectrumBridge.diagnostics()));
                if(ambientBridge!=null)report.put("ambientLight",new JSONObject(ambientBridge.status()));
                report.put("media",safe).put("flutterViewport",engineState.flutterViewport).put("globalDock",GlobalDockService.snapshot(this)).put("systemSettings",full.opt("systemSettings"));
                if(mapHost!=null)report.put("mapViews",mapHost.snapshot());
                writer.println("UNI_STATE="+report.toString());
            }catch(Exception e){writer.println("UNI_STATE_UNAVAILABLE");}return;
        }
        super.dump(prefix,fd,writer,args);
    }

    private void toast(String text){Toast.makeText(this,text,Toast.LENGTH_SHORT).show();}

    @Override protected void onStart(){
        super.onStart();
        UniLog.enter(LogTags.APP,"launcher/onStart");
        // Reconcile stale legacy UNI policy after upgrades even when the global
        // dock is off; both switches keep their own persisted state.
        SystemNavigationPolicy.setHidden(this,rt.prefs(),rt.prefs().getBoolean("systemNavigationHidden",false));
        if(chrome!=null)chrome.apply();
        rt.setHomeVisible(true);rt.addListener(this,this::publish);
        if(mapHost!=null)mapHost.setVisible(true);
        publish();
    }

    @Override protected void onResume(){
        LauncherVisibility.set(true);
        super.onResume();if(chrome!=null)chrome.apply();
        OtaBootReceiver.scheduleLauncherBroadcasts(this);
        GlobalDockService.ensureStarted(this);publish();
        UniLog.done(LogTags.APP,"launcher/onResume");
    }

    @Override protected void onStop(){
        LauncherVisibility.set(false);
        if(rt!=null){
            // A superseded HOME activity must not hide its replacement's dock.
            if(active.get()==this)rt.setHomeVisible(false);
            rt.removeListener(this);
        }
        if(mapHost!=null)mapHost.setVisible(false);
        super.onStop();
        UniLog.enter(LogTags.APP,"launcher/onStop");
    }

    @Override public void onWindowFocusChanged(boolean focus){super.onWindowFocusChanged(focus);if(focus&&chrome!=null)chrome.apply();}

    /**
     * 车机有时把媒体键当普通按键派发给当前窗口，而不是走 MediaSession 路由。
     * 这类按键交给媒体适配层（按动作分组与方控输入通道折叠，不会切两次）。
     */
    @Override public boolean dispatchKeyEvent(android.view.KeyEvent event){
        if(event!=null&&event.getAction()==android.view.KeyEvent.ACTION_DOWN&&event.getRepeatCount()==0
            &&rt!=null&&rt.dispatchSteeringKey(event.getKeyCode(),"window"))return true;
        return super.dispatchKeyEvent(event);
    }
    @Override public void onConfigurationChanged(Configuration c){super.onConfigurationChanged(c);UniLog.event(LogTags.APP,"配置变化", "orientation", c.orientation);publish();}
    @Override public void onRequestPermissionsResult(int requestCode,String[] permissions,int[] results){
        super.onRequestPermissionsResult(requestCode,permissions,results);
        // 权限回调是「频谱/日历到底能不能用」的第一现场，结果必须落盘：
        // 否则诊断包里只能看到「频谱没数据」，看不到「权限被拒」。
        UniLog.i(LogTags.APP,"权限回调","requestCode",requestCode,"permissions",java.util.Arrays.toString(permissions),"results",java.util.Arrays.toString(results));
        if(requestCode==4106)xyz.i4o.uni.launcher.audio.SpectrumBridge.permissionChanged();if(requestCode==4105){try{rt.handle(new JSONObject().put("action","calendar-refresh"));}catch(Exception ignored){}publish();}
        if(requestCode==REQUEST_STORAGE){
            // 存储权限的结果要交回给发起方：界面在等它，才知道能不能导出。
            java.util.function.Consumer<Boolean> done=pendingStorage;pendingStorage=null;
            if(done!=null){
                boolean writable=storageWritable(this),readable=storageReadable(this);
                UniLog.i(LogTags.APP,"存储权限回调","writable",writable,"readable",readable);
                done.accept(writable);
            }
            // 垃圾清理面板等同一个回调：能写就重扫一次，写不了由面板如实显示不可用。
            try{rt.handle(new JSONObject().put("action","cleaner-permission"));}catch(Exception ignored){}
            publish();
        }
    }

    @Override protected void onActivityResult(int requestCode,int resultCode,Intent data){
        super.onActivityResult(requestCode,resultCode,data);
        if(requestCode!=PICK_WALLPAPER)return;
        MethodChannel.Result pending=wallpaperResult;wallpaperResult=null;
        if(pending==null)return;
        if(resultCode!=Activity.RESULT_OK||data==null){pending.success(null);return;}
        String path=data.getStringExtra("wallpaperPath");
        final Uri uri=path==null?data.getData():Uri.fromFile(new File(path));
        if(uri==null){pending.success(null);return;}
        // 解码/缩放/压缩/亮度全部移出主线程，避免大图导入阻塞第一帧或界面。
        new Thread(()->{
            try{
                Map<String,Object> result=importWallpaper(uri);
                runOnUiThread(()->{try{pending.success(result);}catch(Exception ignored){}});
            }catch(Exception|OutOfMemoryError e){
                UniLog.w(LogTags.WALLPAPER,"壁纸导入失败",e);
                runOnUiThread(()->{try{pending.error("invalid-image","无法读取这张图片",null);}catch(Exception ignored){}});
            }
        },"uni-wallpaper").start();
    }

    private Map<String,Object> importWallpaper(Uri uri)throws Exception{
        final int targetW=1920,targetH=1080;
        BitmapFactory.Options bounds=new BitmapFactory.Options();bounds.inJustDecodeBounds=true;
        try(InputStream in=getContentResolver().openInputStream(uri)){BitmapFactory.decodeStream(in,null,bounds);}
        if(bounds.outWidth<=0||bounds.outHeight<=0)throw new IllegalArgumentException("Invalid image");
        final int W=bounds.outWidth,H=bounds.outHeight;
        // 中心裁剪区域（源图坐标）：只解码需要的部分，长图不再放大成超大中间位图。
        float cropScale=Math.max(targetW/(float)W,targetH/(float)H);
        int regionW=Math.max(1,Math.min(W,Math.round(targetW/cropScale)));
        int regionH=Math.max(1,Math.min(H,Math.round(targetH/cropScale)));
        int regionX=(W-regionW)/2,regionY=(H-regionH)/2;
        Bitmap source=null;android.graphics.Rect srcRect=null;
        try(InputStream in=getContentResolver().openInputStream(uri)){
            try{
                int sample=1;while(regionW/sample>targetW*2||regionH/sample>targetH*2)sample*=2;
                BitmapFactory.Options opts=new BitmapFactory.Options();opts.inSampleSize=sample;opts.inPreferredConfig=Bitmap.Config.ARGB_8888;
                android.graphics.BitmapRegionDecoder decoder=android.graphics.BitmapRegionDecoder.newInstance(in,false);
                try{source=decoder.decodeRegion(new android.graphics.Rect(regionX,regionY,regionX+regionW,regionY+regionH),opts);}
                finally{decoder.recycle();}
                if(source!=null)srcRect=new android.graphics.Rect(0,0,source.getWidth(),source.getHeight());
            }catch(Exception regionUnsupported){source=null;}
        }
        if(source==null){
            // 兜底：限制整图解码面积后，再中心裁剪绘制。
            int sample=1;while(W/sample>4096||H/sample>4096)sample*=2;
            BitmapFactory.Options opts=new BitmapFactory.Options();opts.inSampleSize=sample;opts.inPreferredConfig=Bitmap.Config.ARGB_8888;
            try(InputStream in=getContentResolver().openInputStream(uri)){source=BitmapFactory.decodeStream(in,null,opts);}
            if(source==null)throw new IllegalArgumentException("Unsupported image");
            float scale=Math.max(targetW/(float)source.getWidth(),targetH/(float)source.getHeight());
            int srcW=Math.max(1,Math.round(targetW/scale)),srcH=Math.max(1,Math.round(targetH/scale));
            int srcX=(source.getWidth()-srcW)/2,srcY=(source.getHeight()-srcH)/2;
            srcRect=new android.graphics.Rect(srcX,srcY,srcX+srcW,srcY+srcH);
        }
        // 直接把源图所需区域绘制到固定 1920×1080 目标位图，不产生中间放大位图。
        Bitmap cropped=Bitmap.createBitmap(targetW,targetH,Bitmap.Config.ARGB_8888);
        new android.graphics.Canvas(cropped).drawBitmap(source,srcRect,new android.graphics.Rect(0,0,targetW,targetH),null);
        source.recycle();
        File dir=new File(getFilesDir(),"wallpapers");if(!dir.exists()&&!dir.mkdirs())throw new IllegalStateException("Cannot create wallpaper directory");
        File out=new File(dir,"custom-"+System.currentTimeMillis()+".jpg");
        try(FileOutputStream stream=new FileOutputStream(out)){if(!cropped.compress(Bitmap.CompressFormat.JPEG,90,stream))throw new IllegalStateException("Cannot encode image");}
        Bitmap sampleBitmap=Bitmap.createScaledBitmap(cropped,32,18,true);
        double luminance=0;
        for(int y=0;y<sampleBitmap.getHeight();y++)for(int x=0;x<sampleBitmap.getWidth();x++){
            int color=sampleBitmap.getPixel(x,y);
            luminance+=(0.2126*android.graphics.Color.red(color)+0.7152*android.graphics.Color.green(color)+0.0722*android.graphics.Color.blue(color))/255.0;
        }
        luminance/=sampleBitmap.getWidth()*sampleBitmap.getHeight();
        sampleBitmap.recycle();
        File[] old=dir.listFiles();if(old!=null)for(File file:old)if(!file.equals(out)&&file.getName().startsWith("custom-"))file.delete();
        cropped.recycle();
        Map<String,Object> result=new HashMap<>();result.put("path",out.getAbsolutePath());result.put("luminance",luminance);return result;
    }

    public static void requestAudioSpectrumPermission(android.content.Context context){
        MainActivity owner=active.get();
        if(owner!=null&&owner.hasWindowFocus()){
            owner.requestPermissions(new String[]{android.Manifest.permission.RECORD_AUDIO},4106);
        }else context.startActivity(new Intent(context,MainActivity.class).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK).putExtra("uniSpectrumPermission",true));
    }

    /**
     * 垃圾清理的存储权限。UNI 桌面的 signature|privileged 权限随平台签名自动授予，
     * 只剩 WRITE_EXTERNAL_STORAGE 这类 dangerous 权限要过一次系统弹窗；面板打开时
     * 直接请求，用户不应该看到「去授权」再跳设置页。
     */
    public void requestStoragePermission(){
        if(android.os.Build.VERSION.SDK_INT>=23
            &&checkSelfPermission(android.Manifest.permission.WRITE_EXTERNAL_STORAGE)!=PackageManager.PERMISSION_GRANTED){
            requestPermissions(new String[]{android.Manifest.permission.WRITE_EXTERNAL_STORAGE},REQUEST_STORAGE);
        }else if(rt!=null){
            // 权限本来就有（例如平台签名已授予或用户授权过），直接让清理器重扫一次。
            try{rt.handle(new JSONObject().put("action","cleaner-permission"));}catch(Exception ignored){}
            publish();
        }
    }
    private boolean isSettingsIntent(Intent intent){
        return intent!=null&&(intent.getBooleanExtra("uniSettings",false)||
            (intent.getComponent()!=null&&"xyz.i4o.uni.launcher.DesktopSettings".equals(intent.getComponent().getClassName())));
    }
    /** Channel numbers arrive as Integer, Double or String depending on the caller. */
    private static int number(Object value,int fallback){
        if(value instanceof Number)return ((Number)value).intValue();
        if(value instanceof CharSequence){
            try{return (int)Math.round(Double.parseDouble(value.toString().trim()));}
            catch(NumberFormatException ignored){return fallback;}
        }
        return fallback;
    }
    private void dispatchIntent(Intent intent){
        // 桌面入口有两种：回到桌面 / 直接进设置。分不清是哪一种时，
        // 「用户点了没反应」和「点了进错地方」都很难查，这里明确记一笔。
        boolean settings=isSettingsIntent(intent);
        UniLog.event(LogTags.APP,"分发入口请求","target",settings?"settings":"home");
        if(intent!=null&&intent.getBooleanExtra("uniSpectrumPermission",false)){
            getWindow().getDecorView().post(()->requestPermissions(new String[]{android.Manifest.permission.RECORD_AUDIO},4106));
            intent.removeExtra("uniSpectrumPermission");
        }
        if(channel!=null)channel.invokeMethod(settings?"open-settings":"home",null);
    }

    @Override protected void onNewIntent(Intent intent){
        super.onNewIntent(intent);setIntent(intent);
        initialSettings=isSettingsIntent(intent);
        dispatchIntent(intent);publish();
    }

    @Override protected void onDestroy(){
        UniLog.enter(LogTags.APP,"launcher/onDestroy");
        if(wallpaperResult!=null){wallpaperResult.success(null);wallpaperResult=null;}
        if(rt!=null)rt.removeListener(this);
        if(mapHost!=null)mapHost.close();
        if(spectrumBridge!=null){spectrumBridge.close();spectrumBridge=null;}
        if(ambientBridge!=null){ambientBridge.close();ambientBridge=null;}
        // 共享引擎这一侧：通道、事件流和游标都属于引擎（Dart isolate 还在跑），
        // 在这里清掉就等于把下一个窗口的更新掐断。只有本窗口独占引擎时，这次
        // onDestroy 才是真正的一次销毁。
        if(ownsEngine){
            if(channel!=null)channel.setMethodCallHandler(null);
            otaEvents=null;
            if(events!=null)events.setStreamHandler(null);
            engineState.reset();
        }
        if(active.get()==this)active.clear();
        // 真正退出（不是重建）才把进程级引擎一起放掉，避免一个不会再有人接管的
        // isolate 长期占着内存和定时器。
        if(!ownsEngine&&isFinishing()&&active.get()==null)releaseSharedEngine();
        super.onDestroy();
    }

    /** 释放进程级主引擎；只在没有窗口会再接管时调用。 */
    private static void releaseSharedEngine(){
        FlutterEngine engine;
        synchronized(MainActivity.class){
            engine=sharedEngine;sharedEngine=null;sharedState=new EngineState();
        }
        if(engine!=null)engine.destroy();
    }
}
