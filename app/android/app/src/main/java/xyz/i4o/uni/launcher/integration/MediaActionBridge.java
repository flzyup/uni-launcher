package xyz.i4o.uni.launcher.integration;

import android.content.Context;
import android.media.MediaMetadata;
import android.media.Rating;
import android.media.session.MediaController;
import android.media.session.PlaybackState;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import org.json.JSONObject;
import xyz.i4o.uni.launcher.core.MediaActions;
import xyz.i4o.uni.launcher.core.SessionProxy;
import xyz.i4o.uni.launcher.log.LogTags;
import xyz.i4o.uni.launcher.log.UniLog;

/**
 * 「收藏 / 播放模式」的<b>执行层</b>（移植自 CarDesk 的 MediaActionsDispatcher +
 * MusicController 的相关部分）。
 *
 * <h3>分发规则（三层）</h3>
 *
 * <table>
 *   <tr><th>层</th><th>包</th><th>收藏</th><th>播放模式</th></tr>
 *   <tr><td>① 专用通道</td><td>QQ 音乐车机版</td><td>URI 协议 {@code m0=5/6}</td><td>URI 协议 {@code m0=101/103/105}</td></tr>
 *   <tr><td>① 专用通道</td><td>网易云车机版</td><td>标准会话 {@code star_action}</td><td>标准会话 {@code play_mode_action}</td></tr>
 *   <tr><td>② 标准兜底</td><td>汽水音乐车机版</td><td>标准评分 {@code setRating(心形)}</td><td>——（它没有对外通道）</td></tr>
 *   <tr><td>② 标准兜底</td><td><b>其它任何播放器</b></td><td>标准评分 {@code setRating(心形)}</td><td>标准会话 {@code SET_PLAY_MODE}</td></tr>
 * </table>
 *
 * <p><b>但不是无脑乱发</b> —— 能不能亮按钮由<b>运行时探测</b>决定
 * （见 {@link MediaActions#capsOf}）：探不到就隐藏，探到了才下发。
 *
 * <h3>乐观更新为什么要「延后」</h3>
 *
 * 收藏按钮是<b>实心/空心</b>的心形 —— 立即乐观更新的话，界面会先跳成实心，
 * 几十毫秒后又被播放器的权威回报纠正回来 → <b>肉眼看到一次闪烁</b>（看着像按钮抽风）。
 *
 * <p>→ 改成<b>延后乐观</b>：下发后先等播放器回报；回报到了就用回报值；
 * 一直没人回报（比如 QQ 音乐不回报），{@link #OPTIMISTIC_FAVORITE_MS} 之后才落乐观值。
 *
 * <p>播放模式那边没有这个问题（图标是 repeat / repeat_one / shuffle，闪一下不明显，
 * 而且 QQ 根本不回报模式 → 必须立即乐观），所以它不走这条路。
 *
 * <p>下发失败<b>不抛异常</b>，只记日志并返回 false —— 音乐卡上的按钮点不动不该让桌面崩掉。
 */
public final class MediaActionBridge {
    /**
     * 「没人回报」时的乐观落盘兜底时间。
     *
     * <p>网易云的回报是重发的 metadata（{@code setRating} 之后），也就百来毫秒；
     * 这个间隔只是<b>兜底</b>（万一某个播放器不回报），不是等待时间。
     */
    public static final long OPTIMISTIC_FAVORITE_MS = 600L;

    /** 网易云：收藏 / 取消收藏的动作名。 */
    public static final String NETEASE_ACTION_STAR = "star_action";
    /** 网易云：切播放模式的动作名。 */
    public static final String NETEASE_ACTION_PLAY_MODE = "play_mode_action";
    /** 网易云：读当前播放模式的动作名。 */
    public static final String NETEASE_ACTION_GET_PLAY_MODE = "get_play_mode_action";
    /** 网易云：收藏与否（{@code is_star} = true 表示收藏）。 */
    public static final String NETEASE_EXTRA_IS_STAR = "is_star";
    /** 网易云：播放模式编码（1 / 2 / 3）。 */
    public static final String NETEASE_EXTRA_PLAY_MODE = "play_mode";

