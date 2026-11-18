import 'dart:async';

import 'package:flutter/material.dart';
import 'controller/launcher_controller.dart';
import 'platform/adaptive_quality.dart';
import 'platform/native_gateway.dart';
import 'launcher_app.dart';
import 'screens/global_dock_app.dart';
import 'screens/global_panel_app.dart';

/// prelude 最多等这么久。超时不是错误：根组件会先画启动底色，
/// prelude 到了再换成真桌面 —— 也就是改动前的老行为。
const _preludeBudget = Duration(milliseconds: 400);

Future<void> main() async {
  // Cold-start split: the native side logs its own phases under UNI-Startup,
  // these two marks cover what Dart adds on top (bootstrap handshake + first frame).
  final clock = Stopwatch()..start();
  WidgetsFlutterBinding.ensureInitialized();
  // 帧预算看门狗（见 AdaptiveQuality）：车机上卡不卡是量出来的，不是猜的。
  AdaptiveQuality.shared.start();
  final controller = LauncherController(AndroidGateway());
  // 先拿外观，再挂根组件。
  //
  // 反过来（先 runApp、后 await prelude）会让「窗口第一帧」是一块纯色画布，
  // 而真正的桌面要等 prelude 回来后再重建一次 —— 实测这一段就是首绘之后那
  // 300 ms 的等待。prelude 只读偏好，往返几十毫秒，等得起；真慢就超时退化成
  // 老行为，不能把启动卡死。
  await controller.initializePrelude().timeout(_preludeBudget, onTimeout: () {});
  runApp(LauncherApp(controller: controller));
  // 遥测、图标、事件流在首帧之后补，一个字节都不挡在第一帧前面。
  unawaited(controller.initializeRest());
  final booted = clock.elapsedMilliseconds;
  WidgetsBinding.instance.addPostFrameCallback((_) {
    final a = controller.appearance;
    debugPrint('UNI-Startup dart bootstrap=$booted firstFrame=${clock.elapsedMilliseconds} '
        'style=${a.themeStyle} glass=${a.glass} mode=${a.mode} radius=${a.radius} '
        'apps=${controller.appNames.length} blur=${a.glass && a.themeStyle != 'blueGlass'}');
    // 把「桌面真的画出来了」回填进原生 StartupTrace：只到窗口首绘（启动底色）
    // 是不够的，用户感知的启动时间是到这一帧。失败无所谓，诊断而已。
    AndroidGateway.methods
        .invokeMethod<void>('mark', 'launcherContent')
        .then((_) {}, onError: (Object _) {});
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
