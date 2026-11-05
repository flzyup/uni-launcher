# UNI 桌面 · action 路由表（写入命令全清单）

`action` 是桌面与原生之间**唯一的写命令入口**：所有"改状态"的操作都走 `xyz.i4o.uni.launcher/platform` 的 `action` 方法，参数是一个 JSON **字符串** `{"action":"名字", ...}`。
这份文档按业务域列出仓库里**实际存在**的全部 action（从 `LauncherRuntime.java`、`GlobalDockService.java`、`MainActivity.java`、`CommandPolicy.java` 逐条提取），附参数键名、效果、以及 `文件:行号`。
智能体增删 action 时的用法：先在本表查到行号 → 改对应分支 → 回本表更新；本表没有的名字就是不存在，不要"顺手实现"。
两个高频坑：`action` 成功永远返回 `success(null)`，业务失败只走原生 Toast / 状态事件；只写在 `MainActivity.handle` 或只写在 `GlobalDockService.handleCommand` 里的 action，在另一条派发链上**静默无效**（见 §1）。

---

## 0. 阅读约定

| 短名 | 文件 |
| --- | --- |
| `MainActivity` | `app/android/app/src/main/java/xyz/i4o/uni/launcher/MainActivity.java` |
| `GlobalDockService` | `app/android/app/src/main/java/xyz/i4o/uni/launcher/GlobalDockService.java` |
| `LauncherRuntime` | `app/android/app/src/main/java/xyz/i4o/uni/launcher/LauncherRuntime.java` |
| `CommandPolicy` | `app/android/app/src/main/java/xyz/i4o/uni/launcher/core/CommandPolicy.java` |
| `ClimateState` | `app/android/app/src/main/java/xyz/i4o/uni/launcher/core/ClimateState.java` |
| `BootLaunch` | `app/android/app/src/main/java/xyz/i4o/uni/launcher/BootLaunch.java` |
| `StorageCleaner` | `app/android/app/src/main/java/xyz/i4o/uni/launcher/integration/StorageCleaner.java` |
| `MediaAdapter` | `app/android/app/src/main/java/xyz/i4o/uni/launcher/integration/MediaAdapter.java` |
| `OfficialCarContract` | `app/android/app/src/main/java/xyz/i4o/uni/launcher/integration/OfficialCarContract.java` |
| `native_gateway` | `app/lib/platform/native_gateway.dart` |
| `launcher_controller` | `app/lib/controller/launcher_controller.dart` |

---

## 1. 前置说明：一条 action 会经过谁

```
Dart  native_gateway:37-47        jsonEncode({'action':…,'value':…,'zone':…,'enabled':…})
        ↓ invokeMethod('action', <String>)
主窗口                                                           底栏/面板窗口
MainActivity:147-151  校验 ≤8192                                  GlobalDockService:242-247  校验 ≤8192
MainActivity:262-287  handle()                                    GlobalDockService:89-164  handleCommand()
  ├─ 263  GlobalDockService.handleCommand()  ← 底栏专属 action 先吃
  ├─ 268  calendar-access
  ├─ 274  launch-navigation 先藏地图
  ├─ 275  hide-navigation / global-navigation
  └─ 286  LauncherRuntime.handle()                              → 失败才落 LauncherRuntime.handle()（:246）
            └─ LauncherRuntime:288-482 handleOnMain()
```

### 1.1 参数键（只有这三个业务键 + action 本身）

| 键 | 类型 | 读取位置 |
| --- | --- | --- |
| `action` | `String` | `LauncherRuntime:289`、`GlobalDockService:90`、`MainActivity:267` |
| `value` | `String` | `LauncherRuntime:289`、`GlobalDockService:122,125,130,148,155` |
| `zone` | `String` | `LauncherRuntime:289`、`LauncherRuntime:458`（车控 zone） |
| `enabled` | `Boolean` | `LauncherRuntime:305,315-318,320-333,349,373,393`、`GlobalDockService:93,107,110` |

Dart 侧打包：`native_gateway:41-46`；统一入口 `launcher_controller:313-337`（`command(action, {value, zone, enabled})`），失败时把 `message` 设为 `操作暂不可用`（`launcher_controller:334`）。

### 1.2 错误处理与返回

| 场景 | 表现 | 位置 |
| --- | --- | --- |
| arguments `null` 或长度 > 8192 | `error("invalid", …)`，Dart 抛 `PlatformException` | `MainActivity:149`、`GlobalDockService:244` |
| JSON 语法错误 | `error("unavailable","操作暂不可用")` | `MainActivity:167`、`GlobalDockService:249` |
| 动作被识别并执行 | `result.success(null)`，**无业务返回值** | `MainActivity:150`、`GlobalDockService:247` |
| 动作不被识别 | 依旧 `success(null)`；`LauncherRuntime.handle` 返回 `false`（`LauncherRuntime:482`），该布尔被调用方忽略 | `LauncherRuntime:161,482` |
| 动作被拒（参数非法/未安装/未连接） | 原生 Toast，返回值不变 | `LauncherRuntime:630`、`toast(...)` 各分支 |
| 状态变化 | 走 `publish()` → `xyz.i4o.uni.launcher/events` | `LauncherRuntime:505-524` |

