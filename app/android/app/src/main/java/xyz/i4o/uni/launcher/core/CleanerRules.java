package xyz.i4o.uni.launcher.core;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Set;
import java.util.regex.Pattern;

/**
 * 垃圾清理规则引擎：纯 JVM，不引用 Android，可在 native-tests 里直接断言。
 *
 * <p>判定顺序固定，任何一条规则都不能绕过：
 * <ol>
 *   <li>路径本身不合法（相对路径、{@code ..}、NUL、超长）→ {@link Kind#NEVER}；</li>
 *   <li>{@code never} 白名单命中 → {@link Kind#NEVER}（用户媒体、导航离线地图、行车记录仪、OTA 包…）；</li>
 *   <li>某条规则命中且扩展名/最小体积/最小年龄都满足 → {@link Kind#RULE}；</li>
 *   <li>其余 → {@link Kind#NONE}。</li>
 * </ol>
 *
 * <p>路径统一用逻辑路径（{@code /sdcard/...}）比较，物理路径由调用方映射
 * （车机上是 {@code /storage/emulated/0}），这样规则文件与设备差异无关，
 * 测试也不需要真机。
 */
public final class CleanerRules {

    public enum Kind { NEVER, RULE, NONE }

    /** 一条判定结论。{@code ruleId} 只在 {@link Kind#RULE} 时有意义。 */
    public static final class Decision {
        public final Kind kind;
        public final String ruleId, reason;

        private Decision(Kind kind, String ruleId, String reason) {
            this.kind = kind;
            this.ruleId = ruleId;
            this.reason = reason;
        }

        public static Decision never(String reason) {
            return new Decision(Kind.NEVER, "", reason == null ? "" : reason);
        }

        public static Decision rule(String id) {
            return new Decision(Kind.RULE, id == null ? "" : id, "");
        }

        public boolean isNever() { return kind == Kind.NEVER; }
        public boolean isRule() { return kind == Kind.RULE; }

        @Override public String toString() { return kind + (ruleId.isEmpty() ? "" : ":" + ruleId) + (reason.isEmpty() ? "" : "(" + reason + ")"); }
    }

    public static final Decision NONE = new Decision(Kind.NONE, "", "");

    /** 一条清理规则。字段全部可变 + 链式 setter，规则文件解析和单测都用同一种写法。 */
    public static final class Rule {
        public String id = "", name = "", group = "junk", risk = "safe", source = "", check = "", note = "";
        /** 扫描起点（逻辑路径）。空表示不扫。 */
        public final List<String> roots = new ArrayList<>();
        /** 命中路径（前缀语义）。 */
        public final List<String> paths = new ArrayList<>();
        /** 命中路径（glob，`**` 跨段，`*` 单段）。 */
        public final List<String> globs = new ArrayList<>();
        /** 允许的扩展名（小写，不带点）。空表示不限。 */
        public final List<String> extensions = new ArrayList<>();
        /** 反向排除（前缀语义），优先级高于 paths/globs。 */
        public final List<String> exclude = new ArrayList<>();
        /** true：删目录内容保留目录本身；false：整个路径一起删。 */
        public boolean contents;
        /** 默认勾选。只有 verified 的规则才允许默认勾选，见 {@link #decisionEnabled()}. */
        public boolean defaultOn;
        /** 实车/采集确认过。false 时默认不勾，只展示。 */
        public boolean verified;
        public int minAgeDays, maxDepth = 4;
        public long minSize;

        public Rule id(String v) { id = v == null ? "" : v; return this; }
        public Rule name(String v) { name = v == null ? "" : v; return this; }
        /** 面板分组：cache / junk / leftover / large。 */
        public Rule group(String v) { group = v == null || v.isEmpty() ? "junk" : v; return this; }
        public Rule risk(String v) { risk = v == null ? "safe" : v; return this; }
        public Rule source(String v) { source = v == null ? "" : v; return this; }
        public Rule check(String v) { check = v == null ? "" : v; return this; }
        public Rule note(String v) { note = v == null ? "" : v; return this; }
        public Rule roots(String... v) { add(roots, v); return this; }
        public Rule paths(String... v) { add(paths, v); return this; }
        public Rule globs(String... v) { add(globs, v); return this; }
        public Rule extensions(String... v) {
            for (String s : v) if (s != null && !s.isEmpty()) extensions.add(s.toLowerCase(Locale.ROOT));
            return this;
        }
        public Rule exclude(String... v) { add(exclude, v); return this; }
        public Rule contents(boolean v) { contents = v; return this; }
        public Rule defaultOn(boolean v) { defaultOn = v; return this; }
        public Rule verified(boolean v) { verified = v; return this; }
        public Rule minAgeDays(int v) { minAgeDays = Math.max(0, v); return this; }
        public Rule maxDepth(int v) { maxDepth = Math.max(1, v); return this; }
        public Rule minSize(long v) { minSize = Math.max(0, v); return this; }

        /** 未确认的规则不许默认勾选：这条约束写死在引擎里，界面和解析都不能推翻。 */
        public boolean decisionEnabled() { return defaultOn && verified; }

