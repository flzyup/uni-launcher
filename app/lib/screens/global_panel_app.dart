import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../platform/native_gateway.dart';
import '../controller/launcher_controller.dart';
import '../theme/launcher_theme.dart';
import '../widgets/bottom_dock.dart';
import '../widgets/card_content.dart';
import '../widgets/dock_window_scope.dart';
import '../widgets/navigation_app_picker.dart';
import '../widgets/music_app_picker.dart';
import '../widgets/recent_tasks_panel.dart';

/// Separate, reusable window above the dock; never resizes its surface.
class GlobalPanelApp extends StatefulWidget {
  final LauncherController controller;
  const GlobalPanelApp({super.key, required this.controller});
  @override
  State<GlobalPanelApp> createState() => _GlobalPanelAppState();
}

class _GlobalPanelAppState extends State<GlobalPanelApp> {
  final navigator = GlobalKey<NavigatorState>();
  int revision = -1;
  Uint8List? backdrop;
  void replaceBackdrop(Uint8List? bytes) {
    final previous = backdrop;
    setState(() => backdrop = bytes);
    if (previous != null && !identical(previous, bytes))
      MemoryImage(previous).evict();
  }

  @override
  void initState() {
    super.initState();
    widget.controller.native.addListener(syncPanel);
    widget.controller.beforeExternalLaunch = () async {
      await widget.controller.command('dismiss-dock-panel');
    };
    WidgetsBinding.instance.addPostFrameCallback((_) => syncPanel());
  }

  void syncPanel() {
    final dock = mapOf(widget.controller.native.value['globalDock']);
    final next = dock['panelRevision'] as int? ?? 0;
    if (revision == next) return;
    revision = next;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted || revision != next) return;
      final nav = navigator.currentState;
      if (nav == null) return;
      nav.popUntil((r) => r.isFirst);
      final context = nav.overlay!.context;
      if (dock['panel'] == '') {
        replaceBackdrop(null);
        return;
      }
      if (dock['panel'] == 'recents') {
        replaceBackdrop(null);
        await WidgetsBinding.instance.endOfFrame;
        if (mounted && revision == next) {
          await widget.controller.command('panel-ready', value: '$next');
        }
        return;
      }
      if (widget.controller.appearance.usesBackdropBlur &&
          widget.controller.gateway is AndroidGateway) {
        final bytes = await AndroidGateway.methods
            .invokeMethod<Uint8List>('panel-backdrop');
        if (!mounted || revision != next || !context.mounted) return;
        if (bytes != null) {
          await precacheImage(MemoryImage(bytes), context);
          if (!mounted || revision != next || !context.mounted) return;
        }
        replaceBackdrop(bytes);
      }
      switch (dock['panel']) {
        case 'media':
          await showMediaPanel(context, widget.controller);
        case 'climate':
          await showClimatePanel(context, widget.controller);
        case 'vehicle':
          await showVehiclePanel(context, widget.controller);
        case 'navigation':
          await showNavigationPicker(context, widget.controller);
        case 'music-picker':
          await showMusicPicker(context, widget.controller);
        case 'apps':
          await showAppsPanel(context, widget.controller);
        default:
          return;
      }
      // An older route finishing must not dismiss a newly selected panel.
      if (mounted && revision == next) {
        await widget.controller.command('dismiss-dock-panel', value: '$next');
      }
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  @override
  void dispose() {
    if (backdrop != null) MemoryImage(backdrop!).evict();
    widget.controller.native.removeListener(syncPanel);
    widget.controller.beforeExternalLaunch = null;
    widget.controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) => DockWindowScope(
          expand: (_) async {},
          onPresented: () =>
              widget.controller.command('panel-ready', value: '$revision'),
          child: MaterialApp(
              navigatorKey: navigator,
              debugShowCheckedModeBanner: false,
              theme: launcherTheme(SurfaceStyle.from(
                  widget.controller.appearance,
                  widget.controller.native.value['dark'] == true)),
              color: Colors.transparent,
              home: Scaffold(
                  backgroundColor: Colors.transparent,
                  resizeToAvoidBottomInset: false,
                  body: mapOf(widget.controller.native.value['globalDock'])[
                              'panel'] ==
                          'recents'
                      ? RecentTasksPanel(controller: widget.controller)
                      : backdrop != null &&
                              widget.controller.appearance.usesBackdropBlur
                          ? SizedBox.expand(
                              child: Image.memory(backdrop!,
                                  fit: BoxFit.fill, gaplessPlayback: true))
                          : null))));
}
