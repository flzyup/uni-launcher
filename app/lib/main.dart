import 'package:flutter/material.dart';
import 'controller/launcher_controller.dart';
import 'platform/adaptive_quality.dart';
import 'platform/native_gateway.dart';
import 'launcher_app.dart';
import 'screens/global_dock_app.dart';
import 'screens/global_panel_app.dart';

Future<void> main() async {
  // Cold-start split: the native side logs its own phases under UNI-Startup,
  // these two marks cover what Dart adds on top (bootstrap handshake + first frame).
  final clock = Stopwatch()..start();
  WidgetsFlutterBinding.ensureInitialized();
  // 帧预算看门狗（见 AdaptiveQuality）：车机上卡不卡是量出来的，不是猜的。
  AdaptiveQuality.shared.start();
  final controller = LauncherController(AndroidGateway());
  // 先把根组件挂上去。引导还没读到外观时根组件只画一块与 launch_background
  // 同色的画布，所以「窗口第一帧」不再等着 bootstrap 快照打包完；外观一到就换
  // 成真正的界面，剩下的遥测照旧在后面补。
  runApp(LauncherApp(controller: controller));
  await controller.initialize();
  final booted = clock.elapsedMilliseconds;
  WidgetsBinding.instance.addPostFrameCallback((_) {
    final a = controller.appearance;
    debugPrint('UNI-Startup dart bootstrap=$booted firstFrame=${clock.elapsedMilliseconds} '
        'style=${a.themeStyle} glass=${a.glass} mode=${a.mode} radius=${a.radius} '
        'apps=${controller.appNames.length} blur=${a.glass && a.themeStyle != 'blueGlass'}');
  });
}

@pragma('vm:entry-point')
Future<void> globalDockMain() async {
  WidgetsFlutterBinding.ensureInitialized();
  AdaptiveQuality.shared.start();
  final controller = LauncherController(AndroidGateway());
  await controller.initialize();
  runApp(GlobalDockApp(controller: controller));
}

@pragma('vm:entry-point')
Future<void> globalPanelMain() async {
  WidgetsFlutterBinding.ensureInitialized();
  AdaptiveQuality.shared.start();
  final controller = LauncherController(AndroidGateway());
  await controller.initialize();
  runApp(GlobalPanelApp(controller: controller));
}
