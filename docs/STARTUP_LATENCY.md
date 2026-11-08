# 启动白屏与冷启动预算

这份文档回答三个问题：启动白屏是怎么来的、还有多少时间可以省、1 秒以内到底有没有可能。数据来自 Android 9 / x86_64 / 1920×1080 模拟器（与车机同分辨率、同 API 级别），以及 `car-reports/perf/` 里 820A 车机的历史记录。模拟器的绝对耗时不能换算成 820A，但**分段结构和各段的相对占比可以直接看**。

## 一、白屏不是慢，是颜色

启动过程里屏幕上的白色有三层，全部来自 Flutter 模板的默认值：

| 层 | 位置 | 原来是什么 | 谁画的 |
| --- | --- | --- | --- |
| 1 | `drawable-v21/launch_background.xml` | `?android:colorBackground` → 纯白 | system_server 的 Activity 预览窗口（starting window） |
| 2 | `values/styles.xml` 的 `NormalTheme` | `?android:colorBackground` → 纯白 | FlutterView 背后的窗口底色 |
| 3 | `launcher_app.dart` 的 `bootCanvas` | `Color(0xFFFFFFFF)` | Flutter 的兜底画布 |

第 1 层是最要命的：它在**进程还没 fork 出来**的时候就被系统画好了，而 `minSdk = 24`，所以真正生效的是 `drawable-v21/` 那一份 —— `drawable/` 下的同名文件永远不会被选中。以前改过 `drawable/launch_background.xml` 的人会觉得「明明改了没效果」，原因就在这里。

三层加起来的效果是：从点击到 Flutter 画出桌面之间，整块屏幕是白的。车机上 `am start -W` 的 TotalTime 是 **2.8–4.0 s**（`car-reports/perf/before-0617.json` / `after-0618.json`），也就是三秒白屏。

现在三层都换成**上一次保存的外观对应的画布色**：

- 资源兜底：`res/values/colors.xml` 的 `uni_boot_canvas` = `#FF0A121B`（blueGlass / classic / nocturne 三个皮肤深色档之间的中性值，三套皮肤下都不跳色）。
- 运行时精确值：`LauncherRuntime.bootCanvasArgb()` 读 `saveDesign` 时算好并落盘的 `bootCanvasArgb`，`MainActivity.onCreate` 一开始就 `setBackgroundDrawable` 给 window。浅色主题用户看到的是浅色启动底，不是「深→白→浅」的三段闪。
- Flutter 兜底：`LauncherApp._bootCanvas()` 直接用 `SurfaceStyle.background`，和原生同一套值。

实测（模拟器，启动途中截图）：中心像素 `(41,45,58)`，平均 `(33,43,59)`，白色占比 **0.0**。改之前这一帧是纯白。

## 二、时间花在哪

`StartupTrace` 现在把整条链路都打出来了（`adb logcat -s UNI-Startup`，或诊断包 `summary.txt` 的「冷启动」段）。一次典型冷启动（模拟器，已 AOT）：

| 分段 | 相对进程启动 | 说明 |
| --- | ---: | --- |
| `onCreate` | 132–183 ms | fork + Application + 类加载 |
| `runtime` | +48–96 ms | `LauncherRuntime` 构造（全部适配器） |
| `window` | 454–575 ms | FlutterEngine 创建 + attach + `configureFlutterEngine` |
| `firstDraw` | 763–861 ms | 窗口首绘（此时是启动底色，还没有桌面） |
| `prelude` | 1031–1253 ms | Dart 侧读到外观 |
| `launcherContent` | 1219–1403 ms | **桌面真正画出来** |

改之前同一台设备：`launcherContent` 在 **1931–2095 ms**。也就是说「看得见桌面」提前了 **约 0.6 s**。

### 一个必须知道的度量陷阱

`am start -W` 的 TotalTime 会被**空画布首帧**骗过：改动前的版本先画一帧纯色画布，系统立刻认为「已显示」，TotalTime 好看（1.28–1.52 s），但桌面内容要再等 0.6 s 才出现。改动后第一帧就是桌面，TotalTime 反而变成 1.50–1.78 s，而用户感知是**变快**的。

所以量冷启动不要只看 `am start -W`，要看 `UNI-Startup: done ... launcherContent=...` 这一行。

## 三、1 秒以内有没有可能

分两个口径，答案不一样。

