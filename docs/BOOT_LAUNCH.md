# 开机自启动（记忆配置 · 计划）

设置 → 记忆配置里的第三个区块（上面是并排的「驾驶模式 / 自动启停」，下面还有「开机自动播放音乐」）。
一行就是「应用 + 开机后第几秒启动」，可以加任意多条，
例如「开机立刻启动高德」「开机后 5 秒启动 LX Music」「开机后 8 秒启动 UNI 语音」。

## 语义

- **时间基准是开机**（`SystemClock.elapsedRealtime()`），不是桌面进程起来的时刻。桌面进程
  在第 5 秒才起来时，「开机后 8 秒」仍然按真实开机时刻补上；「开机立刻」在进程可用后
  250 ms 内执行。
- **每次开机每行只启动一次**。已启动的 key 连同本次开机的 `bootWall`
  （`System.currentTimeMillis() - elapsedRealtime()`）落在 prefs 里；桌面进程崩了重启，
  同一次开机内不会重放；换了开机周期（`bootWall` 相差超过 60 秒）自动清空。
- **只在开机窗口内动手**：`elapsedRealtime() > 10 分钟` 就完全不排程，白天手动重启桌面
  不会突然弹应用。
- **总开关默认关闭**，关着时计划行照原样显示，但一个应用都不启动。
- 同一秒内的多条计划按添加顺序每次错开 250 ms，避免同时抢前台。
- 上限 12 条、单条 0–600 秒；同「应用 + 秒数」重复添加视为已存在。

## 存盘

`SharedPreferences("launcher")`：

| 键 | 类型 | 含义 |
| --- | --- | --- |
| `bootLaunchEnabled` | boolean | 总开关 |
| `bootLaunchPlans` | String | JSON 数组 `[{"id":"包名/类名","delay":5}]`，`id` 与应用目录的 `id` 一致 |
| `bootLaunchBoot` | long | 最近一次排程的 `bootWall`，用来判断是否换了一次开机 |
| `bootLaunchFired` | String | 本次开机已启动过的 key 数组，key 为 `id@delay` |

## 动作（`MethodChannel('xyz.i4o.uni.launcher/platform')` · `action`）

| action | 参数 | 说明 |
| --- | --- | --- |
| `boot-launch-enabled` | `enabled` | 开关；打开时立即尝试排程 |
| `boot-launch-add` | `value`=应用 `id`，`zone`=秒数 | 越界或重复返回 toast，不写入 |
| `boot-launch-remove` | `value`=key（`id@delay`） | 删一行 |
| `boot-launch-clear` | — | 清空全部计划 |
| `boot-launch-run` | `value`=key | 立刻启动一次，用于验证；不改变开机计划、不写 fired |

## 快照

`state.bootLaunch`：

```json
{
  "enabled": true,
  "plans": [{"key":"cn.toside.music.mobilegcx/...@5","id":"...","package":"cn.toside...",
             "delay":5,"installed":true,"state":"launched","reason":"","atSec":142}],
  "maxDelay": 600, "maxPlans": 12, "bootSeconds": 300, "demo": false
}
```

`state` 是这一进程里的最近一次结果（`launched` / `failed` / `skipped`），设置页把它显示成
「已启动 / 上次未启动 / 上次已跳过 + 原因」。`installed` 由 `PackageManager` 现查，
应用被卸载后行还在但会标「应用未安装」。

## 启动路径

1. 先用应用目录里的组件名 `apps.launch(id)`（`ACTION_MAIN` + `CATEGORY_LAUNCHER` +
   `FLAG_ACTIVITY_NEW_TASK`）；
2. 目录还没建好时按包名兜底 `apps.launchPackage(pkg)`；
3. 两者都不行就记 `failed`，原因「应用未安装或无法启动」。

演示模式下只记 `skipped`，不启动任何东西。

`MainActivity.onCreate` 与 `GlobalDockService.onCreate` 都会调
`runtime.scheduleBootLaunch()`，进程内只排一次。

## 实测

领克 05 / DCY11 车机上已验证：添加计划 → 列表出现「LX Music-歌词秀 · 开机后 5 秒」→
点行内 ▶ 立刻启动，应用被拉起，行状态变「已启动」。开机全流程需要整车断电重启才能完整覆盖，
目前仅验证到进程内排程与启动路径。
