# 歌词投到仪表盘（副屏投射）

参考应用（`com.zuoqirun.lyricscompanion` 20261021-7902e14）确实有这个功能。这一份文档写清楚它到底怎么做的、UNI 里对应实现在哪、以及上车验证的顺序。

结论先说：**它不是"把歌词发给仪表"，而是把歌词窗口加到仪表那块屏幕自己的窗口管理器上。** 全程不需要车厂接口、不需要另一台设备、不需要投屏协议。

---

## 1. 参考应用的做法（带行号证据）

反编译源码在 `_apk/jadx/sources/com/zuoqirun/lyricscompanion/`。

| 步骤 | 代码位置 | 做了什么 |
| --- | --- | --- |
| 拿到屏幕管理服务 | `LyricsDisplayService.java:318` | `getSystemService("display")` |
| 枚举全部屏幕 | `LyricsDisplayService.java:1268`（`DisplaySettingsActivity`）与 `SecondaryDisplayResolver.resolve` | `getDisplays(DISPLAY_CATEGORY_PRESENTATION)`，再退化为"所有 id > 0 的屏幕" |
| 为目标屏幕建 Context | `LyricsDisplayService.java:550` | `createDisplayContext(targetDisplay)` — 这个 Context 的 `WINDOW_SERVICE` 属于那块屏幕 |
| 取那块屏幕自己的窗口管理器 | `LyricsDisplayService.java:551` | `(WindowManager) ctx.getSystemService("window")` |
| 加窗口（副屏） | `LyricsDisplayService.java:578` | `wm.addView(view, params)`，`type = SDK ≥ 26 ? TYPE_APPLICATION_OVERLAY(2038) : TYPE_PHONE(2002)`，`format = -3`（TRANSLUCENT） |
| 窗口参数 | `LyricsDisplayService.java:983`（`overlayParams`）、`OverlayTouchGeometry.windowFlags()` | `16778024` = `FLAG_NOT_FOCUSABLE(0x8)` + `FLAG_NOT_TOUCH_MODAL(0x20)` + `FLAG_LAYOUT_IN_SCREEN(0x100)` + `FLAG_LAYOUT_NO_LIMITS(0x200)` + `FLAG_HARDWARE_ACCELERATED(0x1000000)` |
| 记住是哪个屏幕 | `DisplaySlotRegistry` | prefs 键 `extra_displays`，条目为 `name\u0001id\u00011`；`chooseIndex` 先按 name+id 精确匹配，再按唯一名字，最后按 id |
| 每个屏幕独立配置 | `DisplaySlotContext` | prefs 名 `lyrics_companion_display<N>` |
| 屏幕尺寸/密度 | `DisplaySettingsActivity:1248` | `createDisplayContext(targetDisplay).getResources().getDisplayMetrics().density` — **用目标屏幕自己的密度，不是手机/主屏的** |
| 屏幕变化 | `LyricsDisplayService` 的 `DisplayListener` | 增删改都重新解析，失败按指数退避重试 |

两个关键点，很多"投屏"方案就是死在这两条上：

1. **必须用 `createDisplayContext`，不能用 Activity 自己的 WindowManager。** 用主 Context 加窗口，窗口永远落在主屏上，`params.x/y` 再怎么调也只是在主屏上乱跑。
2. **必须查那块屏幕的 density。** 主屏 240 dpi、仪表 320 dpi 的情况很常见，用错密度字号会差三成。

参考应用里 `FullscreenLyricsActivity` **没有**做屏幕定向 —— 它只做全屏歌词，不参与副屏投射。别被名字误导。

---

## 2. UNI 里的实现（已落地并通过编译/测试）