**口径 A：820A 车机、进程真的不在、page cache 也冷 —— 1 秒不现实。**

装进内存的东西是硬成本：`libflutter.so` 13.0 MB + `libapp.so` 7.8 MB + `classes.dex` 0.96 MB ≈ **21.8 MB**。820A 的 eMMC 顺序读 200 MB/s 量级，mmap 按缺页随机读会放大 3–8 倍，光把代码搬进内存就是 300–700 ms。再加上 Dart VM/isolate 在 820A 单核上的启动，纯冷的地板大约在 1.3–1.8 s。3 s 压缩到 1 s 以内，靠优化代码做不到。

**口径 B：进程已经预热过（开机阶段拉起）—— 1 秒轻松，甚至 0.6 s。**

模拟器上把「Dart 启动 → 桌面内容」这段压到 1.35 s 之后，剩下的时间几乎全在 engine 创建 + Dart isolate 启动（`window` 到 `prelude` 之间有 500–700 ms）。这两项都可以在**用户看到 HOME 之前**完成：

- 开机广播（`GlobalDockBootReceiver` 已经是 `directBootAware`）里 `FlutterLoader.ensureInitializationComplete` + 建一个 warmup 引擎，把 `.so` 读进 page cache、把 Dart VM 拉起来；
- 用户按到 HOME 时，`MainActivity.provideFlutterEngine` 已经是 warm 路径（现在窗口重建复用引擎的路径实测只有几百毫秒）。

结论：**要「冷启动 1 秒」，得先把冷启动挪到开机动画里去。** 单纯抠 Activity 里的代码，上限就是 1.3–1.5 s。

## 四、这一轮改了什么

1. `res/values/colors.xml`（新增）+ `drawable/launch_background.xml` + `drawable-v21/launch_background.xml` + `values/styles.xml` + `values-night/styles.xml`：三层白色全部换成深色启动底。
2. `LauncherRuntime`：`bootCanvasArgb()` / `designCanvasArgb()`，保存布局时把画布色算好落盘；`saveDesignOnMain` 顺手写入。
3. `MainActivity`：`applyBootCanvas()` 在 `onCreate` 最前面给 window 上底色；`prelude` 分支打点；新增 `mark` 通道；`summary` 改由 Dart 回报 `launcherContent` 之后再汇总（3 s 兜底）。
4. `launcher_controller.dart`：`initialize()` 拆成 `initializePrelude()` / `initializeRest()`。
5. `main.dart`：`await initializePrelude()`（400 ms 超时）→ `runApp` → `unawaited(initializeRest())`。首帧直接就是桌面，省掉「空画布 → 重建桌面」那一次全树构建。
6. `launcher_app.dart`：兜底画布改用 `SurfaceStyle.background`。

## 五、还没做的（按性价比排序）

1. **引擎预热**（最大头，能省 500–700 ms）：自定义 `Application`，`onCreate` 里 `LauncherEngines.warm(app)` 建一个 entrypoint 为空的引擎；`MainActivity` 复用它。`GlobalDockBootReceiver` 里在 `LOCKED_BOOT_COMPLETED` 就做一次，让 HOME 出现时是 warm 路径。
2. **构建期瘦身**：`--split-debug-info` + `--obfuscate`，`libapp.so` 通常还能再降 10–20%。
3. **Impeller A/B**：Android 上默认走 Impeller(GLES)。820A 的 Adreno 530 首次编译 pipeline 有成本，上真车 `--ez enable-impeller false` 对比 `firstDraw` 再定。
4. **dexopt 预编译**：新装的包是 `speed-profile`，把 `cmd package compile -m speed -f` 做一遍能省一点 Java 侧冷启动；模拟器上差异在噪声内，车机上因为 CPU 弱，收益应该更明显。
5. **`LyricOffset.load()` / `ClusterLyricsService.enabled()`** 目前还在主线程，可以挪到首帧之后。

## 六、复现

```sh
adb shell am force-stop xyz.i4o.uni.launcher
adb logcat -c
adb shell am start -W -n xyz.i4o.uni.launcher/.MainActivity
adb logcat -d -s UNI-Startup
```

关键判据：`done total=... fromCreate onCreate=0 runtime=... window=... firstDraw=... prelude=... launcherContent=...`。
`firstDraw` 是启动底色出现，`launcherContent` 是桌面出来 —— 后者才是用户感知的启动时间。
