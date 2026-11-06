package xyz.i4o.uni.launcher.integration;

import android.annotation.SuppressLint;
import android.app.usage.StorageStats;
import android.app.usage.StorageStatsManager;
import android.content.Context;
import android.content.pm.ApplicationInfo;
import android.content.pm.PackageInfo;
import android.content.pm.PackageManager;
import android.os.Build;
import android.os.Environment;
import android.os.Handler;
import android.os.Looper;
import android.os.Process;
import android.os.StatFs;
import android.os.storage.StorageManager;
import android.os.SystemClock;
import android.os.UserHandle;
import android.util.Log;

import org.json.JSONArray;
import org.json.JSONObject;

import java.io.File;
import java.io.InputStream;
import java.lang.reflect.Method;
import java.lang.reflect.Proxy;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.HashMap;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.UUID;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;

import xyz.i4o.uni.launcher.core.CleanerRules;
import xyz.i4o.uni.launcher.platform.HiddenApiCompat;

/**
 * 全系统垃圾清理：一次遍历拿到所有类目，清理走系统接口 + 规则删除两条路。
 *
 * <p>四块能力，缺哪个就降级哪个，绝不假装成功：
 * <ul>
 *   <li>本应用缓存：直接删，零权限；</li>
 *   <li>所有应用缓存（内部 {@code /data/data/&lt;pkg&gt;/cache} + 外部
 *       {@code /sdcard/Android/data/&lt;pkg&gt;/cache}）：{@code StorageStatsManager} 统计 +
 *       反射 {@code deleteApplicationCacheFiles}，等价系统「清除缓存」；</li>
 *   <li>公开存储：{@link CleanerRules} 一次遍历喂全部规则，缩略图/日志/广告缓存/空目录/
 *       卸载残留/安装包/大文件同时算清；</li>
 *   <li>权限：{@code WRITE_EXTERNAL_STORAGE} 由 Activity 自动申请（面板打开即弹一次），
 *       其余 signature|privileged 权限随平台签名自动授予。</li>
 * </ul>
 *
 * <p>清理量只统计「delete() 真的返回 true」的字节数，不估算。
 */
public final class StorageCleaner {
    private static final String TAG = "UniCleaner";
    private static final String RULES_ASSET = "cleaner/rules.json";
    private static final String LOGICAL_ROOT = CleanerRules.LOGICAL_ROOT;
    /** 一次扫描最多走这么多个条目；MSM8996 上再大就会明显拖慢桌面。 */
    private static final int ENTRY_BUDGET = 60000;
    /** 单个 APK 的包信息解析要几十毫秒，给个上限防止全盘几千个包把扫描拖死。 */
    private static final int APK_CHECK_BUDGET = 80;
    private static final long SCAN_TIMEOUT_MS = 20000;
    private static final int WALK_MAX_DEPTH = 8;
    private static final int MAX_SELECTION = 12;
    /** {@code StorageManager.UUID_DEFAULT}：反射拿不到卷 UUID 时的主存储兜底。 */
    private static final UUID PRIMARY_UUID = new UUID(0L, 0L);
    private static final String PERM_READ_STORAGE = "android.permission.READ_EXTERNAL_STORAGE";
    private static final String PERM_WRITE_STORAGE = "android.permission.WRITE_EXTERNAL_STORAGE";
    private static final String PERM_DELETE_CACHE = "android.permission.DELETE_CACHE_FILES";
    private static final String PERM_USAGE_STATS = "android.permission.PACKAGE_USAGE_STATS";

    private final Context context;
    private final Runnable notify;
    private final Handler main = new Handler(Looper.getMainLooper());
    /** 清理互斥：主窗口和面板窗口可能同时点，两个引擎共用一个实例。 */
    private final Object cleanLock = new Object();

    private volatile boolean running, cancel;
    private volatile String phase = "idle", current = "", error = "";
    private volatile double progress;
    private volatile JSONArray categories = new JSONArray();
    private volatile long freeBytes, totalBytes, lastCleanBytes, lastCleanAt;
    private volatile JSONArray lastCleanIds = new JSONArray();
    private volatile String rulesIssue = "";
    private volatile boolean storageGranted;
    private volatile int revision;

    private final CleanerRules rules;
    private final Map<String, Bucket> buckets = new HashMap<>();
    private Bucket selfCache = new Bucket();
    private Bucket appCache = new Bucket();
    private Bucket systemCache = new Bucket();
    private boolean cacheStatsUsable = true;
    private int apkChecks;
    private int visited;
    private boolean budgetExceeded;
    private long scanStartedAt;
    /** 本次清理按文件推进的进度：缩略图一类动辄上万个文件，只按类目跳变看着像卡死。 */
    private volatile int purgeFiles;
    private volatile int purgeTotal;
    /** 最近一次扫描覆盖的条目与耗时，面板拿来交代「扫到了多少」。 */
    private volatile int scanned;
    private volatile long scanMs;

