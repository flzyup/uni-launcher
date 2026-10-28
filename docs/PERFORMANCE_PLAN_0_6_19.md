# 0.6.19 性能深挖方案（老车机：MSM8996 / Adreno 530 / Android 9 / 1920 宽）

目标不是"再抠一点 setState"，而是把**每帧固定成本**和**冷启动成本**压下来。本轮已完成的 P0/P1/P2 见 [PERFORMANCE_0_6_18.md](PERFORMANCE_0_6_18.md)；本文是下一轮的挖掘结果与排序。

标注约定：**【测】**= 本机模拟器实测（`LX_1080p`，Android 10 x86_64，1920×1080，density 160，swiftshader 软件光栅，**不是车机**）；**【码】**= 代码事实（附 file:line）；**【估】**= 未测推断，必须在车上用第 6 节的脚本确认。

## 0. 现场数据

| 指标 | 数值 | 来源 |
| --- | --- | --- |
| 冷启动（release，COLD） | `Displayed +2896ms`，`am start -W TotalTime 2847ms` | 【测】 |
| 常驻内存 PSS | **112.2 MB**（Native Heap 54.0 MB、Java 6.5 MB、Unknown 21.3 MB） | 【测】单引擎 |
| 静止 10 秒出帧数 | 16 帧（≈1.6 fps），p50 5ms / p90 15ms | 【测】 |
| 翻页 raster p50 | 59–65 ms（slide/fade/depth 三档） | 【测】 |
| 关掉卡片阴影后 raster p50 | **54.0–54.5 ms**（三档一致下降 5–7ms） | 【测】 |
| 全量遥测包 | 805 KB（序列化 8.4ms / 解析 3.5ms） | 【测】 |
| 增量遥测包（0.6.18 后） | 694 B（0.10ms / 0.03ms） | 【测】 |
| `launcherTheme()` 每次调用 | 1.10–1.90 ms → 0.2 µs（已修） | 【测】 |

静止时只有 1.6 fps，说明**空闲基本不动**——这点比预期好，不该再往"减少空闲重绘"上花力气；要打的是**冷启动**和**每次卡片重绘/每帧的固定绘制成本**。

## 1. 优先级总表

| # | 项 | 现状 | 预计收益 | 风险 | 层 |
| --- | --- | --- | --- | --- | --- |
| 1 | 冷启动：图标链路移出主线程 + 落盘缓存 | 主线程同步编码 ~70 个 PNG | 冷启动 −0.6~1.2s，首包 805KB→~5KB | 低 | P0 |
| 2 | 卡片背景预烘焙（阴影+填充+边框 → `ui.Image`） | 每卡 37px 高斯模糊 | 单卡重绘 8–15ms → <1ms【估】；实测页面级 −5~7ms | 中（视觉需对照） | P0 |
| 3 | `GlassSurface` 去掉多余一层 `ClipRRect` | 双层裁剪 | 每卡每帧省一次 clip | 低 | P0 |
| 4 | 关闭 InkWell 涟漪/高亮 | 每次点击一层 300–600ms 动画 | 点击反馈帧成本 −2~5ms【估】 | 低（视觉） | P0 |
| 5 | glass 模式降级（每卡 `BackdropFilter`） | 每卡一次 sigma10 背景模糊 | glass 模式整帧 −10ms 以上【估】 | 中（视觉） | P0 |
| 6 | Impeller 后端 A/B（opengles / lazy-shader） | manifest 未设置，默认 Vulkan | 未知，可能整体 ±20% | 低（一行 meta-data） | P1 |
| 7 | 能量流动画不再常亮 | 1600ms 循环驱动 1300ms 动画 | 车机静止时不再 60fps 常亮 | 低 | P1 |
| 8 | 图像缓存预算下调 | 24MB/128 项 + 最近任务 12MB | PSS −20~30MB【估】 | 低 | P1 |
| 9 | 面板复用底栏引擎 | 两个引擎（同 group） | −10~20MB、少一个 raster 线程【估】 | 中 | P1 |
| 10 | 去掉全屏 `FittedBox` 1.2× | 整棵树被缩放 | 文本/图标不再重采样 | 高（设计契约断言） | P2 |
| 11 | 静态文案 const 化 / 文本高度固定 | 卡片重建即重排文本 | 中文排版成本下降 | 低 | P2 |
| 12 | HOME 常驻（不重建 Activity） | 冷启动每次都走完整引擎启动 | 回桌面 −1~2s【估】 | 中 | P2 |

