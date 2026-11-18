import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ImageFilterContext;
import '../theme/launcher_theme.dart';
import 'liquid_press.dart';

/// Shares material depth, preventing nested controls from blurring text in
/// their own container. Sibling lenses still sample independently.
class _LiquidDepth extends InheritedWidget {
  const _LiquidDepth({required super.child});
  @override
  bool updateShouldNotify(_LiquidDepth oldWidget) => false;
}

class LiquidMaterial extends StatefulWidget {
  final Widget child;
  final BorderRadius radius;
  final bool sheet, content, shadow;
  const LiquidMaterial(
      {super.key,
      required this.child,
      required this.radius,
      this.sheet = false,
      this.content = false,
      this.shadow = true});
  @override
  State<LiquidMaterial> createState() => _LiquidMaterialState();
}

class _LiquidMaterialState extends State<LiquidMaterial> {
  static Future<ui.FragmentProgram?>? _program;
  static bool _reportedBackend = false;
  static bool _reportedShader = false;
  ui.FragmentShader? _shader;
  bool _shaderRequested = false;
  @override
  void initState() {
    super.initState();
    if (!_reportedBackend) {
      _reportedBackend = true;
      debugPrint(
          'UniLiquid shaderFilter=${ui.ImageFilter.isShaderFilterSupported}');
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _loadShaderIfNeeded();
  }

  @override
  void didUpdateWidget(LiquidMaterial oldWidget) {
    super.didUpdateWidget(oldWidget);
    _loadShaderIfNeeded();
  }

  void _loadShaderIfNeeded() {
    // 嵌套分组和按钮共享外层采样，也不为它们分配用不到的着色器实例。
    final nested =
        context.dependOnInheritedWidgetOfExactType<_LiquidDepth>() != null;
    if (!_shaderRequested &&
        !nested &&
        !widget.content &&
        ui.ImageFilter.isShaderFilterSupported) {
      _shaderRequested = true;
      _program ??=
          ui.FragmentProgram.fromAsset('assets/shaders/liquid_glass.frag')
              .then<ui.FragmentProgram?>((p) => p)
              .catchError((Object error) {
        debugPrint('UniLiquid optics fallback: $error');
        return null;
      });
      _program!.then((program) {
        if (mounted && program != null) {
          if (!_reportedShader) {
            _reportedShader = true;
            debugPrint('UniLiquid optical shader ready');
          }
          setState(() => _shader = program.fragmentShader());
        }
      });
    }
  }

  @override
  void dispose() {
    _shader?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = SurfaceStyle.of(context);
    final nested = !widget.content &&
        context.dependOnInheritedWidgetOfExactType<_LiquidDepth>() != null;
    final interaction = LiquidInteraction.of(context);
    final amount = interaction.amount.clamp(0.0, 1.0);
    final blur = s.glass && !nested;
    final sigma = s.lowPower
        ? (widget.sheet ? 8.0 : 4.0)
        : (widget.content ? 12.0 : (widget.sheet ? 18.0 : 12.0));
    ui.ImageFilter filter = ui.ImageFilter.blur(
        sigmaX: sigma, sigmaY: sigma, tileMode: ui.TileMode.clamp);
    final shader = _shader;
    if (blur && !s.lowPower && !widget.content && shader != null) {
      // The engine supplies texture dimensions (0,1) and sampler 0.
      shader.setFloat(2, widget.radius.topLeft.x);
      shader.setFloat(3, 10 + amount * 8);
      shader.setFloat(4, amount);
      shader.setFloat(5, interaction.point.dx);
      shader.setFloat(6, interaction.point.dy);
      filter = ui.ImageFilter.compose(
          outer: ui.ImageFilter.shader(shader), inner: filter);
    }
    if (blur) {
      filter =
          ui.ImageFilter.compose(outer: s.liquidBackdrop.filter, inner: filter);
    }
    // The regular material provides contrast; never put an opaque painted
    // gradient over the sampled backdrop. Reduced quality keeps readability.
    // Gradient stops already carry the material alpha. Setting a translucent
    // BoxDecoration.color as well would multiply the shader alpha a second
    // time, invalidating the contrast plane used by SurfaceStyle.
    final fill = DecoratedBox(
        decoration: BoxDecoration(
            borderRadius: widget.radius,
            gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: s.liquidFill(
                    nested: nested,
                    sheet: widget.sheet,
                    content: widget.content),
                stops: const [0, .46, 1])));
    final surface = Stack(fit: StackFit.passthrough, children: [
      Positioned.fill(
          child: blur
              ? BackdropFilter(
                  key: const ValueKey('liquid-live-backdrop'),
                  filter: filter,
                  child: fill)
              : fill),
      if (blur && !s.lowPower && !widget.content && shader == null)
        Positioned.fill(
            child: IgnorePointer(
                child: Stack(fit: StackFit.expand, children: [
          for (final band in const [(9.0, 1.035), (4.0, 1.07)])
            ClipPath(
                clipper: _LensRing(widget.radius, band.$1),
                child: BackdropFilter(
                    key: ValueKey('liquid-edge-lens-${band.$1}'),
                    filterConfig: LiquidLensFilter(
                        scale: band.$2 + amount * .025,
                        point: interaction.point),
                    child: const SizedBox.expand())),
        ]))),
      _LiquidDepth(child: widget.child),
      if (!nested || widget.sheet || amount > 0)
        Positioned.fill(
            child: IgnorePointer(
                child: CustomPaint(
                    painter: LiquidOpticsPainter(
                        radius: widget.radius,
                        dark: s.dark,
                        amount: amount,
                        point: interaction.point,
                        quiet: widget.content || (nested && !widget.sheet),
                        rimScale: nested && widget.sheet ? .55 : 1)))),
    ]);
    return DecoratedBox(
        decoration: BoxDecoration(
            borderRadius: widget.radius,
            boxShadow: widget.shadow && !nested
                ? [
                    BoxShadow(
                        color:
                            Colors.black.withValues(alpha: s.dark ? .24 : .10),
                        blurRadius: 18,
                        offset: const Offset(0, 6),
                        spreadRadius: -3)
                  ]
                : null),
        child: ClipRRect(borderRadius: widget.radius, child: surface));
  }
}