| 文件 | 作用 |
| --- | --- |
| `app/android/.../integration/display/DisplayPicker.java` | 纯函数选屏逻辑：id 命中 → 唯一名字命中 → 否则 `NONE`。歧义时**不猜**，因为猜错就是把歌词糊到副驾屏或倒车影像上 |
| `app/android/.../integration/display/ClusterPanelGeometry.java` | 纯排版数学（无 Android 类型）：`width/height/origin` 把「面板中心 = 屏幕百分比」换算成窗口像素，并把面板收在屏内。设置页预览与服务端共用同一组常数 |
| `app/android/.../integration/lyrics/LyricCast.java` | 进程内广播牌：`publish(title, artist, sourceLabel, timeline, playing, positionMs, sampledAtMs, speed)` / `state()` / `cursorAt(nowMs)`。投射窗口没有自己的快照通道，靠它取数据 |
| `app/android/.../integration/display/ClusterLyricsView.java` | 纯 `View` + Canvas：上一句 / 当前句 / 翻译或下一句三层字号与透明度；逐字填充边缘走渐变而不是硬切；间奏画三点脉冲；`style` 支持胶囊底板 / 纯文字 / 发光 |
| `app/android/.../integration/display/ClusterLyricsService.java` | `Service`：解析目标屏幕 → `createDisplayContext` → `addView`（绝对定位）→ `Choreographer` 帧循环（**只在播放时跑**）→ `DisplayListener` 重连 + 指数退避；`restyle()` 用 `updateViewLayout` 原地改位置/字号/配色，拖动预览时不重建窗口 |
| `app/android/.../integration/MediaAdapter.java` | 快照里加 `LyricCast.publish(...)`，一次 `System.currentTimeMillis()` 同时喂桌面卡片和仪表窗口，保证两边填充边缘一模一样；`started()` 让投射服务判断要不要自己拉起适配器 |
| `app/android/.../LauncherRuntime.java` | `pumpMediaCast()` / `releaseMediaCast()`：只取媒体分组、不扫应用，供投射服务在**没有 Flutter 监听者**时取歌词 |
| `app/android/.../MainActivity.java` | 通道方法 `clusterLyricsDisplays` / `clusterLyricsStatus` / `clusterLyricsApply`（整个 Map 原样转交）；`onCreate` 里按已存偏好兜底重启服务 |
| `app/lib/platform/cluster_lyrics.dart` | Dart 侧客户端：`displays()` / `status()` / `apply()`，`MissingPluginException` 与 `PlatformException` 都降级为空而不抛 |
| `app/lib/model/cluster_layout.dart` | `ClusterPanelGeometry` 的 Dart 孪生：预览框的像素换算、拖拽 → 比例、边界收拢 |
| `app/lib/widgets/cluster_lyrics_settings.dart` | 设置页「仪表投屏」：开关、屏幕列表、**可拖动的位置预览框**、行数 1/2/3、宽度 50–100%、字号 5 档、6 个高亮色、3 种样式、底板开关、失败原因与歌词行数回显（每 2s 轮询） |
| `app/lib/screens/settings_screen.dart` | 左侧标签栏注册（氛围灯之后） |
| `app/android/app/src/main/AndroidManifest.xml` | `<service android:name=".integration.display.ClusterLyricsService" android:exported="false"/>` |

### 为什么是原生 View 而不是第二个 Flutter engine

副屏窗口里跑 Flutter 要再起一个 engine、再走一遍插件注册，而它对这块屏幕的 `DisplayMetrics` 还得再单独喂一次。这段内容只有三行文字，Canvas 画一遍是几十微秒。用 View 的另一个好处是：窗口没有自己的快照通道，直接从进程内的 `LyricCast` 读，两边不会有两套时钟。

### 数据从哪来

```
MediaAdapter.snapshot()            // 媒体会话 → 标题/歌手/时长/位置/速度
  └─ LyricTimelineProvider.resolve(...)   // 时间轴（内嵌 LRC / 磁盘缓存 / 在线目录）
       ├─ snapshot.lyricTimeline (JSON)   → Flutter 歌词卡片（同一份文档，0.7.8 起）
       └─ LyricCast.publish(State)        → ClusterLyricsService → 副屏 Canvas
```

