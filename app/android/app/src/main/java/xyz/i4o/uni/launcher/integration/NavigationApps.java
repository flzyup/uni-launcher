package xyz.i4o.uni.launcher.integration;

import android.content.Context;
import android.content.BroadcastReceiver;
import android.content.Intent;
import android.content.IntentFilter;
import android.content.SharedPreferences;
import android.content.pm.PackageManager;
import android.os.Build;
import org.json.JSONObject;
import java.util.IdentityHashMap;
import java.util.LinkedHashMap;
import java.util.Map;

/** Resolve installed navigation only; never launch a guessed component. */
public final class NavigationApps {
    private static final String[] CANDIDATES={"com.autonavi.amapauto","com.autonavi.amapautp.yh","com.autonavi.amapautolite","com.autonavi.amapauto32","com.autonavi.minimap","com.baidu.BaiduMap","com.baidu.navi","com.tencent.map"};
    // LiveNavigationHost creates short-lived NavigationApps helpers. Share only
    // package queries and one package receiver per Application, never Activities.
    private static final Map<Context,PackageQueries> QUERIES=new IdentityHashMap<>();
    private final Context context;
    private final SharedPreferences prefs;
    private final PackageQueries queries;
    public NavigationApps(Context context,SharedPreferences prefs){
        this.context=context.getApplicationContext();
        if(this.context==null)throw new IllegalArgumentException("Application context required");
        this.prefs=prefs;
        synchronized(QUERIES){
            PackageQueries cached=QUERIES.get(this.context);
            if(cached==null){cached=new PackageQueries(this.context);QUERIES.put(this.context,cached);}
            queries=cached;
        }
    }
    public String selected(){
        String saved=prefs.getString("navigationPackage","auto");
        if(!"auto".equals(saved))return saved;
        for(String p:CANDIDATES)if(queries.get(p).launch!=null)return p;
        return "";
    }
    public Intent launchIntent(){return launchIntent(selected());}
    private Intent launchIntent(String pkg){
        if(pkg.isEmpty())return null;
        Intent launch=queries.get(pkg).launch;
        // Callers add launch flags; never expose the cached mutable Intent.
        return launch==null?null:new Intent(launch);
    }
    /** Prefer the declared map entry instead of an OEM USB/import splash proxy.
     * Resolve and authorize the installed activity; no component name is guessed.
     * AMap's no-op launch keeps the existing route intact. */
    public Intent displayIntent(){
        String pkg=selected();
        if(pkg.startsWith("com.autonavi."))try{
            Intent direct=new Intent(Intent.ACTION_VIEW,android.net.Uri.parse("androidauto://launch_do_nothing")).setPackage(pkg);
            android.content.pm.ResolveInfo resolved=context.getPackageManager().resolveActivity(direct,PackageManager.MATCH_DEFAULT_ONLY);
            android.content.pm.ActivityInfo info=resolved==null?null:resolved.activityInfo;
            if(info!=null&&pkg.equals(info.packageName)&&info.exported&&info.enabled&&info.applicationInfo.enabled
                    &&(info.permission==null||context.checkSelfPermission(info.permission)==PackageManager.PERMISSION_GRANTED))
                return direct.setComponent(new android.content.ComponentName(info.packageName,info.name));
        }catch(Exception|LinkageError ignored){}
        return launchIntent();
    }
    /** Return an embedded single-task navigation stack to the physical display
     * before launching it. Starting the package alone leaves AMap focused on
     * ActivityView's virtual display and appears to do nothing on the panel. */
    public boolean launchFullscreen(){
        String pkg=selected();Intent intent=displayIntent();if(pkg.isEmpty()||intent==null)return false;
        try{moveOwnSingleTaskToDisplay(pkg);}
        catch(Exception|LinkageError e){android.util.Log.i("UniNavigation","No embedded navigation stack to restore",e);}
        try{
            context.startActivity(intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK|Intent.FLAG_ACTIVITY_CLEAR_TOP|Intent.FLAG_ACTIVITY_SINGLE_TOP));
            return true;
        }catch(Exception|LinkageError e){android.util.Log.w("UniNavigation","Unable to open navigation full screen",e);return false;}
    }
    private void moveOwnSingleTaskToDisplay(String pkg)throws Exception{
        Object manager=Class.forName("android.app.ActivityManager").getMethod("getService").invoke(null);
        java.lang.reflect.Method all=manager.getClass().getMethod("getAllStackInfos");all.setAccessible(true);
        java.util.List<?> stacks=(java.util.List<?>)all.invoke(manager);
        for(Object stack:stacks){
            Class<?> type=stack.getClass();String[] names=(String[])type.getField("taskNames").get(stack);
            if(names==null||names.length!=1||names[0]==null||!names[0].startsWith(pkg+"/"))continue;
            int display=type.getField("displayId").getInt(stack);if(display==0)return;
            java.lang.reflect.Method move=manager.getClass().getMethod("moveStackToDisplay",int.class,int.class);move.setAccessible(true);
            move.invoke(manager,type.getField("stackId").getInt(stack),0);return;
        }
    }
    public JSONObject snapshot(){
        JSONObject j=new JSONObject();try{
            String selected=selected();
            Intent intent=launchIntent(selected);
            boolean permission=context.checkSelfPermission("android.permission.INJECT_EVENTS")==PackageManager.PERMISSION_GRANTED;
            boolean stacks=context.checkSelfPermission("android.permission.MANAGE_ACTIVITY_STACKS")==PackageManager.PERMISSION_GRANTED;
            boolean move=context.checkSelfPermission("android.permission.INTERNAL_SYSTEM_WINDOW")==PackageManager.PERMISSION_GRANTED;
            boolean api=Build.VERSION.SDK_INT==28;
            boolean enabled=prefs.getBoolean("embedNavigation",true);
            String label=selected.isEmpty()?"地图导航":queries.get(selected).label;
            j.put("label",label).put("package",selected).put("preferredPackage",prefs.getString("navigationPackage","auto"))
                .put("installed",intent!=null).put("enabled",enabled).put("injectGranted",permission).put("activityStacksGranted",stacks).put("moveStackGranted",move)
                .put("canEmbed",api&&permission&&stacks&&move&&intent!=null&&enabled)
                .put("options",options(selected))
                .put("reason",intent==null?"请安装或选择导航应用":!enabled?"地图嵌入已关闭":!api?"当前容器适用于 Android 9":!permission||!stacks||!move?"需要车机系统嵌入授权":"等待地图容器就绪");
        }catch(Exception ignored){}return j;
    }
    /** Launchable navigation apps for the card title-bar switcher. */
    private org.json.JSONArray options(String selected){
        org.json.JSONArray list=new org.json.JSONArray();
        try{
            LinkedHashMap<String,String> seen=new LinkedHashMap<>();
            if(!selected.isEmpty()&&queries.get(selected).launch!=null){
                seen.put(selected,labelOf(selected));
            }
            for(String p:CANDIDATES){
                if(seen.containsKey(p))continue;
                if(queries.get(p).launch!=null)seen.put(p,labelOf(p));
            }
            for(java.util.Map.Entry<String,String> e:seen.entrySet()){
                list.put(new JSONObject().put("package",e.getKey()).put("label",e.getValue()));
            }
        }catch(Exception ignored){}
        return list;
    }
    private String labelOf(String pkg){
        return queries.get(pkg).label;
    }
    private static final class AppEntry {
        final Intent launch;
        final String label;
        AppEntry(Intent launch,String label){this.launch=launch;this.label=label;}
    }
    private static final class PackageQueries {
        final Context application;
        final Map<String,AppEntry> entries=new LinkedHashMap<>();
        String locales="";
        PackageQueries(Context application){
            this.application=application;
            IntentFilter filter=new IntentFilter();
            for(String action:new String[]{Intent.ACTION_PACKAGE_ADDED,Intent.ACTION_PACKAGE_REMOVED,Intent.ACTION_PACKAGE_CHANGED,Intent.ACTION_PACKAGE_REPLACED})filter.addAction(action);
            filter.addDataScheme("package");
            // Process/Application-lifetime registration, shared by all helpers.
            application.registerReceiver(new BroadcastReceiver(){
                @Override public void onReceive(Context c,Intent intent){
                    synchronized(PackageQueries.this){entries.clear();}
                }
            },filter);
        }
        synchronized AppEntry get(String pkg){
            String current=application.getResources().getConfiguration().getLocales().toLanguageTags();
            if(!locales.equals(current)){entries.clear();locales=current;}
            AppEntry cached=entries.get(pkg);
            if(cached!=null)return cached;
            PackageManager pm=application.getPackageManager();
            Intent launch=pm.getLaunchIntentForPackage(pkg);
            String label="地图导航";
            // Missing packages are cached too; package broadcasts invalidate both
            // positive and negative results. Preferences/permissions stay live.
            if(launch!=null)try{label=pm.getApplicationLabel(pm.getApplicationInfo(pkg,0)).toString();}catch(Exception ignored){label=pkg;}
            cached=new AppEntry(launch==null?null:new Intent(launch),label);
            entries.put(pkg,cached);
            return cached;
        }
    }
}
