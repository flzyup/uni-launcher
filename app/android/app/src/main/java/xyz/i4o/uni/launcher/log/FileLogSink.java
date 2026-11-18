package xyz.i4o.uni.launcher.log;

import android.content.Context;
import android.os.StatFs;
import android.util.Log;

import java.io.File;
import java.io.RandomAccessFile;
import java.text.SimpleDateFormat;
import java.util.ArrayDeque;
import java.util.ArrayList;
import java.util.Collections;
import java.util.Deque;
import java.util.Date;
import java.util.List;
import java.util.Locale;

/**
 * 落盘日志：按天分文件、单文件限大小、滚动保留若干份。
 *
 * <h3>为什么自己写</h3>
 * 真机调试时 {@code adb logcat} 会被别的进程刷走，而且**重启就丢**。
 * 这里把日志同时写到 App 私有目录，一键导出成诊断包发给开发。
 *
 * <h3>文件规则（车机存储紧张，占用必须封顶）</h3>
 * <ul>
 *   <li>目录：{@code context.filesDir/logs/}</li>
 *   <li>命名：{@code uni-yyyyMMdd-<序号>.txt}（同一天超过 {@link #MAX_FILE_BYTES} 就换下一个序号）</li>
 *   <li>单文件上限：{@link #MAX_FILE_BYTES}（512KB）</li>
 *   <li>份数上限：{@link #MAX_FILES}（8 份）</li>
 *   <li><b>总字节上限</b>：{@link #MAX_TOTAL_BYTES}（4MB）—— 份数一样、每份大小不同的话占用差别很大，
 *       所以再加一道总字节的硬上限；两者取更严的那个</li>
 *   <li><b>磁盘余量保护</b>：剩余可用空间低于 {@link #MIN_FREE_BYTES}（16MB）就**不再写盘**，
 *       只留 Logcat —— 日志不能把车机写满，那会影响导航、空调这些正经功能</li>
 * </ul>
 *
 * <h3>线程安全</h3>
 * 写入用一把锁串行化；Logcat 输出不锁（{@code android.util.Log} 自己有锁）。
 */
final class FileLogSink {
    /** 单个日志文件上限（512KB）。 */
    static final long MAX_FILE_BYTES = 512L * 1024;
    /** 最多保留多少个日志文件。 */
    static final int MAX_FILES = 8;
    /** 全部日志文件的总字节上限（4MB）。与份数上限取更严的那个。 */
    static final long MAX_TOTAL_BYTES = 4L * 1024 * 1024;
    /** 剩余可用空间低于这个值就不再写盘（把空间留给系统）。 */
    static final long MIN_FREE_BYTES = 16L * 1024 * 1024;
    /** 同一天最多造多少个文件（防止 index 无限增长）。 */
    static final int MAX_INDEX_PER_DAY = 64;
    /** 每写多少条做一次保留份数/总字节的清理（避免每条日志都 listFiles）。 */
    static final int TRIM_INTERVAL = 256;
    /** 日志目录名。 */
    static final String DIR_NAME = "logs";

    private static final SimpleDateFormat DAY_FMT = new SimpleDateFormat("yyyyMMdd", Locale.CHINA);
    private static final SimpleDateFormat TIME_FMT = new SimpleDateFormat("MM-dd HH:mm:ss.SSS", Locale.CHINA);

    private final File dir;
    private final Object lock = new Object();
    private File current;

    /** 距离下一次清理还剩多少条。 */
    private int writesSinceTrim;

    /**
     * 是否已经因为**磁盘写不进去**而降级（停止落盘，只留 Logcat）。
     *
     * 车机存储满了以后继续写只会一直抛异常、一直刷 Logcat 警告，
     * 所以一旦确认是空间问题就直接停写，等用户清日志或系统腾出空间再说。
     */
    private volatile boolean degraded;

    /** 当前落盘级别（低于这个级别的只进 Logcat，不落盘）。 */
    private volatile LogLevel level = LogLevel.INFO;

    FileLogSink(Context context) {
        this.dir = new File(context.getFilesDir(), DIR_NAME);
    }

