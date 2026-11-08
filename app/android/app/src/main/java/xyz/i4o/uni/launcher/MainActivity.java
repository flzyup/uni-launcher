package xyz.i4o.uni.launcher;

import android.content.ComponentName;
import android.content.Context;
import android.content.Intent;
import android.app.Activity;
import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import android.net.Uri;
import android.content.pm.PackageManager;
import android.content.pm.ResolveInfo;
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
import java.util.List;
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
    /** 切走时抓下的最后一帧；切回时先贴上去，Flutter 画好再撤（见 installResumeSnapshot）。 */
    private android.widget.ImageView resumeSnapshot;
    private android.graphics.Bitmap snapshotBitmap;

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
    /** 任何入口切往全屏导航前先关闭内嵌宿主可见态，阻止 verifyPlacement 把已迁回主屏的导航栈拉回虚拟屏。 */
    public static void hideEmbeddedNavigation(){
        MainActivity a=active.get();
        if(a!=null)a.runOnUiThread(()->{if(a.mapHost!=null)a.mapHost.setVisible(false);});
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
                    StartupTrace.mark("prelude");
                    result.success(preludeSnapshot());
                    initialSettings=false;
                }
                // Dart 侧回填「桌面内容首帧」：native 只到窗口首绘，用户真正看到
                // 桌面是这一帧，冷启动的总账要打在这里。
                else if("mark".equals(call.method)){
                    String label=call.arguments instanceof CharSequence?call.arguments.toString():"";
                    if(label.startsWith("launcherContent")){StartupTrace.mark(label);StartupTrace.summary();}
                    else if(!label.isEmpty())StartupTrace.mark(label);
                    result.success(null);
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
                    if(candidate==null||!getPackageName().equals(candidate.packageName)||candidate.versionCode<=installed.versionCode||installed.signatures==null||candidate.signatures==null||!java.util.Arrays.equals(installed.signatures,candidate.signatures)){
                        result.success("invalid-package");
                    }else if(android.os.Build.VERSION.SDK_INT>=26&&!getPackageManager().canRequestPackageInstalls()){
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
        // 越早越好：FlutterActivity 等一下会在自己的 onCreate 里 setTheme(NormalTheme)
        // 并装上 FlutterView，之后 window 的背景就交给主题了。提前给我们自己的
        // drawable，PhoneWindow 会保留它，Flutter 首帧之前露出的就不是白色。
        applyBootCanvas();
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
                // 汇总等 Dart 回报 launcherContent（桌面真的画出来）再做；
                // 这里只兜底：Dart 起不来时 3 秒后按首绘结账，统计不能缺。
                traceRoot.postDelayed(StartupTrace::summary,3000);
                UniLog.done(LogTags.APP,"launcher/onCreate","settings",initialSettings);
                return true;
            }
        });
        installResumeSnapshot();
    }

    /**
     * 切回桌面时的「秒开」覆盖层。
     *
     * <p>Flutter 的绘制走 {@code FlutterSurfaceView}，窗口被遮住时系统会把那块
     * surface 收走；切回来要重建 GrContext、把所有纹理重新上传、再整屏重绘。
     * 820A 上实测这一段是 500–800 ms —— 而原厂桌面是原生 View，切回只是合成
     * 已有的 buffer。差别不在代码写得好不好，在渲染架构。
     *
     * <p>所以换个思路：切走时用 {@link android.view.PixelCopy} 抓一张当前画面存着，
     * 切回来先把它贴在最上层。用户看到的是「立刻回到走之前的样子」，真正的
     * Flutter 帧画好之后再撤掉。视觉上是 0 ms，代价是一张半分辨率的截图。
     */
    private void installResumeSnapshot(){
        if(android.os.Build.VERSION.SDK_INT<26)return;  // PixelCopy 从 O 开始
        resumeSnapshot=new android.widget.ImageView(this);
        resumeSnapshot.setScaleType(android.widget.ImageView.ScaleType.FIT_XY);
        resumeSnapshot.setVisibility(android.view.View.GONE);
        resumeSnapshot.setClickable(false);
        resumeSnapshot.setFocusable(false);
        resumeSnapshot.setImportantForAccessibility(android.view.View.IMPORTANT_FOR_ACCESSIBILITY_NO);
        addContentView(resumeSnapshot,new android.view.ViewGroup.LayoutParams(
            android.view.ViewGroup.LayoutParams.MATCH_PARENT,
            android.view.ViewGroup.LayoutParams.MATCH_PARENT));
    }

    /** 窗口还完整可见时抓帧；失败就当作没有快照，切回走原来的路径。 */
    private void captureResumeSnapshot(){
        // 车机 Android 9（API 28）在含有 VirtualDisplay 地图与 Flutter 纹理合成的窗口上，
        // PixelCopy 会触发底层 OpenGL 的 glReadPixels 报错 GL_INVALID_OPERATION (0x502)，
        // 进而引发 libhwui assert 抛出 SIGABRT 崩溃。车机环境下跳过截图，回切依靠 Flutter 热引擎自然恢复。
        if(android.os.Build.VERSION.SDK_INT<=28)return;
        if(resumeSnapshot==null)return;
        final android.view.View root=getWindow().getDecorView();
        final int w=root.getWidth(),h=root.getHeight();
        if(w<=0||h<=0)return;
        // PixelCopy 要求目标位图与源区域等尺寸，所以不能先缩小再抓；RGB_565 已经
        // 把这块从 8 MB 压到 4 MB，够用就行 —— 它只是一张过渡用的静态图。
        final android.graphics.Bitmap shot;
        try{shot=android.graphics.Bitmap.createBitmap(w,h,android.graphics.Bitmap.Config.RGB_565);}
        catch(OutOfMemoryError e){return;}
        try{
            android.view.PixelCopy.request(getWindow(),shot,result->{
                if(result!=android.view.PixelCopy.SUCCESS){shot.recycle();return;}
                android.graphics.Bitmap previous=snapshotBitmap;
                snapshotBitmap=shot;
                if(previous!=null&&!previous.isRecycled())previous.recycle();
            },new android.os.Handler(android.os.Looper.getMainLooper()));
        }catch(RuntimeException e){
            UniLog.w(LogTags.APP,"切回快照抓帧失败",e,"reason",e.getClass().getSimpleName());
        }
    }

    private void showResumeSnapshot(){
        if(resumeSnapshot==null||snapshotBitmap==null||snapshotBitmap.isRecycled())return;
        resumeSnapshot.setImageBitmap(snapshotBitmap);
        resumeSnapshot.setVisibility(android.view.View.VISIBLE);
        resumeSnapshot.bringToFront();
        // 兜底：某些情况下 Flutter 不会再回调「UI 已显示」（比如它一直认为自己
        // 还在显示），到点就撤，免得静态图把界面永久盖住。
        resumeSnapshot.removeCallbacks(hideResumeSnapshot);
        resumeSnapshot.postDelayed(hideResumeSnapshot,1200);
    }

    private final Runnable hideResumeSnapshot=new Runnable(){
        public void run(){
            if(resumeSnapshot==null)return;
            if(resumeSnapshot.getVisibility()!=android.view.View.VISIBLE)return;
            resumeSnapshot.setVisibility(android.view.View.GONE);
            UniLog.d(LogTags.APP,"切回快照已撤下","reason","fallback-timeout");
        }
    };

    /** Flutter 真正画出这一帧之后才撤覆盖层，顺序不能反。 */
    private final io.flutter.embedding.engine.renderer.FlutterUiDisplayListener resumeUiShown=
        new io.flutter.embedding.engine.renderer.FlutterUiDisplayListener(){
            @Override public void onFlutterUiDisplayed(){
                if(resumeSnapshot==null)return;
                resumeSnapshot.removeCallbacks(hideResumeSnapshot);
                if(resumeSnapshot.getVisibility()==android.view.View.VISIBLE){
                    resumeSnapshot.setVisibility(android.view.View.GONE);
                    UniLog.d(LogTags.APP,"切回快照已撤下","reason","first-frame");
                }
            }
            @Override public void onFlutterUiNoLongerDisplayed(){}
        };

    /**
     * 启动窗口底色跟随上次保存的外观。
     *
     * <p>窗口在进程启动时就已经被系统画出来了（starting window 用 LaunchTheme
     * 的 windowBackground），那一段只能靠资源兜底；这里管的是紧接着的一段：
     * {@code NormalTheme} 接管之后、Flutter 首帧之前露出的那块窗口底色。
     * 以前它是 {@code ?android:colorBackground}（浅色主题下纯白），现在换成
     * 上次外观真实的画布色，浅色用户不会再看到「深→白→浅」的三段闪烁。
     */
    private void applyBootCanvas(){
        try{
            final int argb=LauncherRuntime.bootCanvasArgb(this);
            getWindow().setBackgroundDrawable(new android.graphics.drawable.ColorDrawable(argb));
            // 落一条日志：启动白屏的排查只看这一行 —— 它必须等于上次外观的画布色，
            // 而不是 0xFFFFFFFF。
            UniLog.i(LogTags.APP,"启动底色","argb",String.format(java.util.Locale.US,"#%08X",argb));
        }catch(RuntimeException ignored){
            // 拿不到 window 时保持主题里的深色兜底，启动不能因此失败。
        }
    }

    private void updateSnapshot(){
        int a=engineState.cursor.apps,d=engineState.cursor.design,
            m=engineState.cursor.media,s=engineState.cursor.settings;
        // 主窗口始终走带设置目录的快照：设置目录预热完成后由游标补发一次，其余
        // 时间只发分组增量，绝不触发同步扫描。
        long s0=android.os.SystemClock.elapsedRealtimeNanos();
        JSONObject packet=rt.snapshotWithSettings(engineState.cursor);
        long s1=android.os.SystemClock.elapsedRealtimeNanos();
        // The settings catalogue is a legitimate large payload; without its cursor
        // here, its first delivery looked like a leak and hid real ones.
        boolean staticIncluded=a!=engineState.cursor.apps||d!=engineState.cursor.design
            ||m!=engineState.cursor.media||s!=engineState.cursor.settings;
        decorate(packet);
        long s2=android.os.SystemClock.elapsedRealtimeNanos();
        engineState.cached=packet.toString();
        long s3=android.os.SystemClock.elapsedRealtimeNanos();
        splitBuildMs=(s1-s0)/1000000L;splitDecorateMs=(s2-s1)/1000000L;splitStringMs=(s3-s2)/1000000L;
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

    /**
     * 窗口投影：insets / 显示指标 / 权限 / 悬浮坞状态。
     *
     * <p>只缓存**真的贵且几乎不变**的两项：悬浮窗权限（AppOps → system_server）
     * 和显示指标。insets、content 高度、悬浮坞的 expanded/panelReady 这些是本地
     * 字段读，每次现算 —— 它们有独立的发布路径（{@code GlobalDockService} 自己的
     * 发射口），缓存了就会出现「面板已经开了、主窗口还认为没开」且之后不再发
     * 新包、永远停在旧值的那种坏死状态。
     */
    private JSONObject decorate(JSONObject state){
        long d0=android.os.SystemClock.elapsedRealtimeNanos();
        try{
            View content=findViewById(android.R.id.content),decor=getWindow().getDecorView();
            WindowInsets insets=decor.getRootWindowInsets();
            long d1=android.os.SystemClock.elapsedRealtimeNanos();
            boolean alreadyInset=content!=null&&insets!=null&&insets.getSystemWindowInsetBottom()>0&&content.getHeight()>0
                &&content.getHeight()+insets.getSystemWindowInsetBottom()<=decor.getHeight()+1;
            state.put("contentReservesSystemBars",alreadyInset);
            // This firmware sometimes expands content behind its persistent
            // 136px OEM bar after a virtual-display focus change. Stable insets
            // retain the reservation even when content/system insets become 0.
            if(insets!=null&&insets.getStableInsetBottom()>0)reservedBottomPx=insets.getStableInsetBottom();
            if(content!=null&&content.getHeight()>0){
                int usable=content.getHeight();
                android.util.DisplayMetrics real=realMetrics();
                if(!rt.prefs().getBoolean("hideNavigation",false)&&!rt.prefs().getBoolean("systemNavigationHidden",false)
                    &&real.heightPixels>reservedBottomPx)
                    usable=Math.min(usable,real.heightPixels-reservedBottomPx);
                if(rt.prefs().getBoolean("globalDockEnabled",false)){
                    usable=Math.min(usable,xyz.i4o.uni.launcher.overlay.WorkspacePolicy.dockTop(this,rt.prefs()));
                }
                state.put("contentHeightPx",content.getHeight()).put("viewportHeightPx",usable).put("reservedBottomPx",reservedBottomPx);
            }
            long d2=android.os.SystemClock.elapsedRealtimeNanos();
            state.put("initialSettings",initialSettings)
                .put("systemNavigationHidden",rt.prefs().getBoolean("systemNavigationHidden",false))
                .put("systemNavigationGranted",navGranted())
                .put("globalDock",GlobalDockService.snapshot(this,overlayAllowed()));
            long d3=android.os.SystemClock.elapsedRealtimeNanos();
            splitInsetsMs=(d1-d0)/1000000L;splitGeometryMs=(d2-d1)/1000000L;splitDockMs=(d3-d2)/1000000L;
        }catch(Exception e){UniLog.e(LogTags.APP,"窗口快照失败",e);}
        return state;
    }

    /** AppOps 查询按 2 秒复用：只有用户去系统设置授权才会变。 */
    private Boolean overlayAllowed(){
        long now=android.os.SystemClock.elapsedRealtime();
        if(overlayAllowed==null||now-overlayAllowedAt>=PERMISSION_CACHE_MS){
            overlayAllowed=android.provider.Settings.canDrawOverlays(this);overlayAllowedAt=now;
        }
        return overlayAllowed;
    }

    private android.util.DisplayMetrics realMetrics(){
        long now=android.os.SystemClock.elapsedRealtime();
        if(realMetrics==null||now-realMetricsAt>=WINDOW_PROJECTION_TTL_MS){
            android.util.DisplayMetrics metrics=new android.util.DisplayMetrics();
            getWindowManager().getDefaultDisplay().getRealMetrics(metrics);
            realMetrics=metrics;realMetricsAt=now;
        }
        return realMetrics;
    }

    /** WRITE_SECURE_SETTINGS 的查询同样按 2 秒复用：它只在装机/授权时变。 */
    private Boolean navGrantedCache;private long navGrantedAt;
    /** 上一包 decorate 的三段：insets 读取 / 几何计算 / 悬浮坞快照。 */
    private long splitInsetsMs,splitGeometryMs,splitDockMs;

    private boolean navGranted(){
        long now=android.os.SystemClock.elapsedRealtime();
        if(navGrantedCache==null||now-navGrantedAt>=PERMISSION_CACHE_MS){
            navGrantedCache=SystemNavigationPolicy.granted(this);navGrantedAt=now;
        }
        return navGrantedCache;
    }

    /** 权限/显示指标缓存作废；调用点在窗口、配置或用户命令可能改了它们的每一处。 */
    private void invalidateWindowCaches(){overlayAllowed=null;realMetrics=null;navGrantedCache=null;}

    private void handle(JSONObject request)throws Exception{
        // 用户操作可能改掉窗口投影里的东西（隐藏导航栏、悬浮坞开关、系统设置
        // 刷新），缓存必须先失效，否则那一次发布带回去还是旧值，界面不会自己
        // 再变第二次。
        invalidateWindowCaches();
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

    /**
     * 请求一次窗口快照，同一轮主线程消息内只真正打一次包。
     *
     * <p>一次「从第三方应用返回桌面」以前会连打三到四次全量 JSON：onNewIntent、
     * onStart 里 setHomeVisible 的、onStart 末尾显式的、onResume 的，外加 content
     * 布局变化那一次。它们的内容几乎完全相同，后面几次全靠 signature 去重才没把
     * 多余的包发出去 —— 但打包本身（buildSnapshot 在主线程组装 JSON）是实打实做了
     * 三遍。这里只置一次排程标志，落在一轮消息之后执行，重复请求直接合并。
     */
    private void publish(){
        if(rt==null)return;
        // updateSnapshot() advances this window's group cursors, so a packet that
        // no sink can receive must not be built at all. Dart only subscribes to
        // the events channel after its bootstrap snapshot, and the deferred app
        // scan usually finishes inside that gap: building the delta there marked
        // apps as delivered, so the badge fell back to the raw package name and
        // the whole app grid stayed empty for the rest of the session.
        if(engineState.sink==null)return;
        if(snapshotQueued)return;
        snapshotQueued=true;
        // 排到主线程 Handler 而不是某个 View 上：View.post 在窗口 detach 时
        // 会丢消息，标志就永远停在 true，之后的快照全部被吞掉。
        ui.post(snapshotRun);
    }

    private boolean snapshotQueued;
    private final android.os.Handler ui=new android.os.Handler(android.os.Looper.getMainLooper());
    private int packetCount;private long packetMs,packetWorstMs,packetWindowAt;
    private long updateMsSum,emitMsSum;
    /** 上一包的拆解：JSON 组装 / 窗口装饰 / 序列化，慢的时候直接看这三个。 */
    private long splitBuildMs,splitDecorateMs,splitStringMs;
    private Boolean overlayAllowed;private long overlayAllowedAt;
    private android.util.DisplayMetrics realMetrics;private long realMetricsAt;
    private static final long WINDOW_PROJECTION_TTL_MS=2000;
    /** 权限类结果只随「用户去系统设置授权」变，而那条路一定经过 onResume，
     *  所以按 60 秒兜底、靠 invalidateWindowCaches() 精确失效就够了 —— 
     *  2 秒的 TTL 在 15 秒一包的实际节奏下等于每次都失效，白付 IPC。 */
    private static final long PERMISSION_CACHE_MS=60000;
    private final Runnable snapshotRun=()->{
        snapshotQueued=false;
        if(rt==null||engineState.sink==null)return;
        long t0=android.os.SystemClock.elapsedRealtimeNanos();
        updateSnapshot();
        long tMid=android.os.SystemClock.elapsedRealtimeNanos();
        emit();
        long t1=android.os.SystemClock.elapsedRealtimeNanos();
        long ms=(t1-t0)/1000000L,updateMs=(tMid-t0)/1000000L,emitMs=(t1-tMid)/1000000L;
        // 这段是主线程上的 JSON 组装，返回桌面那一下卡不卡，账都在这里。
        // 逐包留痕会自己变成噪声（这一行要格式化再写 logd，慢机器上几毫秒），
        // 所以只记 32ms 以上的单包，另外每 30 秒汇总一行：包数、均值、最差
        // ——「空闲时到底拼了几次快照」一眼可见。
        packetCount++;packetMs+=ms;updateMsSum+=updateMs;emitMsSum+=emitMs;
        if(ms>packetWorstMs)packetWorstMs=ms;
        if(ms>=32)UniLog.d(LogTags.APP,"快照打包耗时","ms",ms,"updateMs",updateMs,"emitMs",emitMs,
            "buildMs",splitBuildMs,"decorateMs",splitDecorateMs,"stringMs",splitStringMs,
            "insetsMs",splitInsetsMs,"geomMs",splitGeometryMs,"dockMs",splitDockMs,
            "chars",engineState.cached==null?0:engineState.cached.length());
        long now=android.os.SystemClock.elapsedRealtime();
        if(packetWindowAt==0)packetWindowAt=now;
        else if(now-packetWindowAt>=30000){
            int n=Math.max(1,packetCount);
            UniLog.d(LogTags.APP,"快照节流","packets",packetCount,"avgMs",packetMs/n,
                "updateMs",updateMsSum/n,"emitMs",emitMsSum/n,
                "worstMs",packetWorstMs);
            packetCount=0;packetMs=0;packetWorstMs=0;updateMsSum=0;emitMsSum=0;packetWindowAt=now;
        }
    };

    private static final java.util.regex.Pattern SIGNATURE_TIMESTAMPS=
        java.util.regex.Pattern.compile("\"([A-Za-z]*AtMs|[A-Za-z]*AtElapsedMs|sourceTimestampNanos|ageMs)\":-?\\d+");

    /** Snapshot timestamps are restamped on every read, so a packet would look new
     *  even when nothing moved. Ignoring them keeps the launcher at 0fps while it
     *  is idle instead of rebuilding the whole tree at the publish rate. */
    private static String signature(String packet){
        if(packet==null)return null;
        return SIGNATURE_TIMESTAMPS.matcher(packet).replaceAll("\"t\":0");
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
                if(m!=null)for(String key:new String[]{"available","authorized","playing","source","preferredPackage","sessions","reason","canToggle","canNext","canPrevious","canSeek","controlSource","lyricsSource","durationMs","positionMs","steeringControlReady","steeringKeys","steeringInject","steeringIdleDrops","dimCluster","dimClusterEnabled","transportEffect","steeringEnabled","instrumentEnabled","instrumentMetadataReady"})safe.put(key,m.opt(key));
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
        UniLog.enter(LogTags.APP,"launcher/onStart","at",System.currentTimeMillis());
        // 先把上一次离开时的画面贴上去，再让 Flutter 慢慢重绘 —— 顺序不能反。
        showResumeSnapshot();
        if(getFlutterEngine()!=null)
            getFlutterEngine().getRenderer().addIsDisplayingFlutterUiListener(resumeUiShown);
        // Reconcile stale legacy UNI policy after upgrades even when the global
        // dock is off; both switches keep their own persisted state.
        SystemNavigationPolicy.setHidden(this,rt.prefs(),rt.prefs().getBoolean("systemNavigationHidden",false));
        if(chrome!=null)chrome.apply();
        GlobalDockService.resumeDockForExternalHome();
        rt.setHomeVisible(true);rt.addListener(this,this::publish);
        if(mapHost!=null)mapHost.setVisible(true);
        // 这里不再显式 publish()：addListener / setHomeVisible 已经在同一轮主线程
        // 消息里排好了快照，onResume 紧接着还会再排一次。多打一次包只是把同一份
        // JSON 在主线程上再组装一遍。
    }

    @Override protected void onPause(){
        // 窗口还在最上层时抓这一帧；等到 onStop 就已经被下一个应用盖住了。
        captureResumeSnapshot();
        super.onPause();
    }

    @Override protected void onResume(){
        LauncherVisibility.set(true);
        // 从别的应用回桌面时窗口/权限/坞状态可能已经变了，投影缓存先作废。
        invalidateWindowCaches();
        super.onResume();if(chrome!=null)chrome.apply();
        OtaBootReceiver.scheduleLauncherBroadcasts(this);
        GlobalDockService.ensureStarted(this);publish();
        UniLog.done(LogTags.APP,"launcher/onResume","at",System.currentTimeMillis());
    }

    @Override protected void onStop(){
        LauncherVisibility.set(false);
        if(rt!=null){
            // A superseded HOME activity must not hide its replacement's dock.
            if(active.get()==this)rt.setHomeVisible(false);
            rt.removeListener(this);
        }
        if(mapHost!=null)mapHost.setVisible(false);
        if(getFlutterEngine()!=null)
            getFlutterEngine().getRenderer().removeIsDisplayingFlutterUiListener(resumeUiShown);
        super.onStop();
        UniLog.enter(LogTags.APP,"launcher/onStop");
    }

    @Override public void onWindowFocusChanged(boolean focus){super.onWindowFocusChanged(focus);if(focus&&chrome!=null)chrome.apply();}

    @Override public boolean dispatchTouchEvent(android.view.MotionEvent ev){
        if(ev!=null){
            int action=ev.getActionMasked();
            xyz.i4o.uni.launcher.audio.SpectrumBridge.notifyMapTouch(
                action!=android.view.MotionEvent.ACTION_UP&&action!=android.view.MotionEvent.ACTION_CANCEL);
        }
        return super.dispatchTouchEvent(ev);
    }

    /**
     * 车机有时把媒体键当普通按键派发给当前窗口，而不是走 MediaSession 路由。
     * 这类按键交给媒体适配层（按动作分组与方控输入通道折叠，不会切两次）。
     *
     * <p>HOME 单独处理：AOSP 的 PhoneWindowManager 一般会在派发前把 HOME 吞掉
     * （直接走 launchHome），所以这段在手机上多半收不到；但把 HOME 当普通键下发
     * 的车机（例如原车输入通道直派）会走到这里。能收到就必须自己处理，否则用户
     * 在设置页或应用抽屉里按 HOME 一点反应都没有。
     */
    @Override public boolean dispatchKeyEvent(android.view.KeyEvent event){
        if(event!=null&&event.getAction()==android.view.KeyEvent.ACTION_DOWN&&event.getRepeatCount()==0){
            if(event.getKeyCode()==android.view.KeyEvent.KEYCODE_HOME){
                android.content.SharedPreferences prefs=getSharedPreferences("launcher",0);
                String target=prefs.getString("homeKeyTarget",getPackageName());
                boolean isUni="uni".equals(target)||getPackageName().equals(target);
                if(!isUni){
                    GlobalDockService.dismissPanelNow("window");
                    launchHomeTarget(this,target);
                    return true;
                }
                dispatchHomeFirst("window");
                return true;
            }
            if(rt!=null&&rt.dispatchSteeringKey(event.getKeyCode(),"window"))return true;
        }
        return super.dispatchKeyEvent(event);
    }
    /** 让桌面落回第一屏：设置页关掉、应用抽屉退回首页、编辑态收尾。 */
    /**
     * 原生其它入口（原车 HOME 私有码、底栏）要求回桌面。
     *
     * <p>没有活动窗口时至少把底栏面板收掉，避免「面板窗口还在最上面盖着」。
     */
    public static void requestHomeFirst(String via){
        MainActivity host=active.get();
        Context ctx=host;
        if(ctx==null)ctx=GlobalDockService.getActive();
        if(ctx!=null){
            android.content.SharedPreferences prefs=ctx.getSharedPreferences("launcher",0);
            String target=prefs.getString("homeKeyTarget",ctx.getPackageName());
            boolean isUni="uni".equals(target)||ctx.getPackageName().equals(target);
            if(!isUni){
                GlobalDockService.dismissPanelNow(via);
                launchHomeTarget(ctx,target);
                return;
            }
        }
        if(host==null){GlobalDockService.dismissPanelNow(via);return;}
        host.bringSelfToFront();
        host.dispatchHomeFirst(via);
    }

    public static void launchHomeTarget(Context context, String targetPackage){
        if(context==null)return;
        try{
            GlobalDockService.suspendDockForExternalHome();
            PackageManager pm=context.getPackageManager();
            Intent homeIntent=new Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_HOME);
            List<ResolveInfo> resolves=pm.queryIntentActivities(homeIntent,PackageManager.MATCH_DEFAULT_ONLY);
            ResolveInfo target=null;
            if(targetPackage!=null&&!targetPackage.isEmpty()&&!"oem".equals(targetPackage)){
                if(resolves!=null){
                    for(ResolveInfo ri:resolves){
                        if(ri.activityInfo!=null&&targetPackage.equals(ri.activityInfo.packageName)){
                            target=ri;
                            break;
                        }
                    }
                }
                if(target==null){
                    resolves=pm.queryIntentActivities(homeIntent,0);
                    if(resolves!=null){
                        for(ResolveInfo ri:resolves){
                            if(ri.activityInfo!=null&&targetPackage.equals(ri.activityInfo.packageName)){
                                target=ri;
                                break;
                            }
                        }
                    }
                }
            }else{
                if(resolves!=null){
                    for(ResolveInfo ri:resolves){
                        if(ri.activityInfo!=null&&!context.getPackageName().equals(ri.activityInfo.packageName)){
                            target=ri;
                            break;
                        }
                    }
                }
                if(target==null){
                    resolves=pm.queryIntentActivities(homeIntent,0);
                    if(resolves!=null){
                        for(ResolveInfo ri:resolves){
                            if(ri.activityInfo!=null&&!context.getPackageName().equals(ri.activityInfo.packageName)){
                                target=ri;
                                break;
                            }
                        }
                    }
                }
            }
            if(target!=null){
                Intent launch=new Intent(Intent.ACTION_MAIN)
                    .addCategory(Intent.CATEGORY_HOME)
                    .setClassName(target.activityInfo.packageName,target.activityInfo.name)
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK|Intent.FLAG_ACTIVITY_RESET_TASK_IF_NEEDED);
                context.startActivity(launch);
                UniLog.i(LogTags.APP,"拉起目标桌面: "+target.activityInfo.packageName+"/"+target.activityInfo.name);
                MainActivity host=active.get();
                if(host!=null){
                    try{host.moveTaskToBack(true);}catch(Throwable ignored){}
                }
                return;
            }
            String pkgToLaunch=targetPackage!=null&&!targetPackage.isEmpty()&&!"oem".equals(targetPackage)?targetPackage:"ecarx.launcher3";
            Intent fallback=pm.getLaunchIntentForPackage(pkgToLaunch);
            if(fallback!=null){
                fallback.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
                context.startActivity(fallback);
                UniLog.i(LogTags.APP,"拉起桌面 fallback: "+pkgToLaunch);
                MainActivity host=active.get();
                if(host!=null){
                    try{host.moveTaskToBack(true);}catch(Throwable ignored){}
                }
                return;
            }
            Toast.makeText(context,"未找到所选桌面应用",Toast.LENGTH_SHORT).show();
        }catch(Throwable e){
            UniLog.w(LogTags.APP,"拉起目标桌面失败",e);
            Toast.makeText(context,"打开桌面失败: "+e.getMessage(),Toast.LENGTH_SHORT).show();
        }
    }

    public static void launchOemHome(Context context){
        launchHomeTarget(context,"ecarx.launcher3");
    }
    /**
     * 把桌面窗口拉回前台。
     *
     * <p>原车 HOME（VHAL 注入 KEYCODE_HOME，被我们的原车输入通道截到）到达时，
     * 桌面通常正躲在第三方应用后面 —— 这时候只把 Flutter 的页码重置、面板收掉，
     * 用户在屏幕上什么都看不到，表现就是「按 HOME 没反应」。所以先真的把自己
     * 拉到前面，再走「回首屏」。
     */
    private void bringSelfToFront(){
        if(isFinishing()||hasWindowFocus())return;
        try{
            Intent intent=new Intent(this,MainActivity.class)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK
                    |Intent.FLAG_ACTIVITY_CLEAR_TOP
                    |Intent.FLAG_ACTIVITY_SINGLE_TOP
                    |Intent.FLAG_ACTIVITY_REORDER_TO_FRONT);
            startActivity(intent);
            UniLog.event(LogTags.APP,"HOME 拉起桌面","hasFocus",false,"at",System.currentTimeMillis());
        }catch(Throwable e){
            UniLog.w(LogTags.APP,"HOME 拉起桌面失败",e);
        }
    }
    private void dispatchHomeFirst(String via){
        UniLog.event(LogTags.APP,"HOME 回首屏","channel",via,"at",System.currentTimeMillis());
        // 面板窗口（全部应用 / 最近任务 / 媒体 / 空调）是独立 overlay，压在 Activity
        // 之上；先直接收掉，不等 Dart 往返，否则用户看到的是「HOME 按了没反应」。
        GlobalDockService.dismissPanelNow("home");
        // The parameter is the input channel that reported the key ("window", 方控…). It used to
        // shadow the Flutter MethodChannel field, so the call below did not compile.
        if(channel!=null)channel.invokeMethod("home-first",null);
    }
    @Override public void onConfigurationChanged(Configuration c){invalidateWindowCaches();super.onConfigurationChanged(c);UniLog.event(LogTags.APP,"配置变化", "orientation", c.orientation);publish();}
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
        UniLog.event(LogTags.APP,"分发入口请求","target",settings?"settings":"home","at",System.currentTimeMillis());
        if(intent!=null&&intent.getBooleanExtra("uniSpectrumPermission",false)){
            getWindow().getDecorView().post(()->requestPermissions(new String[]{android.Manifest.permission.RECORD_AUDIO},4106));
            intent.removeExtra("uniSpectrumPermission");
        }
        if(settings){
            if(channel!=null)channel.invokeMethod("open-settings",null);
        }else{
            android.content.SharedPreferences prefs=getSharedPreferences("launcher",0);
            String target=prefs.getString("homeKeyTarget",getPackageName());
            boolean isUni="uni".equals(target)||getPackageName().equals(target);
            if(!isUni&&intent!=null&&Intent.ACTION_MAIN.equals(intent.getAction())&&intent.hasCategory(Intent.CATEGORY_HOME)){
                launchHomeTarget(this,target);
                return;
            }
            dispatchHomeFirst("intent");
        }
    }

    @Override protected void onNewIntent(Intent intent){
        super.onNewIntent(intent);setIntent(intent);
        initialSettings=isSettingsIntent(intent);
        dispatchIntent(intent);publish();
    }

    @Override protected void onDestroy(){
        UniLog.enter(LogTags.APP,"launcher/onDestroy");
        if(snapshotBitmap!=null&&!snapshotBitmap.isRecycled())snapshotBitmap.recycle();
        snapshotBitmap=null;
        resumeSnapshot=null;
        if(wallpaperResult!=null){wallpaperResult.success(null);wallpaperResult=null;}
        if(rt!=null)rt.removeListener(this);
        if(mapHost!=null)mapHost.close();
        if(spectrumBridge!=null){spectrumBridge.close();spectrumBridge=null;}
        if(ambientBridge!=null){ambientBridge.close();ambientBridge=null;}
        // 共享引擎这一侧：通道、事件流和游标都属于引擎（Dart isolate 还在跑），
        // 在这里清掉就等于把下一个窗口的更新掐断。只有本窗口独占引擎时，这次
        // onDestroy 才是真正的一次销毁。
        MainActivity current=active.get();
        boolean releaseShared=!ownsEngine&&isFinishing()&&(current==null||current==this||current.ownsEngine);
        if(ownsEngine||releaseShared){
            if(channel!=null)channel.setMethodCallHandler(null);
            otaEvents=null;
            if(events!=null)events.setStreamHandler(null);
            engineState.reset();
        }
        if(current==this)active.clear();
        // 真正退出（不是重建）才把进程级引擎一起放掉，避免一个不会再有人接管的
        // isolate 长期占着内存和定时器。
        if(releaseShared){
            releaseSharedEngine();
            if(current!=null&&current!=this&&current.ownsEngine&&!current.isFinishing()){
                promoteToSharedEngine(current);
            }
        }
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

    private static void promoteToSharedEngine(MainActivity owner){
        FlutterEngine engine=owner.getFlutterEngine();
        if(engine==null)return;
        synchronized(MainActivity.class){
            sharedEngine=engine;
            sharedState=owner.engineState;
        }
        owner.ownsEngine=false;
        final FlutterEngine promoted=engine;
        engine.addEngineLifecycleListener(new FlutterEngine.EngineLifecycleListener(){
            public void onPreEngineRestart(){}
            public void onEngineWillDestroy(){
                synchronized(MainActivity.class){
                    if(sharedEngine!=promoted)return;
                    sharedEngine=null;sharedState=new EngineState();
                }
            }
        });
    }
}