    public StorageCleaner(Context context, Runnable notify) {
        this.context = context.getApplicationContext() == null ? context : context.getApplicationContext();
        this.notify = notify;
        // 反射 deleteApplicationCacheFiles 需要放开隐藏 API；已在 Activity 里调过一次，
        // 这里再调是幂等的，Dock 先启动、Activity 还没创建的情况下也能用。
        HiddenApiCompat.tryExempt();
        this.storageGranted = hasPermission(PERM_WRITE_STORAGE);
        // final 字段不能在 try/catch 两处分别赋值，先落到局部再一次性定下来。
        CleanerRules loaded;
        String issue = "";
        try {
            loaded = loadRules();
        } catch (Throwable t) {
            loaded = new CleanerRules(new ArrayList<>(), new ArrayList<>());
            issue = "规则文件读取失败：" + t.getClass().getSimpleName();
        }
        this.rules = loaded;
        this.rulesIssue = issue;
    }

    // ---------------------------------------------------------------- 对外

    public JSONObject snapshot() {
        JSONObject j = new JSONObject();
        try {
            j.put("running", running)
                    .put("phase", phase)
                    .put("progress", Math.max(0, Math.min(1, progress)))
                    .put("current", current)
                    .put("rev", revision)
                    .put("free", freeBytes)
                    .put("total", totalBytes)
                    .put("categories", categories)
                    .put("storageGranted", storageGranted)
                    .put("scanned", scanned)
                    .put("scanMs", scanMs)
                    .put("purgeFiles", purgeFiles)
                    .put("purgeTotal", purgeTotal)
                    .put("lastClean", new JSONObject()
                            .put("bytes", lastCleanBytes)
                            .put("at", lastCleanAt)
                            .put("ids", lastCleanIds))
                    .put("error", error)
                    .put("rulesIssue", rulesIssue);
        } catch (Exception ignored) {
        }
        return j;
    }

    public void scan() {
        if (running) return;
        begin("scan");
        Thread worker = new Thread(() -> {
            try {
                scanInto();
            } catch (Throwable t) {
                Log.w(TAG, "scan failed", t);
                error = "扫描中断：" + t.getClass().getSimpleName();
            } finally {
                finish();
                Log.i(TAG, "scan done in " + (SystemClock.elapsedRealtime() - scanStartedAt) + "ms");
            }
        }, "uni-cleaner");
        worker.setDaemon(true);
        worker.start();
    }

    /** @param ids 逗号分隔的类目 id，超过 12 个或含未知 id 时整条命令作废。 */
    public void clean(String ids) {
        Set<String> selected = parseSelection(ids);
        if (selected.isEmpty()) {
            error = "未选择要清理的内容";
            bump();
            return;
        }
        if (running) {
            error = "正在扫描，等扫描完成再清理";
            bump();
            return;
        }
        begin("clean");
        Thread worker = new Thread(() -> cleanTask(selected), "uni-cleaner-clean");
        worker.setDaemon(true);
        worker.start();
    }

    public void cancel() {
        if (running) cancel = true;
    }

    /** 由 Activity 重新申请存储权限后调用，刷新授权状态并重扫。 */
    public void refreshPermission() {
        storageGranted = hasPermission(PERM_WRITE_STORAGE);
        bump();
        if (storageGranted && !running) scan();
    }

    private void begin(String nextPhase) {
        running = true;
        cancel = false;
        phase = nextPhase;
        progress = 0;
        current = "";
        error = "";
        purgeFiles = 0;
        purgeTotal = 0;
        bump();
    }

    private void finish() {
        running = false;
        phase = "idle";
        progress = 1;
        current = "";
        bump();
    }

    // ---------------------------------------------------------------- 扫描

    private void scanInto() {
        scanStartedAt = SystemClock.elapsedRealtime();
        visited = 0;
        apkChecks = 0;
        budgetExceeded = false;
        storageGranted = hasPermission(PERM_WRITE_STORAGE);
        volumeStats();
        buckets.clear();
        selfCache = measureSelfCache();
        progress = 0.12;
        bump();

        appCache = appCacheStats(false);
        progress = 0.3;
        bump();
        systemCache = appCacheStats(true);
        progress = 0.42;
        bump();

        walkStorage();
        categories = buildCategories();
        scanned = visited;
        scanMs = SystemClock.elapsedRealtime() - scanStartedAt;
    }

