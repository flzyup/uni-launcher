import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import '../theme/launcher_theme.dart';

class LiquidInteraction extends InheritedWidget {
  final double amount;
  final Offset point;
  const LiquidInteraction(
      {super.key,
      required super.child,
      this.amount = 0,
      this.point = const Offset(.25, .1)});
  static LiquidInteraction of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<LiquidInteraction>() ??
      const LiquidInteraction(child: SizedBox());
  @override
  bool updateShouldNotify(LiquidInteraction old) =>
      old.amount != amount || old.point != point;
}

/// Touch expands and gently pulls the lens; release settles with a spring.
/// The animation controller is completely idle outside an interaction.
class LiquidPress extends StatefulWidget {
  final Widget child;
  final bool enabled;
  const LiquidPress({super.key, required this.child, this.enabled = true});
  @override
  State<LiquidPress> createState() => _LiquidPressState();
}

class _LiquidPressState extends State<LiquidPress>
    with SingleTickerProviderStateMixin {
  late final AnimationController motion =
      AnimationController.unbounded(vsync: this);
  Offset point = const Offset(.25, .1);
  int? pointer;
  bool get reduced => MediaQuery.disableAnimationsOf(context);
  void locate(Offset local) {
    final box = context.findRenderObject();
    if (box is RenderBox &&
        box.hasSize &&
        box.size.width > 0 &&
        box.size.height > 0) {
      setState(() => point = Offset((local.dx / box.size.width).clamp(0.0, 1.0),
          (local.dy / box.size.height).clamp(0.0, 1.0)));
    }
  }

  void release() {
    pointer = null;
    if (!mounted) return;
    if (reduced) {
      motion.value = 0;
      return;
    }
    motion.animateWith(SpringSimulation(
        const SpringDescription(mass: 1, stiffness: 390, damping: 25),
        motion.value,
        0,
        motion.velocity));
  }

  @override
  void didUpdateWidget(LiquidPress old) {
    super.didUpdateWidget(old);
    if (!widget.enabled) {
      pointer = null;
      motion.stop();
      motion.value = 0;
    }
  }

  @override
  void dispose() {
    pointer = null;
    motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final style = SurfaceStyle.of(context);
    if (!style.liquidGlass || !widget.enabled) return widget.child;
    return Listener(
      onPointerDown: (event) {
        if (pointer != null) return;
        pointer = event.pointer;
        locate(event.localPosition);
        if (reduced)
          motion.value = 1;
        else
          motion.animateTo(1,
              duration: const Duration(milliseconds: 110),
              curve: Curves.easeOutCubic);
      },
      onPointerMove: (event) {
        if (event.pointer == pointer) locate(event.localPosition);
      },
      onPointerUp: (event) {
        if (event.pointer == pointer) release();
      },
      onPointerCancel: (event) {
        if (event.pointer == pointer) release();
      },
      child: AnimatedBuilder(
          animation: motion,
          child: widget.child,
          builder: (context, child) {
            final value = motion.value.clamp(-.2, 1.15);
            return LiquidInteraction(
                amount: value.clamp(0.0, 1.0),
                point: point,
                child: Transform.translate(
                    offset: reduced
                        ? Offset.zero
                        : Offset((point.dx - .5) * 3 * value,
                            (point.dy - .5) * 2 * value),
                    child: Transform.scale(
                        key: const ValueKey('liquid-lens-transform'),
                        scale: reduced ? 1 : 1 + .035 * value,
                        child: CustomPaint(
                            foregroundPainter: _TouchLight(
                                value.clamp(0.0, 1.0),
                                point,
                                style.controlRadius),
                            child: child))));
          }),
    );
  }
}

class _TouchLight extends CustomPainter {
  final double amount, radius;
  final Offset point;
  const _TouchLight(this.amount, this.point, this.radius);
  @override
  void paint(Canvas canvas, Size size) {
    if (amount <= 0 || size.isEmpty) return;
    final rect = Offset.zero & size;
    final shape =
        RRect.fromRectAndRadius(rect.deflate(.6), Radius.circular(radius));
    canvas.save();
    canvas.clipRRect(shape);
    canvas.drawRect(
        rect,
        Paint()
          ..shader = RadialGradient(
              center: Alignment(point.dx * 2 - 1, point.dy * 2 - 1),
              radius: 1.1,
              colors: [
                Colors.white.withValues(alpha: .30 * amount),
                Colors.transparent
              ]).createShader(rect));
    canvas.drawRRect(
        shape,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2
          ..color = Colors.white.withValues(alpha: .6 * amount));
    canvas.restore();
  }

  @override
  bool shouldRepaint(_TouchLight old) =>
      old.amount != amount || old.point != point || old.radius != radius;
}
