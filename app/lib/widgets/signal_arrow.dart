import 'package:flutter/material.dart';

import 'svg_path.dart';

/// 稿子 `.ring svg` 里的方向箭头：24 视口实心路径，左转那条带 90° 弯角。
///
/// 以前这里是 `assets/icons/signal-*.svg` 那套线性图标——直行和左转都只是一根
/// 直线加个箭头，稿子里左转那条「先上去、再拐弯、箭头朝左」的弯角完全没画出来。
/// 稿子只给了左转、直行两条路径，右转是左转沿竖直轴镜像；掉头按同一套笔画重量
/// （杆 4.6、箭头 12×7.5）补一条。
abstract final class SignalArrowPaths {
  /// 稿子 f1 左转（含弯角）：箭头朝左，尾部上去后向右下拐。
  static const left = 'M1.5 7L10.4 2V4.7H14.6A6.3 6.3 0 0 1 20.9 11V17.2'
      'A2.3 2.3 0 0 1 16.3 17.2V11A1.7 1.7 0 0 0 14.6 9.3H10.4V12Z';

  /// 稿子 f1 直行：箭头朝上，杆底两端圆角。
  static const straight =
      'M6 10.5L12 3L18 10.5V11.5H14.3V19.5A2.3 2.3 0 0 1 9.7 19.5V11.5H6Z';

  /// 掉头：左杆下来接到朝下的箭头，右杆到底，顶部半环（外 r8.2 / 内 r3.6）。
  static const uturn = 'M8.4 13.8V12A3.6 3.6 0 0 1 15.6 12V20.8H20.2V12'
      'A8.2 8.2 0 0 0 3.8 12V13.8H0.1L6.1 20.6L12.1 13.8H8.4Z';

  static final _cache = <String, Path>{};

  /// 方向 → 路径。未知方向返回 null，调用方自己兜底。
  static Path? of(String direction) => switch (direction) {
        'left' => _cached('left', left),
        'straight' => _cached('straight', straight),
        'right' => _cached('right', left),
        'uturn' => _cached('uturn', uturn),
        _ => null,
      };

  static Path _cached(String key, String d) =>
      _cache.putIfAbsent(key, () => svgPath(d));

  /// 需要镜像（沿竖直轴）的方向。
  static bool mirrored(String direction) => direction == 'right';
}

/// 一颗方向箭头。未知方向不画（调用方用通用红绿灯图标兜底）。
class SignalArrow extends StatelessWidget {
  final String direction;
  final double size;
  final Color color;

  /// 稿子路径的视口边长。
  static const double viewBox = 24;

  const SignalArrow(
      {super.key,
      required this.direction,
      required this.size,
      required this.color});

  @override
  Widget build(BuildContext context) => SizedBox.square(
      dimension: size,
      child: CustomPaint(painter: _SignalArrowPainter(direction, color)));
}

class _SignalArrowPainter extends CustomPainter {
  final String direction;
  final Color color;
  _SignalArrowPainter(this.direction, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final path = SignalArrowPaths.of(direction);
    if (path == null) return;
    final k = size.width / SignalArrow.viewBox;
    canvas.save();
    if (SignalArrowPaths.mirrored(direction)) {
      canvas.translate(size.width, 0);
      canvas.scale(-k, k);
    } else {
      canvas.scale(k);
    }
    canvas.drawPath(
        path,
        Paint()
          ..isAntiAlias = true
          ..style = PaintingStyle.fill
          ..color = color);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _SignalArrowPainter old) =>
      old.direction != direction || old.color != color;
}
