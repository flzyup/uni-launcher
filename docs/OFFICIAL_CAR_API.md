# 官方车辆接口与接入说明

2026 年 10 月 24 日核对的 DCY11 IP753 使用 `car_service`。正式接入沿用官方 Launcher3 的 `Car.create → IConnectable → ICarFunction`，并通过同一厂商属性通道读取 HVAC、座椅和四轮胎压。旧 `ecarxcar_service` 不存在。

用户整合后的现车只读验证已报告 `connected=true`、左右温度 `22.5`、座椅加热 `0`、四轮胎压原始值 `220/215/215/215`。控制成功、显示单位和原厂图标的一致性仍须分别验收。本轮没有发送现车控制命令。

**证据身份与范围**

以下只保存摘要、精确符号和文件身份，不包含原始车辆日志、APK、厂商实现或可识别车辆的字段。完整本地输入在 `analysis/raw/official` 与 `car-reports/car-20261024-201216/oem-interfaces`，这些目录按仓库规则不提交。

| 输入 | SHA256 | 关键证据 |
| --- | --- | --- |
| 官方 Launcher3 V2023-08-21_b5bd9b1 | `203b478878d96af54bdb998770cb4e4e245d960fe069f94d839565c433a9aa6d` | `ecarx.launcher3.util.CarUtils.<init>/updateCarConnected`；现车原包哈希一致 |
| ecarx.adapterapi.jar | `f4704d7d90ad24f8100bcc686b1ca0dba005777466d75b8f65242f2785d597bf` | `CarImpl`、`CarFunction*`、`SensorImpl`、`VehicleSignalManager`、`GeelyProto.PublicAttrValue`；现车哈希一致 |
| XCHvac V2023-08-22_4376776 | `20ee0b31771388619d98d882cc9354995240cdafd664673996175f0a91339fbd` | `com.ecarx.hvac.controller.HvacController` 的实际读取、订阅与 setter 调用 |
| CarService.apk | `e19193ed9841b6ea1365d184c23753e288a509c5c4bb22a2fed629c7d1ad0f07` | `CarPropertyService`、`PropertyHalServiceIds` 的读写权限检查 |
| android.car.jar | `fd3ef21c8b5d12e1492582b4f5f382d0ce3d223e3b48a902ea110b46f3216068` | `Car.createCar(Context,ServiceConnection)`、`CarPropertyManager`、`CarPropertyValue` 的本车签名 |

提供的 `com.ecarx.hvac.inter.apk`、`com.ecarx.xcvehicle.inter.apk` 是资源覆盖包，没有 DEX；实际 HVAC 实现来自另行只读提取的 XCHvac。现车无 `com.ecarx.xcvehicle` 主包。`android.cevt.adaptapiservice.jar` 的 `IAdaptapiService` 仅提供 USB 接口，不是空调入口。官方 Launcher3 主要负责能力探测及 Widget 承载，控制合约进一步由 XCHvac 和 framework 实现佐证。既有 Launcher3 摘要见 [APK_ANALYSIS.md](APK_ANALYSIS.md) 与 [evidence.json](../analysis/evidence.json)。

**连接、生命周期和权限**

完整链路为 `com.ecarx.xui.adaptapi.car.Car.create(Context) → ICar → ICarFunction / IConnectable`，底层经 `VehicleSignalManager → android.car.Car → getCarManager("property") → CarPropertyManager`。`Car.create` 返回对象不代表已连接。

`registerConnectWatcher(IConnectWatcher)` 使用 `onConnected()`、`onDisConnected()`；底层 `registerReadyChangedCallback` 在已就绪时立即补发通知。SDK 无公开的 ready callback 注销方法，`unregisterConnectWatcher()` 仅清空当前 watcher。Reader 在进程内复用一个 SDK 连接，以弱引用分发状态；每个 Reader 的原始属性连接和自己的订阅在 `close()` 释放，因此可以适配 `onStart` 新建、`onStop` 关闭。