注意 `LauncherRuntime.handle` 的注释："true means recognized, including input rejected by the original gates"（`LauncherRuntime:161`）——**返回值只表示"这个名字我认识"，不表示"操作成功"**。

### 1.3 哪些 action 只在一条链上生效（关键不对称）

| 只存在于 | action | 从另一条链发的后果 |
| --- | --- | --- |
| `MainActivity.handle` | `calendar-access`（`:268`）、`hide-navigation`／`global-navigation`（`:275-283`） | 从底栏/面板发：静默无效（`GlobalDockService:246` 只落 `runtime.handle`，`LauncherRuntime` 里没有这三个分支） |
| `GlobalDockService.handleCommand` | `global-dock`、`system-navigation-hidden`、`show-dock-panel`、`panel-ready`、`dismiss-dock-panel`、`system-back`、`show-recents`、`clear-system-recents`、`open-recent-task`、`remove-recent-task`、`toggle-recent-lock`、`show-home`、`show-desktop-settings` | 从主窗口发：**正常生效**（`MainActivity:263` 先调 `handleCommand`） |
| `LauncherRuntime.handleOnMain` | 其余全部 | 两条链都生效 |

---

## 2. 桌面 / 图标 / 应用

| action | 需要的参数 | 效果 | 实现位置 |
| --- | --- | --- | --- |
| `rename-app` | `zone`:String = 包名；`value`:String = 新显示名（空串 = 恢复默认） | 写 prefs `appNames`；校验：`zone` 非空且 ≤255、`value` ≤96、两者都不含 `\n`/`\r`，越界**静默丢弃**并返回已识别；写盘 `commit()` 失败则 Toast「应用名称保存失败」 | `LauncherRuntime:292-300` |
| `desktop-page` | `value`:String，`"0"` 表示首页 | `setDesktopContent("0".equals(value))`，影响快照 `desktopSelected` | `LauncherRuntime:301-303` |
| `demo-mode` | `enabled`:Boolean | 写 prefs `demo`（演示模式：车控/媒体走本地模拟器）；当前 Dart 未见调用方 | `LauncherRuntime:304-306` |
| `select-player` | `value`:String = 包名或 `auto` | 写 prefs `mediaPackage`；非 `auto` 且 `getLaunchIntentForPackage` 为空 → Toast「所选应用未安装或不可启动」；有订阅者时立即 `media.setPreferredPackage` | `LauncherRuntime:307-314` |
| `select-navigation` | `value`:String = 包名或 `auto` | 写 prefs `navigationPackage`；校验同上；并 `trafficLights.navigationChanged()` | `LauncherRuntime:307-314` |
| `launch-app` | `value`:String = 包名 | `AppRepository.launch(包名)`；失败 Toast「应用未安装或无法启动」；底栏链上额外先 `dismissPanel()` | `LauncherRuntime:401`、`GlobalDockService:160-162` |
| `app-info` | `value`:String = 包名 | 打开系统应用信息页；失败 Toast「无法打开应用信息」 | `LauncherRuntime:395` |
| `app-enable` | `value`:String = 包名 | `setEnabled(包名,true)` 并触发一次后台应用刷新；失败 Toast「无法修改应用状态」 | `LauncherRuntime:396-399` |
| `app-disable` | `value`:String = 包名 | 同上，`false` | `LauncherRuntime:396-399` |
| `request-uninstall` | `value`:String = 包名 | 走卸载请求；不可卸载 Toast「该应用不可卸载」 | `LauncherRuntime:400` |
| `refresh` | 无 | 后台重建应用列表 + 重启媒体/车辆数据源 | `LauncherRuntime:390` |
| `media-access` | 无 | 跳「通知使用权」页（媒体会话授权）；无入口 Toast「系统没有提供媒体授权入口」 | `LauncherRuntime:402` |
| `official-widget` | `value`:String = 原厂卡片 type | 该校验 `catalog.providers(value)`，空则 Toast「没有对应的原厂卡片」，否则起 `OfficialWidgetActivity` 并带 `extra type`；底栏链先 `dismissPanel()` | `LauncherRuntime:439-442`、`GlobalDockService:160-162` |
| `open-official` | `value`:String = 原厂 type，特例 `"camera"` | `camera`：`apps.launchOfficialCamera(...)`，失败 Toast「当前车辆未提供原车全景入口」并 `GlobalDockService.resumeAfterCameraLaunchFailure()`；其它 type 走 `catalog.packageFor(value)` 启动，失败 Toast「此设备未安装对应原车应用」。底栏链：`camera` 额外挂起底栏（`GlobalDockService:155`），且一律先 `dismissPanel()` | `LauncherRuntime:443-451` |

---

## 3. 导航与地图

