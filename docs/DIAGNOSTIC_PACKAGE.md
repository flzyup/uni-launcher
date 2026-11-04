# 诊断日志与诊断包

把「车机上出问题但连不上 adb」这件事变成**可取证**的流程：应用自己写日志、自己打包，
用户把一个 zip 从车机取走就能还原现场。

功能移植自 CarDesk 的诊断包导出，本文档说明 UNI 侧的落法与差异。

## 入口

设置 → **系统与调试** → 顶部「诊断日志」：

| 操作 | 结果 |
| --- | --- |
| 导出诊断包 | 生成 zip，落到 `Download/UNI/uni-logs-<时间戳>.zip` |
| 导出并分享 | 同上，并调起系统分享面板 |
| 预览最近日志 | 显示最后 40 行，确认日志确实在写 |
| 清空日志 | 删除全部已落盘的日志文件 |
| 落盘级别 | 调试／信息／警告／仅错误，控制哪些级别写入文件 |

公共目录里最多保留 3 份诊断包，更早的自动删除（车机存储紧张）。

## 诊断包里有什么

```
uni-logs-20261103-204012.zip
├── summary.txt    环境 / 版本 / 权限 / 冷启动 / 子系统状态 / 频谱 / 氛围灯 / 底栏 / 锚点 / 设置全量键值 / 日志文件清单
└── logs/          全部日志文件（uni-yyyyMMdd-<序号>.txt）
```

`summary.txt` 的分段是为了让「不用翻日志就能回答」的问题被回答：

- **冷启动**：本次启动 + 上次冷启动的分段耗时。数字持久化在 `uni_startup.xml`，
  **日志被轮转掉也不会丢**。`total` 与 `am start -W` 的 TotalTime 同一时钟（`uptimeMillis`），
  可以直接对照；`bootMs` 用来区分「系统开机慢」和「桌面启动慢」。
- **子系统状态**：车辆、媒体、导航、红绿灯、天气、系统状态、日历、局域网传输、调试桥的只读快照。
  **只读**——导出诊断包不会改变车况。
- **权限**：逐项列出是否授予。「频谱没起来」有可能是 `RECORD_AUDIO` 被拒，
  这一段能自证，不必再猜。
- **锚点统计**：本次运行各功能节点被触发了多少次、最近走了哪几步（见下）。
- **设置全量键值**：连**类型**一起列出。`SharedPreferences.getInt()` 在值被存成别的类型时
  会直接抛 `ClassCastException`，只印 `toString()` 看不出是哪个键坏了。

## 日志

### 统一门面

原生侧用 `xyz.i4o.uni.launcher.log.UniLog`，Dart 侧用 `lib/platform/uni_log.dart`。
两边写进**同一个文件**——桌面大部分功能节点在 Dart 侧，如果两边分开落盘，
诊断包只能看到一半链路，导出一次仍然定位不了问题。

```java
UniLog.i(LogTags.VEHICLE, "写入空调", "func", 0x10010300, "zone", 1);
UniLog.w(LogTags.VEHICLE, "通道连接失败", t);
UniLog.event(LogTags.UI, "命令下发", "action", "toggle-play");
```

结构化字段拼成 `key=value`，真机上直接 grep：

```bash
adb logcat | grep 'UNI/Vehicle.*func=0x10010300'
```

### 级别与落盘

| 级别 | 含义 | 默认落盘 |
| --- | --- | --- |
| `DEBUG` | 调试细节 | 否 |
| `INFO` | 关键状态与用户操作 | 是 |
| `WARN` / `ERROR` | 异常与降级 | 总是 |

低于门槛的级别**只进 Logcat**。级别可调且**持久化**（存在 `launcher` 这个 prefs 文件里），
车机重启后不会丢。

### 文件规则（车机存储紧张，占用必须封顶）

- 目录：`filesDir/logs/`
- 命名：`uni-yyyyMMdd-<序号>.txt`
- 单文件上限 512KB，份数上限 8 份，**总字节上限 4MB**（两道约束取更严的）
- **磁盘余量保护**：剩余空间低于 16MB 就停止写盘，只留 Logcat ——
  日志不能把车机写满，那会影响导航、空调这些正经功能。
  降级状态会在诊断包里明确写出，否则用户看到「日志很少」会以为是 App 的问题。

### 锚点

关键功能节点用锚点标记，渲染成：

```
[ANCHOR] <节点> <阶段> [key=value...]
```

节点名用 `域/动作` 的稳定写法（如 `vehicle/read`、`media/transport`、`ota/check`），
阶段取 `enter` / `done` / `fail` / `skip`。同一条链路的节点在日志里是连续的，
一条 grep 就能看全：

```bash
adb logcat | grep '\[ANCHOR\] vehicle/read'
```

锚点同时进一份内存账本（`AnchorLedger`）：按节点统计触发次数、保留最近 200 条。
诊断包的「锚点统计」段直接给出结论——**哪个节点一次都没触发过**，
比翻几百行日志快得多。