所以仪表上的逐字高亮和桌面卡片上的**是同一个 `sungPrefix()`**（Java 侧 `LyricTimeline.Cursor.sungPrefix()`，Dart 侧 `LyricCursor.sungPrefix`），不是两份各自估算的实现。0.7.8 起连"拿哪份歌词"也统一了：卡片优先 `lyricTimeline`，`snapshot.lyrics` 只在没有时间轴时兜底。之前卡片读原始 LRC 文本、面板读时间轴，同一时刻会显示不同句子——`docs/interface/05-副屏投射.md` 第 8 节「两份歌词文档」有完整复盘。

### 投射服务自己取数（0.7.7 起）

`MainActivity.publish()` 在 `sink == null` 时直接返回（`MainActivity.java:301`），而车上用户几乎一直在音乐 app 全屏。只靠快照喂 `LyricCast`，仪表会停在"打开桌面那一刻"的那一句——**这就是"看起来没接入歌词"的真正原因。**

现在 `ClusterLyricsService` 自己按 700ms 节奏调 `LauncherRuntime.pumpMediaCast()`（`ClusterLyricsService.java:376` → `LauncherRuntime.java:171`）：只取媒体分组、不扫应用、不构建设置目录；适配器被 `stop()` 过（Flutter 最后一个监听者撤掉时会发生）会先 `start()` 回来。停投时 `stopFeed()` 走 `releaseMediaCast()`，不留下一个只为投射开着的媒体监听。

---

## 3. 上车验证顺序

按这个顺序走，第 1 步就能判定这台车到底能不能投。

1. **看屏幕列表**：设置 → 仪表投屏。列表为空 → 这块屏幕没有向应用暴露，后面都不用试了（仪表由独立 SoC/总线驱动，第三方画不上去）。
2. **只看到 1 个屏幕**：仪表没暴露。退路是第 4 节。
3. **看到多个屏幕**：点一个 id > 0 的，看仪表是否出现文字。位置不对就回「位置与大小」**直接拖预览框里的歌词块**：松手即保存为屏幕百分比，服务端立刻 `updateViewLayout` 生效，不用重启、不用重装、不用改代码。
4. **看不到但日志有 `attached`**：说明窗口加到了别的屏（比如副驾屏）。回设置页换一个。
5. **完全没有反应**：看设置页那行"报告"文字。它区分了四种失败：
   - `已投射 · <屏幕名> · ID <n>` — 加窗口成功
   - `投射失败 · display-changed:BadTokenException` — 权限/窗口 token 问题（缺 `SYSTEM_ALERT_WINDOW` 或屏幕已在销毁）
   - `投射失败 · service-created:no-target` — 没解析到目标屏幕（第 1、2 条）
   - `后台启动被系统拒绝，回到桌面再试` — Android 8+ 后台限制，从前台点开关重试

`logcat` 过滤：`adb logcat -s ClusterLyricsService`（服务本身不打日志时，可用 `adb shell dumpsys window displays` 看窗口落到了哪个 display）。

---

## 4. 兜底路线（仪表没暴露时）

按代价从低到高：

**A. 自建 VirtualDisplay，把桌面内容镜像过去**
UNI 已经有这套底座：`integration/platform/LiveNavigationHost.java` 里 `createVirtualDisplay(VIRTUAL_DISPLAY_FLAG_PUBLIC | OWN_CONTENT_ONLY, ...)`，并用反射进 `ActivityManager` 把 task 在 display 之间搬。用法是：建一个 VirtualDisplay，`setSurface` 到目标屏幕的 Surface（如果有 `DisplayManager` 拿得到的 `Surface`），再把 `ClusterLyricsView` 画进去。
限制：目标屏幕的 Surface 通常也拿不到，除非是 `Presentation` 场景。

