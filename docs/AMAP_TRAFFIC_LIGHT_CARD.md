# 高德红绿灯数据与 UNI 卡片设计

2026-10-26。两份本地 APK 静态分析和卡片设计已完成；0.6.9 已实现卡片与广播接入，完成 Android 9 模拟器验证。方向和灯态枚举已于 2026-11-15 实车实测修正（见「标准通道改用实测枚举」一节）；`dir` 2/3、`status` 2/3 仍待补。

## 结论

具备接入路径。官方版含标准红绿灯广播构造与发送链，修改版保留该链，同时增加了巡航多方向广播。参考图中的左转、直行并排布局可以设计，但只有收到同一批次的多方向数据时才展示。不能根据多个时刻收到的官方单方向数据，拼出看似同时有效的多个信号。

静态代码证明接口存在，不证明当前账号、地区、渠道配置和具体路口一定触发发送。仍需在有红绿灯信息的路口记录广播，核对方向、灯态枚举、数据更新周期与退出条件。

## 输入 APK

| 文件 | 包名 | 版本 |
| --- | --- | --- |
| `Auto_9.5.0.600013_release_signed.apk` | `com.autonavi.amapauto` | 9.5.0.600013 / 26000001 |
| `9.5高德-完美自动投屏3D彩虹.apk` | `com.autonavi.amapautp.yh` | 9.5.0.600013 / 26000001 |

SHA-256 与精简证据见 [amap-traffic-evidence.json](../analysis/amap-traffic-evidence.json)。不同包名需要适配桌面的导航应用关联；不能写死官方包名。

## 官方标准协议

发送 action：`AUTONAVI_STANDARD_BROADCAST_SEND`，`KEY_TYPE=60073`。

| Extra | 类型 | 静态代码确认的内容 |
| --- | --- | --- |
| `dir` | int | 单个方向的原始值；2026-11-15 实测 1=左转、4=直行，其余待补 |
| `trafficLightStatus` | int | 原始灯态；2026-11-15 实测 1=红、4=绿，其余待补（**与巡航通道不是同一套**） |
| `redLightCountDownSeconds` | int | 模型定义的红灯倒计时秒数 |
| `waitRound` | int | 模型定义的等待轮次；显示规则待实测 |
| `greenLightLastSecond` | int，可选 | 受 `ib.t()` 条件控制，不保证每次携带；不能直接把它当成总是有效的绿灯倒计时 |

路径：`v70.a(JsonHeader,String)` 将 JSON 解析成 `RspTrafficLightsCountdownInfoModel` → `wh0.c()` 写入以上 extras → 广播发送分支 `fd.m(Intent)` 设置 action → `se.sendBroadcast(Intent)`。

本版本 `wh0.c()` 不写 `lightsData` 数组；不能套用其他版本或网络示例中同名协议的扩展字段。`TRAFFIC_LIGHT_NUM` / `trafficLightNum` 是路口灯数量类信息，不是实时灯态和秒数。

