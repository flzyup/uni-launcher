# 0.6.18：交互卡顿的 P0/P1/P2 修复

版本 `0.6.18+31`，包名 `xyz.i4o.uni.launcher`。本轮以 `origin/main` 的 0.6.18（`b1f68d3`）为基线合并，只在本机做静态检查（`flutter analyze`、`flutter test`、`javac` 类型检查），**没有连接或安装车机**；仓库内 `app/verification/page-motion/profile-report.json` 与 `app/verification/0.6.18/page-motion/profile-report.json` 的帧耗时来自模拟器，不能换算成高通 820A / Adreno 530 的实车帧率。

## 结论回顾：两个独立成因

| 症状 | 成因 | 关键证据 |
| --- | --- | --- |
| 静止画面也"不丝滑"（栅格耗时高） | 每张卡片带 37dp 模糊阴影 + 抗锯齿圆角裁剪；背景 4~5 层全屏图元；`glass=true` 时每张卡片一个 `BackdropFilter`；翻屏时两页同时绘制还要穿过全局 1.2× 缩放 | `raster P50 30.30ms / P90 35.6ms`，`over16_67Ms 240/240`（模拟器） |
| 每次点击/拖动后的"顿一下" | 每产生一条遥测就把整份快照（含 50 个应用图标 base64、封面 ≤1MB、歌词 ≤128KB）序列化两遍、解析一遍，主线程扇出到 3 个引擎，Dart 侧再 `jsonDecode` + 整棵 `MaterialApp` 重建 | `LauncherRuntime.snapshot()` 的 `toString()→new JSONObject()`；`ThemeData` 扩展无值等价导致 `Theme` 每次全树重建 |

构建耗时本身很好（P90 1.35~1.84ms），所以"少 setState、多 const"这类改动没有可感知收益；本轮按上表两条分别动手。

## P0：快照分包 + 发布合并

### 1. 重负载移出高频包（`LauncherRuntime.java`）

新增 `snapshot(boolean includeStatic)`：`includeStatic=false` 时不再发送 `apps`（图标 base64）、`savedDesign`、`appNames`，并把 `media.artwork` / `media.lyrics` 从包里摘掉，改为标记 `"partial": true`。读取方保留上一份副本。

- 分包依据是 `staticRevision`：`trackStatic()` 用"应用数组身份 + 设计长度 + 名称条目数 + 封面/歌词内容哈希"做指纹，只有真正变化才自增；重命名（键数不变）与设计保存（长度可能不变）在写入点显式自增，避免内容变化被增量包吞掉。
- 每个窗口（主界面、全局底栏、全局面板）各自记 `sentStaticRevision`，所以谁都能在需要时独立拿到一次完整包。
- `snapshot()` 里去掉了 `new JSONObject(buildSnapshot().toString())` 的"序列化+解析"往返；剩下的唯一一次序列化就是把包交给 EventChannel。

体量对比（按 50 个 72×72 PNG 图标、封面 ≤1MB 估算）：完整包 400KB~1.6MB，遥测包 2~4KB。`MainActivity.updateSnapshot()` 里留了一条反向断言：万一有重负载又漏进增量包（>64KB），`logcat -s UniPerf` 会直接报出来。

### 2. 发布合并与限频（`LauncherRuntime.publish()`）

空调、媒体、系统状态原本各在自己的回调里 `publish()`，一次交互会连着打好几包。现在同一 looper 轮次内合并，并限制最小间隔 80ms（约 12 次/秒），单包成本从"每次回调一次"降到"每 80ms 一次"。

### 3. 主线程周期阻塞

- `WorkspacePolicy`：反射 `getAllStackInfos` 的 binder 调用从 250ms 改为 1000ms（它只负责发现"新出现的全屏任务"，没有可用事件源），并把三处 `commit()` 改为 `apply()`，去掉主线程同步 fsync。
- 全局面板的最近任务缩略图改为"变了才发，关闭时发空数组"，不再每包重发整组缩略图。

### 4. Dart 侧增量消费（`launcher_controller.dart`）

`_receive` 识别 `partial` 包：把上一份 `apps`/`recentTasks`/`savedDesign`/`appNames` 以及 `media.artwork`/`lyrics` 合并进来，**保持同一个对象引用**。这有两层意义：一是图标不会被误判为"新图"而重新解码，二是 `NativeSliceBuilder` 的深比较走 `identical` 分支，开销可忽略。

