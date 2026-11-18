import 'package:flutter/material.dart';

import '../theme/design_tokens.dart';

/// A one-line text that scrolls only when it does not fit its parent.
///
/// A fitting text renders as a normal [Text], so it has no ticker and no
/// continuous repaint cost.
class MarqueeText extends StatefulWidget {
  final String data;
  final TextStyle style;
  final TextAlign? textAlign;

  const MarqueeText({
    super.key,
    required this.data,
    required this.style,
    this.textAlign,
  });

  @override
  State<MarqueeText> createState() => _MarqueeTextState();
}

class _MarqueeTextState extends State<MarqueeText>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(vsync: this);
  bool _running = false;
  bool _tickerEnabled = true;
  TextPainter? _cachedPainter;
  String? _cachedData;
  TextStyle? _cachedStyle;
  TextAlign? _cachedAlign;
  TextDirection? _cachedDirection;
  TextScaler? _cachedScaler;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final enabled = TickerMode.valuesOf(context).enabled;
    if (enabled == _tickerEnabled) return;
    _tickerEnabled = enabled;
    if (!_tickerEnabled && _running) {
      _controller.stop();
      _running = false;
    }
  }

  @override
  void dispose() {
    _cachedPainter?.dispose();
    _controller.dispose();
    super.dispose();
  }

  TextPainter _resolvePainter(BuildContext context) {
    final effectiveStyle = DefaultTextStyle.of(context).style.merge(widget.style);
    final align = widget.textAlign ?? TextAlign.start;
    final direction = Directionality.of(context);
    final scaler =
        MediaQuery.maybeTextScalerOf(context) ?? TextScaler.noScaling;
    final existing = _cachedPainter;
    if (existing != null &&
        _cachedData == widget.data &&
        _cachedStyle == effectiveStyle &&
        _cachedAlign == align &&
        _cachedDirection == direction &&
        _cachedScaler == scaler) {
      return existing;
    }
    existing?.dispose();
    _cachedData = widget.data;
    _cachedStyle = effectiveStyle;
    _cachedAlign = align;
    _cachedDirection = direction;
    _cachedScaler = scaler;
    final painter = TextPainter(
      text: TextSpan(text: widget.data, style: effectiveStyle),
      textAlign: align,
      textDirection: direction,
      textScaler: scaler,
      maxLines: 1,
    )..layout();
    _cachedPainter = painter;
    return painter;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final width = constraints.maxWidth;
      if (!width.isFinite || width <= 0) {
        return Text(widget.data,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: widget.style,
            textAlign: widget.textAlign);
      }

      final text = _resolvePainter(context);

      if (text.width <= width + 1) {
        if (_running) {
          _controller
            ..stop()
            ..value = 0;
          _running = false;
        }
        return Text(widget.data,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: widget.style,
            textAlign: widget.textAlign);
      }

      final travel = text.width + Design.px(48);
      final milliseconds =
          (travel / Design.px(28) * 1000).ceil().clamp(2200, 14000).toInt();
      final duration = Duration(milliseconds: milliseconds);
      if (_controller.duration != duration) _controller.duration = duration;
      if (_tickerEnabled && !_running) {
        _controller.repeat();
        _running = true;
      } else if (!_tickerEnabled && _running) {
        _controller.stop();
        _running = false;
      }

      final edge = Design.px(24).clamp(0, width / 3).toDouble();
      return RepaintBoundary(
        child: SizedBox(
          width: width,
          height: text.height,
          child: ClipRect(
            child: ShaderMask(
                blendMode: BlendMode.dstIn,
                shaderCallback: (bounds) => LinearGradient(
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                      colors: const [
                        Colors.transparent,
                        Colors.white,
                        Colors.white,
                        Colors.transparent
                      ],
                      stops: [
                        0,
                        edge == 0 ? 0 : edge / width,
                        edge == 0 ? 1 : 1 - edge / width,
                        1
                      ],
                    ).createShader(bounds),
                child: AnimatedBuilder(
                  animation: _controller,
                  builder: (context, _) => CustomPaint(
                    key: ValueKey('marquee-paint-' +
                        (widget.key is ValueKey<String>
                            ? (widget.key as ValueKey<String>).value
                            : widget.data)),
                    painter: MarqueePainter(
                      text: text,
                      offset: _controller.value * travel,
                    ),
                  ),
                )),
          ),
        ),
      );
    });
  }
}

class MarqueePainter extends CustomPainter {
  final TextPainter text;
  final double offset;

  MarqueePainter({required this.text, required this.offset});

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    final tile = text.width + Design.px(48);
    var x = -offset % tile;
    if (x > 0) x -= tile;
    while (x < size.width) {
      text.paint(canvas, Offset(x, 0));
      x += tile;
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(MarqueePainter oldDelegate) =>
      oldDelegate.offset != offset || oldDelegate.text.text != text.text;
}
