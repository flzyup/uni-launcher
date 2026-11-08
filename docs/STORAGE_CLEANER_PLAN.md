# 垃圾清理（UNI 菜单第四项）

规划 2026-05-19，实现同日完成，同日按「要 360/SD 女佣那种全系统清理」重做一版。
右下角 UNI 菜单第四项「垃圾清理」：点击 → 自动申请存储权限 → 一次遍历扫全机 → 分类勾选 → 二次确认 → 清理 → 报实测释放量。

状态：**全系统版已实现，实车（领克 05 / MSY8996 / Android 9）采集验证并据此优化到 v3**；规则 8 条（3 条默认勾选）、白名单 10 条、59 项规则断言 + 8 个界面用例 + 412 项既有 Flutter 用例全绿，Android 编译通过。实车采集脚本 `tools/probe_storage.py` 已按新类目扩展。

v3 相对 v2 的改动全部来自实车数据（`analysis/du-sdcard.txt`，22158 项 / 2.70 GB 全盘清单，按引擎逻辑回放）：

| 改动 | 依据 | 效果 |
| --- | --- | --- |
| `ad-cache` 增补 `.csj`/`.pangle`/`.txad`/`.gdt`/`.ksad`/`.mob` | 车上唯一命中的广告目录是 `/sdcard/Download/.csj`（穿山甲），原 7 组 glob 全是 0 命中 | 广告类目从 0 变成有命中 |
| `log` 增补 `*.log.?*` | `vr/log/GCF_DDFW_*.log.1/.2/.3` 共 25 MB 不匹配 `*.log`（glob 不支持 `[0-9]` 字符类，只能用 `?`） | 日志类目 99.2 → 128.5 MB |
| `never` 增补 `/sdcard/*.tgz`、`*.tar.gz`、`*.tar`、`*.img`、`sys-apks*`、`*speech*.tgz` | 车上 `sys-apks.tgz` 835 MB + `vr-speech.tgz` 189 MB 是系统备份，原先只因「不到 90 天」没被 `large-unused` 列出 | 放久也不会被误勾 |
| `snapshot` 增加 `purgeFiles`/`purgeTotal`/`scanned`/`scanMs` | 缩略图类目一台车就有 13762 个文件，清理时只按类目跳变看着像卡死 | 面板显示「正在清理 3200 / 13762 个文件」「扫描 460 项 · 1.2 秒」 |
| 修 `storageUuid()` 反射目标类 | `getUuidForPath` 在 `android.os.storage.StorageManager` 上，原先错调 `StorageStatsManager` → `NoSuchMethodException` → 退回全零 UUID → 系统把查询当成别的卷，**所有应用缓存一律回 0** | 「应用缓存」从「系统未开放存储统计」变成 `36.2 MB / 33 个应用` |

### 实车实测（2026-11-05，领克 05 / IP753 / MSM8996 / Android 9，`192.168.22.18`）

装 `0.7.6+2055` 后点 UNI → 垃圾清理：

| 类目 | 面板数字 | 与外部测量对照 |
| --- | --- | --- |
| 桌面缓存 | 20 KB | `du` 一致 |
| 应用缓存 | **36.2 MB（33 个应用）** | `dumpsys diskstats` 报 `App Cache Size: 35328000`（33.7 MB），吻合 |
| 系统应用缓存 | 53.5 MB（124 个应用） | 默认不勾 |
| 应用外部缓存 | 0 | 车上 6 个 `cache` 目录都是空的，`du` 报的 52 KB 全是目录块 |
| 缩略图缓存 | 250.0 MB | 13762 个文件；`du -k` 报 188.7 MB，差的是 `.thumbdata4` 的 sparse 与逻辑大小（`File.length()` 口径） |
| 日志与临时文件 | 128.4 MB | 含 `vr/log/*.log.1/.2/.3` 25 MB |
| 安装包 | 608.2 MB | 比回放的 756.4 MB 少 148 MB —— 版本校验真的在拦未安装/已更新的包 |
| **可清理合计** | **1.1 GB / 7 项** | 默认勾选 414.6 MB |
| 扫描 | 471 项 · 3.7 秒 | 单遍遍历，预算未触顶 |