    /**
     * 待落盘的记录（已带行分隔符）。
     *
     * <p>有界：日志宁可丢，也绝不能阻塞调用线程 —— 大部分日志是在主线程写的。
     */
    private final java.util.concurrent.ConcurrentLinkedQueue<String> pending =
            new java.util.concurrent.ConcurrentLinkedQueue<>();
    /** 队列上限：积压到这个数说明磁盘跟不上，直接丢弃新记录。 */
    private static final int MAX_PENDING = 4096;
    /** 落盘线程。单线程保证顺序，最低优先级，daemon 不挡进程退出。 */
    private static final java.util.concurrent.ExecutorService WRITER =
            java.util.concurrent.Executors.newSingleThreadExecutor(r -> {
                Thread t = new Thread(r, "uni-log-writer");
                t.setDaemon(true);
                t.setPriority(Thread.MIN_PRIORITY);
                return t;
            });
    private final java.util.concurrent.atomic.AtomicBoolean draining =
            new java.util.concurrent.atomic.AtomicBoolean();

    /**
     * 写一行。返回 true 表示已接受（入队）。
     *
     * <p><b>这里绝不能同步写盘。</b>每次落盘是一次 open/seek/write/close，而
     * onStart、onResume、快照发布这些热路径上每条日志都在主线程调用它。一次
     * 「从第三方应用返回桌面」会打出 15~20 条 INFO，以前就是 15~20 次同步文件
     * 操作压在主线程上，正好压在用户等的那一帧前面。
     */
    boolean write(LogLevel level, String tag, String message, Throwable error) {
        if (!level.reached(this.level)) return false;
        if (degraded) return false;
        if (pending.size() >= MAX_PENDING) return false;
        try {
            String line = LogFormat.line(TIME_FMT.format(new Date()), level, tag, message, error);
            pending.add(LogFormat.record(line));
        } catch (Throwable ignored) {
            return false;
        }
        scheduleDrain();
        return true;
    }

    private void scheduleDrain() {
        if (!draining.compareAndSet(false, true)) return;
        try {
            WRITER.execute(this::drain);
        } catch (Throwable t) {
            draining.set(false);
        }
    }

    /** 后台线程：把队列排空。期间新到的记录由下一轮处理。 */
    private void drain() {
        try {
            String record;
            while ((record = pending.poll()) != null) append(record);
        } finally {
            draining.set(false);
            if (!pending.isEmpty()) scheduleDrain();
        }
    }

    /** 真正落盘一条（后台线程，串行）。 */
    private void append(String record) {
        synchronized (lock) {
            try {
                File file = target();
                if (file == null) return;
                try (RandomAccessFile raf = new RandomAccessFile(file, "rw")) {
                    raf.seek(raf.length());
                    // 每条记录必须带行分隔符，否则整个文件会挤成一行
                    raf.write(record.getBytes(java.nio.charset.StandardCharsets.UTF_8));
                }
                if (++writesSinceTrim >= TRIM_INTERVAL) {
                    writesSinceTrim = 0;
                    trim();
                }
            } catch (Throwable e) {
                // 日志系统自己不能把 App 弄崩
                if (isOutOfSpace(e)) {
                    degraded = true;
                    Log.w(LogTags.LOG, "file log write failed: out of space, stop persisting logs");
                } else {
                    Log.w(LogTags.LOG, "file log write failed: " + e.getMessage());
                }
            }
        }
    }

    /**
     * 当前正在写的文件；需要换文件时按规则挑一个新的。
     *
     * 返回 null 表示**现在不该写盘**：
     * <ul>
     *   <li>磁盘剩余空间低于 {@link #MIN_FREE_BYTES}；</li>
     *   <li>当天的文件序号已经用满（不应该发生，有总字节上限兜底）。</li>
     * </ul>
     */
    private File target() {
        if (!dir.exists() && !dir.mkdirs()) return null;
        String today = DAY_FMT.format(new Date());
        File file = current;
        if (file != null && file.exists() && LogFormat.isSameDay(file.getName(), today)) {
            if (file.length() < MAX_FILE_BYTES) return file;
        }
        // 要开新文件了：先把旧文件清一清，保证总占用不超标
        trim();
        // 磁盘余量不够就别写了 —— 日志不能把车机存储写满
        if (!hasFreeSpace()) {
            Log.w(LogTags.LOG, "free space below floor, stop persisting logs");
            degraded = true;
            return null;
        }
        // 新文件：找当天下一个可用序号
        for (int index = 0; index < MAX_INDEX_PER_DAY; index++) {
            File candidate = new File(dir, LogFormat.fileName(today, index));
            if (!candidate.exists() || candidate.length() < MAX_FILE_BYTES) {
                current = candidate;
                return candidate;
            }
        }
        return null;
    }

