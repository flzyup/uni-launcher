package xyz.i4o.uni.launcher.core;

import java.util.HashMap;
import java.util.Map;

/**
 * 「收藏 / 播放模式」这两件事的协议抽象层（移植自 CarDesk 的同名实现）。
 *
 * <h3>要解决的问题</h3>
 *
 * 桌面要在音乐卡上加：
 * <ul>
 *   <li><b>收藏按钮</b>（并同步歌曲的收藏状态）；</li>
 *   <li><b>随机播放 / 顺序播放</b>切换。</li>
 * </ul>
 *
 * 桌面是<b>第三方</b>，不是这些播放器的车机 partner —— 每家暴露的通道都不一样：
 *
 * <table>
 *   <tr><th>播放器</th><th>收藏</th><th>播放模式</th><th>通道</th></tr>
 *   <tr><td>QQ 音乐车机版</td><td>是</td><td>是</td><td>第三方 URI 协议（{@code qqmusiccar://?action=20&amp;m0=…}）</td></tr>
 *   <tr><td>网易云车机版</td><td>是</td><td>是</td><td><b>标准 MediaSession</b>（{@code sendCustomAction}）</td></tr>
 *   <tr><td>汽水音乐车机版</td><td>是</td><td>否</td><td><b>标准 MediaSession</b>（{@code setRating} → 心形评分）</td></tr>
 *   <tr><td>其它播放器</td><td>探测</td><td>探测</td><td><b>通用兜底</b>：标准 MediaSession 通道 + 运行时探测</td></tr>
 * </table>
 *
 * → 所以桌面这一侧不能写死某一家，要<b>按包名分发</b>（已知包走专用通道，未知包走通用兜底）。
 *
 * <h3>为什么网易云走「标准 API」而不是私有 JSK</h3>
 *
 * 网易云的私有通道（{@code IIotServer} / {@code ServiceFacade}）是<b>进程内</b>的静态 Map，
 * 第三方根本接不上。真正能用的是它 MediaSession 回调里的两个标准入口：
 *
 * <pre>
 * onSetRating(RatingCompat rating)  → is_star  → 收藏 / 取消收藏
 * onCustomAction(String action, Bundle extras) → play_mode_action → 切播放模式
 * </pre>
 *
 * → 也就是说网易云<b>把收藏和播放模式挂在了标准会话回调上</b>，
 * 第三方拿 {@code MediaController} 就能读写，不需要碰它的私有通道。
 *
 * <h3>为什么单独抽一个类</h3>
 *
 * 三件事揉在 UI 层会变成一大坨不可测的 if：
 * <ol>
 *   <li>状态模型（收藏态 / 播放模式是什么）；</li>
 *   <li>「这个播放器支持吗」的判定；</li>
 *   <li>真的下发指令。</li>
 * </ol>
 *
 * ①② 是<b>纯逻辑</b>（可在 JVM 单测里覆盖），③ 才碰 Android。
 * 所以本类只放 ①②，③ 放到 {@code MediaActionBridge} 这个执行层里。
 *
 * <h3>收藏态为什么要分「三态」</h3>
 *
 * 不是「已收藏 / 未收藏」两态，而是<b>三态</b>：已收藏 / 未收藏 / 不知道。
 *
 * 「不知道」必须单独一种：QQ 音乐只在 {@code update_song} 那类广播里带 {@code key_is_fav}，
 * {@code update_state}（只有播放态）里没有 → 那时若当成「未收藏」，
 * 界面会在每次播放态更新时闪一下「未收藏」—— <b>用户看着像收藏状态丢了</b>。
 */
public final class MediaActions {
    private MediaActions() {}

    // ---------------------------------------------------------------- 包名

    /** QQ 音乐车机版：第三方 URI 协议。 */
    public static final String QQ_PACKAGE = "com.tencent.qqmusiccar";

    /** 网易云车机版：标准 MediaSession 的 onCustomAction / onSetRating。 */
    public static final String NETEASE_PACKAGE = "com.netease.cloudmusic.iot";