结论：`dumpsys diskstats` 与面板在应用缓存上差 0.9 MB（两次测量间隔），说明 `StorageStatsManager` 这条路是真数据而不是估算。

关键设计（与上一版的差别）：

1. **面板一打开就自动申请存储权限**，原生 `MainActivity` 直接弹系统框，界面上没有「去授权」入口，也不跳设置页。
2. **一次遍历喂全部规则**：缩略图、日志、广告缓存、空目录、卸载残留、安装包、大文件在同一次 `walk` 里同时算清，不是每类各扫一遍全盘。
3. **覆盖全系统**：除本应用缓存，还有所有应用的内部 `cache/`（反射 `deleteApplicationCacheFiles`）、公共存储里的 `Android/data/*/cache`，以及 `/sdcard` 全盘按规则命中项 —— 不是只清自己。

已落地文件：

| 层 | 文件 | 作用 |
| --- | --- | --- |
| 规则引擎 | `app/android/app/src/main/java/xyz/i4o/uni/launcher/core/CleanerRules.java` | 纯 JVM：路径合法性、glob（带编译缓存）、白名单优先 + 例外口、`matchAll` 多规则命中、扩展名/体积/年龄门槛、剪枝 |
| 清理器 | `app/android/app/src/main/java/xyz/i4o/uni/launcher/integration/StorageCleaner.java` | 单遍扫描、多桶累计、清理、取消、进度节流、权限状态、类目快照 |
| 规则数据 | `app/android/app/src/main/assets/cleaner/rules.json` | 8 条规则 + 9 条 `never` 白名单 |
| 运行时 | `LauncherRuntime.java` | `cleaner` 字段、`state.cleaner`、`cleaner-scan/clean/cancel/grant/permission` 五个 action、`PermissionHost` 接口 |
| 权限 | `MainActivity.java` | `requestStoragePermission()`（requestCode 4107）+ 结果回调重扫 |
| 面板 | `app/lib/widgets/storage_cleaner_panel.dart`、`app/lib/model/storage_cleaner.dart` | 分组列表、勾选、二次确认、进度、错误与权限等待态 |
| 入口 | `bottom_dock.dart`（`uni-menu-cleaner`）、`global_panel_app.dart`（`case 'cleaner'`）、`GlobalDockService.java`（面板白名单） | 与「车辆信息」「传文件」同一条路径 |
| 采集 | `tools/probe_storage.py` | 实车只读采集：外部缓存/卸载残留/全盘安装包/空目录 → `analysis/storage-probe-<日期>.json` |
| 离线测试 | `tools/test_cleaner_rules.py` + `app/native-tests/test/.../CleanerRulesTest.java` | 50 项断言，不需要设备 |

验证命令：

```powershell
python tools/test_cleaner_rules.py                            # 规则引擎 50 项断言
cd app; & "C:\dev\flutter\bin\flutter.bat" analyze             # No issues found
cd app; & "C:\dev\flutter\bin\flutter.bat" test                # 400 项
cd app\android; .\gradlew.bat :app:compileDebugJavaWithJavac   # BUILD SUCCESSFUL
python tools/probe_storage.py -s <serial>                      # 实车采集（只读）
```

---

## 1. 现状事实（改动落点）

| 环节 | 位置 | 事实 |
| --- | --- | --- |
| 右下角图标 | `app/lib/widgets/bottom_dock.dart:377` `ValueKey('uni-menu')` | 底栏最右端的 UNI 图标，点击调 `showUniDockMenu` |
| 菜单分发 | 同上 `:404` | 先试 `c.presentGlobalPanel('uni-menu')`，全局底栏开着就由独立面板窗口渲染；否则本窗口 popup |
| 菜单项 | 同上 `:458-480` | 四项：车辆信息、传文件、**垃圾清理**、UNI桌面设置；每项 `_UniPopupItem`，行高约 62 设计单位 |
| 面板窗口分发 | `app/lib/screens/global_panel_app.dart:88` | `case 'cleaner': await showCleanerPanel(...)` |
| 原生面板白名单 | `GlobalDockService.java:352` | 已含 `"cleaner"`，不在此表的面板名直接 return |
| 命令通道 | `LauncherRuntime.handleOnMain` | `action` + `value` + `zone` 同步执行；`transfer-*`、`quark-*` 已证明这套模式可用 |
| 快照下发 | `LauncherRuntime.snapshot()` | `state.put("cleaner", cleaner.snapshot())`，Dart 读 `native['cleaner']` |
| 弹层 | `launcher_dialog.dart:10` `showLauncherSheet` | 880×780 设计单位，面板窗口里自动 `DockWindowScope.expand` |
| 图标 | `uni_icon.dart:49` | `Icons.cleaning_services_outlined → 'broom'`，资源已存在 |
| 权限先例 | `MainActivity` 4105（日历）/ 4106（录音） | 同一种 `requestPermissions` + `onRequestPermissionsResult` 写法，4107 沿用 |