    /**
     * 删掉超出保留份数**或**超出总字节上限的旧文件。
     *
     * 两道约束取更严的那个：份数够但每份都不小，照样能把车机占满。
     */
    private void trim() {
        List<File> files = files();
        if (files.isEmpty()) return;
        List<String> names = new ArrayList<>(files.size());
        List<LogFormat.FileSize> sizes = new ArrayList<>(files.size());
        for (File file : files) {
            names.add(file.getName());
            sizes.add(new LogFormat.FileSize(file.getName(), file.length()));
        }
        List<String> drop = new ArrayList<>(LogFormat.toRemove(names, MAX_FILES));
        drop.addAll(LogFormat.toRemoveByBytes(sizes, MAX_TOTAL_BYTES));
        drop = new ArrayList<>(new java.util.LinkedHashSet<>(drop));
        if (drop.isEmpty()) return;
        for (String name : drop) {
            File file = new File(dir, name);
            try {
                file.delete();
            } catch (Throwable ignored) {
                // 删不掉就留着，下一轮 trim 再试
            }
            if (current != null && current.getName().equals(name)) current = null;
        }
        UniLog.d(LogTags.LOG, "清理旧日志文件", "deleted", drop.size(), "left", files.size() - drop.size());
    }

    /** 剩余可用空间是否还够写日志。取不到就按「够」处理，别误杀。 */
    private boolean hasFreeSpace() {
        try {
            StatFs stat = new StatFs(dir.getAbsolutePath());
            return stat.getAvailableBytes() > MIN_FREE_BYTES;
        } catch (Throwable t) {
            return true;
        }
    }

    /** 是不是「磁盘满了」这类不可恢复的错误。 */
    private boolean isOutOfSpace(Throwable e) {
        String msg = e.getMessage() + " " + e.getClass().getName();
        return msg.contains("ENOSPC") || msg.contains("No space") || msg.contains("空间");
    }

    /** 日志目录。 */
    File directory() {
        return dir;
    }

    /** 全部日志文件（按时间正序）。 */
    List<File> files() {
        File[] listed = dir.listFiles((f) -> f.getName().startsWith(LogFormat.FILE_PREFIX)
                && f.getName().endsWith(LogFormat.FILE_SUFFIX));
        if (listed == null) return Collections.emptyList();
        List<File> files = new ArrayList<>(listed.length);
        Collections.addAll(files, listed);
        files.sort((a, b) -> Long.compare(a.lastModified(), b.lastModified()));
        return files;
    }

    /** 当前日志占用的总字节数。 */
    long totalBytes() {
        long total = 0L;
        for (File file : files()) total += file.length();
        return total;
    }

    /** 末尾 {@code lines} 行（给「导出前预览」用）。 */
    String tail(int lines) {
        StringBuilder out = new StringBuilder();
        List<File> files = files();
        for (int i = files.size() - 1; i >= 0; i--) {
            File file = files.get(i);
            // 逐行读取而不是一次读满：日志文件可以到 512KB，
            // 而 java.nio.file 是 API 26 才有的 —— 本应用最低支持 API 24。
            try (java.io.BufferedReader reader = new java.io.BufferedReader(
                    new java.io.InputStreamReader(
                            new java.io.FileInputStream(file), java.nio.charset.StandardCharsets.UTF_8))) {
                Deque<String> tail = new ArrayDeque<>();
                String line;
                while ((line = reader.readLine()) != null) {
                    tail.addLast(line);
                    if (tail.size() > lines) tail.removeFirst();
                }
                for (String text : tail) out.append(text).append('\n');
            } catch (Throwable ignored) {
                // 单个文件读不出来不影响其它文件
            }
        }
        return out.toString();
    }

    /** 清空全部日志（顺带解除降级状态，让落盘重新可用）。 */
    void clear() {
        pending.clear();
        synchronized (lock) {
            current = null;
            writesSinceTrim = 0;
            for (File file : files()) {
                try {
                    file.delete();
                } catch (Throwable ignored) {
                    // 删不掉就留着
                }
            }
            degraded = false;
        }
    }

    /** 当前落盘级别。 */
    LogLevel level() {
        return level;
    }

    void level(LogLevel level) {
        this.level = level;
    }

    /** 是否已降级（磁盘不足，只写 Logcat）。 */
    boolean degraded() {
        return degraded;
    }
}