    /** 汽水音乐车机版：收藏走标准评分通道，播放模式没有对外通道。 */
    public static final String SODA_PACKAGE = "com.luna.music.car";

    // ---------------------------------------------------------------- 收藏态

    /**
     * 收藏态。
     *
     * @param favorited true = 已收藏；false = 未收藏；<b>null = 不知道</b>
     */
    public static final class FavoriteState {
        /** null 表示「不知道」。 */
        public final Boolean favorited;

        public FavoriteState(Boolean favorited) { this.favorited = favorited; }

        /** 状态已知吗。 */
        public boolean known() { return favorited != null; }

        /** 是否已收藏（状态未知时返回 false，<b>别拿它当状态用</b>，先看 {@link #known()}）。 */
        public boolean isFavorited() { return Boolean.TRUE.equals(favorited); }

        @Override public boolean equals(Object other) {
            if (this == other) return true;
            if (!(other instanceof FavoriteState)) return false;
            FavoriteState that = (FavoriteState) other;
            return favorited == null ? that.favorited == null : favorited.equals(that.favorited);
        }

        @Override public int hashCode() { return favorited == null ? 0 : favorited.hashCode(); }

        @Override public String toString() { return favorited == null ? "unknown" : String.valueOf(favorited); }

        /** 不知道（播放器没报，或这条广播里没这个字段）。 */
        public static final FavoriteState UNKNOWN = new FavoriteState(null);
        /** 已收藏。 */
        public static final FavoriteState FAVORITED = new FavoriteState(Boolean.TRUE);
        /** 未收藏。 */
        public static final FavoriteState NOT_FAVORITED = new FavoriteState(Boolean.FALSE);
    }

    // ---------------------------------------------------------------- 播放模式

    /**
     * 三种播放模式。
     *
     * 顺序播放 → 单曲循环 → 随机播放 → 顺序播放（循环切换）。
     *
     * 命名与 Android {@code PlaybackState} 的 {@code setRepeatMode} /
     * {@code setShuffleMode} 的语义对齐。
     */
    public enum PlayMode {
        /** 顺序播放（列表循环）。 */
        REPEAT_ALL,
        /** 单曲循环。 */
        REPEAT_ONE,
        /** 随机播放。 */
        SHUFFLE;

        /** 稳定的线缆名（跨 Dart / Java 传递用）。 */
        public String wire() { return name(); }

        /** 从线缆名解析；不认识返回 null。 */
        public static PlayMode fromWire(String value) {
            if (value == null) return null;
            for (PlayMode mode : values()) if (mode.name().equals(value)) return mode;
            return null;
        }
    }

    /**
     * 播放模式状态。
     *
     * @param mode 当前模式；<b>null = 不知道</b>
     */
    public static final class PlayModeState {
        public final PlayMode mode;

        public PlayModeState(PlayMode mode) { this.mode = mode; }

        /** 状态已知吗。 */
        public boolean known() { return mode != null; }

        @Override public boolean equals(Object other) {
            if (this == other) return true;
            if (!(other instanceof PlayModeState)) return false;
            return mode == ((PlayModeState) other).mode;
        }

        @Override public int hashCode() { return mode == null ? 0 : mode.hashCode(); }

        @Override public String toString() { return mode == null ? "unknown" : mode.name(); }

        /** 不知道。 */
        public static final PlayModeState UNKNOWN = new PlayModeState(null);
    }

    // ---------------------------------------------------------------- 能力判定

    /**
     * 一个播放器支持哪些动作。
     *
     * @param favorite 支不支持收藏
     * @param playMode 支不支持切播放模式
     */
    public static final class Caps {
        public final boolean favorite, playMode;

        public Caps(boolean favorite, boolean playMode) {
            this.favorite = favorite;
            this.playMode = playMode;
        }

        @Override public boolean equals(Object other) {
            if (this == other) return true;
            if (!(other instanceof Caps)) return false;
            Caps that = (Caps) other;
            return favorite == that.favorite && playMode == that.playMode;
        }

