package xyz.i4o.uni.launcher.overlay;

import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.content.pm.ResolveInfo;
import android.graphics.Rect;
import android.os.Handler;
import android.os.Looper;
import android.util.DisplayMetrics;
import android.view.WindowManager;
import java.lang.reflect.Method;
import java.util.HashSet;
import java.util.List;
import java.util.Set;
import org.json.JSONObject;
import xyz.i4o.uni.launcher.log.LogTags;
import xyz.i4o.uni.launcher.log.UniLog;

/** Android 9 task bounds reserve space without synthetic insets. IP753's OEM
 * navigation library applies overscan repeatedly, leaving large empty areas.
 * Only visible fullscreen stacks on the physical display are adjusted. */
public final class WorkspacePolicy {
    private static final String SAVED="uniWorkspaceBounds";
    /** A reflective getAllStackInfos binder round trip on the main thread. It only
     * has to notice a newly fullscreen task, which no event reports, so poll at 1s:
     * fast enough that the reserved strip appears with the task transition, and 4x
     * fewer main-thread binder calls than the previous 250ms loop. */
    private static final long POLL_MS=1000;
    private final Context context;
    private final SharedPreferences prefs;
    private final Handler handler=new Handler(Looper.getMainLooper());
    private Object manager;
    private Method stacks,resize;
    private JSONObject originals;
    private boolean running,available;
    private final boolean compatibilityOnly;
    private int resized;
    /** 上一次记过日志的已调整任务数：轮询每秒一次，只在数量变化时落一条。 */
    private int loggedResized=-1;
    /** 记录已向系统请求过调整的栈与目标尺寸，防止不支持缩放的全屏栈每秒重复触发 resizeStack。 */
    private final java.util.Map<Integer,String> attempted=new java.util.HashMap<>();
    private final Set<String> cachedHomePackages=new HashSet<>();
    private long lastHomeCheckAt=0;

