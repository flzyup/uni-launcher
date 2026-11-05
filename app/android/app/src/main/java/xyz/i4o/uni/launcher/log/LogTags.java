package xyz.i4o.uni.launcher.log;

import java.util.Arrays;
import java.util.List;

/**
 * 日志 tag 规范。
 *
 * 全部 tag 统一带 {@code UNI/} 前缀，方便在真车上用一条命令筛出本 App 的日志：
 *
 * <pre>
 * adb logcat | grep 'UNI/'
 * </pre>
 *
 * 分域规则（一位主责方一个 tag，方便按功能收集）：
 *
 * <table>
 * <tr><th>tag</th><th>负责的功能域</th></tr>
 * <tr><td>UNI/App</td><td>启动 / 生命周期 / 全局</td></tr>
 * <tr><td>UNI/Vehicle</td><td>车辆适配层：属性通道建立、读、写</td></tr>
 * <tr><td>UNI/Signal</td><td>车辆信号：续航 / 油量 / 胎压 / 车窗 / 车门</td></tr>
 * <tr><td>UNI/Hvac</td><td>空调：写入、回读、失败回滚</td></tr>
 * <tr><td>UNI/Media</td><td>媒体会话、切歌、播放控制、来源</td></tr>
 * <tr><td>UNI/Lyric</td><td>歌词解析与来源</td></tr>
 * <tr><td>UNI/Spectrum</td><td>音频频谱采集</td></tr>
 * <tr><td>UNI/Ambient</td><td>氛围灯：颜色映射、灯珠下发</td></tr>
 * <tr><td>UNI/Nav</td><td>导航应用、画中画、音频焦点</td></tr>
 * <tr><td>UNI/Traffic</td><td>红绿灯：广播解析、倒计时</td></tr>
 * <tr><td>UNI/Weather</td><td>天气与定位</td></tr>
 * <tr><td>UNI/Calendar</td><td>日历</td></tr>
 * <tr><td>UNI/Ota</td><td>在线更新：检查、下载、安装</td></tr>
 * <tr><td>UNI/Dock</td><td>全局底栏 / 跨应用浮窗</td></tr>
 * <tr><td>UNI/Apps</td><td>应用仓库与抽屉</td></tr>
 * <tr><td>UNI/Setting</td><td>设置项变更</td></tr>
 * <tr><td>UNI/Sys</td><td>系统能力：导航栏 / 状态栏 / 免打扰</td></tr>
 * <tr><td>UNI/Theme</td><td>日夜模式 / 主题</td></tr>
 * <tr><td>UNI/Wallpaper</td><td>壁纸选取与缩放</td></tr>
 * <tr><td>UNI/Transfer</td><td>局域网传输</td></tr>
 * <tr><td>UNI/Debug</td><td>调试桥（ADB）</td></tr>
 * <tr><td>UNI/UI</td><td>Flutter 侧（由 Dart 通过平台通道写入）</td></tr>
 * <tr><td>UNI/Log</td><td>日志系统自身（导出、滚动、失败）</td></tr>
 * </table>
 */
public final class LogTags {
    private LogTags() {}

    public static final String APP = "UNI/App";
    public static final String VEHICLE = "UNI/Vehicle";
    public static final String SIGNAL = "UNI/Signal";
    public static final String HVAC = "UNI/Hvac";
    public static final String MEDIA = "UNI/Media";
    public static final String LYRIC = "UNI/Lyric";
    public static final String SPECTRUM = "UNI/Spectrum";
    public static final String AMBIENT = "UNI/Ambient";
    public static final String NAV = "UNI/Nav";
    public static final String TRAFFIC = "UNI/Traffic";
    public static final String WEATHER = "UNI/Weather";
    public static final String CALENDAR = "UNI/Calendar";
    public static final String OTA = "UNI/Ota";
    public static final String DOCK = "UNI/Dock";
    public static final String APPS = "UNI/Apps";
    public static final String SETTING = "UNI/Setting";
    public static final String SYS = "UNI/Sys";
    public static final String THEME = "UNI/Theme";
    public static final String WALLPAPER = "UNI/Wallpaper";
    public static final String TRANSFER = "UNI/Transfer";
    public static final String DEBUG = "UNI/Debug";
    public static final String UI = "UNI/UI";
    public static final String LOG = "UNI/Log";

    /** 全部 tag（导出诊断包时列出，方便排查「哪个域没日志」）。 */
    public static final List<String> ALL = Arrays.asList(
            APP, VEHICLE, SIGNAL, HVAC, MEDIA, LYRIC, SPECTRUM, AMBIENT, NAV, TRAFFIC,
            WEATHER, CALENDAR, OTA, DOCK, APPS, SETTING, SYS, THEME, WALLPAPER, TRANSFER,
            DEBUG, UI, LOG);
}
