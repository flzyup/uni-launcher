import 'package:flutter/material.dart';
import 'controller/launcher_controller.dart';
import 'platform/adaptive_quality.dart';
import 'theme/launcher_theme.dart';
import 'screens/launcher_shell.dart';

/// 根组件只做两件事：换主题，和「一帧都还没有」时给一块画布。
///
/// 以前整个 [LauncherShell] 建在 `AnimatedBuilder(controller)` 里面，于是每条
/// 遥测（车辆、媒体、天气、图标）都是「从 MaterialApp 重建整棵树」。现在 Shell
/// 作为 `child` 只建一次、自己订阅需要的数据，这里只在主题真的变了（外观设置
/// 变化，或画质降级翻转）时才换 ThemeData。
class LauncherApp extends StatelessWidget {
  final LauncherController controller;
  const LauncherApp({super.key, required this.controller});

  /// 与 `launch_background.xml` 同色：引导还没读完外观时，窗口保持一种颜色，
  /// 而不是「先白、再黑、再换主题」。
  static const Color bootCanvas = Color(0xFFFFFFFF);

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
      animation: Listenable.merge([controller, AdaptiveQuality.shared]),
      child: LauncherShell(controller: controller),
      builder: (context, shell) {
        if (!controller.designReady) return const ColoredBox(color: bootCanvas);
        final style = SurfaceStyle.from(
            controller.appearance, controller.native.value['dark'] == true,
            adaptToWallpaper: true,
            lowPower: AdaptiveQuality.shared.degraded);
        return MaterialApp(
            title: 'UNI 桌面',
            debugShowCheckedModeBanner: false,
            theme: launcherTheme(style),
            home: shell);
      });
}