        @Override public int hashCode() { return (favorite ? 2 : 0) + (playMode ? 1 : 0); }

        /** 什么都不支持。 */
        public static final Caps NONE = new Caps(false, false);
        /** 都支持。 */
        public static final Caps ALL = new Caps(true, true);
    }

    /**
     * <b>运行时探测</b>到的会话事实。
     *
     * <p>能力表只覆盖逆向过的几个播放器。桌面上还有一堆别的音乐 App，
     * 它们各有各的私有协议，桌面不可能一家一家逆 → 只能靠<b>标准 MediaSession 通道</b>兜底。
     *
     * <p>但<b>不能无脑乱发</b>：亮一个「点了没反应」的按钮比没有更糟。
     * → 所以先看这个会话<b>自己发布的事实</b>，再决定亮不亮。
     *
     * <table>
     *   <tr><th>能力</th><th>判据</th></tr>
     *   <tr><td>收藏</td><td>会话 metadata 里<b>有</b>心形评分（{@code METADATA_KEY_USER_RATING}）</td></tr>
     *   <tr><td>播放模式</td><td>会话 {@code PlaybackState} 的 {@code repeatMode} / {@code shuffleMode} <b>被设置过</b></td></tr>
     * </table>
     *
     * @param favoriteHeart metadata 里心形评分读出来的值；<b>null = 没有心形评分项</b>
     * @param repeatMode {@code PlaybackState.getRepeatMode()}
     * @param shuffleMode {@code PlaybackState.getShuffleMode()}
     */
    public static final class Probe {
        public final Boolean favoriteHeart;
        public final int repeatMode, shuffleMode;

        public Probe(Boolean favoriteHeart, int repeatMode, int shuffleMode) {
            this.favoriteHeart = favoriteHeart;
            this.repeatMode = repeatMode;
            this.shuffleMode = shuffleMode;
        }

        /** 什么事实都没探到（没有会话 / 没有元数据）。 */
        public static final Probe EMPTY = new Probe(null, RepeatMode.NONE, ShuffleMode.NONE);
    }

    /**
     * {@code PlaybackState} 的<b>重复模式</b>取值（与 Android framework 同口径）。
     *
     * <p>{@code REPEAT_MODE_UNSET} 是 API 29 才加的，而本工程跑在 API 28 的车机上 →
     * 直接引用 framework 常量在低版本上拿不到「未设置」这个态。
     * → 自己定义一份（值与 framework 完全一致），纯 Java、可单测。
     */
    public static final class RepeatMode {
        /** 不重复（播完一遍就停）。 */
        public static final int NONE = 0;
        /** 单曲循环。 */
        public static final int ONE = 1;
        /** 列表循环（顺序播放）。 */
        public static final int ALL = 2;
        /** 未设置（API 29+ 才有这个值；低版本用 {@link #NONE}）。 */
        public static final int UNSET = -1;

        private RepeatMode() {}
    }

    /**
     * {@code PlaybackState} 的<b>随机模式</b>取值（与 Android framework 同口径）。
     */
    public static final class ShuffleMode {
        /** 不随机。 */
        public static final int NONE = 0;
        /** 随机播放。 */
        public static final int ALL = 1;
        /** 未设置（API 29+ 才有这个值；低版本用 {@link #NONE}）。 */
        public static final int UNSET = -1;

        private ShuffleMode() {}
    }

    /**
     * 这个会话<b>有没有暴露</b>播放模式（能力探测用，纯逻辑，可单测）。
     *
     * <p>「设置过」= {@code repeatMode} 或 {@code shuffleMode} <b>不是 NONE</b>。
     *
     * <p>不能用 {@code != UNSET} 判定：{@code REPEAT_MODE_UNSET}（-1）是 API 29 才有的，
     * API 28 的 framework 里 {@code PlaybackState} 的默认值是 <b>NONE（0）</b> →
     * 用 {@code != UNSET} 判的话，API 28 上<b>每个会话都会「暴露」播放模式</b> → 按钮到处乱亮。
     *
     * → 统一按「<b>大于 0</b>」判定：只有 ONE / ALL / SHUFFLE_ALL 才算数。
     */
    public static boolean exposesPlayMode(int repeatMode, int shuffleMode) {
        return repeatMode > RepeatMode.NONE || shuffleMode > ShuffleMode.NONE;
    }