| action | 需要的参数 | 效果 | 实现位置 |
| --- | --- | --- | --- |
| `launch-navigation` | 无 | `navigation.launchFullscreen()` 全屏拉起已选导航；无选择 Toast「请选择已安装的导航应用」；**主窗口链**先 `mapHost.setVisible(false)`（`:274`），底栏链先 `dismissPanel()`（`:160`） | `LauncherRuntime:384`、`MainActivity:274`、`GlobalDockService:160-162` |
| `embed-navigation` | `enabled`:Boolean（缺省按 `true`） | 写 prefs `embedNavigation` | `LauncherRuntime:315` |
| `map-texture-scale` | `enabled`:Boolean | 写 prefs `mapTextureScale`（地图纹理降分辨率，配合 `LiveNavigationHost` 的 `scale`） | `LauncherRuntime:316` |
| `navigation-card-title-hidden` | `enabled`:Boolean（缺省按 `true`） | 写 prefs `navigationCardTitleHidden` | `LauncherRuntime:317` |
| `hide-navigation` | `enabled`:Boolean | 写 prefs `hideNavigation`；随后 `chrome.apply()` + `rt.publish()`。**只在主窗口链生效**；当前 Dart 未见调用方（设置页用 `system-navigation-hidden`） | `MainActivity:275-283` |
| `global-navigation` | `enabled`:Boolean | 写 prefs `globalNavigation`；当 `enabled=true` 且无 `WRITE_SECURE_SETTINGS` → Toast「全局隐藏需要系统授权，当前窗口隐藏仍可使用」并**提前返回**（连 `hideNavigation` 都不写）。**只在主窗口链生效**；当前 Dart 未见调用方 | `MainActivity:275-283` |

---

## 4. 媒体

| action | 需要的参数 | 效果 | 实现位置 |
| --- | --- | --- | --- |
| `auto-play-music` | `enabled`:Boolean | 写 prefs `autoPlayMusic`；开机 5 分钟内由 `scheduleBootAutoPlay()` 排程（`LauncherRuntime:551-559`） | `LauncherRuntime:318` |
| `seek` | `value`:String（毫秒，`Long.parseLong`） | 解析失败或 <0 → 静默返回已识别；演示模式把位置夹在 258000ms 内，否则 `media.command("seek", position)`，不支持时 Toast「当前音源不支持调整进度」 | `LauncherRuntime:461-467` |
| `toggle-play` | 无 | 演示模式：翻转 `demoPlaying`；否则 `media.command`，没有媒体会话时退化为"启动已选播放器"（`launchPackage`），仍失败 Toast「请选择已安装的音乐播放器」 | `LauncherRuntime:468-481` |
| `previous` | 无 | 演示模式：`demoTrack--`、位置归零；否则 `media.command("previous")`，失败 Toast「当前音源不支持此操作，或尚未授权媒体访问」 | `LauncherRuntime:468-481` |
| `next` | 无 | 同上，`demoTrack++` | `LauncherRuntime:468-481` |

**媒体域里的两个"看起来像 action 但不是"的名字**（不要做成 invokeMethod 的 action）：`select-online`、`select-bluetooth` 是 `OfficialMediaBridge` 回调里的内部分支（`MediaAdapter:137-139`），由原车媒体中心回调触发，不经过 `action` 通道。

---

## 5. 车辆 / 车控

`drive-mode` 与 `start-stop` 走"设置"通道（`CommandPolicy.isSettingAction`，`CommandPolicy:17-19`）；其余走"空调"通道（`CommandPolicy.isClimateAction`，`CommandPolicy:7-11`）。两者都会先判 `prefs.demo`：演示模式不写车辆，直接 Toast「演示模式不写入车辆设置」（`LauncherRuntime:453`）。

