import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';
import '../theme/design_tokens.dart';
import '../theme/launcher_theme.dart';
import 'canvas_scope.dart';
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
  /// 选择器类弹层用设计稿自己那套紧凑规格（标题 19 / 关闭 36 / 内边距
  /// 26·28·22 / 头部间距 12）。其余弹层不传，保持原来的 40·34 那一套。
  bool compact = false,
  /// 弹层自带头部时传 false：不再画标题行与关闭键，正文拿到整块面板。
  /// 设计稿里 f20 桌面命名、f29 车辆信息都是自绘头部（居中标题 / vh-head）。
  bool showHeader = true,
  /// 覆盖面板内边距；null 时按 [compact] 取默认值。
  EdgeInsets? padding,
  /// 头部右侧、关闭键左边的附加动作（音乐弹层的「选择音乐应用」走这里）。
  Widget? actions,
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
        transitionDuration: const Duration(milliseconds: 140),
        transitionBuilder: (context, animation, _, child) => FadeTransition(
            opacity: CurvedAnimation(
                parent: animation,
                curve: Curves.easeOutCubic,
                reverseCurve: Curves.easeInCubic),
            child: child),
        pageBuilder: (context, _, __) => Padding(
            padding: EdgeInsets.only(
                bottom: MediaQuery.viewInsetsOf(context).bottom),
            child: RepaintBoundary(
                // 与桌面同一套 1600 画布坐标系：车机上是恒等变换，
                // 模拟器/小窗下按同比例缩，不会被裁。
                child: CanvasScope(
                    child: LauncherSheet(
                    title: title,
                    titleWidget: titleWidget,
                    subtitle: subtitle,
                    closeLabel: closeLabel,
                    width: width,
                    height: height,
                    glowType: glowType,
                    compact: compact,
                    showHeader: showHeader,
                    padding: padding,
                    actions: actions,
                    child: Builder(builder: builder))))));
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
  final bool compact;
  final bool showHeader;
  final EdgeInsets? padding;
  final Widget? actions;
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
      this.compact = false,
      this.showHeader = true,
      this.padding,
      this.actions,
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
                    final panel = ConstrainedBox(
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
                                                // 稿子里 `.dlg.pick` 是实色无光晕，
                                                // 选择器弹层不传 glowType 即关闭。
                                                glow: glowType == null
                                                    ? null
                                                    : s.cardGlow(glowType!),
                                                padding: padding ??
                                                    (compact
                                                        ? EdgeInsets.only(
                                                            left: Design.dz(28),
                                                            right: Design.dz(28),
                                                            top: Design.dz(26),
                                                            bottom: Design.dz(22))
                                                        : EdgeInsets.symmetric(
                                                            horizontal: Design.px(40),
                                                            vertical: Design.px(34))),
                                                child: !showHeader
                                                    ? child
                                                    : Column(
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
                                                                              style: TextStyle(
                                                                                  fontSize: compact ? Design.dz(19) : Design.px(34),
                                                                                  fontWeight: FontWeight.w500,
                                                                                  letterSpacing: compact ? Design.dz(19) * .04 : null)),
                                                                          if (subtitle !=
                                                                              null) ...[
                                                                            SizedBox(height: Design.px(12)),
                                                                            Text(subtitle!,
                                                                                style: TextStyle(fontSize: Design.px(20), color: s.muted))
                                                                          ],
                                                                        ])),
                                                        if (actions != null) ...[
                                                          actions!,
                                                          SizedBox(
                                                              width: Design.px(
                                                                  compact ? 12 : 16))
                                                        ],
                                                        if (compact)
                                                          _CompactClose(
                                                              label: closeLabel,
                                                              onTap: () =>
                                                                  Navigator.pop(
                                                                      context))
                                                        else
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
                                                          height: compact
                                                              ? Design.dz(12)
                                                              : Design.px(28)),
                                                      Flexible(child: child),
                                                    ]))));

                    return SizedBox.expand(
                        child: FittedBox(
                            fit: BoxFit.fill,
                            child: SizedBox(
                                width: Design.canvasWidth,
                                height: canvasHeight,
                                child: Center(child: panel))));
                  }))),
        ]));
  }
}

/// 设计稿 `.sheet-h .x`：36 正圆、6% 墨色底 + 9% 描边、15px 图标。
/// 紧凑弹层用它，普通弹层仍走 [IconAction]。
class _CompactClose extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _CompactClose({required this.label, required this.onTap});
  @override
  Widget build(BuildContext context) {
    final ink = SurfaceStyle.of(context).text;
    return Semantics(
        button: true,
        label: label,
        child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onTap,
            child: Container(
                width: Design.dz(36),
                height: Design.dz(36),
                decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: ink.withValues(alpha: .06),
                    border:
                        Border.all(color: ink.withValues(alpha: .09))),
                child: Center(
                    child: Icon(Icons.close,
                        size: Design.dz(15),
                        color: ink.withValues(alpha: .70))))));
  }
}
