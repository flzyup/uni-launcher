package xyz.i4o.uni.launcher.core;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertNull;
import static org.junit.Assert.assertTrue;

import org.junit.Test;

import xyz.i4o.uni.launcher.integration.QqMusicControl;

/**
 * 「收藏 / 播放模式」的协议抽象层（移植自 CarDesk 的 MediaActionsTest）。
 *
 * <h3>这里断言的每一条都有出处</h3>
 *
 * <h4>QQ 音乐车机版（{@code com.tencent.qqmusiccar} 1.9.8.22 反编译 + 模拟器实测）</h4>
 * <ul>
 *   <li>收藏码：{@code BroadcastReceiverCenterForThird.controlPlay()} 的 {@code case 5 / 6}；</li>
 *   <li>播放模式码：{@code MODE_SONG_REPEAT = 101} /
 *       {@code MODE_LIST_REPEAT = 103} / {@code MODE_SONG_SHUFFLE = 105}。</li>
 * </ul>
 *
 * <h4>网易云车机版（{@code com.netease.cloudmusic.iot} 6.2.81 反编译）</h4>
 * <ul>
 *   <li>收藏动作名：{@code "star_action"}；播放模式动作名：{@code "play_mode_action"}；</li>
 *   <li>读播放模式动作名：{@code "get_play_mode_action"}；</li>
 *   <li>播放模式编码：车机侧 <b>1 = 顺序 / 2 = 随机 / 3 = 单曲</b>
 *       （网易云内部 0/1/2 → 车机 1/3/2）。</li>
 * </ul>
 *
 * <h4>汽水音乐车机版</h4>
 * <ul>
 *   <li>收藏：<b>标准评分通道</b>（{@code onSetRating} → 收藏）；</li>
 *   <li>播放模式：只在进程内指令中心，第三方接不上 → <b>不支持</b>。</li>
 * </ul>
 *
 * <h4>未适配的音乐 App（通用兜底）</h4>
 * 靠<b>运行时探测</b>决定亮不亮按钮。
 *
 * <p>纯 Java，不碰 Android —— 直接 JVM 单测。
 */
public class MediaActionsTest {

    // ------------------------------------------------------------ 能力表

    @Test
    public void qqMusicSupportsFavoriteAndPlayMode() {
        MediaActions.Caps caps = MediaActions.capsOf(MediaActions.QQ_PACKAGE, null);
        assertTrue(caps.favorite);
        assertTrue(caps.playMode);
    }

    @Test
    public void neteaseSupportsFavoriteAndPlayMode() {
        MediaActions.Caps caps = MediaActions.capsOf(MediaActions.NETEASE_PACKAGE, null);
        assertTrue(caps.favorite);
        assertTrue(caps.playMode);
    }

    @Test
    public void sodaSupportsFavoriteButNotPlayMode() {
        // 汽水的收藏走标准评分通道，播放模式没有对外通道 → 播放模式按钮隐藏。
        MediaActions.Caps caps = MediaActions.capsOf(MediaActions.SODA_PACKAGE, null);
        assertTrue(caps.favorite);
        assertFalse(caps.playMode);
        assertTrue(MediaActions.supportsFavorite(MediaActions.SODA_PACKAGE, null));
        assertFalse(MediaActions.supportsPlayMode(MediaActions.SODA_PACKAGE, null));
    }

    @Test
    public void capsAreKeyedByPackageNotBySourceId() {
        // 同一个「网易云音乐」来源 id 下，另一个包（手机版 / clone）没有这两条通道。
        assertFalse(MediaActions.supportsFavorite("com.netease.cloudmusic", null));
        assertFalse(MediaActions.supportsFavorite("com.tencent.qqmusic", null));
    }

