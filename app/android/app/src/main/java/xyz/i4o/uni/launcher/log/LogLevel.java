package xyz.i4o.uni.launcher.log;

/**
 * 日志级别。
 *
 * 落盘规则：低于 {@code UniLog.level()} 的级别**只进 Logcat 不落盘**，
 * 避免车机长期运行把存储写满。
 *
 * 单独成文件是为了让格式化逻辑能在 **JVM 单测**里直接用（不碰
 * {@code android.util.Log} 的 stub）。
 */
public enum LogLevel {
    /** 调试细节：默认不落盘。 */
    DEBUG("D", android.util.Log.DEBUG),
    /** 关键状态与用户操作：默认落盘。 */
    INFO("I", android.util.Log.INFO),
    /** 异常与降级：总是落盘。 */
    WARN("W", android.util.Log.WARN),
    /** 错误：总是落盘。 */
    ERROR("E", android.util.Log.ERROR);

    /** 落盘时的单字符标记。 */
    public final String label;
    /** 对应的 Logcat 优先级。 */
    public final int androidPriority;

    LogLevel(String label, int androidPriority) {
        this.label = label;
        this.androidPriority = androidPriority;
    }

    /** 是否达到落盘门槛。 */
    public boolean reached(LogLevel threshold) {
        return ordinal() >= threshold.ordinal();
    }

    /**
     * 按名字解析（用于持久化后回读）。
     *
     * 认不出来就返回 null（调用方回落默认级别）——
     * 持久化的值可能来自旧版本或被手改，不能让它把日志系统搞挂。
     */
    public static LogLevel byNameOrNull(String name) {
        if (name == null || name.trim().isEmpty()) return null;
        for (LogLevel level : values()) if (level.name().equals(name)) return level;
        return null;
    }
}
