import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/design_tokens.dart';
import '../theme/launcher_theme.dart';
import 'svg_path.dart';
import 'uni_icon.dart';

/// 设计稿一组卡片头配色（`gc-*` 渐变的终点色），蓝 / 薄荷 / 紫 / 琥珀 / 青。
abstract final class CardTint {
  static const blue = Color(0xFF4E8CF8);
  static const mint = Color(0xFF3BE2C0);
  static const violet = Color(0xFF8E6CFF);
  static const amber = Color(0xFFFFB057);
  static const cyan = Color(0xFF6FD3FF);
}

/// `assets/icons/*.svg` 名 → 稿子图形名。没有对应图形的（导航 / 音乐 /
/// 红绿灯 / 轮胎 / 油量）返回空串，[CardGlyph] 会画成「开口环 + 原图标」。
String glyphKindForSymbol(String symbol) => switch (symbol) {
      'car' => 'car',
      'battery' => 'battery',
      'air' => 'air',
      'clock' => 'clock',
      'apps' => 'apps',
      'user' => 'user',
      'broom' => 'cleanup',
      'cloud' => 'weather',
      'calendar' => 'calendar',
      _ => '',
    };

/// 卡片头图形（稿子 `.card-hd .ic`）。
///
/// 以前每张卡头的图标是 `assets/icons/*.svg` 里那张通用线性图，直接铺一块
/// 43 画布的图片；稿子的语言是「虚线开口环（r17，缺口在右上）+ 环内一枚渐变
/// 线描图形」，每张卡还有各自的色相。这里按稿子重画：环和图形都画在同一个 44
/// 视口里，坐标照抄 simulator.html，改稿时一比一核。
///
/// 稿子没给图形的卡（导航 / 音乐 / 红绿灯 / 轮胎 / 油量）走 [symbol]：仍套同一
/// 枚开口环，里面放原来那条线性图标——否则一屏里一半是环、一半是散图标。
class CardGlyph extends StatelessWidget {
  /// 稿子图形名：car / battery / clock / apps / gauge / air / weather /
  /// calendar / user / cleanup。未知值退到 [symbol]。
  final String kind;

  /// `assets/icons/<symbol>.svg`，[kind] 没有对应图形时用它兜底。
  final String symbol;

  /// 画布单位，52.8 即稿子 `.ic` 的 44（内部再经 [Design.px] 换算）。
  final double size;

  /// 覆盖配色；不传按 [kind] 取稿子色相。
  final Color? tint;

  const CardGlyph(this.kind,
      {super.key, required this.symbol, this.size = 52.8, this.tint});

  /// 稿子色相。浅色两套皮肤不套这套配色——它们只有单强调色的语言。
  static Color tintOf(String kind) => switch (kind) {
        'car' => CardTint.blue,
        'battery' || 'cleanup' => CardTint.mint,
        'gauge' => CardTint.amber,
        'air' || 'weather' => CardTint.cyan,
        _ => CardTint.violet,
      };

  @override
  Widget build(BuildContext context) {
    final s = SurfaceStyle.of(context);
    // 浅色皮肤不套稿子的分卡配色（那套属于 eclipse 暗夜），也不直接用 accent：
    // 浅色两套的强调色偏淡，2px 的细线铺在白卡上会糊掉。往正文墨色里推 35%
    // 压深一档，线才立得住。
    final color = tint ??
        (s.nocturne ? tintOf(kind) : Color.lerp(s.accent, s.text, .35)!);
    final side = Design.px(size);
    final spec = _glyphs[kind];
    if (spec != null) {
      return SizedBox.square(
          dimension: side,
          child: CustomPaint(
              painter: _GlyphPainter(spec, color, light: !s.nocturne)));
    }
    return SizedBox.square(
        dimension: side,
        child: Stack(alignment: Alignment.center, children: [
          CustomPaint(
              size: Size.square(side),
              painter: _GlyphPainter(const [], color, light: !s.nocturne)),
          UniIcon(symbol,
              size: side * .44, color: color.withValues(alpha: .85)),
        ]));
  }
}

