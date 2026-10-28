package xyz.i4o.uni.launcher.integration;

import android.content.Context;
import android.content.Intent;
import android.content.ComponentName;
import android.content.pm.ResolveInfo;
import android.content.pm.ActivityInfo;
import android.content.pm.ApplicationInfo;
import android.content.pm.PackageManager;
import android.graphics.Bitmap;
import android.graphics.Canvas;
import android.graphics.drawable.Drawable;
import android.util.Base64;
import org.json.JSONArray;
import org.json.JSONObject;
import java.io.ByteArrayOutputStream;
import java.util.Collections;
import java.util.Comparator;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.HashSet;
import java.util.Set;

public final class AppRepository {
    private final Context context;
    private final Map<String, ComponentName> allowed = new LinkedHashMap<String, ComponentName>();
    public AppRepository(Context context) {this.context=context;}
    public JSONArray refresh() {
        long traceStart=android.os.SystemClock.uptimeMillis();
        allowed.clear(); JSONArray result=new JSONArray();
        Set<String> players=musicPackages();
        Intent query=new Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER);
        PackageManager pm=context.getPackageManager();
        List<ResolveInfo> apps=pm.queryIntentActivities(query,0);
        long afterQuery=android.os.SystemClock.uptimeMillis();
        // loadLabel is a resource lookup per call; the old comparator called it
        // twice for every comparison (~n log n IPCs). Read each label once.
        int count=apps.size();
        final String[] labels=new String[count];
        for(int i=0;i<count;i++){
            try{labels[i]=apps.get(i).loadLabel(pm).toString();}catch(RuntimeException e){labels[i]="";}
        }
        Integer[] order=new Integer[count];
        for(int i=0;i<count;i++)order[i]=i;
        java.util.Arrays.sort(order,new Comparator<Integer>() {
            public int compare(Integer a,Integer b){return labels[a].compareTo(labels[b]);}
        });
        // Device-policy answers are identical for every app in one refresh.
        boolean uninstallAllowed=uninstallAllowed();
        Set<String> admins=activeAdminPackages();
        long afterLabels=android.os.SystemClock.uptimeMillis();
        String self=context.getPackageName();
        for(Integer index:order){
            ResolveInfo app=apps.get(index);
            try{
                if(!usable(app.activityInfo))continue;
                String pkg=app.activityInfo.packageName;
                if(self.equals(pkg)&&!"xyz.i4o.uni.launcher.DesktopSettings".equals(app.activityInfo.name))continue;
                ComponentName c=new ComponentName(pkg,app.activityInfo.name);
                String key=c.flattenToString();
                if(allowed.containsKey(key))continue;
                allowed.put(key,c);
                // flags come with the resolve result, so this needs no extra IPC.
                ApplicationInfo info=app.activityInfo.applicationInfo;
                boolean uninstallable=uninstallAllowed&&!self.equals(pkg)&&!admins.contains(pkg)
                    &&(info==null||(info.flags&(ApplicationInfo.FLAG_SYSTEM|ApplicationInfo.FLAG_UPDATED_SYSTEM_APP))==0);
                result.put(new JSONObject().put("id",key).put("package",pkg).put("label",labels[index])
                    .put("canUninstall",uninstallable).put("isMusic",players.contains(pkg))
                    .put("icon","data:image/webp;base64,"+iconBase64(app,info,pkg,pm)));
            }catch(Exception e){android.util.Log.w("UniApps","Unable to read app icon",e);}
        }
        long end=android.os.SystemClock.uptimeMillis();
        android.util.Log.i("UNI-Startup","apps="+result.length()
            +" query="+(afterQuery-traceStart)+" labels="+(afterLabels-afterQuery)
            +" icons="+(end-afterLabels)+" refresh="+(end-traceStart));
        return result;
    }

    /** Icons dominate start-up: each app costs an inflate, a 72x72 draw and an
     * encode. Encode once per installed build and keep the bytes on disk, so a
     * later start only reads a few KB instead of touching package resources. */
    private String iconBase64(ResolveInfo app,ApplicationInfo info,String pkg,PackageManager pm)throws Exception{
        long stamp=info==null||info.sourceDir==null?0:new java.io.File(info.sourceDir).lastModified();
        String name=pkg.replaceAll("[^A-Za-z0-9._]","_")+"-"+stamp+".img";
        java.io.File cached=new java.io.File(iconCacheDir(),name);
        byte[] bytes=null;
        try{if(cached.isFile()&&cached.length()>0)bytes=java.nio.file.Files.readAllBytes(cached.toPath());}catch(Exception ignored){}
        if(bytes==null||bytes.length==0){
            Drawable drawable=app.loadIcon(pm);
            Bitmap bitmap=Bitmap.createBitmap(72,72,Bitmap.Config.ARGB_8888);
            Canvas canvas=new Canvas(bitmap);
            drawable.setBounds(0,0,72,72);drawable.draw(canvas);
            ByteArrayOutputStream out=new ByteArrayOutputStream();
            // WebP keeps alpha and is roughly a third of the PNG size at this size.
            bitmap.compress(Bitmap.CompressFormat.WEBP,80,out);
            bitmap.recycle();
            bytes=out.toByteArray();
            try{cached.getParentFile().mkdirs();java.nio.file.Files.write(cached.toPath(),bytes);}catch(Exception ignored){}
        }
        return Base64.encodeToString(bytes,Base64.NO_WRAP);
    }

    private java.io.File iconCacheDir(){
        java.io.File dir=new java.io.File(context.getCacheDir(),"app-icons");
        java.io.File[] existing=dir.listFiles();
        if(existing!=null&&existing.length>400)for(java.io.File file:existing)file.delete();
        return dir;
    }

    private boolean uninstallAllowed(){
        try{
            android.os.UserManager users=(android.os.UserManager)context.getSystemService(Context.USER_SERVICE);
            return users==null||!users.hasUserRestriction(android.os.UserManager.DISALLOW_UNINSTALL_APPS);
        }catch(Exception e){return false;}
    }

    private Set<String> activeAdminPackages(){
        Set<String> result=new HashSet<>();
        try{
            android.app.admin.DevicePolicyManager policy=
                (android.app.admin.DevicePolicyManager)context.getSystemService(Context.DEVICE_POLICY_SERVICE);
            List<ComponentName> admins=policy==null?null:policy.getActiveAdmins();
            if(admins!=null)for(ComponentName admin:admins)result.add(admin.getPackageName());
        }catch(Exception ignored){}
        return result;
    }
    private Set<String> musicPackages(){
        Set<String> result=new HashSet<>();
        Collections.addAll(result,"com.tencent.qqmusiccar","com.tencent.qqmusic","com.netease.cloudmusic.iot","ecarx.xsf.mediacenter");
        PackageManager pm=context.getPackageManager();
        try{for(ResolveInfo r:pm.queryIntentServices(new Intent("android.media.browse.MediaBrowserService"),0))
            if(r.serviceInfo!=null&&r.serviceInfo.enabled&&r.serviceInfo.exported)result.add(r.serviceInfo.packageName);}catch(RuntimeException ignored){}
        try{for(ResolveInfo r:pm.queryIntentActivities(new Intent(Intent.ACTION_MAIN).addCategory("android.intent.category.APP_MUSIC"),0))
            if(usable(r.activityInfo))result.add(r.activityInfo.packageName);}catch(RuntimeException ignored){}
        return result;
    }
    public boolean canUninstall(String pkg){
        try{
            ApplicationInfo a=context.getPackageManager().getApplicationInfo(pkg,0);
            if(context.getPackageName().equals(pkg)||(a.flags&(ApplicationInfo.FLAG_SYSTEM|ApplicationInfo.FLAG_UPDATED_SYSTEM_APP))!=0)return false;
            android.os.UserManager users=(android.os.UserManager)context.getSystemService(Context.USER_SERVICE);
            if(users.hasUserRestriction(android.os.UserManager.DISALLOW_UNINSTALL_APPS))return false;
            android.app.admin.DevicePolicyManager policy=(android.app.admin.DevicePolicyManager)context.getSystemService(Context.DEVICE_POLICY_SERVICE);
            java.util.List<ComponentName> admins=policy.getActiveAdmins();
            if(admins!=null)for(ComponentName admin:admins)if(pkg.equals(admin.getPackageName()))return false;
            return true;
        }catch(Exception e){return false;}
    }
    private boolean knownPackage(String pkg){for(ComponentName c:allowed.values())if(c.getPackageName().equals(pkg))return true;return false;}
    public boolean showInfo(String pkg){
        if(!knownPackage(pkg))return false;
        try{context.startActivity(new Intent(android.provider.Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
            android.net.Uri.parse("package:"+pkg)).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK));return true;}
        catch(RuntimeException e){return false;}
    }
    public boolean requestUninstall(String pkg){
        if(!knownPackage(pkg)||!canUninstall(pkg))return false;
        try{context.startActivity(new Intent(Intent.ACTION_UNINSTALL_PACKAGE,android.net.Uri.parse("package:"+pkg))
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK));return true;}
        catch(RuntimeException e){return false;}
    }
    public boolean launch(String key) {
        ComponentName c=allowed.get(key);if(c==null)return false;
        try {if (!usable(context.getPackageManager().getActivityInfo(c,0))) return false;
            context.startActivity(new Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER).setComponent(c).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK));return true;}
        catch(Exception e){return false;}
    }
    public boolean launchPackage(String pkg) {
        try {
            Intent i = packageIntent(pkg);
            if (i == null) return false;
            context.startActivity(i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK));return true;
        } catch(Exception e){return false;}
    }
    public String packageStatus(String pkg) {
        if (pkg == null || pkg.length() == 0) return "not-installed";
        try {
            ApplicationInfo app = context.getPackageManager().getApplicationInfo(pkg,0);
            if (!app.enabled) return "disabled";
            return packageIntent(pkg) == null ? "no-accessible-launcher" : "available";
        } catch (PackageManager.NameNotFoundException e) { return "not-installed"; }
        catch (Exception e) { return "unavailable"; }
    }
    private Intent packageIntent(String pkg) throws PackageManager.NameNotFoundException {
        if (pkg == null || pkg.length() == 0) return null;
        PackageManager pm = context.getPackageManager();
        if (!pm.getApplicationInfo(pkg,0).enabled) return null;
        Intent intent = pm.getLaunchIntentForPackage(pkg);
        if (intent == null) return null;
        ResolveInfo resolved = pm.resolveActivity(intent,0);
        if (resolved == null || !usable(resolved.activityInfo) || !pkg.equals(resolved.activityInfo.packageName)) return null;
        // Pin the checked component; do not let implicit resolution pick a different application.
        return new Intent(intent).setComponent(new ComponentName(pkg,resolved.activityInfo.name));
    }
    private boolean usable(ActivityInfo info) {
        return info != null && info.enabled && info.applicationInfo != null && info.applicationInfo.enabled
            && info.exported && (info.permission == null || info.permission.length() == 0
                || context.checkSelfPermission(info.permission) == PackageManager.PERMISSION_GRANTED);
    }
    public boolean launchOfficial(String type) {
        for (String pkg : new OfficialCatalog(context).applicationPackages(type)) {
            if (launchPackage(pkg)) return true;
        }
        return false;
    }
    /** Official Launcher3 CarUtils.updateApps flow: the firmware ships both
     * parking activities component-disabled, so a HOME launcher must enable the
     * component matching the PAC capability read from 0x23050080 before start.
     * capability comes from OfficialCarReader.cameraCapability(); -1/none means
     * this vehicle exposes no manual camera entry. */
    public boolean launchOfficialCamera(int capability) {
        PackageManager pm=context.getPackageManager();
        ComponentName avm=new ComponentName("com.ecarx.parking","com.ecarx.park2.MainAvmActivity");
        ComponentName pac=new ComponentName("com.ecarx.parking","com.ecarx.park2.MainPacActivity");
        try{
            if(capability==OfficialCarContract.PAC_CAMERA_360AM){
                setCameraComponent(pm,avm,true);setCameraComponent(pm,pac,false);
                return startCameraComponent(avm);
            }
            if(capability==OfficialCarContract.PAC_CAMERA_REARONLY){
                setCameraComponent(pm,pac,true);setCameraComponent(pm,avm,false);
                return startCameraComponent(pac);
            }
            // This IP753 reports 255 for the capability function while the OEM
            // itself has already enabled MainAvmActivity at power-on. Respect
            // the current component states: start whichever is enabled.
            if(startCameraComponent(avm))return true;
            return startCameraComponent(pac);
        }catch(Exception e){return false;}
    }
    /** Compatibility entry used by the retained WebView reference build. */
    public boolean launchOfficialAvm(){return launchOfficialCamera(-1);}
    private void setCameraComponent(PackageManager pm,ComponentName c,boolean enabled){
        try{pm.setComponentEnabledSetting(c,
                enabled?PackageManager.COMPONENT_ENABLED_STATE_ENABLED:PackageManager.COMPONENT_ENABLED_STATE_DISABLED,
                PackageManager.DONT_KILL_APP);}catch(RuntimeException ignored){}
    }
    private boolean startCameraComponent(ComponentName c){
        try{
            ActivityInfo info=context.getPackageManager().getActivityInfo(c,0);
            if(info==null||!info.exported)return false;
            context.startActivity(new Intent(Intent.ACTION_MAIN).setComponent(c).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK));return true;
        }catch(Exception e){return false;}
    }
}
