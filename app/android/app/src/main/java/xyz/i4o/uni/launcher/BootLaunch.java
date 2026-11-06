package xyz.i4o.uni.launcher;

import android.content.Context;
import android.content.SharedPreferences;
import android.os.Handler;
import android.os.SystemClock;

import org.json.JSONArray;
import org.json.JSONObject;

import xyz.i4o.uni.launcher.integration.AppRepository;

/**
 * 开机自启动计划：一行是「应用 + 开机后多少秒启动」。
 *
 * 目标时刻锚定在**开机**（{@link SystemClock#elapsedRealtime()}），不是桌面进程启动时刻，
 * 所以桌面进程晚起来也能按真实开机秒数补上；同一开机周期内每个计划只启动一次，
 * 桌面重启不会重放。整件事只在开机后 10 分钟内进行，用户中午手动重启桌面不会突然弹应用。
 */
public final class BootLaunch {
    /** 秒；上限 10 分钟，和开机窗口一致。 */
    public static final int MAX_DELAY = 600;
    public static final int MAX_PLANS = 12;
    public static final long BOOT_WINDOW_MS = 10 * 60 * 1000L;

    private static final String KEY_ENABLED = "bootLaunchEnabled";
    private static final String KEY_PLANS = "bootLaunchPlans";
    private static final String KEY_BOOT = "bootLaunchBoot";
    private static final String KEY_FIRED = "bootLaunchFired";

    private final Context context;
    private final SharedPreferences prefs;
    private final AppRepository apps;
    private final Handler main;
    private final Runnable publish;
    private boolean scheduled;
    /** key → 最近一次结果，只在内存里，给设置页显示「上次结果」。 */
    private final JSONObject results = new JSONObject();

    public BootLaunch(Context context, SharedPreferences prefs, AppRepository apps,
                      Handler main, Runnable publish) {
        this.context = context;
        this.prefs = prefs;
        this.apps = apps;
        this.main = main;
        this.publish = publish;
    }

    public static String key(String id, int delay) {
        return id + "@" + delay;
    }

    /** 组件名 "包名/类名" 里的包名，用来在目录还没建好时按包名兜底启动。 */
    public static String packageOf(String id) {
        if (id == null) return "";
        int slash = id.indexOf('/');
        return slash <= 0 ? id : id.substring(0, slash);
    }

    public boolean enabled() {
        return prefs.getBoolean(KEY_ENABLED, false);
    }

    public JSONArray plans() {
        try {
            return new JSONArray(prefs.getString(KEY_PLANS, "[]"));
        } catch (Exception ignored) {
            return new JSONArray();
        }
    }

    private void storePlans(JSONArray plans) {
        prefs.edit().putString(KEY_PLANS, plans.toString()).apply();
    }

    private long bootWall() {
        return System.currentTimeMillis() - SystemClock.elapsedRealtime();
    }

    /** 当前开机周期已经启动过的 key；换了一次开机就清空。 */
    private JSONArray fired() {
        long boot = bootWall();
        long stored = prefs.getLong(KEY_BOOT, 0);
        JSONArray list;
        try {
            list = new JSONArray(prefs.getString(KEY_FIRED, "[]"));
        } catch (Exception ignored) {
            list = new JSONArray();
        }
        if (stored == 0 || Math.abs(boot - stored) > 60000L) {
            return new JSONArray();
        }
        return list;
    }

    private void markFired(String key) {
        JSONArray list = fired();
        if (!contains(list, key)) list.put(key);
        prefs.edit().putLong(KEY_BOOT, bootWall()).putString(KEY_FIRED, list.toString()).apply();
    }

    private static boolean contains(JSONArray list, String value) {
        for (int i = 0; i < list.length(); i++) {
            if (value.equals(list.optString(i))) return true;
        }
        return false;
    }

    public boolean setEnabled(boolean value) {
        prefs.edit().putBoolean(KEY_ENABLED, value).apply();
        if (value) schedule();
        return true;
    }

    /** 添加或覆盖同一「应用 + 秒数」的重复计划。 */
    public boolean add(String id, int delay) {
        if (id == null || id.isEmpty()) return false;
        int seconds = Math.max(0, Math.min(MAX_DELAY, delay));
        JSONArray list = plans();
        String key = key(id, seconds);
        for (int i = 0; i < list.length(); i++) {
            JSONObject plan = list.optJSONObject(i);
            if (plan != null && key.equals(keyOf(plan))) return true;
        }
        if (list.length() >= MAX_PLANS) return false;
        try {
            list.put(new JSONObject().put("id", id).put("delay", seconds));
        } catch (Exception ignored) {
            return false;
        }
        storePlans(list);
        return true;
    }

    public boolean remove(String key) {
        JSONArray list = plans();
        JSONArray next = new JSONArray();
        boolean changed = false;
        for (int i = 0; i < list.length(); i++) {
            JSONObject plan = list.optJSONObject(i);
            if (plan == null) continue;
            if (key.equals(keyOf(plan))) {
                changed = true;
                continue;
            }
            next.put(plan);
        }
        if (!changed) return false;
        storePlans(next);
        return true;
    }