// 环：稿子是 circle r=17、dasharray "76 31"、rotate(-40)。周长 106.8，即一段
// 76 的实线 + 31 的空白 = 256° 的开口环，缺口朝右上。
const double _ringRadius = 17;
const double _ringDash = 76;
const double _ringCircum = 2 * math.pi * _ringRadius;
const double _ringStart = -40 * math.pi / 180;

class _GlyphPainter extends CustomPainter {
  final List<_El> els;
  final Color color;

  /// 浅色皮肤。稿子的线描是「白 .65 → 卡色 .85」的渐变，白底上白色那端直接
  /// 消失；浅色改成「淡强调 → 强调」，笔画才立得住。
  final bool light;
  const _GlyphPainter(this.els, this.color, {this.light = false});

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 44);
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..strokeCap = StrokeCap.round
      ..color = color.withValues(alpha: .22)
      ..isAntiAlias = true;
    canvas.drawArc(
        Rect.fromCircle(center: const Offset(22, 22), radius: _ringRadius),
        _ringStart,
        _ringDash / _ringCircum * 2 * math.pi,
        false,
        ring);
    for (final el in els) {
      el.paint(canvas, color, light: light);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _GlyphPainter old) =>
      old.color != color || old.els != els || old.light != light;
}

/// 一条图形元素。稿子这 11 张卡头只用到三种画法：描边路径、圆角矩形、实心
/// 小圆点，所以不搬整套 SVG 解析，只把这三类画出来，坐标沿用 44 视口。
class _El {
  final Path? path;
  final Rect? box;
  final double corner, dotRadius;
  final Offset? dot;
  final double width, opacity, rotate;

  const _El._({
    this.path,
    this.box,
    this.corner = 0,
    this.dot,
    this.dotRadius = 0,
    this.width = 1.6,
    this.opacity = 1,
    this.rotate = 0,
  });

  /// 描边路径（`d` 只用到 M/L/H/V/C/S/A/Z 及相对写法）。
  factory _El.path(String d, {double width = 1.6, double opacity = 1}) =>
      _El._(path: svgPath(d), width: width, opacity: opacity);

  /// 圆角矩形描边；[rotate] 是绕自身中心的旋转角（度），稿子里的毛刷把。
  factory _El.roundRect(double x, double y, double w, double h, double r,
          {double width = 1.6, double opacity = 1, double rotate = 0}) =>
      _El._(
          box: Rect.fromLTWH(x, y, w, h),
          corner: r,
          width: width,
          opacity: opacity,
          rotate: rotate);

  /// 描边圆。
  factory _El.circle(double cx, double cy, double r,
          {double width = 1.6, double opacity = 1}) =>
      _El._(
          box: Rect.fromCircle(center: Offset(cx, cy), radius: r),
          corner: r,
          width: width,
          opacity: opacity);

  /// 实心小圆点（仪表指针的轴心）。
  factory _El.dot(double cx, double cy, double r) =>
      _El._(dot: Offset(cx, cy), dotRadius: r, opacity: .85);

  void paint(Canvas canvas, Color tint, {bool light = false}) {
    final paint = Paint()..isAntiAlias = true;
    if (dot != null) {
      canvas.drawCircle(
          dot!, dotRadius, paint..color = tint.withValues(alpha: opacity));
      return;
    }
    // 稿子的描边色是「白 .65 → 卡色 .85」的对角渐变，透明度按元素乘进去。
    // 浅色底上白色那端看不见，换成「淡强调 → 强调」。
    paint
      ..style = PaintingStyle.stroke
      ..strokeWidth = width
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..shader = LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: light
                  ? [
                      tint.withValues(alpha: .45 * opacity),
                      tint.withValues(alpha: .95 * opacity),
                    ]
                  : [
                      Colors.white.withValues(alpha: .65 * opacity),
                      tint.withValues(alpha: .85 * opacity),
                    ])
          .createShader(const Rect.fromLTWH(0, 0, 44, 44));
    canvas.save();
    if (rotate != 0 && box != null) {
      canvas.translate(box!.center.dx, box!.center.dy);
      canvas.rotate(rotate * math.pi / 180);
      canvas.translate(-box!.center.dx, -box!.center.dy);
    }
    if (path != null) {
      canvas.drawPath(path!, paint);
    } else if (box != null) {
      canvas.drawRRect(
          RRect.fromRectAndRadius(box!, Radius.circular(corner)), paint);
    }
    canvas.restore();
  }
}

