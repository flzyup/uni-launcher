package xyz.i4o.uni.launcher.core;

import java.util.ArrayList;
import java.util.List;

/**
 * 规则引擎的离线断言：路径合法性、glob、白名单优先、例外口、扩展名/体积/年龄、
 * 扫描剪枝。不涉及 Android，也不需要设备。
 */
public final class CleanerRulesTest {
    private static int checks;

    private static void check(boolean value, String label) {
        checks++;
        if (!value) throw new AssertionError("failed: " + label);
    }

    private static long daysAgo(int days) {
        return 1000L * 60 * 60 * 24 * 30 - 1000L * 60 * 60 * 24 * days;
    }

    private static CleanerRules sampleRules() {
        List<CleanerRules.Rule> rules = new ArrayList<>();
        rules.add(new CleanerRules.Rule()
                .id("external-cache").name("应用外部缓存").group("cache")
                .verified(true).defaultOn(true)
                .roots("/sdcard/Android/data")
                .globs("/sdcard/Android/data/*/cache", "/sdcard/Android/data/*/code_cache")
                .contents(true));
        rules.add(new CleanerRules.Rule()
                .id("thumbnails").name("缩略图缓存").verified(true).defaultOn(true)
                .roots(CleanerRules.LOGICAL_ROOT)
                .globs("/sdcard/**/.thumbnails")
                .contents(true));
        rules.add(new CleanerRules.Rule()
                .id("ad-cache").name("广告缓存").group("junk")
                .verified(true).defaultOn(false)
                .roots(CleanerRules.LOGICAL_ROOT)
                .globs("/sdcard/**/.csj/**", "/sdcard/**/.pangle/**"));
        rules.add(new CleanerRules.Rule()
                .id("log").name("日志").verified(true).defaultOn(true)
                .roots(CleanerRules.LOGICAL_ROOT)
                .globs("/sdcard/*.log", "/sdcard/**/*.log.?*")
                .paths("/sdcard/LOST.DIR")
                .minAgeDays(7));
        rules.add(new CleanerRules.Rule()
                .id("apk-leftover").name("安装包残留").group("leftover")
                .verified(true).defaultOn(false)
                .roots("/sdcard/Download")
                .globs("/sdcard/Download/**/*.apk")
                .extensions("apk")
                .minSize(1 << 20));
        rules.add(new CleanerRules.Rule()
                .id("draft").name("未确认规则").verified(false).defaultOn(true)
                .roots("/sdcard/LOST.DIR2"));
        List<CleanerRules.Never> never = new ArrayList<>();
        never.add(new CleanerRules.Never()
                .globs("/sdcard/DCIM/**")
                .except("/sdcard/DCIM/.thumbnails")
                .reason("照片"));
        never.add(new CleanerRules.Never()
                .paths("/sdcard/amapauto9")
                .reason("导航离线地图"));
        never.add(new CleanerRules.Never()
                .globs("/sdcard/*.tgz", "/sdcard/*.tar.gz", "/sdcard/sys-apks*")
                .reason("系统备份"));
        return new CleanerRules(rules, never);
    }