**B. `Presentation` 对话框**
如果屏幕以 `DISPLAY_CATEGORY_PRESENTATION` 暴露，`Presentation(displayContext, display)` 是官方支持的写法，不需要悬浮窗权限。缺点是它会拿到自己的窗口（有焦点语义），在车机上可能盖住仪表原有内容。
UNI 里没走这条，因为悬浮窗方案在参考应用上已验证可用，而且不抢焦点。

**C. 把 Activity 定向到那块屏幕**
`ActivityOptions.setLaunchDisplayId(displayId)`（API 26+）或 `startActivity` 前设置。适合"整屏换成 UNI 歌词界面"，不适合叠加。
适合场景：仪表本身允许第三方整屏接管（少见）。

**D. 车厂通道**
`com.ecarx.oem.*` 之类。UNI 清单里已经有 `ecarx.oem.permission.*` 一批权限，但具体有没有"副屏文字注入"接口取决于车型，需要抓原厂 APK 才能确认。这条是唯一能"写进仪表原生区域"的路，也是唯一要车厂配合的路。

---

## 5. 验证记录

已跑过的检查（全部通过）：

```
javac（android-28 + org.json + flutter embedding + androidx）
  → 全部 87 个 java 源文件（另加 2 个 R/BuildConfig 桩）编译通过，exit 0

JUnit（全部 9 个测试类）
  → OK (61 tests)；org.json 必须排在 android.jar 之前，否则命中的是 android 里的 Stub!

flutter analyze（整个 app）
  → No issues found!

flutter test（整个 app）
  → All tests passed! (446 tests)
```

新增测试覆盖的行为：
- `DisplayPickerTest`：id 优先、改名后按名字找回、同名多屏不猜、主屏永不作为目标、行文案格式
- `ClusterPanelGeometryTest`（新，6 条）：宽度上下限、行高与行数、**比例是面板中心而非左上角**、面板永不出屏、默认 62% 与旧硬编码位置重合、NaN/越界回落
- `LyricCastTest`：播放时按倍速推进、暂停时定格、无词时清空上一首（不残留）、`sungPrefix()` 与 Dart 侧一致
- `cluster_lyrics_test.dart`：通道契约（`displayId`/`displayName` 成对下发）、位置/样式/行数/高亮色全量下发、`status` 回传 `lyricLines` 与 `lyricSummary`、缺省降级
- `cluster_layout_test.dart`（新，7 条）：与 Java 侧同一组数字、拖拽比例可回读、预览块按真实密度缩放、NaN 回落
- `cluster_lyrics_settings_test.dart`（10 条）：列表渲染、空列表如实说明、点屏即生效、开关关闭不带目标、**预览块落在存储的比例上**、拖拽后比例被保存、行数/宽度/样式/高亮色各自下发、重置回默认、头部显示歌词行数、纯点击不挪面板

### 设备实测（雷电模拟器 LDPlayer 9，Android 9 / 1920×1080，debug 包）

| 项 | 实测值 |
| --- | --- |
| 存储 | `xRatio=0.5 yRatio=0.72 widthRatio=0.86 fontSp=44 rows=3` |
| `dumpsys window windows` | `mAttrs={(135,671)(1651x214) gr=TOP START CENTER ty=APPLICATION_OVERLAY fmt=TRANSLUCENT}` |
| 复算 | `x=round(1920*0.5)-1651/2=135`、`y=round(1080*0.72)-214/2=671`、`h=44*1.62*3=214` —— 逐位一致 |
| `status.report` | `已投射 · 内置屏幕 · ID 0 · 网易云音乐 38 行` |
| 歌词内容 | 曲目「底牌 / 框框」，`LyricCatalog` 走网易云取到 38 行，面板上实测出现「那些幸福 也关于痛的例外」「也许爱 太多的无奈」等真实歌词 |
| 拖动预览 | `adb shell input swipe 1135 756 1000 660` → prefs `xRatio=0.43 yRatio=0.3388`，窗口随即变成 `mAttrs={(1,259)(1651x214)}`（`1≈round(1920*0.43)-825`、`259=round(1080*0.3388)-107`），进程没重启 |
| 回到中间 | 点一次 → prefs `0.5 / 0.62 / 0.94`，窗口 `mAttrs={(58,563)(1805x214)}`（`1805=round(1920*0.94)`、`58=960-902`、`563=670-107`） |