以上是本地 APK 证据。高德公开 [AutoSDK 灯态图层文档](https://a.amap.com/amapauto/static/bl/500/android/api/classcom_1_1autonavi_1_1gbl_1_1layer_1_1_guide_traffic_light_layer_item.html) 也定义了灯态和倒计时，但 SDK 图层 API 与已安装应用的对外广播是两套接口，不能用 SDK 文档替代本次 APK 的协议核对。

## 修改版巡航协议

新增类 `floatapp.CruiseTrafficLightBroadcaster`。

- `AutoamapPluginManage` 初始化它的 application context。
- `CameraLightInteract.notifyCameraLightInfosImpl(CameraLightInfoWrapper)` 在原始通知后调用 `onCameraLightInfo`。
- action 为 `NAVITOOL_CRUISE_TRAFFIC_LIGHTS`，extra `data` 是 JSON 字符串。
- JSON 顶层：`ts`（发送端当前毫秒时间）、`lights`（数组）。
- 每个数组元素：`direction`、`status`、`countdown`、`waitNum`、`showType`，均来自 `CameraLightInfo` 的字段。
- 发送函数直接调用 `Context.sendBroadcast(intent)`；这个函数没有指定接收包名或 permission。

因此该修改版确实具备把多个方向发送给其他应用的代码路径，更适合参考图。类名中的“Cruise”不等于已经证明未导航时所有路口都会发数据；仍以实测触发为准。

## 视觉方案

设计文件：[可浏览设计](../design/traffic-lights.html)、[1920×1080 深浅色设计图](../design/traffic-lights.png)。全部数据明确标为示例。

- 沿用 UNI 的表面色、主题色、文字色和可调圆角；毛玻璃遵循桌面设置，沿用非实时背景处理。
- 标题为“红绿灯”，右侧轻量展示关联地图名称，点击标题打开关联地图。
- 方向用线条箭头和淡色圆形底；倒计时用大号等宽数字，单位弱化。不使用无法从数据得到的整周期进度环。
- 灯色保留红 / 黄 / 绿语义，不随用户主题色改变；同时显示“红灯 / 黄灯 / 绿灯”文字，避免只依靠颜色。
- 单方向：紧凑横向布局，标题在左、方向和秒数在右。建议卡片尺寸 4×2。
- 多方向：两方向并排，大尺寸可扩为三方向；同批次数组决定显示数量。建议 4×3，更多方向用 8×3，实际网格适配时验证最小可读尺寸。
- 未提供倒计时但灯态有效：保留方向与灯态，秒数用 `—`。未知枚举使用中性色，不猜方向或灯态。
- 暂无信号 / 数据失效使用两个轻量空状态，不保留上次数字。不会为了保持视觉充实添加虚构的路口名、距离或车道。

## 导航模式现状（2026-11-14 定案，以此为准）

导航用的是官方标准广播（`KEY_TYPE=60073`），一包只带**一路** `dir`，所以卡上**永远只有一列**。
现在的显示（已实现，和巡航共用同一套渲染）：

| 项 | 现状 |
|---|---|
| 方向 | `dir` 1 → 左转、4 → 直行，表外为 `unknown` |
| 灯色 | `trafficLightStatus` 1 → 红、4 → 绿，表外灰；**绿灯最后 3 秒按黄灯画**（展示层规则） |
| 倒计时 | `redLightCountDownSeconds`，递减到 0 后显示 `—` |
| 列数 | 1 列（协议限制；多方向只有巡航批量包才有） |

**与稿子的差异，按用户 2026-11-14 决定不处理，以现状为准**：稿子 v2 对单方向有
`.tlg-solo`（灯环 84 / 读秒 88 / 状态词 / 读秒进度条），我们不做，单方向与两路三路同尺寸。

### 两个已知风险（未实测，出问题按日志改）

1. ~~**标准通道的枚举是复用的，不是实测来的。**~~ **已于 2026-11-15 实测并改表**，
   见下一节。现有枚举只覆盖 `dir` 1/4 与 `status` 1/4；`dir` 2/3、`status` 2/3 至今
   没有实车样本，仍是 `unknown`（灰灯 + 方向待确认），等下次抓日志补。
2. **`redLightCountDownSeconds` 的字段名是「红灯倒计时」。** 绿灯期间它填的是绿灯剩余、
   还是上一轮红灯的残值，从未实测。若绿灯时该值不刷新，卡上会出现一个**不动的数字**——
   那种情况就应该改成「绿灯不显示倒计时」。同样只能靠实车日志判断。

## 变更：标准通道改用实测枚举（2026-11-15）

实车现象（三张现场照片 + 同日诊断包 `uni-logs-20261115-161849`）：

| 照片 | 高德实际 | 报文 raw(dir/status) | 改前显示 | 改后 |
|---|---|---|---|---|
| 15:38 | 直行红 24、下轮绿 25 | `4/1` | 绿、无箭头、25 | 红、直行、25 |
| 15:40 | 直行绿 8（另有红 3） | `4/4` | **灰**、无箭头、9 | 绿、直行、9 |
| 16:13 | 左转红 20 | `1/1` | **绿**左转、19 | 红左转、19 |

对齐方式：16:13 那张拍在日志时间 16:13:44，落在 `1/1` 段（16:12:39 起、倒计时 85 递减）
的第 65 秒，85−65 = **20**，与高德界面逐秒吻合；卡片本地递减到 19。同一路口的左转相位
在日志里是 `1/1`(85s 红) → `1/4`(31s 绿) 交替两轮，因此 `status=4` 是绿。

结论：**标准广播的 `dir`/`status` 与巡航不是同一套枚举**，而
`analysis/amap-traffic-evidence.json:69` 原本就写着
`"yh CameraLightInfo cruise only; do not apply to standard dir/status"`。2026-11-14 那次
「沿用巡航表」的决定是错的，直接导致红灯显示绿、绿灯显示灰。

改法（只动 `AmapTrafficLightProtocol.standard()`，`cruise()` 一个字没改）：

```java
String dir  = direction == 1 ? "left" : direction == 4 ? "straight" : "unknown";
String lamp = status    == 1 ? "red"  : status    == 4 ? "green"    : "unknown";
```

单测 `standardMapsRedStatusToRedAndGreenStatusToGreen` 锁住这三组实测值，
`cruiseKeepsItsOwnVerifiedTable` 锁住巡航通道不受影响。

## 变更：标准通道沿用巡航枚举（2026-11-14，已被上一节取代）

实车现象：导航状态下红绿灯卡只有一个灰灯 + 倒计时，巡航状态正常。原因是标准通道
（`AUTONAVI_STANDARD_BROADCAST_SEND` / `KEY_TYPE=60073`）的 `dir` 与 `trafficLightStatus`
从未实测过，实现里刻意把 direction/lamp 都填 `unknown`（本文件前面写着「语义待实测」）。

用户决定：**标准通道直接用巡航那套已验证的表**（`1/2/3 = 左/直/右`；`0 = 红`、`1/2 = 绿`），
先把导航状态的卡片点亮；原始值继续留在 `rawDirection` / `rawStatus`，`signalDetail()` 的周期
日志会以 `left/red@20(raw 1/0)` 这种形式一起打印，实测出现反例（导航里绿灯却显示红）时照
日志改表即可，不用再猜。

风险与边界没变：这是**显示级**的复用，不等于标准通道枚举已验证；`greenLightLastSecond`
仍然只记录不使用。

## 变更：绿灯最后 3 秒按黄灯展示（2026-11-14）

用户规则：只有**绿灯倒计时 ≤3 秒**时切黄，红灯一律不管。

实现落在展示层（`TrafficSignal.lampAt(elapsedMs)`）：`lamp == green` 且 `remaining` 非空且
`≤3` 时返回 `amber`（灯珠颜色、语义标签、卡头小灯都跟着走），秒数照常显示 `3/2/1`。
绿灯没有倒计时（显示 `—`）时不切 —— 没有秒数就没有依据，仍按数据里的灯态画，等下一批广播。
数据层的 lamp 不变，所以日志与上报仍是原始灯态。

## 实现契约与验证边界

实现已拆分为 `AmapTrafficLightProtocol`（纯协议解析）、`AmapTrafficLightAdapter`（单个共享接收器、有效期与来源关联）、`TrafficLightSnapshot`（Flutter 数据契约）和 `TrafficLightCard`（响应式展示）。完整实现与验证见 [0.6.9 记录](IP753_0_6_9.md)。

1. 两个协议分别解析，保留 raw direction/status；实测前不共用未经核对的枚举表。
2. 来源随用户关联的地图切换；停止导航、切换地图、空数组或明确无效信号时清空。官方广播没有来源包名字段，不通过 intent 自带的可伪造 extras 声称已验证发送方；仅作为导航提示使用。
3. 使用本机单调时钟计时。修改版 `ts` 可用于诊断，不直接依赖两端墙钟一致。
4. 有效期按真实广播周期确定。收到快照后可每秒更新数字，但不在零秒时自动切换红绿灯，不在失效后继续外推。
5. 只在当前可见卡片且数据有效时启动秒级 ticker；不重绘地图、桌面和全局底栏，不做高频发光动画，适应 IP753 的性能约束。

待上车核对：官方导航中 `60073` 是否实发、标准字段的枚举与可选绿灯值、修改版巡航数组是否实发、两方向是否同批更新、切换路口/退出导航的清空方式、实际更新间隔和断网行为。

设计验证：深浅色、单方向、多方向和两个空状态均已导图；4 项布局检查通过（画布尺寸、卡片内部边界、卡片外部边界、示例标记），浏览器无运行异常。实现阶段另有 Flutter 组件、Java 协议和 Android 9 模拟器验证，没有将模拟数据当成实车接收成功。

## 复现

```sh
/tmp/uni-apk-venv/bin/python tools/analyze_amap_traffic.py ../amap
node tools/render_traffic_lights.mjs
```

静态分析原始输出位于被 Git 忽略的 `analysis/raw/amap/`；Git 仅管理自写工具、精简事实与设计，不提交第三方 APK 或整包反汇编。