签名事实：`targetSdk=28`，全项目只有一张证书——AOSP 测试签名（`build.gradle.kts` 的 `aospTest` signing config，SHA-256 `C8:A2:E9:BC:…`，实车包与开发包同一张），manifest 里 `STATUS_BAR_SERVICE`、`INSTALL_PACKAGES` 等 signature 权限实际生效 → 本应用是特权应用，`DELETE_CACHE_FILES` / `PACKAGE_USAGE_STATS` 随签名自动授予，只有 `WRITE_EXTERNAL_STORAGE` 要过一次系统弹窗。

---

## 2. 能力边界（API 28 上真实存在的四条路）

| 能力 | API | 权限 | 能清什么 |
| --- | --- | --- | --- |
| 自删缓存 | `File.delete` | 无 | 本应用 `getCacheDir()` / `getCodeCacheDir()` / `getExternalCacheDir()` |
| 统计各应用占用 | `StorageStatsManager.queryStatsForPackage` | `PACKAGE_USAGE_STATS`（signature\|privileged） | 只读：`getCacheBytes()` / `getDataBytes()` / `getAppBytes()` |
| 逐应用清缓存 | 反射 `PackageManager.deleteApplicationCacheFiles(pkg, IPackageDataObserver)` | `DELETE_CACHE_FILES`（signature\|privileged） | 每个应用的 `cache/`，**等价系统「应用 → 存储 → 清除缓存」**，内部与外部缓存一起清 |
| 删公共存储文件 | `File.delete` | `WRITE_EXTERNAL_STORAGE`（dangerous，API 28 无分区存储） | `/sdcard` 下规则命中的文件，含 `Android/data/*/cache` |

做不到、也没写进 UI 的：
- `/data/tombstones`、`/data/anr`、`/data/local/tmp`、其他应用 `files/`/`databases/`/`shared_prefs/` —— 无 root 不可达，扫描时跳过且不计入。
- 「内存加速」是另一件事，本功能不含。
- 清理量一律**前后实测**，不用估算值冒充结果。

---

## 3. 规则从哪来

### 3.1 系统 API 自带语义（不用写路径规则）

「应用缓存」这一类不需要知道任何路径：PMS 知道每个应用的 cache 在哪，`deleteApplicationCacheFiles` 就是系统设置那个按钮的实现。我们只做「扫描 → 列大小 → 调用 → 报差值」。这一条覆盖了用户大部分心理预期（「微信/地图/浏览器占了多少」），且永远不会因为路径写错删错东西。

### 3.2 Android 平台约定目录（写进规则文件的常量）

| 类别 | 逻辑路径 | 依据 |
| --- | --- | --- |
| 外部缓存 | `/sdcard/Android/data/*/cache`、`*/code_cache` | `getExternalCacheDir()` 的固定位置 |
| 缩略图 | `/sdcard/**/.thumbnails`、`/sdcard/**/thumbnails` | AOSP MediaProvider 历史约定 |
| 日志/临时 | `*.log`、`*.tmp`、`*.dmp`、`*.crash`、`LOST.DIR` | fat 卷修复遗留 + 应用自写日志的通行命名 |
| 空目录 | 任意 `listFiles().length == 0` 的目录 | 系统不依赖空目录存在 |
| 卸载残留 | `/sdcard/Android/{data,obb}/<pkg>` 且 `getPackageInfo` 抛 `NameNotFoundException` | 唯一权威判据：包管理器说不存在 |
| 安装包 | `*.apk`/`*.apks`/`*.xapk`/`*.apkm` 且归档 `versionCode ≤` 已装版本 | `getPackageArchiveInfo` 对比 `getPackageInfo` |