    private void walkStorage() {
        File storage = Environment.getExternalStorageDirectory();
        if (storage == null || !storage.isDirectory()) {
            buckets.clear();
            return;
        }
        if (!storageGranted) {
            buckets.clear();
            return;
        }
        String physicalRoot = storage.getAbsolutePath();
        long now = System.currentTimeMillis();
        ScanWalker walker = new ScanWalker(now);
        walk(storage, storage.listFiles(), physicalRoot, 0, walker);
        if (budgetExceeded) rulesIssue = "文件过多，部分目录没扫到";
    }

    private JSONArray buildCategories() {
        JSONArray out = new JSONArray();
        boolean pathsUsable = storageGranted;
        out.put(category("self-cache", "桌面缓存", "cache", "safe", true, true, selfCache,
                selfCache.count == 0 ? "已经很干净" : "图标与图片缓存，会自动重建", true));
        out.put(category("app-cache", "应用缓存", "cache", "low", cacheStatsUsable, true,
                appCache, appCacheNote(false), cacheStatsUsable));
        out.put(category("system-cache", "系统应用缓存", "cache", "review", false, true,
                systemCache, appCacheNote(true), cacheStatsUsable));
        for (CleanerRules.Rule rule : rules.rules()) {
            Bucket bucket = buckets.get(rule.id);
            if (bucket == null) bucket = new Bucket();
            String note = rule.note;
            if (!pathsUsable) {
                note = "正在获取存储权限…";
            } else if (note == null || note.isEmpty()) {
                note = bucket.count == 0 ? "没有发现" : bucket.count + " 个文件";
            }
            out.put(category(rule.id, rule.name, rule.group, rule.risk, rule.decisionEnabled(),
                    rule.verified, bucket, note, pathsUsable));
        }
        return out;
    }

    private String appCacheNote(boolean system) {
        if (!cacheStatsUsable) return "系统未开放存储统计（PACKAGE_USAGE_STATS）";
        Bucket bucket = system ? systemCache : appCache;
        if (bucket.apps == 0) return "没有可清理的缓存";
        return bucket.apps + " 个应用" + (bucket.unreadable > 0 ? "，" + bucket.unreadable + " 个读取受限" : "");
    }

    private Bucket measureSelfCache() {
        Bucket bucket = new Bucket();
        for (File dir : new File[]{context.getCacheDir(), codeCacheDir(), context.getExternalCacheDir()}) {
            if (dir == null) continue;
            long[] measured = measureContents(dir, 0);
            bucket.bytes += measured[0];
            bucket.count += (int) measured[1];
        }
        return bucket;
    }

    private File codeCacheDir() {
        try {
            return context.getCodeCacheDir();
        } catch (Throwable t) {
            return null;
        }
    }

