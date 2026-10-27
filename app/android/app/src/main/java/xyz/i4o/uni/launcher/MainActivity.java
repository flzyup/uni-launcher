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
    private LauncherRuntime rt;
    private xyz.i4o.uni.launcher.audio.SpectrumBridge spectrumBridge;
    private NavigationChrome chrome;
    private LiveNavigationHost mapHost;
    private String cached="{}";
    private JSONObject flutterViewport=new JSONObject();
    private int reservedBottomPx;
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
        if(rt==null)rt=LauncherRuntime.get(this);
        mapHost=new LiveNavigationHost(this,engine.getDartExecutor().getBinaryMessenger(),engine.getRenderer());
        channel=new MethodChannel(engine.getDartExecutor().getBinaryMessenger(),"xyz.i4o.uni.launcher/platform");
        channel.setMethodCallHandler((call,result)->{
            try{
                if("snapshot".equals(call.method)){
                    updateSnapshot(true);result.success(cached);
                    // Bootstrap consumes the fallback once. Events must not consume
                    // it before Dart has installed its method handler.
                    initialSettings=false;
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
            public void onListen(Object args,EventChannel.EventSink events){sink=events;publish();}
            public void onCancel(Object args){sink=null;}
        });
    }

    @Override protected void onCreate(Bundle saved){
        rt=LauncherRuntime.get(this);
        initialSettings=isSettingsIntent(getIntent());
        super.onCreate(saved);getWindow().addFlags(WindowManager.LayoutParams.FLAG_FULLSCREEN);
        // Android can create a separate HOME task after a regular app launch.
        // Keep one host/engine so hidden instances cannot retain map displays.
        MainActivity previous=active.get();active=new java.lang.ref.WeakReference<>(this);
        if(previous!=null&&previous!=this&&!previous.isFinishing())previous.finish();
        chrome=new NavigationChrome(this,rt.prefs());
        findViewById(android.R.id.content).addOnLayoutChangeListener((v,l,t,r,b,ol,ot,orr,ob)->{
            if(r-l!=orr-ol||b-t!=ob-ot)v.post(this::publish);
        });
        dispatchIntent(getIntent());publish();
    }

    private void updateSnapshot(){updateSnapshot(false);}
    private void updateSnapshot(boolean includeSettings){
        JSONObject state=includeSettings?rt.snapshotWithSettings():rt.snapshot();
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
                if(!rt.prefs().getBoolean("hideNavigation",false)&&!rt.prefs().getBoolean("systemNavigationHidden",false)
                    &&decor.getHeight()>reservedBottomPx)
                    usable=Math.min(usable,decor.getHeight()-reservedBottomPx);
                if(rt.prefs().getBoolean("globalDockEnabled",false)){
                    android.util.DisplayMetrics real=new android.util.DisplayMetrics();getWindowManager().getDefaultDisplay().getRealMetrics(real);
                    usable=Math.min(usable,real.heightPixels-Math.round(real.widthPixels*96f/1920f));
                }
                state.put("contentHeightPx",content.getHeight()).put("viewportHeightPx",usable).put("reservedBottomPx",reservedBottomPx);
            }
            state.put("initialSettings",initialSettings)
                .put("systemNavigationHidden",rt.prefs().getBoolean("systemNavigationHidden",false))
                .put("systemNavigationGranted",SystemNavigationPolicy.granted(this))
                .put("globalDock",GlobalDockService.snapshot(this));
        }catch(Exception e){android.util.Log.e("UniState","Window snapshot failed",e);}
        cached=state.toString();
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
            rt.prefs().edit().putBoolean(key,request.optBoolean("enabled",false)).commit();
            chrome.apply();rt.publish();return;
        }
        rt.handle(request);
        if("refresh-system-settings".equals(action)||"navigation-audio-mode".equals(action)){
            updateSnapshot(true);if(sink!=null)sink.success(cached);
        }
    }

    private void publish(){if(rt==null)return;updateSnapshot();if(sink!=null)sink.success(cached);}

    @Override public void dump(String prefix,java.io.FileDescriptor fd,java.io.PrintWriter writer,String[] args){
        if(args!=null)for(String arg:args)if("--uni-state".equals(arg)){
            // dumpsys is already restricted to Android DUMP callers. Exclude
            // artwork, song text and app icons from this read-only diagnostic.
            try{
                updateSnapshot(true);JSONObject full=new JSONObject(cached),report=new JSONObject();
                for(String key:new String[]{"version","demo","hideNavigation","systemNavigationHidden","systemNavigationGranted","contentReservesSystemBars","contentHeightPx","viewportHeightPx","reservedBottomPx","desktopSelected","systemStatus","weather","calendar","navigation","vehicle","trafficLights"})report.put(key,full.opt(key));
                JSONObject m=full.optJSONObject("media"),safe=new JSONObject();
                if(m!=null)for(String key:new String[]{"available","authorized","playing","source","preferredPackage","sessions","reason","canToggle","canNext","canPrevious","canSeek","controlSource","lyricsSource","durationMs","positionMs","steeringControlReady","instrumentMetadataReady"})safe.put(key,m.opt(key));
                if(m!=null)safe.put("lyricsAvailable",!m.optString("lyrics").isEmpty()).put("artworkAvailable",!m.optString("artwork").isEmpty()).put("officialMedia",m.optJSONObject("officialMedia"));
                report.put("audioSpectrum",new JSONObject(xyz.i4o.uni.launcher.audio.SpectrumBridge.diagnostics()));
                report.put("media",safe).put("flutterViewport",flutterViewport).put("globalDock",GlobalDockService.snapshot(this)).put("systemSettings",full.opt("systemSettings"));
                if(mapHost!=null)report.put("mapViews",mapHost.snapshot());
                writer.println("UNI_STATE="+report.toString());
            }catch(Exception e){writer.println("UNI_STATE_UNAVAILABLE");}return;
        }
        super.dump(prefix,fd,writer,args);
    }

    private void toast(String text){Toast.makeText(this,text,Toast.LENGTH_SHORT).show();}

    @Override protected void onStart(){
        super.onStart();rt.setHomeVisible(true);rt.addListener(this,this::publish);
        if(mapHost!=null)mapHost.setVisible(true);
        publish();
    }

    @Override protected void onResume(){
        super.onResume();if(chrome!=null)chrome.apply();
        GlobalDockService.ensureStarted(this);publish();
    }

    @Override protected void onStop(){
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
        try{pending.success(importWallpaper(data.getData()));}
        catch(Exception e){android.util.Log.w("UniWallpaper","Image import failed",e);pending.error("invalid-image","无法读取这张图片",null);}
    }

    private Map<String,Object> importWallpaper(Uri uri)throws Exception{
        BitmapFactory.Options bounds=new BitmapFactory.Options();bounds.inJustDecodeBounds=true;
        try(InputStream in=getContentResolver().openInputStream(uri)){BitmapFactory.decodeStream(in,null,bounds);}
        if(bounds.outWidth<=0||bounds.outHeight<=0)throw new IllegalArgumentException("Invalid image");
        int sample=1;
        while(bounds.outWidth/sample>3840||bounds.outHeight/sample>2160)sample*=2;
        BitmapFactory.Options options=new BitmapFactory.Options();options.inSampleSize=sample;options.inPreferredConfig=Bitmap.Config.ARGB_8888;
        Bitmap decoded;
        try(InputStream in=getContentResolver().openInputStream(uri)){decoded=BitmapFactory.decodeStream(in,null,options);}
        if(decoded==null)throw new IllegalArgumentException("Unsupported image");
        final int targetW=1920,targetH=1080;
        float scale=Math.max(targetW/(float)decoded.getWidth(),targetH/(float)decoded.getHeight());
        int scaledW=Math.max(targetW,Math.round(decoded.getWidth()*scale)),scaledH=Math.max(targetH,Math.round(decoded.getHeight()*scale));
        Bitmap scaled=Bitmap.createScaledBitmap(decoded,scaledW,scaledH,true);
        Bitmap cropped=Bitmap.createBitmap(scaled,(scaledW-targetW)/2,(scaledH-targetH)/2,targetW,targetH);
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
        if(cropped!=scaled)cropped.recycle();if(scaled!=decoded)scaled.recycle();decoded.recycle();
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
        if(channel!=null)channel.setMethodCallHandler(null);
        if(events!=null)events.setStreamHandler(null);
        sink=null;if(active.get()==this)active.clear();
        super.onDestroy();
    }
}
