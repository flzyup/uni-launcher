package xyz.i4o.uni.launcher.log;

import android.content.Context;

import java.util.List;
import java.util.Map;

import io.flutter.embedding.engine.FlutterEngine;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;

/**
 * 日志的 Flutter 桥。
 *
 * <p>桌面的功能节点大部分在 Dart 侧（卡片、页面、设置、OTA），原生侧只是
 * 执行层。两边的日志必须落到**同一个文件**里，否则诊断包里的
 * {@code logs/} 只能看到一半链路，导出一次仍然定位不了问题。
 *
 * <p>因此 Dart 通过本通道把记录送回原生，由 {@link UniLog} 统一写盘。
 *
 * <h3>方法</h3>
 * <ul>
 *   <li>{@code log} —— 写一条（或一批）日志；</li>
 *   <li>{@code anchor} —— 打一个关键功能节点锚点；</li>
 *   <li>{@code export} —— 导出诊断包（后台线程，回调里回结果）；</li>
 *   <li>{@code exportAndShare} —— 导出并调起系统分享；</li>
 *   <li>{@code clear} —— 清空日志；</li>
 *   <li>{@code preview} —— 取末尾若干行；</li>
 *   <li>{@code status} —— 取日志系统状态（占用、文件数、是否降级、锚点数）；</li>
 *   <li>{@code ensurePermission} —— 申请导出诊断包需要的存储权限（Android 9 及以下）；</li>
 *   <li>{@code level} —— 读或设置落盘级别。</li>
 * </ul>
 */
public final class LogBridge {
    /** 通道名。 */
    public static final String CHANNEL = "xyz.i4o.uni.launcher/log";

    private LogBridge() {}

    /**
     * 把日志通道挂到某个引擎上。
     *
     * <p>每个 Flutter 引擎都要挂一次：桌面、全局底栏、全局面板是三个引擎，
     * 三个引擎里的 Dart 代码都会打日志。
     */
    public static void attach(Context context, FlutterEngine engine) {
        Context app = context.getApplicationContext();
        UniLog.init(app);
        new MethodChannel(engine.getDartExecutor().getBinaryMessenger(), CHANNEL).setMethodCallHandler(
                (MethodCall call, MethodChannel.Result result) -> handle(app, call, result));
    }

    private static void handle(Context context, MethodCall call, MethodChannel.Result result) {
        try {
            switch (call.method) {
                case "log":
                    log(call);
                    result.success(null);
                    break;
                case "anchor":
                    anchor(call);
                    result.success(null);
                    break;
                case "export":
                    export(context, result, false);
                    break;
                case "exportAndShare":
                    export(context, result, true);
                    break;
                case "clear":
                    LogTools.clear(context, message -> result.success(message));
                    break;
                case "preview":
                    result.success(LogTools.preview(intArgument(call, 60)));
                    break;
                case "status":
                    result.success(status(context));
                    break;
                case "ensurePermission":
                    // 弹窗是异步的，结果等系统回调再给 Flutter。
                    xyz.i4o.uni.launcher.MainActivity.requestStoragePermission(
                            context, granted -> result.success(granted));
                    break;
                case "level":
                    level(call, result);
                    break;
                default:
                    result.notImplemented();
                    break;
            }
        } catch (Throwable t) {
            // 日志通道本身出错绝不能把 App 带崩。
            UniLog.w(LogTags.LOG, "日志通道调用失败", t, "method", call.method);
            try {
                result.error("unavailable", "日志服务暂不可用", null);
            } catch (Throwable ignored) {
                // 通道已经断了
            }
        }
    }

    @SuppressWarnings("unchecked")
    private static void log(MethodCall call) {
        Object argument = call.arguments;
        if (argument instanceof List) {
            // 批量：一次通道调用送一批记录，避免高频日志把平台通道打满。
            LogTools.logBatchFromFlutter((List<Map<String, Object>>) argument);
            return;
        }
        if (argument instanceof Map) {
            Map<String, Object> record = (Map<String, Object>) argument;
            Object kind = record.get("kind");
            if ("anchor".equals(String.valueOf(kind))) {
                LogTools.anchorFromFlutter(string(record.get("tag")), string(record.get("node")),
                        string(record.get("stage")), map(record.get("fields")));
                return;
            }
            LogTools.logFromFlutter(string(record.get("level")), string(record.get("tag")),
                    string(record.get("message")), map(record.get("fields")));
        }
    }

    @SuppressWarnings("unchecked")
    private static void anchor(MethodCall call) {
        Map<String, Object> record = call.arguments instanceof Map
                ? (Map<String, Object>) call.arguments : new java.util.HashMap<>();
        LogTools.anchorFromFlutter(string(record.get("tag")), string(record.get("node")),
                string(record.get("stage")), map(record.get("fields")));
    }

    private static void export(Context context, MethodChannel.Result result, boolean share) {
        LogTools.ExportCallback callback = (exported, message) -> {
            // 两条路都回同一份结构化结果。分享只是多弹一个面板，
            // 导出本身成没成功是同一件事 —— 回一句纯文案的话，
            // Flutter 侧解析不出来，界面就会把「导出成功」显示成失败。
            Map<String, Object> payload = exportResult(exported);
            payload.put("message", message == null ? "" : message);
            result.success(payload);
        };
        if (share) LogTools.exportAndShare(context, callback);
        else LogTools.export(context, callback);
    }

    /**
     * 导出结果：给界面看的文案，加上取件用的绝对路径。
     *
     * <p>路径单独给出，是为了让人（和自动化验证）能直接确认文件真的落在了
     * 公共目录里，而不是只相信一句「导出成功」。
     */
    private static Map<String, Object> exportResult(Diagnostics.Result result) {
        Map<String, Object> payload = new java.util.LinkedHashMap<>();
        payload.put("ok", result.ok());
        payload.put("path", result.displayPath);
        payload.put("files", result.fileCount);
        payload.put("bytes", result.bytes);
        payload.put("reason", result.reason == null ? "" : result.reason);
        return payload;
    }

    private static void level(MethodCall call, MethodChannel.Result result) {
        Object argument = call.arguments;
        if (argument instanceof String) {
            LogLevel level = LogLevel.byNameOrNull(String.valueOf(argument).toUpperCase(java.util.Locale.CHINA));
            if (level == null) {
                result.error("invalid", "未知的日志级别", null);
                return;
            }
            UniLog.setLevel(level);
        }
        result.success(UniLog.level().name());
    }

    /** 日志系统状态（设置页展示用）。 */
    private static Map<String, Object> status(Context context) {
        Map<String, Object> status = new java.util.LinkedHashMap<>();
        status.put("level", UniLog.level().name());
        status.put("bytes", UniLog.totalBytes());
        status.put("degraded", UniLog.degraded());
        status.put("anchors", AnchorLedger.nodeCount());
        status.put("initialized", UniLog.initialized());
        // 导出诊断包要写公共目录，权限没授就得让界面看见，别等导出时才报错。
        status.put("storageWritable",
                xyz.i4o.uni.launcher.MainActivity.storageWritable(context));
        status.put("storageReadable",
                xyz.i4o.uni.launcher.MainActivity.storageReadable(context));
        return status;
    }

    private static int intArgument(MethodCall call, int fallback) {
        Object argument = call.arguments;
        if (argument instanceof Number) return ((Number) argument).intValue();
        return fallback;
    }

    @SuppressWarnings("unchecked")
    private static Map<String, Object> map(Object value) {
        return value instanceof Map ? (Map<String, Object>) value : null;
    }

    private static String string(Object value) {
        return value == null ? null : String.valueOf(value);
    }
}
