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
import xyz.i4o.uni.launcher.overlay.SystemNavigationPolicy;
import xyz.i4o.uni.launcher.platform.LiveNavigationHost;

/** Home window and Flutter bridge; shared integrations live in LauncherRuntime. */
public final class MainActivity extends FlutterActivity {
    private static java.lang.ref.WeakReference<MainActivity> active=new java.lang.ref.WeakReference<>(null);
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
    private String cached="{}";
    private JSONObject flutterViewport=new JSONObject();
    private int reservedBottomPx;
    private final LauncherRuntime.StaticCursor cursor=new LauncherRuntime.StaticCursor();
    /** Last signature handed to the sink; see emit(). */
    private String sentSignature;
    private boolean initialSettings;
    private EventChannel.EventSink sink;
    private EventChannel events;
    private MethodChannel channel;
    private MethodChannel.Result wallpaperResult;
    private static final int PICK_WALLPAPER=4206;

    @Override public FlutterEngine provideFlutterEngine(android.content.Context context){
        return LauncherEngines.create(context,"main",true);
    }
    @Override public boolean shouldDestroyEngineWithHost(){return true;}

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
        if(rt==null)rt=LauncherRuntime.get(this);
        mapHost=new LiveNavigationHost(this,engine.getDartExecutor().getBinaryMessenger(),engine.getRenderer());
        channel=new MethodChannel(engine.getDartExecutor().getBinaryMessenger(),"xyz.i4o.uni.launcher/platform");
        channel.setMethodCallHandler((call,result)->{
            try{
                if("snapshot".equals(call.method)){
                    updateSnapshot();result.success(cached);
                    // Bootstrap consumes the fallback once. Events must not consume
                    // it before Dart has installed its method handler.
                    initialSettings=false;
                }
                else if("otaInfo".equals(call.method)){
                    android.content.pm.PackageInfo info=getPackageManager().getPackageInfo(getPackageName(),0);
                    File dir=new File(getFilesDir(),"ota"); if(!dir.isDirectory()&&!dir.mkdirs()) throw new IllegalStateException("ota directory");
                    Map<String,Object> data=new HashMap<>();data.put("versionName",info.versionName);data.put("versionCode",(long)info.versionCode);data.put("sdk",android.os.Build.VERSION.SDK_INT);data.put("abis",java.util.Arrays.asList(android.os.Build.SUPPORTED_ABIS));data.put("directory",dir.getAbsolutePath());data.put("enabled",getPreferences(0).getBoolean("otaEnabled",true));data.put("dismissedVersion",getPreferences(0).getInt("otaDismissedVersion",0));data.put("dismissedAt",getPreferences(0).getLong("otaDismissedAt",0));result.success(data);
                }
                else if("otaDismiss".equals(call.method)){if(call.arguments instanceof Number)getPreferences(0).edit().putInt("otaDismissedVersion",((Number)call.arguments).intValue()).putLong("otaDismissedAt",System.currentTimeMillis()).apply();result.success(null);}
                else if("otaEnabled".equals(call.method)){getPreferences(0).edit().putBoolean("otaEnabled",Boolean.TRUE.equals(call.arguments)).apply();result.success(null);}
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
                    wallpaperResult=result;
                    Intent pick=new Intent(Intent.ACTION_OPEN_DOCUMENT).setType("image/*").addCategory(Intent.CATEGORY_OPENABLE)
                        .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION|Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION);
                    startActivityForResult(pick,PICK_WALLPAPER);
                }
                else if("desktopPage".equals(call.method)){
                    int page=call.arguments instanceof Number?((Number)call.arguments).intValue():0;
                    if(mapHost!=null)mapHost.preparePageChange();
                    flutterViewport.put("page",page);
                    rt.setDesktopContentSilently(page==0);result.success(null);
                }
                else if("viewport".equals(call.method)){flutterViewport=new JSONObject((String)call.arguments);
                    rt.setDesktopContent(!flutterViewport.optBoolean("settings")&&flutterViewport.optInt("page")==0);result.success(null);}
                else if("action".equals(call.method)){
                    String raw=(String)call.arguments;
                    if(raw==null||raw.length()>8192){result.error("invalid","Invalid request",null);return;}
                    handle(new JSONObject(raw));result.success(null);
                }
                else result.notImplemented();
            }catch(Exception e){result.error("unavailable","操作暂不可用",null);}
        });
        events=new EventChannel(engine.getDartExecutor().getBinaryMessenger(),"xyz.i4o.uni.launcher/events");
        events.setStreamHandler(new EventChannel.StreamHandler(){
            public void onListen(Object args,EventChannel.EventSink events){sink=events;sentSignature=null;publish();}
            public void onCancel(Object args){
                sink=null;sentSignature=null;
                // The next subscriber is a fresh Dart controller with no cached
                // groups, so the first packet must carry every group again.
                cursor.apps=-1;cursor.design=-1;cursor.media=-1;cursor.settings=-1;
            }
        });
    }

    @Override protected void onCreate(Bundle saved){
        long traceStart=StartupTrace.mark();
        rt=LauncherRuntime.get(this);
        rt.scheduleBootAutoPlay();
        StartupTrace.began(traceStart);StartupTrace.runtime(StartupTrace.mark());
        initialSettings=isSettingsIntent(getIntent());
        super.onCreate(saved);getWindow().addFlags(WindowManager.LayoutParams.FLAG_FULLSCREEN);
        // 隐藏 API 豁免：频谱的次选路径要反射 audioSessionId（公开 SDK 里没有）。
        android.util.Log.i("UniState","隐藏 API 豁免 "+xyz.i4o.uni.launcher.platform.HiddenApiCompat.tryExempt());
        // Android can create a separate HOME task after a regular app launch.
        // Keep one host/engine so hidden instances cannot retain map displays.
        MainActivity previous=active.get();active=new java.lang.ref.WeakReference<>(this);
        if(previous!=null&&previous!=this&&!previous.isFinishing())previous.finish();
        chrome=new NavigationChrome(this,rt.prefs());
        findViewById(android.R.id.content).addOnLayoutChangeListener((v,l,t,r,b,ol,ot,orr,ob)->{
            if(r-l!=orr-ol||b-t!=ob-ot)v.post(this::publish);
        });
        dispatchIntent(getIntent());publish();
        StartupTrace.window(StartupTrace.mark());
        final android.view.View traceRoot=getWindow().getDecorView();
        traceRoot.getViewTreeObserver().addOnPreDrawListener(new android.view.ViewTreeObserver.OnPreDrawListener(){
            public boolean onPreDraw(){traceRoot.getViewTreeObserver().removeOnPreDrawListener(this);StartupTrace.firstDraw();return true;}
        });
    }

    private void updateSnapshot(){
        int a=cursor.apps,d=cursor.design,m=cursor.media,s=cursor.settings;
        // 主窗口始终走带设置目录的快照：设置目录预热完成后由游标补发一次，其余
        // 时间只发分组增量，绝不触发同步扫描。
        JSONObject state=rt.snapshotWithSettings(cursor);
        // The settings catalogue is a legitimate large payload; without its cursor
        // here, its first delivery looked like a leak and hid real ones.
        boolean staticIncluded=a!=cursor.apps||d!=cursor.design||m!=cursor.media
            ||s!=cursor.settings;
        decorate(state);
        cached=state.toString();
        // Invariant: a telemetry-only packet must stay small. If a payload key ever
        // leaks back into the delta pack, say so instead of silently stalling frames.
        if(!staticIncluded&&cached.length()>65536)
            android.util.Log.w("UniPerf","Telemetry packet "+cached.length()+" chars; payload leaked into the delta pack");
    }

    /** dumpsys --uni-state 专用：用全新游标强制携带全部分组与设置目录。 */
    private void updateSnapshotFull(){
        JSONObject state=rt.snapshotWithSettings(new LauncherRuntime.StaticCursor());
        decorate(state);
        cached=state.toString();
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
        }catch(Exception e){android.util.Log.e("UniState","Window snapshot failed",e);}
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
        if(sink==null)return;
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
        if(sink==null||cached==null)return;
        String sig=signature(cached);
        if(sig.equals(sentSignature))return;
        sentSignature=sig;
        sink.success(cached);
    }

    @Override public void dump(String prefix,java.io.FileDescriptor fd,java.io.PrintWriter writer,String[] args){
        if(args!=null)for(String arg:args)if("--uni-state".equals(arg)){
            // dumpsys is already restricted to Android DUMP callers. Exclude
            // artwork, song text and app icons from this read-only diagnostic.
            try{
                updateSnapshotFull();JSONObject full=new JSONObject(cached),report=new JSONObject();
                for(String key:new String[]{"version","demo","hideNavigation","systemNavigationHidden","systemNavigationGranted","contentReservesSystemBars","contentHeightPx","viewportHeightPx","reservedBottomPx","desktopSelected","systemStatus","weather","calendar","navigation","vehicle","trafficLights"})report.put(key,full.opt(key));
                JSONObject m=full.optJSONObject("media"),safe=new JSONObject();
                if(m!=null)for(String key:new String[]{"available","authorized","playing","source","preferredPackage","sessions","reason","canToggle","canNext","canPrevious","canSeek","controlSource","lyricsSource","durationMs","positionMs","steeringControlReady","instrumentMetadataReady"})safe.put(key,m.opt(key));
                if(m!=null)safe.put("lyricsAvailable",!m.optString("lyrics").isEmpty()).put("artworkAvailable",!m.optString("artwork").isEmpty()).put("officialMedia",m.optJSONObject("officialMedia"));
                report.put("audioSpectrum",new JSONObject(xyz.i4o.uni.launcher.audio.SpectrumBridge.diagnostics()));
                if(ambientBridge!=null)report.put("ambientLight",new JSONObject(ambientBridge.status()));
                report.put("media",safe).put("flutterViewport",flutterViewport).put("globalDock",GlobalDockService.snapshot(this)).put("systemSettings",full.opt("systemSettings"));
                if(mapHost!=null)report.put("mapViews",mapHost.snapshot());
                writer.println("UNI_STATE="+report.toString());
            }catch(Exception e){writer.println("UNI_STATE_UNAVAILABLE");}return;
        }
        super.dump(prefix,fd,writer,args);
    }

    private void toast(String text){Toast.makeText(this,text,Toast.LENGTH_SHORT).show();}

    @Override protected void onStart(){
        super.onStart();
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
        GlobalDockService.ensureStarted(this);publish();
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
    }

    @Override public void onWindowFocusChanged(boolean focus){super.onWindowFocusChanged(focus);if(focus&&chrome!=null)chrome.apply();}
    @Override public void onConfigurationChanged(Configuration c){super.onConfigurationChanged(c);publish();}
    @Override public void onRequestPermissionsResult(int requestCode,String[] permissions,int[] results){
        super.onRequestPermissionsResult(requestCode,permissions,results);if(requestCode==4106)xyz.i4o.uni.launcher.audio.SpectrumBridge.permissionChanged();if(requestCode==4105){try{rt.handle(new JSONObject().put("action","calendar-refresh"));}catch(Exception ignored){}publish();}
    }

    @Override protected void onActivityResult(int requestCode,int resultCode,Intent data){
        super.onActivityResult(requestCode,resultCode,data);
        if(requestCode!=PICK_WALLPAPER)return;
        MethodChannel.Result pending=wallpaperResult;wallpaperResult=null;
        if(pending==null)return;
        if(resultCode!=Activity.RESULT_OK||data==null||data.getData()==null){pending.success(null);return;}
        final Uri uri=data.getData();
        // 解码/缩放/压缩/亮度全部移出主线程，避免大图导入阻塞第一帧或界面。
        new Thread(()->{
            try{
                Map<String,Object> result=importWallpaper(uri);
                runOnUiThread(()->{try{pending.success(result);}catch(Exception ignored){}});
            }catch(Exception e){
                android.util.Log.w("UniWallpaper","Image import failed",e);
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
    private boolean isSettingsIntent(Intent intent){
        return intent!=null&&(intent.getBooleanExtra("uniSettings",false)||
            (intent.getComponent()!=null&&"xyz.i4o.uni.launcher.DesktopSettings".equals(intent.getComponent().getClassName())));
    }
    private void dispatchIntent(Intent intent){
        if(intent!=null&&intent.getBooleanExtra("uniSpectrumPermission",false)){
            getWindow().getDecorView().post(()->requestPermissions(new String[]{android.Manifest.permission.RECORD_AUDIO},4106));
            intent.removeExtra("uniSpectrumPermission");
        }
        if(channel!=null)channel.invokeMethod(isSettingsIntent(intent)?"open-settings":"home",null);
    }

    @Override protected void onNewIntent(Intent intent){
        super.onNewIntent(intent);setIntent(intent);
        initialSettings=isSettingsIntent(intent);
        dispatchIntent(intent);publish();
    }

    @Override protected void onDestroy(){
        if(wallpaperResult!=null){wallpaperResult.success(null);wallpaperResult=null;}
        if(rt!=null)rt.removeListener(this);
        if(mapHost!=null)mapHost.close();
        if(spectrumBridge!=null){spectrumBridge.close();spectrumBridge=null;}
        if(ambientBridge!=null){ambientBridge.close();ambientBridge=null;}
        if(channel!=null)channel.setMethodCallHandler(null);
        if(events!=null)events.setStreamHandler(null);
        sink=null;if(active.get()==this)active.clear();
        super.onDestroy();
    }
}
