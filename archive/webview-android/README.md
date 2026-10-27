# UNI Launcher 0.1.0

这是保留的 WebView 基线。当前版本入口已迁移到 [Flutter 工程](../../app/README.md)，复用 `app/android/app/src/main/` 中的 `core/`、`integration/` 与资源；以下说明只描述基线 APK。

包名 `xyz.i4o.uni.launcher`。一个 APK，Java 原生 Android 宿主 + APK 内的离线界面，复用已评审的 V04 组件。当前为 Android 9 模拟器验证版；实车空调、胎压和官方字段一致性仍待上车核对。

## 已实现

- HOME、横屏、真实应用枚举/图标/启动、应用变化更新、返回/回首页。
- 无侧栏；底栏顺序：首页、全部、空调、音乐控制、音乐信息、车辆、360。长按首页进入设置。
- 深浅/跟随系统、5 组主题色、自定义 HEX、0–40 圆角。
- 卡片添加、拖动、缩放、编辑、删除/撤销、取消/完成、分页；原生存储保证重启恢复，最多 20 页。
- 原厂 9 类/14 Provider 共用一份目录；IP753 卡片库排除其他车型的出行服务。
- AppWidgetHost 授权、独立 host ID、生命周期、提供者缺失回退。兼容视图使用原厂 RemoteViews，其内部视觉不能由宿主任意重绘。
- MediaSession 授权、源选择、metadata/播放回调、支持项判断、播放/暂停/切歌。此通道与原车媒体中心同值与否仍需实车比对。
- 导航栏：窗口沉浸模式；可选全局 `policy_control`，需 `WRITE_SECURE_SETTINGS`。备份并恢复原值，不覆盖已有的其他策略。
- 官方 `Car.create → getICarFunction → getFunctionValue` 只读探测；360 使用官方 `CarUtils` 中已启用且导出的 `com.ecarx.parking/com.ecarx.park2.MainAvmActivity`，不启用禁用组件。

## 实车数据边界

实车默认关闭模拟数据：未接通的值显示 `—`，控制置灰。模拟器默认演示，可在设置关闭；模拟空调不会向车辆发送命令。

当前缺提供者 APK、实车字段和车控框架。地图是示意图，尚无实时导航嵌入。天气/账号/日历/清理/胎压/AQI 统一卡片尚未接通真实字段，可打开原厂 Widget 或应用兼容。`VehicleAdapter` 的原生空调命令目前返回不可用，不能把演示温度变化当成实车控制完成。

官方 Launcher 主要宿主 Widget，未包含完整空调写契约。后续按本车框架和提供者补齐适配器，不使用其他车型的属性 ID。实现未替换官方应用或修改其数据库。

这是普通 UID 的本地开发签名版，无系统共享 UID；不能假定拥有官方权限。WebView 调试已启用供本轮验证，后续发布版应关闭。

## 模块与复用

| 路径 | 职责 |
| --- | --- |
| `src/.../MainActivity.java` | 生命周期、离线资源、白名单桥接、原生保存 |
| `../../app/android/app/src/main/java/.../core/` | 与 Android 无关的命令边界和模拟状态 |
| `../../app/android/app/src/main/java/.../integration/` | 应用、媒体、车辆、导航栏、官方目录和 Widget 宿主 |
| `../../design/*.js` / `*.css` | 共享主题 token、图标、卡片、设置和编辑交互 |
| `ui/runtime.*` | 正式 App 的数据/动作适配、空态和旧 WebView 兼容 |
| `../../analysis/official-widgets.json` | 原厂 Provider 目录唯一来源 |
| `../../app/native-tests/test/` | Java 状态边界测试 |
| `../../app/native-tests/test-fixture/` | 仅供模拟器的合成 MediaSession / RemoteViews 源 |
| `tools/verify-emulator.mjs` | 真正的 Android WebView + ADB 触控验证 |

界面未申请 INTERNET；仅加载 HTTPS 虚拟源映射的 APK assets，禁用 file/content 访问和外部页面导航。桥接不支持任意 shell 或组件执行。音乐元数据在 HTML 输出边界转义。

Android 9 自带 WebView 66 不支持实时 `backdrop-filter`：使用半透明材质与柔和渐变背景降级，较新 WebView 使用共享模糊效果。首版不宣称原车已实现背景实时采样模糊。

## 构建

本机 Java 17、D8、aapt2、apksigner 在 `/tmp/linkco-build`，API 28 SDK 在 `/data/tools/linkco-android/sdk`。可用 `--toolchain`、`--sdk` 覆盖，目录结构见 `build.py`。无 Gradle 和第三方 Android 运行库。

```sh
cd archive/webview-android
npm ci
python3 build.py --test-only
python3 build.py
```

产物 `dist/UNI-Launcher-0.1.0-debug.apk`。签名材料保存在 SDK 同级的 `uni-debug.keystore`；源码、测试和报告提交本地 Git，构建产物与私钥忽略。源码不另打包。

## 模拟器

需要系统 adb、Node 24、KVM。下载 Google API 28 平台、x86_64 镜像和模拟器，独立存放并核验官方仓库校验值，首次约 1 GB：

```sh
python3 tools/prepare-emulator.py
ANDROID_AVD_HOME=/data/tools/linkco-android/avd \
ANDROID_SDK_ROOT=/data/tools/linkco-android/sdk \
/data/tools/linkco-android/sdk/emulator/emulator -avd uni-api28 \
  -no-window -no-audio -no-snapshot -no-boot-anim -no-metrics \
  -gpu swiftshader_indirect -port 5580
```

另一终端等 `adb -s emulator-5580 shell getprop sys.boot_completed` 返回 `1`，然后：

```sh
adb -s emulator-5580 install -r dist/UNI-Launcher-0.1.0-debug.apk
python3 ../../app/native-tests/tools/build-fixture.py
node tools/verify-emulator.mjs --fixture
```

脚本只接受 `emulator-*`，会清理该模拟器中 UNI 的测试数据，并设置测试授权。合成源使用目录中的媒体提供者组件名验证匹配，代码和数据均由测试产生；**它不是原厂 APK，不得安装到车机**。测试 APK 仅存放在 `build/fixture`。完成后可执行 `adb -s emulator-5580 uninstall ecarx.xsf.mediacenter` 清理。

真实模拟器截图和 [验证报告](verification/emulator-report.json) 验证的是 Android 接入和界面逻辑。车控、休眠/启动、倒车接管、窗口边界、权限和长时性能需要实车验证。

下一轮按 [IP753 实车验证记录](../../docs/CAR_ACCEPTANCE.md) 补齐提供者字段、权限与车控契约。

依据：本地 [官方 APK 分析](../../docs/APK_ANALYSIS.md)、[AppWidgetHost 契约](https://developer.android.com/reference/android/appwidget/AppWidgetHost)、[Android 模拟器启动/安装](https://developer.android.com/studio/run/emulator-commandline)。
