package xyz.i4o.uni.launcher.integration;

import android.content.ComponentName;
import android.content.Context;
import android.content.Intent;
import android.content.pm.ActivityInfo;
import android.content.pm.PackageInfo;
import android.content.pm.PackageManager;
import android.content.pm.ResolveInfo;
import android.content.res.Resources;
import android.content.res.AssetManager;
import android.content.res.XmlResourceParser;
import android.provider.Settings;
import java.lang.reflect.Field;
import java.lang.reflect.Modifier;
import java.util.LinkedHashMap;
import java.util.Locale;
import java.util.Map;
import java.util.Set;
import java.util.TreeSet;
import org.json.JSONArray;
import org.json.JSONObject;
import org.xmlpull.v1.XmlPullParser;

/** Main-thread owned discovery cache. Snapshot never calls PackageManager. */
public final class SystemSettingsRepository {
    private static final String ANDROID="http://schemas.android.com/apk/res/android";
    private final Context context;
    private final PackageManager pm;
    private final Map<String,Intent> intents=new LinkedHashMap<>();
    private JSONArray entries=new JSONArray();

    public SystemSettingsRepository(Context context){this.context=context;pm=context.getPackageManager();refresh();}

    public void refresh(){
        intents.clear();entries=new JSONArray();
        Set<String> packages=new TreeSet<>();
        Set<String> actions=new TreeSet<>();
        for(Field field:Settings.class.getFields()){
            if(field.getType()!=String.class||!Modifier.isStatic(field.getModifiers())||!field.getName().startsWith("ACTION_"))continue;
            try{String action=(String)field.get(null);if(action!=null&&action.startsWith("android.settings."))actions.add(action);}
            catch(ReflectiveOperationException|RuntimeException ignored){}
        }
        // A phone/contacts app may handle one Settings action. That does not
        // make every exported activity in that app a settings destination.
        discover(Settings.ACTION_SETTINGS,null,packages);
        for(String action:actions)discover(action,null,null);
        // OEM-only actions need not appear in the platform Settings constants.
        // Installed manifest filters, not an APK-version-specific action list, are the source.
        try{
            for(PackageInfo info:pm.getInstalledPackages(0)){
                if(info.packageName.toLowerCase(Locale.ROOT).contains("settings"))packages.add(info.packageName);
            }
        }catch(RuntimeException ignored){}
        for(String pkg:new TreeSet<>(packages))discoverManifest(pkg);
    }

    private void discover(String action,String pkg,Set<String> packages){
        Intent intent=new Intent(action);if(pkg!=null)intent.setPackage(pkg);
        try{
            for(ResolveInfo resolved:pm.queryIntentActivities(intent,PackageManager.GET_RESOLVED_FILTER)){
                ActivityInfo activity=resolved.activityInfo;
                if(!allowed(activity))continue;
                if(packages!=null)packages.add(activity.packageName);
                add(activity,action,label(activity,resolved,action),"android-settings");
            }
        }catch(RuntimeException ignored){}
    }

    private void discoverManifest(String pkg){
        discoverDeclaredActivities(pkg);
        try{
            Resources resources=pm.getResourcesForApplication(pkg);
            // A merged Resources AssetManager may resolve the framework manifest.
            // Use the installed APK's asset cookie explicitly.
            try(AssetManager assets=AssetManager.class.getConstructor().newInstance()){
            int cookie=(Integer)AssetManager.class.getMethod("addAssetPath",String.class)
                    .invoke(assets,pm.getApplicationInfo(pkg,0).sourceDir);
            if(cookie==0)return;
            try(XmlResourceParser xml=assets.openXmlResourceParser(cookie,"AndroidManifest.xml")){
                String activity=null;boolean filter=false;String filterLabel=null;
                Set<String> actions=new TreeSet<>();
                for(int event=xml.next();event!=XmlPullParser.END_DOCUMENT;event=xml.next()){
                    String tag=xml.getName();
                    if(event==XmlPullParser.START_TAG){
                        if("activity".equals(tag)||"activity-alias".equals(tag))activity=xml.getAttributeValue(ANDROID,"name");
                        else if(activity!=null&&"intent-filter".equals(tag)){
                            filter=true;actions.clear();
                            int resource=xml.getAttributeResourceValue(ANDROID,"label",0);
                            filterLabel=resource!=0?resources.getString(resource):xml.getAttributeValue(ANDROID,"label");
                        }else if(filter&&"action".equals(tag)){
                            String action=xml.getAttributeValue(ANDROID,"name");
                            if(action!=null&&!Intent.ACTION_MAIN.equals(action))actions.add(action);
                        }
                    }else if(event==XmlPullParser.END_TAG){
                        if("intent-filter".equals(tag)&&activity!=null){
                            String name=activity.startsWith(".")?pkg+activity:activity.contains(".")?activity:pkg+"."+activity;
                            ActivityInfo info=pm.getActivityInfo(new ComponentName(pkg,name),0);
                            if(allowed(info))for(String action:actions){
                                String title=label(info,null,action);
                                if(filterLabel!=null&&!filterLabel.trim().isEmpty()&&actions.size()==1)title=filterLabel;
                                add(info,action,title,"manifest");
                            }
                            filter=false;
                        }else if("activity".equals(tag)||"activity-alias".equals(tag))activity=null;
                    }
                }
            }
        }
        }catch(Exception|LinkageError ignored){/* Restricted or missing package: omit it. */}
    }