    /**
     * 从会话的 {@code PlaybackState} 模式字段读<b>播放模式</b>（纯逻辑，可单测）。
     *
     * <ul>
     *   <li>{@code shuffleMode == ALL} → <b>随机播放</b>（随机优先于重复）；</li>
     *   <li>{@code repeatMode == ONE} → <b>单曲循环</b>；</li>
     *   <li>{@code repeatMode == ALL} → <b>顺序播放</b>；</li>
     *   <li>其余 → <b>不知道</b>（null）。</li>
     * </ul>
     */
    public static PlayMode playModeFromState(int repeatMode, int shuffleMode) {
        if (shuffleMode == ShuffleMode.ALL) return PlayMode.SHUFFLE;
        if (repeatMode == RepeatMode.ONE) return PlayMode.REPEAT_ONE;
        if (repeatMode == RepeatMode.ALL) return PlayMode.REPEAT_ALL;
        return null;
    }

    /**
     * 各播放器的动作能力表（<b>按包名</b>）。
     *
     * <p>表里没有的包 → 走 {@link #capsOf} 的<b>运行时探测</b>（通用兜底）。
     */
    private static final Map<String, Caps> CAPS = new HashMap<String, Caps>();

    static {
        // QQ 音乐车机版：第三方 URI 协议。
        CAPS.put(QQ_PACKAGE, new Caps(true, true));
        // 网易云车机版：标准 MediaSession —— onSetRating（心形评分 → 收藏）
        // 与 onCustomAction（"play_mode_action" → 播放模式）。
        CAPS.put(NETEASE_PACKAGE, new Caps(true, true));
        // 汽水音乐车机版：收藏走标准评分通道（onSetRating → handleCollectOrUnCollectCommand），
        // 播放模式只在它进程内的指令中心里，第三方接不上 → 按钮隐藏。
        CAPS.put(SODA_PACKAGE, new Caps(true, false));
    }

    /**
     * 这个包支持哪些动作。
     *
     * <h3>两级判定</h3>
     * <ol>
     *   <li><b>能力表里有的包</b> → 直接查表（专用通道，逆向验证过的）；</li>
     *   <li><b>表里没有的包</b> → 看 {@code probe}（运行时探测，通用兜底）：
     *     <ul>
     *       <li>会话发了<b>心形评分</b> → 说明它用标准收藏语义 → 亮收藏按钮；</li>
     *       <li>会话<b>暴露了</b>播放模式字段 → 说明它用标准模式语义 → 亮播放模式按钮；</li>
     *       <li>探测不到 → <b>什么都不亮</b>（不猜：猜错了会亮一个点了没反应的按钮）。</li>
     *     </ul>
     * </li>
     * </ol>
     *
     * @param packageName 播放器包名
     * @param probe 运行时探测到的事实（null = 没探到 → 兜底一律不支持）
     */
    public static Caps capsOf(String packageName, Probe probe) {
        String pkg = packageName == null ? "" : packageName.trim();
        if (pkg.isEmpty()) return Caps.NONE;
        Caps known = CAPS.get(pkg);
        if (known != null) return known;
        if (probe == null) return Caps.NONE;
        return new Caps(probe.favoriteHeart != null,
                exposesPlayMode(probe.repeatMode, probe.shuffleMode));
    }

    /** 这个包支不支持收藏。 */
    public static boolean supportsFavorite(String packageName, Probe probe) {
        return capsOf(packageName, probe).favorite;
    }

    /** 这个包支不支持切播放模式。 */
    public static boolean supportsPlayMode(String packageName, Probe probe) {
        return capsOf(packageName, probe).playMode;
    }

    // ---------------------------------------------------------------- 播放模式循环