    @Test
    public void packagesOutsideTheTableSupportNothing() {
        assertFalse(MediaActions.supportsFavorite(null, null));
        assertFalse(MediaActions.supportsFavorite("", null));
        assertFalse(MediaActions.supportsFavorite("   ", null));
        assertFalse(MediaActions.supportsPlayMode("com.example.player", null));
        assertEquals(MediaActions.Caps.NONE, MediaActions.capsOf("com.example.player", null));
    }

    // ---------------------------------------------------- 通用兜底（运行时探测）

    @Test
    public void unadaptedAppWithHeartRatingSupportsFavorite() {
        // 会话发了心形评分 → 说明它用标准收藏语义 → 亮收藏按钮
        MediaActions.Probe probe = new MediaActions.Probe(Boolean.FALSE,
                MediaActions.RepeatMode.NONE, MediaActions.ShuffleMode.NONE);
        MediaActions.Caps caps = MediaActions.capsOf("com.example.player", probe);
        assertTrue(caps.favorite);
        assertFalse(caps.playMode);
    }

    @Test
    public void unadaptedAppWithoutHeartRatingDoesNotSupportFavorite() {
        // 没有心形评分项 → 不猜 → 不亮收藏按钮
        MediaActions.Probe probe = new MediaActions.Probe(null,
                MediaActions.RepeatMode.NONE, MediaActions.ShuffleMode.NONE);
        assertFalse(MediaActions.capsOf("com.example.player", probe).favorite);
    }

    @Test
    public void unadaptedAppExposingPlayModeSupportsPlayMode() {
        MediaActions.Probe probe = new MediaActions.Probe(null,
                MediaActions.RepeatMode.ALL, MediaActions.ShuffleMode.NONE);
        MediaActions.Caps caps = MediaActions.capsOf("com.example.player", probe);
        assertFalse(caps.favorite);
        assertTrue(caps.playMode);
    }

    @Test
    public void unadaptedAppWithoutProbeSupportsNothing() {
        // 没有会话 → 探不到 → 两个按钮都不亮
        MediaActions.Caps caps = MediaActions.capsOf("com.example.player", null);
        assertEquals(MediaActions.Caps.NONE, caps);
        assertFalse(MediaActions.supportsFavorite("com.example.player", null));
        assertFalse(MediaActions.supportsPlayMode("com.example.player", null));
    }

    @Test
    public void knownPackagesIgnoreTheProbe() {
        // 网易云 / 汽水在能力表里 → 探测结果说什么都不改它们的结论
        MediaActions.Probe probe = new MediaActions.Probe(null,
                MediaActions.RepeatMode.NONE, MediaActions.ShuffleMode.NONE);
        assertTrue(MediaActions.capsOf(MediaActions.NETEASE_PACKAGE, probe).favorite);
        assertTrue(MediaActions.capsOf(MediaActions.NETEASE_PACKAGE, probe).playMode);
        // 汽水：收藏仍然支持，播放模式仍然不支持（探测到模式字段也不给开）
        assertTrue(MediaActions.capsOf(MediaActions.SODA_PACKAGE, probe).favorite);
        assertFalse(MediaActions.capsOf(MediaActions.SODA_PACKAGE, probe).playMode);
    }

    // ---------------------------------------------------- 播放模式字段（标准口径）

    @Test
    public void playModeIsExposedOnlyAboveNone() {
        // API 28 的 PlaybackState 默认值是 NONE(0)（UNSET(-1) 是 API 29 才有）
        // → 必须按「大于 0」判，否则每个会话都会「暴露」播放模式
        assertFalse(MediaActions.exposesPlayMode(MediaActions.RepeatMode.NONE, MediaActions.ShuffleMode.NONE));
        assertFalse(MediaActions.exposesPlayMode(MediaActions.RepeatMode.UNSET, MediaActions.ShuffleMode.UNSET));
        assertTrue(MediaActions.exposesPlayMode(MediaActions.RepeatMode.ALL, MediaActions.ShuffleMode.NONE));
        assertTrue(MediaActions.exposesPlayMode(MediaActions.RepeatMode.ONE, MediaActions.ShuffleMode.NONE));
        assertTrue(MediaActions.exposesPlayMode(MediaActions.RepeatMode.NONE, MediaActions.ShuffleMode.ALL));
    }

