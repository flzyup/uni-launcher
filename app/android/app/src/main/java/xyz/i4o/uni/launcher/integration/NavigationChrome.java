package xyz.i4o.uni.launcher.integration;

import android.app.Activity;
import android.content.SharedPreferences;
import android.content.pm.PackageManager;
import android.provider.Settings;
import android.view.View;
import xyz.i4o.uni.launcher.log.LogTags;
import xyz.i4o.uni.launcher.log.UniLog;

/** Official window flag path + Dudu's optional policy_control path, preserving prior policy. */
public final class NavigationChrome {
    private static final String GLOBAL_RULE="immersive.navigation=*";
    private final Activity activity;
    private final SharedPreferences prefs;
    public NavigationChrome(Activity activity, SharedPreferences prefs) { this.activity=activity; this.prefs=prefs; }

    /**
     * 把窗口的沉浸状态对齐到偏好。
     *
     * <p>这个方法在一次「从第三方应用返回桌面」里会被调用三次（onStart、onResume、
     * onWindowFocusChanged）。以前它无条件 setSystemUiVisibility + requestApplyInsets
     * + requestLayout：{@code setSystemUiVisibility} 自身就会 requestLayout，于是每一次
     * 返回都会强制整窗重新测量、重新分发 insets，而 content 的 OnLayoutChangeListener
     * 又据此再打一次全量快照。现在只在系统 UI 标志真的变了时才动窗口 —— 值没变时
     * 这条路径是零副作用的。
     */
    public void apply() {
        boolean hide = prefs.getBoolean("hideNavigation", false) || prefs.getBoolean("systemNavigationHidden", false);
        View decor = activity.getWindow().getDecorView();
        int want = hide
            ? View.SYSTEM_UI_FLAG_HIDE_NAVIGATION | View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY | View.SYSTEM_UI_FLAG_FULLSCREEN
            : 0;
        // setSystemUiVisibility 内部会 requestLayout；相同值不调用，返回路径就不再有
        // 那次被动的整窗重排版与随之而来的二次快照。
        if (decor.getSystemUiVisibility() != want) {
            decor.setSystemUiVisibility(want);
            decor.requestApplyInsets();
        }
        if (!prefs.getBoolean("globalNavigation", false) && !prefs.contains("savedPolicy")) return;
        if (activity.checkSelfPermission("android.permission.WRITE_SECURE_SETTINGS") != PackageManager.PERMISSION_GRANTED) return;
        try {
            String current = Settings.Global.getString(activity.getContentResolver(), "policy_control");
            if (hide && prefs.getBoolean("globalNavigation", false)) {
                // 已经是我们的规则：再写一次会让 WindowManager 重算一次沉浸策略，
                // 而这条路径每次 onStart 都会走 —— 值没变就必须不写。
                if (GLOBAL_RULE.equals(current)) { UniLog.d(LogTags.NAV,"全局导航栏策略已是目标状态，跳过写入"); return; }
                // Do not replace another component's immersive configuration.
                if (current != null && current.length()>0) return;
                if (!prefs.contains("savedPolicy")) prefs.edit().putString("savedPolicy", current == null ? "<unset>" : current).apply();
                Settings.Global.putString(activity.getContentResolver(), "policy_control", GLOBAL_RULE);
            } else if (prefs.contains("savedPolicy")) {
                if (GLOBAL_RULE.equals(current)) {
                    String saved=prefs.getString("savedPolicy", "<unset>");
                    Settings.Global.putString(activity.getContentResolver(), "policy_control", "<unset>".equals(saved)?null:saved);
                }
                prefs.edit().remove("savedPolicy").apply();
            }
        } catch (SecurityException e) { UniLog.i(LogTags.NAV, "全局导航栏策略未授权"); }
    }
}