    private void discoverDeclaredActivities(String pkg){
        try{
            PackageInfo pack=pm.getPackageInfo(pkg,PackageManager.GET_ACTIVITIES|PackageManager.GET_META_DATA);
            if(pack.activities==null)return;
            for(ActivityInfo info:pack.activities){
                if(!allowed(info))continue;
                String title=dashboardTitle(info);
                if(title==null&&"com.ecarx.settings.drivemode.DriveModeActivity".equals(info.name)){
                    Resources resources=pm.getResourcesForApplication(pkg);
                    int id=resources.getIdentifier("drive_mode","string",pkg);if(id!=0)title=resources.getString(id);
                }
                if(title==null){CharSequence loaded=info.loadLabel(pm);title=loaded==null?info.name:loaded.toString();}
                add(info,"",title,"activity");
            }
        }catch(Exception|LinkageError ignored){}
    }

    private String sourceLabel(ActivityInfo info){
        if("com.ecarx.settings".equals(info.packageName))return "原车设置";
        if("com.android.settings".equals(info.packageName))return "Android 设置";
        CharSequence label=info.applicationInfo.loadLabel(pm);
        return label==null||label.toString().trim().isEmpty()?"系统设置":label.toString().trim();
    }

    private String dashboardTitle(ActivityInfo activity){
        try{
            ActivityInfo info=pm.getActivityInfo(new ComponentName(activity.packageName,activity.name),PackageManager.GET_META_DATA);
            if(info.metaData==null)return null;
            Resources resources=pm.getResourcesForApplication(info.packageName);
            for(String key:new String[]{"com.android.settings.title","com.android.settings.FRAGMENT_TITLE"}){
                Object value=info.metaData.get(key);
                if(value instanceof Integer){String text=resources.getString((Integer)value);if(!text.trim().isEmpty())return text;}
                if(value instanceof String&&!((String)value).trim().isEmpty())return ((String)value).trim();
            }
            int resource;
            // Only settings/dashboard metadata is relevant; shortcuts are not titles.
            for(String key:info.metaData.keySet()){
                if(!key.toLowerCase(Locale.ROOT).contains("dashboard"))continue;
                Object value=info.metaData.get(key);if(!(value instanceof Integer))continue;
                resource=(Integer)value;
                try(XmlResourceParser xml=resources.getXml(resource)){
                    for(int event=xml.next();event!=XmlPullParser.END_DOCUMENT;event=xml.next()){
                        if(event!=XmlPullParser.START_TAG)continue;
                        // Only a root title describes this activity. Child tiles
                        // describe other destinations and must not relabel it.
                        if(xml.getDepth()!=1)continue;
                        int title=xml.getAttributeResourceValue(ANDROID,"title",0);
                        if(title!=0){String text=resources.getString(title);if(!text.trim().isEmpty())return text;}
                        String literal=xml.getAttributeValue(ANDROID,"title");if(literal!=null&&!literal.trim().isEmpty())return literal;
                    }
                }
            }
        }catch(Exception ignored){}
        return null;
    }

