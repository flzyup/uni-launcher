package xyz.i4o.uni.launcher.log;

import android.content.ContentValues;
import android.content.Context;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.net.Uri;
import android.os.Build;
import android.os.Environment;
import android.provider.MediaStore;
import android.util.Log;

import java.io.File;
import java.io.FileOutputStream;
import java.io.OutputStream;
import java.text.SimpleDateFormat;
import java.util.ArrayList;
import java.util.Date;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.zip.ZipEntry;
import java.util.zip.ZipOutputStream;

import xyz.i4o.uni.launcher.GlobalDockService;
import xyz.i4o.uni.launcher.LauncherRuntime;
import xyz.i4o.uni.launcher.StartupTrace;
import xyz.i4o.uni.launcher.ambient.AmbientLightBridge;
import xyz.i4o.uni.launcher.audio.SpectrumBridge;

/**
 * 诊断包导出：把日志 + 运行快照打成一个 zip，落到公共目录，用户在车上直接取走。
 *
 * <h3>产物</h3>
 * <pre>
 * Download/UNI/uni-logs-20261103-204012.zip
 *   ├── summary.txt 环境 / 版本 / 权限 / 车辆通道 / 锚点 / 设置全量键值
 *   └── logs/ 全部日志文件（uni-yyyyMMdd-N.txt）
 * </pre>
 *
 * <h3>为什么不用 FileProvider</h3>
 * 分享走 {@code MediaStore} 的 {@code content://} URI + {@code ACTION_SEND}，
 * 不需要额外引入 androidx 的 FileProvider。
 */
public final class Diagnostics {
    private Diagnostics() {}

    /** 导出结果。 */
    public static final class Result {
        /** 成功。{@code uri} 为 null 表示写到了公共目录的普通路径（Android 9 及以下）。 */
        public final Uri uri;
        public final String displayPath;
        public final int fileCount;
        public final long bytes;
        public final String reason;

        private Result(Uri uri, String displayPath, int fileCount, long bytes, String reason) {
            this.uri = uri;
            this.displayPath = displayPath;
            this.fileCount = fileCount;
            this.bytes = bytes;
            this.reason = reason;
        }

        public boolean ok() {
            return reason == null;
        }

        static Result success(Uri uri, String displayPath, int fileCount, long bytes) {
            return new Result(uri, displayPath, fileCount, bytes, null);
        }

        static Result fail(String reason) {
            return new Result(null, "", 0, 0L, reason);
        }
    }

    private static final String TAG = LogTags.LOG;
    private static final String PUBLIC_DIR_NAME = "UNI";
    private static final String STAMP_FMT = "yyyyMMdd-HHmmss";

    /**
     * 打进诊断包的日志总字节上限（2MB）。
     *
     * 日志文件本身有 4MB 上限，压缩后一般远小于此，
     * 但保险起见还是限一下 —— 诊断包要写到公共目录，车机存储紧张。
     * 超了只带**最新**的那部分，并在 summary 里注明截断了。
     */
    private static final long PACK_LOG_BYTES = 2L * 1024 * 1024;

    /** 诊断包文件名前缀（用于识别并清理旧包）。 */
    private static final String PACK_NAME_PREFIX = "uni-logs-";

    /** 公共目录里最多保留几份诊断包。 */
    private static final int KEEP_PACKS = 3;

    /** 需要在快照里核对的权限。 */
    private static final String[] PERMISSIONS = {
            android.Manifest.permission.INTERNET,
            android.Manifest.permission.ACCESS_NETWORK_STATE,
            android.Manifest.permission.ACCESS_WIFI_STATE,
            android.Manifest.permission.CHANGE_WIFI_STATE,
            android.Manifest.permission.WAKE_LOCK,
            android.Manifest.permission.ACCESS_COARSE_LOCATION,
            android.Manifest.permission.ACCESS_FINE_LOCATION,
            android.Manifest.permission.RECEIVE_BOOT_COMPLETED,
            // `Manifest.permission.QUERY_ALL_PACKAGES` 是 API 30 起公开的常量，
            // 老系统编不到 —— 这里用权限名字符串。
            "android.permission.QUERY_ALL_PACKAGES",
            android.Manifest.permission.WRITE_EXTERNAL_STORAGE,
            android.Manifest.permission.READ_EXTERNAL_STORAGE,
            // 频谱采集（氛围灯）：没这两个权限频谱永远起不来，
            // 「灯不亮」在诊断包里就必须能自证。
            android.Manifest.permission.RECORD_AUDIO,
            android.Manifest.permission.MODIFY_AUDIO_SETTINGS,
            // 车辆能力（android.car 权限，system 签名）
            "android.car.permission.CAR_VENDOR_EXTENSION",
    };

