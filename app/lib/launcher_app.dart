import 'package:flutter/material.dart';
import 'controller/launcher_controller.dart';
import 'theme/launcher_theme.dart';
import 'screens/launcher_shell.dart';

class LauncherApp extends StatelessWidget {
  final LauncherController controller;
  const LauncherApp({super.key, required this.controller});
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final style = SurfaceStyle.from(
            controller.appearance, controller.native.value['dark'] == true,
            adaptToWallpaper: true);
        return MaterialApp(
            title: 'UNI 桌面',
            debugShowCheckedModeBanner: false,
            theme: launcherTheme(style),
            home: LauncherShell(controller: controller));
      });
}