    private boolean allowed(ActivityInfo info){
        if(info==null||!info.exported||!info.enabled||info.applicationInfo==null||!info.applicationInfo.enabled)return false;
        if(info.permission!=null&&!info.permission.isEmpty()&&context.checkSelfPermission(info.permission)!=PackageManager.PERMISSION_GRANTED)return false;
        try{
            int app=pm.getApplicationEnabledSetting(info.packageName);
            int component=pm.getComponentEnabledSetting(new ComponentName(info.packageName,info.name));
            return (app==PackageManager.COMPONENT_ENABLED_STATE_DEFAULT||app==PackageManager.COMPONENT_ENABLED_STATE_ENABLED)
                    &&(component==PackageManager.COMPONENT_ENABLED_STATE_DEFAULT||component==PackageManager.COMPONENT_ENABLED_STATE_ENABLED);
        }catch(RuntimeException e){return false;}
    }

    private String label(ActivityInfo info,ResolveInfo resolved,String action){
        String token=action.substring(action.lastIndexOf('.')+1);
        String stem=token.toLowerCase(Locale.ROOT).replaceFirst("_(settings|fragment)$","");
        try{
            Resources resources=pm.getResourcesForApplication(info.packageName);
            // Resource names verified in the local OEM R$string table. IDs remain
            // dynamic so translations and firmware resource renumbering are honored.
            String special=null;
            switch(token){
                case "AP_SETTINGS": special="name_ap";break;
                case "DRIVER_FRAGMENT": special="item_title_driver_support";break;
                case "TIMEFORMAT_SETTINGS": special="system_time_format";break;
                case "OPEN_DRIVE_MODE_VIEW": special="drive_mode";break;
                case "WIRELESS_SETTINGS": special="name_network";break;
            }
            if(special!=null){int id=resources.getIdentifier(special,"string",info.packageName);if(id!=0){String text=resources.getString(id);if(!text.trim().isEmpty())return text;}}
            for(String key:new String[]{"name_"+stem,"item_title_"+stem,stem+"_settings_title",stem+"_title","setting_"+stem,"settings_"+stem,stem}){
                int id=resources.getIdentifier(key,"string",info.packageName);
                if(id!=0){String value=resources.getString(id);if(!value.trim().isEmpty())return value;}
            }
        }catch(Exception ignored){}
        CharSequence title=resolved!=null?resolved.loadLabel(pm):info.loadLabel(pm);
        String dashboard=dashboardTitle(info);if(dashboard!=null&&!dashboard.trim().isEmpty())return dashboard;
        CharSequence appLabel=info.applicationInfo.loadLabel(pm);
        if(title!=null&&!title.toString().trim().isEmpty()&&(appLabel==null||!title.toString().contentEquals(appLabel)))return title.toString();
        // Keep technical disambiguation in activity/action metadata, never in the label.
        return title==null?sourceLabel(info):title.toString();
    }

    private void add(ActivityInfo info,String action,String label,String source){
        label=label==null?"":label.trim();
        if(label.isEmpty())label=sourceLabel(info);
        ComponentName component=new ComponentName(info.packageName,info.name);
        String id=component.flattenToString()+"|"+action;
        if(intents.containsKey(id)){
            if("manifest".equals(source))for(int i=0;i<entries.length();i++){
                JSONObject existing=entries.optJSONObject(i);
                if(existing!=null&&id.equals(existing.optString("id")))try{existing.put("label",label).put("source",sourceLabel(info));}catch(org.json.JSONException ignored){}
            }
            return;
        }
        try{
            entries.put(new JSONObject().put("id",id).put("label",label).put("source",sourceLabel(info))
                    .put("package",info.packageName).put("activity",info.name).put("action",action));
            intents.put(id,(action.isEmpty()?new Intent():new Intent(action)).setComponent(component).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK));
        }catch(org.json.JSONException ignored){}
    }

    public JSONArray snapshot(){
        try{return new JSONArray(entries.toString());}catch(org.json.JSONException e){return new JSONArray();}
    }

    public boolean open(String id){
        Intent intent=intents.get(id);if(intent==null)return false;
        try{
            if(!allowed(pm.getActivityInfo(intent.getComponent(),0)))return false;
            context.startActivity(new Intent(intent));return true;
        }catch(Exception|LinkageError e){return false;}
    }
}