        private static void add(List<String> target, String... values) {
            for (String v : values) if (v != null && !v.isEmpty()) target.add(v);
        }
    }

    /**
     * 白名单条目：命中即永不清。
     *
     * <p>{@code except} 是必需的例外口：例如照片目录整体受保护，但
     * {@code /sdcard/DCIM/.thumbnails} 这类缓存必须能单独清掉。例外只放宽本条白名单，
     * 不会绕过其它白名单条目，也不会让规则跳过后续校验。
     */
    public static final class Never {
        public final List<String> paths = new ArrayList<>();
        public final List<String> globs = new ArrayList<>();
        public final List<String> except = new ArrayList<>();
        public String reason = "";

        public Never reason(String v) { reason = v == null ? "" : v; return this; }
        public Never paths(String... v) { for (String s : v) if (s != null && !s.isEmpty()) paths.add(s); return this; }
        public Never globs(String... v) { for (String s : v) if (s != null && !s.isEmpty()) globs.add(s); return this; }
        public Never except(String... v) { for (String s : v) if (s != null && !s.isEmpty()) except.add(s); return this; }
    }

    /** 逻辑根：所有规则与白名单都按这个前缀书写。 */
    public static final String LOGICAL_ROOT = "/sdcard";
    /**
     * 车机上必须显式剪枝的段。`Android/data` 不在此列 —— 应用外部缓存在
     * `Android/data/&lt;pkg&gt;/cache`，必须能走进去；那里的 `files`/`databases`/`shared_prefs`
     * 由 `never` 逐目录保护，比整棵跳过更精确。
     */
    private static final String[] SKIP_SEGMENTS = {"/sdcard/Android/media"};
    private static final int MAX_PATH_LENGTH = 512;
    private static final Map<String, Pattern> GLOB_CACHE = new HashMap<>();

    private final List<Rule> rules;
    private final List<Never> never;

    public CleanerRules(List<Rule> rules, List<Never> never) {
        this.rules = rules == null ? new ArrayList<>() : new ArrayList<>(rules);
        this.never = never == null ? new ArrayList<>() : new ArrayList<>(never);
    }

    public List<Rule> rules() { return new ArrayList<>(rules); }

    public Rule rule(String id) {
        if (id == null || id.isEmpty()) return null;
        for (Rule r : rules) if (r.id.equals(id)) return r;
        return null;
    }

    /** 允许清理的 id 集合：内置三类 + 规则文件里的全部 id。 */
    public Set<String> cleanableIds() {
        Set<String> ids = new LinkedHashSet<>();
        for (String builtin : BUILTIN_IDS) ids.add(builtin);
        for (Rule r : rules) if (!r.id.isEmpty()) ids.add(r.id);
        return ids;
    }

    public static final String[] BUILTIN_IDS = {"self-cache", "app-cache", "system-cache"};

    public static boolean isBuiltin(String id) {
        for (String b : BUILTIN_IDS) if (b.equals(id)) return true;
        return false;
    }

    /** 主判定：返回**第一条**命中规则。单条规则消费的场景用它，多类目累加用 {@link #matchAll}。 */
    public Decision decide(String logicalPath, long size, long lastModifiedMs, long nowMs) {
        if (!validPath(logicalPath)) return Decision.never("invalid-path");
        String blocked = neverReason(logicalPath);
        if (blocked != null) return Decision.never(blocked);
        for (Rule r : rules) {
            if (!matchesRule(r, logicalPath)) continue;
            if (!extensionAllowed(r, logicalPath)) continue;
            if (r.minSize > 0 && size < r.minSize) continue;
            if (r.minAgeDays > 0 && lastModifiedMs > nowMs - r.minAgeDays * 86400000L) continue;
            return Decision.rule(r.id);
        }
        return NONE;
    }

    /**
     * 一次遍历喂所有规则：返回全部命中的规则 id（按规则文件顺序，即优先级）。
     *
     * <p>调用方对每个条目**取第一条 check 通过的规则**归属，这样同一个文件不会被
     * 两个类目重复计数。白名单命中直接返回空列表（调用方据此剪枝整棵子树）。
     */
    public List<String> matchAll(String logicalPath, long size, long lastModifiedMs, long nowMs) {
        if (!validPath(logicalPath) || neverReason(logicalPath) != null) return new ArrayList<>();
        List<String> ids = new ArrayList<>(4);
        for (Rule r : rules) {
            if (!matchesRule(r, logicalPath)) continue;
            if (!extensionAllowed(r, logicalPath)) continue;
            if (r.minSize > 0 && size < r.minSize) continue;
            if (r.minAgeDays > 0 && lastModifiedMs > nowMs - r.minAgeDays * 86400000L) continue;
            ids.add(r.id);
        }
        return ids;
    }

    /** 命中白名单时返回原因，否则 null。 */
    public String neverReason(String logicalPath) {
        if (!validPath(logicalPath)) return "invalid-path";
        for (Never n : never) {
            if (!matchesAny(n.paths, n.globs, logicalPath)) continue;
            if (!n.except.isEmpty() && startsWithAny(n.except, logicalPath)) continue;
            return n.reason;
        }
        return null;
    }