现车启动类路径已有 `android.car.jar` 与 `ecarx.adapterapi.jar`，本车不要求新增 `uses-library`，也不需要打包厂商实现。应用必须声明并获授 `android.car.permission.CAR_VENDOR_EXTENSION`，保护级别为 `signature|privileged`；现装自定义 Launcher 已获得该权限。

`PropertyHalServiceIds.insertVendorProperty` 对厂商属性的读写均使用此权限。`CarPropertyService.getProperty/registerListener` 检查读取权限，`setProperty` 检查写权限。平台虽另外定义 `CONTROL_CAR_CLIMATE`、`CONTROL_CAR_SEATS`，本车这些厂商 PA/CB 属性实际映射到 `CAR_VENDOR_EXTENSION`。

**精确接口与编码**

`ICarFunction` 的 getter 为 `getFunctionValue(int function[,int zone]) → int`、`getCustomizeFunctionValue(int function[,int zone]) → float`。setter 为 `setFunctionValue(int function,int value)`、`setFunctionValue(int function,int zone,int value)` 和 `setCustomizeFunctionValue(int function,int zone,float value)`，均返回 `boolean`。三参数调用中 `zone` 在 `value` 前。

| 功能 | function ID | 有证据的写值 |
| --- | --- | --- |
| 电源 | `0x10010100` | `0/1` |
| AUTO | `0x10010200` | `0/1` |
| A/C | `0x10010300` | `0/1` |
| 风量 | `0x10020100` | `0` 关闭；`0x10020101..07` 为 1–7 档 |
| 内外循环 | `0x10030100` | `0x10030101` 内循环；`0x10030102` 外循环 |
| 座椅通风 | `0x10050100` | `0` 关闭；`0x10050101..03` 为 1–3 档，仅驾驶位 |
| 座椅加热 | `0x10050200` | `0` 关闭；`0x10050201..03` 为 1–3 档，支持前排左右 |
| 温度 | `0x10060100` | 直接 `float`；本车摄氏流不使用旧适配器的乘 2 编码 |
| 同步 | `0x10060500` | `0/1` |

温度 `MAX/MIN/STEP` 为 `0x10060200/0x10060300/0x10060400`，使用浮点 getter；当前实现返回 `31/16/0.5`。前排物理左、右位置为 `zone=1/4`；驾驶位由 `CarConfig[8]` 判断，`2` 为右舵。底层厂商属性的 `areaId=0`，与高层座位 zone 不同。

| 状态 PA 属性 | 命令 CB 属性 | 内容 |
| --- | --- | --- |
| `0x21701107 / 08` | `0x21602106 / 07` | 左右温度 |
| `0x21701106` | `0x21402101` | 风量 |
| `0x21701102` | `0x2140210c` | AUTO |
| `0x21701101` | `0x21402110` | A/C |
| `0x21701116` | `0x21402124` | 电源 |
| `0x21701103` | `0x21402102` | 循环 |
| `0x21701111` | `0x21402105` | 同步 |
| `0x2170111f / 20` | `0x21402117 / 18` | 左右座椅加热 |
| `0x2170111b` | `0x21402113` | 驾驶位通风 |

现车配置中 PA 为只读 `byte[]`，CB 为只写属性；温度 CB 类型为 `Float`，表中其余 CB 为 `Integer`。Reader 的控制执行通过官方 SDK setter，不直接写 CB。

`registerFunctionValueWatcher(int[],IFunctionValueWatcher)` 提供状态通知；核心回调为 `onFunctionValueChanged(function,zone,intValue)`、`onCustomizeFunctionValueChanged(function,zone,floatValue)`。Reader 同时实现其余支持项回调。

部分 SDK 声明不能作为写合约：`getSupportedFunctionZones(int)`、`getSupportedFunctionValue(int,int)` 是空数组桩；三参数 `isFunctionSupported` 忽略第三个值参数。风量支持数组列出 AUTO，但 setter 映射不接受它；普通前除霜 `0x10040100` 被实现明确判不支持。本轮命令入口未开放除霜、风向、按摩等额外操作。

**整数报文修正与原厂映射**

