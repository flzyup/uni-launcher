package xyz.i4o.uni.launcher.log;

import android.content.Context;
import android.content.Intent;
import android.net.Uri;
import android.os.Handler;
import android.os.Looper;
import android.widget.Toast;

import java.util.List;
import java.util.Map;

/**
 * 日志相关的 UI 辅助：导出诊断包、分享、预览、清空。
 *
 * <p>导出是**阻塞 IO**（读文件 + 写 zip + 拷公共目录），必须在后台线程跑，
 * 完成后回主线程提示用户。
 *
 * <p>本类是 Java 侧入口；设置页在 Flutter 里，通过平台通道调用这里。
 */
public final class LogTools {
    private LogTools() {}

    private static final Handler MAIN = new Handler(Looper.getMainLooper());

    /** 主线程回调。 */
    public interface Callback {
        /** 参数是给用户看的提示文案。 */
        void onDone(String message);
    }

    /**
     * 导出回调：同时给出结果对象和给用户看的文案。
     *
     * <p>结果对象里有落盘的绝对路径，自动化验证要靠它确认文件真的出现了。
     */
    public interface ExportCallback {
        void onDone(Diagnostics.Result result, String message);
    }

    /**
     * 导出诊断包。
     *
     * @param onDone 主线程回调，参数是给用户看的提示文案。
     */
    public static void export(Context context, ExportCallback onDone) {
        Context app = context.getApplicationContext();
        UniLog.enter(LogTags.LOG, "diagnostics/export", "trigger", "export");
        new Thread(() -> {
            Diagnostics.Result result = Diagnostics.export(app);
            MAIN.post(() -> onDone.onDone(result, messageOf(result)));
        }, "uni-log-export").start();
    }

    /**
     * 导出并调起系统分享（把 zip 直接发给开发）。
     *
     * @param onDone 主线程回调，参数是给用户看的提示文案（成功时为空串）。
     */
    public static void exportAndShare(Context context, ExportCallback onDone) {
        Context app = context.getApplicationContext();
        UniLog.enter(LogTags.LOG, "diagnostics/export", "trigger", "share");
        new Thread(() -> {
            Diagnostics.Result result = Diagnostics.export(app);
            MAIN.post(() -> {
                if (!result.ok()) {
                    onDone.onDone(result, "导出失败：" + result.reason);
                    return;
                }
                Uri uri = result.uri;
                if (uri == null) {
                    // 老系统拿不到 content:// Uri，只能让用户自己取文件。
                    onDone.onDone(result, "已导出到 " + result.displayPath + "，该系统版本不支持直接分享，请手动取文件");
                    return;
                }
                try {
                    Intent intent = Diagnostics.shareIntent(uri, "UNI 桌面 诊断日志");
                    intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
                    Intent chooser = Intent.createChooser(intent, "发送 UNI 桌面 诊断日志");
                    chooser.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
                    app.startActivity(chooser);
                    onDone.onDone(result, "");
                } catch (Throwable t) {
                    onDone.onDone(result, "已导出到 " + result.displayPath + "，但拉起分享失败：" + t.getMessage());
                }
            });
        }, "uni-log-share").start();
    }

    /** 导出结果对应的用户文案。 */
    public static String messageOf(Diagnostics.Result result) {
        if (!result.ok()) return "导出失败：" + result.reason;
        return "诊断包已导出：" + result.displayPath + "\n"
                + "共 " + result.fileCount + " 个日志文件、" + (result.bytes / 1024) + " KB";
    }

    /** 提示。 */
    public static void toast(Context context, String message) {
        Toast.makeText(context, message, Toast.LENGTH_LONG).show();
    }

    /** 清空日志。 */
    public static void clear(Context context, Callback onDone) {
        UniLog.clear();
        MAIN.post(() -> onDone.onDone("日志已清空"));
    }

    /** 末尾若干行预览。 */
    public static String preview(int lines) {
        String tail = UniLog.tail(lines);
        return tail.trim().isEmpty() ? "(暂无日志)" : tail;
    }

    /**
     * 写入一条来自 Flutter 侧的日志。
     *
     * <p>Flutter 侧的功能节点和原生侧同样重要，但它们在另一个 isolate 里，
     * 只能通过平台通道把记录送过来。级别用 {@code D/I/W/E} 表示，
     * 认不出来就按 {@code INFO} 处理。
     */
    public static void logFromFlutter(String levelName, String tag, String message, Map<String, Object> fields) {
        LogLevel level = levelByName(levelName);
        String safeTag = tag == null || tag.trim().isEmpty() ? LogTags.UI : tag;
        Object[] pairs = fields == null ? new Object[0] : fields.entrySet().stream()
                .flatMap(entry -> java.util.stream.Stream.of(entry.getKey(), entry.getValue()))
                .toArray();
        switch (level) {
            case DEBUG: UniLog.d(safeTag, message, pairs); break;
            case WARN: UniLog.w(safeTag, message, pairs); break;
            case ERROR: UniLog.e(safeTag, message, pairs); break;
            default: UniLog.i(safeTag, message, pairs); break;
        }
    }

    /** 写入一条来自 Flutter 侧的锚点。 */
    public static void anchorFromFlutter(String tag, String node, String stage, Map<String, Object> fields) {
        String safeTag = tag == null || tag.trim().isEmpty() ? LogTags.UI : tag;
        Object[] pairs = fields == null ? new Object[0] : fields.entrySet().stream()
                .flatMap(entry -> java.util.stream.Stream.of(entry.getKey(), entry.getValue()))
                .toArray();
        UniLog.anchor(safeTag, node, stage, pairs);
    }

    /** 批量写入 Flutter 侧日志。 */
    public static void logBatchFromFlutter(List<Map<String, Object>> records) {
        if (records == null) return;
        for (Map<String, Object> record : records) {
            try {
                String kind = String.valueOf(record.get("kind"));
                if ("anchor".equals(kind)) {
                    anchorFromFlutter(asString(record.get("tag")), asString(record.get("node")),
                            asString(record.get("stage")), asMap(record.get("fields")));
                } else {
                    logFromFlutter(asString(record.get("level")), asString(record.get("tag")),
                            asString(record.get("message")), asMap(record.get("fields")));
                }
            } catch (Throwable t) {
                // 单条坏记录不能影响其它记录，也不能影响 App
                UniLog.w(LogTags.LOG, "Flutter 日志记录解析失败", t);
            }
        }
    }

    private static LogLevel levelByName(String name) {
        if (name == null) return LogLevel.INFO;
        switch (name.trim().toUpperCase(java.util.Locale.CHINA)) {
            case "D": case "DEBUG": return LogLevel.DEBUG;
            case "W": case "WARN": case "WARNING": return LogLevel.WARN;
            case "E": case "ERROR": return LogLevel.ERROR;
            default: return LogLevel.INFO;
        }
    }

    @SuppressWarnings("unchecked")
    private static Map<String, Object> asMap(Object value) {
        return value instanceof Map ? (Map<String, Object>) value : null;
    }

    private static String asString(Object value) {
        return value == null ? null : String.valueOf(value);
    }
}