    /** 标准通道：切播放模式的自定义动作名。 */
    public static final String ACTION_SET_PLAY_MODE = "xyz.i4o.uni.launcher.action.SET_PLAY_MODE";
    /** 标准通道：通用播放模式编码。 */
    public static final String EXTRA_PLAY_MODE = "play_mode";
    /** 标准通道：Android 标准重复模式。 */
    public static final String EXTRA_REPEAT_MODE = "repeat_mode";
    /** 标准通道：Android 标准随机模式。 */
    public static final String EXTRA_SHUFFLE_MODE = "shuffle_mode";

    private final Context context;
    private final Runnable changed;
    private final Handler handler = new Handler(Looper.getMainLooper());

    private MediaController controller;
    /** 只跟着当前会话走的专属回调（不共用 MediaAdapter 那个「所有会话共用」的回调）。 */
    private MediaController.Callback controllerCallback;
    private MediaActions.FavoriteState favoriteState = MediaActions.FavoriteState.UNKNOWN;
    private MediaActions.PlayModeState playModeState = MediaActions.PlayModeState.UNKNOWN;

    /** 挂起中的乐观收藏更新。 */
    private Runnable pendingFavorite;
    /** 下一次收藏指令的目标状态（true = 收藏）。 */
    private Boolean lastFavoriteTarget;
    /** 下发收藏指令<b>之前</b>的状态（失败要回滚到它）。 */
    private MediaActions.FavoriteState favoriteStateBeforeSend;

    public MediaActionBridge(Context context, Runnable changed) {
        this.context = context == null ? null : context.getApplicationContext();
        this.changed = changed;
    }

    // ---------------------------------------------------------------- 状态

    /** 当前收藏态（三态）。 */
    public MediaActions.FavoriteState favoriteState() { return favoriteState; }

    /** 当前播放模式。 */
    public MediaActions.PlayModeState playModeState() { return playModeState; }

    /** 当前播放器的包名（null = 没有会话）。 */
    public String sourcePackage() {
        return controller == null ? null : controller.getPackageName();
    }

    /**
     * 当前播放器的<b>能力</b>（能不能亮收藏 / 播放模式按钮）。
     *
     * <p>已知包查表；未知包看运行时探测。
     */
    public MediaActions.Caps caps() {
        return MediaActions.capsOf(sourcePackage(), probe());
    }

    /**
     * 运行时探测到的会话事实（纯逻辑，可单测）。
     *
     * @return 探测结果；没有会话返回 null
     */
    public MediaActions.Probe probe() {
        if (controller == null) return null;
        MediaMetadata metadata = null;
        PlaybackState state = null;
        try {
            metadata = controller.getMetadata();
            state = controller.getPlaybackState();
        } catch (RuntimeException unavailableSession) {
            return null;
        }
        return new MediaActions.Probe(favoriteHeart(metadata),
                repeatModeOf(state), shuffleModeOf(state));
    }

    // ---------------------------------------------------------------- 会话接线

    /**
     * 绑定 / 换绑当前会话。
     *
     * <p>换绑 → 收藏态复位成「<b>不知道</b>」（新歌的收藏态由播放器重发 metadata 带来）；
     * 播放模式是<b>播放器级</b>的（不是歌曲级）→ 换绑不清它。
     */
    public void setController(MediaController next) {
        if (sameSession(controller, next)) return;
        unregisterController();
        controller = next;
        cancelPendingFavorite();
        favoriteStateBeforeSend = null;
        lastFavoriteTarget = null;
        setFavoriteState(MediaActions.FavoriteState.UNKNOWN);
        if (next != null) {
            try {
                registerController(next);
                readMetadata(next.getMetadata());
                readPlaybackState(next.getPlaybackState());
            } catch (RuntimeException unavailableSession) {
                // The session vanished between selection and reading: keep the unknown state.
            }
            requestPlayMode();
        }
    }

