import 'package:flutter/material.dart';
import 'controller/launcher_controller.dart';
import 'platform/native_gateway.dart';
import 'launcher_app.dart';
import 'screens/global_dock_app.dart';
import 'screens/global_panel_app.dart';

Future<void> main() async {
  // Cold-start split: the native side logs its own phases under UNI-Startup,
  // these two marks cover what Dart adds on top (bootstrap handshake + first frame).
  final clock = Stopwatch()..start();
  WidgetsFlutterBinding.ensureInitialized();
  final controller = LauncherController(AndroidGateway());
  await controller.initialize();
  final booted = clock.elapsedMilliseconds;
  runApp(LauncherApp(controller: controller));
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
  final controller = LauncherController(AndroidGateway());
  await controller.initialize();
  runApp(GlobalDockApp(controller: controller));
}

@pragma('vm:entry-point')
Future<void> globalPanelMain() async {
  WidgetsFlutterBinding.ensureInitialized();
  final controller = LauncherController(AndroidGateway());
  await controller.initialize();
  runApp(GlobalPanelApp(controller: controller));
}