图标/最近任务的缓存记账（`begin/finish`）只在包内确实带了对应用负载时执行——否则一个不含 `apps` 的增量包会把仍在屏幕上的图标从缓存里清掉。空事件 `{}` 仍然是"整份重置"，这条老契约没变。

## P1：主题等价 + 视图通道去重

- `SurfaceStyle` 增加 `operator ==` / `hashCode`。Flutter 的 `ThemeData ==` 用 `mapEquals` 比较 `extensions`，没有值等价时每次重建都算"新主题"，于是 `Theme` 通知全树重建——每张卡片跟着重建、从而重绘（含模糊阴影与圆角裁剪）。这一条同时是**栅格**开销：重建会让卡片的 `RepaintBoundary` 失效。
- `launcherTheme()` 按样式记忆化，`ColorScheme.fromSeed` 的 HCT 推导从"每次通知一次"变成"每次换外观一次"。
- `LauncherShell` 改为 `StatefulWidget`，`viewport` 通道只在几何/页码/设置态真正变化时上报，不再每次重建都发一次。

## P2：栅格侧

- **翻屏出页裁剪**：`slide` 与 `depth` 共用"未覆盖区域"裁剪器。翻屏时旧页只绘制仍然可见的那部分，被新页盖住的半边不再参与填充。0.6.18 给两页之间留了 24px 间隙（`workspace_motion_test` 的 "adjacent pages retain a visible gutter"），这层裁剪与之相容：裁剪只去掉超出旧页自身右缘（前进）或左缘（后退）的区域，间隙里露出的背景从不落在裁剪范围内，画面像素不变。
- **壁纸采样**：`cacheWidth` 已经等于面板宽度，属于 1:1 贴图，`FilterQuality.medium`（mipmap）不改变任何像素却要额外的显存与上传，改为 `low`。
- **能量流动画**：这张卡会**永久**按 1.6s 循环重绘，原先每帧重新排版 4 个中文标签（文字整形是全帧里最贵的一步）。改为按"文本+颜色"缓存 `TextPainter`，像素不变。

## 明确没有做的三件事

| 提案 | 为什么停手 |
| --- | --- |
| 去掉全局 `FittedBox` 的 1.2× 缩放（把 `Design.canvasWidth` 设成真实宽度） | 设计基准是 1600 画布，`design_contract_test.dart` 用 1920 屏幕断言的是**缩放后**的最终几何（`closeTo(14.9333)`、`sheet.width 933.333`）。若把 `canvasWidth` 改成 1920，它必须等到首次布局才知道，而 `SurfaceStyle.from` 在布局之前就计算了 `Design.px`，同一帧里会出现两种基准的混用。收益（消掉一个恒等矩阵层）远小于风险。 |
| `switchPage` 改乐观提交（先切页再等原生） | `layout_test.dart` 有一条显式契约："native map must be hidden before Flutter paints another page"——先隐藏原生地图 Surface 再换页，是为了避免地图盖在第二页上。这里不是延迟，是顺序要求。真正要缩的是那次 method channel 的排队时间，而它已被 P0 大幅削掉（不再排在几百 KB 的序列化后面）。 |
| 把 `BottomDock` 拆成媒体段/空调段各自 `select` | 底栏的构建依赖 `native` 几乎全量字段，拆分需要重写它内部的闭包结构，对全局面板回归测试风险高。P0 之后包已经降到 2~4KB、且限频 12Hz，这段重建的绝对成本已经很小。 |

`glass=true` 时每张卡片的 `BackdropFilter`、卡片 37dp 模糊阴影、背景多层叠加，都属于**画面本身**的成本；降它们等于改视觉，需要拿设计稿做实车 A/B，不在本轮静默改动的范围内。

## 车机上怎么量

```bash
# 1) 交互卡顿：点一次空调、拖一次卡片，比较 janky frame 数与 95 分位
adb shell dumpsys gfxinfo xyz.i4o.uni.launcher framestats
adb shell dumpsys gfxinfo xyz.i4o.uni.launcher reset

# 2) 增量包是否仍然很重（正常应无输出）
adb logcat -s UniPerf

# 3) 主线程是否还在被周期任务占用
adb shell top -H -p $(adb shell pidof xyz.i4o.uni.launcher)
```

判读方式：如果 `UniPerf` 没有告警，但帧仍然超预算，剩下的就是栅格（视觉）成本，应转去做 `glass`/阴影/背景层的 A/B；如果 `UniPerf` 有告警，说明还有负载漏进增量包。

## 本机 A/B 实测

