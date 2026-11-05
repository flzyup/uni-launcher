package xyz.i4o.uni.launcher.log;

import java.util.ArrayDeque;
import java.util.ArrayList;
import java.util.Deque;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

/**
 * 锚点账本：记录关键功能节点被触发了多少次、最近走了哪几步。
 *
 * <h3>为什么需要它</h3>
 * 锚点散落在几十个文件里，光有日志行还不够 —— 出问题时要看的是
 * 「这条链路走到哪一步就断了」和「哪个节点一次都没触发过」。
 * 这里把锚点按 {@code 节点/阶段} 计数，并保留最近若干条，
 * 导出诊断包时就能直接给出结论，而不是让人去翻几百行日志。
 *
 * <h3>内存开销</h3>
 * 计数表按节点去重（正常几十条），最近锚点环形缓冲固定 {@link #RECENT_LIMIT} 条，
 * 不会随运行时间增长。
 */
public final class AnchorLedger {
    /** 最近锚点的保留条数。 */
    static final int RECENT_LIMIT = 200;

    private static final Object LOCK = new Object();
    /** 节点键 → 阶段 → 次数。 */
    private static final Map<String, Map<String, Integer>> COUNTS = new LinkedHashMap<>();
    /** 最近锚点（新的在前）。 */
    private static final Deque<String> RECENT = new ArrayDeque<>(RECENT_LIMIT);

    private AnchorLedger() {}

    /** 记录一次锚点。 */
    static void record(String tag, String node, String stage, String rendered) {
        synchronized (LOCK) {
            String key = tag + " " + node;
            Map<String, Integer> stages = COUNTS.get(key);
            if (stages == null) {
                stages = new LinkedHashMap<>();
                COUNTS.put(key, stages);
            }
            Integer count = stages.get(stage);
            stages.put(stage, count == null ? 1 : count + 1);
            RECENT.addFirst(rendered);
            while (RECENT.size() > RECENT_LIMIT) RECENT.removeLast();
        }
    }

    /** 清空账本（清日志时一起清，免得诊断包里的数字对不上日志文件）。 */
    static void reset() {
        synchronized (LOCK) {
            COUNTS.clear();
            RECENT.clear();
        }
    }

    /** 锚点统计（诊断包 summary.txt 用）。 */
    public static String describe() {
        synchronized (LOCK) {
            if (COUNTS.isEmpty()) return "(本次运行没有记录锚点)\n";
            StringBuilder sb = new StringBuilder();
            for (Map.Entry<String, Map<String, Integer>> entry : COUNTS.entrySet()) {
                sb.append(entry.getKey()).append('\n');
                for (Map.Entry<String, Integer> stage : entry.getValue().entrySet()) {
                    sb.append("    ").append(stage.getKey()).append('=').append(stage.getValue()).append('\n');
                }
            }
            return sb.toString();
        }
    }

    /** 最近若干条锚点（诊断包 summary.txt 用）。 */
    public static String recent(int limit) {
        synchronized (LOCK) {
            if (RECENT.isEmpty()) return "(本次运行没有记录锚点)\n";
            StringBuilder sb = new StringBuilder();
            int count = 0;
            for (String line : RECENT) {
                if (count++ >= limit) break;
                sb.append(line).append('\n');
            }
            return sb.toString();
        }
    }

    /** 锚点节点数（诊断包里给个概览）。 */
    public static int nodeCount() {
        synchronized (LOCK) {
            return COUNTS.size();
        }
    }

    /** 供测试与调试使用：当前计数快照。 */
    static Map<String, Map<String, Integer>> snapshot() {
        synchronized (LOCK) {
            return new LinkedHashMap<>(COUNTS);
        }
    }

    /** 供测试与调试使用：最近锚点列表。 */
    static List<String> recentLines() {
        synchronized (LOCK) {
            return new ArrayList<>(RECENT);
        }
    }
}
