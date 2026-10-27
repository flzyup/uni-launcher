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

public final class AppRepository {
    private final Context context;
    private final Map<String, ComponentName> allowed = new LinkedHashMap<String, ComponentName>();
    public AppRepository(Context context) {this.context=context;}
    public JSONArray refresh() {
        allowed.clear(); JSONArray result=new JSONArray();
        Intent query=new Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER);
        List<ResolveInfo> apps=context.getPackageManager().queryIntentActivities(query,0);
        Collections.sort(apps,new Comparator<ResolveInfo>() {
            public int compare(ResolveInfo a,ResolveInfo b){return a.loadLabel(context.getPackageManager()).toString().compareTo(b.loadLabel(context.getPackageManager()).toString());}
        });
        for(ResolveInfo app:apps) try {
            if (!usable(app.activityInfo)) continue;
            if(context.getPackageName().equals(app.activityInfo.packageName))continue;
            ComponentName c=new ComponentName(app.activityInfo.packageName,app.activityInfo.name);
            String key=c.flattenToString(); if(allowed.containsKey(key))continue;
            allowed.put(key,c);
            Drawable drawable=app.loadIcon(context.getPackageManager());
            Bitmap bitmap=Bitmap.createBitmap(72,72,Bitmap.Config.ARGB_8888);Canvas canvas=new Canvas(bitmap);
            drawable.setBounds(0,0,72,72);drawable.draw(canvas);
            ByteArrayOutputStream out=new ByteArrayOutputStream();bitmap.compress(Bitmap.CompressFormat.PNG,100,out);bitmap.recycle();
            result.put(new JSONObject().put("id",key).put("package",app.activityInfo.packageName).put("label",app.loadLabel(context.getPackageManager()).toString()).put("canUninstall",canUninstall(app.activityInfo.packageName))
                .put("icon","data:image/png;base64,"+Base64.encodeToString(out.toByteArray(),Base64.NO_WRAP)));
        } catch(Exception e){android.util.Log.w("UniApps","Unable to read app icon",e);}
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