## 2. P0 细节

### 2.1 冷启动 2.8s：图标链路是主嫌

【码】`AppRepository.refresh()`（`integration/AppRepository.java:29-52`）在 `LauncherRuntime` 构造期**同步**做四件事：

1. `queryIntentActivities` 取全部可启动应用；
2. 排序比较器里**每次比较调用两次 `loadLabel`**（`:34-36`）——这是跨进程 IPC，70 个应用约 850 次调用；
3. 每个应用 `loadIcon` → 画到 72×72 → **PNG quality 100** 压缩（`:44-47`）；
4. `Base64.encodeToString` 拼进 JSON（`:49`）。

放到首帧之前，等于"启动时必须先把所有图标编码完"。四条改法按收益排序：

- **a. 排序前一次性取标签**：先把 `ComponentName → label` 读进 `HashMap` 再排序，消掉 ~850 次 IPC。【估】−100~250ms
- **b. PNG → WebP**：72×72 图标 PNG(100) 约 8–12KB，`Bitmap.CompressFormat.WEBP_LOSSY`（质量 80，保留 alpha）约 2–3KB。包体、base64、Dart 侧解码量同比降 3–4 倍。【估】首包 −500~800KB
- **c. 首帧不带图标**：`snapshot(includeStatic=false)` 已经支持分包，把 `installed` 改成"后台线程分批填充"（每批 8 个，`publish()` 触发增量），Dart 侧 `_carriedKeys` 已能承接未变化的 `apps`。首屏图标按批到达，不再挡首帧。【估】首帧 −0.3~0.8s
- **d. 图标落盘缓存**：以「包名 + `lastUpdateTime` + 目标尺寸」为键，写到 `getCacheDir()`；二次冷启动直接读，跳过 inflate/压缩。【估】二次冷启动再 −0.2~0.4s

这四条互不冲突，一起做是"启动路径重排"，不是"调参"。

### 2.2 卡片背景预烘焙（最大的一笔每帧成本）

【码】`widgets/glass_surface.dart:73-91`：每张卡都是

```
DecoratedBox(圆角 + BoxShadow(blur = Design.px(44) ≈ 37px, offset y = Design.px(16)))
└── ClipRRect          ← 外层，只为把阴影裁进圆角
    └── DecoratedBox(填充 + 边框)
        └── Material → Padding → child
```

卡片各自有 `RepaintBoundary`（`widgets/editable_card.dart:62`），所以阴影在层内缓存——**但每当这张卡的数据变化，整层（含 37px 模糊）就重新光栅化一次**。而卡片正是最常变化的东西。

【测】把这层阴影整个关掉再跑同一套翻页基准：raster p50 从 59.07/65.49/60.91/62.16（四轮）降到 **54.47/53.97/54.06**（slide/fade/depth 三档一致），即页面级 −5~7ms。单次对比落在噪声边缘，但**三档效果同向下降**，方向可信。

改法：把「阴影 + 填充 + 圆角 + 边框」用 `PictureRecorder` 画一次成 `ui.Image`，按 `(w, h, surfaceStyle, radius, shadow)` 缓存，`CustomPaint` 里只做一次 `drawImageRect`。内容仍走一层 `ClipRRect`。