两组数据都是在同一台机器、同一个模拟器（`LX_1080p`，Android 10 / x86_64 / 1920×1080 / density 160 / swiftshader 软件光栅）上，用 `origin/main` 的独立 worktree 与本次分支各跑一遍得到的。**结论只对本机成立，不能换算成 820A + Adreno 530。**

### 1. 翻页帧耗时（`flutter drive … --profile --no-dds`，各跑两轮）

| 效果 | origin/main raster p50 | 本分支 raster p50 | origin/main build p50 | 本分支 build p50 |
| --- | --- | --- | --- | --- |
| slide | 59.07 / 65.49 ms | 60.91 / 62.16 ms | 1.93 / 1.36 ms | 2.07 / 1.46 ms |
| fade | 58.68 / 62.38 ms | 58.73 / 63.81 ms | 2.29 / 2.27 ms | 1.89 / 1.56 ms |
| depth | 59.81 / 63.91 ms | 60.93 / **56.90** ms | 1.69 / 2.01 ms | 1.21 / 0.85 ms |

**判读：这条轴测不出差别。** 同一棵树两轮之间 raster p50 就能相差 6.4ms（≈11%），树间差异完全落在这个噪声里；`over 16.67ms` 在四组数据里都是 240/240，因为软件光栅的底板成本（全屏合成 + 模糊）远高于 16.67ms。

原因不是"改了没用"，而是**这个测试场景踩不到被改的代码**：0.6.18 已经把翻页进度改成 `ValueNotifier pagePosition`，滑动过程中 controller 不通知、不发包、不重建主题；而 P0/P1 改的正是"通知/发包"这条路径。`depth` 那两轮偏低（56.9 / 60.9 对 59.8 / 63.9）与出页裁剪节省的填充面积方向一致，但仍在噪声内，不作结论。

### 2. 每个包的实际成本（同一份基准文件在两棵树各跑一次，Dart JIT 数值）

| 场景 | 包体 | `jsonEncode` | `jsonDecode` | controller 摄取（解码 + base64 + 合并） |
| --- | --- | --- | --- | --- |
| 全量 + 封面（50 个 6KB 图标） | 805 KB | 8.4 / 9.2 ms | 3.5 / 3.6 ms | 6.2 / 4.8 ms |
| 全量无封面 | 405 KB | 5.9 / 4.9 ms | 1.8 / 1.9 ms | 5.8 / 3.4 ms |
| **增量包（本分支的高频包）** | **694 B** | **0.10 ms** | **0.03 ms** | **~1.0 ms** |

（"a / b" = origin/main / 本分支。原生侧用的是 `org.json`，比 Dart 快，但改变前每条事件要做"序列化 + 解析"两遍，且三个窗口各做一次。）

一次交互的差异：改变前是 3 个窗口 × (0.4~0.8MB 序列化 + 解析)，改变后是 3 个窗口 × 2~4KB 单遍序列化 + Dart 端 0.03ms 解码。这就是"点一下顿一下"消失的地方，属于**主线程阻塞时间**，不体现在翻页动画的帧耗时里。

### 3. 每次通知的主题计算

同一份基准文件测得 `launcherTheme()` 单次调用：

| | origin/main | 本分支 |
| --- | --- | --- |
| 缓存命中 | 无缓存概念，每次重建 **1.10~1.90 ms** | **0.2 µs** |
| 真正重建 | 1.10~1.90 ms | 1.10 ms（仅换外观时） |

`LauncherApp.build` 里 `AnimatedBuilder(animation: controller)` 每收到一次通知就重新算一次主题；改变前 `ThemeData` 因 `SurfaceStyle` 无值等价而恒不相等，`Theme` 于是让全树依赖者重建——卡片连带 37dp 模糊阴影与圆角裁剪一起重绘。改变后主题是同一个实例，`Theme` 的比较直接短路。

## 验证记录

- 合并基线：`origin/main` `b1f68d3`（0.6.18），与本轮改动无同区冲突；`LauncherShell` 两边都改成了 `StatefulWidget`，人工合并后保留 0.6.18 的 `pagePosition` 与本轮的 `viewport` 去重
- `flutter analyze`：No issues found
- `flutter test`：167 项通过（0.6.18 自带 166 项 + 新增 1 项：增量包保留被省略的负载与图标缓存）
- Android 源文件 `javac --release 8`（android-36 + flutter.jar + androidx 子集）：通过
- `app/native-tests/tools/*.py`：本轮改动不涉及它们编译的类（媒体/歌词适配器），且本机缺 `org.json` jar 无法运行
