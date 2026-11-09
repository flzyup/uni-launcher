package xyz.i4o.uni.launcher;

import android.app.ActivityManager;
import android.content.ComponentName;
import android.content.Context;
import android.content.Intent;
import android.content.IntentFilter;
import android.content.pm.PackageManager;
import android.content.pm.ResolveInfo;
import java.lang.reflect.Method;
import java.util.ArrayList;
import java.util.List;
import xyz.i4o.uni.launcher.log.LogTags;
import xyz.i4o.uni.launcher.log.UniLog;

/** Restores or sets the launcher's HOME preference. */
public final class DefaultHomeGuard {
    private DefaultHomeGuard() {}

    /**
     * Resolve the target ComponentName for the given target package/component.
     * If target is null, empty, "uni", or this package, returns UNI MainActivity.
     * If target contains "/", unflattens it.
     * Otherwise finds matching candidate from pm.queryIntentActivities(home, 0).
     */
    public static ComponentName resolveTargetComponent(Context context, String target) {
        final ComponentName own = new ComponentName(context, MainActivity.class);
        if (target == null || target.trim().isEmpty() || "uni".equals(target) || context.getPackageName().equals(target)) {
            return own;
        }
        String cleanTarget = target.trim();
        if ("oem".equals(cleanTarget)) {
            cleanTarget = "ecarx.launcher3";
        }
        if (cleanTarget.contains("/")) {
            ComponentName cn = ComponentName.unflattenFromString(cleanTarget);
            if (cn != null) return cn;
        }
        final Intent home = new Intent(Intent.ACTION_MAIN)
            .addCategory(Intent.CATEGORY_HOME);
        List<ResolveInfo> candidates = context.getPackageManager().queryIntentActivities(home, 0);
        if (candidates != null) {
            for (ResolveInfo ri : candidates) {
                if (ri.activityInfo != null && cleanTarget.equals(ri.activityInfo.packageName)) {
                    return new ComponentName(ri.activityInfo.packageName, ri.activityInfo.name);
                }
            }
            // Fallback: look for ecarx.launcher3
            for (ResolveInfo ri : candidates) {
                if (ri.activityInfo != null && ri.activityInfo.packageName != null && ri.activityInfo.packageName.startsWith("ecarx.")) {
                    return new ComponentName(ri.activityInfo.packageName, ri.activityInfo.name);
                }
            }
            // Fallback: first non-UNI candidate with non-negative priority
            for (ResolveInfo ri : candidates) {
                if (ri.activityInfo != null && ri.activityInfo.packageName != null
                    && !context.getPackageName().equals(ri.activityInfo.packageName)
                    && !"com.android.settings".equals(ri.activityInfo.packageName)
                    && !ri.activityInfo.packageName.endsWith(".fallbackhome")) {
                    return new ComponentName(ri.activityInfo.packageName, ri.activityInfo.name);
                }
            }
        }
        return own;
    }