- 预期：单卡重绘从「一次 37px 高斯 + 两次 clip + 一次 border」变成「一次 blit」。【估】8–15ms → <1ms（车机需实测）
- 风险：低端机上 `ui.Image` 常驻显存；每张卡一份，按尺寸缓存后总量可控（10 张卡 × ~1MB 内）。
- 退化方案（更保守）：只把 `blurRadius` 从 37 降到 12–16、`offset` 保持，视觉几乎无差，成本线性下降。

### 2.3 `GlassSurface` 的双层 `ClipRRect`

外层 `ClipRRect`（`glass_surface.dart:84`）只为让阴影贴合圆角，而阴影本身已经是圆角矩形，不需要裁剪内容。把阴影放到**不带 clip** 的外层 `DecoratedBox` 上，内容只保留内层一次裁剪即可。每卡每帧省一次 clip（低端 GPU 上 clip 会打断批处理）。风险：无，视觉等价，需要一轮截图对照。

### 2.4 点击反馈

【码】`glass_surface.dart:154-159`：`InkWell(highlightColor: alpha .20, splashColor: alpha .12)`。每次点击会启动一层 300–600ms 的水波动画，低端 GPU 上每一帧都要重绘被点击的整个卡片图层。

改法：`splashFactory: NoSplash.splashFactory`（或保留 `highlightColor` 但去掉 splash），把点击反馈改成「按下时直接换一次颜色」（一帧完成）。视觉上是取舍，需要产品确认。

### 2.5 glass 模式（背景模糊）

【码】`theme/launcher_theme.dart:81` `liveBlur => glass && !technicalFrame`；`glass_surface.dart:86-90` 每个 `GlassSurface` 一个 `BackdropFilter.grouped(ImageFilter.blur(10,10))`。`BackdropFilter` 需要把背景重新读回、做两遍高斯，再合成——在 Adreno 530 上是**最贵**的单类操作，而卡片一屏有 8–10 张。

本机默认外观 `glass=false` 所以测不到；车机若用 `blueGlass`，这一项极可能是整帧超预算的主因。改法：

- 模糊只保留给**对话框**和**底部 dock**（`launcher_dialog.dart:124`、`bottom_dock.dart`）；
- 卡片改用「半透明色 + 预烘焙噪点/渐变」，视觉上接近但不读回背景；
- 在设置里给「性能模式 / 画质模式」开关，老车机默认性能模式。

【估】glass 模式下整帧 −10ms 以上。**建议先在车上确认当前保存的外观是哪种**（这是决定要不要动这一项的前提）。

## 3. P1 细节

### 3.1 Impeller 后端（一行 meta-data 的 A/B）

【码】从 `flutter.jar` 反查：`io.flutter.embedding.engine.FlutterEngineFlags` 暴露了这些 manifest 键：

| meta-data 键 | 引擎参数 | 用途 |
| --- | --- | --- |
| `EnableImpeller` | `--enable-impeller=` | 开关（3.47 已无 Skia 回退，关掉会退回软件渲染，仅供诊断） |
| `ImpellerBackend` | `--impeller-backend=` | `vulkan` / `opengles` |
| `ImpellerLazyShaderInitialization` | `--impeller-lazy-shader-mode` | 延迟着色器初始化（减少首帧卡顿） |
| `ImpellerAntialiasLines` | `--impeller-antialias-lines` | 线抗锯齿（可关） |

当前 manifest 一个都没设（`AndroidManifest.xml` 无相关 meta-data），即走默认 Vulkan。**Adreno 530 是 2016 年的 Vulkan 1.0 驱动**，Impeller 的 Vulkan 后端在旧驱动上不一定比 GLES 快；这是本轮唯一"可能整体 ±20%"的开关，值得在车上花 10 分钟做四组对照（默认 / `opengles` / `opengles`+`lazy-shader` / `opengles`+`lazy-shader`+`antialias-lines=false`），用第 6 节的命令读数。

### 3.2 能量流动画常亮

