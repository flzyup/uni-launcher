package xyz.i4o.uni.launcher;

import android.content.ComponentName;
import android.content.Context;
import android.content.Intent;
import android.content.IntentFilter;
import android.app.ActivityManager;
import android.content.pm.PackageManager;
import android.content.pm.ResolveInfo;
import java.util.ArrayList;
import java.util.List;
import xyz.i4o.uni.launcher.log.LogTags;
import xyz.i4o.uni.launcher.log.UniLog;

/** Restores the launcher's HOME preference during the boot window. */
public final class DefaultHomeGuard {
    private DefaultHomeGuard() {}

    static boolean restoreIfNeeded(Context context) {
        final android.content.SharedPreferences prefs = context.getSharedPreferences("launcher", Context.MODE_PRIVATE);
        final boolean bootAutostart = prefs.getBoolean("bootAutostart", true);
        final String homeKeyTarget = prefs.getString("homeKeyTarget", "uni");
        if (!bootAutostart || "oem".equals(homeKeyTarget)) {
            UniLog.i(LogTags.SYS, "跳过恢复默认桌面 (bootAutostart=" + bootAutostart + ", homeKeyTarget=" + homeKeyTarget + ")", "tag", "UniHome");
            return false;
        }
        final ComponentName own = new ComponentName(context, MainActivity.class);
        final Intent home = new Intent(Intent.ACTION_MAIN)
            .addCategory(Intent.CATEGORY_HOME)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
        UniLog.enter(LogTags.SYS,"home/guard");
        try {
            ResolveInfo resolved = context.getPackageManager().resolveActivity(home, 0);
            ComponentName current = resolved == null || resolved.activityInfo == null ? null
                : new ComponentName(resolved.activityInfo.packageName, resolved.activityInfo.name);
            // IP753's boot path resolves HOME through the OEM launcher before
            // replacing the always record. That intermediate state cannot be
            // distinguished from a later user choice during the boot window, so
            // the launcher restores its own registered role on every check.
            UniLog.i(LogTags.SYS, "current home=" + current, "tag","UniHome");

            PackageManager pm = context.getPackageManager();
            List<ResolveInfo> candidates = pm.queryIntentActivities(home, PackageManager.MATCH_DEFAULT_ONLY);
            ArrayList<ComponentName> components = new ArrayList<>();
            for (ResolveInfo candidate : candidates) {
                if (candidate.activityInfo != null) components.add(new ComponentName(
                    candidate.activityInfo.packageName, candidate.activityInfo.name));
            }
            if (!components.contains(own)) {
                UniLog.w(LogTags.SYS, "UNI is not a HOME candidate", "tag","UniHome");
                UniLog.skip(LogTags.SYS,"home/guard","reason","not-a-home-candidate");
                return false;
            }
            IntentFilter filter = new IntentFilter(Intent.ACTION_MAIN);
            filter.addCategory(Intent.CATEGORY_HOME);
            filter.addCategory(Intent.CATEGORY_DEFAULT);
            // System API on Android 9, omitted from the public SDK stubs.
            java.lang.reflect.Method replace = PackageManager.class.getDeclaredMethod(
                "replacePreferredActivity", IntentFilter.class, int.class,
                ComponentName[].class, ComponentName.class);
            replace.setAccessible(true);
            replace.invoke(pm, filter, IntentFilter.MATCH_CATEGORY_EMPTY,
                components.toArray(new ComponentName[0]), own);
            ResolveInfo after = pm.resolveActivity(home, PackageManager.MATCH_DEFAULT_ONLY);
            boolean success = after != null && after.activityInfo != null
                && own.equals(new ComponentName(after.activityInfo.packageName, after.activityInfo.name));
            UniLog.i(LogTags.SYS, "HOME restore result=" + success, "tag","UniHome");
            if(success)UniLog.done(LogTags.SYS,"home/guard","home",String.valueOf(current));
            else UniLog.fail(LogTags.SYS,"home/guard","home",String.valueOf(current),"reason","not-restored");
            return success;
        } catch (Exception | LinkageError e) {
            UniLog.w(LogTags.SYS, "Unable to restore default home", e, "tag","UniHome");
            UniLog.fail(LogTags.SYS,"home/guard","error",e.getClass().getSimpleName());
            return false;
        }
    }

    /** Close the boot-time resolver only after the preference was restored. */
    static void dismissResolver(Context context) {
        try {
            ActivityManager tasks = (ActivityManager)
                context.getSystemService(Context.ACTIVITY_SERVICE);
            List<ActivityManager.RunningTaskInfo> running = tasks.getRunningTasks(1);
            boolean resolverForeground = !running.isEmpty()
                && running.get(0).topActivity != null
                && "android".equals(running.get(0).topActivity.getPackageName());
            if (!resolverForeground) return;
            context.startActivity(new Intent(Intent.ACTION_MAIN)
                .addCategory(Intent.CATEGORY_HOME)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK));
        } catch (Exception | LinkageError e) {
            UniLog.w(LogTags.SYS, "Unable to dismiss home resolver", e, "tag","UniHome");
        }
    }
}
