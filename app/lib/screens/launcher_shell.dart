import 'dart:convert';
import 'package:flutter/material.dart';
import '../platform/native_gateway.dart';
import '../controller/launcher_controller.dart';
import '../widgets/desktop.dart';
import '../widgets/scene_background.dart';
import '../theme/design_tokens.dart';
import '../widgets/bottom_dock.dart';
import 'settings_screen.dart';

class LauncherShell extends StatefulWidget {
  final LauncherController controller;
  const LauncherShell({super.key, required this.controller});
  @override
  State<LauncherShell> createState() => _LauncherShellState();
}

class _LauncherShellState extends State<LauncherShell> {
  late final ValueNotifier<double> pagePosition =
      ValueNotifier(widget.controller.page.toDouble());
  LauncherController get controller => widget.controller;

  @override
  void dispose() {
    pagePosition.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, result) {
          if (!didPop) controller.back();
        },
        child: Scaffold(
            // The car's decor already reserves the OEM control bar. Its inset
            // reports fluctuate when an ActivityView gains focus; never apply
            // that inset a second time to the desktop or move the dock for it.
            resizeToAvoidBottomInset: false,
            body: SceneBackground(
              appearance: controller.appearance,
              forceOverlay: controller.settings,
              child: SafeArea(
                  top: false,
                  bottom: false,
                  child: LayoutBuilder(builder: (context, box) {
                    final scale = box.maxWidth / Design.canvasWidth;
                    final nativeHeight =
                        (controller.native.value['viewportHeightPx'] as num?)
                            ?.toDouble();
                    // With the global dock enabled the overlay is the only bar
                    // (home included); the inline dock must not duplicate it.
                    final globalDock = controller.native.value['globalDock'];
                    final globalDockActive = globalDock is Map &&
                        globalDock['enabled'] == true &&
                        globalDock['running'] == true;
                    final height = nativeHeight != null && nativeHeight > 0
                        ? (nativeHeight /
                                MediaQuery.devicePixelRatioOf(context))
                            .clamp(0.0, box.maxHeight)
                        : box.maxHeight;
                    if (controller.gateway is AndroidGateway) {
                      final metrics = jsonEncode({
                        'width': box.maxWidth,
                        'maxHeight': box.maxHeight,
                        'height': height,
                        'nativeHeightPx': nativeHeight,
                        'dpr': MediaQuery.devicePixelRatioOf(context),
                        'page': controller.page,
                        'settings': controller.settings
                      });
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        AndroidGateway.methods
                            .invokeMethod<void>('viewport', metrics)
                            .catchError((Object _) {});
                      });
                    }
                    return Align(
                        alignment: Alignment.topCenter,
                        child: SizedBox(
                            width: box.maxWidth,
                            height: height,
                            child: FittedBox(
                                fit: BoxFit.fill,
                                child: SizedBox(
                                    width: Design.canvasWidth,
                                    height: height / scale,
                                    child: Column(children: [
                                      Header(
                                          controller: controller,
                                          position: pagePosition),
                                      Expanded(
                                          child: IndexedStack(
                                              index:
                                                  controller.settings ? 1 : 0,
                                              children: [
                                            TickerMode(
                                                enabled: !controller.settings,
                                                child: Desktop(
                                                    controller: controller,
                                                    position: pagePosition)),
                                            controller.settings
                                                ? SettingsScreen(
                                                    controller: controller)
                                                : const SizedBox.shrink(),
                                          ])),
                                      if (!globalDockActive)
                                        BottomDock(controller: controller),
                                    ])))));
                  })),
            )));
  }
}