【码】`widgets/vehicle_cards.dart:141-175`：`AnimationController(1300ms)` + `Timer.periodic(1600ms)` 反复 `forward(from: 0)`，只在「车辆状态有 flow」时启动；是否运行只看 `TickerMode`（`launcher_shell.dart` 只对设置页关闭），**桌面页整体是 enabled**。

也就是说：车机有能量流数据时，桌面**永久 60fps 出帧**。本机模拟器没有车辆数据，所以静止只有 1.6fps——这个热点在模拟器上完全看不到，必须在车上确认（`dumpsys gfxinfo` 静止 10 秒的帧数，如果接近 600 就说明命中）。

改法（三选一或组合）：
- 只在「当前可见桌面页包含该卡 && 应用在前台」时跑；
- 帧率降到 30fps（`Ticker` + 自己步进，或 `controller.duration` 拉长）；
- 静态化：把流动改成一次性 1.3s 的光带，之后停住（视觉取舍）。

### 3.3 内存预算

【码】`controller/launcher_controller.dart:119-121`：`imageCache.maximumSize = 128`、`maximumSizeBytes = 24MB`；`:90-91`：`_SnapshotImages(256, 4MB)` 图标、`_SnapshotImages(48, 12MB)` 最近任务。

【测】PSS 112MB。老车机 2GB 内存要和地图、媒体抢，建议图标缓存 24MB→8MB、项数 128→64、最近任务 12MB→4MB，并给 `Image.memory` 加 `cacheWidth`（图标只需 72dp，最近任务按卡片宽度）。【估】−20~30MB。

### 3.4 面板复用底栏引擎

【码】`LauncherEngines.create()` 用 `FlutterEngineGroup`（共享 GPU/font/snapshot），但 `GlobalDockService.java:211` 给 `globalDockMain` 和 `globalPanelMain` 各建一个引擎。两个引擎共享 GPU 上下文，但各自有 Dart 堆和 raster 线程。面板只在点开时存在——可以把面板做成底栏引擎内切换 root widget，省一个引擎。风险中等（两个入口的 isolate 状态不再隔离，需要检查 `main.dart` 两个 entrypoint 的耦合）。

## 4. P2 结构性

- **去掉全屏 `FittedBox` 1.2×**（`screens/launcher_shell.dart:93-97`，1600 设计画布 → 1920 实宽）。当前所有文本在 1600 基准排版后被整体放大，字形边缘会被重采样。彻底解法是让 `Design.canvasWidth` 在首帧从 `LayoutBuilder` 定标，但这会改动 `design_contract_test.dart` 里锚定的成品几何（`closeTo(14.9333)`、`933.333`、`left 62`/`width 96` 等）——属于"能省一点、但要改验收口径"的项，建议放到视觉复审周期里做。
- **文本**：卡片内的静态文案尽量 `const`，并给中文正文固定 `TextHeightBehavior`/`height`，避免每次重建重新排版（低端 CPU 上 CJK 排版远比拉丁文贵）。
- **HOME 常驻**：`MainActivity` 已是 launcher，确认 `launchMode`/`stateNotNeeded` 让系统回桌面时不重建 Activity，否则每次回桌面都重走引擎冷启动（本机 2.8s 的账）。
- **观测**：把「上一帧 build/raster、最近 60 帧 p90、当前包体、图标编码耗时、PSS」接到设置页一个隐藏诊断页，车上不用连 adb 也能判断有没有退化。

## 5. 建议实施顺序

1. 先做 **2.1 冷启动** 与 **2.2 阴影预烘焙**（收益确定、风险可控），一起出 0.6.19 包。
2. 同时准备 **3.1 Impeller 四组 A/B**（只需改 manifest，不碰逻辑）。
3. 车上量到 glass 模式确实是瓶颈后，再动 **2.5**；动之前先确认车上保存的是哪种外观。
4. **3.3 / 3.4 / P2** 放在后续版本，随其他改动一起验证。

## 6. 车上验证脚本

