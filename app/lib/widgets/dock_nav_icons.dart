import 'package:flutter/material.dart';

/// 底栏导航键图标：按 eclipse 设计稿 SVG path 1:1 复刻（24 视窗坐标系）。
/// 来源 theme-styles/eclipse/simulator.html 的 .dk-b 五枚图标，勿手改路径。

/// 纯 chevron 返回（设计稿 M14.5 5.5L8 12l6.5 6.5，无尾巴）。
class NavChevronIcon extends StatelessWidget {
  final double size;
  final Color color;
  const NavChevronIcon({super.key, required this.size, required this.color});
  @override
  Widget build(BuildContext context) => CustomPaint(
      size: Size.square(size),
      painter: _StrokeIconPainter(color, 1.8, (p) {
        p.moveTo(14.5, 5.5);
        p.lineTo(8, 12);
        p.lineTo(14.5, 18.5);
      }));
}

/// 房子（设计稿双 path：屋体圆角 1.3 + 门口线）。
class NavHomeIcon extends StatelessWidget {
  final double size;
  final Color color;
  const NavHomeIcon({super.key, required this.size, required this.color});
  @override
  Widget build(BuildContext context) => CustomPaint(
      size: Size.square(size),
      painter: _StrokeIconPainter(color, 1.7, (p) {
        p.moveTo(4.5, 11);
        p.lineTo(12, 4.5);
        p.lineTo(19.5, 11);
        p.lineTo(19.5, 18.7);
        p.arcToPoint(const Offset(18.2, 20),
            radius: const Radius.circular(1.3), clockwise: true);
        p.lineTo(5.8, 20);
        p.arcToPoint(const Offset(4.5, 18.7),
            radius: const Radius.circular(1.3), clockwise: true);
        p.close();
      }, extra: (p) {
        p.moveTo(9.6, 20);
        p.lineTo(9.6, 14.6);
        p.lineTo(14.4, 14.6);
        p.lineTo(14.4, 20);
      }, extraStroke: 1.6));
}

/// 全部应用：九宫格实心圆点（r=2）。
class NavAppsDotsIcon extends StatelessWidget {
  final double size;
  final Color color;
  const NavAppsDotsIcon({super.key, required this.size, required this.color});
  @override
  Widget build(BuildContext context) => CustomPaint(
      size: Size.square(size),
      painter: _DotsIconPainter(color, const [
        Offset(5.2, 5.2), Offset(12, 5.2), Offset(18.8, 5.2),
        Offset(5.2, 12), Offset(12, 12), Offset(18.8, 12),
        Offset(5.2, 18.8), Offset(12, 18.8), Offset(18.8, 18.8),
      ]));
}

/// 最近任务：rx=3 圆角方框。
class NavRecentsIcon extends StatelessWidget {
  final double size;
  final Color color;
  const NavRecentsIcon({super.key, required this.size, required this.color});
  @override
  Widget build(BuildContext context) => CustomPaint(
      size: Size.square(size),
      painter: _StrokeIconPainter(color, 1.7, (p) {
        p.addRRect(RRect.fromRectAndRadius(
            const Rect.fromLTWH(4.5, 4.5, 15, 15),
            const Radius.circular(3)));
      }));
}

/// 360 影像：圆环 + 环内 "360" 字样。
class NavCamera360Icon extends StatelessWidget {
  final double size;
  final Color color;
  const NavCamera360Icon({super.key, required this.size, required this.color});
  @override
  Widget build(BuildContext context) => CustomPaint(
      size: Size.square(size),
      painter: _Camera360Painter(color));
}

class _StrokeIconPainter extends CustomPainter {
  final Color color;
  final double stroke;
  final void Function(Path) build;
  final void Function(Path)? extra;
  final double extraStroke;
  _StrokeIconPainter(this.color, this.stroke, this.build,
      {this.extra, this.extraStroke = 1.7});
  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 24);
    Paint mk(double w) => Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = w
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = color;
    final main = Path();
    build(main);
    canvas.drawPath(main, mk(stroke));
    if (extra != null) {
      final second = Path();
      extra!(second);
      canvas.drawPath(second, mk(extraStroke));
    }
  }

  @override
  bool shouldRepaint(covariant _StrokeIconPainter old) => old.color != color;
}

class _DotsIconPainter extends CustomPainter {
  final Color color;
  final List<Offset> dots;
  _DotsIconPainter(this.color, this.dots);
  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 24);
    final paint = Paint()..color = color;
    for (final d in dots) {
      canvas.drawCircle(d, 2, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _DotsIconPainter old) => old.color != color;
}

class _Camera360Painter extends CustomPainter {
  final Color color;
  _Camera360Painter(this.color);
  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 24);
    canvas.drawCircle(
        const Offset(12, 12),
        8.6,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.7
          ..color = color);
    final tp = TextPainter(
        text: TextSpan(
            text: '360',
            style: TextStyle(
                fontSize: 7.2,
                fontWeight: FontWeight.w600,
                color: color)),
        textDirection: TextDirection.ltr)
      ..layout();
    // 数字没有下伸部，按字形盒中心对准圆心（+0.4 光学补偿）。
    tp.paint(
        canvas,
        Offset(12 - tp.width / 2, 12 - tp.height / 2 + 0.4));
  }

  @override
  bool shouldRepaint(covariant _Camera360Painter old) => old.color != color;
}
