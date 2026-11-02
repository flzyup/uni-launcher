import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';
import '../theme/design_tokens.dart';
import '../theme/launcher_theme.dart';
import 'glass_surface.dart';
import 'dock_window_scope.dart';

/// One glass sheet and one design-coordinate system for every desktop overlay.
Future<T?> showLauncherSheet<T>(
  BuildContext context, {
  required String title,
  Widget? titleWidget,
  String? subtitle,
  String closeLabel = '关闭面板',
  required double width,
  double? height,
  /// 暗夜主题下弹层的底部光晕取自哪张卡片（沿用一卡一色）。null 用强调色。
  String? glowType,
  required WidgetBuilder builder,
}) async {
  final dock = DockWindowScope.of(context);
  if (dock != null) {
    await dock.expand(true);
    await WidgetsBinding.instance.endOfFrame;
    if (!context.mounted) {
      await dock.expand(false);
      return null;
    }
  }
  try {
    final dismissed = showGeneralDialog<T>(
        context: context,
        barrierDismissible: true,
        barrierLabel: closeLabel,
        barrierColor: Colors.transparent,
        transitionDuration: const Duration(milliseconds: 180),
        pageBuilder: (context, _, __) => AnimatedPadding(
            duration: const Duration(milliseconds: 180),
            padding: EdgeInsets.only(
                bottom: MediaQuery.viewInsetsOf(context).bottom),
            child: LauncherSheet(
                title: title,
                titleWidget: titleWidget,
                subtitle: subtitle,
                closeLabel: closeLabel,
                width: width,
                height: height,
                glowType: glowType,
                child: Builder(builder: builder))));
    if (dock?.onPresented != null) {
      await WidgetsBinding.instance.endOfFrame;
      if (context.mounted) await dock!.onPresented!();
    }
    return await dismissed;
  } finally {
    if (dock != null) await dock.expand(false);
  }
}

/// Lightweight auto-dismissing toast; never pushes layout like a SnackBar.
void showLauncherToast(BuildContext context, String message) {
  final overlay = Overlay.of(context, rootOverlay: true);
  late final OverlayEntry entry;
  var fading = false;
  entry = OverlayEntry(builder: (context) {
    final s = SurfaceStyle.of(context);
    return Positioned(
        left: 0,
        right: 0,
        bottom: Design.px(120),
        child: IgnorePointer(
            child: Center(
                child: AnimatedOpacity(
                    opacity: fading ? 0 : 1,
                    duration: const Duration(milliseconds: 240),
                    child: GlassSurface(
                        tone: SurfaceTone.strong,
                        padding: EdgeInsets.symmetric(
                            horizontal: Design.px(30), vertical: Design.px(14)),
                        child: Text(message,
                            style: TextStyle(
                                fontSize: Design.px(20), color: s.text)))))));
  });
  overlay.insert(entry);
  Future.delayed(const Duration(milliseconds: 2000), () {
    fading = true;
    entry.markNeedsBuild();
    Future.delayed(const Duration(milliseconds: 260), () {
      if (entry.mounted) entry.remove();
    });
  });
}

class LauncherSheet extends StatelessWidget {
  final String title, closeLabel;
  final String? subtitle;
  final Widget? titleWidget;
  final double width;
  final double? height;
  final String? glowType;
  final Widget child;
  const LauncherSheet(
      {super.key,
      required this.title,
      this.titleWidget,
      required this.closeLabel,
      required this.width,
      this.subtitle,
      this.height,
      this.glowType,
      required this.child});
  @override
  Widget build(BuildContext context) {
    final s = SurfaceStyle.of(context);
    return Material(
        type: MaterialType.transparency,
        child: Stack(children: [
          Positioned.fill(
              child: GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: ColoredBox(
                      color: s.dark
                          ? const Color(0x8007151D)
                          : const Color(0x3361716B)))),
          if (s.liveBlur)
            Positioned.fill(
                child: IgnorePointer(
                    child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                        child: const SizedBox.expand()))),
          Positioned.fill(
              child: SafeArea(
                  top: DockWindowScope.of(context) == null,
                  bottom: DockWindowScope.of(context) == null,
                  child: LayoutBuilder(builder: (context, box) {
                    final scale = box.maxWidth / Design.canvasWidth;
                    final canvasHeight = box.maxHeight / scale;
                    return SizedBox.expand(
                        child: FittedBox(
                            fit: BoxFit.fill,
                            child: SizedBox(
                                width: Design.canvasWidth,
                                height: canvasHeight,
                                child: Center(
                                    child: ConstrainedBox(
                                        constraints: BoxConstraints(
                                            maxWidth: width,
                                            maxHeight: math.max(120,
                                                canvasHeight - Design.px(64))),
                                        child: SizedBox(
                                            width: width,
                                            height: height,
                                            child: GlassSurface(
                                                tone: SurfaceTone.strong,
                                                sheet: true,
                                                // 弹层沿用来源卡片的一卡一色光晕，
                                                // 暗夜下才有；其他主题返回 null。
                                                glow: s.cardGlow(glowType ?? ''),
                                                padding: EdgeInsets.symmetric(
                                                    horizontal: Design.px(40),
                                                    vertical: Design.px(34)),
                                                child: Column(
                                                    mainAxisSize:
                                                        MainAxisSize.min,
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment
                                                            .stretch,
                                                    children: [
                                                      Row(children: [
                                                        Expanded(
                                                            child:
                                                                titleWidget ??
                                                                    Column(
                                                                        crossAxisAlignment:
                                                                            CrossAxisAlignment.start,
                                                                        children: [
                                                                          Text(
                                                                              title,
                                                                              style: TextStyle(fontSize: Design.px(34), fontWeight: FontWeight.w500)),
                                                                          if (subtitle !=
                                                                              null) ...[
                                                                            SizedBox(height: Design.px(12)),
                                                                            Text(subtitle!,
                                                                                style: TextStyle(fontSize: Design.px(20), color: s.muted))
                                                                          ],
                                                                        ])),
                                                        IconAction(
                                                            icon: Icons.close,
                                                            label: closeLabel,
                                                            size: Design.px(54),
                                                            iconSize:
                                                                Design.px(25),
                                                            soft: true,
                                                            onTap: () =>
                                                                Navigator.pop(
                                                                    context))
                                                      ]),
                                                      SizedBox(
                                                          height:
                                                              Design.px(28)),
                                                      Flexible(child: child),
                                                    ]))))))));
                  }))),
        ]));
  }
}