```bash
# 冷启动（3 次取中位数，先 force-stop）
adb shell am force-stop xyz.i4o.uni.launcher
adb shell am start -W -n xyz.i4o.uni.launcher/.MainActivity | grep -E 'TotalTime|WaitTime'

# 静止时到底在不在出帧（判断能量流动画是否常亮）：应为十几帧
adb shell dumpsys gfxinfo xyz.i4o.uni.launcher reset
sleep 10
adb shell dumpsys gfxinfo xyz.i4o.uni.launcher | grep -E 'Total frames rendered|Janky frames|90th percentile'

# 翻页/点击的帧分布
adb shell dumpsys gfxinfo xyz.i4o.uni.launcher framestats

# 内存
adb shell dumpsys meminfo xyz.i4o.uni.launcher | grep -E 'TOTAL|Native Heap|Graphics'

# 渲染后端确认（Impeller 后端切换后必看）
adb logcat -c && adb shell am force-stop xyz.i4o.uni.launcher
adb shell am start -n xyz.i4o.uni.launcher/.MainActivity && sleep 3
adb logcat -d | grep -iE 'impeller|vulkan|opengles'

# 增量包是否仍然很轻（正常无输出）
adb logcat -s UniPerf
```

判读规则：`Total frames rendered` 在静止 10 秒里接近 600 → 2.2/3.2 命中；`Janky frames` 比例在点击后集中出现 → 2.2/2.4/2.5；`Native Heap` 长期上涨 → 3.3 的图像缓存。

## 7. 探针工具（已就绪）

`tools/car_perf_probe.ps1` 把上面第 6 节整条流程自动化，一次跑完输出一份 JSON + 原始 `framestats.csv` + 截图。

```powershell
# 车机（无线 adb 连好之后）
pwsh tools/car_perf_probe.ps1 -Label before
pwsh tools/car_perf_probe.ps1 -Label before-r2      # 第二遍取中位数
# 装上新包后再跑
pwsh tools/car_perf_probe.ps1 -Label after
```

行为约定：

- **只读为主**：不 `pm clear`（除非显式 `-ClearData`）、不卸载、不改偏好设置；装包由人手动做。
- 跑之前先 `pm path` + 把已装 APK 拉下来用 `apksigner` 验证书，打印出 `certificate`；两次对照该字段必须一致，否则 A/B 无意义。
- 采集：冷启动 ×N（force-stop → `am start -W`）取中位数、静止 N 秒出帧数、翻页 N 次后的 `framestats`、`meminfo`、Impeller 后端日志行、一张 `screencap`。
- 产物落 `car-reports/perf/<label>/`（已被 `.gitignore` 忽略），报告在 `car-reports/perf/<label>.json`。

模拟器干跑（`-Label emulator-dryrun`，2 轮冷启动 / 6s 静止 / 4 次翻页）：

| 字段 | 值 |
| --- | --- |
| `coldStart.medianTotalMs` | 2832.5（2822–2843） |
| `idle` | 9 帧 / 6s = **1.5 fps** |
| `interaction.summary` | 33 帧，p50 5ms，janky 0% |
| `memory.totalPssKb` | 112137 |
| `identity.certificate` | `c8a2e9bc…`（与 IP753 证书一致，覆盖安装链路可用） |
| `identity.backendLog` | `Using the Impeller rendering backend (OpenGLES).` |

顺带发现两件事：

1. **模拟器上 Impeller 走的是 OpenGLES 后端**，不是 Vulkan。所以 3.1 的四组 A/B 在车机上第一件事就是看这行日志——如果车机是 Vulkan，那"降级到 GLES"才有意义；如果车机本来就是 GLES，那 3.1 只剩 `lazy-shader` / `antialias-lines` 两个开关值得试。
2. 模拟器日志里有 `Fragment shader active uniforms exceed GL_MAX_FRAGMENT_UNIFORM_VECTORS (261)`（因为模拟器 GLES 上限低）。Adreno 530 的上限高得多，正常不会触发，但车机上要顺手看一眼有没有同类 `Impeller validation` 报错——有就说明某些 shader 在该 GPU 上走了退化路径。