| action | 需要的参数 | 效果 | 实现位置 |
| --- | --- | --- | --- |
| `drive-mode` | `value`:String，必须是 `DRIVE_MODES` 之一 | `vehicle.command(action,"",value)`；失败 Toast「车辆未连接或未确认该设置值」 | `LauncherRuntime:452-455`、`CommandPolicy:18,26-27` |
| `start-stop` | `value`:String `on`/`off` | 同上；SDK 侧非法值直接返回 null（`OfficialCarCommand:38-42`） | `LauncherRuntime:452-455` |
| `climate-power` | 无（zone/value 不用） | 演示模式 `ClimateState.apply` 翻转 `power`；否则下发车控 | `LauncherRuntime:456-460`、`ClimateState:17` |
| `climate-mode` | `value`:String ∈ `auto`/`ac`/`sync`/`recirc` | 对应位翻转（`sync` 打开时右温跟随左温） | `LauncherRuntime:456-460`、`ClimateState:18-23`、`CommandPolicy:40-42` |
| `temp-up` | `zone`:String ∈ `left`/`right` | 温度 +0.5，夹在 `16..30`（演示）；`sync` 时双区同步 | `LauncherRuntime:456-460`、`ClimateState:10-14`、`CommandPolicy:43` |
| `temp-down` | `zone`:String ∈ `left`/`right` | 温度 -0.5，同上 | 同上 |
| `fan-up` | 无 | 风量 +1，夹在 `1..7` | `ClimateState:15-16`、`CommandPolicy:44` |
| `fan-down` | 无 | 风量 -1，同上 | 同上 |
| `seat-heat` | `zone`:String ∈ `left`/`right`；`value`:String 单字符 `0`..`3` | `left`→`driverHeat`、`right`→`passengerHeat`；等级 >0 时清掉对应座椅通风 | `ClimateState:24-35`、`CommandPolicy:29-38` |
| `seat-vent` | `zone`:String 必须 `left`；`value`:String `0`..`3` | 写 `driverVent`；>0 时清座椅加热；`right` 不支持（`seatControl` 返回 null） | `ClimateState:24-35`、`CommandPolicy:33` |
| `memory-drive-mode-enabled` | `enabled`:Boolean | 写 prefs `memoryDriveModeEnabled`，只记偏好 | `LauncherRuntime:320-322` |
| `memory-drive-mode-target` | `value`:String ∈ `DRIVE_MODES` | 非法 → Toast「该驾驶模式不可用于记忆」；合法写 prefs `memoryDriveMode` | `LauncherRuntime:323-326` |
| `memory-start-stop-enabled` | `enabled`:Boolean | 写 prefs `memoryStartStopEnabled` | `LauncherRuntime:327-329` |
| `memory-start-stop-target` | `value`:String `on`/`off` | 非法 → Toast「启停记忆值无效」；合法写 prefs `memoryStartStop` | `LauncherRuntime:330-333` |
| `memory-apply-now` | `value`:String `driveMode`／`startStop`／`all`（空 = 全不选） | 演示模式直接 Toast「演示模式不写入车辆设置」；否则按已开启的记忆项下发 `vehicle.command`，都没有则 Toast「请先开启要应用的记忆项」 | `LauncherRuntime:334-347` |

**吹风模式（`floor`/`face`/`defrost`/`floor-defrost`/`floor-face`/`face-defrost`/`all`/`auto`）目前只有读回标签，没有对应 action**（`OfficialCarContract:200-212` 是 `blowingMode(int)` 的返回值）。想加吹风写入，得先在这里登记新 action，而不是复用上面任何一个。

---

## 6. 系统 / 底栏 / 维护

### 6.1 底栏与窗口

| action | 需要的参数 | 效果 | 实现位置 |
| --- | --- | --- | --- |
| `global-dock` | `enabled`:Boolean | 写 prefs `globalDockEnabled`；开启时若无悬浮权限 → 跳悬浮窗授权页（失败 Toast「请在系统设置允许 UNI 显示在其他应用上层」），有权限 → `ensureStarted`；关闭时 `stopService` + 还原系统栏改动 + `MainActivity.refreshNavigationChrome` | `GlobalDockService:92-104` |
| `system-navigation-hidden` | `enabled`:Boolean | 系统导航栏隐藏开关：`NavigationInsets.activate/restore`、`SystemNavigationPolicy.setHidden`（失败 Toast「当前系统未允许管理原有导航栏」）、`refreshNavigationChrome`，400ms 后二次 `update()` | `GlobalDockService:105-120` |
| `show-dock-panel` | `value`:String ∈ `apps`/`climate`/`media`/`vehicle`/`navigation`/`music-picker`/`uni-menu`/`transfer`/`cleaner` | 展开面板；点同一个按钮再发一次 = 收起；**白名单不含 `recents`**（`GlobalDockService:352`），任务列表只能由 `show-recents` 打开 | `GlobalDockService:121-123,351-363` |
| `panel-ready` | `value`:String = 当前 `panelRevision` 的十进制字符串 | 面板 Flutter 侧宣告渲染完成：`value` 等于 `""+panelRevision` 才把 `panelReady=true` 并发一次快照（用于等第一帧再取消遮罩） | `GlobalDockService:124-128` |
| `dismiss-dock-panel` | `value`:String，空串或当前 `panelRevision` | 收起面板；`value` 与 revision 不符时**忽略**（避免旧路由关掉新面板） | `GlobalDockService:129-132` |
| `system-back` | 无 | 有面板先关面板；否则在线程里 `Instrumentation().sendKeyDownUpSync(KEYCODE_BACK)`，失败 Toast「系统返回暂不可用」 | `GlobalDockService:133-139` |
| `show-home` | 无 | 关面板 + `cameraSuspended=false`，把 `MainActivity` 以 `NEW_TASK|REORDER_TO_FRONT` 拉到前台（不带 `uniSettings`） | `GlobalDockService:150-154` |
| `show-desktop-settings` | 无 | 同上，但 `putExtra("uniSettings", true)`，落到设置页 | `GlobalDockService:150-154` |

### 6.2 最近任务

