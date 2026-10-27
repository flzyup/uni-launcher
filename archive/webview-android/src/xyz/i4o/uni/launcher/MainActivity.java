package xyz.i4o.uni.launcher;

import android.app.Activity;
import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.content.IntentFilter;
import android.content.SharedPreferences;
import android.content.res.Configuration;
import android.os.Build;
import android.os.Bundle;
import android.webkit.ConsoleMessage;
import android.webkit.JavascriptInterface;
import android.webkit.WebChromeClient;
import android.webkit.WebResourceRequest;
import android.webkit.WebResourceResponse;
import android.webkit.WebView;
import android.webkit.WebViewClient;
import android.net.Uri;
import org.json.JSONObject;
import org.json.JSONArray;
import java.io.ByteArrayInputStream;
import xyz.i4o.uni.launcher.core.ClimateState;
import xyz.i4o.uni.launcher.core.CommandPolicy;
import xyz.i4o.uni.launcher.integration.*;

/** Offline UI components + native Android integration. No network or shell bridge. */
public final class MainActivity extends Activity {
    private static final String ORIGIN="https://uni.launcher.local/";
    private WebView web;
    private SharedPreferences prefs;
    private NavigationChrome chrome;
    private AppRepository apps;
    private OfficialCatalog catalog;
    private MediaAdapter media;
    private VehicleAdapter vehicle;
    private JSONArray installed=new JSONArray();
    private final ClimateState simulator=new ClimateState();
    private volatile String cached="{}";
    private boolean ready;
    private final BroadcastReceiver packages=new BroadcastReceiver(){public void onReceive(Context c,Intent i){installed=apps.refresh();publish();}};