    /**
     * 路径合法性。相对路径、含 {@code ..} 段、含 NUL、空段、超长一律拒绝。
     * 调用方还必须在物理层面再做一次 canonical 校验，这里只是第一道闸。
     */
    public static boolean validPath(String path) {
        if (path == null || path.isEmpty() || path.length() > MAX_PATH_LENGTH) return false;
        if (path.charAt(0) != '/') return false;
        if (path.indexOf('\0') >= 0 || path.indexOf('\\') >= 0) return false;
        if (path.contains("//")) return false;
        for (String segment : path.split("/", -1)) {
            if ("..".equals(segment) || ".".equals(segment)) return false;
        }
        return true;
    }

    /**
     * 扫描剪枝：{@code /sdcard/Android/{data,media,obb}} 整体跳过。
     *
     * <p>理由与 SD Maid 的 SystemCrawler 一致：这三棵子树由存储/包管理接口负责，
     * 路径规则再进去一遍会重复统计；而且 Android 11 起第三方应用也没有权限读。
     */
    public static boolean skipSubtree(String logicalPath) {
        if (logicalPath == null) return false;
        for (String prefix : SKIP_SEGMENTS) {
            if (logicalPath.equals(prefix) || logicalPath.startsWith(prefix + "/")) return true;
        }
        return false;
    }

    /** 逻辑路径是否落在允许根内。 */
    public static boolean underRoot(String logicalPath, String logicalRoot) {
        if (logicalPath == null || logicalRoot == null || logicalRoot.isEmpty()) return false;
        if (logicalPath.equals(logicalRoot)) return true;
        String prefix = logicalRoot.endsWith("/") ? logicalRoot : logicalRoot + "/";
        return logicalPath.startsWith(prefix);
    }

    private static boolean matchesRule(Rule r, String path) {
        if (!r.exclude.isEmpty() && startsWithAny(r.exclude, path)) return false;
        if (!r.paths.isEmpty() && startsWithAny(r.paths, path)) return true;
        if (!r.globs.isEmpty() && globsMatch(r.globs, path)) return true;
        // 规则只给了 roots：整棵子树都算命中（用于「扫这个目录下的全部临时文件」）。
        return r.paths.isEmpty() && r.globs.isEmpty() && startsWithAny(r.roots, path);
    }

    private static boolean matchesAny(List<String> paths, List<String> globs, String path) {
        return startsWithAny(paths, path) || globsMatch(globs, path);
    }

    private static boolean startsWithAny(List<String> prefixes, String path) {
        for (String prefix : prefixes) {
            if (underRoot(path, prefix)) return true;
        }
        return false;
    }

    private static boolean globsMatch(List<String> globs, String path) {
        for (String glob : globs) {
            if (globMatch(glob, path)) return true;
        }
        return false;
    }

    private static boolean extensionAllowed(Rule r, String path) {
        if (r.extensions.isEmpty()) return true;
        int slash = path.lastIndexOf('/');
        int dot = path.lastIndexOf('.');
        if (dot <= slash) return false;
        return r.extensions.contains(path.substring(dot + 1).toLowerCase(Locale.ROOT));
    }

    /**
     * 简化 glob：{@code **} 匹配任意段（含 /），{@code *} 匹配单段内任意字符，
     * {@code ?} 匹配单字符，其余按字面量。大小写不敏感（车机文件系统就是这样）。
     */
    public static boolean globMatch(String pattern, String path) {
        if (pattern == null || path == null) return false;
        if (pattern.isEmpty()) return false;
        Pattern compiled = compile(pattern);
        return compiled.matcher(path).matches();
    }

    private static Pattern compile(String glob) {
        synchronized (GLOB_CACHE) {
            Pattern cached = GLOB_CACHE.get(glob);
            if (cached != null) return cached;
            StringBuilder regex = new StringBuilder("^");
            int i = 0;
            while (i < glob.length()) {
                char c = glob.charAt(i);
                if (c == '*') {
                    if (i + 1 < glob.length() && glob.charAt(i + 1) == '*') {
                        // `**/` 允许零层：`/sdcard/**/.thumbnails` 也要匹配 /sdcard/.thumbnails。
                        int after = i + 2;
                        if (after < glob.length() && glob.charAt(after) == '/') {
                            regex.append("(?:.*/)?");
                            i = after + 1;
                        } else {
                            regex.append(".*");
                            i = after;
                        }
                        continue;
                    }
                    regex.append("[^/]*");
                    i++;
                } else if (c == '?') {
                    regex.append("[^/]");
                    i++;
                } else {
                    regex.append(Pattern.quote(String.valueOf(c)));
                    i++;
                }
            }
            regex.append('$');
            Pattern compiled = Pattern.compile(regex.toString(), Pattern.CASE_INSENSITIVE);
            GLOB_CACHE.put(glob, compiled);
            return compiled;
        }
    }
}
