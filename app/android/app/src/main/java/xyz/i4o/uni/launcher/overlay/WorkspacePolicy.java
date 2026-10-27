package xyz.i4o.uni.launcher.overlay;

import android.content.Context;
import android.content.SharedPreferences;
import android.graphics.Rect;
import android.os.Handler;
import android.os.Looper;
import android.util.DisplayMetrics;
import android.util.Log;
import android.view.WindowManager;
import java.lang.reflect.Method;
import java.util.List;
import org.json.JSONObject;

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
    private int resized;
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
        }catch(Exception e){Log.w("UniWorkspace","Task workspace API unavailable",e);}
    }
    public void start(){running=true;handler.post(check);}
    public boolean available(){return available;}
    public int resized(){return resized;}
    private void resize(int id,Rect bounds)throws Exception{resize.invoke(manager,id,bounds,true,true,false,-1);}
    private void update(){
        if(!available)return;
        try{
            DisplayMetrics real=new DisplayMetrics();((WindowManager)context.getSystemService(Context.WINDOW_SERVICE)).getDefaultDisplay().getRealMetrics(real);
            Rect target=new Rect(0,0,real.widthPixels,real.heightPixels-Math.round(real.widthPixels*96f/1920f));
            for(Object info:(List<?>)stacks.invoke(manager)){
                Class<?> t=info.getClass();
                if(t.getField("displayId").getInt(info)!=0||!t.getField("visible").getBoolean(info))continue;
                String[] names=(String[])t.getField("taskNames").get(info);
                if(names==null||names.length==0)continue;
                int id=t.getField("stackId").getInt(info);if(id==0)continue;Rect bounds=(Rect)t.getField("bounds").get(info);
                // OEM recents crashes in a delayed HomePresenter callback when
                // stack resize recreates its Activity. Its task cards already
                // fit above the bottom strip; retain its native fullscreen size.
                boolean nativeSize=false;for(String name:names)if(name!=null
                    &&(name.startsWith("com.ecarx.parking/")||name.startsWith("com.ecarx.recents/")))nativeSize=true;
                if(nativeSize){restoreOne(id,bounds);continue;}
                // Preserve floating, split-screen or PIP tasks; never resize a
                // map's virtual display, SystemUI window or unrelated small task.
                if(bounds==null||bounds.left!=0||bounds.top!=0||bounds.width()!=real.widthPixels
                    ||(bounds.height()!=real.heightPixels&&!bounds.equals(target)))continue;
                if(bounds.equals(target))continue;
                String key=""+id;
                if(!originals.has(key)){
                    originals.put(key,bounds.flattenToString());prefs.edit().putString(SAVED,originals.toString()).apply();
                }
                resize(id,target);resized++;
            }
        }catch(Exception e){available=false;Log.w("UniWorkspace","Unable to reserve task workspace",e);}
    }
    private void restoreOne(int id,Rect current)throws Exception{
        String key=""+id;if(!originals.has(key))return;
        Rect original=Rect.unflattenFromString(originals.optString(key));
        if(original!=null&&!original.equals(current))resize(id,original);
        originals.remove(key);prefs.edit().putString(SAVED,originals.toString()).apply();
    }
    public void stopAndRestore(){
        running=false;handler.removeCallbacks(check);
        if(available)try{
            for(Object info:(List<?>)stacks.invoke(manager)){
                Class<?> t=info.getClass();
                if(t.getField("displayId").getInt(info)==0)
                    restoreOne(t.getField("stackId").getInt(info),(Rect)t.getField("bounds").get(info));
            }
        }catch(Exception e){Log.w("UniWorkspace","Unable to restore task workspace",e);return;}
        if(originals.length()==0)prefs.edit().remove(SAVED).apply();
    }
}