`GeelyProto.PublicAttrValue` 的 field 4 名为 `int32_data`，实际读写方法却是 `readSInt32/writeSInt32`。必须先按 ZigZag 还原，再应用对应 PA 枚举：`data = (wire >>> 1) ^ -(wire & 1)`。最初读取器将它误当普通 varint，现已修复。`availability/format/status/level` 不做 ZigZag；`double_data` 保持 IEEE 754 双精度。

| wire 整数 | 还原的 PA data | 官方枚举或映射 |
| --- | --- | --- |
| 电源 `2` | `1` | `ON` |
| 同步 `2` | `1` | `ON` |
| 通风 `6` | `3` | `LVL3`，SDK 值 `0x10050103` |
| 风向 `14` | `7` | `AUT`，SDK 值 `0x10070108` |
| 风量 `2` | `1` | `LVL1`，SDK 值 `0x10020101` |
| 单位 `1` | `-1` | 未知；官方 `PaDTpmsUnitSettingData.fromInteger` 回退 `KILO_PASCAL` |

风量图标“两格”不能反推 wire 编码；通风图标看似关闭也不能把已核对的 `LVL3` 改成 OFF。需要同一时刻比较 SDK getter、PA data 与原厂界面。Reader 现在分别暴露 `wireInt32`、解码后的 `raw`、`sdkMappedValue`、`sdkExpectedValue`、`sdkMappingConsistent`；SDK 与 PA 暂时不一致时保留读取并关闭该项写能力，下一轮重新核对。

**胎压与其他车辆信息**

四轮精确方法为 `VehicleSignalManager.getPaDTpmsTirePressureFrntLe/FrntRi/ReLe/ReRi()`，返回对象有 `public final availability` 和 `Double data`。属性分别是 `0x21701053..56`。`getPaDTpmsUnitSetting()` 使用 `0x21701057`，解码后的有效枚举为 `0=kPa、1=psi、2=bar`；SDK 单位函数为 `0x25010500`。

`registerSignalChangedCallback(PaDTpms…ChangedCallback)`、`unregisterSignalChangedCallback(...)` 使用每项 public interface，回调为 `onSignalChanged(对应PA类型)`。高层 `ITireSensor` 虽定义四轮常量，`SensorImpl.getSensorLatestValue` 未实现这些分支；标准 `TIRE_PRESSURE` 属性也未配置。Reader 因此直接读取同一属性通道的 PA 报文，保留 HAL 状态与源时间戳。

四轮原始值已由用户实读。其物理单位与单位偏好是否同步变化仍未完成证据闭环；`wire=1 → data=-1` 只能确认原厂会默认 kPa，不能确认收到有效 kPa 设置。因此压力保留 `unit=raw、unitVerified=false`；单位字段保留无效状态、原始值及 `sdkFallback=kPa`，不显示成 PSI，不按数值量级擅自转换。

车辆信息补充路径中，SDK 实现了车速 `1048832`、车内 PM2.5 `1049344`、AQI `1049856`、燃油 `1050112`、里程 `1050368`、续航 `1050624` 等连续读取。厂商车速原始整数除以 100；燃油原始 Double 乘 1000，不能直接当百分比。独立 [OfficialVehicleSensors.java](../app/android/app/src/main/java/xyz/i4o/uni/launcher/integration/OfficialVehicleSensors.java) 已实现下表七项，由 Reader 的工作线程调用；helper 不创建新连接，也不修改 Reader。