    /**
     * 是不是同一个会话。
     *
     * <p>比对象引用可靠：会话列表刷新时 framework 可能给出**新的** {@code MediaController}
     * 实例，但它包装的仍是同一个 token → 换绑时不该把收藏态重置掉。
     */
    private static boolean sameSession(MediaController a, MediaController b) {
        if (a == b) return true;
        if (a == null || b == null) return false;
        try {
            return a.getSessionToken().equals(b.getSessionToken());
        } catch (RuntimeException unavailableSession) {
            return false;
        }
    }

    /**
     * 给当前会话注册**专属**回调。
     *
     * <p>为什么不能共用 MediaAdapter 那个回调：那个回调注册在**所有**被观察到的会话上，
     * 别的播放器推元数据也会走它 → 收藏态会被别的 App 的评分覆盖掉。
     * → 这里注册一个只跟着当前会话走的回调。
     */
    private void registerController(final MediaController target) {
        controllerCallback = new MediaController.Callback() {
            @Override public void onMetadataChanged(MediaMetadata metadata) {
                if (controller != target) return;
                readMetadata(metadata);
            }
            @Override public void onPlaybackStateChanged(PlaybackState state) {
                if (controller != target) return;
                readPlaybackState(state);
            }
            @Override public void onSessionEvent(String event, Bundle extras) {
                if (controller != target) return;
                // 必须显式限定外部类：不写的话会解析到**这个**回调自己 → 无限递归。
                MediaActionBridge.this.onSessionEvent(event, extras);
            }
        };
        target.registerCallback(controllerCallback, handler);
    }

    /** 注销当前会话的专属回调。 */
    private void unregisterController() {
        MediaController previous = controller;
        MediaController.Callback previousCallback = controllerCallback;
        controllerCallback = null;
        if (previous != null && previousCallback != null) {
            try { previous.unregisterCallback(previousCallback); }
            catch (RuntimeException unavailableSession) { /* Already destroyed. */ }
        }
    }

    /**
     * 会话事件（网易云用它回播放模式与收藏结果）。
     *
     * @param event 事件名
     * @param extras 事件参数
     */
    public void onSessionEvent(String event, Bundle extras) {
        if (event == null || extras == null) return;
        try {
            if (NETEASE_ACTION_GET_PLAY_MODE.equals(event)) {
                if (!extras.containsKey(NETEASE_EXTRA_PLAY_MODE)) return;
                MediaActions.PlayMode mode = MediaActions.playModeFromNeteaseCode(
                        extras.getInt(NETEASE_EXTRA_PLAY_MODE, -1));
                if (mode == null) return;
                setPlayModeState(new MediaActions.PlayModeState(mode));
            } else if (NETEASE_ACTION_STAR.equals(event)) {
                int code = extras.getInt("code", MediaActions.FavoriteResult.FAILED);
                applyFavoriteResult(code, extras.getString("message"));
            }
        } catch (RuntimeException malformedPayload) {
            UniLog.fail(LogTags.MEDIA, "media/action-event", "event", event, "reason", "malformed-payload");
        }
    }

    // ---------------------------------------------------------------- 下发指令

    /**
     * <b>收藏 / 取消收藏</b>当前歌曲。
     *
     * <p>状态「不知道」时，按下收藏按钮 → <b>收藏</b>（不是「取消收藏」）。
     * 理由：用户点收藏按钮的心智是「我想收藏它」。
     *
     * @return 是否真的下发出去了
     */
    public boolean toggleFavorite() {
        if (context == null || controller == null) {
            UniLog.fail(LogTags.MEDIA, "media/favorite", "reason", "no-active-session");
            return false;
        }
        MediaActions.Caps caps = caps();
        if (!caps.favorite) {
            UniLog.fail(LogTags.MEDIA, "media/favorite", "reason", "unsupported-by-player",
                    "package", String.valueOf(sourcePackage()));
            return false;
        }
        boolean target = !favoriteState.isFavorited();
        lastFavoriteTarget = target;
        favoriteStateBeforeSend = favoriteState;
        boolean ok = sendFavorite(target);
        if (!ok) {
            // 下发失败 → 状态不变（也不排乐观更新）。
            favoriteStateBeforeSend = null;
            return false;
        }
        // 延后乐观：先等播放器的权威回报，没人回报才在兜底时间后落乐观值。
        scheduleOptimisticFavorite(target);
        return true;
    }

