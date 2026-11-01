package xyz.i4o.uni.launcher.overlay;

import android.content.Context;
import android.content.SharedPreferences;
import android.content.pm.PackageManager;
import android.provider.Settings;

/** Own only our exact policy update; restore the previous value without
 * overwriting later changes made by another app. No overscan or display resize. */
public final class SystemNavigationPolicy {
    private static final String SAVED="uniSystemNavSaved", APPLIED="uniSystemNavApplied";
    private SystemNavigationPolicy(){}
    public static boolean granted(Context c){return c.checkSelfPermission("android.permission.WRITE_SECURE_SETTINGS")==PackageManager.PERMISSION_GRANTED;}
    public static boolean setHidden(Context c,SharedPreferences p,boolean hidden){
        if(!granted(c))return false;
        try{
            String current=Settings.Global.getString(c.getContentResolver(),"policy_control");
            if(hidden){
                String cleaned=removeOwnedFull(current);
                String previous=cleaned==null?"<unset>":cleaned;
                if(p.contains(SAVED)&&java.util.Objects.equals(current,p.getString(APPLIED,"")))previous=p.getString(SAVED,previous);
                else if(p.contains("savedPolicy")&&"immersive.navigation=*".equals(current))previous=p.getString("savedPolicy",previous);
                String desired=merge(current);
                if(!Settings.Global.putString(c.getContentResolver(),"policy_control",desired))return false;
                return p.edit().putString(SAVED,previous).putString(APPLIED,desired).putBoolean("systemNavigationHidden",true).remove("savedPolicy").putBoolean("hideNavigation",false).putBoolean("globalNavigation",false).commit();
            }
            if(p.contains(SAVED)&&java.util.Objects.equals(current,p.getString(APPLIED,""))){
                String saved=p.getString(SAVED,"<unset>");
                if(!Settings.Global.putString(c.getContentResolver(),"policy_control","<unset>".equals(saved)?null:removeOwnedFull(saved)))return false;
            }else if(!p.contains(SAVED)){
                // Recover the exact legacy UNI rule left behind by old builds
                // that removed bookkeeping while the immersive policy remained.
                String cleaned=removeOwnedFull(current);
                if(!java.util.Objects.equals(cleaned,current)
                    &&!Settings.Global.putString(c.getContentResolver(),"policy_control",cleaned))return false;
            }
            return p.edit().remove(SAVED).remove(APPLIED).putBoolean("systemNavigationHidden",false)
                .putBoolean("hideNavigation",false).putBoolean("globalNavigation",false).commit();
        }catch(RuntimeException e){return false;}
    }
    private static String removeOwnedFull(String value){
        if(value==null)return null;
        StringBuilder result=new StringBuilder();
        for(String part:value.split(":")){
            if(part.isEmpty()||"immersive.full=*,-com.ecarx.parking".equals(part)
                ||"immersive.status=*,-com.ecarx.parking".equals(part)
                ||OWNED_RULE.equals(part))continue;
            if(result.length()>0)result.append(':');result.append(part);
        }
        return result.length()==0?null:result.toString();
    }
    private static final String OWNED_RULE="immersive.full=*,-com.ecarx.parking,-com.android.packageinstaller";
    private static String merge(String current){
        StringBuilder result=new StringBuilder();
        // Keep the OEM navigation bar fully hidden: some builds (IP744) still
        // surface it when only the status policy is hidden. Exempt the package
        // installer so its confirmation controls keep the real bottom inset and
        // remain above the UNI dock.
        if(current!=null)for(String part:current.split(":"))if(!part.isEmpty()&&!part.startsWith("immersive.")){
            if(result.length()>0)result.append(':');result.append(part);
        }
        if(result.length()>0)result.append(':');
        return result.append(OWNED_RULE).toString();
    }
}