调用前需要人工确认的只有一件：**车机当前用的是哪种外观（classic / blueGlass）**。这个值存在应用私有 prefs 里，无 root 读不到，截图我也看不了（当前会话的模型没有图像输入），所以要么你瞄一眼告诉我，要么我用一个临时变体包把外观打印进 logcat。

## 8. 车机实测（首次上车，2026-10-28）

设备：`MSM8996 for arm64` / `dcy11_a1` / Android 9（sdk 28）/ 1920×1080 density 160 / **Adreno 530, GLES 3.2**。无线 adb 直连。

### 8.1 先说仪表：这台车上 `dumpsys gfxinfo` 对 Flutter 无效

探针第一版用 `gfxinfo` 统计，在车机上读到 **0 帧**，而同一时刻滑动明明切换了页面。原因是 Flutter 在自己的 `1.raster` 线程绘制到 SurfaceView，绕开 HWUI，Android 9 的 gfxinfo 计数器不记账。**改用 `dumpsys SurfaceFlinger --latency '<SurfaceView 图层>'`，并用 `/proc/uptime`（同一单调时钟）截取动画窗口内的呈现时间戳。** 探针已按此改写。

### 8.2 冷启动：0.6.18 比车机上原有的 0.6.17 慢 0.5–0.65s

| 版本 | 冷启动（force-stop → `am start -W`） |
| --- | --- |
| 0.6.17（车机原装，vc2028） | 3096 / 2809 / 3054 ms，中位 **3054** |
| 0.6.18（性能分支，vc2031） | 3761 / 3575 / 3722 / 3710 / 3540，中位 **3710**；再测一轮 3530 / 3282 / 3531 |

覆盖安装成功（同证书 `c8a2e9bc…`，prefs 与卡片布局全部保留），所以这是同一台设备、同一份用户数据下的可比数字。**这是回退，需要定位**：0.6.18 包含 upstream 的翻页动画/`pagePosition` 改动，需要再做一个「仅 upstream、不含性能改动」的构建来二分。

### 8.3 空闲功耗：一个页面 28% CPU，另一个只有 13%

| 场景 | 出帧 | CPU（单核） | 地图消耗帧 |
| --- | --- | --- | --- |
| 第 1 页（含导航卡，`renderMode: realtime`） | 11.4 fps | **28.0%** | +89 / 8s ≈ 11/s |
| 第 2 页（无导航卡） | **1.0 fps** | **13.1%** | +0 |

结论：**桌面上那 11fps 的持续重绘，来源是导航卡里的实时地图合成，不是遥测包。** 第 2 页只有 1fps（每秒一次的时钟刷新），说明遥测链路本身并不触发重绘。

但第 2 页仍有 13% CPU，8 秒内线程分布：UI 线程 46 ticks、`pool-3-thread-1` 42、`1.raster` 30、`HeapTaskDaemon` 16、`uni-system-stat` 13。原生侧最密的轮询是 `OfficialCarReader.worker.scheduleWithFixedDelay(..., 1, SECONDS)`（`OfficialCarReader.java:84`），即**每秒一次走原车 binder 读全部车辆字段**，这是那 ~5% 的主要来源。

### 8.4 翻页动画：UI 线程构建受限，不是 GPU

单次滑动，该图层的逐帧呈现间隔（ms）：

```
100  83.3  150  50  33.3  33.3  50  66.6  50  16.7  16.6  50  66.7  33.3  33.3  250
```

中间出现了两个 **16.6ms** 帧，说明 Adreno 530 完全有能力跑满 60fps，动画期间的 33–150ms 是**UI 线程构建新页面的成本**（卡片树 + 中文排版 + 图标解码），与冷启动慢是同一个病根。这一条同时说明：继续优化 GPU 光栅（阴影、模糊）在车机上收益有限，重心应转到「减少每帧构建量」。

