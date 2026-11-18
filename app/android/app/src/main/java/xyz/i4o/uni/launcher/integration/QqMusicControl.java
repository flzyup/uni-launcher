package xyz.i4o.uni.launcher.integration;

import android.content.Context;
import android.content.Intent;
import android.net.Uri;
import xyz.i4o.uni.launcher.core.MediaActions;
import xyz.i4o.uni.launcher.log.LogTags;
import xyz.i4o.uni.launcher.log.UniLog;

/**
 * QQ 音乐车机版（{@code com.tencent.qqmusiccar}）的<b>收藏 / 播放模式</b>通道。
 *
 * <h3>为什么不能用标准 MediaSession</h3>
 *
 * 真车（领克 dcy11 / Android 9）诊断包实测：QQ 音乐车机版在会话枚举里
 * <b>一次都没出现过</b>。反编译 + 实测才看清它到底做了什么：
 *
 * <pre>
 * state=PlaybackState {state=0, position=0, ..., actions=631}
 * metadata: null
 * </pre>
 *
 * 三个致命点：
 * <ol>
 *   <li><b>metadata: null</b> —— 它只把歌名塞进老式的 {@code RemoteControlClient}，
 *       MediaSession 一个字节的元数据都没有；</li>
 *   <li><b>state=0（STATE_NONE）</b> —— 它从不更新播放态；</li>
 *   <li><b>没有 setCallback</b> —— 会话是个「空壳」。</li>
 * </ol>
 *
 * <p>所以标准 MediaSession 这条路对 QQ 音乐车机版是<b>死的</b>。
 *
 * <h3>但它有一整套专门给第三方用的协议</h3>
 *
 * 真正的传输控制走 <b>URI scheme</b>：{@code qqmusiccar://?action=20&m0=<命令码>}
 *
 * <table>
 *   <tr><th>m0</th><th>含义</th></tr>
 *   <tr><td>0 / 1 / 2 / 3</td><td>播放 / 暂停 / 上一首 / 下一首</td></tr>
 *   <tr><td><b>5 / 6</b></td><td><b>收藏 / 取消收藏</b></td></tr>
 *   <tr><td><b>101 / 103 / 105</b></td><td><b>单曲循环 / 列表循环 / 随机播放</b></td></tr>
 * </table>
 *
 * <p>{@code action=20} 才是真正下发给播放器的（{@code parseUrlObject()} → {@code controlPlay(m0)}）；
 * 走广播通道的 {@code action=0/2/3} 只会<b>把 QQ 音乐的界面打开</b>，<b>不会</b>真的切歌。
 *
 * <h3>⚠️ 收藏这条通道是「<b>切换</b>」语义，不是「设为」</h3>
 *
 * {@code controlPlay()} 里 {@code case 5} 与 {@code case 6} 落在一起，
 * 最终调 {@code FavorSongServer.a(songInfo, true ^ 当前是否已收藏)} →
 * <b>m0=5 与 m0=6 完全等价，都是「翻转当前收藏态」</b>。
 *
 * <p>后果：桌面状态还是「不知道」时点一下收藏，若 QQ 那边<b>本来就已收藏</b>，
 * 这一下会把它<b>取消</b>掉 → 桌面按乐观值显示，与播放器实际状态相反。
 * 这是<b>协议本身的限制</b>（第三方通道只有 toggle，没有「设为」）。
 */
public final class QqMusicControl {
    /** QQ 音乐车机版的三方控制 scheme。 */
    public static final String SCHEME = "qqmusiccar";

    /** URI 里的 {@code action=20} → 走 {@code controlPlay(m0)}（真正的传输控制）。 */
    public static final int URI_ACTION_CONTROL = 20;

    /** 收藏当前歌曲（{@code m0=5}）。 */
    public static final int CMD_FAVORITE = 5;

    /** 取消收藏当前歌曲（{@code m0=6}；与 {@link #CMD_FAVORITE} 实际等价，都是 toggle）。 */
    public static final int CMD_UNFAVORITE = 6;

    /** 单曲循环（{@code m0=101}）。 */
    public static final int MODE_SONG_REPEAT = 101;

    /** 列表循环（顺序播放，{@code m0=103}）。 */
    public static final int MODE_LIST_REPEAT = 103;

    /** 随机播放（{@code m0=105}）。 */
    public static final int MODE_SONG_SHUFFLE = 105;

    private QqMusicControl() {}

    /**
     * 生成传输控制用的 URI（纯逻辑，可单测）。
     *
     * <p>只有 {@code action=20} 才会真正下发到播放器；
     * 别的 action 在这个 URI 里只会「打开 QQ 音乐的某个页面」。
     *
     * @param code 命令码
     * @return 对应的 URI
     */
    public static String controlUri(int code) {
        return SCHEME + "://?action=" + URI_ACTION_CONTROL + "&m0=" + code;
    }

    /**
     * 播放模式 → QQ 的命令码（纯逻辑，可单测）。
     *
     * @return 101 / 103 / 105
     */
    public static int playModeCode(MediaActions.PlayMode mode) {
        if (mode == MediaActions.PlayMode.REPEAT_ONE) return MODE_SONG_REPEAT;
        if (mode == MediaActions.PlayMode.SHUFFLE) return MODE_SONG_SHUFFLE;
        return MODE_LIST_REPEAT;
    }

    /**
     * 给 QQ 音乐发<b>真正的传输控制</b>（URI 通道）。
     *
     * <p>为什么用 {@code startActivity} 而不是 {@code sendBroadcast}：
     * URI scheme 对应的是 QQ 音乐清单里的 <b>{@code DispacherActivityForThird}</b>
     * 这个 Activity（exported），它内部再转成广播给接收器。
     * 用 {@code startActivity} 走 Activity 这条路，<b>不受 Android 8 起
     * 「隐式广播不再投递给清单接收器」的限制</b>，一定能送到。
     *
     * @param code 命令码（{@link #CMD_FAVORITE} 等）
     * @return 是否真的发出去了
     */
    public static boolean sendControl(Context context, int code) {
        if (context == null) return false;
        String uri = controlUri(code);
        try {
            Intent intent = new Intent(Intent.ACTION_VIEW, Uri.parse(uri))
                    .setPackage(MediaActions.QQ_PACKAGE)
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
            context.getApplicationContext().startActivity(intent);
            return true;
        } catch (RuntimeException error) {
            UniLog.fail(LogTags.MEDIA, "media/qq-control", "code", code, "reason", "start-failed",
                    "error", error.getClass().getSimpleName());
            return false;
        }
    }

    /**
     * 收藏 / 取消收藏当前歌曲。
     *
     * <p>走 URI 通道：{@code qqmusiccar://?action=20&m0=5}（收藏）/ {@code &m0=6}（取消）。
     *
     * @param favorited true = 收藏，false = 取消收藏
     *   （<b>注意</b>：QQ 这条通道上是 toggle，两者实际等价）
     * @return 是否真的发出去了
     */
    public static boolean sendFavorite(Context context, boolean favorited) {
        return sendControl(context, favorited ? CMD_FAVORITE : CMD_UNFAVORITE);
    }

    /**
     * 切播放模式。
     *
     * <p>走 URI 通道：{@code qqmusiccar://?action=20&m0=101|103|105}。
     *
     * @param mode 目标模式
     * @return 是否真的发出去了
     */
    public static boolean sendPlayMode(Context context, MediaActions.PlayMode mode) {
        return sendControl(context, playModeCode(mode));
    }
}