    @Test
    public void playModeComesFromThePlaybackStateFields() {
        assertEquals(MediaActions.PlayMode.SHUFFLE,
                MediaActions.playModeFromState(MediaActions.RepeatMode.NONE, MediaActions.ShuffleMode.ALL));
        assertEquals(MediaActions.PlayMode.REPEAT_ONE,
                MediaActions.playModeFromState(MediaActions.RepeatMode.ONE, MediaActions.ShuffleMode.NONE));
        assertEquals(MediaActions.PlayMode.REPEAT_ALL,
                MediaActions.playModeFromState(MediaActions.RepeatMode.ALL, MediaActions.ShuffleMode.NONE));
        // 随机优先于重复
        assertEquals(MediaActions.PlayMode.SHUFFLE,
                MediaActions.playModeFromState(MediaActions.RepeatMode.ALL, MediaActions.ShuffleMode.ALL));
        // 没设置 → 不知道
        assertNull(MediaActions.playModeFromState(MediaActions.RepeatMode.NONE, MediaActions.ShuffleMode.NONE));
        assertNull(MediaActions.playModeFromState(MediaActions.RepeatMode.UNSET, MediaActions.ShuffleMode.UNSET));
    }

    @Test
    public void genericPlayModeCodesDifferFromNeteaseCodes() {
        // 通用：1=顺序 / 2=单曲 / 3=随机
        assertEquals(1, MediaActions.genericPlayModeCode(MediaActions.PlayMode.REPEAT_ALL));
        assertEquals(2, MediaActions.genericPlayModeCode(MediaActions.PlayMode.REPEAT_ONE));
        assertEquals(3, MediaActions.genericPlayModeCode(MediaActions.PlayMode.SHUFFLE));
        // 网易云：1=顺序 / 2=随机 / 3=单曲 → 同一个模式的编码不一样
        assertEquals(2, MediaActions.neteasePlayModeCode(MediaActions.PlayMode.SHUFFLE));
        assertEquals(3, MediaActions.neteasePlayModeCode(MediaActions.PlayMode.REPEAT_ONE));
    }

    @Test
    public void standardParametersPointAtTheSameMode() {
        // play_mode（通用编码）与 repeat_mode / shuffle_mode（Android 标准值）
        // 必须指向同一个模式 —— 两套一起发，认哪套的播放器都能听懂。
        MediaActions.PlayMode shuffle = MediaActions.PlayMode.SHUFFLE;
        assertEquals(MediaActions.RepeatMode.NONE, MediaActions.androidRepeatMode(shuffle));
        assertEquals(MediaActions.ShuffleMode.ALL, MediaActions.androidShuffleMode(shuffle));
        MediaActions.PlayMode all = MediaActions.PlayMode.REPEAT_ALL;
        assertEquals(MediaActions.RepeatMode.ALL, MediaActions.androidRepeatMode(all));
        assertEquals(MediaActions.ShuffleMode.NONE, MediaActions.androidShuffleMode(all));
        MediaActions.PlayMode one = MediaActions.PlayMode.REPEAT_ONE;
        assertEquals(MediaActions.RepeatMode.ONE, MediaActions.androidRepeatMode(one));
        assertEquals(MediaActions.ShuffleMode.NONE, MediaActions.androidShuffleMode(one));
    }

    // ---------------------------------------------------- 收藏结果回报

    @Test
    public void favoriteSuccessCorrectsToTheTargetState() {
        // 网易云 yc/s0.java → session event code=0 "操作成功"
        assertEquals(MediaActions.FavoriteState.FAVORITED,
                MediaActions.favoriteStateFromResult(MediaActions.FavoriteResult.OK, true));
        assertEquals(MediaActions.FavoriteState.NOT_FAVORITED,
                MediaActions.favoriteStateFromResult(MediaActions.FavoriteResult.OK, false));
    }