### 8.5 本次已落到车上的改动

`MainActivity` / `GlobalDockService` 的发射口加了包签名去重：把 `*AtMs` / `*AtElapsedMs` 这类每次读取都会重打的时间戳从比较签名里抹掉，签名不变就不发包。实测依据：前后两次状态转储有 **46 处差异，全部是时间戳**（`vehicle.fields.*.updatedAtMs/updatedAtElapsedMs/observedAtMs`）。

注意：这只省掉了"内容没变还往 Dart 送"的那部分；`updateSnapshot()` 本身仍会在每次 `publish()` 时重建 JSON（`pool-3-thread-1` 的 5% 里有一部分是这个）。要彻底解决需要让适配器维护 dirty 标记，而不是每次重建。

## 9. P0/P1 全部实施后的车上复测

### 9.1 改了什么

| 项 | 改动 | 位置 |
| --- | --- | --- |
| 冷启动 | 标签一次读完再排序（原来每次比较调两次 `loadLabel`，约 850 次 IPC） | `AppRepository.refresh()` |
| 冷启动 | 图标 PNG(100) → WebP(80)，并在 `cacheDir/app-icons` 按「包名+sourceDir mtime」落盘缓存 | `AppRepository.iconBase64()` |
| 冷启动 | 卸载能力判定里的 `getApplicationInfo`/`UserManager`/`ActiveAdmins` 从每应用一次提到每轮一次，系统应用标志改从 `ResolveInfo.activityInfo.applicationInfo.flags` 直接读（零 IPC） | `uninstallAllowed()` / `activeAdminPackages()` |
| 翻页 | 卡片阴影 44→20（技术风格 18→12），偏移 16→10 | `glass_surface.dart:76-84` |
| 交互 | 按钮保留按下高亮、去掉扩散水波 | `glass_surface.dart:163` |
| 常态 | 车辆字段轮询改为自调度：前台 1s、后台 3s | `OfficialCarReader.start()/poll` |
| 常态 | 系统状态轮询 2s → 隐藏时 5s | `SystemStatusAdapter:49` |
| 常态 | 新增非阻塞可见性信号 | `LauncherVisibility.java`，`MainActivity.onResume/onStop` |
| 内存 | `imageCache` 128 项/24MB → 64 项/10MB；最近任务快照 12MB → 6MB | `launcher_controller.dart:91,120,121` |

### 9.2 复测数据（同一台车，屏幕常亮、launcher 在前台）

| 指标 | 改动前 | 改动后 |
| --- | --- | --- |
| 冷启动中位 | 3710 ms（3540–3761，5 轮） | **3449 ms**（3004–4213，6 轮） |
| 冷启动最小 | 3282 ms | **3004 ms** |
| 装完首启（图标缓存冷） | — | 4825 ms（要写 70 个图标文件） |
| 第 1 页空闲（实时地图在） | 11.4 fps / 28.0% CPU | 11.9 fps / **29.2%** CPU |
| 第 2 页空闲 | 1.0 fps / 13.1% CPU | 1.1–1.4 fps / **12.9–14.8%** CPU |
| 翻页逐帧间隔最大值 | 750 ms（含 250 ms） | **116.7 ms** |
| PSS（地图已挂载时） | 178,760 / 194,023 KB | 198,832 KB（Graphics 127,516） |
| PSS（地图未挂载时） | — | 112,602 KB（Graphics 45,900） |

### 9.3 结论（三条都要看清楚）

