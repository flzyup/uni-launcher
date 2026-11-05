package xyz.i4o.uni.launcher.log;

import android.content.Context;
import android.content.SharedPreferences;
import android.util.Log;

import java.io.File;

/**
 * 统一日志门面：**同时**写 Logcat 与本地文件。
 *
 * <h3>用法</h3>
 * <pre>
 * UniLog.i(LogTags.VEHICLE, "写入空调", "func", 0x10010300, "zone", 1);
 * UniLog.w(LogTags.VEHICLE, "通道连接失败", t);
 * UniLog.anchor(LogTags.VEHICLE, "vehicle/read", LogFormat.STAGE_ENTER, "source", "official");
 * </pre>
 *
 * 结构化字段会拼成 {@code key=value}，方便在真机上直接 grep：
 * <pre>
 * adb logcat | grep 'UNI/Vehicle.*func=0x10010300'
 * </pre>
 *
 * <h3>级别</h3>
 * <ul>
 *   <li>{@code DEBUG}：调试细节，**默认不落盘**（只进 Logcat），避免车机长期跑爆存储；</li>
 *   <li>{@code INFO}：关键状态与用户操作，**默认落盘**；</li>
 *   <li>{@code WARN} / {@code ERROR}：异常与降级，**总是落盘**。</li>
 * </ul>
 *
 * <h3>锚点</h3>
 * 关键功能节点用 {@link #anchor} 打标记，形如
 * {@code [ANCHOR] vehicle/read enter source=official}。
 * 一条 grep 就能筛出某条链路的全部节点：
 * <pre>
 * adb logcat | grep '\[ANCHOR\] vehicle/read'
 * </pre>
 *
 * <h3>线程安全</h3>
 * 全局单例；{@link #init} 之后才能写文件（未 init 时只进 Logcat，不会崩）。
 */
public final class UniLog {
    private UniLog() {}

    /**
     * 和 {@code LauncherRuntime} 用同一个 prefs 文件（{@code "launcher"}）。
     *
     * 共用一个文件的好处：诊断包「设置全量键值」段能直接看到落盘级别，
     * 用户不用另外找地方确认「到底开没开调试日志」。
     */
    private static final String PREFS_NAME = "launcher";
    /** 落盘级别的持久化键。 */
    private static final String KEY_LEVEL = "log_level";

    private static volatile FileLogSink sink;

    /** 落盘级别的持久化。 */
    private static volatile SharedPreferences prefs;

    /** 已初始化（便于诊断包记录）。 */
    public static boolean initialized() {
        return sink != null;
    }