    @Test
    public void alreadyInThatStateAlsoCorrectsToTheTargetState() {
        // code=-2 "已经是收藏状态了" —— 虽然没真改，
        // 但它明确说了「当前状态就是你要的那个」→ 界面要跟上
        assertEquals(MediaActions.FavoriteState.FAVORITED,
                MediaActions.favoriteStateFromResult(MediaActions.FavoriteResult.ALREADY, true));
        assertEquals(MediaActions.FavoriteState.NOT_FAVORITED,
                MediaActions.favoriteStateFromResult(MediaActions.FavoriteResult.ALREADY, false));
    }

    @Test
    public void favoriteFailureReturnsNullSoTheCallerRollsBack() {
        assertNull(MediaActions.favoriteStateFromResult(MediaActions.FavoriteResult.FAILED, true));
        assertNull(MediaActions.favoriteStateFromResult(-99, true));
    }

    // ------------------------------------------------------------ 收藏态

    @Test
    public void favoriteStateHasThreeValues() {
        assertFalse(MediaActions.FavoriteState.UNKNOWN.known());
        assertFalse(MediaActions.FavoriteState.UNKNOWN.isFavorited());
        assertTrue(MediaActions.FavoriteState.FAVORITED.known());
        assertTrue(MediaActions.FavoriteState.FAVORITED.isFavorited());
        assertTrue(MediaActions.FavoriteState.NOT_FAVORITED.known());
        assertFalse(MediaActions.FavoriteState.NOT_FAVORITED.isFavorited());
    }

    @Test
    public void qqKeyIsFavBecomesAFavoriteState() {
        // 出处：putSongInfo() → `i4 = (songInfo == null || !MyFavManager.H().R(songInfo)) ? 0 : 1`
        assertEquals(MediaActions.FavoriteState.FAVORITED, MediaActions.favoriteFromRaw(1));
        assertEquals(MediaActions.FavoriteState.NOT_FAVORITED, MediaActions.favoriteFromRaw(0));
        // -1 = 这条广播里没有这个字段 → **不知道**（不能当成「未收藏」）
        assertEquals(MediaActions.FavoriteState.UNKNOWN, MediaActions.favoriteFromRaw(-1));
    }

    @Test
    public void unknownDoesNotOverwriteKnown() {
        // QQ 的 update_state 广播里没有 key_is_fav →
        // 若直接覆盖，已知的「已收藏」会被冲成「不知道」→ 界面会闪一下。
        MediaActions.FavoriteState known = MediaActions.FavoriteState.FAVORITED;
        assertEquals(known, MediaActions.mergeFavorite(known, MediaActions.FavoriteState.UNKNOWN));
        assertEquals(known, MediaActions.mergeFavorite(known, null));
        // 确实带了这个字段的新值 → 更新
        assertEquals(MediaActions.FavoriteState.NOT_FAVORITED,
                MediaActions.mergeFavorite(known, MediaActions.FavoriteState.NOT_FAVORITED));
    }

    // ------------------------------------------------------------ 播放模式

    @Test
    public void playModeCyclesThroughAllThree() {
        assertEquals(MediaActions.PlayMode.REPEAT_ONE,
                MediaActions.nextPlayMode(MediaActions.PlayMode.REPEAT_ALL));
        assertEquals(MediaActions.PlayMode.SHUFFLE,
                MediaActions.nextPlayMode(MediaActions.PlayMode.REPEAT_ONE));
        assertEquals(MediaActions.PlayMode.REPEAT_ALL,
                MediaActions.nextPlayMode(MediaActions.PlayMode.SHUFFLE));
    }

    @Test
    public void unknownPlayModeStartsAtRepeatAll() {
        // 最保守的那个档位：随机播放会让「下一首听到的歌跟预期不一样」
        assertEquals(MediaActions.PlayMode.REPEAT_ALL, MediaActions.nextPlayMode(null));
    }

