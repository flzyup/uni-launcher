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
import xyz.i4o.uni.launcher.log.LogTags;
import xyz.i4o.uni.launcher.log.UniLog;

/** Resolve installed navigation only; never launch a guessed component. */
public final class NavigationApps {
    private static final String[] CANDIDATES={"com.autonavi.amapauto","com.autonavi.amapautp.yh","com.autonavi.amapautolite","com.autonavi.amapauto32","com.autonavi.minimap","com.baidu.BaiduMap","com.baidu.navi","com.tencent.map"};
    // LiveNavigationHost creates short-lived NavigationApps helpers. Share only
    // package queries and one package receiver per Application, never Activities.
    private static final Map<Context,PackageQueries> QUERIES=new IdentityHashMap<>();
    private final Context context;
    private final SharedPreferences prefs;
    private final PackageQueries queries;
    private volatile String autoCandidate="";
    private volatile long autoResolvedAt;
    /**
     * auto 解析结果保鲜期。
     *
     * <p>以前是 1 秒，而且同步跑在 snapshot 里。{@code getRunningTasks} /
     * {@code getRecentTasks} 是 system_server 往返，实测单次 80~225ms；更要命的是
     * 它占着 ActivityManager 的锁，主线程紧接着的 {@code checkSelfPermission}
     * 也要走 ActivityManager —— 于是连主线程的权限检查都跟着排队几十毫秒。
     * 现在只在「首次」和「装态变化」时解析，其余时间一律读缓存。
     */
    private static final long AUTO_TTL_MS=30000;
    private int autoGeneration=-1;
    /** 单线程解析器：getRunningTasks / getRecentTasks 是 system_server 往返，不能放主线程。 */
    private static final java.util.concurrent.ExecutorService RESOLVER=
        java.util.concurrent.Executors.newSingleThreadExecutor(r->{
            Thread t=new Thread(r,"nav-resolve");t.setDaemon(true);t.setPriority(Thread.MIN_PRIORITY);return t;
        });
    private volatile boolean autoResolved;
    private final java.util.concurrent.atomic.AtomicBoolean autoRefreshing=
        new java.util.concurrent.atomic.AtomicBoolean();
    /** 解析结果变化后的通知（Runtime 用它补发一包快照）。 */
    public volatile Runnable onChanged;
    // 仅用于日志：记录最近一次的选择结果。selected() 会被广播与快照高频调用，
    // 每次都打印会把同一行刷满文件。
    private String tracedSelection="";
    private volatile String autoReason="";
    // options() 每次都要 queryIntentActivities 两遍（PackageManager 全表扫描），
    // 而结果只在装/卸应用或切语言时才会变。缓存到下一次包变化为止。
    private org.json.JSONArray optionsCache;
    private int optionsGeneration=-1;
    private String optionsLocale="";
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
        if(!"auto".equals(saved)){traceSelection(saved,"pinned","用户指定的导航应用");return saved;}
        if(!autoResolved){
            // 首次：同步解析一次（冷启动付一次），之后一律读缓存。
            autoCandidate=resolveAuto();
            autoResolvedAt=android.os.SystemClock.elapsedRealtime();
            autoGeneration=queries.generation();
            autoResolved=true;
        }else if(queries.generation()!=autoGeneration
            ||android.os.SystemClock.elapsedRealtime()-autoResolvedAt>=AUTO_TTL_MS){
            refreshAutoAsync();
        }
        traceSelection(autoCandidate,"auto",autoReason);
        return autoCandidate;
    }
    /**
     * 后台刷新 auto 结果。
     *
     * <p>以前这是 {@code snapshot()} 里的同步调用：每次快照都可能走
     * {@code getRunningTasks(32)} + {@code getRecentTasks(32)} 两次 system_server
     * 往返，实测单次 80~225ms，全部压在主线程上，而快照是 12Hz 触发的 —— 于是
     * 桌面在「按 home 回来」这种时刻根本没有空闲的主线程可用。
     */
    private void refreshAutoAsync(){
        if(!autoRefreshing.compareAndSet(false,true))return;
        final boolean had=autoResolved;
        final String previous=autoCandidate;
        try{
            RESOLVER.execute(()->{
                try{
                    String pkg=resolveAuto();
                    boolean changed=!had||!pkg.equals(previous);
                    autoCandidate=pkg;
                    autoResolvedAt=android.os.SystemClock.elapsedRealtime();
                    autoGeneration=queries.generation();
                    autoResolved=true;
                    if(changed){
                        Runnable notify=onChanged;
                        if(notify!=null)notify.run();   // publish() 自己会切回主线程
                    }
                }catch(RuntimeException|LinkageError ignored){
                    // 解析失败保持上一次的结果，下一次 TTL 再试
                }finally{
                    autoRefreshing.set(false);
                }
            });
        }catch(RuntimeException e){
            autoRefreshing.set(false);
        }
    }
    // 只在选择结果变化时记录：结果本身稳定，变化才是维护者要看的状态。
    private synchronized void traceSelection(String pkg,String source,String reason){
        String key=pkg+"|"+source;
        if(key.equals(tracedSelection))return;
        tracedSelection=key;
        if(pkg.isEmpty()){UniLog.fail(LogTags.NAV,"nav/select","source",source,"reason",reason);return;}
        UniLog.enter(LogTags.NAV,"nav/select","source",source);
        UniLog.i(LogTags.NAV,"导航应用已选择","package",pkg,"source",source,"reason",reason);
        UniLog.done(LogTags.NAV,"nav/select","package",pkg,"source",source);
    }
    private String resolveAuto(){
        try{
            android.app.ActivityManager manager=(android.app.ActivityManager)
                context.getSystemService(Context.ACTIVITY_SERVICE);
            if(manager!=null){
                // REAL_GET_TASKS still exposes map tasks here. Prefer the most
                // recently active installed map so the official and yh AMap APKs
                // can coexist without forcing a manual source selection.
                for(android.app.ActivityManager.RunningTaskInfo task:manager.getRunningTasks(32)){
                    String pkg=task.topActivity==null?"":task.topActivity.getPackageName();
                    for(String p:CANDIDATES)if(p.equals(pkg)&&queries.get(p).launch!=null){autoReason="正在前台运行的地图任务";return p;}
                }
                for(android.app.ActivityManager.RecentTaskInfo task:manager.getRecentTasks(32,0)){
                    String pkg=task.baseIntent==null||task.baseIntent.getComponent()==null?"":
                        task.baseIntent.getComponent().getPackageName();
                    for(String p:CANDIDATES)if(p.equals(pkg)&&queries.get(p).launch!=null){autoReason="最近使用过的地图任务";return p;}
                }
            }
        }catch(Exception|LinkageError ignored){}
        for(String p:CANDIDATES)if(queries.get(p).launch!=null){autoReason="已安装的候选导航应用";return p;}
        autoReason="未找到已安装的导航应用";
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
                    &&(info.permission==null||context.checkSelfPermission(info.permission)==PackageManager.PERMISSION_GRANTED)){
                // 直连的是高德自己的空实现页，地图视图直接挂上去，不经过 USB 导入代理。
                UniLog.i(LogTags.NAV,"地图显示入口已解析","package",pkg,"activity",info.name,"kind","amap-direct");
                return direct.setComponent(new android.content.ComponentName(info.packageName,info.name));
            }
        }catch(Exception|LinkageError ignored){}
        UniLog.i(LogTags.NAV,"地图显示入口回落到启动意图","package",pkg,"kind","launch");
        return launchIntent();
    }
    /** Return an embedded single-task navigation stack to the physical display
     * before launching it. Starting the package alone leaves AMap focused on
     * ActivityView's virtual display and appears to do nothing on the panel. */
    public boolean launchFullscreen(){
        String pkg=selected();Intent intent=displayIntent();if(pkg.isEmpty()||intent==null){UniLog.fail(LogTags.NAV,"nav/launch","package",pkg,"reason","没有可用的导航入口");return false;}
        UniLog.enter(LogTags.NAV,"nav/launch","package",pkg,"mode","fullscreen");
        xyz.i4o.uni.launcher.MainActivity.hideEmbeddedNavigation();
        try{moveOwnSingleTaskToDisplay(pkg);}
        catch(Exception|LinkageError e){UniLog.w(LogTags.NAV,"No embedded navigation stack to restore",e,"package",pkg);}
        try{
            context.startActivity(intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK|Intent.FLAG_ACTIVITY_SINGLE_TOP));
            UniLog.done(LogTags.NAV,"nav/launch","package",pkg,"mode","fullscreen");
            return true;
        }catch(Exception|LinkageError e){UniLog.w(LogTags.NAV,"Unable to open navigation full screen",e,"package",pkg);UniLog.fail(LogTags.NAV,"nav/launch","package",pkg,"mode","fullscreen","reason","启动失败");return false;}
    }
    private void moveOwnSingleTaskToDisplay(String pkg)throws Exception{
        Object manager=Class.forName("android.app.ActivityManager").getMethod("getService").invoke(null);
        java.lang.reflect.Method all=manager.getClass().getMethod("getAllStackInfos");all.setAccessible(true);
        java.util.List<?> stacks=(java.util.List<?>)all.invoke(manager);
        for(Object stack:stacks){
            Class<?> type=stack.getClass();String[] names=(String[])type.getField("taskNames").get(stack);
            if(names==null)continue;
            int display=type.getField("displayId").getInt(stack);
            boolean matched=false;
            if(display!=0){
                for(String name:names)if(name!=null&&name.startsWith(pkg+"/")){matched=true;break;}
            }else if(names.length==1&&names[0]!=null&&names[0].startsWith(pkg+"/")){
                matched=true;
            }
            if(!matched)continue;
            int id=type.getField("stackId").getInt(stack);
            if(display!=0){
                java.lang.reflect.Method move=manager.getClass().getMethod("moveStackToDisplay",int.class,int.class);move.setAccessible(true);
                move.invoke(manager,id,0);
                UniLog.i(LogTags.NAV,"内嵌导航栈已切回物理屏幕","package",pkg,"stackId",id,"display",0);
            }
            // Moving the stack does not stretch its Activity bounds. Resize it
            // to the physical workspace before the fullscreen transition draws,
            // then restore card bounds when LiveNavigationHost moves it back.
            android.util.DisplayMetrics real=new android.util.DisplayMetrics();
            ((android.view.WindowManager)context.getSystemService(Context.WINDOW_SERVICE)).getDefaultDisplay().getRealMetrics(real);
            int top=xyz.i4o.uni.launcher.overlay.WorkspacePolicy.dockTop(context,prefs);
            java.lang.reflect.Method resizeStack=manager.getClass().getMethod("resizeStack",int.class,android.graphics.Rect.class,boolean.class,boolean.class,boolean.class,int.class);
            resizeStack.setAccessible(true);
            resizeStack.invoke(manager,id,new android.graphics.Rect(0,0,real.widthPixels,top),true,true,false,-1);
            try{
                java.lang.reflect.Method focus=manager.getClass().getMethod("setFocusedStack",int.class);
                focus.setAccessible(true);
                focus.invoke(manager,id);
            }catch(Exception ignored){}
            UniLog.i(LogTags.NAV,"地图视图已铺满物理屏幕","package",pkg,"width",real.widthPixels,"height",top);
            return;
        }
    }
    public JSONObject snapshot(){
        JSONObject j=new JSONObject();try{
            String selected=selected();
            Intent intent=launchIntent(selected);
            final int perms=permissions();
            boolean permission=(perms&1)!=0;
            boolean stacks=(perms&2)!=0;
            boolean move=(perms&4)!=0;
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
    // 权限位：checkSelfPermission 在 Android 9 上是一次 ActivityManager 往返，
    // snapshot 里以前每次都要付三次。缓存 10 秒 —— 平台签名权限安装时就定了，
    // 留一个短过期只是为了让用户真的改了设置之后能自己恢复。
    private int permFlags=-1;
    private long permAtMs;
    private int permissions(){
        long now=android.os.SystemClock.elapsedRealtime();
        if(permFlags<0||now-permAtMs>10000){
            int flags=0;
            if(context.checkSelfPermission("android.permission.INJECT_EVENTS")==PackageManager.PERMISSION_GRANTED)flags|=1;
            if(context.checkSelfPermission("android.permission.MANAGE_ACTIVITY_STACKS")==PackageManager.PERMISSION_GRANTED)flags|=2;
            if(context.checkSelfPermission("android.permission.INTERNAL_SYSTEM_WINDOW")==PackageManager.PERMISSION_GRANTED)flags|=4;
            permFlags=flags;permAtMs=now;
        }
        return permFlags;
    }
    /** Launchable navigation apps for the card title-bar switcher. */
    private org.json.JSONArray options(String selected){        final int generation=queries.generation();
        final String locale=queries.locales;
        org.json.JSONArray cached=optionsCache;
        if(cached!=null&&generation==optionsGeneration&&locale.equals(optionsLocale))return cached;
        org.json.JSONArray list=new org.json.JSONArray();
        try{
            LinkedHashMap<String,String> seen=new LinkedHashMap<>();
            for(String p:CANDIDATES){
                if(seen.containsKey(p))continue;
                if(queries.get(p).launch!=null)seen.put(p,labelOf(p));
            }
            // Discover apps that actually declare map or turn-by-turn intent
            // handling. Require an enabled exported handler and a launchable app.
            PackageManager pm=context.getPackageManager();
            for(String uri:new String[]{"geo:0,0?q=0,0","google.navigation:q=0,0"}){
                Intent intent=new Intent(Intent.ACTION_VIEW,android.net.Uri.parse(uri));
                for(android.content.pm.ResolveInfo match:pm.queryIntentActivities(intent,PackageManager.MATCH_DEFAULT_ONLY)){
                    android.content.pm.ActivityInfo info=match.activityInfo;
                    if(info==null||!info.exported||!info.enabled||!info.applicationInfo.enabled)continue;
                    String pkg=info.packageName;
                    if(queries.get(pkg).launch!=null)seen.putIfAbsent(pkg,labelOf(pkg));
                }
            }
            for(java.util.Map.Entry<String,String> e:seen.entrySet()){
                list.put(new JSONObject().put("package",e.getKey()).put("label",e.getValue()));
            }
        }catch(Exception ignored){}
        optionsCache=list;optionsGeneration=generation;optionsLocale=locale;
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
        /** 每次包集合或语言变化就 +1，给上层当缓存键。 */
        private volatile int generation;
        int generation(){return generation;}
        PackageQueries(Context application){
            this.application=application;
            IntentFilter filter=new IntentFilter();
            for(String action:new String[]{Intent.ACTION_PACKAGE_ADDED,Intent.ACTION_PACKAGE_REMOVED,Intent.ACTION_PACKAGE_CHANGED,Intent.ACTION_PACKAGE_REPLACED})filter.addAction(action);
            filter.addDataScheme("package");
            // Process/Application-lifetime registration, shared by all helpers.
            application.registerReceiver(new BroadcastReceiver(){
                @Override public void onReceive(Context c,Intent intent){
                    synchronized(PackageQueries.this){entries.clear();generation++;}
                }
            },filter);
        }
        synchronized AppEntry get(String pkg){
            String current=application.getResources().getConfiguration().getLocales().toLanguageTags();
            if(!locales.equals(current)){entries.clear();locales=current;generation++;}
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