    /**
     * 导出诊断包。
     *
     * 必须在**后台线程**调用（会读文件、写 zip、拷到公共目录）。
     */
    public static Result export(Context context) {
        Context app = context.getApplicationContext();
        // The exporter can be reached before any window exists (boot receiver,
        // global dock). Make sure the sink exists, otherwise the package would
        // be built without a single log file.
        UniLog.init(app);
        String stamp = new SimpleDateFormat(STAMP_FMT, Locale.CHINA).format(new Date());
        String name = PACK_NAME_PREFIX + stamp + ".zip";
        try {
            // 从**最新**的文件往回装，装满 PACK_LOG_BYTES 就停
            File dir = UniLog.logDirectory();
            File[] listed = dir == null ? null : dir.listFiles();
            List<File> all = new ArrayList<>();
            if (listed != null) {
                for (File file : listed) all.add(file);
            }
            all.sort((a, b) -> Long.compare(a.lastModified(), b.lastModified()));
            List<File> picked = new ArrayList<>();
            long pickedBytes = 0L;
            for (int i = all.size() - 1; i >= 0; i--) {
                File file = all.get(i);
                if (pickedBytes + file.length() > PACK_LOG_BYTES) continue;
                picked.add(file);
                pickedBytes += file.length();
            }
            picked.sort((a, b) -> a.getName().compareTo(b.getName()));
            boolean truncated = picked.size() < all.size();
            String summary = summary(app, truncated, all.size() - picked.size());
            File cacheZip = new File(app.getCacheDir(), name);
            long bytes;
            try (ZipOutputStream zos = new ZipOutputStream(new FileOutputStream(cacheZip))) {
                zos.putNextEntry(new ZipEntry("summary.txt"));
                zos.write(summary.getBytes(java.nio.charset.StandardCharsets.UTF_8));
                zos.closeEntry();
                for (File file : picked) {
                    zos.putNextEntry(new ZipEntry("logs/" + file.getName()));
                    try (java.io.InputStream in = new java.io.FileInputStream(file)) {
                        byte[] buffer = new byte[8192];
                        int read;
                        while ((read = in.read(buffer)) > 0) zos.write(buffer, 0, read);
                    }
                    zos.closeEntry();
                }
            }
            bytes = cacheZip.length();

            PublishResult target = publish(app, cacheZip, name);
            // 公共目录已经有副本了，cache 里的临时 zip 用完就删（车机存储紧张）
            try {
                cacheZip.delete();
            } catch (Throwable ignored) {
                // 删不掉就留着，下次导出会被覆盖
            }
            // 公共目录里的旧诊断包只留最近几份
            pruneOldPacks(app);
            if (target instanceof PublishResult.PublishedUri) {
                PublishResult.PublishedUri published = (PublishResult.PublishedUri) target;
                UniLog.i(TAG, "诊断包已导出", "uri", published.contentUri, "bytes", bytes, "files", picked.size());
                return Result.success(published.contentUri, published.display, picked.size(), bytes);
            }
            if (target instanceof PublishResult.Path) {
                PublishResult.Path path = (PublishResult.Path) target;
                UniLog.i(TAG, "诊断包已导出", "path", path.path, "bytes", bytes, "files", picked.size());
                return Result.success(null, path.path, picked.size(), bytes);
            }
            PublishResult.Fail fail = (PublishResult.Fail) target;
            UniLog.w(TAG, "诊断包导出失败", "reason", fail.reason);
            return Result.fail(fail.reason);
        } catch (Throwable t) {
            UniLog.e(TAG, "诊断包导出异常", t);
            return Result.fail(t.getMessage() == null ? t.getClass().getSimpleName() : t.getMessage());
        }
    }

