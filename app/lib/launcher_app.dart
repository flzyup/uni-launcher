import 'package:flutter/material.dart';
import 'controller/launcher_controller.dart';
import 'model/appearance.dart';
import 'platform/adaptive_quality.dart';
import 'platform/ui_routes.dart';
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

  /// 引导还没读完外观时，窗口保持一种颜色，而不是「先白、再深、再换主题」。
  ///
  /// 这里给的不是某个固定色，而是 [SurfaceStyle.background] 本身：默认外观
  /// （blueGlass）加系统明暗推出来的那块画布色，和原生
  /// `res/values/colors.xml` 的 `uni_boot_canvas`、`LauncherRuntime.bootCanvasArgb()`
  /// 是同一套值。于是启动过程是「深色启动窗 → 深色画布 → 主题背景」，中间没有
  /// 白场；外观真的和默认不同时，prelude 到了会换成正确的那一种。
  Color _bootCanvas() => SurfaceStyle.from(
        const Appearance(),
        WidgetsBinding.instance.platformDispatcher.platformBrightness ==
            Brightness.dark,
      ).background;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
      animation: Listenable.merge([controller, AdaptiveQuality.shared]),
      child: LauncherShell(controller: controller),
      builder: (context, shell) {
        if (!controller.designReady) return ColoredBox(color: _bootCanvas());
        final style = SurfaceStyle.from(
            controller.appearance, controller.native.value['dark'] == true,
            adaptToWallpaper: true,
            lowPower: AdaptiveQuality.shared.degraded);
        return MaterialApp(
            title: 'UNI 桌面',
            debugShowCheckedModeBanner: false,
            navigatorKey: launcherNavigatorKey,
            theme: launcherTheme(style),
            home: shell);
      });
}