    /**
     * <b>切播放模式</b>：顺序播放 → 单曲循环 → 随机播放 → 顺序播放。
     *
     * @return 是否真的下发出去了
     */
    public boolean cyclePlayMode() {
        if (context == null || controller == null) {
            UniLog.fail(LogTags.MEDIA, "media/play-mode", "reason", "no-active-session");
            return false;
        }
        MediaActions.Caps caps = caps();
        if (!caps.playMode) {
            UniLog.fail(LogTags.MEDIA, "media/play-mode", "reason", "unsupported-by-player",
                    "package", String.valueOf(sourcePackage()));
            return false;
        }
        MediaActions.PlayMode next = MediaActions.nextPlayMode(playModeState.mode);
        boolean ok = sendPlayMode(next);
        if (!ok) return false;
        // 播放模式是立即乐观：QQ 音乐根本不回报模式，等回报就永远停在旧图标。
        setPlayModeState(new MediaActions.PlayModeState(next));
        return true;
    }

    /** 下发收藏指令（按包名分流）。 */
    private boolean sendFavorite(boolean favorited) {
        String pkg = sourcePackage();
        boolean ok;
        String route;
        if (MediaActions.QQ_PACKAGE.equals(pkg)) {
            route = "qq-uri";
            ok = QqMusicControl.sendFavorite(context, favorited);
        } else if (MediaActions.NETEASE_PACKAGE.equals(pkg)) {
            route = "netease-custom-action";
            Bundle extras = new Bundle();
            extras.putBoolean(NETEASE_EXTRA_IS_STAR, favorited);
            ok = SessionProxy.sendCustomAction(context, controller, NETEASE_ACTION_STAR, extras);
        } else {
            route = "standard-rating";
            ok = SessionProxy.sendRating(context, controller, Rating.newHeartRating(favorited));
        }
        UniLog.done(LogTags.MEDIA, "media/favorite", "package", String.valueOf(pkg),
                "favorited", favorited, "route", route, "accepted", ok);
        return ok;
    }

    /** 下发播放模式指令（按包名分流）。 */
    private boolean sendPlayMode(MediaActions.PlayMode mode) {
        String pkg = sourcePackage();
        boolean ok;
        String route;
        if (MediaActions.QQ_PACKAGE.equals(pkg)) {
            route = "qq-uri";
            ok = QqMusicControl.sendPlayMode(context, mode);
        } else if (MediaActions.NETEASE_PACKAGE.equals(pkg)) {
            route = "netease-custom-action";
            Bundle extras = new Bundle();
            extras.putInt(NETEASE_EXTRA_PLAY_MODE, MediaActions.neteasePlayModeCode(mode));
            ok = SessionProxy.sendCustomAction(context, controller, NETEASE_ACTION_PLAY_MODE, extras);
        } else {
            route = "standard-custom-action";
            Bundle extras = new Bundle();
            // sendCustomAction has no official parameter format, so send both dialects:
            // the launcher-wide code and the Android standard repeat/shuffle values.
            extras.putInt(EXTRA_PLAY_MODE, MediaActions.genericPlayModeCode(mode));
            extras.putInt(EXTRA_REPEAT_MODE, MediaActions.androidRepeatMode(mode));
            extras.putInt(EXTRA_SHUFFLE_MODE, MediaActions.androidShuffleMode(mode));
            ok = SessionProxy.sendCustomAction(context, controller, ACTION_SET_PLAY_MODE, extras);
        }
        UniLog.done(LogTags.MEDIA, "media/play-mode", "package", String.valueOf(pkg),
                "mode", mode.name(), "route", route, "accepted", ok);
        return ok;
    }