    protected void onCreate(Bundle saved){
        super.onCreate(saved);getWindow().addFlags(android.view.WindowManager.LayoutParams.FLAG_FULLSCREEN);
        prefs=getSharedPreferences("launcher",0);chrome=new NavigationChrome(this,prefs);
        if(!prefs.contains("demo"))prefs.edit().putBoolean("demo",Build.FINGERPRINT.contains("generic")||Build.MODEL.contains("sdk_gphone")||Build.MODEL.contains("Android SDK")).apply();
        apps=new AppRepository(this);catalog=new OfficialCatalog(this);vehicle=new OfficialVehicleAdapter(this);
        media=new MediaAdapter(this,new Runnable(){public void run(){publish();}});
        installed=apps.refresh();
        WebView.setWebContentsDebuggingEnabled(true);
        web=new WebView(this);web.setBackgroundColor(0xff101b22);
        web.getSettings().setJavaScriptEnabled(true);web.getSettings().setDomStorageEnabled(true);
        web.getSettings().setAllowFileAccess(false);web.getSettings().setAllowContentAccess(false);
        web.getSettings().setAllowFileAccessFromFileURLs(false);web.getSettings().setAllowUniversalAccessFromFileURLs(false);
        web.getSettings().setMixedContentMode(android.webkit.WebSettings.MIXED_CONTENT_NEVER_ALLOW);
        web.addJavascriptInterface(new Bridge(),"UniNative");
        web.setWebViewClient(new WebViewClient(){
            public boolean shouldOverrideUrlLoading(WebView view,String url){return !url.startsWith(ORIGIN);}
            public WebResourceResponse shouldInterceptRequest(WebView view,WebResourceRequest request){
                String url=request.getUrl().toString();
                if(!url.startsWith(ORIGIN))return empty();
                String path=request.getUrl().getPath();
                if(path==null||path.contains(".."))return empty();
                if("/".equals(path))path="/index.html";
                String mime=path.endsWith(".js")?"application/javascript":path.endsWith(".css")?"text/css":path.endsWith(".json")?"application/json":"text/html";
                try{return new WebResourceResponse(mime,"UTF-8",getAssets().open("ui"+path));}catch(Exception e){return empty();}
            }
            public void onPageFinished(WebView view,String url){ready=true;publish();}
        });
        web.setWebChromeClient(new WebChromeClient(){public boolean onConsoleMessage(ConsoleMessage m){android.util.Log.d("UniUI",m.message()+" @"+m.lineNumber());return true;}});
        setContentView(web);IntentFilter filter=new IntentFilter();filter.addAction(Intent.ACTION_PACKAGE_ADDED);filter.addAction(Intent.ACTION_PACKAGE_REMOVED);filter.addAction(Intent.ACTION_PACKAGE_CHANGED);filter.addDataScheme("package");registerReceiver(packages,filter);
        updateSnapshot();web.loadUrl(ORIGIN+"index.html?view=single");
    }
    private WebResourceResponse empty(){return new WebResourceResponse("text/plain","UTF-8",new ByteArrayInputStream(new byte[0]));}
    private void updateSnapshot(){
        JSONObject state=new JSONObject();try{
            JSONObject climate=new JSONObject().put("left",simulator.left).put("right",simulator.right).put("fan",simulator.fan).put("power",simulator.power)
                .put("auto",simulator.auto).put("ac",simulator.ac).put("sync",simulator.sync).put("recirc",simulator.recirc);
            state.put("demo",prefs.getBoolean("demo",false)).put("hideNavigation",prefs.getBoolean("hideNavigation",false))
                .put("globalNavigation",prefs.getBoolean("globalNavigation",false))
                .put("globalNavigationGranted",checkSelfPermission("android.permission.WRITE_SECURE_SETTINGS")==android.content.pm.PackageManager.PERMISSION_GRANTED)
                .put("dark",(getResources().getConfiguration().uiMode&Configuration.UI_MODE_NIGHT_MASK)==Configuration.UI_MODE_NIGHT_YES)
                .put("apps",installed).put("climate",climate).put("vehicle",vehicle.snapshot()).put("media",media.snapshot()).put("version","0.1.0");
            state.put("savedDesign",prefs.getString("savedDesign", ""));
        }catch(Exception e){android.util.Log.e("UniState","Snapshot failed",e);}cached=state.toString();
    }
    private void publish(){
        updateSnapshot();if(ready&&web!=null)web.evaluateJavascript("window.Uni&&window.Uni.receive("+cached+")",null);
    }
    private void toast(String text){if(ready)web.evaluateJavascript("showToast("+JSONObject.quote(text)+")",null);}
    private final class Bridge {
        @JavascriptInterface public String bootstrap(){return cached;}
        @JavascriptInterface public boolean saveDesign(String raw){
            if(raw==null||raw.length()>65536)return false;
            try{
                JSONObject data=new JSONObject(raw);JSONObject p=data.getJSONObject("preferences");
                if(data.optInt("version")!=4||!p.optString("custom").matches("#[0-9a-fA-F]{6}"))return false;
                String mode=p.optString("mode"),palette=p.optString("palette");
                if(!"system".equals(mode)&&!"dark".equals(mode)&&!"light".equals(mode))return false;
                if(!"mint".equals(palette)&&!"blue".equals(palette)&&!"violet".equals(palette)&&!"amber".equals(palette)&&!"rose".equals(palette)&&!"custom".equals(palette))return false;
                int radius=p.getInt("radius"),pages=data.getInt("pageCount");
                if(radius<0||radius>40||pages<1||pages>20)return false;
                JSONArray cards=data.getJSONArray("cards");if(cards.length()>200)return false;
                for(int i=0;i<cards.length();i++){
                    JSONObject c=cards.getJSONObject(i);int x=c.getInt("x"),y=c.getInt("y"),w=c.getInt("w"),h=c.getInt("h"),page=c.getInt("page");
                    if(x<0||y<0||w<1||h<1||x+w>12||y+h>6||page<0||page>=pages)return false;
                }
                return prefs.edit().putString("savedDesign",raw).commit();
            }catch(Exception e){return false;}
        }
        @JavascriptInterface public void dispatch(final String raw){
            if(raw==null||raw.length()>8192)return;
            runOnUiThread(new Runnable(){public void run(){try{handle(new JSONObject(raw));}catch(Exception e){toast("操作暂不可用");android.util.Log.w("UniBridge","Action failed",e);}}});
        }
    }
    private void handle(JSONObject request)throws Exception{
        String action=request.optString("action"),value=request.optString("value");
        if("hide-navigation".equals(action)||"global-navigation".equals(action)||"demo-mode".equals(action)){
            if("global-navigation".equals(action)&&request.optBoolean("enabled",false)&&checkSelfPermission("android.permission.WRITE_SECURE_SETTINGS")!=android.content.pm.PackageManager.PERMISSION_GRANTED){toast("全局隐藏需要系统授权，当前窗口隐藏仍可使用");return;}
            String key="hide-navigation".equals(action)?"hideNavigation":"global-navigation".equals(action)?"globalNavigation":"demo";
            prefs.edit().putBoolean(key,request.optBoolean("enabled",false)).commit();chrome.apply();publish();return;
        }
        if("refresh".equals(action)){installed=apps.refresh();media.start();vehicle.close();vehicle=new OfficialVehicleAdapter(this);publish();return;}
        if("launch-app".equals(action)){if(!apps.launch(value))toast("应用未安装或无法启动");return;}
        if("media-access".equals(action)){try{startActivity(new Intent("android.settings.ACTION_NOTIFICATION_LISTENER_SETTINGS"));}catch(Exception e){toast("系统没有提供媒体授权入口");}return;}
        if("official-widget".equals(action)){
            if(catalog.providers(value).isEmpty()){toast("没有对应的原厂卡片");return;}
            startActivity(new Intent(this,OfficialWidgetActivity.class).putExtra("type",value));return;
        }
        if("open-official".equals(action)){
            if("camera".equals(value)){if(!apps.launchOfficialAvm())toast("原车 360 入口未安装、未启用或不可访问");return;}
            if(!apps.launchPackage(catalog.packageFor(value)))toast("此设备未安装对应原车应用");return;
        }
        if(CommandPolicy.isClimateAction(action)){
            boolean demo=prefs.getBoolean("demo",false);
            boolean ok=demo?simulator.apply(action,request.optString("zone"),value):vehicle.command(action,request.optString("zone"),value);
            if(!ok)toast("尚未连接空调，可从空调面板打开原车应用");publish();return;
        }
        if("toggle-play".equals(action)||"previous".equals(action)||"next".equals(action)){
            if(!media.command(action))toast("当前音源不支持此操作，或尚未授权媒体访问");publish();
        }
    }
    protected void onResume(){super.onResume();if(chrome!=null){chrome.apply();media.start();publish();}if(web!=null)web.onResume();}
    protected void onPause(){if(media!=null)media.stop();if(web!=null)web.onPause();super.onPause();}
    public void onWindowFocusChanged(boolean focus){super.onWindowFocusChanged(focus);if(focus&&chrome!=null)chrome.apply();}
    public void onConfigurationChanged(Configuration c){super.onConfigurationChanged(c);publish();}
    protected void onNewIntent(Intent intent){super.onNewIntent(intent);if(ready)web.evaluateJavascript("window.Uni.home()",null);}
    public void onBackPressed(){if(ready)web.evaluateJavascript("window.Uni.back()",null);}
    protected void onDestroy(){unregisterReceiver(packages);media.stop();vehicle.close();web.removeJavascriptInterface("UniNative");web.destroy();super.onDestroy();}
}
