package xyz.i4o.uni.launcher;

import android.content.Context;
import android.os.SystemClock;

import java.text.SimpleDateFormat;
import java.util.Date;
import java.util.LinkedHashMap;
import java.util.Locale;
import java.util.Map;

import xyz.i4o.uni.launcher.log.LogTags;
import xyz.i4o.uni.launcher.log.UniLog;

/**
 * 冷启动分段计时。
 *
 * <h3>为什么要有</h3>
 * 「车机开机后黑屏一段时间才出桌面」这件事，**以前根本没法量化**：
 * 诊断包里只有业务日志，没有一条「从进程启动到首帧画出来用了多少毫秒」。
 * 每次用户反馈「还是有点慢」，我们只能猜是运行时构建、天气网络、
 * 还是媒体会话绑定。
 *
 * <p>这个类只做一件事：**在关键节点打一个 uptimeMillis 时间戳**，
 * 一次性写成 {@code key=value} 日志。时间基准与 {@code am start -W} 的
 * TotalTime 一致（都用 {@code SystemClock.uptimeMillis()}），可以直接对照系统的启动耗时。
 *
 * <h3>车机没有 adb 也能看</h3>
 * <p>真机可能连不上 adb，所以这里**不是只写 logcat**：
 * <ul>
 *   <li>每个分段都写 {@link UniLog}（INFO，默认落盘）→ 进诊断包的 {@code logs/}；</li>
 *   <li>桌面就绪时把汇总行**持久化**到 {@code uni_startup.xml}
 *       → 诊断包 {@code summary.txt} 的「冷启动」段直接给出本次 + 上次的数字，
 *       <b>即使日志已经被轮转掉也不会丢</b>。</li>
 * </ul>
 *
 * <p>{@code bootMs} 是「开机以来毫秒」，用来区分两种情况：
 * 系统开机就慢（{@code bootMs} 很大） vs 我们的进程启动慢（{@code processMs} 大）。
 *
 * <h3>怎么读</h3>
 * <ul>
 *   <li>车机无 adb：设置 → 系统与调试 → 诊断日志 → 导出诊断包，
 *       看 {@code summary.txt} 的「---- 冷启动 ----」段（本次 + 上次）；</li>
 *   <li>有 adb：{@code adb logcat -s UNI-Startup}。</li>
 * </ul>
 */
public final class StartupTrace {
    /** 只进 Logcat 的独立 tag：真机上用 {@code adb logcat -s UNI-Startup} 读。 */
    private static final String LOGCAT_TAG = "UNI-Startup";

    /** 持久化最近一次启动摘要（诊断包 summary.txt 用）。 */
    private static final String PREFS = "uni_startup";
    private static final String KEY_LAST = "last";
    private static final String KEY_LAST_AT = "last_at";
    private static final String KEY_LAST_COLD = "last_cold";
    private static final String KEY_LAST_COLD_AT = "last_cold_at";

    /**
     * 「开机以来多少毫秒内启动」算一次冷启动记录（5 分钟）。
     *
     * <p>车机重启后用户可能先开别的应用、过很久才回桌面，那时进程早被回收，
     * 再回桌面是**热启动**（数字很小）。如果只存 {@code last}，这条热启动会把
     * 开机时那次冷启动的数字覆盖掉，用户下次开机前就再也看不到「黑屏其实多长」。
     * 所以额外存一份 {@code last_cold}，只被「开机 5 分钟内启动」的记录更新。
     */
    private static final long COLD_BOOT_WINDOW_MS = 5L * 60_000L;

    /** 锚点节点名。 */
    private static final String NODE = "startup/trace";

    /** 进程启动时刻（uptimeMillis）。API 24 起就有这个方法，minSdk 正好是 24。 */
    private static final long processStart = android.os.Process.getStartUptimeMillis();

    /** 已经打过的时间戳（按打点顺序）。 */
    private static final Map<String, Long> marks = new LinkedHashMap<>();

    /** 已写过汇总（进程内只持久化一次，避免热启动把冷启动记录覆盖掉）。 */
    private static boolean summarized;

    /** 绑定 Context（只在 {@link #install} 之后才能持久化）。 */
    private static volatile Context app;

    private StartupTrace() {}

    /**
     * 绑定 Context（App 启动时调一次）。
     *
     * <p>只用来把汇总行持久化到 prefs —— 不绑定也能跑，只是诊断包里看不到「上次启动」。
     */
    public static void install(Context context) {
        if (app == null) app = context.getApplicationContext();
    }

    /** 当前时刻的 uptimeMillis 标记。 */
    public static long mark() {
        return SystemClock.uptimeMillis();
    }

    /**
     * 打一个启动分段。
     *
     * <p>三个数字一起打：
     * <ul>
     *   <li>{@code processMs}：距进程启动（含 fork / Application 初始化）；</li>
     *   <li>{@code onCreateMs}：距 {@code onCreate} 入口 —— 这一列才是**我们能优化**的部分；</li>
     *   <li>{@code bootMs}：开机以来 —— 用来区分「系统开机慢」和「桌面启动慢」。</li>
     * </ul>
     */
    public static synchronized void mark(String label) {
        long at = SystemClock.uptimeMillis();
        marks.put(label, at);
        long sinceProcess = at - processStart;
        long sinceOnCreate = at - (marks.containsKey("onCreate") ? marks.get("onCreate") : processStart);
        long boot = sinceBoot();
        UniLog.i(LogTags.APP, "启动分段：" + label,
                "processMs", sinceProcess,
                "onCreateMs", sinceOnCreate,
                "bootMs", boot);
        android.util.Log.i(LOGCAT_TAG,
                label + " process=" + sinceProcess + "ms onCreate=" + sinceOnCreate + "ms boot=" + boot + "ms");
        // 诊断包即使在中途导出，也能拿到目前走过的分段（不必等到 summary）。
        if ("onCreate".equals(label)) persist(currentLine());
    }

