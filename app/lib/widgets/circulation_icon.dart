import 'package:flutter/material.dart';

/// Cabin outline and direction of airflow. Null means the vehicle has not
/// reported a trustworthy circulation state; it must not imply fresh air.
class CirculationIcon extends StatelessWidget {
  final bool? recirculating;
  final Color color;
  final double size;
  const CirculationIcon(
      {super.key,
      required this.recirculating,
      required this.color,
      this.size = 28});

  @override
  Widget build(BuildContext context) => CustomPaint(
      size: Size.square(size),
      painter: _CirculationPainter(recirculating, color));
}

class _CirculationPainter extends CustomPainter {
  final bool? recirculating;
  final Color color;
  const _CirculationPainter(this.recirculating, this.color);
  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 32, size.height / 32);
    final line = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(
        Path()
          ..moveTo(3, 23)
          ..lineTo(5, 15)
          ..lineTo(9, 9)
          ..quadraticBezierTo(10, 7, 13, 7)
          ..lineTo(21, 7)
          ..quadraticBezierTo(24, 7, 26, 11)
          ..lineTo(29, 16)
          ..lineTo(29, 23)
          ..quadraticBezierTo(29, 25, 27, 25)
          ..lineTo(5, 25)
          ..quadraticBezierTo(3, 25, 3, 23),
        line);
    if (recirculating == true) {
      canvas.drawPath(
          Path()
            ..moveTo(10, 18)
            ..cubicTo(11, 13, 21, 12, 23, 17)
            ..lineTo(20, 16)
            ..moveTo(23, 17)
            ..lineTo(22, 14),
          line);
    } else if (recirculating == false) {
      canvas.drawPath(
          Path()
            ..moveTo(1, 15)
            ..lineTo(17, 15)
            ..moveTo(14, 12)
            ..lineTo(17, 15)
            ..lineTo(14, 18),
          line);
    } else {
      canvas.drawLine(const Offset(12, 17), const Offset(20, 17), line);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_CirculationPainter old) =>
      old.recirculating != recirculating || old.color != color;
}