Dart 侧：

```dart
UniLog.enter(UniLogTags.vehicle, 'vehicle/read');
UniLog.done(UniLogTags.vehicle, 'vehicle/read', fields: {'count': 12});
```

### 热路径

日志会写文件，所以**不在逐帧、逐广播、逐遥测包的路径上打日志**。
这些位置按「一个周期记一次」处理，记聚合值（次数、最后一个值），
不记每一次。Dart 侧的遥测包最高每秒 12 次，逐包记录会把包里其它内容全埋掉，
所以只记录**真正的状态跳变**（应用列表刷新、换歌、播放状态翻转、设置目录到达）。

「记一次」必须真的成立——这是模拟器实测出来的：

- 红绿灯广播走高德同一个 action，但**好几种 extras 键集**轮流发
  （`EXTRA_GEOLOCATION` / `EXTRA_STATE,EXTRA_STATUS_DETAILS` / `EXTSCREEN_*` …）。
  去重要记住**见过的所有形态**，只记最后一个的话，另外几种会轮流把日志刷出来。
- 键名要**排序后**再拼。`Bundle.keySet().toString()` 是实例身份哈希
  （`KeySet@344fc936`），拿它做签名等于没去重，而且维护者看到的是一串无意义的哈希。
- 1Hz 的车辆轮询这类心跳锚点一律降为 `DEBUG`：按 `INFO` 落盘，
  几小时就写满 4MB，把真正的事件挤掉。

实测（模拟器，`uni-ambient`，Android 10）：修掉广播去重后，
落盘从 **4.8KB/分钟** 降到 **0.64KB/分钟**，4MB 上限约可撑 4.5 天。

## 权限与系统版本

| 系统 | 导出走哪条路 | 需要什么 |
| --- | --- | --- |
| Android 10+（API 29+） | `MediaStore.Downloads` | 什么都不需要 |
| Android 9 及以下（API ≤ 28） | 先直接写 `Download/UNI/`，写不了再借 `MediaStore.Files` | `WRITE_EXTERNAL_STORAGE`（面板里运行时申请） |

所以 manifest 里要声明（`maxSdkVersion="28"`，Android 10+ 不再申请）：

```xml
<uses-permission android:name="android.permission.WRITE_EXTERNAL_STORAGE" android:maxSdkVersion="28"/>
```

### 运行时申请存储权限

诊断面板会实时显示存储权限状态，缺权限时**在导出之前**就弹系统授权框：

- 面板顶部一行「存储权限：已授予 / ⚠ 存储权限未授予，导出诊断包需要先授权」；
- 未授权时额外出现「申请存储权限」按钮；
- 点「导出诊断包」或「导出并分享」时，若还没权限，先弹系统框，
  授权通过才继续导出；被拒则中止并提示「请在系统设置里允许『文件和存储』」。

实现走原生 `requestPermissions`（requestCode `4107`），一次申请读写两项：

| 权限 | 用途 | 被拒的后果 |
| --- | --- | --- |
| `WRITE_EXTERNAL_STORAGE` | 导出诊断包 | **导出被拦下**，无法生成诊断包 |
| `READ_EXTERNAL_STORAGE` | 清理旧包、列 MediaStore | 导出照样成功，只是旧包会堆积 |

只有原生明确回报「写权限不可写」才会拦下导出；老版本原生侧没有这个字段时
按可写处理，不会因为兼容问题把导出卡死。

Android 10+（API 29+）走 `MediaStore.Downloads`，不需要任何权限，
原生侧直接回报可写，不弹框。

车机上 UNI 是系统应用，安装时这类权限通常自动授予，所以弹框一般只在
把 UNI 装成普通应用时才会出现。模拟器实测（Android 9 / API 28）：
首次点「导出诊断包」弹系统框 → 允许 → 导出成功落到 `Download/UNI/`；
拒绝则不导出、面板保持未授权态；再点「申请存储权限」仍能弹框（会多一个
"Don't ask again" 复选框）允许后可正常导出。

### 清理旧包还要读权限

「公共目录里只保留最近 3 份」要**读** MediaStore 集合才能列出自己导出的包，
所以 `READ_EXTERNAL_STORAGE`（manifest 里本来就有，`maxSdkVersion="32"`）也得授上。
少了它：导出照样成功，但旧包会一直堆着 —— 车机存储紧张，这个后果比导出失败更糟。

### 普通应用在 Android 9 上写不了公共目录

Android 9 的 sdcardfs 按**进程组**判权限：只有进了全局 `sdcard_rw` 组（1015）
的进程才能直接写 `/sdcard/Download` 这类公共目录。

- 车机上 UNI 是**系统应用**，有这个组，直接写这条路是通的；
- 装成**普通应用**就没有这个组，`mkdirs()` 直接失败，
  报「无法创建目录 /storage/emulated/0/Download/UNI」。