    /**
     * 点一下「播放模式」按钮后的<b>下一个模式</b>（纯逻辑，可单测）。
     *
     * <p>顺序：顺序播放 → 单曲循环 → 随机播放 → 顺序播放。
     *
     * <p>未知 → 先给<b>顺序播放</b>（最保守的那个）。
     * 理由：随机播放会让用户「下一首听到的歌跟预期不一样」，
     * 在不知道当前状态时先落到最不容易出意外的档位。
     *
     * @param current 当前模式；null = 不知道
     * @return 下一个模式
     */
    public static PlayMode nextPlayMode(PlayMode current) {
        if (current == PlayMode.REPEAT_ALL) return PlayMode.REPEAT_ONE;
        if (current == PlayMode.REPEAT_ONE) return PlayMode.SHUFFLE;
        if (current == PlayMode.SHUFFLE) return PlayMode.REPEAT_ALL;
        return PlayMode.REPEAT_ALL;
    }

    // ---------------------------------------------------------------- 收藏态合并

    /**
     * 收到一条播放器广播后，<b>更新</b>收藏态（纯逻辑，可单测）。
     *
     * <p>为什么「未知」不覆盖已知：QQ 音乐的 {@code update_state} 广播里<b>没有</b>
     * {@code key_is_fav} → 如果直接覆盖，已知的「已收藏」会被冲成「不知道」→ 按钮闪一下。
     *
     * → <b>只有确实带了这个字段的新值，才更新</b>。
     *
     * @param current 当前状态
     * @param incoming 新广播里的收藏态（null = 这条广播没带）
     * @return 合并后的状态
     */
    public static FavoriteState mergeFavorite(FavoriteState current, FavoriteState incoming) {
        if (incoming == null || !incoming.known()) return current;
        return incoming;
    }

    /**
     * 把 QQ 音乐广播里的 {@code key_is_fav} 读成收藏态（纯逻辑，可单测）。
     *
     * @param favorite {@code key_is_fav} 的值；<b>-1 = 这条广播里没有</b>
     * @return 对应的收藏态（-1 → 未知）
     */
    public static FavoriteState favoriteFromRaw(int favorite) {
        if (favorite < 0) return FavoriteState.UNKNOWN;
        if (favorite == 1) return FavoriteState.FAVORITED;
        return FavoriteState.NOT_FAVORITED;
    }

    // ---------------------------------------------------------------- 网易云编码

    /**
     * 网易云车机版的播放模式编码（<b>车机侧口径</b>）。
     *
     * <p>网易云<b>内部</b>的播放模式是 0 / 1 / 2（顺序 / 单曲 / 随机），
     * 但它给车机侧用的是另一套编号。
     *
     * <table>
     *   <tr><th>车机编码</th><th>含义</th></tr>
     *   <tr><td>1</td><td>顺序播放（列表循环）</td></tr>
     *   <tr><td>2</td><td>随机播放</td></tr>
     *   <tr><td>3</td><td>单曲循环</td></tr>
     * </table>
     */
    public static final class NeteasePlayMode {
        public static final int REPEAT_ALL = 1;
        public static final int SHUFFLE = 2;
        public static final int REPEAT_ONE = 3;

        private NeteasePlayMode() {}
    }

    /** 播放模式 → 网易云的车机编码（纯逻辑，可单测）。 */
    public static int neteasePlayModeCode(PlayMode mode) {
        if (mode == PlayMode.SHUFFLE) return NeteasePlayMode.SHUFFLE;
        if (mode == PlayMode.REPEAT_ONE) return NeteasePlayMode.REPEAT_ONE;
        return NeteasePlayMode.REPEAT_ALL;
    }

    /**
     * 网易云的车机编码 → 播放模式（纯逻辑，可单测）。
     *
     * @return 对应的模式；<b>不认识就返回 null</b>（当「不知道」处理，别瞎猜）
     */
    public static PlayMode playModeFromNeteaseCode(int code) {
        if (code == NeteasePlayMode.REPEAT_ALL) return PlayMode.REPEAT_ALL;
        if (code == NeteasePlayMode.SHUFFLE) return PlayMode.SHUFFLE;
        if (code == NeteasePlayMode.REPEAT_ONE) return PlayMode.REPEAT_ONE;
        return null;
    }