### 3.3 车机现场采集

车机是定制系统（`dcy11` / `AP_IHU_CN_IP753_21082602`），OEM 目录命名只有现场能拿到。`tools/probe_storage.py` 一次只读采集：

```text
df -k /data /sdcard                     # 卷容量
dumpsys diskstats                       # 分类占用（缓存/照片/应用…）
du -k -d 2 /sdcard                      # 顶层占用排行
du -sk /sdcard/Android/data/*/cache ... # 每个应用的外部缓存
ls -1 /sdcard/Android/data | 对比已装包  # 卸载残留
find /sdcard -name '*.apk' -size +512k  # 全盘安装包
find /sdcard -type d -empty             # 空目录样本
du -sk /sdcard/<候选>                   # 每条候选项的体积
```

输出 `analysis/storage-probe-<日期>.json`，每条候选 `verified:false`，含汇总（`externalCacheBytes`/`orphanBytes`/`apkBytes`/`emptyDirs`）。确认后才手工改 `rules.json`。

### 3.4 开源分类法（只借结构，不抄数据）

| 项目 | 许可证 | 借了什么 |
| --- | --- | --- |
| [SD Maid SE · SystemCleaner](https://sdmse.darken.eu/zh-hans/systemcleaner) | 专有（文档） | 过滤器维度：路径前缀/包含/后缀/精确 + 名称匹配 + 体积/时间门槛；类目清单里的过期安装包、LOST.DIR、缩略图、系统日志、广告/分析残留；`SystemCrawler` 扫 SDCARD 时跳过 `Android/media` 等段 —— 我们照此实现了 `skipSubtree()` |
| [DirClean/Rules](https://github.com/DirClean/Rules) | GPL-3.0 | 每个叶子目录一个 JSON + `mode` 枚举（CACHE/LOG/AD/UNINSTALL/USER_DATA）+ `willClean`/`carefully_clean` 双开关。我们的 `default` + `verified` 双闸门同构：**未确认的规则不许默认勾选** |
| [haobo-cleaner](https://github.com/138849070/haobo-cleaner) | GPL-3.0 | `CleanRule(roots, include, exclude, excludeDirs, minSize, maxDepth)` 成了我们的规则字段；模块划分（常规/应用/残留/空目录/大文件/安装包）与「大文件遍历全盘」「`*.apk/*.apks/*.xapk/*.apkm`」「结果上限防 OOM」三条工程结论一并采纳 |

**不抄数据**：两个 GPL 项目的规则 JSON 一行都没复制，`rules.json` 按 AOSP 约定 + 本机实测重写；SD Maid 是专有软件，只参考公开文档里的分类维度。

---

## 4. 规则文件与匹配语义（`assets/cleaner/rules.json`，version 2）

只由 Java 读，Dart 只显示原生下发的类目名，避免两份规则漂移。字段与 `CleanerRules.Rule` 一一对应。

字段语义（`CleanerRules` 里写死，规则文件不可改）：

- `roots`：扫描起点，同时是安全边界。
- `paths`：**前缀**匹配（`/sdcard/DCIM` 不匹配 `/sdcard/DCIMX`）。
- `globs`：`**/` 跨段且允许零层（`/sdcard/**/.thumbnails` 匹配 `/sdcard/.thumbnails`），`**` 跨段、`*` 单段、`?` 单字符，大小写不敏感，正则编译结果按 pattern 缓存。
- `exclude`：反向排除，优先级高于 `paths`/`globs`。
- `extensions`：小写不带点。
- `contents`：命中目录时只删内容、保留目录本身（缓存类用）。
- `check`：语义检查器名 —— `apk-outdated`、`orphan-package`、`empty-dir`。**不认识的 `check` 一律判 false：宁可少清，不猜。**
- `default` + `verified`：两者同时 true 才允许默认勾选（`Rule.decisionEnabled()`）。
- `maxDepth`：该规则的深度上限（存储根为 0），`/sdcard/Android/data/<pkg>/cache` 恰好是 3。

匹配顺序硬性规定：**先 `never` 再 `rules`**；一个文件/目录只归属**按文件顺序第一条命中且 `check` 通过的规则**（`matchAll` 返回有序命中列表，扫描器取第一个 accepted），所以顺序即优先级，也不会重复计数。`never.except` 只放宽本条白名单（照片目录整体受保护，`.thumbnails` 例外）。所有删除前用 `getCanonicalPath()` 归一，逃出根的路径一律拒绝 —— 这是防「规则写错删到别处」的技术兜底，`CleanerRulesTest` 覆盖 `..`/`.`/`//`/NUL/反斜杠/超长五种逃逸。

当前规则集（顺序即优先级）：

| # | id | 名称 | 分组 | 阈值 | 默认勾选 | 风险 |
| --- | --- | --- | --- | --- | --- | --- |
| 1 | `external-cache` | 应用外部缓存 | 缓存 | `contents:true`，深度 3 | ✅ | 无 |
| 2 | `thumbnails` | 缩略图缓存 | 系统垃圾 | `contents:true`，深度 8 | ✅ | 无 |
| 3 | `ad-cache` | 广告与分析缓存 | 系统垃圾 | 7 组 SDK 目录 glob | ❌ | 低 |
| 4 | `log` | 日志与临时文件 | 系统垃圾 | 3 天，深度 8 | ✅ | 低 |
| 5 | `orphan-data` | 卸载残留 | 残留与安装包 | `check:orphan-package` | ❌ | review |
| 6 | `apk-leftover` | 安装包 | 残留与安装包 | `check:apk-outdated`，≥512KB，≥1 天 | ❌ | review |
| 7 | `empty-dir` | 空文件夹 | 系统垃圾 | `check:empty-dir`，深度 6 | ❌ | 低 |
| 8 | `large-unused` | 长期未动的大文件 | 大文件 | ≥200MB 且 ≥90 天 | ❌ | review |

内置三类不走规则文件，由 `StorageCleaner` 直接产出：`self-cache`（桌面缓存，默认勾 ✅）、`app-cache`（应用缓存，默认勾 ✅）、`system-cache`（系统应用缓存，默认不勾）。

`never` 白名单 9 条：`DCIM/**`（`except` 缩略图）、用户媒体目录、导航离线地图与应用数据（7 个已知目录）、`Android/data/*/{files,databases,shared_prefs,lib,no_backup,app_*}`、`Android/media/**`、行车记录仪视频、OTA 包与固件、`*.db*` 与 `shared_prefs`、备份目录。

红线（永不出现、永不可选）：导航离线地图、行车记录仪视频、照片音乐、`getFilesDir()` 全目录（含 `transfers/`、`quark/`、`ota/update.apk`、壁纸与设计 JSON）、`shared_prefs`、任何 `*.db`、OTA 包与固件。`Android/obb` 不在白名单里：已装应用的 obb 会因 `orphan-package` 判 false 而保留，卸载残留才会被清 —— 这是唯一允许碰 obb 的路径。

「只列不删」的基调不变：4 条 review 类永远默认不勾，必须手点；点「清理」后还要二次确认，没有「一键清空」按钮。

---

## 5. 原生实现

### 5.1 单遍扫描

```text
scanInto()
  volumeStats()         df 等价：StatFs 取 free/total
  measureSelfCache()    自身三个 cache 目录
  appCacheStats(false)  StorageStatsManager 逐包统计（非系统包）
  appCacheStats(true)   同上（系统包）
  walkStorage()         从 /sdcard 走一次，每条路径 matchAll → 第一条 check 通过的规则 → 累加进该规则的桶
  buildCategories()     3 内置 + 8 条规则 → JSON 数组
```

`walk()` 对每个目录只 `listFiles()` 一次，子数组直接传给递归；`logicalOf()` 只做字符串拼接（六万条目每个都 `getCanonicalPath()` 会明显拖慢），canonical 校验留到真正删除时。剪枝三条：`skipSubtree()`（`Android/media`）、`neverReason()` 命中（整棵不进）、已归属某规则（`handled`，不深入）。

清理用同一套 `walk()`，通过 `Walker.onlyRule()` 只认目标规则 —— 否则若某路径的第一命中规则不是它，会永远清不到。

### 5.2 统计口径

- 自身缓存、路径规则：`delete()` 返回 true 才累加 `File.length()`。
- 应用缓存：`StorageStatsManager` 前后差值（binder 删除异步，逐字节累加会偏乐观）。

### 5.3 工程约束

- 两个 Flutter 引擎共用 `LauncherRuntime` 单例，扫描状态天然共享；清理走 `cleanLock`，任务挂在 `uni-cleaner` / `uni-cleaner-clean` 守护线程，不绑 Activity —— 面板关掉照样跑完，结果 `publish()` 广播。
- 条目预算 60000（超出写 `rulesIssue` 并停止深入）、单次扫描 20 秒软超时、深度 8、APK 解析预算 60 个（`getPackageArchiveInfo` 要几十毫秒，全盘几千个会把扫描拖死）、单次清理最多 12 个类目。
- `deleteApplicationCacheFiles` 用 `Proxy` 实现 `IPackageDataObserver`，`onRemoveCompleted` 等 3 秒；失败的应用计数写进 `error`，不显示成成功。
- `StorageStatsManager.getUuidForPath(File)` 是隐藏方法，反射取主存储卷 UUID；取不到就整块降级为「系统存储统计接口不可用」。
- `PACKAGE_USAGE_STATS` / `DELETE_CACHE_FILES` / `CLEAR_APP_CACHE` / `WRITE_EXTERNAL_STORAGE(maxSdk=28)` 已在 manifest 声明。

### 5.4 权限：打开即申请

```text
面板 initState
  storageGranted == false → command('cleaner-grant') → PermissionHost.requestStoragePermission()
      ├─ 已授予 / 无需申请 → rt.handle('cleaner-permission') → cleaner.refreshPermission() → 自动重扫
      └─ 未授予 → requestPermissions(WRITE_EXTERNAL_STORAGE, 4107)
                    → onRequestPermissionsResult(4107) → 'cleaner-permission' → 重扫
```

没有 Activity 时（只有底栏在跑）`PermissionHost` 为空，`cleaner-grant` 退化成 `refreshPermission()`，不卡住。用户点了拒绝时按钮变成「等待存储权限」，旁边只留一个「重试授权」（再走一次同一入口，不跳设置页）；`readyState` 期间主按钮不可点。

### 5.5 快照与命令

```json
{
  "running": false, "phase": "idle|scan|clean", "progress": 0.0,
  "current": "应用缓存", "rev": 12,
  "free": 21474836480, "total": 68719476736,
  "storageGranted": true,
  "categories": [
    {"id":"external-cache","name":"应用外部缓存","group":"cache","risk":"safe",
     "default":true,"verified":true,"bytes":123456,"count":37,
     "note":"应用存在公共存储里的缓存，会自动重建","available":true}
  ],
  "lastClean": {"bytes": 0, "at": 0, "ids": ["self-cache"]},
  "error": "", "rulesIssue": ""
}
```

| action | value | 行为 |
| --- | --- | --- |
| `cleaner-scan` | 空 | 已在跑则忽略；起 `uni-cleaner` 线程，边扫边 `publish()` |
| `cleaner-clean` | `"self-cache,app-cache"` | 校验 id 白名单（≤12，任一未知整条作废）→ 进程锁 → 固定顺序执行 → 重建类目表 → 写 `lastClean` |
| `cleaner-cancel` | 空 | 置取消标志，协作式取消 |
| `cleaner-grant` | 空 | 有 `PermissionHost` 就弹系统框，否则直接刷新状态 |
| `cleaner-permission` | 空 | 授权结果回调：刷新 `storageGranted` 并重扫 |

---

## 6. UI

- 弹层 `showLauncherSheet(880×780, glowType: 'broom')`，`broom` 已在 `Nocturne._glow` 登记（`0x473BE2C0`）。
- 顶部：大字「可清理 X MB」（全部可清量）+ 一行说明（扫描中变「扫描中 42%」+ 当前类目）+ 右上「已用 32.1 GB / 64 GB」+ 容量条（空闲显示已用比例，运行时显示进度）。
- 中部按分组渲染：**缓存 / 系统垃圾 / 残留与安装包 / 大文件**，每组一行小标题 + 该类合计 + 细分隔线；组内每行 = 勾选框 + 图标 + 名称（+「需确认」/「待实车确认」）+ 说明 + 右侧大小。`available:false` 整行变灰、`onTap` 为 null。
- 底部：状态行（「已选 3 项 · 5.5 MB」）+ 可选「重试授权」「停止」+ 主按钮。「清理 10.0 MB」→ 点一次变「确认清理 10.0 MB」+「取消」（inline 二次确认，不叠第二层弹层，车机好点），再点才发命令。
- 说明行：`error` / `rulesIssue` / 「上次清理 今天 18:20，释放 320 MB」合并成一行，最多两行省略。
- 空状态「还没有扫描结果」；全部为 0 时按钮「暂无可清理内容」不可点。
- 无障碍：每行 `Semantics(checked:, enabled:)`；按钮高 62 设计单位、主按钮最小宽 300；勾选框 28 且带对勾不只靠颜色。
- 文案原则：不承诺"加速""省电"，只报字节数；未实车确认的类目直接写「未在实车确认，先只看不删」。

---

## 7. 改动清单

| 文件 | 改动 |
| --- | --- |
| `app/lib/widgets/bottom_dock.dart` | UNI 菜单第四项 `ValueKey('uni-menu-cleaner')`（`UniIcon('broom')`，标题「垃圾清理」+ `showCleanerPanel` 分发） |
| `app/lib/widgets/storage_cleaner_panel.dart`（新） | `showCleanerPanel` + `CleanerPanel`：分组列表、勾选、二次确认、进度、权限等待态 |
| `app/lib/model/storage_cleaner.dart`（新） | `CleanerCategory`（含 `group`）/`CleanerState`（含 `storageGranted`）、分组常量、`formatBytes`、`lastCleanLabel` |
| `app/lib/screens/global_panel_app.dart` | `case 'cleaner': await showCleanerPanel(...)` |
| `app/lib/theme/launcher_theme.dart` | `Nocturne._glow` 加 `'broom'` |
| `GlobalDockService.java` | 面板白名单加 `"cleaner"` |
| `integration/StorageCleaner.java`（新） | 单遍扫描、多桶累计、清理、取消、权限状态、反射桥、规则解析 |
| `core/CleanerRules.java`（新） | 规则引擎：glob、`matchAll`、白名单优先 + 例外、canonical 守卫（纯 JVM） |
| `LauncherRuntime.java` | `cleaner` 字段 + `PermissionHost` 接口 + `state.put("cleaner", ...)` + 五个 action |
| `MainActivity.java` | `rt.attachPermissionHost(this::requestStoragePermission)`、`requestStoragePermission()`（4107）、`onRequestPermissionsResult` 4107 分支 |
| `AndroidManifest.xml` | `PACKAGE_USAGE_STATS`、`DELETE_CACHE_FILES`、`CLEAR_APP_CACHE`、`WRITE_EXTERNAL_STORAGE(maxSdk=28)` |
| `assets/cleaner/rules.json`（新） | 8 条规则 + 9 条 never（version 2） |
| `tools/probe_storage.py`（新） | adb 只读采集：候选路径 + 外部缓存 + 卸载残留 + 全盘安装包 + 空目录 |
| `tools/test_cleaner_rules.py` + `CleanerRulesTest.java`（新） | 50 项断言 |
| `app/test/storage_cleaner_panel_test.dart`（新） | 6 个 widget 测试：分组与默认勾选、确认流、取消、停止、权限自动申请、错误行 |

---

## 8. 验证

已完成（本机，2026-05-19）：

1. `python tools/test_cleaner_rules.py` → `CleanerRulesTest passed (50 checks)`：路径逃逸（`..`/`.`/`//`/NUL/反斜杠/超长）、前缀误判、glob（`**` 零层/跨段、`*` 不跨段、`?`）、`never` 优先与 `except`、扩展名/体积/年龄门槛、`roots` 兜底、`default && verified` 双闸门、剪枝只剩 `Android/media`、`matchAll` 多规则有序命中与白名单返回空。
2. `flutter analyze` → `No issues found!`。
3. `flutter test` → 400 项全通过（含本功能 6 项）。
4. `gradlew :app:compileDebugJavaWithJavac` → `BUILD SUCCESSFUL`。

待做（需要设备）：

1. Android 9 模拟器（1920×1080）：`dd` 造 200MB 垃圾 + `mkdir -p /sdcard/DCIM/.thumbnails` + 塞两个旧 APK + 造一个卸载残留目录，走完整链路「点 UNI → 第四项 → 权限弹窗 → 扫描 → 勾选 → 确认 → 清理」，两种窗口模式各一次；断言面板报数与 `df` 差值 < 5%。
2. 回归 `python tools/verify_global_dock.py`、`tools/verify_release_dock.py`（第四项没把 popup 撑破、面板生命周期不变）。
3. 实车：先只看不删，截图类目与大小；跑 `probe_storage.py` 落 JSON，把真实存在的目录确认成 `verified:true`。
4. 第一次真删只允许 `self-cache` + `thumbnails`；`external-cache`、`app-cache` 各单独一轮，清完逐个启动导航/音乐/天气/原车设置确认无异常。
5. 全程保留 `/sdcard` 清单快照，事后 diff 证明 `never` 目录零变化。

---

## 9. 分阶段

| 阶段 | 内容 | 状态 |
| --- | --- | --- |
| P0 | 菜单第四项 + 面板骨架 + `self-cache` | ✅ |
| P1 | `StorageStatsManager` + `app-cache` 清理 + 二次确认 + 实测释放量 | ✅ |
| P2 | `CleanerRules` + `rules.json` + `probe_storage.py` | ✅ |
| P2.5 | **全系统重做**：单遍多规则扫描、`external-cache`/`ad-cache`/`orphan-data`/`empty-dir`/全盘 `apk-leftover`/全盘 `large-unused`、分组 UI、权限自动申请 | ✅ |
| P3 | 回收站（移入 `<filesDir>/trash/<ts>/`，7 天可还原）+ 清理历史 | ⬜ |
| P4 | 月度提醒（只提醒不自动删）、`unused-app` 建议 | ⬜ |

---

## 10. 已定的默认值

1. `app-cache` + `external-cache` **默认勾选** —— 与系统「清除缓存」等价，登录态不受影响。
2. `system-cache` 做，**默认不勾**，风险 `review`。
3. `thumbnails`、`log` **默认勾选**；`log` 带 3 天门槛，避免清掉正在写的日志。
4. `ad-cache`、`orphan-data`、`apk-leftover`、`empty-dir`、`large-unused` **默认不勾**，用户手点。
5. 权限**打开即申请**，界面无「去授权」；拒绝后才出现「重试授权」。
6. 菜单名「垃圾清理」—— 用户原话，比「存储空间」直白。

---

## 11. 已知风险与对策

| 风险 | 对策 |
| --- | --- |
| 规则写错删到用户数据 | never 优先 + canonical 校验 + 未确认规则不许默认勾 + 逃逸单测 |
| 清理量虚报 | 只报 `delete()` 成功字节与 `StorageStatsManager` 前后差 |
| 车机上扫描卡顿 | 后台线程 + 条目/深度/时长/APK 解析四道上限 + 160ms 进度节流 + 可取消 |
| 双引擎并发清理 | 进程级 `cleanLock` + 面板关闭任务继续 + 结果只走快照 |
| 权限被拒 | 类目 `available:false` + 写明「正在获取存储权限…」，不假装成功 |
| 清缓存导致应用重登/重载地图 | 文案写明「登录状态不受影响，离线地图不会被清理」；`system-cache` 默认不勾 |
| 全盘遍历把 `Android/data` 里的应用数据带走 | `Android/data/*/files`、`databases`、`shared_prefs` 均在 `never`；只有 `cache`/`code_cache` 可清 |
