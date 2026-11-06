# 方控与中控按键接入桌面媒体控制

## 结论

能。但**必须接原车输入通道**：领克 05（IP753）的方控播放/暂停、上下曲不走 AOSP 的
`85/87/88`，而是 ECARX 自定义码（`200085/200087/200088`，方向盘「快进」是 `210005`），
由系统 `EcarxInputDispatcherService` 派发。桌面只镜像标准 `MediaSession` 的话，
这些键能不能到桌面取决于原车是否额外把标准媒体键也发一份，属于碰运气。

按键码来源与反编译依据见 [car-reports/carcontrol/STEERING_KEYS.md](../car-reports/carcontrol/STEERING_KEYS.md)。

## 实现

| 文件 | 作用 |
| --- | --- |
| `core/SteeringKeyPolicy.java` | 按键码 → 媒体动作、动作分组、跨通道折叠。纯 Java，有单元测试。 |
| `integration/SteeringKeyBridge.java` | 反射接原车输入通道：先 `com.ecarx.xui.adaptapi.input.Input#requestKeysInterception`，失败退 `android.cevt.dcy11.inputmanager.InputManager#setCallback`。 |
| `integration/MediaAdapter.java` | 四条外部通道统一入口 `onSteeringAction(channel,action)`；`snapshot()` 里带 `steeringKeys` 与 `steeringInject` 诊断。 |
| `integration/SteeringKeyInjector.java` | 传输控制不可用时按键注入：`InputManager#injectInputEvent` 优先，退回 `input keyevent`。 |
| `integration/KugouKeyRelay.java` | 酷狗车机版专用广播旁路（`byd.intent.action.MEDIA_BUTTON` → `BYDBroadcastReceiver`）。 |
| `MainActivity.dispatchKeyEvent` | 车机把媒体键当普通按键派给窗口时（不走 MediaSession 路由）的兜底路径。 |
| `LauncherRuntime.dispatchSteeringKey` | 窗口路径到媒体适配层的转接。 |

两条原车接口都在 `/system/framework`（`ecarx.adapterapi.jar`、`android.cevt.dcy11.inputmanager.jar`，
均有 boot vdex），所以全用反射、零编译期依赖，也不需要打包任何原厂 jar。
`requestKeysInterception` 在原厂实现里只是登记回调（返回值被忽略），**不改写按键路由**，
原车媒体中心和播放器照旧收到这些键——这一点决定了下面必须做折叠。

## 按键映射

| 键码 | 含义 | 动作 |
| --- | --- | --- |
| 200085 | 方向盘播放/暂停 | `toggle-play` |
| 200087 / 200088 | 方向盘下一首 / 上一首 | `next` / `previous` |
| 210005 | 方向盘快进（下一条） | `next` |
| 85 / 126 / 127 | AOSP 播放暂停 / 播放 / 暂停 | `toggle-play` / `play` / `pause` |
| 87 / 88 | AOSP 下一首 / 上一首 | `next` / `previous` |
| 110003、210003 | 中控「媒体源」 | 不接管，只进诊断 |
| 200024/200025/200164、110007-110010、210007-210010 | 音量与旋钮 | 不接管，只进诊断 |

## 倒推执行：传输控制不可用时的兜底

方控收到键之后，动作要交给当前播放器执行。正常路径是 `MediaController#getTransportControls`，
但有的车机播放器（酷狗车机版是典型）不发布可用的 `TransportControls`，`getActions()` 里
连 `ACTION_SKIP_TO_NEXT` 都没有；这类播放器只在自己是焦点窗口时对按键有反应。于是执行面
按下面顺序降级，任意一级成功即算完成（`MediaAdapter#command`）：

1. **标准传输控制**（`transport()`）：按 `getActions()` 掩码判断能力，没有就直接下一级，不改写玩家状态。
2. **专用广播**（`KugouKeyRelay`）：当前音源是 `com.kugou.android.auto` 且包确实装上时，
   发 `byd.intent.action.MEDIA_BUTTON` 到它自己的 `BYDBroadcastReceiver`。零权限、定向，
   不会误伤焦点窗口。
3. **按键注入**（`SteeringKeyInjector`）：`InputManager#injectInputEvent`（`INJECT_EVENTS`，
   车机包已声明并随平台签名授予，亚毫秒级、无进程开销）；反射失败或第一次注入被拒才退回
   `input keyevent`（每键一次进程 fork，二十毫秒起步）。注入的键码是 AOSP 的
   `85/87/88/126/127`，不是原车码——`200085` 一类只在原车输入通道里被认识。

**回环抑制**。注入下去的键会从原车输入回调或标准会话再回来一次，若不挡住就会一次按键走两步
（下一首跳两首）。`MediaAdapter#injectedEcho` 在注入时记下动作分组与时间，250ms 内同分组的
外部通道回调直接丢掉。这比「临时把窗口设成可获焦、用窗口吞掉按键」那套做法干净：不遮界面、
不动焦点，也不和状态栏抢窗口层级。