---

### 踩过的坑：面板停在"当前音源未提供歌词"

现象：status 明明回 网易云音乐 · 64 行 · 每天每天，桌面卡片也在滚词，只有副屏面板一直写"当前音源未提供歌词"。

成因是帧循环自己把自己关了。换歌那一瞬间 MediaAdapter.publish() 带的是新标题 + 空时间轴（在线目录还在请求中），面板画出"当前音源未提供歌词"后，	ick() 里的 if (state.playing && state.hasTimeline()) 为假 —— 不排下一帧。700ms 后时间轴到了，LyricCast 换了新 State，但**没有任何人重新起帧**，于是窗口停在那一句话上，直到用户关一次再开一次投射。

修法（ClusterLyricsService）：

- 	ick() 记下 lastDrawn，不再用 handler.postDelayed(this::startFrames, …) 而是 startFrames()（rameScheduled 在 doFrame 里已经置回 false，不会卡住）；
- 700ms 的 pump() 兼当看门狗：if (panel != null && LyricCast.state() != lastDrawn) startFrames();
- 空态文案分三种：无曲目 → 等待播放；播放中但时间轴未到 → 正在获取歌词；暂停且无时间轴 → 当前音源未提供歌词。

实测：进程被杀后重新拉起（时间轴必然晚到），面板在 2 秒内从"正在获取歌词"翻到真实歌词「我们在一起像old friend / 分享生活里的一切 / 我知道你每个笑」。

### 踩过的坑：卡片有词、面板只有三个点

现象：同一秒里桌面卡片高亮「编曲 : 方大同」，副屏面板只有一行省略号状的三个点。

成因不是渲染，是数据：卡片读 `snapshot.lyrics`（`[00:00.00] 作词 : 娃娃` 这种带 credit 的 LRC），面板读 `snapshot.lyricTimeline`（网易云 KRC，第一行 `t=17560`，压根没有 credit 段）。于是 0–17.5 秒卡片有内容、面板在间奏。再加上两份缓存的键不同（`round` vs `floor` 时长、不同的标题归一化），面板那份还经常是"未命中缓存 → 等网络"。

修法：

- `LyricsResolver.key` 委托 `LyricCatalog.key`（`LyricsResolver.java:177`），两个缓存同一把钥匙；
- 卡片优先读 `lyricTimeline`（`app/lib/widgets/lyrics_view.dart:63`、`Lyrics.fromTimeline`）；
- KRC 丢掉的 credit 段用 LRC 补在时间轴前面（`LyricTimeline.withLeadLines` + `LyricTimelineProvider.withLead`），逐字时间不变；
- 间奏时段画上一句（`Cursor.previous`）+ 三点 + 下一句（`Cursor.next`），不再只有点。

实测：切歌后 1.2 秒截图，卡片高亮行、面板首行、底部胶囊是同一句（`_apk/unify-12s.png`）；`java ... JUnitCore` 全套 `OK (63 tests)`。

## 6. 已知限制