    private boolean isHomePackage(String pkg){
        if(pkg==null||pkg.isEmpty()||context.getPackageName().equals(pkg))return false;
        long now=System.currentTimeMillis();
        if(now-lastHomeCheckAt>10000||cachedHomePackages.isEmpty()){
            cachedHomePackages.clear();
            try{
                Intent home=new Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_HOME);
                List<ResolveInfo> homes=context.getPackageManager().queryIntentActivities(home,0);
                if(homes!=null){
                    for(ResolveInfo ri:homes){
                        if(ri.activityInfo!=null&&ri.activityInfo.packageName!=null){
                            String p=ri.activityInfo.packageName;
                            if(!context.getPackageName().equals(p)
                                &&!"com.android.settings".equals(p)
                                &&!p.endsWith(".fallbackhome")){
                                cachedHomePackages.add(p);
                            }
                        }
                    }
                }
                lastHomeCheckAt=now;
            }catch(Throwable ignored){}
        }
        return cachedHomePackages.contains(pkg);
    }

    private boolean isNativeSizeTask(String name,String ownPrefix){
        if(name==null||name.isEmpty())return false;
        if(name.startsWith(ownPrefix)
            ||name.startsWith("com.ecarx.parking/")
            ||name.startsWith("com.ecarx.recents/")
            ||name.startsWith("ecarx.launcher3/")
            ||name.startsWith("com.android.car.carlauncher/")
            ||name.startsWith("com.android.launcher3/")){
            return true;
        }
        int slash=name.indexOf('/');
        String pkg=slash>0?name.substring(0,slash):name;
        if("ecarx.launcher3".equals(pkg)
            ||"com.android.car.carlauncher".equals(pkg)
            ||"com.android.launcher3".equals(pkg)){
            return true;
        }
        String target=prefs.getString("homeKeyTarget","");
        if(!target.isEmpty()&&!"uni".equals(target)&&(pkg.equals(target)||name.startsWith(target+"/"))){
            return true;
        }
        return isHomePackage(pkg);
    }
    private final Runnable check=new Runnable(){public void run(){
        if(!running)return;
        update();if(available)handler.postDelayed(this,POLL_MS);
    }};
    public WorkspacePolicy(Context context,SharedPreferences prefs){
        this(context,prefs,false);
    }
    public WorkspacePolicy(Context context,SharedPreferences prefs,boolean compatibilityOnly){
        this.context=context;this.prefs=prefs;
        this.compatibilityOnly=compatibilityOnly;
        try{originals=new JSONObject(prefs.getString(SAVED,"{}"));}catch(Exception e){originals=new JSONObject();}
        try{
            manager=Class.forName("android.app.ActivityManager").getMethod("getService").invoke(null);
            Class<?> type=Class.forName("android.app.IActivityManager");
            stacks=type.getMethod("getAllStackInfos");
            resize=type.getMethod("resizeStack",int.class,Rect.class,boolean.class,boolean.class,boolean.class,int.class);
            available=true;
        }catch(Exception e){UniLog.w(LogTags.SYS,"Task workspace API unavailable",e,"tag","UniWorkspace");UniLog.fail(LogTags.SYS,"sys/workspace","reason","api-unavailable","error",e.getClass().getSimpleName());}
    }
    public void start(){running=true;UniLog.enter(LogTags.SYS,"sys/workspace","action","start","compatibilityOnly",compatibilityOnly);handler.post(check);UniLog.done(LogTags.SYS,"sys/workspace","action","start","compatibilityOnly",compatibilityOnly);}
    public boolean available(){return available;}
    public int resized(){return resized;}
    public static int systemBarHeight(Context c,SharedPreferences p){
        if(p.getBoolean("systemNavigationHidden",false))return 0;
        android.content.res.Resources r=c.getResources();
        int id=r.getIdentifier("navigation_bar_height_landscape","dimen","android");
        if(id==0)id=r.getIdentifier("navigation_bar_height","dimen","android");
        return id==0?0:r.getDimensionPixelSize(id);
    }
    public static int dockHeight(Context c,SharedPreferences p){
        DisplayMetrics real=new DisplayMetrics();((WindowManager)c.getSystemService(Context.WINDOW_SERVICE)).getDefaultDisplay().getRealMetrics(real);
        return Math.round(real.widthPixels*96f/1920f);
    }
    public static int dockTop(Context c,SharedPreferences p){
        DisplayMetrics real=new DisplayMetrics();((WindowManager)c.getSystemService(Context.WINDOW_SERVICE)).getDefaultDisplay().getRealMetrics(real);
        return Math.max(0,real.heightPixels-dockHeight(c,p)-systemBarHeight(c,p));
    }
    private void resize(int id,Rect bounds)throws Exception{resize.invoke(manager,id,bounds,true,true,false,-1);}
    private void update(){
        if(!available)return;
        try{
            DisplayMetrics real=new DisplayMetrics();((WindowManager)context.getSystemService(Context.WINDOW_SERVICE)).getDefaultDisplay().getRealMetrics(real);
            Rect target=new Rect(0,0,real.widthPixels,dockTop(context,prefs));
            String ownPrefix=context.getPackageName()+"/";
            for(Object info:(List<?>)stacks.invoke(manager)){
                Class<?> t=info.getClass();
                if(t.getField("displayId").getInt(info)!=0)continue;
                boolean visible=t.getField("visible").getBoolean(info);
                String[] names=(String[])t.getField("taskNames").get(info);
                int id=t.getField("stackId").getInt(info);if(id==0)continue;Rect bounds=(Rect)t.getField("bounds").get(info);
                if(compatibilityOnly&&!WorkspaceCompatibilityPolicy.shouldResize(visible,names)){
                    restoreOne(id,bounds,real);continue;
                }
                if(!visible||names==null||names.length==0){attempted.remove(id);continue;}
                // OEM recents, OEM launcher, AppPane and home apps must retain native size.
                // stack resize recreates activities or squashes grids, dropping labels.
                // UNI's own MainActivity already reserves dockTop via viewportHeightPx.
                boolean nativeSize=false;
                for(String name:names)if(isNativeSizeTask(name,ownPrefix))nativeSize=true;
                if(nativeSize){restoreOne(id,bounds,real);continue;}
                // Preserve floating, split-screen or PIP tasks; never resize a
                // map's virtual display, SystemUI window or unrelated small task.
                if(bounds==null||bounds.left!=0||bounds.top!=0||bounds.width()!=real.widthPixels
                    ||(bounds.height()!=real.heightPixels&&!bounds.equals(target)
                       &&bounds.height()!=real.heightPixels-Math.round(real.widthPixels*96f/1920f)
                       &&!originals.has(""+id)))continue;
                if(bounds.equals(target)){attempted.remove(id);continue;}
                String attemptSig=target.flattenToString()+"|"+bounds.flattenToString()+"|"+names[0];
                if(attemptSig.equals(attempted.get(id)))continue;
                attempted.put(id,attemptSig);
                String key=""+id;
                if(!originals.has(key)){
                    originals.put(key,bounds.flattenToString());prefs.edit().putString(SAVED,originals.toString()).apply();
                }
                resize(id,target);resized++;
            }
            // 这一段每秒跑一次：只有调整数量变了才落盘，避免把日志文件写满。
            if(resized!=loggedResized){loggedResized=resized;UniLog.i(LogTags.SYS,"工作区已预留","tasks",resized);}
        }catch(Exception e){available=false;UniLog.w(LogTags.SYS,"Unable to reserve task workspace",e,"tag","UniWorkspace");UniLog.fail(LogTags.SYS,"sys/workspace","reason","resize-failed","error",e.getClass().getSimpleName());}
    }
    private void restoreOne(int id,Rect current,DisplayMetrics real)throws Exception{
        attempted.remove(id);
        String key=""+id;
        Rect original=null;
        if(originals.has(key)){
            original=Rect.unflattenFromString(originals.optString(key));
            originals.remove(key);prefs.edit().putString(SAVED,originals.toString()).apply();
        }
        if(original==null&&real!=null){
            original=new Rect(0,0,real.widthPixels,real.heightPixels);
        }
        if(original!=null&&!original.equals(current))resize(id,original);
    }
    public void stopAndRestore(){
        running=false;handler.removeCallbacks(check);
        UniLog.enter(LogTags.SYS,"sys/workspace","action","stop","resized",resized);
        if(available)try{
            DisplayMetrics real=new DisplayMetrics();((WindowManager)context.getSystemService(Context.WINDOW_SERVICE)).getDefaultDisplay().getRealMetrics(real);
            for(Object info:(List<?>)stacks.invoke(manager)){
                Class<?> t=info.getClass();
                if(t.getField("displayId").getInt(info)==0)
                    restoreOne(t.getField("stackId").getInt(info),(Rect)t.getField("bounds").get(info),real);
            }
        }catch(Exception e){UniLog.w(LogTags.SYS,"Unable to restore task workspace",e,"tag","UniWorkspace");UniLog.fail(LogTags.SYS,"sys/workspace","action","stop","error",e.getClass().getSimpleName());return;}
        if(originals.length()==0)prefs.edit().remove(SAVED).apply();
        UniLog.done(LogTags.SYS,"sys/workspace","action","stop","resized",resized);
    }
}
