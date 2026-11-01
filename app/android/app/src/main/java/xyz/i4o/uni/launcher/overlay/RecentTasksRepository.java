package xyz.i4o.uni.launcher.overlay;

import android.app.ActivityManager;
import android.content.ComponentName;
import android.content.Context;
import android.content.Intent;
import android.content.pm.ApplicationInfo;
import android.content.pm.PackageManager;
import android.graphics.Bitmap;
import android.graphics.Canvas;
import android.graphics.drawable.Drawable;
import android.util.Base64;
import java.io.ByteArrayOutputStream;
import java.lang.reflect.Method;
import java.util.HashSet;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Set;
import org.json.JSONArray;
import org.json.JSONObject;

/** Platform-signed Android 9 recent-task adapter. Task policy remains native;
 * Flutter only renders the cards and sends back task IDs from this allow-list. */
public final class RecentTasksRepository {
    private final Context context;
    private final ActivityManager activities;
    private final PackageManager packages;
    private final Set<Integer> allowed=new LinkedHashSet<>();
    private final Set<Integer> locked=new HashSet<>();
    private final Set<String> protectedPackages=new HashSet<>();

    public RecentTasksRepository(Context context){
        this.context=context.getApplicationContext();
        activities=(ActivityManager)context.getSystemService(Context.ACTIVITY_SERVICE);
        packages=context.getPackageManager();
        protectedPackages.add(context.getPackageName());
        protectedPackages.add("android");
        protectedPackages.add("com.android.systemui");
        protectedPackages.add("com.ecarx.launcher3");
        protectedPackages.add("com.android.launcher3");
        protectedPackages.add("com.ecarx.recents");
        protectedPackages.add("com.ecarx.parking");
        try{
            Intent home=new Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_HOME);
            ComponentName component=home.resolveActivity(packages);
            if(component!=null)protectedPackages.add(component.getPackageName());
        }catch(RuntimeException ignored){}
    }

    public boolean canRemove(){
        return context.checkSelfPermission("android.permission.REMOVE_TASKS")==PackageManager.PERMISSION_GRANTED
            ||context.checkSelfPermission("android.permission.MANAGE_ACTIVITY_STACKS")==PackageManager.PERMISSION_GRANTED;
    }

    @SuppressWarnings("deprecation")
    public synchronized JSONArray snapshot(){
        JSONArray result=new JSONArray();allowed.clear();Set<String> seen=new HashSet<>();
        try{
            Set<Integer> running=new HashSet<>();
            for(ActivityManager.RunningTaskInfo task:activities.getRunningTasks(32))running.add(task.id);
            List<ActivityManager.RecentTaskInfo> recent=activities.getRecentTasks(24,
                ActivityManager.RECENT_IGNORE_UNAVAILABLE|ActivityManager.RECENT_WITH_EXCLUDED);
            for(ActivityManager.RecentTaskInfo task:recent){
                int id=task.id>=0?task.id:task.persistentId;
                ComponentName component=task.topActivity!=null?task.topActivity:
                    task.baseActivity!=null?task.baseActivity:
                    task.origActivity!=null?task.origActivity:task.baseIntent==null?null:task.baseIntent.getComponent();
                if(id<0||component==null||!running.contains(id))continue;
                String pkg=component.getPackageName();
                if(protectedPackages.contains(pkg)||!seen.add(pkg))continue;
                ApplicationInfo app=packages.getApplicationInfo(pkg,0);
                if(!app.enabled)continue;
                JSONObject item=new JSONObject().put("taskId",id).put("package",pkg)
                    .put("label",packages.getApplicationLabel(app).toString())
                    .put("locked",locked.contains(id))
                    .put("icon",encodeDrawable(packages.getApplicationIcon(app),96));
                Bitmap preview=taskSnapshot(id);
                if(preview!=null){
                    item.put("snapshot",encodeBitmap(preview,Bitmap.CompressFormat.JPEG,76,720));
                    preview.recycle();
                }
                result.put(item);allowed.add(id);
            }
        }catch(Exception e){android.util.Log.w("UniRecents","Unable to read recent tasks",e);}
        locked.retainAll(allowed);
        return result;
    }

    public synchronized boolean open(int taskId){
        if(!allowed.contains(taskId))return false;
        try{
            // Embedded map tasks live on ActivityView's virtual display. Move
            // their stack back to display 0 before restoring the card.
            Object service=ActivityManager.class.getMethod("getService").invoke(null);
            Class<?> api=Class.forName("android.app.IActivityManager");
            for(Object stack:(List<?>)api.getMethod("getAllStackInfos").invoke(service)){
                Class<?> type=stack.getClass();int[] ids=(int[])type.getField("taskIds").get(stack);
                if(ids==null)continue;
                for(int id:ids)if(id==taskId){
                    int display=type.getField("displayId").getInt(stack);
                    if(display!=0)api.getMethod("moveStackToDisplay",int.class,int.class)
                        .invoke(service,type.getField("stackId").getInt(stack),0);
                    break;
                }
            }
            activities.moveTaskToFront(taskId,0);return true;
        }
        catch(RuntimeException e){android.util.Log.w("UniRecents","Unable to open task "+taskId,e);return false;}
        catch(Exception e){android.util.Log.w("UniRecents","Unable to restore task "+taskId,e);return false;}
    }

    public synchronized Boolean toggleLock(int taskId){
        if(!allowed.contains(taskId))return null;
        if(!locked.remove(taskId))locked.add(taskId);
        return locked.contains(taskId);
    }

    public synchronized boolean remove(int taskId){
        if(locked.contains(taskId)||!allowed.remove(taskId)||!canRemove())return false;
        return removeUnchecked(taskId);
    }

    public synchronized int clear(){
        if(!canRemove())return 0;
        int count=0;
        for(Integer id:new LinkedHashSet<>(allowed)){
            if(locked.contains(id))continue;
            if(removeUnchecked(id))count++;
        }
        allowed.clear();allowed.addAll(locked);return count;
    }

    private boolean removeUnchecked(int taskId){
        try{
            Object service=ActivityManager.class.getMethod("getService").invoke(null);
            Object result=Class.forName("android.app.IActivityManager").getMethod("removeTask",int.class).invoke(service,taskId);
            return !(result instanceof Boolean)||((Boolean)result).booleanValue();
        }catch(Exception e){android.util.Log.w("UniRecents","Unable to remove task "+taskId,e);return false;}
    }

    @android.annotation.SuppressLint("BlockedPrivateApi")
    private Bitmap taskSnapshot(int taskId){
        try{
            Object service=ActivityManager.class.getMethod("getService").invoke(null);
            Object snapshot=Class.forName("android.app.IActivityManager")
                .getMethod("getTaskSnapshot",int.class,boolean.class).invoke(service,taskId,true);
            if(snapshot==null)return null;
            Object buffer=snapshot.getClass().getMethod("getSnapshot").invoke(snapshot);
            if(buffer==null)return null;
            Class<?> graphicBuffer=Class.forName("android.graphics.GraphicBuffer");
            Method create=Bitmap.class.getDeclaredMethod("createHardwareBitmap",graphicBuffer);
            create.setAccessible(true);
            Bitmap hardware=(Bitmap)create.invoke(null,buffer);
            return hardware==null?null:hardware.copy(Bitmap.Config.ARGB_8888,false);
        }catch(Exception e){
            android.util.Log.d("UniRecents","No snapshot for task "+taskId+": "+e.getClass().getSimpleName());
            return null;
        }
    }

    private static String encodeDrawable(Drawable drawable,int size){
        Bitmap bitmap=Bitmap.createBitmap(size,size,Bitmap.Config.ARGB_8888);
        Canvas canvas=new Canvas(bitmap);drawable.setBounds(0,0,size,size);drawable.draw(canvas);
        String value=encodeBitmap(bitmap,Bitmap.CompressFormat.PNG,100,size);bitmap.recycle();return value;
    }

    private static String encodeBitmap(Bitmap source,Bitmap.CompressFormat format,int quality,int maxWidth){
        Bitmap output=source;
        if(source.getWidth()>maxWidth){
            int height=Math.max(1,Math.round(source.getHeight()*maxWidth/(float)source.getWidth()));
            output=Bitmap.createScaledBitmap(source,maxWidth,height,true);
        }
        ByteArrayOutputStream bytes=new ByteArrayOutputStream();output.compress(format,quality,bytes);
        if(output!=source)output.recycle();
        return "data:image/"+(format==Bitmap.CompressFormat.PNG?"png":"jpeg")+";base64,"+
            Base64.encodeToString(bytes.toByteArray(),Base64.NO_WRAP);
    }
}
