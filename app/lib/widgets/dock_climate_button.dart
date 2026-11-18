import 'package:flutter/material.dart';
import '../controller/launcher_controller.dart';
import '../model/vehicle_data.dart';
import '../theme/design_tokens.dart';
import '../theme/launcher_theme.dart';
import 'climate_panel.dart';

/// 底栏风量柱：七根斜柱，柱顶偏右、柱底偏左（`/` 方向倾斜 24°）。
///
/// 与原生 `fan` 1-7 **一一对应**，不再折成「三档」。未点亮的柱子仍保留
/// `.16` 的白色可见度——原实现用 `s.edge`，暗夜下几乎与胶囊底色同值，
/// 整排只剩一两根显眼，看着像坏了。
/// 点击向下降一档（与面板 fan-down 命令一致）。
class FanBars extends StatelessWidget {
  final LauncherController controller;
  final Map<String, dynamic> native;
  final double scale;
  const FanBars({
    super.key,
    required this.controller,
    required this.native,
    this.scale = 1,
  });

  /// 档位数：原生 fan 1-7。
  static const int levels = 7;

  /// 倾斜角。负值 = 逆时针，柱顶朝右上，与参考图同向。
  static const double _tilt = -24 * 3.14159265 / 180;

  /// 柱宽 / 柱间距（1920 口径）= 画布 4 / 4.7，设计稿方案 C 口径。
  static const double _barWidth = 4.8;
  static const double _barGap = 5.64;

  /// 七根柱子的总布局宽度（含间距），供上层排版预留。
  static double width(double scale) =>
      Design.px((levels - 1) * (_barWidth + _barGap) + _barWidth);

  @override
  Widget build(BuildContext context) {
    final s = SurfaceStyle.of(context);
    final demo = native['demo'] == true;
    final climate = native['climate'] is Map ? native['climate'] as Map : const {};
    final fanField = VehicleField.fromNative(native, 'fan');
    final fanKnown = demo || fanField.valid;
    final fanRaw = demo ? climate['fan'] : fanField.value;
    final fanLevel =
        fanKnown ? (int.tryParse('$fanRaw') ?? 0).clamp(0, levels) : 0;
    final writable = climateWritable(native, 'fan');
    final bars = <Widget>[];
    for (var index = 1; index <= levels; index++) {
      final lit = fanKnown && index <= fanLevel;
      bars.add(Padding(
          padding: EdgeInsets.only(
              right: index == levels ? 0 : Design.px(_barGap)),
          child: Transform.rotate(
              angle: _tilt,
              child: Container(
                  key: ValueKey('dock-fan-segment-$index'),
                  width: Design.px(_barWidth),
                  height: Design.px(12 * scale),
                  decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(Design.px(2.4)),
                      color: lit
                          ? s.accent.withValues(alpha: .9)
                          : s.text.withValues(alpha: .16))))));
    }
    return Tooltip(
        message: '风量，${fanKnown ? '$fanLevel' : '未知'}档（共七档）',
        child: Semantics(
            button: true,
            label: '风量，${fanKnown ? '$fanLevel' : '未知'}档（共七档）',
            enabled: writable,
            child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: writable ? () => controller.command('fan-down') : null,
                child: SizedBox(
                    key: const ValueKey('dock-fan-bars'),
                    height: Design.px(14 * scale),
                    child: Row(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: bars)))));
  }
}

/// 底栏风扇单元：**上面四瓣花、下面七根风量柱**，宽度由柱子撑开（画布 56）。
///
/// 这是实车原厂空调栏的排法（花与柱纵向叠放、共用一个命中区），
/// 与设计稿 `simulator.html` 里「花一个 cb 格 + 柱子另起一格」的并排版式
/// 不同——并排时两格加起来要 144 宽，横向吃掉了媒体胶囊的空间。
///
/// **不再占满 72 方格**：胶囊里六格由 `Row(spaceBetween)` 平分，
/// 这一格宽度跟柱子走，视觉间距才和其余五格相同（2026-11-15）。
///
/// 命中区：点花 → 打开空调面板；点柱子 → 风量降一档。
class DockFanCluster extends StatelessWidget {
  final LauncherController controller;
  final Map<String, dynamic> native;
  final double scale;
  const DockFanCluster({
    super.key,
    required this.controller,
    required this.native,
    this.scale = 1,
  });