| fields 键 | SDK ID | 精确 PA getter | PA 范围与归一化 | 默认单位及有效性 |
| --- | --- | --- | --- | --- |
| `pm25` | `1049344` | `getPaClAqInsideRaw()` | 整数 `0..1023` | `µg/m³`，XCHvac 原厂资源明确标注 |
| `aqi` | `1049856` | `getPaClAqInsideIndex()` | 整数 `0..1023` | 无量纲指数，不冒充室外 AQI |
| `speed` | `1048832` | `getPaNaviVehSpeed()` | 整数 `0..12500`，除以 `100` | 物理单位待确认，默认不输出可展示的 `value` |
| `odometer` | `1050368` | `getPaDiDstTrVld()` | 整数 `0..2000000`，不缩放 | 距离单位待确认 |
| `range` | `1050624` | `getPaDiDstToEmpty()` | 整数 `0..4095`，不缩放 | 距离单位待确认；不称作纯电续航 |
| `maintenanceMileage` | `4206592` | `getPaDiDstToSrv()` | 整数 `0..32000`，不缩放 | 距离单位待确认 |
| `batteryPercent` | `4210688` | `getBliHvBattLevelIndicationIhu()` | Double `data` 的 `0..100`，不缩放 | `%`；不使用该对象的 `level` 字段替代 |

以上范围、比例和电池百分比来自同一 JAR 的 `SensorImpl.getSensorLatestValue/isSensorSupported`、`SensorPaUtil.getValue/getAvailability`，与独立 PA 对象的 public `data/availability` 字段核对。helper 先检查借来的 `signals.isReady()` 和 PA `ACTIVE`、类型、范围，再与 SDK 的支持状态及读数比较；PA 缺失、停用、异常值不能借 SDK 默认零伪装成正常零。PA-only 读取允许 `sdkCar=null`，仍必须有已连接的 signals。没有定义燃油百分比字段。

```java
OfficialVehicleSensors info = new OfficialVehicleSensors(sdkCar, signals);
JSONObject infoState = info.snapshot(); // 同步读取，返回 connected/fields/errors
// 每轮选择 snapshot 或 appendTo 之一即可；appendTo 同样触发一轮新读取。
JSONObject infoResult = info.appendTo(fields); // 仅更新上表七个键，保留 HVAC/座椅/胎压
```

两参数构造器不会猜测速度、距离的单位。数据本身有效但单位未核实时，字段为 `sampleValid=true、valid=false、unitVerified=false`，保留 `raw/sampleValue/sdkValue` 供对照。具备源单位证据后，可使用三参数构造器并传入 `OfficialVehicleSensors.Units.confirmed(speedUnit, distanceUnit, evidence)`；速度允许 `m/s、km/h、mph`，距离允许 `km、mi`，未确认的维度传 `null`。参数描述的是已证实的 SDK 归一化结果单位，不是 UI 偏好，也不会触发单位换算。

helper 不订阅、不持有 Context、不关闭借来的对象，没有车控入口；需由现有 worker 在已连接期间调用。`updatedAtMs` 为成功查询的观察时间，PA getter 不暴露 HAL 时间戳，因此明确标记 `sourceTimestampAvailable=false`。

标准属性路径已配置 `PERF_VEHICLE_SPEED=291504647`、`PERF_ODOMETER=291504644`、`FUEL_LEVEL=291504903`、`EV_BATTERY_LEVEL=291504905`、`GEAR_SELECTION=289408000`，分别需要 `CAR_SPEED`、`CAR_MILEAGE`、`CAR_ENERGY`、`CAR_ENERGY`、`CAR_POWERTRAIN`。当前 Launcher 尚未声明这些额外权限。标准 HVAC、外温、标准剩余续航、标准胎压未配置，不能代替厂商合约。

**Reader API 与本地验证**

实现位于 [OfficialCarReader.java](../app/android/app/src/main/java/xyz/i4o/uni/launcher/integration/OfficialCarReader.java)，常量与写合约见 [OfficialCarContract.java](../app/android/app/src/main/java/xyz/i4o/uni/launcher/integration/OfficialCarContract.java)。

```java
OfficialCarReader reader = new OfficialCarReader(context, changedOnMain);
reader.start();
JSONObject state = reader.snapshot(); // read() 也可启动并返回缓存
boolean queued = reader.command(action, zone, mode); // 只由用户 UI 操作转发
reader.close(); // 此实例关闭后不可复用
```

