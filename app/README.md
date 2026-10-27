# UNI Launcher · Flutter Android

0.6.12 新增可选“深蓝玻璃”主题：深浅色、四角短框线、静态玻璃、统一选中态和全局底栏；圆角仍支持 0–40。移除“功能接入”分类，其可用选项移入系统设置最上方“应用与底栏”。[实现与验证](../docs/THEME_BLUE_GLASS.md#v50612-实现与验证)。

0.6.11 优化跟手翻屏：平移、淡入淡出、缩放、层叠与无动画，页面与指示条共用进度；隐藏/运动页停止歌词和进度更新，导航应用查询缓存并减少重复媒体同步。[实现与验证边界](../docs/PERFORMANCE_0_6_11.md)。

0.6.10 完善卡片拖放：占位让位、满屏交换、跨屏持续拖动、位置动画与右下角网格缩放；红绿灯箭头加粗。交互和验证见 [0.6.10 记录](../docs/IP753_0_6_10.md)。

0.6.9 增加红绿灯卡片：官方标准广播与修改版巡航多方向数组、可调尺寸、失效清空和深浅色。Android 9 模拟器链路与界面已验证；真实路口及方向 / 灯态枚举仍待实车核对，live 模式当前中性显示。见 [0.6.9 记录](../docs/IP753_0_6_9.md)。

0.6.8 引入原生实时地图纹理，移除地图静态占位和 ActivityView 容器。模拟器已验证触控、换屏、弹窗与全屏恢复；实车已完成初始实时画面接入，其余回归因 ADB 离线待续。见 [0.6.8 验证记录](../docs/IP753_0_6_8.md)。

0.5.0 增加全局底栏、独立系统导航栏开关和三张车辆信息卡。底栏背景铺满屏幕宽度、外层直角、底部无留白；跨应用媒体 / 空调与桌面共用原生 Runtime。实现和限制见[全局底栏](../docs/GLOBAL_DOCK.md)、[车辆卡片](../docs/VEHICLE_CARD_DESIGN.md)、[官方能力对照](../docs/OEM_PARITY_0_5.md)。

0.5.0 新增全局底栏与系统导航栏独立开关，底栏背景铺满、直角、底边不留白；新增动力电池 / 驾驶模式 / 能量流卡片和空气质量卡片，并补齐原车 Widget 配置与应用回退。实车包 `UNI-Launcher-0.5.0-IP753.apk` 尚待上车，本轮结果见 [0.5 验收范围](../docs/IP753_0_5.md)。0.4.2 已完成的地图 / 窗口修复和历史实车读数保留于 [0.4.2 记录](../docs/IP753_0_4_2.md)。

包名 `xyz.i4o.uni.launcher`，面向领克 05 IP753 / Android 9。界面由 Flutter 绘制，Android 平台通道复用已有 Java 适配器。源代码直接保存在本目录并由仓库的本地 Git commit 管理，不另行打包源码。

## 0.4.0 接入补充

- 导航卡片使用 Android 9 ActivityView 容器显示实际导航应用，支持关联应用、嵌入开关、全屏和失败回退。普通权限模拟器只验证降级，真高德已实车显示；切屏/休眠/倒车仍按实车报告逐项验收。
- 可关联已安装的网易云、QQ、原车音乐等播放器。读取及控制绑定同一应用会话，增加封面和可用操作判断；无会话不控制其他播放器。
- 0.4.0 的候选通道已由 0.4.2 官方车辆读取器替换；后台限频、新鲜度、逐项能力和命令读回共用独立模块。
- 38 类矢量天气图标，昼夜和未知状态由公共组件处理；原厂天气数据接口仍待核对。
- 完整差距、证据和上车条件见[官方能力对照](../docs/OEM_PARITY_0_4.md)。

## 界面与设置

- 无左侧栏；80 逻辑像素底栏按「首页、全部、空调操作、音乐控制、音乐信息、车辆信息、360」排列，操作按钮使用图标。
- 长按首页进入设置；深色、浅色、跟随系统，5 组主题色、自定义取色器与行内 HEX。
- 圆角 0–40，提供滑杆和数值输入，0 为直角。毛玻璃独立开关，默认关闭；关闭时移除所有 `BackdropFilter`，保留半透明材质。设置与卡片布局保存到 Android SharedPreferences。
- 切换动效页可选无动画、淡入淡出、横向滑动，支持左右轻扫，底栏固定；默认无动画。实车启用原生地图时直接切页并保留容器，避免 Android 9 原生 Surface 参与 Flutter 翻页动画。
- 音乐卡片、底栏和详情复用滚动歌词，有时间轴时按媒体进度同步，支持暂停与 seek；无歌词不沿用旧曲目。来源与边界见[歌词接入说明](../docs/MEDIA_LYRICS_AND_MOTION.md)。
- 卡片长按编辑、网格移动、缩放、重命名、删除/撤销、取消/完成、添加与分页；尺寸按内容设最小值，最多 20 页。
- 覆盖官方目录中的导航、媒体、天气、日历、账号、清理、胎压、可选空气质量；其他车型的出行服务保留目录记录但不出现在 IP753 卡片库。

## 样式核对与座椅

此次按[设计一致性审计](../docs/UI_FIDELITY_AUDIT.md)修正默认胶囊按钮、坐标换算、完整桌面预览、原始 SVG 图标、卡片内容结构、分类卡片库、单卡尺寸设置及所有面板。`Design.px` 明确 1920 稿件到 1600 逻辑画布的换算，按钮采用圆角矩形，圆形色点保留语义形状。

空调面板增加主驾加热/通风、副驾加热，显式选择关闭/1/2/3档。演示中主驾加热与通风互斥；实车通过官方档位编码和独立能力控制；不自动补发互斥操作，状态以车辆读回为准。每项座椅控制分别检查自己的 capability，普通空调写权限不启用座椅控制；实车数据未知时显示 `—` 并禁用操作。

`python3 tools/sync_design_assets.py` 从本仓库原创设计符号同步 SVG 资源；Flutter 使用 `flutter_svg` 绘制，仍无 WebView。新增卡片、编辑器、气候面板、座椅和统一弹层模块各自复用公共主题与表面。

## 模块

| 路径 | 职责 |
| --- | --- |
| `lib/model/` | 外观偏好、卡片规格、网格约束和布局序列化 |
| `lib/controller/` | 状态订阅、编辑事务、撤销与持久化 |
| `lib/theme/`、`lib/widgets/glass_surface.dart` | 经典/深蓝玻璃 token、公共框线、圆角、玻璃与表面/图标按钮 |
| `lib/widgets/` | 卡片内容、可编辑容器、底栏和功能面板 |
| `lib/screens/` | 首页、桌面设置 |
| `lib/platform/` | `NativeGateway` 接口、MethodChannel / EventChannel |
| `android/app/src/main/java/.../MainActivity.java` | FlutterActivity、生命周期、限定命令与状态桥接 |
| `android/app/src/main/java/.../core`、`integration` | 共用 Java 应用列表、媒体、车辆、导航栏和原厂 Widget 宿主 |
| `../analysis/official-widgets.json` | 共用原厂提供者目录，Gradle 构建时同步到 assets |
| `test/`、`integration_test/` | 状态/组件测试与 Android 9 真模拟器交互测试 |

正常界面不显示 Binder、权限异常或属性 ID；应用关联与底栏选项位于系统设置首项。Flutter 入口不编译旧 WebView MainActivity、离线 HTML 或 JS 界面。

## 实车接入边界

实车默认关闭模拟数据，未接通数据为 `—`，对应控制禁用；模拟器可演示空调和媒体，演示操作不会控制车辆。平台能力沿用[官方 APK 证据](../docs/APK_ANALYSIS.md)，嘟嘟仅作辅助参考。

- 已接入 Android 的应用列表/图标/启动、媒体会话状态与控制、原厂 Widget 兼容页、窗口导航栏隐藏，以及需系统授权的全局隐藏。媒体会话与原车媒体中心同源同值仍待实车比对。
- 车辆适配器使用官方 `Car.create → IConnectable → ICarFunction`，并保留 CarPropertyManager 原始 PA 的状态、时间戳和解码。空调/座椅操作由 UI 单独触发，按权限、读数、支持项和 SDK 映射启用；命令排队、发送和新状态确认分开，不自动重放。精确合约见[官方车辆接口](../docs/OFFICIAL_CAR_API.md)。
- 胎压、AQI 和 PHEV 电量已接入官方读取；胎压单位及原厂同值比对继续验收。天气、账号、日历、清理仍待 Provider 字段；保留原厂 Widget/应用兼容入口。
- 演示路线只用于无原生导航状态的界面预览；实际 Android 首页使用导航容器或明确的全屏回退。真高德画面、切屏与设置显隐已在实车检查；实时摘要、倒车接管、休眠恢复和长时性能仍待验收。

## 构建

本机验证工具链：Flutter 3.47.8 / Dart 3.13.7、Java 17、Android SDK 36。Android 最低 API 24，目标 API 28，维持当前车机行为；不用于商店发布。工程的签名配置使用仓库外的本地开发 keystore，与早期版本一致，便于覆盖安装。可用 `UNI_SIGNING_STORE` 覆盖路径，私钥不入库。

```sh
cd app
flutter pub get
flutter analyze --no-pub
flutter test --no-pub
flutter build apk --release --target-platform android-arm64,android-x64 --split-per-abi
```

构建产物在 `build/app/outputs/flutter-apk/`。`app-arm64-v8a-release.apk` 是普通开发签名包，`app-x86_64-release.apk` 供模拟器。IP753 实车使用单独签名的 `UNI-Launcher-0.5.0-IP753.apk`；两种证书不能相互覆盖安装，同一实车证书的后续版本可正常升级。当前启动、地图、媒体与车辆边界见[0.4.2 实车记录](../docs/IP753_0_4_2.md)。

分 ABI APK 的 versionCode 由 Flutter 添加 ABI 前缀，本次 arm64 为 2007、x86_64 为 4007；后续升级应提高 `pubspec.yaml` 的构建号。当前签名、大小和 SHA-256 记录于[构建报告](verification/build-report.json)。

JDK 保存在 `/data/tools/linkco-android/java-runtime/`，不再依赖 `/tmp`；Flutter 已配置此持久路径。

本机 Flutter SDK 位于 `/data/tools/flutter`、Android SDK 位于 `/data/tools/linkco-android/sdk`。需要本地代理环境时可用 `python3 tools/flutter_task.py <flutter 参数>`；脚本为 Gradle 继承已有代理，测试连接本机 VM service 时绕过代理。可用 `FLUTTER_SDK` 覆盖 Flutter 路径。SDK、Gradle 缓存和 build 均不提交。

## 验证

启动已有 API 28 / 1920×1080 横屏模拟器（配置见[基线模拟器说明](../archive/webview-android/README.md)）后：

```sh
python3 tools/flutter_task.py drive \
  --driver=test_driver/driver.dart \
  --target=integration_test/launcher_test.dart \
  --debug -d emulator-5580
```

测试使用模拟空调及两个独立的合成播放器；会重置这个模拟器内 UNI 的主题/布局、调整演示和导航栏开关。执行前应指定模拟器，不把测试脚本用于实车。

切换 release 构建与集成测试时保留默认 pub 步骤，以重新生成包含开发测试插件的注册代码；不要在这种切换后直接使用 `drive --no-pub`。

组件测试覆盖默认无模糊、开关与原生保存、深浅主题/0 圆角、布局冲突/边界、取消/恢复、最小卡片尺寸、未连接状态。Android 集成测试覆盖真实应用列表平台通道、底栏顺序、首页长按、主题/模糊持久化、触摸拖动缩放、演示空调回读与导航栏开关。

歌词集成测试需先在模拟器安装合成媒体源，不能安装到车机：

```sh
python3 native-tests/tools/build-fixture.py
python3 tools/flutter_task.py drive --driver=test_driver/driver.dart --target=integration_test/launcher_test.dart -d emulator-5580
```

驱动脚本在 Flutter 安装完成后准备模拟器媒体授权与前台测试音源，校验设备为模拟器；测试源可分别卸载 `ecarx.xsf.mediacenter` 和 `xyz.i4o.uni.fixture.player`。

[验证报告](verification/emulator-report.json)和同目录的 `flutter-*.png` 是实际模拟器输出。只验证功能，不把模拟器帧率视为 MSM8996 实车性能。后续按[实车验收记录](../docs/CAR_ACCEPTANCE.md)继续核对。

离线官方接口回归：`python3 ../tools/test_official_car.py`；网易云兼容回归：`python3 native-tests/tools/test-netease-adapter.py`。

最终静态分析、状态/组件测试、Android 9 集成与 release 验证结果见[构建报告](verification/build-report.json)。实际 release [首页](verification/flutter-release-home.png)与[设置](verification/flutter-release-settings.png)截图单独保存；实时车控和性能仍待实车。
