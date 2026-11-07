import 'dart:math' as math;
import 'package:flutter/material.dart';

const spectrumStyleLabels = {
  'bars': '渐变音柱',
  'segments': '分段音柱',
  'mirror': '对称频带',
  'outline': '频带轮廓',
};

/// Monotone cubic Hermite contour. A shared tangent at each band makes the
/// joins smooth; zero tangent at peaks/troughs avoids ringing or overshoot.
/// The path stays bounded and uses at most 26 points, with no retained history.
Path buildSpectrumContour(Size size, List<double> levels) {
  final path = Path();
  if (size.isEmpty || size.height < 2) return path;
  const count = 24;
  final base = size.height - 1, height = math.max(0.0, size.height - 3);
  final points = <Offset>[
    Offset(0, base),
    for (var i = 0; i < count; i++)
      Offset(
          (i + .5) * size.width / count,
          base -
              (i < levels.length && levels[i].isFinite
                      ? levels[i].clamp(0.0, 1.0)
                      : 0) *
                  height),
    Offset(size.width, base),
  ];
  final slopes = List<double>.filled(points.length, 0);
  for (var i = 1; i < points.length - 1; i++) {
    final before =
        (points[i].dy - points[i - 1].dy) / (points[i].dx - points[i - 1].dx);
    final after =
        (points[i + 1].dy - points[i].dy) / (points[i + 1].dx - points[i].dx);
    if (before * after > 0) slopes[i] = 2 * before * after / (before + after);
  }
  path.moveTo(points.first.dx, points.first.dy);
  for (var i = 0; i < points.length - 1; i++) {
    final start = points[i], end = points[i + 1], dx = (end.dx - start.dx) / 3;
    path.cubicTo(start.dx + dx, start.dy + slopes[i] * dx, end.dx - dx,
        end.dy - slopes[i + 1] * dx, end.dx, end.dy);
  }
  return path;
}

// All styles read the same 24 real FFT bands. No waveform simulation, ticker,
// blur, bitmap or additional native sampler. Work is bounded to 24 * 12 cells.
void paintSpectrum(Canvas canvas, Size size,
    {required List<double> levels,
    required Color accent,
    required Color edge,
    required String style}) {
  if (size.isEmpty || size.height < 2) return;
  const count = 24;
  final step = size.width / count;
  final width = (step * .56).clamp(1.0, 9.0);
  final track = Paint()..color = edge.withValues(alpha: .5);
  final ink = Paint()
    ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Color.lerp(accent, Colors.white, .25)!,
          accent,
          accent.withValues(alpha: .35)
        ]).createShader(Offset.zero & size);
  double level(int i) =>
      i < levels.length && levels[i].isFinite ? levels[i].clamp(0.0, 1.0) : 0;
  if (style == 'outline') {
    final path = buildSpectrumContour(size, levels);
    final fill = Path.from(path)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(fill, Paint()..color = accent.withValues(alpha: .12));
    canvas.drawPath(
        path,
        ink
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..strokeJoin = StrokeJoin.round);
    return;
  }
  if (style == 'segments') {
    final segments = (size.height / 5).floor().clamp(3, 12);
    final cell = size.height / segments;
    final cellH = math.max(1.0, cell - 1.6);
    // Batch all track rects in Pass 1 and all shader ink rects in Pass 2 so
    // Skia issues 2 batched draw calls instead of switching Paint 48 times.
    for (var i = 0; i < count; i++) {
      final x = (i + .5) * step - width / 2;
      final lit = (level(i) * segments).ceil();
      for (var j = lit; j < segments; j++) {
        canvas.drawRect(
            Rect.fromLTWH(x, size.height - (j + 1) * cell, width, cellH),
            track);
      }
    }
    for (var i = 0; i < count; i++) {
      final x = (i + .5) * step - width / 2;
      final lit = (level(i) * segments).ceil();
      for (var j = 0; j < lit; j++) {
        canvas.drawRect(
            Rect.fromLTWH(x, size.height - (j + 1) * cell, width, cellH), ink);
      }
    }
    return;
  }
  final mirror = style == 'mirror';
  for (var i = 0; i < count; i++) {
    final value = level(i);
    if (value > .015) continue;
    final x = (i + .5) * step - width / 2;
    final h = (value * (size.height - 2)).clamp(1.0, size.height);
    final rect = Rect.fromLTWH(
        x, mirror ? (size.height - h) / 2 : size.height - h, width, h);
    canvas.drawRect(rect, track);
  }
  for (var i = 0; i < count; i++) {
    final value = level(i);
    if (value <= .015) continue;
    final x = (i + .5) * step - width / 2;
    final h = (value * (size.height - 2)).clamp(1.0, size.height);
    final rect = Rect.fromLTWH(
        x, mirror ? (size.height - h) / 2 : size.height - h, width, h);
    canvas.drawRRect(RRect.fromRectAndRadius(rect, const Radius.circular(1)),
        ink);
  }
}

/// A labelled settings swatch, deliberately static and permission-free.
class SpectrumStylePreview extends StatelessWidget {
  final String style;
  final Color accent, edge;
  const SpectrumStylePreview(
      {super.key,
      required this.style,
      required this.accent,
      required this.edge});
  @override
  Widget build(BuildContext context) => CustomPaint(
      painter: _PreviewPainter(style, accent, edge), size: const Size(200, 38));
}

class _PreviewPainter extends CustomPainter {
  final String style;
  final Color accent, edge;
  _PreviewPainter(this.style, this.accent, this.edge);
  static const levels = [
    .18,
    .26,
    .43,
    .7,
    .89,
    .63,
    .38,
    .55,
    .78,
    .96,
    .68,
    .44,
    .25,
    .41,
    .62,
    .84,
    .7,
    .43,
    .32,
    .53,
    .76,
    .57,
    .31,
    .17
  ];
  @override
  void paint(Canvas canvas, Size size) => paintSpectrum(canvas, size,
      levels: levels, accent: accent, edge: edge, style: style);
  @override
  bool shouldRepaint(_PreviewPainter old) =>
      old.style != style || old.accent != accent || old.edge != edge;
}