    /** 所有应用的 cache。统计靠 StorageStatsManager，删除靠反射。 */
    @SuppressLint("NewApi")
    private Bucket appCacheStats(boolean system) {
        Bucket bucket = new Bucket();
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            cacheStatsUsable = false;
            return bucket;
        }
        StorageStatsManager stats = (StorageStatsManager) context.getSystemService(Context.STORAGE_STATS_SERVICE);
        UUID uuid = storageUuid(stats);
        if (stats == null || uuid == null) {
            Log.w(TAG, "storage stats unavailable: service=" + (stats != null) + " uuid=" + uuid);
            cacheStatsUsable = false;
            return bucket;
        }
        PackageManager pm = context.getPackageManager();
        UserHandle user = Process.myUserHandle();
        for (PackageInfo info : installedPackages(pm)) {
            ApplicationInfo app = info.applicationInfo;
            if (app == null) continue;
            boolean isSystem = (app.flags & ApplicationInfo.FLAG_SYSTEM) != 0;
            if (isSystem != system) continue;
            bucket.total++;
            try {
                long cache = stats.queryStatsForPackage(uuid, info.packageName, user).getCacheBytes();
                if (cache > 0) {
                    bucket.bytes += cache;
                    bucket.apps++;
                }
            } catch (Throwable t) {
                if (bucket.unreadable == 0) {
                    Log.w(TAG, "queryStatsForPackage(" + info.packageName + ") failed: "
                            + t.getClass().getSimpleName() + " " + t.getMessage());
                }
                bucket.unreadable++;
            }
        }
        // 全都被拒说明权限没下来，不是「刚好没缓存」。
        if (bucket.unreadable > 0 && bucket.unreadable == bucket.total) cacheStatsUsable = false;
        return bucket;
    }

    // ---------------------------------------------------------------- 遍历

    private void walk(File dir, File[] children, String physicalRoot, int depth, Walker walker) {
        if (cancel || children == null || depth > WALK_MAX_DEPTH || walker.exceeded()) return;
        Arrays.sort(children, (a, b) -> a.getName().compareToIgnoreCase(b.getName()));
        for (File child : children) {
            if (cancel) return;
            if (++visited > ENTRY_BUDGET) {
                budgetExceeded = true;
                return;
            }
            String logical = logicalOf(child, physicalRoot);
            if (logical == null) continue;
            if (CleanerRules.skipSubtree(logical)) continue;
            // 白名单在 matchAll 之前判一次：既不进规则，也整棵剪枝。
            if (rules.neverReason(logical) != null) continue;
            boolean isDir = child.isDirectory() && !isSymlink(child);
            File[] grandchildren = isDir ? child.listFiles() : null;
            long size = isDir ? 0 : child.length();
            long modified = child.lastModified();
            List<String> ids = rules.matchAll(logical, size, modified, walker.now());
            boolean handled = false;
            String only = walker.onlyRule();
            for (String id : ids) {
                if (only != null && !only.equals(id)) continue;
                CleanerRules.Rule rule = rules.rule(id);
                if (rule == null || depth > rule.maxDepth) continue;
                if (!passesCheck(rule, child, grandchildren, isDir)) continue;
                walker.onHit(child, rule, size, grandchildren, depth);
                handled = true;
                break;
            }
            if (handled) continue;
            if (isDir) walk(child, grandchildren, physicalRoot, depth + 1, walker);
        }
    }

    /** 扫描：每条命中归属第一条 check 通过的规则，累加到对应桶。 */
    private final class ScanWalker implements Walker {
        private final long now;
        private long lastBump;

        ScanWalker(long now) { this.now = now; }

        @Override public long now() { return now; }

        @Override public String onlyRule() { return null; }

        @Override public boolean exceeded() {
            if (budgetExceeded) return true;
            if (SystemClock.elapsedRealtime() - scanStartedAt > SCAN_TIMEOUT_MS) {
                rulesIssue = "扫描超时，结果可能不完整";
                return true;
            }
            return false;
        }

        @Override public void onHit(File file, CleanerRules.Rule rule, long size, File[] children, int depth) {
            Bucket bucket = buckets.get(rule.id);
            if (bucket == null) {
                bucket = new Bucket();
                buckets.put(rule.id, bucket);
            }
            if (file.isDirectory() && !isSymlink(file)) {
                long[] measured = measureContents(file, depth);
                bucket.bytes += measured[0];
                bucket.count += (int) measured[1];
            } else {
                bucket.bytes += size;
                bucket.count++;
            }
            long nowMs = SystemClock.elapsedRealtime();
            if (nowMs - lastBump > 160) {
                lastBump = nowMs;
                progress = Math.min(0.95, 0.42 + 0.53 * (visited / (double) ENTRY_BUDGET));
                bump();
            }
        }
    }

    /** 清理：同样的遍历，命中即删。 */
    private final class PurgeWalker implements Walker {
        private final CleanerRules.Rule target;
        private final long now = System.currentTimeMillis();
        long removed;

        PurgeWalker(CleanerRules.Rule target) { this.target = target; }

        @Override public long now() { return now; }

        @Override public String onlyRule() { return target.id; }

        @Override public boolean exceeded() { return cancel; }

        @Override public void onHit(File file, CleanerRules.Rule rule, long size, File[] children, int depth) {
            if (file.isDirectory() && rule.contents) {
                if (children != null) for (File inner : children) removed += deleteTree(inner);
            } else {
                removed += deleteTree(file);
            }
        }
    }

    interface Walker {
        long now();
        boolean exceeded();
        /** 非 null 时只考虑这一条规则（清理场景），避免命中被别的规则先截走。 */
        String onlyRule();
        void onHit(File file, CleanerRules.Rule rule, long size, File[] children, int depth);
    }

    // ---------------------------------------------------------------- 检查器

    /**
     * 规则附带的语义检查。规则文件里的 {@code check} 字段指向这里，不认识的检查器一律
     * 判 false：宁可少清，不猜。
     */
    private boolean passesCheck(CleanerRules.Rule rule, File file, File[] children, boolean isDir) {
        if (rule.check.isEmpty()) return true;
        switch (rule.check) {
            case "apk-outdated":
                return !isDir && apkOutdated(file);
            case "orphan-package":
                return isDir && packageOrphaned(file);
            case "empty-dir":
                return isDir && children != null && children.length == 0;
            default:
                return false;
        }
    }

    /**
     * 已安装且归档版本不高于已装版本 → 残留安装包。解析失败（split/apks/xapk）或未安装的包
     * 一律保留：那可能是用户正准备装的东西。
     */
    private boolean apkOutdated(File file) {
        if (apkChecks >= APK_CHECK_BUDGET) {
            rulesIssue = "安装包超过 " + APK_CHECK_BUDGET + " 个，只判定了一部分";
            return false;
        }
        apkChecks++;
        try {
            PackageManager pm = context.getPackageManager();
            PackageInfo archive = pm.getPackageArchiveInfo(file.getAbsolutePath(), 0);
            if (archive == null || archive.packageName == null) return false;
            PackageInfo installed;
            try {
                installed = pm.getPackageInfo(archive.packageName, 0);
            } catch (PackageManager.NameNotFoundException notInstalled) {
                return false;
            }
            return archive.versionCode <= installed.versionCode;
        } catch (Throwable t) {
            return false;
        }
    }

    /** 目录名就是包名、而该包已经不在了 → 卸载残留。 */
    private boolean packageOrphaned(File dir) {
        String name = dir.getName();
        if (name.isEmpty() || name.indexOf('.') < 0) return false;
        try {
            context.getPackageManager().getPackageInfo(name, 0);
            return false;
        } catch (PackageManager.NameNotFoundException missing) {
            return true;
        } catch (Throwable t) {
            return false;
        }
    }

    // ---------------------------------------------------------------- 清理

    private void cleanTask(Set<String> selected) {
        synchronized (cleanLock) {
            long started = SystemClock.elapsedRealtime();
            long removed = 0;
            JSONArray done = new JSONArray();
            int index = 0;
            purgeFiles = 0;
            purgeTotal = selectedFileCount(selected);
            try {
                for (String id : orderedSelection(selected)) {
                    if (cancel) break;
                    current = labelOf(id);
                    long step;
                    if ("self-cache".equals(id)) {
                        step = purgeSelfCache();
                    } else if ("app-cache".equals(id)) {
                        step = purgeAppCaches(false);
                    } else if ("system-cache".equals(id)) {
                        step = purgeAppCaches(true);
                    } else {
                        step = purgeRule(rules.rule(id));
                    }
                    removed += step;
                    done.put(id);
                    index++;
                    progress = index / (double) Math.max(1, selected.size());
                    bump();
                    Log.i(TAG, "cleaned " + id + " -> " + step + " bytes");
                }
            } catch (Throwable t) {
                Log.w(TAG, "clean failed", t);
                error = "清理中断：" + t.getClass().getSimpleName();
            } finally {
                lastCleanBytes = removed;
                lastCleanAt = System.currentTimeMillis();
                lastCleanIds = done;
                // 清理后重新统计，面板直接显示新数据（不依赖调用方再点一次扫描）。
                try {
                    scanStartedAt = SystemClock.elapsedRealtime();
                    visited = 0;
                    apkChecks = 0;
                    budgetExceeded = false;
                    volumeStats();
                    selfCache = measureSelfCache();
                    appCache = appCacheStats(false);
                    systemCache = appCacheStats(true);
                    buckets.clear();
                    walkStorage();
                    categories = buildCategories();
                    scanned = visited;
                    scanMs = SystemClock.elapsedRealtime() - scanStartedAt;
                } catch (Throwable t) {
                    Log.w(TAG, "refresh failed", t);
                }
                finish();
                Log.i(TAG, "clean done in " + (SystemClock.elapsedRealtime() - started)
                        + "ms, removed=" + removed);
            }
        }
    }

    private long purgeSelfCache() {
        long removed = 0;
        for (File dir : new File[]{context.getCacheDir(), codeCacheDir(), context.getExternalCacheDir()}) {
            if (dir == null) continue;
            File[] children = dir.listFiles();
            if (children == null) continue;
            for (File child : children) {
                if (cancel) return removed;
                removed += deleteTree(child);
            }
        }
        return removed;
    }

    /** 逐应用清 cache。反射失败即计数上报，不显示成成功。 */
    @SuppressLint("NewApi")
    private long purgeAppCaches(boolean system) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return 0;
        StorageStatsManager stats = (StorageStatsManager) context.getSystemService(Context.STORAGE_STATS_SERVICE);
        UUID uuid = storageUuid(stats);
        if (stats == null || uuid == null) {
            error = "系统存储统计接口不可用，应用缓存已跳过";
            return 0;
        }
        PackageManager pm = context.getPackageManager();
        UserHandle user = Process.myUserHandle();
        long before = sumCacheBytes(stats, uuid, pm, user, system);
        int failed = 0, attempted = 0;
        for (PackageInfo info : installedPackages(pm)) {
            if (cancel) break;
            ApplicationInfo app = info.applicationInfo;
            if (app == null) continue;
            boolean isSystem = (app.flags & ApplicationInfo.FLAG_SYSTEM) != 0;
            if (isSystem != system) continue;
            long cache;
            try {
                cache = stats.queryStatsForPackage(uuid, info.packageName, user).getCacheBytes();
            } catch (Throwable t) {
                continue;
            }
            if (cache <= 0) continue;
            attempted++;
            if (!deleteApplicationCacheFiles(pm, info.packageName)) failed++;
        }
        long after = sumCacheBytes(stats, uuid, pm, user, system);
        if (failed > 0 && attempted > 0) {
            error = failed + " 个应用的缓存未能清理（系统拒绝）";
        }
        // 以统计差值报数：binder 里的删除是异步的，逐字节累加会偏乐观。
        return Math.max(0, before - after);
    }

    private long sumCacheBytes(StorageStatsManager stats, UUID uuid, PackageManager pm,
                               UserHandle user, boolean system) {
        long total = 0;
        for (PackageInfo info : installedPackages(pm)) {
            ApplicationInfo app = info.applicationInfo;
            if (app == null) continue;
            boolean isSystem = (app.flags & ApplicationInfo.FLAG_SYSTEM) != 0;
            if (isSystem != system) continue;
            try {
                total += stats.queryStatsForPackage(uuid, info.packageName, user).getCacheBytes();
            } catch (Throwable ignored) {
            }
        }
        return total;
    }

    private long purgeRule(CleanerRules.Rule rule) {
        if (rule == null || !hasPermission(PERM_WRITE_STORAGE)) return 0;
        File storage = Environment.getExternalStorageDirectory();
        if (storage == null) return 0;
        String physicalRoot = storage.getAbsolutePath();
        PurgeWalker walker = new PurgeWalker(rule);
        // 从存储根走一遍，靠规则匹配（Walker.onlyRule）过滤，这样规则挂在多深的子目录都成立。
        walk(storage, storage.listFiles(), physicalRoot, 0, walker);
        return walker.removed;
    }

    /** 递归删除并累计真实删除的字节数；符号链接只删链接本身，不跟进去。 */
    private long deleteTree(File target) {
        if (target == null || cancel) return 0;
        String canonical = canonical(target);
        if (canonical == null) return 0;
        File file = new File(canonical);
        if (file.isDirectory() && !isSymlink(file)) {
            File[] children = file.listFiles();
            long removed = 0;
            if (children != null) for (File child : children) removed += deleteTree(child);
            // 目录本身不占字节，删不掉（被占用）就只把子项算进去。
            file.delete();
            return removed;
        }
        long size = file.length();
        if (!file.delete()) return 0;
        // 每 400 个文件推一次进度：13762 张缩略图那种量级，一次 publish 太贵，不推又像卡住。
        if ((++purgeFiles % 400) == 0) bump();
        return size;
    }

    /**
     * 选中类目预计要删的文件数，只算按路径走的规则类目；
     * 应用缓存走系统接口，没有文件粒度，进度用类目百分比。
     */
    private int selectedFileCount(Set<String> selected) {
        JSONArray list = categories;
        if (list == null) return 0;
        int total = 0;
        for (int i = 0; i < list.length(); i++) {
            JSONObject category = list.optJSONObject(i);
            if (category == null || !selected.contains(category.optString("id"))) continue;
            total += Math.max(0, category.optInt("count"));
        }
        return total;
    }

    // ---------------------------------------------------------------- 反射桥

    /**
     * {@code PackageManager.deleteApplicationCacheFiles(pkg, observer)}：系统设置里
     * 「清除缓存」的同一个入口，需要 {@code DELETE_CACHE_FILES}（signature|privileged）。
     */
    @SuppressLint("PrivateApi")
    private static boolean deleteApplicationCacheFiles(PackageManager pm, String packageName) {
        try {
            Class<?> observerClass = Class.forName("android.content.pm.IPackageDataObserver");
            ClassLoader loader = observerClass.getClassLoader();
            if (loader == null) loader = PackageManager.class.getClassLoader();
            final CountDownLatch done = new CountDownLatch(1);
            final boolean[] ok = {false};
            Object observer = Proxy.newProxyInstance(loader,
                    new Class<?>[]{observerClass}, (proxy, method, args) -> {
                        if ("onRemoveCompleted".equals(method.getName())) {
                            ok[0] = args != null && args.length > 1 && Boolean.TRUE.equals(args[1]);
                            done.countDown();
                        }
                        return null;
                    });
            Method method = PackageManager.class.getMethod(
                    "deleteApplicationCacheFiles", String.class, observerClass);
            method.invoke(pm, packageName, observer);
            done.await(3, TimeUnit.SECONDS);
            return ok[0];
        } catch (Throwable t) {
            return false;
        }
    }

    /**
     * 主存储卷 UUID。{@code getUuidForPath} 在 {@link StorageManager} 上（不是
     * {@code StorageStatsManager}），是隐藏方法；拿不到就退回主存储默认 UUID，
     * 但那样系统会把查询当成别的卷、缓存一律回 0，所以优先拿真值。
     */
    @SuppressLint("PrivateApi")
    private UUID storageUuid(StorageStatsManager stats) {
        if (stats == null) return null;
        StorageManager manager = (StorageManager) context.getSystemService(Context.STORAGE_SERVICE);
        if (manager == null) return PRIMARY_UUID;
        for (File probe : new File[]{Environment.getDataDirectory(), context.getFilesDir(),
                Environment.getExternalStorageDirectory()}) {
            if (probe == null) continue;
            try {
                Method method = StorageManager.class.getDeclaredMethod("getUuidForPath", File.class);
                method.setAccessible(true);
                Object value = method.invoke(manager, probe);
                if (value instanceof UUID) {
                    Log.i(TAG, "uuid(" + probe + ") = " + value);
                    return (UUID) value;
                }
            } catch (Throwable t) {
                Log.w(TAG, "getUuidForPath(" + probe + ") failed: " + t);
            }
        }
        return PRIMARY_UUID;
    }

    // ---------------------------------------------------------------- 工具

    private CleanerRules loadRules() throws Exception {
        try (InputStream in = context.getAssets().open(RULES_ASSET)) {
            String json = new String(readAll(in), StandardCharsets.UTF_8);
            return RuleJson.parse(new JSONObject(json));
        }
    }

    private static byte[] readAll(InputStream in) throws Exception {
        java.io.ByteArrayOutputStream out = new java.io.ByteArrayOutputStream();
        byte[] buffer = new byte[8192];
        int read;
        while ((read = in.read(buffer)) > 0) out.write(buffer, 0, read);
        return out.toByteArray();
    }

    private JSONObject category(String id, String name, String group, String risk, boolean defaultOn,
                                boolean verified, Bucket bucket, String note, boolean available) {
        JSONObject j = new JSONObject();
        try {
            j.put("id", id).put("name", name).put("group", group == null ? "junk" : group)
                    .put("risk", risk).put("default", defaultOn).put("verified", verified)
                    .put("bytes", Math.max(0, bucket.bytes)).put("count", Math.max(0, bucket.count))
                    .put("note", note == null ? "" : note).put("available", available);
        } catch (Exception ignoredEx) {
        }
        return j;
    }

    private Set<String> parseSelection(String ids) {
        Set<String> selected = new LinkedHashSet<>();
        if (ids == null || ids.isEmpty() || ids.length() > 256) return selected;
        Set<String> allowed = rules.cleanableIds();
        for (String raw : ids.split(",")) {
            String id = raw.trim();
            if (id.isEmpty() || !allowed.contains(id)) return new LinkedHashSet<>();
            selected.add(id);
            if (selected.size() > MAX_SELECTION) return new LinkedHashSet<>();
        }
        return selected;
    }

    /** 固定顺序：先自身缓存，再应用缓存，最后公开目录（规则文件顺序）。 */
    private List<String> orderedSelection(Set<String> selected) {
        List<String> ordered = new ArrayList<>();
        for (String id : CleanerRules.BUILTIN_IDS) if (selected.contains(id)) ordered.add(id);
        for (CleanerRules.Rule rule : rules.rules()) {
            if (selected.contains(rule.id)) ordered.add(rule.id);
        }
        return ordered;
    }

    private String labelOf(String id) {
        if ("self-cache".equals(id)) return "桌面缓存";
        if ("app-cache".equals(id)) return "应用缓存";
        if ("system-cache".equals(id)) return "系统应用缓存";
        CleanerRules.Rule rule = rules.rule(id);
        return rule == null ? id : rule.name;
    }

    private List<PackageInfo> installedPackages(PackageManager pm) {
        try {
            List<PackageInfo> list = pm.getInstalledPackages(0);
            return list == null ? new ArrayList<>() : list;
        } catch (Throwable t) {
            return new ArrayList<>();
        }
    }

    private boolean hasPermission(String permission) {
        try {
            return context.checkSelfPermission(permission) == PackageManager.PERMISSION_GRANTED;
        } catch (Throwable t) {
            return false;
        }
    }

    private void volumeStats() {
        try {
            File storage = Environment.getExternalStorageDirectory();
            if (storage == null) return;
            StatFs stat = new StatFs(storage.getAbsolutePath());
            totalBytes = stat.getBlockCountLong() * stat.getBlockSizeLong();
            freeBytes = stat.getAvailableBlocksLong() * stat.getBlockSizeLong();
        } catch (Throwable t) {
            Log.w(TAG, "volume stats failed", t);
        }
    }

    /** 只做字符串拼接，不走 canonical：六万条目每个都做一次 syscall 会明显拖慢扫描。 */
    private String logicalOf(File file, String physicalRoot) {
        String path = file.getAbsolutePath();
        if (path == null || !path.startsWith(physicalRoot)) return null;
        return LOGICAL_ROOT + path.substring(physicalRoot.length());
    }

    private String canonical(File file) {
        try {
            String path = file.getCanonicalPath();
            if (path == null || path.length() > 1024) return null;
            return path;
        } catch (Throwable t) {
            return null;
        }
    }

    private static boolean isSymlink(File file) {
        try {
            return !file.getCanonicalFile().equals(file.getAbsoluteFile());
        } catch (Throwable t) {
            return false;
        }
    }

    /** 统计目录内文件总字节数与文件数（不跟随符号链接）。 */
    private long[] measureContents(File dir, int depth) {
        long[] total = new long[]{0, 0};
        if (dir == null || depth > WALK_MAX_DEPTH + 2) return total;
        File[] children = dir.listFiles();
        if (children == null) return total;
        for (File child : children) {
            if (child.isDirectory() && !isSymlink(child)) {
                long[] inner = measureContents(child, depth + 1);
                total[0] += inner[0];
                total[1] += inner[1];
            } else {
                total[0] += child.length();
                total[1]++;
            }
        }
        return total;
    }

    private void bump() {
        revision++;
        Runnable callback = notify;
        if (callback == null) return;
        if (Looper.myLooper() == Looper.getMainLooper()) callback.run();
        else main.post(callback);
    }

    static final class Bucket {
        long bytes;
        int count;
        int apps;
        int total;
        int unreadable;
    }

    // ---------------------------------------------------------------- 规则解析

    /** 只认已知字段，坏规则跳过，不让整份文件失效。 */
    static final class RuleJson {
        static CleanerRules parse(JSONObject root) {
            List<CleanerRules.Rule> rules = new ArrayList<>();
            List<CleanerRules.Never> never = new ArrayList<>();
            JSONArray rawRules = root.optJSONArray("rules");
            if (rawRules != null) {
                for (int i = 0; i < rawRules.length(); i++) {
                    JSONObject raw = rawRules.optJSONObject(i);
                    if (raw == null) continue;
                    String id = raw.optString("id", "");
                    String name = raw.optString("name", "");
                    if (id.isEmpty() || name.isEmpty()) continue;
                    if (CleanerRules.isBuiltin(id)) continue;
                    CleanerRules.Rule rule = new CleanerRules.Rule()
                            .id(id).name(name)
                            .group(raw.optString("group", "junk"))
                            .risk(raw.optString("risk", "safe"))
                            .source(raw.optString("source", ""))
                            .check(raw.optString("check", ""))
                            .note(raw.optString("note", ""))
                            .roots(strings(raw.optJSONArray("roots")))
                            .paths(strings(raw.optJSONArray("paths")))
                            .globs(strings(raw.optJSONArray("globs")))
                            .extensions(strings(raw.optJSONArray("extensions")))
                            .exclude(strings(raw.optJSONArray("exclude")))
                            .contents(raw.optBoolean("contents", false))
                            .defaultOn(raw.optBoolean("default", false))
                            .verified(raw.optBoolean("verified", false))
                            .minAgeDays(raw.optInt("minAgeDays", 0))
                            .maxDepth(raw.optInt("maxDepth", WALK_MAX_DEPTH))
                            .minSize(raw.optLong("minSize", 0));
                    if (rule.roots.isEmpty() && rule.paths.isEmpty() && rule.globs.isEmpty()) continue;
                    rules.add(rule);
                }
            }
            JSONArray rawNever = root.optJSONArray("never");
            if (rawNever != null) {
                for (int i = 0; i < rawNever.length(); i++) {
                    JSONObject raw = rawNever.optJSONObject(i);
                    if (raw == null) continue;
                    CleanerRules.Never entry = new CleanerRules.Never()
                            .reason(raw.optString("reason", "受保护"))
                            .paths(strings(raw.optJSONArray("paths")))
                            .globs(strings(raw.optJSONArray("globs")))
                            .except(strings(raw.optJSONArray("except")));
                    if (entry.paths.isEmpty() && entry.globs.isEmpty()) continue;
                    never.add(entry);
                }
            }
            return new CleanerRules(rules, never);
        }

        private static String[] strings(JSONArray array) {
            if (array == null) return new String[0];
            List<String> values = new ArrayList<>();
            for (int i = 0; i < array.length(); i++) {
                String value = array.optString(i, "");
                if (!value.isEmpty()) values.add(value);
            }
            return values.toArray(new String[0]);
        }
    }
}