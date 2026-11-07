# 雷电模拟器流畅度排查记录（2026-11）

起因：桌面在雷电模拟器里「卡卡的，一点都不流畅」。

结论先说：卡的主因不在 Flutter 绘制，而在**主线程上每秒数次的全量 JSON 快照**，
以及**模拟器只给了 2 个 vCPU**。两者叠在一起，桌面每动一下都在等主线程和
system_server。下面全部是实测数据，环境是 LDPlayer 9（Android 9 / 1920x1080
density 160）+ 雷电里的原车高德、LX Music。

## 实测证据

| 项目 | 修改前 | 修改后 |
| --- | --- | --- |
| 静置时主线程重拼快照 | 每秒 3~5 次，单次 30~150ms（12 秒采样里 13 条 ≥8ms） | 静置 35 秒 **0 次**；有事件时单次 32~76ms |
| 单次快照拆解 | `build` 7~46ms + `decorate` **24~123ms** | `build` 8~30ms + `decorate` **0~22ms**（冷缓存那一包） |
| 交互时的单包均值 | 41~78ms，最差 168~255ms | **16ms**，最差 49ms |
| 系统状态采样 | 每 2 秒必发一次（`memory` 字节数每次都变） | 只有 bluetooth/network/charging 等真变化才发 |
| 车辆轮询 | 每秒一次 `PERMISSION_DENIED`，每次 4 行 logcat + 7~10ms binder | 无权限时 15s 一次（有权限仍是 1s） |
| 发布节流 | 固定 80ms 上界，不看在慢机器上真花了多久 | 按上一包实测耗时自适应（耗时×2，夹在 80~400ms） |
| 客机负载 | `loadavg 8.5~8.85` @ 2 vCPU，system_server 57~118% | `loadavg 3.8~5.8` @ 4 vCPU |
| 安装包 | 雷电里装的是 `app-profile.apk`（DEBUGGABLE，21.8MB） | `flutter build apk --release`（10.1MB，无 vmsync） |

`decorate()` 那 24~123ms 的定位过程值得记一笔，因为第一次修错了：

1. 先按「整个窗口投影缓存 2 秒」修 —— 快了，但把 `globalDock.expanded/panelReady`
   这类会变的字段也钉住了，而悬浮坞有**自己的发布路径**（`GlobalDockService`
   的发射口不走 `MainActivity.handle()`）。后果是：面板开了、主窗口还认为没开，
   而且之后若没有别的包触发，就一直停在旧值。
2. 于是改成只缓存「贵且几乎不变」的东西，其余现算。实测三段拆分
   （`insetsMs/geomMs/dockMs`）后真相是 `dockMs` 独占 21~63ms —— 里面是
   `GlobalDockService.snapshot()` 的引擎探测（`isDisplayingFlutterUi()`）和
   三次 `checkSelfPermission`/`Settings.canDrawOverlays`。
3. 最终形态：窗口几何、悬浮坞状态**每次现算**（本地字段读，微秒级）；
   权限类结果（悬浮窗、WRITE_SECURE_SETTINGS、REMOVE_TASKS）按 **60 秒**
   兜底 + `invalidateWindowCaches()` 精确失效（`onResume`/用户命令/配置变化
   都算，用户去系统设置授权后返回桌面必经 `onResume`）；引擎探测同样按 2 秒
   记忆，且只对主窗口这条路径生效 —— 悬浮坞自己的窗口仍现查，它靠 `rendering`
   决定呈现。
4. 教训：**缓存的粒度必须等于「变化频率」的粒度**。整块缓存是把正确性当赌注，
   按字段缓存才是把 IPC 从热路径拿掉。


## 代码改动

1. `LauncherRuntime`
   - 发布节流从固定 80ms 改成**按上一包实测耗时自适应**（`耗时×2`，夹在
     80~400ms）。慢机器上主线程占用被压到 50% 上下，突发仍然合并成一包。
   - 新增 `publishInterval()` 供诊断输出。
   - 快照分段计时补上 `names`（appNames 反序列化）和 `proj`（apps 投影）。