所有 Binder getter/setter 在单一工作线程；构造和绑定回调在主线程。字段的 `supported`、`valid`、新鲜度和 `writable` 分开判断。UI 按 `climateCapabilities[key].writable` 和 `seatCapabilities[key].writable` 逐项启用，不能把顶层 `writable` 当作全控件开关。`verified=false` 表示显示一致性尚未验收，并不人为禁止完整合约的控制。

| action | zone | mode |
| --- | --- | --- |
| `temp-up / temp-down` | `left / right`，物理温区 | 忽略 |
| `fan-up / fan-down` | 忽略 | 忽略 |
| `climate-power` | 忽略 | 忽略 |
| `climate-mode` | 忽略 | `auto / ac / recirc / sync` |
| `seat-heat` | `left` 驾驶位，`right` 副驾驶位 | 字符串 `0..3` |
| `seat-vent` | 仅 `left` 驾驶位 | 字符串 `0..3` |

`command=true` 仅表示排队。执行前重新读取目标，独立核验权限、连接代际、支持状态、2.5 秒读取新鲜度与编码；温度再查量程/步长。排队超过 2 秒取消；一次仅允许一个待确认命令，不重试、不在断线后重放，不自动补发座椅互斥操作。`lastCommand.status` 为 `queued/sent/confirmed/unchanged/failed/timeout/cancelled`；发送后以目标值与新源时间戳读回确认，5 秒未确认超时。

持久化离线入口为 [test_official_car.py](../tools/test_official_car.py)：

```sh
python3 tools/test_official_car.py
# 其他环境可显式指定 JDK 与 API 28 平台
python3 tools/test_official_car.py --javac /path/to/jdk/bin/javac --android-jar /path/to/android.jar
# 没有 Android SDK 时只运行纯 JVM 回归
python3 tools/test_official_car.py --skip-android-compile
```

需要 JDK 17；默认检测 `JAVA_HOME/PATH` 与本机已配置工具链、Android SDK。输出默认在临时目录，`--output-dir` 可保留。脚本执行 PA 解码回归、31 项命令编码/边界/读回比较测试，再以 Android 9 Java 8 兼容方式编译全部辅助类，并运行 `OfficialVehicleSensorsTest` 的假 SDK/PA 测试，覆盖可用性、默认零、单位、范围及 PHEV 百分比。`--skip-android-compile` 仅运行前两组纯 JVM 测试。不调用 ADB，不连接网络，不安装应用、不发送车控。


## 0.5 PHEV 驾驶模式与能量流（新增只读采集）

同一已审计 adapter JAR（SHA256 `f4704d7d90ad24f8100bcc686b1ca0dba005777466d75b8f65242f2785d597bf`）的 `CarFunctionValueImpl`、`CarFunctionValueUtil` 与 `VehicleSignalManager` 已闭合以下实现链路。新增 `OfficialHybridReader` 借用现有工作线程的 CarPropertyManager，使用原始 HAL 状态及 PA 枚举，避免 SDK `fromInteger` 把未知值回退成有效默认值。没有新增连接或任何驾驶模式／充电写操作。

| 字段 | 属性与原厂 getter | 校验与语义 |
| --- | --- | --- |
| `driveMode` | Integer `0x21403018`；`getDidDmSelected()`；高层功能 `0x22010100` | HAL status=0、Integer、原始枚举 1..12；7 PURE、8 HYBRID、9 POWER、11 ECO_HEV_PHEV、12 COMFORT_HEV。原始枚举不是高层 `0x220101xx` 返回码。 |
| `hybridSelected` | PA `0x21701042`；`getPaDmHybrid()` | ACTIVE、整数 0 NOT_SELECTED／1 SELECTED；表示模式选择，不能证明发动机正在驱动。 |
| `energyFlow` | PA `0x21701052`；`getPfiPowerFlowIndic()`；高层功能 `0x24010100` | ACTIVE、整数 0..12；NOT_READY、MAIN_CHARGING、BOOST、EAWD、ENGINE_ONLY、ENGINE_ONLY_AND_CHARGE、ELECTRIC_DRIVE、STANDSTILL_ENGINE_OFF、STANDSTILL_ENGINE_ON、STANDSTILL_ENGINE_ON_CHARGE、ENGINE_OFF_REGEN_BRAKE、ENGINE_ON_REGEN_BRAKE、ENGINE_ON_REGEN_BRAKE_CHARGE。保留精确源枚举，不推断外接充电。 |
| `electricRange` | PA `0x21701069`；`getTsDtehvBattIndicated()` | 专用电池续航，format=0 km、1 mi；缺失／非法 format 不默认 km。有效域、无效编码及 status 含义尚未闭合，**只保留 raw/format/status，valid=false**，不输出 UI 数值。 |

