import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../model/lyrics.dart';
import '../theme/design_tokens.dart';
import '../theme/launcher_theme.dart';

/// Draws playback progress behind the dock music controls.
///
/// The moving glow is a plain gradient on the left side of the progress
/// divider, fading further left so the cycle feels continuous. It has no
/// blur, shader mask, bitmap capture or read-back.
class DockMusicProgressBackground extends StatefulWidget {
  final Map<String, dynamic> media;
  final bool enabled;
  final Widget child;
  const DockMusicProgressBackground({
    super.key,
    required this.media,
    required this.enabled,
    required this.child,
  });

  @override
  State<DockMusicProgressBackground> createState() =>
      _DockMusicProgressBackgroundState();
}

class _DockMusicProgressBackgroundState
    extends State<DockMusicProgressBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController _glow = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 2100));
  bool _tickerEnabled = false;

  @override
  void initState() {
    super.initState();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final enabled = TickerMode.valuesOf(context).enabled;
    _tickerEnabled = enabled;
    _syncAnimation();
  }

  @override
  void didUpdateWidget(DockMusicProgressBackground oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncAnimation();
  }

  bool get _playing =>
      widget.media['playing'] == true && widget.media['positionKnown'] == true;

  void _syncAnimation() {
    if (widget.enabled && _tickerEnabled && _playing) {
      if (!_glow.isAnimating) _glow.repeat();
    } else {
      _glow.stop();
      _glow.value = 0;
    }
  }

  @override
  void dispose() {
    _glow.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return widget.child;
    final style = SurfaceStyle.of(context);
    return RepaintBoundary(
        child: AnimatedBuilder(
            animation: _glow,
            builder: (context, _) => CustomPaint(
                key: const ValueKey('dock-music-progress'),
                painter: _DockMusicProgressPainter(
                    style: style,
                    media: widget.media,
                    glow: _glow.value,
                    animate: _glow.isAnimating),
                child: widget.child)));
  }
}

class _DockMusicProgressPainter extends CustomPainter {
  final SurfaceStyle style;
  final Map<String, dynamic> media;
  final double glow;
  final bool animate;
  const _DockMusicProgressPainter({
    required this.style,
    required this.media,
    required this.glow,
    required this.animate,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final timeline = MediaTimeline.fromJson(media);
    if (!timeline.known || timeline.durationMs <= 0) return;
    final position = timeline
        .at(DateTime.now().millisecondsSinceEpoch)
        .clamp(0, timeline.durationMs);
    final dividerX =
        (position / timeline.durationMs).clamp(0.0, 1.0) * size.width;
    if (dividerX < 1) return;

    final accent = style.accent;
    // 进度色块必须跟着音乐块的圆角走：外层的裁剪只盖得住四角，盖不住中间
    // 那块满高的 drawRect，在胶囊里就亮成一个直角方框（用户反馈「音乐外面
    // 那个框」）。这里先按 controlRadius 裁一遍，再分主题画。
    canvas.save();
    canvas.clipRRect(RRect.fromRectAndRadius(
        Offset.zero & size, Radius.circular(style.controlRadius)));

    if (style.nocturne) {
      // 暗夜画布是近黑，满高染色会读成一块生硬的方块；设计稿的底栏是细线
      // 语言，所以这里收成底部一条贴合圆角的进度条，末端加一个圆点。
      final barHeight = math.min(Design.dz(4), size.height * .12);
      final barTop = size.height - barHeight - Design.dz(3);
      final radius = Radius.circular(barHeight / 2);
      canvas.drawRRect(
          RRect.fromRectAndRadius(
              Rect.fromLTWH(0, barTop, dividerX, barHeight), radius),
          Paint()
            ..shader = ui.Gradient.linear(Offset.zero, Offset(dividerX, 0), [
              accent.withValues(alpha: .10),
              accent.withValues(alpha: .58),
            ]));
      final dot = barHeight * .95;
      canvas.drawCircle(Offset(dividerX - dot / 2, barTop + barHeight / 2),
          dot / 1.9, Paint()..color = accent.withValues(alpha: .92));
      canvas.restore();
      return;
    }

    final fill = Paint()
      ..shader = ui.Gradient.linear(Offset.zero, Offset(dividerX, 0), [
        accent.withValues(alpha: .05),
        accent.withValues(alpha: .18),
      ]);
    canvas.drawRect(Rect.fromLTWH(0, 0, dividerX, size.height), fill);

    // First-version breathing glow anchored at the divider, with a smooth
    // leftward fade so the cycle reads as one continuous motion.
    final available = math.min(dividerX, Design.px(140));
    final spread = .50 + .50 * math.sin(math.pi * glow);
    final glowWidth = available * (.52 + .48 * spread);
    final glowLeft = math.max(0.0, dividerX - glowWidth);
    final strength = available / Design.px(140);
    final glowPaint = Paint()
      ..shader = ui.Gradient.linear(Offset(glowLeft, 0), Offset(dividerX, 0), [
        accent.withValues(alpha: 0),
        accent.withValues(alpha: .34 * spread * strength),
      ]);
    canvas.drawRect(
        Rect.fromLTWH(glowLeft, 0, dividerX - glowLeft, size.height),
        glowPaint);

    final lineColor = Color.lerp(accent, Colors.white, .22)!;
    final lineHeight = size.height * .72;
    final lineTop = (size.height - lineHeight) / 2;
    canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromLTWH(dividerX - 1, lineTop, 2, lineHeight),
            const Radius.circular(1)),
        Paint()
          ..color = lineColor.withValues(alpha: animate ? .92 : .70)
          ..strokeWidth = 0
          ..style = PaintingStyle.fill);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _DockMusicProgressPainter oldDelegate) =>
      oldDelegate.style != style ||
      oldDelegate.media != media ||
      oldDelegate.glow != glow ||
      oldDelegate.animate != animate;
}
