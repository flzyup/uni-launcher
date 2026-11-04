package xyz.i4o.uni.launcher.log;

/**
 * 日志行的格式化与文件命名（**纯逻辑**，不依赖 Android，可在 JVM 单测里直接验）。
 *
 * <h3>行格式</h3>
 * <pre>
 * MM-dd HH:mm:ss.SSS &lt;级别&gt; &lt;tag&gt; : &lt;消息&gt; [ key=value... ]
 * </pre>
 *
 * 结构化字段拼成 {@code key=value}，真机上可以直接 grep：
 * <pre>
 * adb logcat | grep 'UNI/Vehicle.*source=official'
 * </pre>
 *
 * <h3>锚点格式</h3>
 * <pre>
 * [ANCHOR] &lt;节点&gt; &lt;阶段&gt; [ key=value... ]
 * </pre>
 * 锚点用固定前缀标记，一条 grep 就能筛出某条链路的全部节点：
 * <pre>
 * adb logcat | grep '\[ANCHOR\] vehicle/read'
 * </pre>
 */
public final class LogFormat {
    private LogFormat() {}

    /** 日志文件名前缀。 */
    public static final String FILE_PREFIX = "uni-";
    /** 日志文件名后缀。 */
    public static final String FILE_SUFFIX = ".txt";
    /** 落盘时每条记录的结尾（行分隔符）。 */
    public static final String RECORD_SEPARATOR = "\n";

    /** 锚点前缀。 */
    public static final String ANCHOR_PREFIX = "[ANCHOR] ";
    /** 关键交互事件前缀。 */
    public static final String EVENT_PREFIX = "[EVT] ";

    /** 锚点阶段：进入。 */
    public static final String STAGE_ENTER = "enter";
    /** 锚点阶段：完成。 */
    public static final String STAGE_DONE = "done";
    /** 锚点阶段：失败。 */
    public static final String STAGE_FAIL = "fail";
    /** 锚点阶段：跳过（条件不满足而有意不走）。 */
    public static final String STAGE_SKIP = "skip";

    /**
     * 给一行日志加上行分隔符（落盘用，纯逻辑方便单测）。
     *
     * 每条记录必须自带换行 —— 否则整个文件会变成**一行**，
     * 用 {@code tail -n} / {@code grep -n} 看都会很难受。
     */
    public static String record(String line) {
        return line + RECORD_SEPARATOR;
    }

    /**
     * 拼消息：把结构化字段追加成 {@code key=value} 序列。
     *
     * <ul>
     *   <li>{@code null} 值写成 {@code null}（不是省略），方便看出「字段存在但没值」；</li>
     *   <li>字段按**成对**传入：{@code "key", value, "key2", value2}；</li>
     *   <li>值的字符串里如果含空格，不加引号（保持 grep 友好）。</li>
     * </ul>
     */
    public static String message(String message, Object[] fields) {
        if (fields == null || fields.length == 0) return message;
        StringBuilder sb = new StringBuilder(message);
        for (int i = 0; i + 1 < fields.length; i += 2) {
            sb.append(' ').append(fields[i]).append('=').append(value(fields[i + 1]));
        }
        // 落单的字段没有值，写出来比悄悄丢掉更容易定位问题。
        if (fields.length % 2 != 0) sb.append(' ').append(fields[fields.length - 1]).append("=(missing)");
        return sb.toString();
    }

    /** 字段值的字符串化：null 写成 null，其余走 toString。 */
    public static String value(Object value) {
        return value == null ? "null" : value.toString();
    }

    /** 拼一条锚点：{@code [ANCHOR] <节点> <阶段> [key=value...]}。 */
    public static String anchor(String node, String stage, Object[] fields) {
        StringBuilder sb = new StringBuilder(ANCHOR_PREFIX);
        sb.append(node == null || node.trim().isEmpty() ? "(unnamed)" : node);
        sb.append(' ').append(stage == null || stage.trim().isEmpty() ? STAGE_ENTER : stage);
        if (fields != null) {
            for (int i = 0; i + 1 < fields.length; i += 2) {
                sb.append(' ').append(fields[i]).append('=').append(value(fields[i + 1]));
            }
        }
        return sb.toString();
    }

    /**
     * 拼一整行日志（无异常）。
     */
    public static String line(String timestamp, LogLevel level, String tag, String message) {
        return line(timestamp, level, tag, message, null);
    }

    /**
     * 拼一整行日志。
     *
     * @param timestamp 时间戳文本（调用方给，避免这里依赖 {@code SimpleDateFormat} 的线程安全）
     * @param error     异常：非空时追加 {@code | 异常类: 消息}
     */
    public static String line(String timestamp, LogLevel level, String tag, String message, Throwable error) {
        StringBuilder sb = new StringBuilder();
        sb.append(timestamp).append(' ').append(level.label).append(' ').append(tag).append(" : ").append(message);
        if (error != null) {
            sb.append(" | ").append(error.getClass().getSimpleName()).append(": ").append(error.getMessage() == null ? "" : error.getMessage());
        }
        return sb.toString();
    }

    /**
     * 日志文件名：{@code uni-yyyyMMdd-<序号>.txt}。
     *
     * 同一天超过单文件上限时序号递增。
     */
    public static String fileName(String date, int index) {
        return FILE_PREFIX + date + "-" + index + FILE_SUFFIX;
    }

    /** 文件名里的日期部分是否匹配给定日期。 */
    public static boolean isSameDay(String fileName, String date) {
        return fileName.startsWith(FILE_PREFIX + date + "-");
    }

    /**
     * 裁剪保留列表：按修改时间正序，最多留 {@code maxFiles} 个，其余删除。
     *
     * @return 要删除的文件名集合（纯逻辑，方便单测）
     */
    public static java.util.List<String> toRemove(java.util.List<String> orderedNames, int maxFiles) {
        if (orderedNames.size() <= maxFiles) return java.util.Collections.emptyList();
        return new java.util.ArrayList<>(orderedNames.subList(0, orderedNames.size() - maxFiles));
    }

    /**
     * 按**总字节数**裁剪：从最老的开始删，直到总量不超过 {@code maxBytes}。
     *
     * 单靠「保留几份」兜不住总占用 —— 份数一样、每份大小不同的话占用差别很大，
     * 车机存储又很紧张，所以再加一道总字节的硬上限。
     *
     * @param orderedFiles 文件名 + 字节数，**按修改时间正序**（最老的在前）
     * @param maxBytes     总字节上限；{@code <= 0} 表示**不限制**（一个都不删）
     * @return 要删除的文件名（纯逻辑，方便单测）
     */
    public static java.util.List<String> toRemoveByBytes(java.util.List<FileSize> orderedFiles, long maxBytes) {
        if (orderedFiles.isEmpty() || maxBytes <= 0L) return java.util.Collections.emptyList();
        long total = 0L;
        for (FileSize file : orderedFiles) total += file.bytes;
        if (total <= maxBytes) return java.util.Collections.emptyList();
        java.util.List<String> drop = new java.util.ArrayList<>();
        for (FileSize file : orderedFiles) {
            if (total <= maxBytes) break;
            drop.add(file.name);
            total -= file.bytes;
        }
        return drop;
    }

    /** 文件名 + 字节数（避免在纯逻辑层引入 Android 的 Pair）。 */
    public static final class FileSize {
        public final String name;
        public final long bytes;

        public FileSize(String name, long bytes) {
            this.name = name;
            this.bytes = bytes;
        }
    }
}