    /**
     * <b>问</b>播放器当前是什么播放模式。
     *
     * <p>只有网易云答得上来（它用 session event 回）；
     * 其它播放器只能靠会话 {@code PlaybackState} 的模式字段（读不到就是「不知道」）。
     */
    public boolean requestPlayMode() {
        if (context == null || controller == null) return false;
        if (!MediaActions.NETEASE_PACKAGE.equals(sourcePackage())) return false;
        return SessionProxy.sendCustomAction(context, controller, NETEASE_ACTION_GET_PLAY_MODE, null);
    }

    // ---------------------------------------------------------------- 回报处理

    /**
     * 播放器回报了收藏结果 → <b>校正</b>收藏态。
     *
     * <p>{@code 0}（成功）/ {@code -2}（本来就是这个状态）→ 都按目标态；
     * 其它 → 失败，<b>回滚</b>到下发前的状态（别让界面停在「以为收藏了」）。
     */
    private void applyFavoriteResult(int code, String message) {
        Boolean target = lastFavoriteTarget;
        if (target == null) return;
        MediaActions.FavoriteState corrected =
                MediaActions.favoriteStateFromResult(code, target);
        if (corrected != null) {
            setFavoriteState(corrected);
            return;
        }
        cancelPendingFavorite();
        if (favoriteStateBeforeSend != null) setFavoriteState(favoriteStateBeforeSend);
        UniLog.fail(LogTags.MEDIA, "media/favorite", "reason", "player-rejected", "code", code,
                "message", String.valueOf(message));
    }

    /** 读元数据里的心形评分 → 收藏态。 */
    private void readMetadata(MediaMetadata metadata) {
        Boolean heart = favoriteHeart(metadata);
        if (heart == null) return;
        // The player's report is authoritative: it cancels a pending optimistic update.
        cancelPendingFavorite();
        favoriteStateBeforeSend = null;
        lastFavoriteTarget = null;
        setFavoriteState(heart ? MediaActions.FavoriteState.FAVORITED
                : MediaActions.FavoriteState.NOT_FAVORITED);
    }

    /** 读播放态里的模式字段 → 播放模式。 */
    private void readPlaybackState(PlaybackState state) {
        if (state == null) return;
        MediaActions.PlayMode mode =
                MediaActions.playModeFromState(repeatModeOf(state), shuffleModeOf(state));
        if (mode == null) return;
        setPlayModeState(new MediaActions.PlayModeState(mode));
    }

    // ---------------------------------------------------------------- 状态写入

    private void setFavoriteState(MediaActions.FavoriteState next) {
        if (favoriteState.equals(next)) return;
        UniLog.done(LogTags.MEDIA, "media/favorite-state", "from", favoriteState.toString(),
                "to", next.toString());
        favoriteState = next;
        notifyChanged();
    }

    private void setPlayModeState(MediaActions.PlayModeState next) {
        if (playModeState.equals(next)) return;
        UniLog.done(LogTags.MEDIA, "media/play-mode-state", "from", playModeState.toString(),
                "to", next.toString());
        playModeState = next;
        notifyChanged();
    }

    /** 排一个<b>延后</b>的乐观收藏更新。 */
    private void scheduleOptimisticFavorite(final boolean target) {
        cancelPendingFavorite();
        final MediaActions.FavoriteState optimistic = target
                ? MediaActions.FavoriteState.FAVORITED : MediaActions.FavoriteState.NOT_FAVORITED;
        Runnable job = new Runnable() {
            @Override public void run() {
                pendingFavorite = null;
                setFavoriteState(optimistic);
            }
        };
        pendingFavorite = job;
        handler.postDelayed(job, OPTIMISTIC_FAVORITE_MS);
    }

    /** 取消挂起的乐观收藏更新。 */
    private void cancelPendingFavorite() {
        if (pendingFavorite != null) {
            handler.removeCallbacks(pendingFavorite);
            pendingFavorite = null;
        }
    }

