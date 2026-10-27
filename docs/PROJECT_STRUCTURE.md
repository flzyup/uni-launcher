# 项目目录与原生代码

当前应用由 `app/` 中的 Flutter 界面和 Android 原生代码共同组成：

- `app/lib/`：Flutter 界面、状态和平台通道。
- `app/android/app/src/main/java/xyz/i4o/uni/launcher/`：Android 入口，以及 `core/`、`integration/`、`platform/`、`audio/`、`overlay/` 等原生模块。
- `app/android/app/src/main/res/`：应用的 Android 资源。
- `app/android/nav-insets/`：车机导航栏资源包源文件，由 `tools/build_nav_insets.py` 和车机签名流程使用。
- `app/native-tests/`：原生接口测试、模拟器夹具与相关测试工具；其 `build/` 是本地产物。
- `archive/webview-android/`：早期 WebView 基线、独立构建脚本和历史验证结果。归档基线的构建脚本引用当前应用的原生适配代码，历史结果仅代表当时状态。
- `analysis/`：原厂组件目录和分析摘要；APK、完整反汇编等本地材料不纳入 Git。
- `tools/`：跨目录的构建、签名、分析和验证脚本。

Gradle 在应用模块中显式声明 `core/` 和 `integration/` 源目录，原厂组件目录仍从 `analysis/official-widgets.json` 生成应用资源。生产源码只保留在 `app/android/`；不要将归档目录中的 WebView 入口加入当前应用。

## 验证

在仓库根目录执行：

```sh
python3 tools/test_official_car.py
python3 tools/test_weather_location.py
python3 tools/test_system_settings.py
python3 app/native-tests/tools/test-netease-adapter.py
python3 app/native-tests/tools/test-lyrics-resolver.py
python3 app/native-tests/tools/test-official-media-bridge.py
python3 app/native-tests/tools/test-navigation-media-performance.py
cd app
python3 tools/flutter_task.py analyze
python3 tools/flutter_task.py test
python3 tools/flutter_task.py build apk --release --target-platform android-arm64,android-x64 --split-per-abi
```

构建 IP753 测试包时，`tools/sign_car_apk.py` 会使用本机已有签名材料并嵌入导航栏资源包；相关私钥不在仓库中。模拟器夹具和设备验证脚本需单独按各脚本说明执行，不应针对实车运行模拟器夹具。