| action | 需要的参数 | 效果 | 实现位置 |
| --- | --- | --- | --- |
| `show-recents` | 无 | 有底栏服务 → `toggleRecents()`（面板已是 recents 则收起）；没有底栏 → `SystemRecents.toggle(c)` | `GlobalDockService:140-143` |
| `clear-system-recents` | 无 | 仅当当前面板是 `recents` 才清空并刷新列表，否则无效果 | `GlobalDockService:144-146,440-442` |
| `open-recent-task` | `value`:String = taskId（`Integer.parseInt`，解析失败静默返回） | 切到该任务并关面板；任务已结束 Toast「该任务已经结束」并刷新 | `GlobalDockService:147-149,417-421` |
| `toggle-recent-lock` | `value`:String = taskId | 翻转锁定态；`null` 返回（任务已结束）→ Toast 并刷新；成功则重建 `recentTaskItems` 数组以强制下发 | `GlobalDockService:147-149,423-436` |
| `remove-recent-task` | `value`:String = taskId | 关闭该任务；失败 Toast「无法关闭该任务」 | `GlobalDockService:147-149,437-438` |

**这三个 action 都要求当前面板是 `recents`**（`GlobalDockService:148`），否则 `handleCommand` 返回 `false`，随后落到 `LauncherRuntime.handle` 也无人认领 → 静默无效。

### 6.3 设置目录 / 调试 / 时钟

| action | 需要的参数 | 效果 | 实现位置 |
| --- | --- | --- | --- |
| `refresh-system-settings` | 无 | 后台 `systemSettings.refresh()` + `navigationAudio.refresh()`，完成后推进 `settingsRevision` | `LauncherRuntime:379` |
| `open-system-setting` | `value`:String = 入口 id | `systemSettings.open(value)`；失败 Toast「系统设置入口不可用或权限不足」；底栏链先 `dismissPanel()` | `LauncherRuntime:380`、`GlobalDockService:160-162` |
| `navigation-audio-mode` | `value`:String = 混音模式 | `navigationAudio.setMode(value)`；失败 Toast「导航混音模式不可用或原车未确认变更」 | `LauncherRuntime:381` |
| `calendar-access` | 无 | `READ_CALENDAR` 未授权 → 申请权限（requestCode 4105），已授权 → `rt.publish()`。**只在主窗口链生效** | `MainActivity:268-273` |
| `calendar-refresh` | 无 | `calendar.refresh()` + `publish()` | `LauncherRuntime:382` |
| `weather-forecast-refresh` | 无 | `weather.refreshForecast()`（不 publish，由天气源自己回调） | `LauncherRuntime:383` |
| `debug-refresh` | 无 | `debugBridge.refresh()` | `LauncherRuntime:391` |
| `debug-adb` | `enabled`:Boolean | `debugBridge.change(false, enabled)` | `LauncherRuntime:392-394` |
| `debug-network` | `enabled`:Boolean | `debugBridge.change(true, enabled)` | `LauncherRuntime:392-394` |

### 6.4 开机计划 / 无线 adb

| action | 需要的参数 | 效果 | 实现位置 |
| --- | --- | --- | --- |
| `boot-launch-enabled` | `enabled`:Boolean | 总开关 | `LauncherRuntime:349-351` |
| `boot-launch-add` | `value`:String = 包名/id；`zone`:String = 延迟秒数 | `zone` 解析成 int，必须 `0..600`（`BootLaunch:22`），否则 Toast「启动秒数需在 0 到 600 之间」；已存在或超过 12 条（`BootLaunch:23`）→ Toast「计划已存在或已达到 12 条上限」 | `LauncherRuntime:352-360` |
| `boot-launch-remove` | `value`:String = 计划 id | 不存在 Toast「计划已不存在」 | `LauncherRuntime:361-364` |
| `boot-launch-clear` | 无 | 清空全部计划 | `LauncherRuntime:365-367` |
| `boot-launch-run` | `value`:String = 计划 id | 演示模式 Toast「演示模式不启动应用」；不存在 Toast「计划已不存在」 | `LauncherRuntime:368-372` |
| `wireless-adb-enabled` | `enabled`:Boolean | 写开关（`WirelessAdb`），开机时按 20s 间隔重试排程 | `LauncherRuntime:373-375`、`570-575` |
| `wireless-adb-run` | 无 | `wirelessAdb.ensureNow()` 立即尝试 | `LauncherRuntime:376-378` |

### 6.5 垃圾清理

| action | 需要的参数 | 效果 | 实现位置 |
| --- | --- | --- | --- |
| `cleaner-scan` | 无 | 后台扫描（`StorageCleaner.scan`） | `LauncherRuntime:405`、`StorageCleaner:160` |
| `cleaner-clean` | `value`:String = 逗号分隔类目 id | 白名单/数量在 `StorageCleaner` 内二次校验；空选或含未知 id → 整条作废并写 `error`（不抛异常）；正在扫描时拒绝 | `LauncherRuntime:406`、`StorageCleaner:178-195` |
| `cleaner-cancel` | 无 | 取消当前扫描/清理（`cancel` 标志） | `LauncherRuntime:407`、`StorageCleaner:197` |
| `cleaner-grant` | 无 | 有 PermissionHost 就借主窗口弹一次系统权限框，否则 `cleaner.refreshPermission()` | `LauncherRuntime:409-413` |
| `cleaner-permission` | 无 | 直接 `cleaner.refreshPermission()`（重新读授权态，已授权则自动开扫） | `LauncherRuntime:414`、`StorageCleaner:202-206` |