诊断在 `dumpsys --uni-state` 的 `media.steeringInject`：`mode`（`injectInputEvent` /
`input 命令`）、`injected`、`executed`、`failed`、`lastKey`，以及 `kugou.installed/sent`。
`media.officialMedia.focusOwner` 是原车媒体中心返回的当前焦点客户端，用来判断仪表上的
卡片是不是被别人抢走了。

## 为什么要有折叠

同一次按键可能从两条以上通道到达：原车输入回调、原车媒体中心客户端回调
（`OfficialMediaBridge` 的 `onPlay/onPause/onNext/onPrevious`）、系统媒体键路由到
`steeringSession`、以及窗口 `dispatchKeyEvent`。不折叠就会一次按键切两下（等于没反应）。

`SteeringKeyPolicy.Debounce`：

- 分组：`play/pause/toggle-play` 归 `playback`，`next`、`previous` 各自一组；
- **通道内不折叠**（同一个键连按两次是用户真的按了两次）；
- **不同通道**在同一分组、窗口内先后到达才折叠：`playback` 450ms，换歌 150ms。

## 开关

设置页「导航与媒体」里，`关联的音乐播放器` 下面有两个开关，**都默认开**：

| 开关 | 关掉后 |
| --- | --- |
| 方向盘控制音乐（`steeringKeysEnabled`） | `MediaAdapter.setSteeringEnabled(false)` 立刻反注册原车输入通道，之后从四通道任何一条到达的方控键都不再处理（`onSteeringAction` 直接返回），方向盘按键原样留给原车。 |
| 仪表显示桌面音乐（`instrumentSyncEnabled`） | `OfficialMediaBridge.setEnabled(false)` 立刻反注册 `registerMusic` 令牌并解绑 `ecarx.xsf.MEDIA_CENTER_SERVICE`，`update/claimCurrent/publish/register/心跳` 全部早退，仪表跟回原车播放器，桌面不再往上写曲目、封面和进度。 |

两个开关是分开的：关方控只影响按键，仪表那侧继续同步；关仪表只影响上报，方控仍然接管按键。
偏好分别存 `launcher` 的 `steeringKeysEnabled` / `instrumentSyncEnabled`，桌面下次起来先读它们
再决定要不要接原车输入、要不要注册原车媒体中心。诊断里 `media.steeringEnabled`、
`media.instrumentEnabled` 直接反映两者当前的实际状态。

## 实车核对

接入情况与按键码都能直接读出来：

```sh
adb logcat -s UniSteeringKeys
adb shell dumpsys activity xyz.i4o.uni.launcher/.MainActivity --uni-state
```

- logcat：每个键第一次出现打一行 `key=<码> action=<动作|->`，中控那颗键派发的是哪个码就看这里。
- dumpsys 里 `media.steeringKeys`：`installed`、`mode`（`adaptapi`/`dispatcher`/空）、
  `requested`、`accepted`、`events`、`lastCode`、`seen`（键码 → 次数）。

如果实车按下中控音量旋钮上的播放/暂停，`seen` 里出现的是 `110003`（原厂语义是「媒体源」）
或别的码，就在 `SteeringKeyPolicy.action()` 里补一行映射即可，其余链路不用动。

## 边界

- 前提是车机真的把键发给第三方注册的回调。`installed=false` 时桌面行为退回改动前的状态
  （只镜像标准 `MediaSession`），不会更差，也不会崩。
- `requestKeysInterception` 名字里带「拦截」，原厂实现里只是登记回调、忽略回调返回值，
  但派发服务是否会因此不再把这些键发给别的应用只能实车确认。即使原车媒体中心不再收到
  方控键，键也已经由桌面前转给了当前播放器的 `MediaController`，并且桌面会继续用
  `OfficialMediaBridge` 把曲目/状态同步给原车，不会出现「谁都不响应」。
- 音量键与旋钮旋向不接管，`110003` 默认不接管，避免把原车「媒体源」或音量行为改掉。
- 按键注入是**兜底**不是主路径：`injectInputEvent` 需要 `INJECT_EVENTS`（平台签名包才有），
  拿不到时退 `input keyevent` 也只是壳进程自己的权限，两条都不通时 `command()` 如实返回
  `false`，桌面卡片不会假装按成功。注入落点是**当前焦点窗口**，所以只有传输控制不存在的
  播放器才会走到这一步；正常播放器仍走标准传输控制，不会去按别人的键。
- 注入的键码只有 `85/87/88/126/127`，`seek` 没有对应按键，永远拿不到注入通道。
- 桌面只在有窗口/底栏持有运行时监听时接入（`MediaAdapter.start()`），退出即 `stop()` 反注册。
- 以上是按反编译接口实现的；方控与中控按键的**实车联动尚未验证**，验证结果回填到本节。