    public boolean clear() {
        storePlans(new JSONArray());
        return true;
    }

    private static String keyOf(JSONObject plan) {
        return key(plan.optString("id"), plan.optInt("delay", 0));
    }

    private JSONObject find(String key) {
        JSONArray list = plans();
        for (int i = 0; i < list.length(); i++) {
            JSONObject plan = list.optJSONObject(i);
            if (plan != null && key.equals(keyOf(plan))) return plan;
        }
        return null;
    }

    /** 设置页里的「立刻启动一次」，不影响开机计划本身。 */
    public boolean runNow(String key) {
        JSONObject plan = find(key);
        if (plan == null) return false;
        fire(key, plan, true);
        return true;
    }

    /**
     * 按开机时刻排程；进程内只排一次。开关关闭、或已经过了开机窗口时不排任何东西。
     */
    public void schedule() {
        if (scheduled) return;
        scheduled = true;
        if (!enabled()) return;
        long now = SystemClock.elapsedRealtime();
        if (now > BOOT_WINDOW_MS) return;
        JSONArray fired = fired();
        JSONArray list = plans();
        int stagger = 0;
        for (int i = 0; i < list.length(); i++) {
            final JSONObject plan = list.optJSONObject(i);
            if (plan == null) continue;
            final String id = plan.optString("id");
            if (id.isEmpty()) continue;
            final int delay = Math.max(0, Math.min(MAX_DELAY, plan.optInt("delay", 0)));
            final String key = key(id, delay);
            if (contains(fired, key)) continue;
            long wait = delay * 1000L - now;
            if (wait < 0) wait = 0;
            // 同一秒里的多个计划按顺序错开，避免同时抢前台。
            if (wait == 0) wait = 250L * (++stagger);
            final Runnable task = () -> fire(key, plan, false);
            main.postDelayed(task, wait);
        }
    }

    private void fire(String key, JSONObject plan, boolean manual) {
        String id = plan.optString("id");
        int delay = plan.optInt("delay", 0);
        String state = "failed";
        String reason = "";
        if (!manual && !enabled()) {
            state = "skipped";
            reason = "开机自启动已关闭";
        } else if (prefs.getBoolean("demo", false)) {
            state = "skipped";
            reason = "演示模式";
        } else if (id.isEmpty()) {
            reason = "计划缺少应用";
        } else if (apps.launch(id)) {
            state = "launched";
        } else if (apps.launchPackage(packageOf(id))) {
            state = "launched";
            reason = "按包名启动";
        } else {
            reason = "应用未安装或无法启动";
        }
        record(key, state, reason, manual ? -1 : (int) (SystemClock.elapsedRealtime() / 1000L));
        if (!manual) markFired(key);
        publish.run();
    }

    private void record(String key, String state, String reason, int atSec) {
        try {
            results.put(key, new JSONObject().put("state", state).put("reason", reason)
                    .put("atSec", atSec).put("atMs", System.currentTimeMillis()));
        } catch (Exception ignored) {
        }
    }

    public JSONObject snapshot() {
        JSONObject out = new JSONObject();
        try {
            JSONArray list = new JSONArray();
            JSONArray plans = plans();
            for (int i = 0; i < plans.length(); i++) {
                JSONObject plan = plans.optJSONObject(i);
                if (plan == null) continue;
                String key = keyOf(plan);
                JSONObject item = new JSONObject()
                        .put("key", key)
                        .put("id", plan.optString("id"))
                        .put("package", packageOf(plan.optString("id")))
                        .put("delay", plan.optInt("delay", 0))
                        .put("duplicate", i > 0 && repeatedBefore(plans, i, key));
                JSONObject result = results.optJSONObject(key);
                if (result != null) {
                    item.put("state", result.optString("state"))
                            .put("reason", result.optString("reason"))
                            .put("atSec", result.optInt("atSec", -1))
                            .put("atMs", result.optLong("atMs", 0));
                }
                item.put("installed", installed(plan.optString("id")));
                list.put(item);
            }
            out.put("enabled", enabled())
                    .put("plans", list)
                    .put("maxDelay", MAX_DELAY)
                    .put("maxPlans", MAX_PLANS)
                    .put("bootSeconds", SystemClock.elapsedRealtime() / 1000L)
                    .put("demo", prefs.getBoolean("demo", false));
        } catch (Exception ignored) {
        }
        return out;
    }

    private static boolean repeatedBefore(JSONArray plans, int index, String key) {
        for (int i = 0; i < index; i++) {
            JSONObject plan = plans.optJSONObject(i);
            if (plan != null && key.equals(keyOf(plan))) return true;
        }
        return false;
    }

    private boolean installed(String id) {
        String pkg = packageOf(id);
        if (pkg.isEmpty()) return false;
        try {
            context.getPackageManager().getApplicationInfo(pkg, 0);
            return true;
        } catch (Exception ignored) {
            return false;
        }
    }
}