    /** 初始化（App 启动时调一次）。 */
    public static void init(Context context) {
        if (sink != null) return;
        synchronized (UniLog.class) {
            if (sink == null) {
                try {
                    sink = new FileLogSink(context.getApplicationContext());
                    prefs = context.getApplicationContext().getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE);
                    // 回读上次设置的落盘级别 —— 车机重启 / App 重启后不能丢，
                    // 否则用户调到「调试」后又重启一次，日志突然没了还以为没开。
                    LogLevel persisted = persistedLevel();
                    if (persisted != null) {
                        sink.level(persisted);
                        Log.i(LogTags.LOG, "落盘级别（上次设置） -> " + persisted.label);
                    }
                } catch (Throwable t) {
                    Log.w(LogTags.LOG, "init failed: " + t.getMessage());
                }
            }
        }
    }

    /** 设置落盘级别（同时持久化）。 */
    public static void setLevel(LogLevel level) {
        if (level == null) return;
        FileLogSink current = sink;
        if (current != null) current.level(level);
        try {
            SharedPreferences store = prefs;
            if (store != null) store.edit().putString(KEY_LEVEL, level.name()).apply();
        } catch (Throwable t) {
            Log.w(LogTags.LOG, "写入日志级别失败: " + t.getMessage());
        }
        i(LogTags.LOG, "文件日志级别 -> " + level.label);
    }

    /** 当前落盘级别。 */
    public static LogLevel level() {
        FileLogSink current = sink;
        return current == null ? LogLevel.INFO : current.level();
    }

    /** 持久化里记的上次级别（没有或认不出来就是 null）。 */
    private static LogLevel persistedLevel() {
        try {
            SharedPreferences store = prefs;
            if (store == null) return null;
            return LogLevel.byNameOrNull(store.getString(KEY_LEVEL, null));
        } catch (Throwable t) {
            return null;
        }
    }

    // ------------------------------------------------------------------ 写日志

    public static void d(String tag, String message, Object... fields) {
        write(LogLevel.DEBUG, tag, message, null, fields);
    }

    /** 调试级（带异常）。DEBUG 不落盘，只在 logcat 里看。 */
    public static void d(String tag, String message, Throwable error, Object... fields) {
        write(LogLevel.DEBUG, tag, message, error, fields);
    }

    public static void i(String tag, String message, Object... fields) {
        write(LogLevel.INFO, tag, message, null, fields);
    }

    /** 警告（带异常）。 */
    public static void w(String tag, String message, Throwable error, Object... fields) {
        write(LogLevel.WARN, tag, message, error, fields);
    }

    /** 警告（不带异常）。 */
    public static void w(String tag, String message, Object... fields) {
        write(LogLevel.WARN, tag, message, null, fields);
    }

    /** 错误（带异常）。 */
    public static void e(String tag, String message, Throwable error, Object... fields) {
        write(LogLevel.ERROR, tag, message, error, fields);
    }

    /** 错误（不带异常）。 */
    public static void e(String tag, String message, Object... fields) {
        write(LogLevel.ERROR, tag, message, null, fields);
    }

    /**
     * 关键交互事件。
     *
     * 用 {@code [EVT]} 前缀标记，方便在日志里一眼筛出「用户做了什么」：
     * <pre>
     * adb logcat | grep '\[EVT\]'
     * </pre>
     */
    public static void event(String tag, String message, Object... fields) {
        write(LogLevel.INFO, tag, LogFormat.EVENT_PREFIX + message, null, fields);
    }

    /**
     * 关键功能节点锚点。
     *
     * <p>节点名建议用 {@code 域/动作} 的写法（如 {@code vehicle/read}），
     * 这样同一条链路的所有节点在日志里是连续的，grep 一次就能看全。
     *
     * @param node   节点名（稳定，不要带会变的内容）
     * @param stage  阶段：{@code enter} / {@code done} / {@code fail} / {@code skip}
     * @param fields 结构化字段（成对：key, value, key, value）
     */
    public static void anchor(String tag, String node, String stage, Object... fields) {
        anchorAt(LogLevel.INFO, tag, node, stage, fields);
    }

    /**
     * 关键功能节点锚点（指定级别）。
     *
     * <p>心跳类节点（每秒一次的轮询）必须用 {@link LogLevel#DEBUG}：
     * 落盘级别默认是 INFO，1Hz 的心跳每分钟就是 120 行，
     * 几小时就能把日志写满，把真正的事件挤出去。
     */
    public static void anchorAt(LogLevel level, String tag, String node, String stage, Object... fields) {
        String rendered = LogFormat.anchor(node, stage, fields);
        AnchorLedger.record(tag, node, stage, rendered);
        write(level, tag, rendered, null, null);
    }

    /** 锚点的便捷封装：进入节点。 */
    public static void enter(String tag, String node, Object... fields) {
        anchor(tag, node, LogFormat.STAGE_ENTER, fields);
    }

    /** 锚点的便捷封装：完成节点。 */
    public static void done(String tag, String node, Object... fields) {
        anchor(tag, node, LogFormat.STAGE_DONE, fields);
    }

    /** 锚点的便捷封装：节点失败。 */
    public static void fail(String tag, String node, Object... fields) {
        anchor(tag, node, LogFormat.STAGE_FAIL, fields);
    }

    /** 锚点的便捷封装：节点被跳过。 */
    public static void skip(String tag, String node, Object... fields) {
        anchor(tag, node, LogFormat.STAGE_SKIP, fields);
    }

    /** 心跳锚点：只进 Logcat，默认不落盘。 */
    public static void enterDebug(String tag, String node, Object... fields) {
        anchorAt(LogLevel.DEBUG, tag, node, LogFormat.STAGE_ENTER, fields);
    }

    /** 心跳锚点：只进 Logcat，默认不落盘。 */
    public static void doneDebug(String tag, String node, Object... fields) {
        anchorAt(LogLevel.DEBUG, tag, node, LogFormat.STAGE_DONE, fields);
    }

    /** 心跳锚点：只进 Logcat，默认不落盘。 */
    public static void skipDebug(String tag, String node, Object... fields) {
        anchorAt(LogLevel.DEBUG, tag, node, LogFormat.STAGE_SKIP, fields);
    }

    private static void write(LogLevel level, String tag, String message, Throwable error, Object[] fields) {
        String full = LogFormat.message(message, fields);
        try {
            switch (level) {
                case DEBUG: Log.d(tag, full, error); break;
                case INFO: Log.i(tag, full, error); break;
                case WARN: Log.w(tag, full, error); break;
                case ERROR: Log.e(tag, full, error); break;
                default: break;
            }
        } catch (Throwable t) {
            // Logcat 本身失败不能影响业务
        }
        try {
            FileLogSink current = sink;
            if (current != null) current.write(level, tag, full, error);
        } catch (Throwable t) {
            // 落盘失败也不能影响业务
        }
    }

    // ------------------------------------------------------------------ 导出

    /** 日志目录（App 私有目录）。 */
    public static File logDirectory() {
        FileLogSink current = sink;
        return current == null ? null : current.directory();
    }

    /**
     * 落盘是否已降级（磁盘空间不足，停止写盘、只留 Logcat）。
     *
     * 诊断包里要能看到这个状态 —— 否则用户会以为「没日志」是 App 坏了，
     * 其实是车机存储满了。
     */
    public static boolean degraded() {
        FileLogSink current = sink;
        return current != null && current.degraded();
    }

    /** 当前日志占用的总字节数。 */
    public static long totalBytes() {
        FileLogSink current = sink;
        return current == null ? 0L : current.totalBytes();
    }

    /** 末尾若干行（预览用）。 */
    public static String tail(int lines) {
        FileLogSink current = sink;
        return current == null ? "" : current.tail(lines);
    }

    /** 清空日志（同时清掉锚点账本，免得诊断包里的计数对不上日志文件）。 */
    public static void clear() {
        FileLogSink current = sink;
        if (current != null) current.clear();
        AnchorLedger.reset();
        i(LogTags.LOG, "日志已清空");
    }
}