2. `MainActivity` / `GlobalDockService` / `RecentTasksRepository`
   - `decorate()` 不再整块缓存：窗口几何与悬浮坞状态每次现算，只把
     「贵且只在系统动作后才变」的三项结果缓存 60 秒 ——
     `Settings.canDrawOverlays`、`WRITE_SECURE_SETTINGS`、`REMOVE_TASKS`
     （都是 binder），失效点是 `onResume` / 用户命令 / 配置变化。
   - `GlobalDockService.snapshot(Context, Boolean allowed)` 新增重载，接受调用方
     缓存好的权限结果；引擎探测（`isDisplayingFlutterUi` / `liveCount`）对主窗口
     按 2 秒记忆，悬浮坞自己的窗口仍现查。
   - 新增「快照节流」30 秒汇总日志（包数 / 均值 / 最差 / 当前间隔）和单包
     `buildMs/decorateMs/stringMs/insetsMs/geomMs/dockMs` 拆解，阈值 32ms（原来
     8ms，逐包打印本身就是噪声）。诊断包按这两行就能判断「空闲时到底拼了几次
     快照」以及慢在哪一段。
3. `OfficialCarReader`
   - `publish()` 状态没变就不再通知监听器。之前「等权限 / 等服务」也每秒
     `notifyChanged`，模拟器上等于永久的 1Hz 空转。
   - 没有车厂读取权限时轮询退到 15s（后台 30s），权限授予后最迟 15 秒回到 1s。
   - `PERMISSION_DENIED` 的 DEBUG 只在原因变化时留一条（原来每秒一条，会把
     logd 喂到 chatty，触发限流后写入阻塞）。
4. `SystemStatusAdapter`
   - 「有变化」只看会画进图标槽的字段；`memory` 照常随包发出但不参与判断。
   - `usedBytes` 按 16MB 取整（面板只显示 0.01GB），避免整包每秒都「不同」。

## 模拟器侧（本机已改，配置文件有备份）

`E:\leidian\LDPlayer9\vms\config\leidian0.config`（备份 `leidian0.config.bak-uni`）：

- `advancedSettings.cpuCount`: 2 → **4**（宿主是 8C/16T，2 个 vCPU 撑不住
  Android 9 + system_server + Flutter）
- `advancedSettings.memorySize`: 3072 → **4096**
- `basicSettings.verticalSync`: false → **true**（关着垂直同步时呈现节奏不齐，
  高帧也会看着一顿一顿）

此外两个「不是代码问题但确实在吃帧」的点：

- 雷电里装的是 **profile 包**，换成 release 包才有可比性（本次已重装）。
- 车机的「仪表歌词投屏」在模拟器上也会开窗口（`dumpsys window` 里能看到
  `UNI 歌词投屏` 和一块 `叠加视图 #1` 1920x720 的 overlay display），
  在模拟器上建议关掉，它是一块一直重绘的额外 surface。
- 逻辑画布是 1920x1080 dp（density 160），1080p 下的模糊/阴影成本比车机
  1280x720 高不少；只想验证流畅度可以把雷电分辨率降到 1280x720。

## 复现测量

```sh
# 30 秒一行：包数 / 均值 / 最差 / 当前自适应间隔
adb logcat -c && adb logcat | grep -E '快照节流|快照打包耗时'
# 客机负载
adb shell cat /proc/loadavg && adb shell top -b -n 2 -d 3 -m 8
```

判定标准：静置时不应看到「快照节流」（说明 30 秒内没有任何重拼）；交互时
`packets` 应为个位数、`gapMs` 在慢机器上自动升到 100ms 以上；`dockMs` 应该
只有冷启动那一包是两位数。

## 这套改动的代价（须知）

| 代价 | 触发条件 | 现状 |
| --- | --- | --- |
| 状态回显延迟 | 单包耗时×2 的自适应间隔，最坏 400ms | 车上单包 ~15ms，仍走 80ms 下限，行为不变；只有慢机器/模拟器会退到 200~400ms |
| 权限类字段 60 秒兜底 | 从系统设置**以外**的方式授权（adb `pm grant`、OTA 后台授予） | 最多 60 秒；正常路径（用户点授权→返回桌面）经 `onResume` 立即生效 |
| `memory` 不再触发发布 | 最近任务面板开着、整机静止 | 采样线程仍每 2 秒刷新，任何一次发包/打开面板读到的都是 ≤2s 的值；只是这个数字不再自己跳 |
| 车辆状态 15 秒粒度 | 没有车厂读取权限 | 授权后最迟 15 秒回到 1 秒 |
| 下游拿不到「心跳包」 | `publish()` 内容不变就不发 | 依赖「每 5 秒必有一包」的外部逻辑要改成事件驱动 |
| 逐包日志变粗 | 8ms → 32ms 阈值 | 30 秒汇总（均值/最差/各段）补上 |
| 装车签名 | 雷电里现在装的是 debug keystore 签名的包 | 平台签名的包装不进去，需先卸载 |

