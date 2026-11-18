# HOME 键与「回首屏」

## 语义

| 入口 | 走哪条 | 结果 |
| --- | --- | --- |
| 车机 HOME 键（系统 HOME intent） | `onNewIntent` → `dispatchIntent()` → `dispatchHomeFirst("intent")` | 收起面板、关设置页、退出编辑、路由回根、回第一屏 |
| 车机把 HOME 当普通按键派发（原车输入通道直派） | `MainActivity.dispatchKeyEvent` 认 `KEYCODE_HOME` → `dispatchHomeFirst("window")` | 同上，并吞掉按键 |
| 桌面窗口被复用（`rehost`，非 HOME） | Flutter `home` | 关设置页，**保留原页码** |

原生侧两条 HOME 路径都走 `MainActivity.dispatchHomeFirst()`：

```java
UniLog.event(LogTags.APP,"HOME 回首屏","channel",via,...);
GlobalDockService.dismissPanelNow("home");          // 全部应用/最近任务/媒体/空调面板
channel.invokeMethod("home-first",null);            // 设置页/路由/页码
```

Dart 侧 `LauncherController.homeFirst()` = `home(resetPage: true)`：

- `settings = false` → 设置页关掉；
- `editing` 时先 `finishEdit()`（已提交布局保留），不再像以前那样直接 return；
- `popToLauncherRoot()` → 全部应用、最近任务这类压在桌面上的 **路由** 全部退掉；
- `command('dismiss-dock-panel')` → 兜住「面板走的是全局底栏独立窗口」那种情况；
- `_setPage(0)` → 应用抽屉（末页）与第二、三页都退回第一屏。

## 为什么面板要在原生侧收两次

「全部应用」「最近任务」有两条实现：全局底栏的**独立 overlay 窗口**（`GlobalDockService`，
窗口标题 `UNI Global Panel`），和桌面窗口内的 **Flutter 路由**（底栏没在跑时的退路）。前者
盖在 Activity 上面，只把桌面翻回第一页没用 —— 窗口还在最上面。所以：

- 原生 `dispatchHomeFirst` 直接 `GlobalDockService.dismissPanelNow()`（不等 Dart 往返）；
- Dart 侧再 `dismiss-dock-panel` + `popToLauncherRoot()` 兜住路由和竞态。

## 为什么还要认 KEYCODE_HOME

AOSP 的 `PhoneWindowManager.interceptKeyBeforeDispatching` 会在派发前把 HOME 吞掉（直接
`launchHome`），所以手机上 `dispatchKeyEvent` 基本收不到 HOME —— 雷电实测走的是 **intent 路径**
（logcat 里是「分发入口请求 target=home」）。但把 HOME 当普通键下发的车机（含原车输入通道直派）
会走到 `dispatchKeyEvent`，能收到就必须自己处理，否则在设置页里按 HOME 毫无反应。

## 验证

```sh
# 1. 设置页打开着，按 HOME
adb shell input keyevent 3
adb logcat -d | grep 'UNI/App' | grep -E 'HOME 回首屏|分发入口'
adb logcat -d | grep 'UNI/UI'  | grep '返回桌面'      # 期望 resetPage=true

# 2. 滑到第二页/抽屉页，按 HOME
adb shell am start -a android.intent.action.MAIN -c android.intent.category.HOME

# 3. 确认桌面仍是默认 HOME
adb shell cmd package resolve-activity --brief -a android.intent.action.MAIN -c android.intent.category.HOME
```

雷电（Android 9，1920×1080）实测：

- 设置页 → `input keyevent 3` → 回第一屏，页码指示器回到第一个点；
- 第 3 页（添加卡片页）→ HOME intent → 回第一屏；
- 全部应用（全局底栏面板）→ HOME → 面板收起 + 回第一屏，日志「HOME 收起面板 panel=apps」；
- 最近任务（全局底栏面板）→ HOME → 面板收起 + 回第一屏，日志「HOME 收起面板 panel=recents」；
- logcat：`分发入口请求 target=home` + `HOME 回首屏 channel=intent` + `回桌面 resetPage=true`。

> 雷电上点底栏按钮要按 `y+61`（底栏是 overlay 窗口，输入坐标比 Flutter 坐标低 61px）；
> 另外 `cmd package set-home-activity xyz.i4o.uni.launcher/.MainActivity` 先设成默认桌面，
> 否则按 HOME 会弹「选择桌面」。

## 车机实体 HOME（领克 05 / IP753，192.168.22.198）

屏幕上那颗带指纹的圆形键，按下时 Android 侧**看不到任何输入事件**：

- `/dev/input/event0..3` 里没有 `KEY_*`（`getevent -lt` 全设备监听，只有触摸）；
- 没有 `KEYCODE_HOME` 派发给窗口，没有 `CLOSE_SYSTEM_DIALOGS` 广播，没有 HOME intent。

真相在 VHAL 日志里：

```
I VHAL.InputHandler: injectKeyCode(0, 3, 0)   ← 按下，keyCode 3 = KEYCODE_HOME
I VHAL.InputHandler: injectKeyCode(1, 3, 0)   ← 抬起
```

即：圆键由 VHAL 直接注入标准 `KEYCODE_HOME`，但事件在派发层就被原车输入通道
（OEM 桌面那条路）截走了，到不了应用。解决办法是**像方控一样把它申请回来**：
`SteeringKeyPolicy.interceptKeys()` 里加上 `KEY_HOME = 3`（以及 ECARX 私有码
`PANEL_HOME = 300001`），原车就放行了：

```
I UniSteeringKeys: granted=200085,200087,200088,210005,85,3,300001,300002 requested=12
I UniSteeringKeys: start ok=true mode=adaptapi accepted=8 reason=已接入原车方控输入（8 个键）
I UniSteeringKeys: key=3 action=home n=1
I UNI/App: [EVT] HOME 拉起桌面 hasFocus=false
I UNI/App: [EVT] HOME 回首屏 channel=input
I UNI/UI : [EVT] 返回桌面 resetPage=true
```

**只截到键还不够**：桌面当时被第三方应用盖着，只重置页码/收面板用户看不到任何变化，
表现依旧是「按 HOME 没反应」。所以 `MainActivity.requestHomeFirst()` 先
`bringSelfToFront()`（`NEW_TASK|CLEAR_TOP|SINGLE_TOP|REORDER_TO_FRONT` 拉起自己），
再走「回首屏」。

排查过程中留下的诊断开关：

- `adb logcat -s UniSteeringKeys:V`：放行清单 + 每个键第一次出现的码值与动作；
- `adb logcat -G 8M`：车机每秒刷 VHAL 日志，默认缓冲区会把几十秒前的行挤掉，
  查这类「按一下」问题先把缓冲调大，或者在按之前 `logcat -c`；
- `analysis/keyprobe/`：独立探测 APP（`xyz.i4o.keyprobe`），四通道同时监测
  （窗口派发 / ECARX 适配层 / binder 回调 / 系统广播）。注意它**没有** ecarx oem
  签名权限，车上那两条 ECARX 通道会报 `Failed to find IInputManager`，
  实际只剩「窗口派发」这一条有效。装法：`adb install -r analysis/keyprobe/keyprobe.apk`。

## 注意

- 这一改动把「从第三方应用按 HOME 回桌面」的落点从「离开时那一页」改成了「第一屏」。如果哪天
  想恢复原行为，把 `MainActivity.dispatchIntent()` 里那行的 `"home-first"` 换回 `"home"` 即可，
  键路径不受影响。
- 全局底栏（`GlobalDockService`）那条走 `command('show-home')`，不受这里影响。
