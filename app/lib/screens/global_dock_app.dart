import 'package:flutter/material.dart';
import '../controller/launcher_controller.dart';
import '../theme/design_tokens.dart';
import '../theme/launcher_theme.dart';
import '../widgets/scene_background.dart';
import '../widgets/bottom_dock.dart';

/// This engine owns only the immutable physical bottom strip.
class GlobalDockApp extends StatelessWidget {
  final LauncherController controller;
  const GlobalDockApp({super.key, required this.controller});
  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
        animation: controller,
        builder: (context, _) {
          final dark = controller.native.value['dark'] == true;
          final style = SurfaceStyle.from(controller.appearance, dark,
              adaptToWallpaper: true);
          return MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: launcherTheme(style),
              color: Colors.transparent,
              home: Scaffold(
                  backgroundColor: Colors.transparent,
                  resizeToAvoidBottomInset: false,
                  body: SizedBox.expand(
                      child: FittedBox(
                          fit: BoxFit.fill,
                          child: SizedBox(
                              width: Design.canvasWidth,
                              height: Design.px(96),
                              child: ClipRect(
                                  child: OverflowBox(
                                      maxWidth: Design.canvasWidth,
                                      maxHeight: 900,
                                      alignment: Alignment.bottomCenter,
                                      child: SizedBox(
                                          width: Design.canvasWidth,
                                          height: 900,
                                          child: SceneBackground(
                                              appearance: controller.appearance,
                                              wallpaperCacheWidth: 960,
                                              child: Align(
                                                  alignment:
                                                      Alignment.bottomCenter,
                                                  child: BottomDock(
                                                      controller:
                                                          controller)))))))))));
        });
  }
}