    // ---------------------------------------------------------------- 收藏结果

    /**
     * 播放器回报的「收藏指令执行结果」码。
     *
     * <p>网易云处理完 {@code star_action} 会回一条同名 session event，
     * bundle 里是 {@code code} + {@code message}。
     */
    public static final class FavoriteResult {
        /** 操作成功（收藏 / 取消收藏生效）。 */
        public static final int OK = 0;
        /** 状态<b>本来就是</b>这样（幂等空操作，没有真正改）。 */
        public static final int ALREADY = -2;
        /** 失败。 */
        public static final int FAILED = -1;

        private FavoriteResult() {}
    }

    /**
     * 播放器的收藏结果 → <b>校正后</b>的收藏态（纯逻辑，可单测）。
     *
     * <p>为什么 0 和 -2 都算「成功」：{@code -2}（已经是该状态）虽然<b>没有真的改</b>，
     * 但它明确告诉了桌面「<b>当前状态就是你要的那个</b>」→
     * 桌面据此把状态校正过来，界面才不会一直停在旧状态。
     *
     * @param code 播放器回报的结果码
     * @param target 桌面<b>请求</b>的目标状态（true = 收藏）
     * @return 校正后的收藏态；<b>null = 失败了</b>，调用方要回滚
     */
    public static FavoriteState favoriteStateFromResult(int code, boolean target) {
        if (code == FavoriteResult.OK || code == FavoriteResult.ALREADY) {
            return target ? FavoriteState.FAVORITED : FavoriteState.NOT_FAVORITED;
        }
        return null;
    }

    // ---------------------------------------------------------------- 通用编码

    /**
     * <b>通用</b>播放模式编码（顺序=1 / 单曲=2 / 随机=3）。
     *
     * <p>{@code sendCustomAction} <b>没有</b>官方约定的参数格式，
     * 但桌面需要一套自己的口径发给「走标准通道」的播放器 →
     * 这里定一套<b>自定的通用编码</b>。
     *
     * <p>注意它和 {@link NeteasePlayMode} <b>不是</b>同一个编号
     * （网易云是 1=顺序 / 2=随机 / 3=单曲）→ 别混用。
     */
    public static final class GenericPlayMode {
        public static final int REPEAT_ALL = 1;
        public static final int REPEAT_ONE = 2;
        public static final int SHUFFLE = 3;

        private GenericPlayMode() {}
    }

    /** <b>通用</b>播放模式编码（纯逻辑，可单测）。 */
    public static int genericPlayModeCode(PlayMode mode) {
        if (mode == PlayMode.REPEAT_ONE) return GenericPlayMode.REPEAT_ONE;
        if (mode == PlayMode.SHUFFLE) return GenericPlayMode.SHUFFLE;
        return GenericPlayMode.REPEAT_ALL;
    }

    /**
     * 模式 → Android 标准<b>重复模式</b>（{@code PlaybackState.REPEAT_MODE_*}，纯逻辑，可单测）。
     *
     * <p>顺序 → ALL(2)，单曲 → ONE(1)，随机 → NONE(0)（随机靠 shuffle 字段表达）。
     */
    public static int androidRepeatMode(PlayMode mode) {
        if (mode == PlayMode.REPEAT_ALL) return RepeatMode.ALL;
        if (mode == PlayMode.REPEAT_ONE) return RepeatMode.ONE;
        return RepeatMode.NONE;
    }

    /**
     * 模式 → Android 标准<b>随机模式</b>（{@code PlaybackState.SHUFFLE_MODE_*}，纯逻辑，可单测）。
     *
     * <p>随机 → ALL(1)，其余 → NONE(0)。
     */
    public static int androidShuffleMode(PlayMode mode) {
        return mode == PlayMode.SHUFFLE ? ShuffleMode.ALL : ShuffleMode.NONE;
    }
}
