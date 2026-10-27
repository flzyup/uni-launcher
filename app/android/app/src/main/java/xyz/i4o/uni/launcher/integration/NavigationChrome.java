package xyz.i4o.uni.launcher.integration;

import android.app.Activity;
import android.content.SharedPreferences;
import android.content.pm.PackageManager;
import android.provider.Settings;
import android.view.View;

/** Official window flag path + Dudu's optional policy_control path, preserving prior policy. */
public final class NavigationChrome {
    private final Activity activity;
    private final SharedPreferences prefs;
    public NavigationChrome(Activity activity, SharedPreferences prefs) { this.activity=activity; this.prefs=prefs; }
    public void apply() {
        boolean nativeInsets=prefs.getBoolean("uniNativeInsetsApplied",false);
        boolean hide = !nativeInsets&&(prefs.getBoolean("hideNavigation", false) || prefs.getBoolean("systemNavigationHidden", false));
        activity.getWindow().getDecorView().setSystemUiVisibility(hide
            ? View.SYSTEM_UI_FLAG_HIDE_NAVIGATION | View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY | View.SYSTEM_UI_FLAG_FULLSCREEN : 0);
        if (!prefs.getBoolean("globalNavigation", false) && !prefs.contains("savedPolicy")) return;
        if (activity.checkSelfPermission("android.permission.WRITE_SECURE_SETTINGS") != PackageManager.PERMISSION_GRANTED) return;
        try {
            String current = Settings.Global.getString(activity.getContentResolver(), "policy_control");
            if (hide && prefs.getBoolean("globalNavigation", false)) {
                // Do not replace another component's immersive configuration.
                if (current != null && current.length()>0 && !"immersive.navigation=*".equals(current)) return;
                if (!prefs.contains("savedPolicy")) prefs.edit().putString("savedPolicy", current == null ? "<unset>" : current).commit();
                Settings.Global.putString(activity.getContentResolver(), "policy_control", "immersive.navigation=*");
            } else if (prefs.contains("savedPolicy")) {
                if ("immersive.navigation=*".equals(current)) {
                    String saved=prefs.getString("savedPolicy", "<unset>");
                    Settings.Global.putString(activity.getContentResolver(), "policy_control", "<unset>".equals(saved)?null:saved);
                }
                prefs.edit().remove("savedPolicy").apply();
            }
        } catch (SecurityException e) { android.util.Log.i("UniChrome", "Global navigation policy not authorized"); }
    }
}
