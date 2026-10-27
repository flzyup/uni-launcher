# 网易云车机版接入

核对版本：`com.netease.cloudmusic.iot` 6.2.81（6002081）。QQ 音乐保持原来的标准 MediaSession 路径。

## 控制

网易云创建 PlaybackState 时只设置状态，没有设置 actions，实际却实现了播放、暂停、前后切歌及 seek 回调。因此不能仅据 actions=0 判定不可控制。

独立的 `NeteaseMediaAdapter` 仅处理这个精确包名。播放/暂停、前后切歌向已选会话发送定向媒体键 DOWN/UP；源码中的接收器消费 UP，存在 500ms 防抖。seek 使用 `TransportControls.seekTo(毫秒)`，播放器内部转换为整秒；按实际时长限制目标。没有全局广播、没有失败重发，也不会控制另一个播放器。发送被接受不等于播放已改变，UI 继续以播放器回调为准。

## 歌词

接收实际存在的三种数据：metadata 的 `android.media.metadata.LYRIC`；`wt_music_lyric` session event 成功状态中的 LRC；`get_lyric_action` event 的三句数组（索引 1 为当前句）。当前句单独显示，不伪造整首歌词或时间轴。切歌、加载、错误时清理旧歌词，并拒绝不匹配的歌曲 ID。

当前安装版本 `assets/ability.json` 没有开启 PlayerConfig.enableLyric，默认关闭。APP 内歌词显示走自己的 UI 链路，对外 MediaSession 上送另有开关。已确认 `show_lyric_action` 只是 UI 指令，不能证明能开启对外上送，桌面不会自动发送它。此版本未上送时明确显示“网易云当前版本未向桌面共享歌词”。未发现可供桌面读取全文的导出 Provider/AIDL；不读取私有缓存、不用网上同名歌曲替代。

## 依据与验证

以上来自现车 APK 的 session 构造、callback、MediaButtonEventReceiver、歌词配置和事件发布代码；嘟嘟的网易云插件使用相同 MediaSession 路径，官方 Launcher3 主要托管媒体中心 Widget。`.inter.apk` 是资源覆盖包，实际接口位于主 APK。原始 APK、字节码与个人媒体日志保存在 Git 忽略的 `car-reports/`。

运行 `python3 app/native-tests/tools/test-netease-adapter.py` 验证零 actions 按键、seek 单位/边界、QQ 零接触、歌词清理和旧回调隔离。JVM 替身测试不代替实车回调验证；实车结果另见验收记录。

## IP753 原车媒体中心与仪表盘（0.6.4）

现车方向盘和仪表盘还依赖 ECARX MediaCenter，单独建立 Android MediaSession 不够。仅启动原车媒体应用能恢复音源目录，不能让第三方播放器接收方向盘控制。现车使用受权限保护的 `ecarx.xsf.mediacenter/.MediaCenterService` Binder 连接；SDK 的 ready 回调在此次环境没有完成，因此未将它作为唯一入口。

`OfficialMediaBridge` 为选中的网易云或 QQ 会话注册在线音源 `6`，提供真实的当前歌曲条目、标题、歌手、专辑、播放状态和进度。它不接管原车收音机、USB 或蓝牙客户端；播放时申请音源，普通进度刷新不重新抢占。原车下一首、上一首、播放、暂停回调定向交给当前播放器。切歌时允许会话短暂消失 2.5 秒，超时释放本工具注册的令牌；停止后拒绝旧回调，播放器切换后不向旧会话发送控制。

2026-10-26 实车：用户分别确认 QQ、网易云的方向盘下一首和仪表盘歌曲信息更新正常。网易云桌面按钮播放/暂停、前后切歌、进度调整亦已观察到状态回读。这不代表网易云已对外共享歌词，歌词仍受上述播放器版本限制。测试与剩余边界见 [0.6.4 实车记录](IP753_0_6_4.md)。桥接替身测试命令为 `python3 app/native-tests/tools/test-official-media-bridge.py`。