/// A size-aware optical magnification filter supported by Skia/GLES on Android
/// 9. It samples the live backdrop; no screenshot or readback is involved.
class LiquidLensFilter implements ImageFilterConfig {
  final double scale;
  final Offset point;
  const LiquidLensFilter(
      {required this.scale, this.point = const Offset(.5, .5)});
  @override
  ui.ImageFilter resolve(ImageFilterContext context) {
    final center = Offset.lerp(
        context.bounds.center,
        context.bounds.topLeft +
            Offset(context.bounds.width * point.dx,
                context.bounds.height * point.dy),
        .12)!;
    final matrix = Matrix4.translationValues(center.dx, center.dy, 0)
      ..scaleByDouble(scale, scale, 1, 1)
      ..translateByDouble(-center.dx, -center.dy, 0, 1);
    return ui.ImageFilter.matrix(matrix.storage,
        filterQuality: FilterQuality.medium);
  }

  @override
  ui.ImageFilter? get filter => null;
  @override
  String get debugShortDescription => 'liquidLens($scale)';
}

class _LensRing extends CustomClipper<Path> {
  final BorderRadius radius;
  final double thickness;
  const _LensRing(this.radius, this.thickness);
  @override
  Path getClip(Size size) {
    final outer = radius.toRRect(Offset.zero & size);
    return Path()
      ..fillType = PathFillType.evenOdd
      ..addRRect(outer)
      ..addRRect(outer.deflate(thickness.clamp(0, size.shortestSide / 2)));
  }

  @override
  bool shouldReclip(_LensRing old) =>
      old.radius != radius || old.thickness != thickness;
}

/// Light follows the touch. Two opposing rims imply a curved lens rather than
/// a uniform outline; the caustic remains within the material's clip.
class LiquidOpticsPainter extends CustomPainter {
  final BorderRadius radius;
  final bool dark, quiet;
  final double amount;
  final double rimScale;
  final Offset point;
  const LiquidOpticsPainter(
      {required this.radius,
      required this.dark,
      required this.amount,
      required this.point,
      this.quiet = false,
      this.rimScale = 1});
  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final rect = Offset.zero & size;
    final edge = radius.toRRect(rect.deflate(.75));
    final light = Alignment(point.dx * 2 - 1, point.dy * 2 - 1);
    final strength = (quiet ? .24 : 1.0) * rimScale;
    final rim = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.1 + amount * .65
      ..shader = LinearGradient(
          begin: light,
          end: Alignment(-light.x, -light.y),
          colors: [
            Colors.white.withValues(alpha: (.66 + amount * .30) * strength),
            Colors.white.withValues(alpha: .07 * strength),
            Colors.white.withValues(alpha: .03 * strength),
            Colors.white.withValues(alpha: .42 * strength)
          ],
          stops: const [
            0,
            .28,
            .64,
            1
          ]).createShader(rect);
    canvas.drawRRect(edge, rim);
    if (!quiet) {
      final inner = radius.toRRect(rect.deflate(2.6));
      canvas.drawRRect(
          inner,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.8
            ..shader = LinearGradient(
                begin: Alignment.bottomRight,
                end: Alignment.topLeft,
                colors: [
                  Colors.white
                      .withValues(alpha: (.17 + amount * .16) * rimScale),
                  Colors.transparent,
                  Colors.white.withValues(alpha: .06 * rimScale)
                ]).createShader(rect));
    }
    if (amount > 0) {
      final center = Offset(size.width * point.dx, size.height * point.dy);
      canvas.drawRRect(
          edge,
          Paint()
            ..shader = ui.Gradient.radial(
                center, math.max(size.width, size.height) * .8, [
              Colors.white.withValues(alpha: amount * .24),
              Colors.transparent
            ]));
    }
  }

  @override
  bool shouldRepaint(covariant LiquidOpticsPainter old) =>
      old.radius != radius ||
      old.dark != dark ||
      old.amount != amount ||
      old.point != point ||
      old.quiet != quiet ||
      old.rimScale != rimScale;
}