/// 稿子的 11 张卡头图形，坐标与 simulator.html 一致（44 视口）。
final Map<String, List<_El>> _glyphs = {
  // 车况与胎压 / 胎压：车顶弧 + 底边
  'car': [
    _El.path('M13 28c0-4 2-9 4.5-11h9c2.5 2 4.5 7 4.5 11'),
    _El.roundRect(11.5, 27, 21, 4, 2),
  ],
  // 动力电池：电池壳 + 正极 + 对勾
  'battery': [
    _El.roundRect(13, 17, 18, 12, 3),
    _El.path('M31 20.5h3.5v5H31'),
    _El.path('M17.5 22.5l3.4 4 4.8-6.4'),
  ],
  // 时间天气：表盘 + 指针 + 右上一小段弧
  'clock': [
    _El.circle(22, 23, 8.5),
    _El.path('M22 18v5l3.4 2'),
    _El.path('M30 10.5a5 5 0 1 1 5 6.4', width: 1.4, opacity: .7),
  ],
  // 快捷应用：四宫格，对角两块实、另两块淡
  'apps': [
    _El.roundRect(12, 12, 8, 8, 2.4, width: 1.5),
    _El.roundRect(24, 12, 8, 8, 2.4, width: 1.5, opacity: .6),
    _El.roundRect(12, 24, 8, 8, 2.4, width: 1.5, opacity: .6),
    _El.roundRect(24, 24, 8, 8, 2.4, width: 1.5),
  ],
  // 行车信息：仪表弧 + 指针 + 轴心
  'gauge': [
    _El.path('M13 26.5c0-6.5 4-11.5 9-11.5s9 5 9 11.5'),
    _El.path('M22 26.5l4.6-5.4'),
    _El.dot(22, 26.5, 1.8),
  ],
  // 车内空气：三道气流弧
  'air': [
    _El.path(
        'M12.5 18.5c6-4.5 13-4.5 19 0M14.5 23c4.8-3.4 10.2-3.4 15 0'
        'M17 27.2c3.2-2.2 6.8-2.2 10 0',
        width: 1.5),
  ],
  // 天气：云 + 地平线
  'weather': [
    _El.path('M29 26a7 7 0 0 0-1.6-13.8 8.6 8.6 0 0 0-16.4 2.4'
        'A5.8 5.8 0 0 0 12 25.7'),
    _El.path('M15 30h13', opacity: .7),
  ],
  // 日历：框 + 顶栏 + 两个挂钩
  'calendar': [
    _El.roundRect(12.5, 13.5, 19, 17, 3),
    _El.path('M12.5 19.5h19M18 10.5v5M26 10.5v5', width: 1.5),
  ],
  // 账号：头像 + 肩线
  'user': [
    _El.circle(22, 16.4, 4.7),
    _El.path('M13.4 31.6c.7-4.7 4.3-7.5 8.6-7.5s7.9 2.8 8.6 7.5'),
  ],
  // 系统清理：刷柄 + 斜置刷头 + 两道刷毛
  'cleanup': [
    _El.path('M30.8 13.2l-8.1 8.1', width: 1.9),
    _El.roundRect(13.4, 21.6, 9.2, 12.2, 2.8, width: 1.7, rotate: -45),
    _El.path('M16.6 29.4l2.6-2.6M19.2 32l2.6-2.6', width: 1.4),
  ],
};