1. **冷启动这次拿回了约 260 ms（中位 −7%）**，方向对但远不到目标。这台机器上冷启动的主体是 Flutter engine 初始化 + 首帧，不是应用数据准备；要继续压必须在应用内打点，把 3.3s 拆成「进程起→onCreate→首帧」三段再对症。
2. **空闲 CPU 与内存基本没动**，因为在地图挂载状态下，两者都被实时地图支配：CPU 那 ~15% 是地图合成，Graphics 那 45–127MB 主要是地图虚拟显示的缓冲和纹理拷贝，不是我们的图片缓存。我们自己的开销已经降到小头。**这解释了为什么 P1 的收益看不见——不是没生效，是分母被地图拿走了。**
3. **翻页的尾部长帧消失了**（750ms/250ms → 最大 116.7ms），但 50–100ms 的帧仍在，说明剩下的成本不是阴影，而是入场页首帧的整体光栅（卡片内容 + 图标纹理 + 中文排版）。下一步要么做真正的图层级预光栅，要么减少单页卡片数量/内容。

### 9.4 顺手发现的一个功能性问题

**内嵌地图会被高德自己抢回前台。** 复测过程中 `mCurrentFocus` 反复从
`xyz.i4o.uni.launcher/.MainActivity` 跳到 `com.autonavi.amapautp.yh/com.autonavi.amapauto.MainMapActivity`，
同时 `mapViews` 的 `taskMoves` 增加、`consumedFrames` 停止增长——也就是桌面上的导航卡变成 0fps 的死图，
直到再次进入桌面才恢复。这个比毫秒级调优更值得先修：它直接表现为"导航卡有时候不动"。


## 9. 与车机原厂桌面的对照基线

对照组：`com.ecarx.cardesk`「CarDesk 车控桌面」`1.0.1027-system`（原厂，同为 HOME 应用，桌面上没有实时地图）。同一台车、同一套非 root 手法、同一组滑动（1600↔320，4 次，间隔 500ms）。

| 指标 | CarDesk（原厂） | uni 0.6.18 | 结论 |
| --- | --- | --- | --- |
| 冷启动中位 | **4090 ms**（3796/4086/4094/4345） | **3710 ms**（3540/3575/3722/3761） | uni 快约 9% |
| 静止出帧 | 0 fps（完全静态） | 0.8 fps（无地图页）/ 11.4 fps（含实时地图页） | 功能差异 |
| 静止 CPU | 14.5 – 23.3%（三次取样，波动大） | 16.6%（无地图页）/ 28.0%（含地图页） | 无地图页基本持平 |
| 交互表现 | gfxinfo：99 帧，63.6% 掉帧，帧耗时 p50 **21 ms** / p90 36 ms | Flinger 呈现间隔 p50 **66.6 ms** / p90 183 ms，67/75 帧 >33 ms | uni 明显更涩 |
| PSS | 60 MB（刚起）/ 71 MB（稳定）/ 102 MB（用过之后） | **190 MB**（Graphics 102 MB：EGL 41 + GL 37） | uni 高 2–2.7 倍 |
| 线程数 | 22 | 32 | — |

两条必须记住的口径差异：

1. **交互指标不是同一个量**。原厂是 HWUI 应用，`gfxinfo` 直接给帧耗时；我们在自己的 `1.raster` 线程绘制，`gfxinfo` 永远 0 帧，只能用呈现间隔反推。方向明确（它约 48fps 节奏、我们约 15fps），但不能当成同精度数字对比。
2. **原厂桌面不是翻页式**。它更像整页滚动/短动画，没有"入场页整屏首次光栅化"这一步，所以"更丝滑"里有一部分来自功能更简单，而不是实现更好。

结论排序：**内存是最大差距（唯一差一个量级的项）→ 交互流畅度是第二差距 → 冷启动我们已经领先 → 静止 CPU 基本持平。** 内存这条是结构性的：Flutter 引擎基线（EGL/GL 各 37–41 MB，全屏 1920×944 缓冲）+ 图像缓存 24 MB/12 MB，不是某段代码写错。

装 CarDesk 会触发系统 HOME 选择器（第二个 HOME 应用），已用 `cmd package set-home-activity xyz.i4o.uni.launcher/.MainActivity` 把默认桌面钉回 uni，`cmd shortcut get-default-launcher` 已确认。


