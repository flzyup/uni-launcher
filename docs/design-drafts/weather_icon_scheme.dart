import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 新方案原型：25 个视觉档位。只用于出图，不进产品代码。
class _Cell extends StatelessWidget {
  final int slot;
  final double size;
  const _Cell(this.slot, {this.size = 96});
  @override
  Widget build(BuildContext context) =>
      SizedBox.square(dimension: size, child: CustomPaint(painter: _P(slot)));
}

class _P extends CustomPainter {
  final int v;
  _P(this.v);

  static const mint = Color(0xFF3BE2C0);
  static const cyan = Color(0xFF6FD3FF);
  static const amber = Color(0xFFFFB057);
  static const rose = Color(0xFFFF5FA8);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 100);
    Paint pen(Color c, [double w = 3]) => Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = w
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = c;

    var main = mint;
    final base = pen(main);

    // 统一云形（圆润三弧），dy 上移给降水腾位置
    Path cloud({double dy = 0}) => Path()
      ..moveTo(22, 76 + dy)
      ..cubicTo(8, 76 + dy, 8, 60 + dy, 22, 58 + dy)
      ..cubicTo(20, 42 + dy, 44, 34 + dy, 54, 46 + dy)
      ..cubicTo(58, 30 + dy, 82, 34 + dy, 82, 50 + dy)
      ..cubicTo(94, 54 + dy, 92, 76 + dy, 78, 76 + dy)
      ..close();

    void sun(Offset c, double r, {int rays = 8, Paint? paint}) {
      final p = paint ?? base;
      canvas.drawCircle(c, r, p);
      for (var i = 0; i < rays; i++) {
        final a = i * 2 * math.pi / rays;
        canvas.drawLine(c + Offset(math.cos(a), math.sin(a)) * (r + 4),
            c + Offset(math.cos(a), math.sin(a)) * (r + 9), p);
      }
    }

    void moon(Offset c, double r, Paint p) {
      // 弯月：外圆 - 偏移圆
      final outer = Path()..addOval(Rect.fromCircle(center: c, radius: r));
      final inner = Path()
        ..addOval(Rect.fromCircle(
            center: c + Offset(r * .55, -r * .25), radius: r * .92));
      canvas.drawPath(Path.combine(PathOperation.difference, outer, inner), p);
      // 两颗小星
      void star(Offset at, double s) {
        canvas.drawLine(at + Offset(-s, 0), at + Offset(s, 0), p);
        canvas.drawLine(at + Offset(0, -s), at + Offset(0, s), p);
      }

      star(c + Offset(r * .95, -r * .75), 3);
      star(c + Offset(r * .6, r * .95), 2);
    }

    void rain(int count, {double slant = 0, double from = 74}) {
      final p = pen(cyan, 3);
      for (var i = 0; i < count; i++) {
        final x = 30.0 + (count == 1 ? 20 : i * 40 / (count - 1));
        canvas.drawLine(Offset(x, from), Offset(x - slant, from + 12), p);
      }
    }

    void snow(int count, {double from = 80}) {
      final p = pen(cyan, 2.6);
      for (var i = 0; i < count; i++) {
        final x = 30.0 + (count == 1 ? 20 : i * 40 / (count - 1));
        for (var j = 0; j < 3; j++) {
          final a = j * math.pi / 3;
          canvas.drawLine(Offset(x - math.cos(a) * 4, from - math.sin(a) * 4),
              Offset(x + math.cos(a) * 4, from + math.sin(a) * 4), p);
        }
      }
    }

    void bolt() {
      final p = pen(amber, 3);
      canvas.drawPath(
          Path()
            ..moveTo(54, 72)
            ..lineTo(42, 88)
            ..lineTo(52, 88)
            ..lineTo(45, 100),
          p);
    }

    void lines(int count, {double y = 62, double gap = 9, double inset = 16}) {
      for (var i = 0; i < count; i++) {
        final w = 100 - inset * 2 - (i % 2) * 10;
        canvas.drawLine(Offset(inset + (i % 2) * 5, y + i * gap),
            Offset(inset + 5 + w, y + i * gap), base);
      }
    }

    switch (v) {
      // ---------- 第 1 行 ----------
      case 0: // 晴
        sun(const Offset(50, 50), 22);
      case 1: // 晴（夜）
        moon(const Offset(52, 50), 24, base);
      case 2: // 晴间多云：双色，太阳被云切
        final sp = pen(amber, 3);
        canvas.save();
        canvas.clipPath(Path.combine(PathOperation.difference,
            Path()..addRect(const Rect.fromLTWH(0, 0, 100, 100)), cloud()));
        sun(const Offset(34, 26), 12, paint: sp);
        canvas.restore();
        canvas.drawPath(cloud(), base);
      case 3: // 多云：云后另一朵云的顶（半透明），读作"后面还有一层云"
        canvas.drawPath(
            Path()
              ..moveTo(26, 52)
              ..cubicTo(26, 30, 50, 26, 58, 42)
              ..cubicTo(63, 25, 88, 29, 86, 50),
            pen(main.withValues(alpha: .5)));
        canvas.drawPath(cloud(), base);
      case 4: // 阴：云 + 云下一道短横线
        canvas.drawPath(cloud(), base);
        canvas.drawLine(const Offset(34, 84), const Offset(66, 84), base);
      case 5: // 阵雨：太阳露头 + 云 + 3 雨线
        final sp = pen(amber, 3);
        canvas.save();
        canvas.clipPath(Path.combine(PathOperation.difference,
            Path()..addRect(const Rect.fromLTWH(0, 0, 100, 100)), cloud()));
        sun(const Offset(36, 22), 10, paint: sp);
        canvas.restore();
        canvas.drawPath(cloud(), base);
        rain(3);
      // ---------- 第 2 行 ----------
      case 6: // 小雨
        canvas.drawPath(cloud(), base);
        rain(2);
      case 7: // 中雨
        canvas.drawPath(cloud(), base);
        rain(3);
      case 8: // 大雨
        canvas.drawPath(cloud(), base);
        rain(4, slant: 2);
      case 9: // 暴雨（数量满 + 斜雨 + 加粗）
        canvas.drawPath(cloud(), base);
        canvas.drawLine(const Offset(30, 74), const Offset(27, 88),
            pen(cyan, 4));
        canvas.drawLine(const Offset(44, 74), const Offset(41, 90),
            pen(cyan, 4));
        canvas.drawLine(const Offset(58, 74), const Offset(55, 90),
            pen(cyan, 4));
        canvas.drawLine(const Offset(72, 74), const Offset(69, 88),
            pen(cyan, 4));
      case 10: // 雷阵雨
        canvas.drawPath(cloud(), base);
        bolt();
        rain(1);
      case 11: // 冰雹
        canvas.drawPath(cloud(), base);
        bolt();
        final hp = pen(cyan, 3);
        canvas.drawCircle(const Offset(70, 88), 3.2, hp);
        canvas.drawCircle(const Offset(30, 90), 3.2, hp);
      // ---------- 第 3 行 ----------
      case 12: // 冻雨：左边一条雨线、右边一颗冰晶，并排
        canvas.drawPath(cloud(), base);
        canvas.drawLine(const Offset(38, 78), const Offset(38, 90),
            pen(cyan, 3));
        for (var j = 0; j < 3; j++) {
          final a = j * math.pi / 3;
          canvas.drawLine(Offset(62 - math.cos(a) * 4.6, 84 - math.sin(a) * 4.6),
              Offset(62 + math.cos(a) * 4.6, 84 + math.sin(a) * 4.6),
              pen(cyan, 2.6));
        }
      case 13: // 雨夹雪：左雨线 + 右雪花，同一层
        canvas.drawPath(cloud(), base);
        canvas.drawLine(const Offset(38, 78), const Offset(38, 90),
            pen(cyan, 3));
        for (var j = 0; j < 3; j++) {
          final a = j * math.pi / 3;
          canvas.drawLine(Offset(62 - math.cos(a) * 4.6, 84 - math.sin(a) * 4.6),
              Offset(62 + math.cos(a) * 4.6, 84 + math.sin(a) * 4.6),
              pen(cyan, 2.6));
        }
      case 14: // 小雪
        canvas.drawPath(cloud(), base);
        snow(1, from: 86);
      case 15: // 中雪
        canvas.drawPath(cloud(), base);
        snow(2, from: 86);
      case 16: // 大雪
        canvas.drawPath(cloud(), base);
        snow(3, from: 86);
      case 17: // 暴雪：满 + 地面积雪线
        canvas.drawPath(cloud(), base);
        snow(4, from: 82);
        canvas.drawLine(const Offset(20, 96), const Offset(80, 96),
            pen(cyan, 3));
      // ---------- 第 4 行 ----------
      case 18: // 轻雾 / 雾
        lines(3, y: 36, gap: 12, inset: 14);
      case 19: // 霾：横线 + 颗粒（琥珀）
        main = Color.lerp(mint, amber, .55)!;
        lines(3, y: 36, gap: 12, inset: 14);
        final dp = pen(main, 2.6);
        for (final o in [
          const Offset(30, 30),
          const Offset(48, 27),
          const Offset(66, 31),
          const Offset(40, 62),
          const Offset(62, 64)
        ]) {
          canvas.drawCircle(o, 1.6, dp..style = PaintingStyle.fill);
          dp.style = PaintingStyle.stroke;
        }
      case 20: // 沙尘：横线（斜）+ 颗粒
        main = Color.lerp(mint, amber, .65)!;
        final sp = pen(main, 3);
        canvas.drawLine(const Offset(14, 40), const Offset(86, 36), sp);
        canvas.drawLine(const Offset(20, 54), const Offset(80, 50), sp);
        canvas.drawLine(const Offset(16, 68), const Offset(74, 64), sp);
        final dp = pen(main, 2.4)..style = PaintingStyle.fill;
        for (final o in [
          const Offset(34, 30),
          const Offset(58, 26),
          const Offset(44, 62),
          const Offset(68, 58)
        ]) {
          canvas.drawCircle(o, 1.5, dp);
        }
      case 21: // 大风：三道风线，末端各卷一个小圈
        for (var i = 0; i < 3; i++) {
          final y = 32.0 + i * 18;
          canvas.drawPath(
              Path()
                ..moveTo(16, y)
                ..lineTo(56 - i * 8, y)
                ..cubicTo(80, y, 80, y - 16, 66, y - 12)
                ..cubicTo(56, y - 9, 58, y + 6, 68, y + 4),
              base);
        }
      case 22: // 热带风暴：两层旋臂 + 中心
        for (var i = 0; i < 2; i++) {
          canvas.save();
          canvas.translate(50, 50);
          canvas.rotate(i * math.pi);
          canvas.drawPath(
              Path()
                ..moveTo(0, -6)
                ..cubicTo(28, -30, 40, 8, 18, 24)
                ..cubicTo(30, 2, 8, -2, 0, -6),
              base);
          canvas.restore();
        }
        canvas.drawCircle(const Offset(50, 50), 4, base);
      // ---------- 第 5 行 ----------
      case 23: // 热：温度计 + 右上小太阳
        canvas.save();
        canvas.translate(50, 54);
        canvas.scale(.78);
        canvas.translate(-50, -54);
        final tp = pen(amber, 3.4);
        canvas.drawPath(
            Path()
              ..moveTo(43, 56)
              ..lineTo(43, 24)
              ..cubicTo(43, 13, 57, 13, 57, 24)
              ..lineTo(57, 56)
              ..cubicTo(70, 68, 60, 84, 50, 84)
              ..cubicTo(40, 84, 30, 68, 43, 56),
            tp);
        canvas.drawLine(const Offset(50, 48), const Offset(50, 70), tp);
        canvas.drawCircle(
            const Offset(50, 72), 5.4, tp..style = PaintingStyle.fill);
        canvas.restore();
        final sp = pen(amber, 3);
        sun(const Offset(76, 24), 6.5, rays: 6, paint: sp);
      case 24: // 冷：温度计（半柱）+ 右上雪花
        canvas.save();
        canvas.translate(50, 54);
        canvas.scale(.78);
        canvas.translate(-50, -54);
        final cp = pen(cyan, 3.4);
        canvas.drawPath(
            Path()
              ..moveTo(43, 56)
              ..lineTo(43, 24)
              ..cubicTo(43, 13, 57, 13, 57, 24)
              ..lineTo(57, 56)
              ..cubicTo(70, 68, 60, 84, 50, 84)
              ..cubicTo(40, 84, 30, 68, 43, 56),
            cp);
        canvas.drawLine(const Offset(50, 46), const Offset(50, 66), cp);
        canvas.restore();
        final sf = pen(cyan, 2.8);
        for (var j = 0; j < 3; j++) {
          final a = j * math.pi / 3;
          canvas.drawLine(Offset(76 - math.cos(a) * 6, 26 - math.sin(a) * 6),
              Offset(76 + math.cos(a) * 6, 26 + math.sin(a) * 6), sf);
        }
    }
  }

  @override
  bool shouldRepaint(covariant _P old) => old.v != v;
}

void main() {
  testWidgets('weather icon scheme', (t) async {
    t.view.physicalSize = const Size(700, 620);
    t.view.devicePixelRatio = 1;
    Widget row(int from, int to) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = from; i <= to; i++)
            Padding(
                padding: const EdgeInsets.all(8), child: _Cell(i)),
        ]);
    await t.pumpWidget(MaterialApp(
        home: Scaffold(
            backgroundColor: const Color(0xFF0B0D0E),
            body: Center(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
              row(0, 5),
              row(6, 11),
              row(12, 17),
              row(18, 22),
              row(23, 24),
            ])))));
    await t.pumpAndSettle();
    await expectLater(
        find.byType(Column).first, matchesGoldenFile('zz_wicon_scheme.png'));
  });
}