    /** 分享诊断包（需要先 {@link #export} 拿到 Uri）。 */
    public static Intent shareIntent(Uri uri, String subject) {
        Intent intent = new Intent(Intent.ACTION_SEND);
        intent.setType("application/zip");
        intent.putExtra(Intent.EXTRA_STREAM, uri);
        intent.putExtra(Intent.EXTRA_SUBJECT, subject);
        intent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION);
        return intent;
    }

    // ------------------------------------------------------------------ 清理旧诊断包

    /**
     * 公共目录里只保留最近 {@link #KEEP_PACKS} 份诊断包，多余的删掉。
     *
     * 每次导出都会在 {@code Download/UNI/} 留一个 zip，车机存储紧张，
     * 不清理的话导个十几次就把公共目录塞满了。
     *
     * <h3>安全要求</h3>
     * 这里**绝对不能**用 {@code delete(uri.buildUpon().appendQueryParameter(_ID, id))}
     * 这种「把条件塞进 query param」的写法 —— MediaProvider 不一定按它过滤，
     * 实测会把 {@code Downloads} 集合里**所有**文件删掉（连用户的下载文件一起没）。
     *
     * 必须用标准 selection 形式，并且条件里同时带上**文件名**和**相对路径**，
     * 保证只可能删到「我们自己生成的、放在 UNI 目录里的」诊断包。
     */
    private static void pruneOldPacks(Context context) {
        try {
            // 按系统版本拆成两个方法：`MediaStore.Downloads` 是 API 29 才有的类，
            // 混在同一个方法里的话，API 24/28 的校验器可能把整个方法判为不可用，
            // 结果「只保留最近 3 份」在车机上就悄悄不生效了。
            if (Build.VERSION.SDK_INT >= 29) pruneOldPacksViaMediaStore(context);
            else pruneOldPacksViaFile(context);
        } catch (Throwable t) {
            UniLog.d(TAG, "清理旧诊断包失败", "reason", t.getClass().getSimpleName() + ": " + t.getMessage());
        }
    }

    /** Android 10+：走 MediaStore。只在 API 29 及以上才会被调用。 */
    private static void pruneOldPacksViaMediaStore(Context context) {
        android.content.ContentResolver resolver = context.getContentResolver();
        android.net.Uri collection = MediaStore.Downloads.EXTERNAL_CONTENT_URI;
        String[] projection = {
                MediaStore.Downloads._ID,
                MediaStore.Downloads.DISPLAY_NAME,
        };
        // 条件要够窄：只看我们自己前缀的 zip，且只在我们自己的目录下
        String selection = MediaStore.Downloads.DISPLAY_NAME + " LIKE ? AND "
                + MediaStore.Downloads.RELATIVE_PATH + " LIKE ?";
        String[] args = {PACK_NAME_PREFIX + "%", "%" + PUBLIC_DIR_NAME + "%"};
        List<Map.Entry<Long, String>> rows = new ArrayList<>();
        try (android.database.Cursor cursor = resolver.query(collection, projection, selection, args, null)) {
            if (cursor != null) {
                int idIdx = cursor.getColumnIndexOrThrow(MediaStore.Downloads._ID);
                int nameIdx = cursor.getColumnIndexOrThrow(MediaStore.Downloads.DISPLAY_NAME);
                while (cursor.moveToNext()) {
                    String name = cursor.getString(nameIdx);
                    // 二次确认名字，别只信 query 的 LIKE
                    if (name == null || !name.startsWith(PACK_NAME_PREFIX)) continue;
                    rows.add(new java.util.AbstractMap.SimpleEntry<>(
                            cursor.getLong(idIdx), name));
                }
            }
        }
        if (rows.size() <= KEEP_PACKS) return;
        // 按文件名里的时间戳排序（uni-logs-yyyyMMdd-HHmmss.zip）
        rows.sort((a, b) -> a.getValue().compareTo(b.getValue()));
        int drop = rows.size() - KEEP_PACKS;
        for (int i = 0; i < drop; i++) {
            Map.Entry<Long, String> row = rows.get(i);
            long id = row.getKey();
            String name = row.getValue();
            // 精确删除：selection 里同时带 _id / 文件名 / 目录，三重约束
            String delSelection = MediaStore.Downloads._ID + " = ? AND "
                    + MediaStore.Downloads.DISPLAY_NAME + " = ? AND "
                    + MediaStore.Downloads.RELATIVE_PATH + " LIKE ?";
            String[] delArgs = {String.valueOf(id), name, "%" + PUBLIC_DIR_NAME + "%"};
            int deleted = resolver.delete(collection, delSelection, delArgs);
            UniLog.d(TAG, "清理旧诊断包", "name", name, "deleted", deleted);
        }
    }

    /** Android 9 及以下：直接删文件（目录本身就是我们自己写的）。 */
    private static void pruneOldPacksViaFile(Context context) {
        List<File> packs = new ArrayList<>();
        for (File dir : publicDirCandidates()) {
            File[] listed = dir.listFiles((f) -> f.getName().startsWith(PACK_NAME_PREFIX)
                    && f.getName().endsWith(".zip"));
            if (listed == null) continue;
            java.util.Collections.addAll(packs, listed);
        }
        packs.sort((a, b) -> a.getName().compareTo(b.getName()));
        for (int i = 0; i < packs.size() - KEEP_PACKS; i++) {
            File file = packs.get(i);
            try {
                file.delete();
            } catch (Throwable ignored) {
                // 删不掉就留着
            }
            UniLog.d(TAG, "清理旧诊断包", "name", file.getName());
        }
        // MediaStore 再清一遍。
        // 普通应用对公共目录只有「进入」权限，连目录都列不出来（listFiles 返回 null），
        // 而那批包又是 MediaProvider 建的，只有 MediaStore 能删 —— 所以这一步不能省。
        pruneOldPacksViaMediaStoreFiles(context);
    }

    /**
     * Android 9 及以下：借 {@code MediaStore.Files} 清理旧诊断包。
     *
     * <p>条件同时带**目录**和**文件名**两个约束，删的只会是自己生成的包；
     * 绝不能把条件塞进 query param —— MediaProvider 不一定按它过滤，
     * 实测会把集合里**所有**文件删掉（连用户的下载文件一起没）。
     */
    private static void pruneOldPacksViaMediaStoreFiles(Context context) {
        // 读 MediaStore 集合要 READ_EXTERNAL_STORAGE，没有就别试：
        // 抛 SecurityException 只会把日志刷满，旧包留着也就是多占点空间。
        if (!hasPermission(context, android.Manifest.permission.READ_EXTERNAL_STORAGE)) {
            UniLog.d(TAG, "没有读外部存储权限，跳过 MediaStore 清理");
            return;
        }
        try {
            android.content.ContentResolver resolver = context.getContentResolver();
            android.net.Uri collection = MediaStore.Files.getContentUri("external");
            File download = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS);
            String dirPattern = download.getAbsolutePath() + "/%";
            // 两种落点都要管：Download/UNI/ 与退一步的 Download/ 根目录。
            String selection = "(" + MediaStore.MediaColumns.DATA + " LIKE ? OR "
                    + MediaStore.MediaColumns.DATA + " LIKE ?) AND "
                    + MediaStore.MediaColumns.DISPLAY_NAME + " LIKE ?";
            String[] args = {dirPattern + "UNI/%", dirPattern + PACK_NAME_PREFIX + "%",
                    PACK_NAME_PREFIX + "%"};
            List<Map.Entry<Long, String>> rows = new ArrayList<>();
            try (android.database.Cursor cursor = resolver.query(collection,
                    new String[]{MediaStore.MediaColumns._ID, MediaStore.MediaColumns.DATA},
                    selection, args, null)) {
                if (cursor != null) {
                    int idIdx = cursor.getColumnIndexOrThrow(MediaStore.MediaColumns._ID);
                    int dataIdx = cursor.getColumnIndexOrThrow(MediaStore.MediaColumns.DATA);
                    while (cursor.moveToNext()) {
                        String path = cursor.getString(dataIdx);
                        if (path == null) continue;
                        String name = path.substring(path.lastIndexOf('/') + 1);
                        if (!name.startsWith(PACK_NAME_PREFIX)) continue;
                        rows.add(new java.util.AbstractMap.SimpleEntry<>(
                                cursor.getLong(idIdx), path));
                    }
                }
            }
            if (rows.size() <= KEEP_PACKS) return;
            rows.sort((a, b) -> a.getValue().compareTo(b.getValue()));
            int drop = rows.size() - KEEP_PACKS;
            for (int i = 0; i < drop; i++) {
                Map.Entry<Long, String> row = rows.get(i);
                long id = row.getKey();
                String path = row.getValue();
                String name = path.substring(path.lastIndexOf('/') + 1);
                // 三重约束：_id / 完整路径 / 文件名
                String delSelection = MediaStore.MediaColumns._ID + " = ? AND "
                        + MediaStore.MediaColumns.DATA + " = ? AND "
                        + MediaStore.MediaColumns.DISPLAY_NAME + " = ?";
                String[] delArgs = {String.valueOf(id), path, name};
                int deleted = resolver.delete(collection, delSelection, delArgs);
                UniLog.d(TAG, "清理旧诊断包", "name", name, "deleted", deleted);
            }
        } catch (Throwable t) {
            UniLog.d(TAG, "清理旧诊断包失败", "reason", t.getClass().getSimpleName() + ": " + t.getMessage());
        }
    }

    // ------------------------------------------------------------------ 快照

    /**
     * 运行快照：环境 / 版本 / 权限 / 车辆通道 / 频谱 / 氛围灯 / 锚点 / 设置全量键值 / 日志占用。
     *
     * 用的就是 {@code LauncherRuntime} 那个 SharedPreferences 文件，所以**任何**设置项都会出现在里面，
     * 不需要为了打日志去改设置读取逻辑。
     *
     * @param truncated    是否因为超出包体上限而截断了日志
     * @param droppedCount 被截掉的文件数
     */
    public static String summary(Context context, boolean truncated, int droppedCount) {
        Context app = context.getApplicationContext();
        StringBuilder sb = new StringBuilder();
        sb.append("==== UNI 桌面 诊断快照 ====\n");
        sb.append("生成时间: ").append(new SimpleDateFormat("yyyy-MM-dd HH:mm:ss", Locale.CHINA).format(new Date())).append('\n');
        sb.append("包名: ").append(app.getPackageName()).append('\n');
        sb.append("版本: ").append(versionName(app)).append(" (code ").append(versionCode(app)).append(")\n");
        sb.append("安装时间: ").append(installTime(app)).append('\n');
        sb.append("系统: Android ").append(Build.VERSION.RELEASE)
                .append(" (SDK ").append(Build.VERSION.SDK_INT).append(")\n");
        sb.append("设备: ").append(Build.MANUFACTURER).append(' ').append(Build.MODEL).append('\n');
        sb.append("指纹: ").append(Build.FINGERPRINT).append('\n');
        sb.append("分辨率: ").append(display(app)).append('\n');
        sb.append("日志级别: ").append(UniLog.level().label).append('\n');

        // 冷启动：车机经常连不上 adb，「开机黑屏」到底慢在哪只能靠诊断包看。
        // 这里读 StartupTrace：本次进程的分段 + 上一次冷启动的持久化汇总
        //（持久化是因为日志会被轮转，开机最早那几行最容易丢）。
        sb.append("\n---- 冷启动 ----\n");
        try {
            sb.append(StartupTrace.describe());
        } catch (Throwable t) {
            sb.append("启动信息读取失败: ").append(t.getMessage()).append('\n');
        }

        sb.append("\n---- 权限 ----\n");
        for (String permission : PERMISSIONS) {
            sb.append(permission.substring(permission.lastIndexOf('.') + 1))
                    .append(": ")
                    .append(hasPermission(app, permission) ? "已授予" : "未授予")
                    .append('\n');
        }

        sb.append("\n---- 子系统状态（只读快照）----\n");
        try {
            sb.append(LauncherRuntime.describeAdaptersIfAlive(app));
        } catch (Throwable t) {
            sb.append("子系统状态读取失败: ").append(t.getMessage()).append('\n');
        }

        sb.append("\n---- 频谱 ----\n");
        try {
            sb.append(SpectrumBridge.diagnostics().toString()).append('\n');
        } catch (Throwable t) {
            sb.append("频谱状态读取失败: ").append(t.getMessage()).append('\n');
        }

        sb.append("\n---- 氛围灯 ----\n");
        try {
            sb.append(AmbientLightBridge.currentStatus().toString()).append('\n');
        } catch (Throwable t) {
            sb.append("氛围灯状态读取失败: ").append(t.getMessage()).append('\n');
        }

        sb.append("\n---- 全局底栏 ----\n");
        try {
            sb.append(GlobalDockService.snapshot(app).toString()).append('\n');
        } catch (Throwable t) {
            sb.append("底栏状态读取失败: ").append(t.getMessage()).append('\n');
        }

        // 锚点统计：关键功能节点被触发了多少次、最近走了哪几步。
        // 这一段是「看日志不用翻几百行」的入口。
        sb.append("\n---- 锚点统计（本次运行）----\n");
        sb.append("节点数: ").append(AnchorLedger.nodeCount()).append('\n');
        sb.append(AnchorLedger.describe());
        sb.append("\n---- 最近锚点 ----\n");
        sb.append(AnchorLedger.recent(40));

        sb.append("\n---- 设置全量键值（SharedPreferences: launcher）----\n");
        try {
            android.content.SharedPreferences sp = app.getSharedPreferences("launcher", Context.MODE_PRIVATE);
            Map<String, ?> all = sp.getAll();
            List<String> keys = new ArrayList<>(all.keySet());
            java.util.Collections.sort(keys);
            if (keys.isEmpty()) sb.append("(空)\n");
            for (String key : keys) {
                Object value = all.get(key);
                // 连**类型**一起列出来。
                //
                // `SharedPreferences.getInt()` 在键值被存成别的类型时会**直接抛 ClassCastException** ——
                // 旧格式只印 `toString()`，看不出类型，崩溃时定位不到是哪个键。
                sb.append(key).append(" = ").append(truncate(value == null ? null : value.toString()))
                        .append(" [").append(value == null ? "null" : value.getClass().getSimpleName()).append(']')
                        .append('\n');
            }
        } catch (Throwable t) {
            sb.append("读取设置失败: ").append(t.getMessage()).append('\n');
        }

        sb.append("\n---- 日志文件 ----\n");
        File dir = UniLog.logDirectory();
        if (dir == null || !dir.exists()) {
            sb.append("(无)\n");
        } else {
            File[] listed = dir.listFiles();
            List<File> files = new ArrayList<>();
            if (listed != null) java.util.Collections.addAll(files, listed);
            files.sort((a, b) -> a.getName().compareTo(b.getName()));
            if (files.isEmpty()) sb.append("(无)\n");
            long total = 0L;
            for (File file : files) {
                sb.append(file.getName()).append("  ").append(file.length()).append(" bytes\n");
                total += file.length();
            }
            sb.append("合计: ").append(total).append(" bytes（上限 ")
                    .append(FileLogSink.MAX_TOTAL_BYTES).append(" bytes / ")
                    .append(FileLogSink.MAX_FILES).append(" 份）\n");
            // 落盘降级 = 车机存储不够了，日志只剩 Logcat —— 这时要明确写出来，
            // 否则用户看到「日志很少」会以为是 App 的问题。
            if (UniLog.degraded()) {
                sb.append("⚠ 日志落盘已降级：磁盘剩余空间不足，只写 Logcat 不写文件\n");
            }
            if (truncated) {
                sb.append("⚠ 诊断包内日志已截断（超出包体上限，丢弃了最老的 ")
                        .append(droppedCount).append(" 个文件）\n");
            }
        }
        return sb.toString();
    }

    private static String truncate(String value) {
        if (value == null) return "null";
        return value.length() > 300 ? value.substring(0, 300) + "…" : value;
    }

    private static String versionName(Context context) {
        try {
            android.content.pm.PackageInfo info = context.getPackageManager().getPackageInfo(context.getPackageName(), 0);
            return info.versionName == null ? "?" : info.versionName;
        } catch (Throwable t) {
            return "?";
        }
    }

    private static long versionCode(Context context) {
        try {
            android.content.pm.PackageInfo info = context.getPackageManager().getPackageInfo(context.getPackageName(), 0);
            if (Build.VERSION.SDK_INT >= 28) return info.getLongVersionCode();
            return info.versionCode;
        } catch (Throwable t) {
            return 0L;
        }
    }

    private static String installTime(Context context) {
        try {
            long at = context.getPackageManager().getPackageInfo(context.getPackageName(), 0).firstInstallTime;
            return new SimpleDateFormat("yyyy-MM-dd HH:mm", Locale.CHINA).format(new Date(at));
        } catch (Throwable t) {
            return "?";
        }
    }

    private static String display(Context context) {
        try {
            android.util.DisplayMetrics metrics = context.getResources().getDisplayMetrics();
            return metrics.widthPixels + "x" + metrics.heightPixels + " @" + metrics.densityDpi + "dpi";
        } catch (Throwable t) {
            return "?";
        }
    }

    private static boolean hasPermission(Context context, String permission) {
        return context.checkSelfPermission(permission) == PackageManager.PERMISSION_GRANTED;
    }

    // ------------------------------------------------------------------ 发布到公共目录

    private abstract static class PublishResult {
        static final class PublishedUri extends PublishResult {
            final Uri contentUri;
            final String display;

            PublishedUri(Uri contentUri, String display) {
                this.contentUri = contentUri;
                this.display = display;
            }
        }

        static final class Path extends PublishResult {
            final String path;

            Path(String path) {
                this.path = path;
            }
        }

        static final class Fail extends PublishResult {
            final String reason;

            Fail(String reason) {
                this.reason = reason;
            }
        }
    }

    /**
     * 把 zip 放进公共目录。
     *
     * <ul>
     *   <li>Android 10+：走 {@code MediaStore.Downloads}，拿得到 {@code content://} Uri，可以直接分享；</li>
     *   <li>Android 9 及以下：直接写 {@code Download/UNI/}（需要 {@code WRITE_EXTERNAL_STORAGE}）。</li>
     * </ul>
     */
    private static PublishResult publish(Context context, File zip, String name) {
        if (Build.VERSION.SDK_INT >= 29) return publishViaMediaStore(context, zip, name);
        // Android 9 及以下：先直接写文件（车机上 UNI 是系统应用，这条路通），
        // 写不了再借 MediaStore 落到公共目录（普通应用没有 sdcard_rw 时的兜底）。
        PublishResult direct = publishViaFile(context, zip, name);
        if (!(direct instanceof PublishResult.Fail)) return direct;
        String why = ((PublishResult.Fail) direct).reason;
        UniLog.d(TAG, "直接写公共目录失败，改走 MediaStore", "reason", why);
        PublishResult viaMediaStore = publishViaMediaStoreFiles(context, zip, name);
        if (viaMediaStore instanceof PublishResult.Fail) {
            UniLog.w(TAG, "MediaStore 兜底也失败", "reason", ((PublishResult.Fail) viaMediaStore).reason);
            return direct;
        }
        return viaMediaStore;
    }

    private static PublishResult publishViaMediaStore(Context context, File zip, String name) {
        try {
            ContentValues values = new ContentValues();
            values.put(MediaStore.Downloads.DISPLAY_NAME, name);
            values.put(MediaStore.Downloads.MIME_TYPE, "application/zip");
            values.put(MediaStore.Downloads.RELATIVE_PATH, Environment.DIRECTORY_DOWNLOADS + "/" + PUBLIC_DIR_NAME);
            values.put(MediaStore.Downloads.IS_PENDING, 1);
            android.content.ContentResolver resolver = context.getContentResolver();
            Uri uri = resolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values);
            if (uri == null) {
                return new PublishResult.Fail("公共目录写入失败（MediaStore 返回空 Uri）");
            }
            try (OutputStream out = resolver.openOutputStream(uri);
                 java.io.InputStream in = new java.io.FileInputStream(zip)) {
                if (out == null) return new PublishResult.Fail("公共目录写入失败（拿不到输出流）");
                byte[] buffer = new byte[8192];
                int read;
                while ((read = in.read(buffer)) > 0) out.write(buffer, 0, read);
            }
            values.clear();
            values.put(MediaStore.Downloads.IS_PENDING, 0);
            resolver.update(uri, values, null, null);
            return new PublishResult.PublishedUri(uri, "Download/" + PUBLIC_DIR_NAME + "/" + name);
        } catch (Throwable t) {
            return new PublishResult.Fail(t.getMessage() == null ? "公共目录写入异常" : t.getMessage());
        }
    }

    private static PublishResult publishViaFile(Context context, File zip, String name) {
        if (!hasPermission(context, android.Manifest.permission.WRITE_EXTERNAL_STORAGE)) {
            return new PublishResult.Fail("没有存储写入权限（Android 9 及以下需要 WRITE_EXTERNAL_STORAGE）");
        }
        try {
            File dir = publicDir();
            if (!dir.exists() && !dir.mkdirs() && !dir.exists()) {
                return new PublishResult.Fail("无法创建目录 " + dir.getAbsolutePath());
            }
            File out = new File(dir, name);
            try (java.io.InputStream input = new java.io.FileInputStream(zip);
                 FileOutputStream output = new FileOutputStream(out)) {
                byte[] buffer = new byte[8192];
                int read;
                while ((read = input.read(buffer)) > 0) output.write(buffer, 0, read);
            }
            return new PublishResult.Path(out.getAbsolutePath());
        } catch (Throwable t) {
            return new PublishResult.Fail(t.getMessage() == null ? "公共目录写入异常" : t.getMessage());
        }
    }

    /**
     * Android 9 及以下的兜底：借 {@code MediaStore.Files} 落到公共 Download 目录。
     *
     * <p>直接写文件这条路的成立前提是进程在 {@code sdcard_rw} 组里 ——
     * 车机上 UNI 是系统应用，成立；但装成普通应用时进程组里没有这个组，
     * sdcardfs 不给写 {@code /sdcard/Download} 的权限，
     * {@code mkdirs()} 直接失败。
     *
     * <p>{@code MediaStore.Files} + {@code DATA} 让 MediaProvider 代为落盘，
     * 它自己是有权限的那个，所以普通应用也能把包放进公共目录。
     * {@code DATA} 这一列在 API 29 起废弃，这里只在 API 28 及以下用。
     *
     * <p>父目录必须已经存在：MediaProvider 只建文件，不建 {@code Download/UNI/}
     * 这一层。所以按候选目录逐个试，{@code Download/} 这一层是系统建的，一定在。
     */
    private static PublishResult publishViaMediaStoreFiles(Context context, File zip, String name) {
        if (!hasPermission(context, android.Manifest.permission.WRITE_EXTERNAL_STORAGE)) {
            return new PublishResult.Fail("没有存储写入权限（Android 9 及以下需要 WRITE_EXTERNAL_STORAGE）");
        }
        String lastError = "";
        for (File dir : publicDirCandidates()) {
            File out = new File(dir, name);
            try {
                ContentValues values = new ContentValues();
                values.put(MediaStore.MediaColumns.DATA, out.getAbsolutePath());
                values.put(MediaStore.MediaColumns.DISPLAY_NAME, name);
                values.put(MediaStore.MediaColumns.MIME_TYPE, "application/zip");
                values.put(MediaStore.MediaColumns.SIZE, zip.length());
                android.content.ContentResolver resolver = context.getContentResolver();
                Uri uri = resolver.insert(MediaStore.Files.getContentUri("external"), values);
                if (uri == null) {
                    lastError = "公共目录写入失败（MediaStore 返回空 Uri）";
                    continue;
                }
                try (OutputStream output = resolver.openOutputStream(uri);
                     java.io.InputStream input = new java.io.FileInputStream(zip)) {
                    if (output == null) {
                        lastError = "公共目录写入失败（拿不到输出流）";
                        resolver.delete(uri, null, null);
                        continue;
                    }
                    byte[] buffer = new byte[8192];
                    int read;
                    while ((read = input.read(buffer)) > 0) output.write(buffer, 0, read);
                }
                return new PublishResult.PublishedUri(uri, displayOf(out));
            } catch (Throwable t) {
                lastError = t.getClass().getSimpleName() + ": " + t.getMessage();
                UniLog.w(TAG, "MediaStore 写入公共目录异常", "path", out.getAbsolutePath(), "reason", lastError);
            }
        }
        return new PublishResult.Fail("公共目录写入异常 " + lastError);
    }

    /**
     * 公共目录候选：先 {@code Download/UNI/}（车机上的位置），再 {@code Download/}。
     *
     * <p>普通应用建不出 {@code Download/UNI/} 这一层，退到 {@code Download/} 根目录，
     * 那一层是系统建的，一定存在。
     */
    private static File[] publicDirCandidates() {
        File download = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS);
        return new File[]{new File(download, PUBLIC_DIR_NAME), download};
    }

    /** 给用户看的落点，路径是真的。 */
    private static String displayOf(File file) {
        String download = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS).getAbsolutePath();
        String path = file.getAbsolutePath();
        return path.startsWith(download) ? "Download/" + path.substring(download.length() + 1) : path;
    }

    /** 公共目录 {@code Download/UNI/}（首选落点）。 */
    private static File publicDir() {
        return publicDirCandidates()[0];
    }
}