### 6.6 文件传输 / 夸克网盘

| action | 需要的参数 | 效果 | 实现位置 |
| --- | --- | --- | --- |
| `transfer-start` | 无 | 启动局域网传输服务 | `LauncherRuntime:415` |
| `transfer-stop` | 无 | 停止传输服务（与上一行同一行代码，两个分支） | `LauncherRuntime:415` |
| `transfer-install` | `value`:String = 文件名 | 安装该文件；失败 Toast「未找到可安装的文件，或系统未允许安装」 | `LauncherRuntime:416` |
| `transfer-delete` | `value`:String = 文件名 | 删除文件 | `LauncherRuntime:417` |
| `transfer-link-download` | `value`:String = 链接任务 id | 车机侧发起下载；失败 Toast「链接无效或任务已不存在」 | `LauncherRuntime:419` |
| `transfer-link-remove` | `value`:String = 链接任务 id | 移除链接任务 | `LauncherRuntime:420` |
| `transfer-text-remove` | `value`:String = 文本 id | 移除一条共享文本（剪贴板写入由 Dart 做） | `LauncherRuntime:422` |
| `transfer-text-clear` | 无 | 清空共享文本 | `LauncherRuntime:423` |
| `quark-login` | 无 | 开始扫码登录（`quark.startLogin()`） | `LauncherRuntime:425` |
| `quark-login-refresh` | 无 | 与 `quark-login` **同分支别名**（轮询刷新也走这里） | `LauncherRuntime:425` |
| `quark-logout` | 无 | 登出 | `LauncherRuntime:426` |
| `quark-open` | `value`:String，格式 `fid` 或 `fid|name` | 按 `|` 切分后 `quark.open(fid, name)`；无 `|` 时 name 为空 | `LauncherRuntime:427-432` |
| `quark-list` | `value`:String = 目录 fid | `quark.open(value,"")` | `LauncherRuntime:433` |
| `quark-more` | 无 | 加载下一页 | `LauncherRuntime:434` |
| `quark-enqueue` | `value`:String = 逗号分隔 fid | 入队下载；返回 0 件时 Toast「没有可下载的文件，或夸克登录已失效」 | `LauncherRuntime:435-438` |

---

## 7. 参数校验：改代码最容易踩的地方

### 7.1 `saveDesign` 的全套白名单（`LauncherRuntime:242-287`）

任何一条不通过 → 返回 `false`（不抛异常），Dart 侧抛 `StateError('保存未完成')`（`native_gateway:51-52`）。

| 字段 | 允许值 / 约束 | 行号 |
| --- | --- | --- |
| 原文长度 | ≤ 65536 字符 | `242`（`if(raw==null||raw.length()>65536)return false;`） |
| `version` | `4..6` | `246-247` |
| `preferences.custom` | 必须匹配 `#[0-9a-fA-F]{6}` | `247` |
| `preferences.themeStyle`（缺省 `classic`） | `classic`、`blueGlass`、`nocturne` | `249-250` |
| `preferences.pageTransition`（缺省 `none`） | `none`、`fade`、`slide`、`zoom`、`depth` | `251-252` |
| `preferences.mode` | `smart`、`system`、`dark`、`light`（无缺省值，缺失即 `""` → 拒绝） | `253` |
| `preferences.wallpaper`（缺省 `gradient`） | `gradient`、`coastal`、`graphite`、`dawn`、`neon`、`precision`、`terrain`、`custom` | `254-255` |
| `preferences.wallpaperPath` | 长度 ≤ 1024 | `256` |
| `preferences.wallpaperLuminance` | 若存在必须是 `0..1` 的有限 double | `257-260` |
| `preferences.dockMusicProgressBackground` | 若存在必须是 `Boolean` | `261` |
| `preferences.wallpaperOverlay` | 若存在必须是 `Boolean` | `262` |
| `preferences.dockSize`（缺省 `large`） | `small`、`medium`、`large`、`extraLarge` | `263` |
| `preferences.palette` | `mint`、`blue`、`violet`、`amber`、`rose`、`custom`（无缺省值，缺失即 `""` → 拒绝） | `264` |
| `preferences.radius` | `0..40` | `265-266` |
| `pageCount` | `1..20` | `265-266` |
| `cards` | 数量 ≤ 200 | `267` |
| 每张卡 | `x≥0`、`y≥0`、`w≥1`、`h≥1`、`x+w≤12`、`y+h≤6`、`0≤page<pageCount` | `268-271` |
| `appNames`（仅 `version>=5` 且存在） | 条数 ≤ 300；key 非空且 ≤255；value ≤96；都不含 `\n`/`\r` | `272-280` |