三项状态在原有轮询中更新；保留源时间戳、读取时间、原始值与 apiVerified，实车同值验收之前 verified=false。UI 仍要求逐字段有效、5 秒新鲜度和已知枚举；驾驶模式与能量流可以分别缺失。动力电池卡片显示驾驶模式、能量流和独立的“外接充电待同步”，车辆详情另显示混动选择。

动力电池卡片按上述 `energyFlow` 精确枚举绘制发动机、电驱、动力电池和车轮之间的有向路径。流动粒子仅在对应路径有有效状态时运行：燃油动力为暖橙色，电驱与回收为主题色，制动回收反向流向电池；未知或过期枚举不显示活动路径，也不从电量或 `MAIN_CHARGING` 推断外接充电流向。

`HevImpl.getChargingManager()` 在本车实现中返回 null，不能仅靠 `ICharging` 的声明常量接通插枪状态。`getPaPmCharge()` / `0x24020200` 是 HYBRID_FUNC_BATTERY_CHARGE_MODE 的 ON/OFF，不是插枪状态。外接充电仍未接通。新增离线 `OfficialHybridReaderTest` 31 项校验覆盖 HAL 状态／类型、精确属性、ZigZag、未知枚举、缺失 PA 和不可信续航；不使用设备。本轮新增字段尚未上车采样。

## 0.6.3 车门状态扩展契约

当前 `OfficialCarReader` 没有向 Flutter 发布车门字段，因此界面不把未知状态显示成“已关闭”。已核对的 SystemUI 车辆 SDK 声明提供 `VehicleAPI.getBcm() → IBcm.getDoorAndWindowState()`；`IDoorAndWindow` 支持四门 `isDoorOpened/isDoorLocked`、四窗 `isWindowOpened` 以及状态监听，门位常量为前左 `1`、前右 `2`、后左 `3`、后右 `4`。这份 SDK 声明没有尾门或机舱盖常量，且尚未验证该 API 实现在自定义 Launcher 进程中可加载和读取，故本版不建立未经实车验证的 native 连接。

横向车辆组件已预留标准字段 `doorFrontLeft`、`doorFrontRight`、`doorRearLeft`、`doorRearRight`、`tailgateOpen`、`hoodOpen`。每项沿用 `{valid,value,updatedAtMs}` 包装，`value` 为开门布尔值；允许只提供部分字段。有效开启状态以暖橙描边和“车门开启”提示展示，缺字段时不占界面空间。后续四门可接入上述 BCM 读取；尾门和机舱盖须找到并实车核对 IP753 对应属性后再写入，避免把锁止、车窗或默认 `false` 误当开闭状态。

### 车辆线稿参考

胎压卡直接使用用户提供的领克 05 多视图图稿中第一张俯视图提取出的透明线稿 [`lynk-05-top-line.png`](../app/assets/art/lynk-05-top-line.png)，不再以 Flutter `Path` 近似重画。资产固定为 `1826 × 833`（宽高比 `2.192`），组件只做等比缩放和主题色着色，保留外轮廓、前后风挡、分段全景天窗、机盖、后视镜、门缝、门把手、灯组和徽标的相对坐标、曲率与间距。

同一图稿中的车尾、车头及左右侧视图保留为后续设计依据，用于完善车门、尾门、机舱盖、车窗、灯光和车身姿态状态；当前胎压卡不混入这些视角，在原车信号未经确认前也不展示推测状态。