- **只在播放时绘帧**（25 fps）。暂停时渲染最后一帧，不再唤醒 CPU。
- **逐字只有部分源有**：网易云 KRC 带 `w[]`（实测 `每天每天` / `底牌` 都是词级），QQ/酷狗/酷我 目前回 LRC（`wordTimed == false`），整行一次性变色。列表里能看到 `snapshot.lyricTimelineWords` 判定结果。
- **拖动有 12px 死区**：手指移动不超过 12 逻辑像素时面板不动，松手也不保存。否则在设置页顺手一戳就会把歌词挪走（`_CastPreviewState._deadZone`，`cluster_lyrics_settings_test.dart` 里"a tap does not move the panel, only a drag does"钉住了这条）。
- **预览框里的字比真机小**：预览按真实 `displayWidth` 与 `density` 等比缩放，1229×880 的副屏上 26sp 只占很窄一条，所以预览里给了 8px 的字号下限——高度仍按真实公式算，位置判断不受影响。
- **`report` 不是实时的**：它读静态字段，attach 是异步的，所以 `apply` 的返回值里 `report` 可能是上一轮结果。设置页每 2s 轮询一次 `status` 纠正，这也是「歌词行数」能一直变化的原因。
- **完全不拦截触摸**：`FLAG_NOT_FOCUSABLE | FLAG_NOT_TOUCHABLE | FLAG_NOT_TOUCH_MODAL`。少了 `NOT_TOUCHABLE` 时面板会吞掉自己那块区域的点击（投到主屏时最明显：点设置页标签、按钮没反应），加上之后手指直接穿到下面的应用。如果以后要做"点歌词跳转"，需要去掉 `FLAG_NOT_FOCUSABLE` 并自己处理点击区域 —— 参考应用的 `OverlayTouchGeometry` 就是干这个的，但车机上抢焦点风险高，默认不做。
- **屏幕 id 会变**：重启、休眠唤醒后 id 可能不同，所以持久化的是 name+id 成对，并且 `DisplayListener` 会重新解析。
- **AGPL-3.0**：参考应用与 Folia 素材是 AGPL。这里的 Java/Dart 是按相同线格式（KRC/QRC/MRC 的密钥与偏移）**独立重写**的，没有复制上游代码或素材。若之后要引入参考应用的图像资源，才需要处理许可问题。
- **在线歌词目录**（`LyricCatalog`）在无网时静默失败，仪表显示"当前音源未提供歌词"，不会编造时间轴。

---

## 7. 健康探针与心跳（2026-11 增补）

`ClusterLyricsService.pump()` 每 700 ms（`FEED_MS`）做四件事，顺序固定
（`ClusterLyricsService.java:381-404`）：

| # | 动作 | 条件 | 行号 |
| --- | --- | --- | --- |
| 1 | 拉一次媒体快照 | 始终 | `:382-385` |
| 2 | 状态看门狗 | `LyricCast.state() != lastDrawn` → `startFrames()` | `:396` |
| 3 | 心跳重绘 | 每 2 次 pump（≈1.4 s）→ `startFrames()` | `:397` |
| 4 | 附着探针 | `!healthy(panel)` 且距上次重挂 > 5 s → `reattach("health:…")` | `:398-402` |

`healthy = isAttachedToWindow() && getParent() != null`（`:410-416`），抛异常也算不健康。

两个不同的故障各由一个机制兜住：

- **窗口被摘掉**（车机重连、副屏热插、系统收回悬浮窗）：对象里还握着 view，画在一个已经死掉
  的 WindowManager 上 —— 状态页写着已开启，屏上什么都没有，日志里也没有。→ 探针负责重挂，
  5 s 节流避免把 WMS 打满。
- **换曲瞬间没有歌词**：新状态的 timeline 为空，帧循环按设计停住，上一首的词会留在玻璃上。
  → 心跳把它在 1.4 s 内改成「正在获取歌词」。

> 实测：清空 `files/lyric-timeline`、`files/media-lyrics` 后重启再跳曲，0.8 s 时卡片仍是
> 「当前音源未提供歌词」，≈2.4 s 时卡片与投屏已是同一份歌词并同步高亮（`_apk/cold-t1.png`、
> `_apk/cold-t2.png`）。歌词获取侧的并发/变体/直连/缓存策略见
> [LYRIC_PIPELINE_2026_11](LYRIC_PIPELINE_2026_11.md)。