通过后写 `prefs.savedDesign`（`editor.apply()`，异步落盘，`281-284`），并 `publish()` 一次（`286`）。

**Dart 侧生成方的对应约束**：`launcher_controller:339-346` 固定发 `version: 6`，键顺序为 `version`/`preferences`/`ambientLight`/`cards`/`pageCount`/`appNames`。注意 `ambientLight` 也在这份 JSON 里，但原生侧只校验上表字段，`ambientLight` 原样落盘、不做校验。

### 7.2 其它 action 的参数门槛

| action | 门槛 | 失败表现 | 行号 |
| --- | --- | --- | --- |
| `rename-app` | `zone` 非空、≤255、无换行；`value` ≤96、无换行 | 静默（返回已识别，不写盘、不 Toast） | `LauncherRuntime:293` |
| `select-player`／`select-navigation` | `value=="auto"` 或包可启动 | Toast「所选应用未安装或不可启动」 | `LauncherRuntime:308` |
| `memory-drive-mode-target` | `CommandPolicy.validDriveMode(value)` | Toast「该驾驶模式不可用于记忆」 | `LauncherRuntime:324` |
| `memory-start-stop-target` | `on`／`off` | Toast「启停记忆值无效」 | `LauncherRuntime:331` |
| `boot-launch-add` | 延迟 `0..600`；计划数 ≤12 | Toast（两处不同文案） | `LauncherRuntime:354-358`、`BootLaunch:22-23` |
| `seek` | `Long.parseLong(value)` 成功且 ≥0 | 静默 | `LauncherRuntime:462-463` |
| 驾驶模式取值 | `ECO`/`COMFORT`/`DYNAMIC`/`INDIVIDUAL`/`XC`/`HDC`/`PURE`/`HYBRID`/`POWER`/`RACE`/`ECO_HEV_PHEV`/`COMFORT_HEV` | 由 `OfficialCarCommand.driveMode` 再查一次映射，失败返 null → Toast | `CommandPolicy:26-27`、`OfficialCarCommand:26-35` |
| 空调 zone | `left`／`right` | 演示模式 `apply` 返 false → Toast「尚未连接空调，可从空调面板打开原车应用」 | `CommandPolicy:39`、`LauncherRuntime:459` |
| 空调 mode | `auto`／`ac`／`sync`／`recirc` | 同上 | `CommandPolicy:40-42` |
| 座椅等级 | 单字符 `0..3` | 同上 | `CommandPolicy:36-38` |
| 温度 / 风量 | 温度夹 `16..30`（步进 0.5）；风量夹 `1..7` | 静默夹取，不报错 | `CommandPolicy:43-44` |
| `cleaner-clean` | 逗号分隔、≤12 项、全部已知 id | 整条作废并写 `error` | `StorageCleaner:178-190` |
| `show-dock-panel` | `apps`/`climate`/`media`/`vehicle`/`navigation`/`music-picker`/`uni-menu`/`transfer`/`cleaner`（**无 recents**） | `showPanel` 直接 return，静默 | `GlobalDockService:352` |
| `open-recent-task` 等 | `value` 能 `Integer.parseInt` | 静默 | `GlobalDockService:418` |
| `action` 原文 | ≤ 8192 字符 | `error("invalid", …)` | `MainActivity:149`、`GlobalDockService:244` |
| `quark-open` | 用 `|` 分隔 `fid` 与 `name` | 无 `|` 时 name 为空串 | `LauncherRuntime:429-431` |

---

## 8. 已废弃 / 别名 / 不存在的名字

### 8.1 别名与共分支

| 名字 | 关系 | 位置 |
| --- | --- | --- |
| `hide-navigation` / `global-navigation` | 同一段代码的两个独立分支，写的是**两个不同的 prefs 键**（`hideNavigation` vs `globalNavigation`），互不覆盖。`global-navigation` 多一道 `WRITE_SECURE_SETTINGS` 门槛，拿不到权限时**提前 return**，连 `hide-navigation` 都不改 | `MainActivity:275-283` |
| `GlobalDockService` 内部的 `RESTORE_NAV` | 通知栏"显示系统导航栏"按钮复用了 `system-navigation-hidden`+`enabled:false`，不是独立 action | `GlobalDockService:515` |
| `quark-login` / `quark-login-refresh` | 完全同一分支（都 `startLogin()`） | `LauncherRuntime:425` |
| `debug-adb` / `debug-network` | 同一分支，唯一区别是 `change(isNetwork, enabled)` 的第一个参数 | `LauncherRuntime:392-394` |
| `transfer-start` / `transfer-stop` | 同一行代码的两个分支 | `LauncherRuntime:415` |

### 8.2 历史遗留 / 当前 Dart 未调用

以下 action 原生侧仍然实现，但当前 Dart 代码里**没有以字面量方式派发**（grep `command('…')`/`action('…')` 全量命中里没有它们）。改这块时要先判断是不是死代码：