    /**
     * Set the preferred HOME activity in Android to the specified target.
     * Uses IPackageManager.setHomeActivity, replacePreferredActivity, and cmd package fallback.
     */
    public static boolean setPreferredHome(Context context, String targetPackageOrComponent) {
        final ComponentName target = resolveTargetComponent(context, targetPackageOrComponent);
        final Intent home = new Intent(Intent.ACTION_MAIN)
            .addCategory(Intent.CATEGORY_HOME)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
        UniLog.enter(LogTags.SYS, "home/setPreferredHome", "target", target.flattenToShortString());

        int userId = 0;
        try {
            Class<?> uhClass = Class.forName("android.os.UserHandle");
            userId = (Integer) uhClass.getMethod("myUserId").invoke(null);
        } catch (Throwable ignored) {}

        // 1. IPackageManager.setHomeActivity via ActivityThread.getPackageManager()
        try {
            Class<?> activityThreadClass = Class.forName("android.app.ActivityThread");
            Object ipm = activityThreadClass.getMethod("getPackageManager").invoke(null);
            if (ipm != null) {
                Method setHome = ipm.getClass().getMethod("setHomeActivity", ComponentName.class, int.class);
                setHome.setAccessible(true);
                setHome.invoke(ipm, target, userId);
                UniLog.i(LogTags.SYS, "ActivityThread IPackageManager.setHomeActivity invoked", "target", target.flattenToShortString());
            }
        } catch (Throwable t) {
            UniLog.w(LogTags.SYS, "ActivityThread setHomeActivity failed: " + t.getMessage(), t, "tag", "UniHome");
        }

        // 2. IPackageManager.setHomeActivity via ServiceManager.getService("package")
        try {
            Class<?> smClass = Class.forName("android.os.ServiceManager");
            android.os.IBinder binder = (android.os.IBinder) smClass.getMethod("getService", String.class).invoke(null, "package");
            if (binder != null) {
                Class<?> stubClass = Class.forName("android.content.pm.IPackageManager$Stub");
                Object ipm = stubClass.getMethod("asInterface", android.os.IBinder.class).invoke(null, binder);
                if (ipm != null) {
                    Method setHome = ipm.getClass().getMethod("setHomeActivity", ComponentName.class, int.class);
                    setHome.setAccessible(true);
                    setHome.invoke(ipm, target, userId);
                    UniLog.i(LogTags.SYS, "ServiceManager IPackageManager.setHomeActivity invoked", "target", target.flattenToShortString());
                }
            }
        } catch (Throwable t) {
            UniLog.w(LogTags.SYS, "ServiceManager setHomeActivity failed: " + t.getMessage(), t, "tag", "UniHome");
        }

        // 3. Fallback: replacePreferredActivity on PackageManager
        try {
            PackageManager pm = context.getPackageManager();
            List<ResolveInfo> candidates = pm.queryIntentActivities(home, PackageManager.MATCH_DEFAULT_ONLY);
            if (candidates == null || candidates.isEmpty()) {
                candidates = pm.queryIntentActivities(home, 0);
            }
            ArrayList<ComponentName> components = new ArrayList<>();
            int bestMatch = 0;
            if (candidates != null) {
                for (ResolveInfo candidate : candidates) {
                    if (candidate.activityInfo != null) {
                        components.add(new ComponentName(candidate.activityInfo.packageName, candidate.activityInfo.name));
                        if (candidate.match > bestMatch) {
                            bestMatch = candidate.match;
                        }
                    }
                }
            }
            if (!components.contains(target)) {
                components.add(target);
            }
            if (bestMatch <= 0) {
                bestMatch = IntentFilter.MATCH_CATEGORY_EMPTY;
            }

            IntentFilter filter = new IntentFilter(Intent.ACTION_MAIN);
            filter.addCategory(Intent.CATEGORY_HOME);
            filter.addCategory(Intent.CATEGORY_DEFAULT);

            Method replace = pm.getClass().getMethod(
                "replacePreferredActivity", IntentFilter.class, int.class,
                ComponentName[].class, ComponentName.class);
            replace.setAccessible(true);
            replace.invoke(pm, filter, bestMatch,
                components.toArray(new ComponentName[0]), target);
            UniLog.i(LogTags.SYS, "replacePreferredActivity invoked", "target", target.flattenToShortString());
        } catch (Throwable t) {
            UniLog.w(LogTags.SYS, "replacePreferredActivity failed: " + t.getMessage(), t, "tag", "UniHome");
        }

        // 4. Fallback: CLI cmd package set-home-activity
        try {
            Process p = Runtime.getRuntime().exec(new String[]{
                "cmd", "package", "set-home-activity", target.flattenToString()
            });
            p.waitFor();
        } catch (Throwable ignored) {}
        try {
            Process p = Runtime.getRuntime().exec(new String[]{
                "su", "0", "cmd", "package", "set-home-activity", target.flattenToString()
            });
            p.waitFor();
        } catch (Throwable ignored) {}

        // Verify resolution
        boolean success = false;
        try {
            ResolveInfo after = context.getPackageManager().resolveActivity(home, 0);
            if (after != null && after.activityInfo != null) {
                success = target.getPackageName().equals(after.activityInfo.packageName);
            }
        } catch (Throwable ignored) {}

        UniLog.i(LogTags.SYS, "setPreferredHome result=" + success, "tag", "UniHome");
        dismissResolver(context);
        if (success) {
            UniLog.done(LogTags.SYS, "home/setPreferredHome", "target", target.flattenToShortString());
        } else {
            UniLog.fail(LogTags.SYS, "home/setPreferredHome", "target", target.flattenToShortString(), "reason", "not-resolved");
        }
        return success;
    }

    public static boolean restoreIfNeeded(Context context) {
        final android.content.SharedPreferences prefs = context.getSharedPreferences("launcher", Context.MODE_PRIVATE);
        final String homeKeyTarget = prefs.getString("homeKeyTarget", context.getPackageName());
        UniLog.i(LogTags.SYS, "restoreIfNeeded homeKeyTarget=" + homeKeyTarget, "tag", "UniHome");
        return setPreferredHome(context, homeKeyTarget);
    }

    /** Close the resolver dialog after preference was set. */
    public static void dismissResolver(Context context) {
        try {
            context.sendBroadcast(new Intent(Intent.ACTION_CLOSE_SYSTEM_DIALOGS));
        } catch (Throwable ignored) {}
        try {
            ActivityManager tasks = (ActivityManager)
                context.getSystemService(Context.ACTIVITY_SERVICE);
            List<ActivityManager.RunningTaskInfo> running = tasks.getRunningTasks(1);
            boolean resolverForeground = !running.isEmpty()
                && running.get(0).topActivity != null
                && "android".equals(running.get(0).topActivity.getPackageName());
            if (!resolverForeground) return;
            context.sendBroadcast(new Intent(Intent.ACTION_CLOSE_SYSTEM_DIALOGS));
        } catch (Exception | LinkageError e) {
            UniLog.w(LogTags.SYS, "Unable to dismiss home resolver", e, "tag", "UniHome");
        }
    }
}