所以 API 28 及以下多了一条兜底：直接写失败就改用 `MediaStore.Files` + `DATA`，
让 **MediaProvider 代为落盘**（它自己是有权限的那个），普通应用也能把包放进公共目录。
直接写仍然排在前面 —— 车机上的行为一点没变。清理旧包同理，两条路都清一遍。

> `MediaStore.MediaColumns.DATA` 在 API 29 起废弃，所以这条兜底只在 API 28 及以下用。

### 已知边界：换装后旧包可能清不掉

MediaStore 只把**当前安装自己创建**的行暴露给应用。App 被卸载再装一次之后，
之前留下的诊断包在 MediaStore 里还在，但新装的实例看不见它们，也就清不掉。
车机上 App 不会频繁重装，正常使用不受影响；真要收干净可以手动删
`Download/UNI/` 里的旧 zip。

## 与 CarDesk 的差异

| | CarDesk | UNI 桌面 |
| --- | --- | --- |
| 实现语言 | Kotlin（纯原生） | Java（原生层）+ Dart（界面层） |
| 日志门面 | `Logx` | `UniLog` + Dart 侧 `UniLog` |
| 日志落点 | 仅原生 | 原生与 Dart **同一文件**（Dart 经平台通道回传） |
| 冷启动 | `StartupTrace.kt`，持久化 | `StartupTrace.java`，持久化 |
| 诊断包目录 | `Download/CarDesk/` | `Download/UNI/` |
| 诊断包前缀 | `cardesk-logs-` | `uni-logs-` |
| 锚点 | 无统一机制 | `[ANCHOR]` + 内存账本 + 诊断包统计段 |
| 分享 | `MediaStore` + `ACTION_SEND` | 同左 |

CarDesk 的诊断包靠反射拿 `android.os.Process.getStartUptimeMillis()`，因为它的 compileSdk 是 29。
UNI 的 minSdk 是 24，该方法从 API 24 起就是公开 API，直接调用即可，不需要反射。

## 实现要点

- 原生侧核心在 `app/android/app/src/main/java/xyz/i4o/uni/launcher/log/`：
  `UniLog`（门面）、`FileLogSink`（落盘与轮转）、`LogFormat`（纯逻辑格式化）、
  `LogLevel`、`LogTags`、`AnchorLedger`、`Diagnostics`（打包）、`LogTools`（UI 辅助）、
  `LogBridge`（Flutter 通道）。
- `LogFormat` 与 `AnchorLedger` 不依赖 Android，可以在 JVM 单测里直接验：
  `app/android/app/src/test/java/xyz/i4o/uni/launcher/log/`。
- 导出走 `MediaStore.Downloads`（Android 10+）拿 `content://` Uri 直接分享；
  Android 9 及以下写 `Download/UNI/`。
- **清理旧诊断包只能用标准 selection**，
  条件里同时带 `_id`、文件名和相对路径。
  绝不能把条件塞进 query param——MediaProvider 不一定按它过滤，
  实测会把 `Downloads` 集合里**所有**文件删掉（连用户的下载文件一起没）。
- **按车机自己的 API 级别编译校验**。`MediaStore.Downloads` 是 API 29 才有的类，
  按 API 28 编译会整包编不过，脚本里用一份只含 `Downloads` 的桩顶掉 `android.jar`
  的那份（显式参与编译的源文件会遮蔽 classpath 里的同名类）：

  ```bash
  cd app
  ./tools/javac-check.sh 9     # android-9 = API 28，车机（Android 9）的级别
  ./tools/javac-check.sh 24    # UNI 声明的 minSdk
  ./tools/javac-check.sh 29
  ./tools/javac-check.sh 36
  ```

  只按 API 36 编是抓不到 `String.isBlank`（API 35）、`String.join`（API 26）、
  `java.nio.file.Files`（API 26）这类问题的——它们在车机上都是 `NoSuchMethodError`。

  诊断日志这套代码在 API 24 / 28 / 29 / 36 上都能编过。
  顺带一提：按 API 24 编**整包**会报错，但都在既有业务代码里
  （`canRequestPackageInstalls`、`AudioPlaybackConfiguration` 等 API 26+ 的成员），
  运行时都有 `SDK_INT` 兜着。也就是说 UNI 实际能跑的最低版本是 API 26，
  manifest 里的 `minSdk 24` 名义上偏松。

## 怎么读一份诊断包

1. 「车机连不上 adb」时：设置 → 系统与调试 → 诊断日志 → 导出诊断包，
   从 `Download/UNI/` 取 zip。
2. 先看 `summary.txt` 的「---- 锚点统计 ----」和「---- 子系统状态 ----」：
   多数问题在这一段就能定性（权限没批、通道没就绪、某个节点一次没触发）。
3. 再看「---- 冷启动 ----」：确认是系统开机慢还是桌面启动慢。
4. 最后进 `logs/`，按锚点或 tag 过滤：
   ```bash
   unzip uni-logs-*.zip -d pack
   grep '\[ANCHOR\]' pack/logs/*.txt | head -50
   grep 'UNI/Vehicle' pack/logs/*.txt | tail -100
   ```