| action | 现状 | 位置 |
| --- | --- | --- |
| `demo-mode` | 仍可用；Dart 未调用（`demo` 只在原生里由 `Build.FINGERPRINT`/`MODEL` 初始化，`LauncherRuntime:107`） | `LauncherRuntime:304-306` |
| `hide-navigation` / `global-navigation` | 仍可用（仅主窗口链）；设置页改用了 `system-navigation-hidden` | `MainActivity:275-283` |
| `navigation-audio-mode` | 仍可用；Dart 未调用 | `LauncherRuntime:381` |
| `cleaner-permission` | 由 `MainActivity` 的权限回调内部调用（`MainActivity:381,476`），Dart 不需要发 | `LauncherRuntime:414` |
| `desktop-page` | 仍可用；主窗口另有 `desktopPage` 通道方法（`MainActivity:139-144`），两者作用相近但后者"无事件" | `LauncherRuntime:301-303` |

### 8.3 长得像 action、其实不是（防止编造）

| 误当 action 的名字 | 真实身份 | 位置 |
| --- | --- | --- |
| `app-icons` | 图标磁盘缓存目录名 `cacheDir/app-icons` | `AppRepository:124` |
| `global-panel` | 快照里的 `hostMode` 取值（另一个是 `global-dock`），不是命令 | `GlobalDockService:345`、`launcher_controller:76` |
| `all-apps` | 底栏小组件的**本地 UI 动作 id**，onTap 直接调 `controller.home` | `app/lib/widgets/bottom_dock.dart:210` |
| `select-online` / `select-bluetooth` | `OfficialMediaBridge` 回调里的内部分支，由原车媒体中心触发 | `MediaAdapter:137-139` |
| `empty-dir` | 清理规则里的 `check` 名 | `StorageCleaner:488` |
| `capture-enable` | `Visualizer` 失败时抛出的异常消息 | `SpectrumBridge:241` |
| `face-defrost` / `floor-defrost` / `floor-face` | 吹风模式的**读回标签** | `OfficialCarContract:205-207` |
| `dock-panel` / `panel` / `recents` | 面板 kind 的取值，只能作为 `show-dock-panel` 的 `value`；`recents` 不在白名单内 | `GlobalDockService:352,402` |

---

## 9. 待确认

- 待确认：`official-widget` 的 `value`（原厂 type）完整枚举——由 `OfficialCatalog.providers/packageFor` 决定（`OfficialCatalog:42,52`），本次未逐条列出 type 常量。
- 待确认：`open-system-setting` 的 `value`（设置入口 id）完整枚举，见 `SystemSettingsRepository.open`（`SystemSettingsRepository:253`），未逐条核对 id 常量。
- 待确认：`navigation-audio-mode` 的合法取值集合，见 `NavigationAudioAdapter.setMode`（`NavigationAudioAdapter:69`），未逐条列出。
- 待确认：`cleaner-clean` 的类目 id 全表（`StorageCleaner.parseSelection` 内），本文只确认了"逗号分隔、≤12 项、未知 id 整条作废"这一层。
- 待确认：`transfer-install`／`transfer-delete` 的 `value` 是文件名还是 id——`LanTransfer.install(String name)`／`delete(String name)` 形参名为 `name`（`LanTransfer:829,853`），但 Dart 侧上传值的构造未逐行核实。

---

## 本文依据

- `app/android/app/src/main/java/xyz/i4o/uni/launcher/LauncherRuntime.java`（全文 662 行，`handleOnMain` 288-482 为主）
- `app/android/app/src/main/java/xyz/i4o/uni/launcher/GlobalDockService.java`（全文 536 行，`handleCommand` 89-164、`showPanel` 351-363、`handleRecentTask` 417-439）
- `app/android/app/src/main/java/xyz/i4o/uni/launcher/MainActivity.java`（全文 510 行，`handle` 262-287、`onRequestPermissionsResult` 380-382）
- `app/android/app/src/main/java/xyz/i4o/uni/launcher/core/CommandPolicy.java`、`core/ClimateState.java`
- `app/android/app/src/main/java/xyz/i4o/uni/launcher/BootLaunch.java`（常量与 `add/remove/runNow` 签名）
- `app/android/app/src/main/java/xyz/i4o/uni/launcher/integration/StorageCleaner.java`、`MediaAdapter.java`、`OfficialCarCommand.java`、`OfficialCarContract.java`、`AppRepository.java`
- `app/lib/platform/native_gateway.dart`、`app/lib/controller/launcher_controller.dart`、`app/lib/widgets/bottom_dock.dart`

action 名清单通过两道交叉检索确认：①对 `app/android/app/src/main/java/**/*.java` 检索 `"[a-z0-9-]+"\.equals\((action|a)\)`（得到全部比较点）；②对 `app/lib/**/*.dart` 检索 `(command|action)\('([a-z0-9-]+)'`（得到 Dart 侧派发点），两者差集即 §8.2 的"原生有、Dart 未调用"。
