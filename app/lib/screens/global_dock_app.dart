import 'package:flutter/material.dart';
import '../controller/launcher_controller.dart';
import '../theme/design_tokens.dart';
import '../theme/launcher_theme.dart';
import '../widgets/bottom_dock.dart';

/// This engine owns only the immutable physical bottom strip.
class GlobalDockApp extends StatelessWidget {
  final LauncherController controller;
  const GlobalDockApp({super.key, required this.controller});
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
      animation: controller,
      builder: (context, _) => MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: launcherTheme(SurfaceStyle.from(
              controller.appearance, controller.native.value['dark'] == true,
              adaptToWallpaper: true)),
          color: Colors.transparent,
          home: Scaffold(
              // Keep native navigation controls underneath this replacement
              // from bleeding through the glass material.
              backgroundColor: SurfaceStyle.from(controller.appearance,
                      controller.native.value['dark'] == true,
                      adaptToWallpaper: true)
                  .strong
                  .withValues(alpha: 1),
              resizeToAvoidBottomInset: false,
              body: SizedBox.expand(
                  child: FittedBox(
                      fit: BoxFit.fill,
                      child: SizedBox(
                          width: Design.canvasWidth,
                          height: Design.px(96),
                          child: BottomDock(controller: controller)))))));
}