  @override
  Widget build(BuildContext context) {
    final s = SurfaceStyle.of(context), demo = native['demo'] == true;
    final climate =
        native['climate'] is Map ? native['climate'] as Map : const {};
    final autoField = VehicleField.fromNative(native, 'auto');
    final fanField = VehicleField.fromNative(native, 'fan');
    final automatic = demo
        ? climate['auto'] == true
        : autoField.valid && autoField.value == true;
    final fanKnown = demo || fanField.valid;
    final fanLevel = fanKnown
        ? int.tryParse('${demo ? climate['fan'] : fanField.value}') ?? 0
        : 0;
    final label =
        '空调与座椅，${automatic ? "自动风量" : "风量 ${fanKnown ? "$fanLevel" : "未知"} 档"}';
    return Tooltip(
        message: label,
        child: Semantics(
            button: true,
            label: label,
            child: SizedBox(
                key: const ValueKey('climate'),
                height: Design.px(72),
                child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                        borderRadius:
                            BorderRadius.circular(s.controlRadius),
                        onTap: () => showClimatePanel(context, controller),
                        hoverColor: s.accent.withValues(alpha: .08),
                        focusColor: s.accent.withValues(alpha: .16),
                        highlightColor: s.accent.withValues(alpha: .24),
                        splashColor: s.accent.withValues(alpha: .16),
                        overlayColor: WidgetStateProperty.resolveWith(
                            (states) => s.accent.withValues(
                                alpha: states.contains(WidgetState.pressed)
                                    ? .24
                                    : .08)),
                        child: Center(
                            child: Column(
                                mainAxisSize: MainAxisSize.min,
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                              SizedBox(
                                  width: Design.px(25.2 * scale),
                                  height: Design.px(25.2 * scale),
                                  child: CustomPaint(
                                      key: const ValueKey('dock-fan-flower'),
                                      painter: FanFlowerPainter(
                                          color:
                                              fanKnown ? s.accent : s.muted))),
                              SizedBox(height: Design.px(3.6)),
                              FanBars(
                                  controller: controller,
                                  native: native,
                                  scale: scale),
                            ])))))));
  }
}

/// 四瓣风车花：设计稿 `simulator.html` 的 cubic 花瓣，绕中心旋转四次，整花再斜 22°。
///
/// 2026-11-15 方案 C 定稿：花瓣是**细长杯形**（不是实心方块）。之前那版
/// 四圆角方块在 21px 下会糊成一个带叉的圆角方框，实车参考图里其实是杯形瓣。
class FanFlowerPainter extends CustomPainter {
  final Color color;
  const FanFlowerPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final box = size.width / 24;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.3 * box
      ..strokeJoin = StrokeJoin.round
      ..color = color;
    // 一片花瓣（24 见方坐标系里从下往上收口的杯形），其余三片靠旋转复制。
    // 坐标先换算成「以中心为原点」——写成 `Path.shift()` 不管用，
    // 那个方法返回新 Path，级联调用会把它丢掉，花就会散成四个分离的圈。
    double p(double v) => (v - 12) * box;
    final petal = Path()
      ..moveTo(p(12), p(11.7))
      ..cubicTo(p(9.4), p(10.7), p(8.2), p(5.9), p(10.2), p(3))
      ..cubicTo(p(11.2), p(2.3), p(12.8), p(2.3), p(13.8), p(3))
      ..cubicTo(p(15.8), p(5.9), p(14.6), p(10.7), p(12), p(11.7))
      ..close();
    canvas.save();
    canvas.translate(12 * box, 12 * box);
    // 整花倾斜 22°，与原设计稿的 rotate(22 12 12) 一致。
    canvas.rotate(22 * 3.14159265 / 180);
    for (var quarter = 0; quarter < 4; quarter++) {
      canvas.save();
      canvas.rotate(quarter * 3.14159265 / 2);
      canvas.drawPath(petal, paint);
      canvas.restore();
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(FanFlowerPainter oldDelegate) => oldDelegate.color != color;
}