    private void notifyChanged() {
        if (changed != null) changed.run();
    }

    // ---------------------------------------------------------------- 快照

    /**
     * 把「收藏态 / 播放模式 / 能力」写进给 Flutter 的媒体快照。
     *
     * <p>三个字段的语义：
     * <ul>
     *   <li>{@code favorited}：true / false / <b>null（不知道）</b>；</li>
     *   <li>{@code playMode}：{@code REPEAT_ALL} / {@code REPEAT_ONE} / {@code SHUFFLE} / <b>null</b>；</li>
     *   <li>{@code actionCaps}：{@code {favorite: bool, playMode: bool}} —— 界面据此决定亮不亮按钮。</li>
     * </ul>
     */
    public void augmentSnapshot(JSONObject snapshot) {
        if (snapshot == null) return;
        try {
            MediaActions.Caps caps = caps();
            snapshot.put("favorited", favoriteState.known() ? favoriteState.isFavorited() : JSONObject.NULL);
            snapshot.put("playMode", playModeState.known() ? playModeState.mode.wire() : JSONObject.NULL);
            snapshot.put("actionCaps", new JSONObject()
                    .put("favorite", caps.favorite)
                    .put("playMode", caps.playMode));
        } catch (Exception ignored) {
            // Keep the standard snapshot; the buttons simply stay hidden.
        }
    }

    // ---------------------------------------------------------------- 读取会话事实

    /**
     * 从会话元数据里读<b>收藏态</b>（标准通道，纯逻辑，可单测）。
     *
     * <p>播放器把收藏态放在 {@code METADATA_KEY_USER_RATING} 的<b>心形评分</b>里。
     *
     * @param metadata 当前会话的元数据（null = 没有会话）
     * @return true = 已收藏；false = 未收藏；<b>null = 不知道</b>
     *   （没有这个评分项，或者评分类型不是心形）
     */
    public static Boolean favoriteHeart(MediaMetadata metadata) {
        if (metadata == null) return null;
        try {
            Rating rating = metadata.getRating(MediaMetadata.METADATA_KEY_USER_RATING);
            if (rating == null) return null;
            if (rating.getRatingStyle() != Rating.RATING_HEART) return null;
            return rating.hasHeart();
        } catch (RuntimeException unavailableSession) {
            return null;
        }
    }

    /**
     * 从 {@code PlaybackState} 里读<b>重复模式</b>（反射）。
     *
     * <p>{@code getRepeatMode()} 不在公开的 Android API 里（各版本 framework 都没暴露），
     * 只能反射调用 —— 读不到就当「没设置」。
     *
     * @param state 当前会话的播放状态（null = 没有会话）
     * @return 重复模式值；读不到返回 {@link MediaActions.RepeatMode#NONE}
     */
    public static int repeatModeOf(PlaybackState state) {
        if (state == null) return MediaActions.RepeatMode.NONE;
        try {
            Object value = PlaybackState.class.getMethod("getRepeatMode").invoke(state);
            return value instanceof Integer ? (Integer) value : MediaActions.RepeatMode.NONE;
        } catch (Throwable unavailableGetter) {
            return MediaActions.RepeatMode.NONE;
        }
    }

    /**
     * 从 {@code PlaybackState} 里读<b>随机模式</b>（反射，原因同 {@link #repeatModeOf}）。
     *
     * @param state 当前会话的播放状态（null = 没有会话）
     * @return 随机模式值；读不到返回 {@link MediaActions.ShuffleMode#NONE}
     */
    public static int shuffleModeOf(PlaybackState state) {
        if (state == null) return MediaActions.ShuffleMode.NONE;
        try {
            Object value = PlaybackState.class.getMethod("getShuffleMode").invoke(state);
            return value instanceof Integer ? (Integer) value : MediaActions.ShuffleMode.NONE;
        } catch (Throwable unavailableGetter) {
            return MediaActions.ShuffleMode.NONE;
        }
    }
}