    @Test
    public void playModeSurvivesTheWire() {
        for (MediaActions.PlayMode mode : MediaActions.PlayMode.values()) {
            assertEquals(mode, MediaActions.PlayMode.fromWire(mode.wire()));
        }
        assertNull(MediaActions.PlayMode.fromWire("nonsense"));
        assertNull(MediaActions.PlayMode.fromWire(null));
    }

    @Test
    public void neteasePlayModeCodes() {
        // 车机侧：1 = 顺序 / 2 = 随机 / 3 = 单曲
        assertEquals(1, MediaActions.neteasePlayModeCode(MediaActions.PlayMode.REPEAT_ALL));
        assertEquals(2, MediaActions.neteasePlayModeCode(MediaActions.PlayMode.SHUFFLE));
        assertEquals(3, MediaActions.neteasePlayModeCode(MediaActions.PlayMode.REPEAT_ONE));
    }

    @Test
    public void neteasePlayModeCodesDecodeBack() {
        assertEquals(MediaActions.PlayMode.REPEAT_ALL,
                MediaActions.playModeFromNeteaseCode(MediaActions.NeteasePlayMode.REPEAT_ALL));
        assertEquals(MediaActions.PlayMode.SHUFFLE,
                MediaActions.playModeFromNeteaseCode(MediaActions.NeteasePlayMode.SHUFFLE));
        assertEquals(MediaActions.PlayMode.REPEAT_ONE,
                MediaActions.playModeFromNeteaseCode(MediaActions.NeteasePlayMode.REPEAT_ONE));
        // 不认识的值 → 当「不知道」处理，别瞎猜
        assertNull(MediaActions.playModeFromNeteaseCode(0));
        assertNull(MediaActions.playModeFromNeteaseCode(9));
    }

    // ------------------------------------------------------------ QQ 协议码

    @Test
    public void qqCommandCodes() {
        // 出处：BroadcastReceiverCenterForThird 的常量
        assertEquals(5, QqMusicControl.CMD_FAVORITE);
        assertEquals(6, QqMusicControl.CMD_UNFAVORITE);
        assertEquals(101, QqMusicControl.MODE_SONG_REPEAT);
        assertEquals(103, QqMusicControl.MODE_LIST_REPEAT);
        assertEquals(105, QqMusicControl.MODE_SONG_SHUFFLE);
    }

    @Test
    public void qqPlayModeMapsToItsOwnCodes() {
        assertEquals(QqMusicControl.MODE_SONG_REPEAT,
                QqMusicControl.playModeCode(MediaActions.PlayMode.REPEAT_ONE));
        assertEquals(QqMusicControl.MODE_LIST_REPEAT,
                QqMusicControl.playModeCode(MediaActions.PlayMode.REPEAT_ALL));
        assertEquals(QqMusicControl.MODE_SONG_SHUFFLE,
                QqMusicControl.playModeCode(MediaActions.PlayMode.SHUFFLE));
    }

    @Test
    public void qqFavoriteAndPlayModeUseTheUriChannel() {
        // 只有 action=20 才会真正下发给播放器（controlPlay(m0)）
        assertEquals("qqmusiccar://?action=20&m0=5",
                QqMusicControl.controlUri(QqMusicControl.CMD_FAVORITE));
        assertEquals("qqmusiccar://?action=20&m0=6",
                QqMusicControl.controlUri(QqMusicControl.CMD_UNFAVORITE));
        assertEquals("qqmusiccar://?action=20&m0=101",
                QqMusicControl.controlUri(QqMusicControl.MODE_SONG_REPEAT));
        assertEquals("qqmusiccar://?action=20&m0=103",
                QqMusicControl.controlUri(QqMusicControl.MODE_LIST_REPEAT));
        assertEquals("qqmusiccar://?action=20&m0=105",
                QqMusicControl.controlUri(QqMusicControl.MODE_SONG_SHUFFLE));
    }
}
