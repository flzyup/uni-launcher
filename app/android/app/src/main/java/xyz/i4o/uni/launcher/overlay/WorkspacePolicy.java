package xyz.i4o.uni.launcher.overlay;

import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.content.pm.ResolveInfo;
import android.graphics.Rect;
import android.os.Handler;
import android.os.Looper;
import android.os.SystemClock;
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
    private String immersivePackage="";
    /** 已经**真的坐在**目标高度上的栈：只有轮询亲眼看到 `bounds==target` 才进来。
     *  以前这里数的是 resizeStack 的调用次数——系统接受了但没落地也算，
     *  快照里的 `workspaceResizes` 于是会说谎，「已预留」而应用仍被压住。 */
    private final java.util.Map<Integer,String> landed=new java.util.HashMap<>();
    /** 上一次记过日志的已落地任务数：轮询每秒一次，只在数量变化时落一条。 */
    private int loggedResized=-1;
    /** 记录已向系统请求过调整的栈与目标尺寸，防止不支持缩放的全屏栈每秒重复触发 resizeStack。 */
    private final java.util.Map<Integer,String> attempted=new java.util.HashMap<>();
    /** 每个栈被系统拒绝的次数：拒绝后还会重试两次，够了就停，别每秒骚扰 AMS。 */
    private final java.util.Map<Integer,Integer> failures=new java.util.HashMap<>();
    private static final int MAX_RESIZE_ATTEMPTS=3;
    /** 「系统接受了，下一秒 bounds 又回到满屏」的栈：接受 != 落地，得重发。
     *  但重发要冷却，否则就成了每秒一次 resizeStack 的老毛病。 */
    private final java.util.Map<Integer,Integer> stickyRetries=new java.util.HashMap<>();
    private final java.util.Map<Integer,Long> acceptedAt=new java.util.HashMap<>();
    private static final int MAX_STICKY_RETRIES=5;
    private static final long STICKY_COOLDOWN_MS=3000;
    private static final long STICKY_SLOW_MS=30000;
    /** 已经记过「豁免缩放」的栈，只留痕一次，避免轮询把日志写满。 */
    private final Set<String> loggedNativeSize=new HashSet<>();
    /** 只留一次痕的「放弃 / 转慢速」记录，键是 `栈|签名`。 */
    private final Set<String> loggedGiveUp=new HashSet<>();
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
        this.context=context;this.prefs=prefs;
        try{originals=new JSONObject(prefs.getString(SAVED,"{}"));}catch(Exception e){originals=new JSONObject();}
        try{
            manager=Class.forName("android.app.ActivityManager").getMethod("getService").invoke(null);
            Class<?> type=Class.forName("android.app.IActivityManager");
            stacks=type.getMethod("getAllStackInfos");
            resize=type.getMethod("resizeStack",int.class,Rect.class,boolean.class,boolean.class,boolean.class,int.class);
            available=true;
        }catch(Exception e){UniLog.w(LogTags.SYS,"Task workspace API unavailable",e,"tag","UniWorkspace");UniLog.fail(LogTags.SYS,"sys/workspace","reason","api-unavailable","error",e.getClass().getSimpleName());}
    }
    public void start(){running=true;UniLog.enter(LogTags.SYS,"sys/workspace","action","start");handler.post(check);UniLog.done(LogTags.SYS,"sys/workspace","action","start");}
    public void setImmersivePackage(String pkg){
        String value=pkg==null?"":pkg;
        if(value.equals(immersivePackage))return;
        immersivePackage=value;
        if(running)update();
    }
    public boolean available(){return available;}
    /** 当前**落地**的栈数（不是请求成功数），供底栏快照的 `workspaceResizes` 使用。 */
    public int resized(){return landed.size();}
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
    /** resizeStack 的返回值就是系统的接受/拒绝。以前把它丢了，被拒也当成功，
     *  任务于是永远停在满屏 1080，底栏压住它最后 96px —— 实车表现就是
     *  「应用底部被底栏挡住」而日志里却写着「工作区已预留」。 */
    private boolean resize(int id,Rect bounds)throws Exception{
        Object result=resize.invoke(manager,id,bounds,true,true,false,-1);
        return !(result instanceof Boolean)||((Boolean)result);
    }
    private void update(){
        if(!available)return;
        try{
            DisplayMetrics real=new DisplayMetrics();((WindowManager)context.getSystemService(Context.WINDOW_SERVICE)).getDefaultDisplay().getRealMetrics(real);
            Rect target=new Rect(0,0,real.widthPixels,dockTop(context,prefs));
            String ownPrefix=context.getPackageName()+"/";
            long now=SystemClock.elapsedRealtime();
            Set<Integer> seen=new HashSet<>();
            for(Object info:(List<?>)stacks.invoke(manager)){
                Class<?> t=info.getClass();
                if(t.getField("displayId").getInt(info)!=0)continue;
                boolean visible=t.getField("visible").getBoolean(info);
                String[] names=(String[])t.getField("taskNames").get(info);
                int id=t.getField("stackId").getInt(info);if(id==0)continue;Rect bounds=(Rect)t.getField("bounds").get(info);
                seen.add(id);
                if(!visible||names==null||names.length==0){forget(id);continue;}
                // Release the reserved strip for actual immersive requests.
                // Keep it released even while the transient UNI bar overlays the app.
                if(WorkspaceCompatibilityPolicy.isImmersiveTask(names,immersivePackage)){
                    forget(id);landed.remove(id);
                    Rect full=new Rect(0,0,real.widthPixels,real.heightPixels);
                    if(!full.equals(bounds))resize(id,full);
                    continue;
                }
                // OEM recents, OEM launcher, AppPane and home apps must retain native size.
                // stack resize recreates activities or squashes grids, dropping labels.
                // UNI's own MainActivity already reserves dockTop via viewportHeightPx.
                boolean nativeSize=false;
                for(String name:names)if(isNativeSizeTask(name,ownPrefix))nativeSize=true;
                if(nativeSize){
                    // 这一条日志专门用来排查「某应用打开后被底栏压住」：如果它出现在
                    // 现场日志里，说明是豁免名单误伤，不是缩放失败。
                    if(loggedNativeSize.add(id+"|"+names[0]))
                        UniLog.i(LogTags.SYS,"工作区跳过（原生尺寸任务）","stack",id,"task",names[0]);
                    restoreOne(id,bounds,real);continue;
                }
                // Preserve floating, split-screen or PIP tasks; never resize a
                // map's virtual display, SystemUI window or unrelated small task.
                if(bounds==null||bounds.left!=0||bounds.top!=0||bounds.width()!=real.widthPixels
                    ||(bounds.height()!=real.heightPixels&&!bounds.equals(target)
                       &&bounds.height()!=real.heightPixels-Math.round(real.widthPixels*96f/1920f)
                       &&!originals.has(""+id)))continue;
                if(bounds.equals(target)){
                    // 亲眼看到它坐在目标高度上：这才算数，顺手把重试账本清零。
                    landed.put(id,target.flattenToString());
                    forget(id);continue;
                }
                String attemptSig=target.flattenToString()+"|"+bounds.flattenToString()+"|"+names[0];
                if(attemptSig.equals(attempted.get(id))){
                    Integer rejected=failures.get(id);
                    int sticky=stickyRetries.containsKey(id)?stickyRetries.get(id):0;
                    // 被系统明确拒绝到头：这条路走不通，留一条痕就别再骚扰 AMS。
                    if(rejected!=null&&rejected>=MAX_RESIZE_ATTEMPTS){
                        if(loggedGiveUp.add(id+"|"+attemptSig))
                            UniLog.w(LogTags.SYS,"工作区放弃缩放","stack",id,"task",names[0],
                                "reason","rejected","attempts",rejected);
                        continue;
                    }
                    // 没有失败记录 = 上一次是「被接受」，可 bounds 又回到满屏 —— 没粘住。
                    // 以前这里直接 continue，于是这种栈永远停在 1080、一条日志都不打，
                    // 现场只能靠「开关一下隐藏原任务栏」把它撞好（目标高度变了、签名失效）。
                    if(rejected==null){
                        Long at=acceptedAt.get(id);
                        // 前几次 3 秒一补；一直补不上就转 30 秒慢速，别把 resizeStack
                        // 变成每秒一次的主线程绑定调用，但也别彻底放弃让应用一直挡着。
                        boolean slow=sticky>=MAX_STICKY_RETRIES;
                        long wait=slow?STICKY_SLOW_MS:STICKY_COOLDOWN_MS;
                        if(at!=null&&now-at<wait)continue;
                        if(slow){
                            if(loggedGiveUp.add(id+"|"+attemptSig))
                                UniLog.w(LogTags.SYS,"工作区一直没粘住，转慢速重试","stack",id,
                                    "task",names[0],"attempts",sticky);
                        }else{
                            stickyRetries.put(id,sticky+1);
                            UniLog.w(LogTags.SYS,"工作区没粘住，重新请求","stack",id,"task",names[0],
                                "attempt",sticky+1,"bounds",bounds.flattenToString());
                        }
                    }
                }
                attempted.put(id,attemptSig);
                String key=""+id;
                if(!originals.has(key)){
                    originals.put(key,bounds.flattenToString());prefs.edit().putString(SAVED,originals.toString()).apply();
                }
                if(resize(id,target)){failures.remove(id);acceptedAt.put(id,now);landed.remove(id);}
                else{
                    int tried=(failures.containsKey(id)?failures.get(id):0)+1;
                    failures.put(id,tried);
                    if(tried>=MAX_RESIZE_ATTEMPTS)
                        UniLog.fail(LogTags.SYS,"sys/workspace","action","resize","stack",id,"task",names[0],"attempts",tried);
                    else
                        UniLog.w(LogTags.SYS,"任务拒绝工作区缩放，稍后重试","stack",id,"task",names[0],"attempt",tried);
                }
            }
            // 每秒跑一次：消失的栈从「已落地」名单里剔掉，只在数量变化时落一条日志。
            landed.keySet().retainAll(seen);
            if(landed.size()!=loggedResized){
                loggedResized=landed.size();
                UniLog.i(LogTags.SYS,"工作区已预留","tasks",loggedResized);
            }
        }catch(Exception e){available=false;UniLog.w(LogTags.SYS,"Unable to reserve task workspace",e,"tag","UniWorkspace");UniLog.fail(LogTags.SYS,"sys/workspace","reason","resize-failed","error",e.getClass().getSimpleName());}
    }
    /** 清掉某栈的全部「请求/重试」账本，但保留它是否已落地的判断。 */
    private void forget(int id){
        attempted.remove(id);failures.remove(id);stickyRetries.remove(id);acceptedAt.remove(id);
    }
    private void restoreOne(int id,Rect current,DisplayMetrics real)throws Exception{
        forget(id);landed.remove(id);
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
        // 停止时撤销的是「当前已落地」的那些栈，先记下来，循环里会逐个清空。
        int restore=landed.size();
        UniLog.enter(LogTags.SYS,"sys/workspace","action","stop","resized",restore);
        if(available)try{
            DisplayMetrics real=new DisplayMetrics();((WindowManager)context.getSystemService(Context.WINDOW_SERVICE)).getDefaultDisplay().getRealMetrics(real);
            for(Object info:(List<?>)stacks.invoke(manager)){
                Class<?> t=info.getClass();
                if(t.getField("displayId").getInt(info)==0)
                    restoreOne(t.getField("stackId").getInt(info),(Rect)t.getField("bounds").get(info),real);
            }
        }catch(Exception e){UniLog.w(LogTags.SYS,"Unable to restore task workspace",e,"tag","UniWorkspace");UniLog.fail(LogTags.SYS,"sys/workspace","action","stop","error",e.getClass().getSimpleName());return;}
        if(originals.length()==0)prefs.edit().remove(SAVED).apply();
        UniLog.done(LogTags.SYS,"sys/workspace","action","stop","resized",restore);
    }
}