    /**
     * 桌面**完全可见**时打一条汇总（进程内只打一次）。
     *
     * <p>汇总把全部分段压成一行 {@code 名称=距onCreate毫秒}，方便一眼看出时间花在哪：
     * 通常关心 {@code splashFirstFrame}（第一张图）、{@code launcherFirstFrame}（桌面画出来）、
     * {@code servicesStarted}（车控/天气/媒体这些重活干完）。
     */
    public static synchronized void summary() {
        if (summarized) return;
        summarized = true;
        if (marks.isEmpty()) return;
        long total = SystemClock.uptimeMillis() - processStart;
        long boot = sinceBoot();
        String segments = segmentsSinceCreate();
        UniLog.i(LogTags.APP, "启动完成",
                "totalMs", total,
                "bootMs", boot,
                "fromCreateMs", segments);
        android.util.Log.i(LOGCAT_TAG, "done total=" + total + "ms boot=" + boot + "ms fromCreate " + segments);
        UniLog.done(LogTags.APP, NODE, "totalMs", total, "bootMs", boot, "stages", marks.size());
        persist(currentLine());
    }

    /**
     * 诊断包 {@code summary.txt} 用：本次启动 + 上次持久化的启动摘要。
     *
     * <p>这样即使日志文件已经被轮转掉、或者用户是热启动后导出，
     * 也能看到**最近一次冷启动**的数字。
     */
    public static synchronized String describe() {
        String now = currentLine();
        Context context = app;
        String last = null, lastCold = null;
        long lastAt = 0L, lastColdAt = 0L;
        if (context != null) {
            try {
                android.content.SharedPreferences sp = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE);
                last = sp.getString(KEY_LAST, null);
                lastAt = sp.getLong(KEY_LAST_AT, 0L);
                lastCold = sp.getString(KEY_LAST_COLD, null);
                lastColdAt = sp.getLong(KEY_LAST_COLD_AT, 0L);
            } catch (Throwable ignored) {
                // 读不到就只报本次
            }
        }
        StringBuilder sb = new StringBuilder();
        sb.append("本次启动: ").append(now).append('\n');
        if (last != null && !last.trim().isEmpty()) {
            sb.append("上次启动: ");
            if (lastAt > 0) {
                sb.append(new SimpleDateFormat("yyyy-MM-dd HH:mm:ss", Locale.CHINA).format(new Date(lastAt))).append("  ");
            }
            sb.append(last).append('\n');
        } else {
            sb.append("上次启动: (还没有持久化记录)\n");
        }
        if (lastCold != null && !lastCold.trim().isEmpty()) {
            sb.append("上次冷启动(开机5分钟内): ");
            if (lastColdAt > 0) {
                sb.append(new SimpleDateFormat("yyyy-MM-dd HH:mm:ss", Locale.CHINA).format(new Date(lastColdAt))).append("  ");
            }
            sb.append(lastCold).append('\n');
        }
        sb.append("说明: total/processMs 与 `am start -W` 的 TotalTime 同钟（uptimeMillis）；");
        sb.append("bootMs 是开机以来的毫秒数，用来区分系统开机慢还是桌面启动慢。\n");
        return sb.toString();
    }

    /** 当前已打点的分段（未汇总时导出诊断包也能看）。 */
    private static String currentLine() {
        if (marks.isEmpty()) return "（本进程还没有启动分段）";
        long total = SystemClock.uptimeMillis() - processStart;
        return "total=" + total + "ms boot=" + sinceBoot() + "ms fromCreate " + segmentsSinceCreate();
    }

    private static String segmentsSinceCreate() {
        Long onCreateAt = marks.get("onCreate");
        long base = onCreateAt == null ? processStart : onCreateAt;
        StringBuilder sb = new StringBuilder();
        for (Map.Entry<String, Long> entry : marks.entrySet()) {
            if (sb.length() > 0) sb.append(' ');
            sb.append(entry.getKey()).append('=').append(entry.getValue() - base);
        }
        return sb.toString();
    }

    /** 开机以来毫秒（含系统启动过程）。 */
    private static long sinceBoot() {
        return SystemClock.elapsedRealtime();
    }

    /**
     * 把当前摘要落进 prefs（诊断包 summary.txt 读它）。
     *
     * <p>同时写两份：
     * <ul>
     *   <li>{@code last}：最近一次（含热启动）；</li>
     *   <li>{@code last_cold}：只在「开机 5 分钟内启动」时更新 ——
     *       防止后来的热启动记录把开机那次冷启动的数字覆盖掉。</li>
     * </ul>
     *
     * <p>失败不影响启动 —— 这只是诊断，不能因为写盘失败把桌面卡住。
     */
    private static void persist(String line) {
        Context context = app;
        if (context == null) return;
        try {
            long now = System.currentTimeMillis();
            boolean cold = sinceBoot() <= COLD_BOOT_WINDOW_MS;
            android.content.SharedPreferences.Editor editor =
                    context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
                            .putString(KEY_LAST, line)
                            .putLong(KEY_LAST_AT, now);
            if (cold) {
                editor.putString(KEY_LAST_COLD, line).putLong(KEY_LAST_COLD_AT, now);
            }
            editor.apply();
        } catch (Throwable ignored) {
            // 持久化失败不影响启动
        }
    }
}