    public static void main(String[] args) {
        long now = 1000L * 60 * 60 * 24 * 30;

        // 路径合法性：第一道闸，任何非法路径都必须被拒。
        check(CleanerRules.validPath("/sdcard/a/b.txt"), "绝对路径");
        check(!CleanerRules.validPath("sdcard/a"), "相对路径");
        check(!CleanerRules.validPath("/sdcard/../data/data/com.x"), "上跳");
        check(!CleanerRules.validPath("/sdcard/./a"), "当前目录段");
        check(!CleanerRules.validPath("/sdcard//a"), "空段");
        check(!CleanerRules.validPath("/sdcard/a\0b"), "NUL");
        check(!CleanerRules.validPath("/sdcard/a\\b"), "反斜杠");
        check(!CleanerRules.validPath(""), "空串");
        check(!CleanerRules.validPath(null), "null");
        check(!CleanerRules.validPath("/" + "a".repeat(600)), "超长");

        // 前缀语义：/sdcard/DCIM 不能匹配 /sdcard/DCIMX。
        check(CleanerRules.underRoot("/sdcard/DCIM/a.jpg", "/sdcard/DCIM"), "子路径");
        check(CleanerRules.underRoot("/sdcard/DCIM", "/sdcard/DCIM"), "自身");
        check(!CleanerRules.underRoot("/sdcard/DCIMX/a.jpg", "/sdcard/DCIM"), "前缀误判");

        // glob：** 跨段、* 单段、? 单字符、大小写不敏感。
        check(CleanerRules.globMatch("/sdcard/**/.thumbnails", "/sdcard/DCIM/.thumbnails"), "** 一层");
        check(CleanerRules.globMatch("/sdcard/**/.thumbnails", "/sdcard/.thumbnails"), "** 零层");
        check(CleanerRules.globMatch("/sdcard/Download/**/*.apk", "/sdcard/Download/a/b/x.apk"), "深层 apk");
        check(!CleanerRules.globMatch("/sdcard/*.log", "/sdcard/sub/x.log"), "* 不跨段");
        check(CleanerRules.globMatch("/sdcard/*.log", "/sdcard/x.log"), "* 单段");
        check(CleanerRules.globMatch("/sdcard/*dvr*/**", "/sdcard/DVR/1.mp4"), "大小写不敏感");
        check(CleanerRules.globMatch("/sdcard/a?c.log", "/sdcard/abc.log"), "? 单字符");
        check(!CleanerRules.globMatch("/sdcard/a?c.log", "/sdcard/a/c.log"), "? 不跨段");

        // 扫描剪枝：只跳过应用媒体，Android/data 必须能进去（外部缓存在里面）。
        check(!CleanerRules.skipSubtree("/sdcard/Android/data/com.x/cache"), "data 不再整棵跳过");
        check(CleanerRules.skipSubtree("/sdcard/Android/media"), "剪枝 media");
        check(!CleanerRules.skipSubtree("/sdcard/Android/mediax"), "不误伤相似名");
        check(!CleanerRules.skipSubtree("/sdcard/DCIM"), "不误伤普通目录");

        CleanerRules rules = sampleRules();

        // 白名单优先 + 例外口：照片整体受保护，缩略图例外。
        check(rules.decide("/sdcard/DCIM/IMG_0001.jpg", 4096, daysAgo(400), now).isNever(), "照片受保护");
        check(rules.decide("/sdcard/DCIM/IMG_0001.jpg", 4096, daysAgo(400), now).reason.equals("照片"), "白名单原因");
        check(rules.decide("/sdcard/amapauto9/data/abc.dat", 4096, daysAgo(400), now).isNever(), "离线地图受保护");
        // 规则命中目录本身，目录内容由扫描器整体计入（contents=true）。
        CleanerRules.Decision thumbs = rules.decide("/sdcard/DCIM/.thumbnails", 0, daysAgo(400), now);
        check(thumbs.isRule() && "thumbnails".equals(thumbs.ruleId), "缩略图例外命中");
        // 例外只放开白名单，不让「目录里的文件」被别的规则顺带收走。
        CleanerRules.Decision inside = rules.decide("/sdcard/DCIM/.thumbnails/1.jpg", 2048, daysAgo(400), now);
        check(!inside.isNever() && inside.kind == CleanerRules.Kind.NONE, "例外内文件不被白名单拦住");

        // 无白名单的普通路径按规则走。
        check(rules.decide("/sdcard/Download/a.apk", 4 << 20, daysAgo(10), now).ruleId.equals("apk-leftover"), "安装包规则");
        check(rules.decide("/sdcard/Download/a.apk", 100, daysAgo(10), now).kind == CleanerRules.Kind.NONE, "小于 minSize 不清");
        check(rules.decide("/sdcard/Download/a.txt", 4 << 20, daysAgo(10), now).kind == CleanerRules.Kind.NONE, "扩展名不符");

        // 年龄门槛：7 天内不动。
        check(rules.decide("/sdcard/a.log", 100, daysAgo(1), now).kind == CleanerRules.Kind.NONE, "太新的日志");
        check(rules.decide("/sdcard/a.log", 100, daysAgo(30), now).ruleId.equals("log"), "过期日志");
        // 滚动日志（GCF_DDFW_TRACE.log.1 这类）用 ?* 收进来：glob 不支持 [0-9] 字符类。
        check(rules.decide("/sdcard/vr/log/GCF_DDFW_TRACE.log.1", 4096, daysAgo(30), now)
                .ruleId.equals("log"), "滚动日志命中");
        check(rules.decide("/sdcard/vr/log/GCF_DDFW_TRACE.log.12", 4096, daysAgo(30), now)
                .ruleId.equals("log"), "两位滚动日志命中");
        check(CleanerRules.globMatch("/sdcard/**/*.log.?*", "/sdcard/vr/log/x.log.1"), "?* 收滚动后缀");
        check(!CleanerRules.globMatch("/sdcard/**/*.log.?*", "/sdcard/vr/log/x.log."), "?* 要至少一个字符");
        // 穿山甲/优量汇这类国内广告 SDK 目录。
        check(rules.decide("/sdcard/Download/.csj/ins/a.png", 4096, daysAgo(30), now)
                .ruleId.equals("ad-cache"), "穿山甲缓存命中");
        check(rules.matchAll("/sdcard/Download/.csj/ins", 0, daysAgo(30), now)
                .contains("ad-cache"), "穿山甲目录 matchAll");
        // 系统备份与镜像：车机上 sys-apks.tgz 有几百 MB，绝不能被「大文件」顺走。
        CleanerRules.Decision tgz = rules.decide("/sdcard/sys-apks.tgz", 800 << 20, daysAgo(400), now);
        check(tgz.isNever() && tgz.reason.equals("系统备份"), "系统备份受保护");
        check(rules.decide("/sdcard/vr-speech.tgz", 180 << 20, daysAgo(400), now).isNever(), "语音包受保护");
        check(!rules.decide("/sdcard/Download/backup.tgz", 1 << 20, daysAgo(400), now).isNever(),
                "子目录里的 tgz 不误伤");

        // 未确认规则：defaultOn 但 verified=false，不允许默认勾选。
        CleanerRules.Rule draft = rules.rule("draft");
        check(draft != null && draft.defaultOn && !draft.decisionEnabled(), "未确认不默认勾");
        check(rules.rule("thumbnails").decisionEnabled(), "已确认可默认勾");

        // roots 兜底：没有 paths/globs 的规则按 roots 整棵子树命中。
        check(rules.decide("/sdcard/LOST.DIR2/x.tmp", 10, daysAgo(30), now).ruleId.equals("draft"), "roots 兜底");

        // 非法路径永远 NEVER，且原因可读。
        CleanerRules.Decision escape = rules.decide("/sdcard/../data/data/x", 10, daysAgo(30), now);
        check(escape.isNever() && escape.reason.equals("invalid-path"), "逃逸路径被拒");

        // 可清理 id 集合包含内置三类与规则 id。
        check(rules.cleanableIds().contains("self-cache"), "内置 id");
        check(rules.cleanableIds().contains("app-cache"), "内置 id 2");
        check(rules.cleanableIds().contains("system-cache"), "内置 id 3");
        check(rules.cleanableIds().contains("thumbnails"), "规则 id");
        check(CleanerRules.isBuiltin("self-cache") && !CleanerRules.isBuiltin("log"), "内置判定");

        // matchAll：一次遍历喂全部规则，返回按优先级排列的全部命中。
        List<String> externalCache = rules.matchAll(
                "/sdcard/Android/data/com.x/cache", 0, daysAgo(30), now);
        check(rules.matchAll("/sdcard/Android/data/com.x/cache", 0, daysAgo(30), now)
                .contains("external-cache"), "外部缓存命中");
        // 父目录命中后由扫描器整棵接管（contents），子路径不再单独命中，避免重复计数。
        check(rules.matchAll("/sdcard/Android/data/com.x/cachex", 0, daysAgo(30), now)
                .isEmpty(), "相似目录名不命中");
        check(rules.matchAll("/sdcard/Android/data/com.x/files/a.bin",
                10, daysAgo(30), now).isEmpty(), "应用 files 目录不命中任何规则");
        check(rules.matchAll("/sdcard/DCIM/a.jpg", 10, daysAgo(30), now).isEmpty(),
                "白名单路径 matchAll 返回空");
        List<String> apkHits = rules.matchAll("/sdcard/Download/a.apk",
                4 << 20, daysAgo(30), now);
        check(apkHits.contains("apk-leftover"), "安装包命中");
        check(rules.matchAll("/sdcard/../etc/passwd", 10, daysAgo(30), now).isEmpty(),
                "逃逸路径 matchAll 返回空");

        System.out.println("CleanerRulesTest passed (" + checks + " checks)");
    }
}
