import 'dart:math' as math;

import 'package:flutter/material.dart';
import '../controller/launcher_controller.dart';
import '../theme/design_tokens.dart';
import '../theme/launcher_theme.dart';
import 'circulation_icon.dart';
import 'choice_button.dart';
import 'spec_panel.dart';
import 'uni_icon.dart';
import '../model/vehicle_data.dart';
import 'launcher_dialog.dart';
import 'seat_controls.dart';
import 'card_content.dart' show mapOf;
import 'native_slice_builder.dart';

/// 设计稿 `#f7`（`theme-styles/eclipse/simulator.html`）：
/// 1200 宽的底部浮层，标题 21 + 副标题 12.5；三张平面卡（flex 10/11/10）承载
/// 主驾温度 / 风量 / 副驾温度，温度卡下面是一条冷热渐变条，风量卡下面是
/// 七段刻度；再往下是五颗 `.cmode` 胶囊和两张座椅卡。
Future<void> showClimatePanel(
    BuildContext context, LauncherController c) async {
  if (await c.presentGlobalPanel('climate') || !context.mounted) return;
  await showLauncherSheet<void>(context,
      title: '空调与座椅',
      closeLabel: '关闭空调',
      width: Design.dz(1200),
      showHeader: false,
      padding: EdgeInsets.fromLTRB(
          Design.dz(30), Design.dz(24), Design.dz(30), Design.dz(26)),
      builder: (context) => NativeSliceBuilder(
          valueListenable: c.native,
          select: (n) => [
                n['demo'],
                n['climate'],
                mapOf(n['vehicle'])['climate'],
                mapOf(n['vehicle'])['fields'],
                mapOf(n['vehicle'])['writable'],
                mapOf(n['vehicle'])['lastCommand'],
              ],
          builder: (context, n) {
            final s = SurfaceStyle.of(context),
                ink = s.text,
                demo = n['demo'] == true,
                climate = mapOf(n['climate']);
            final autoField = VehicleField.fromNative(n, 'auto');
            final fanField = VehicleField.fromNative(n, 'fan');
            final automatic = demo
                ? climate['auto'] == true
                : (autoField.valid && autoField.value == true) ||
                    (fanField.valid &&
                        '${fanField.value}'.toLowerCase() == 'auto') ||
                    climate['auto'] == true;
            String rememberedValue(String key) {
              final field = VehicleField.fromNative(n, key);
              if (field.valid) {
                return key == 'fan'
                    ? field.display(decimals: 0)
                    : field.display();
              }
              final value = climate[key];
              if (value is num) {
                return key == 'fan'
                    ? value.toStringAsFixed(0)
                    : value.toStringAsFixed(1);
              }
              return value == null ? '—' : '$value';
            }

            bool valueLive(String key) =>
                demo || VehicleField.fromNative(n, key).valid;

            /// `.cmode`：48 高、圆角 13；选中是强调色渐变实底 + acc-d 字。
            ///
            /// 配色按皮肤分两路：
            /// - 暗夜：完全照 `.cmode` 画（6% 底 / 16% 描边、字 58%、选中投影
            ///   55%），`ChoiceButton` 那套 `.opt` 的字是 86%、投影 45%，
            ///   摆在这排上未选中太亮、选中太淡，所以这里自绘。
            /// - 经典 / 蓝玻璃：交给 [ChoiceButton]，选中态走各自的
            ///   `selectionStyle`（蓝玻璃是四角短弧框），浅色深色都成立。
            Widget modePill(String mode, String label,
                {required bool selected,
                required double flex,
                Widget Function(Color fg)? icon}) {
              final writable = climateWritable(n, mode);
              final fg = !writable
                  ? ink.withValues(alpha: .3)
                  : selected
                      ? s.accentText
                      : ink.withValues(alpha: .58);
              final onTap = !writable
                  ? null
                  : () => mode == 'power'
                      ? c.command('climate-power')
                      : c.command('climate-mode', value: mode);
              Widget content(Color color) => FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    if (icon != null) ...[
                      icon(color),
                      SizedBox(width: Design.dz(8))
                    ],
                    Text(label,
                        maxLines: 1,
                        softWrap: false,
                        style: TextStyle(
                            fontSize: Design.dz(15),
                            fontWeight:
                                selected ? FontWeight.w600 : FontWeight.w400,
                            color: color))
                  ]));
              if (!s.nocturne) {
                return Expanded(
                    flex: (flex * 100).round(),
                    child: Opacity(
                        opacity: writable ? 1 : .45,
                        child: ChoiceButton(
                            key: ValueKey('climate-mode-$mode'),
                            selected: selected,
                            onPressed: onTap,
                            kind: ChoiceKind.filled,
                            height: 48,
                            radius: 13,
                            padding: EdgeInsets.zero,
                            child: content(ChoiceButton.foregroundOf(
                                s, ChoiceKind.filled, selected)))));
              }
              return Expanded(
                  flex: (flex * 100).round(),
                  child: Semantics(
                      button: true,
                      selected: selected,
                      child: GestureDetector(
                          key: ValueKey('climate-mode-$mode'),
                          behavior: HitTestBehavior.opaque,
                          onTap: onTap,
                          child: Container(
                              height: Design.dz(48),
                              decoration: BoxDecoration(
                                  borderRadius:
                                      BorderRadius.circular(Design.dz(13)),
                                  color: selected
                                      ? null
                                      : ink.withValues(alpha: .06),
                                  border: selected
                                      ? null
                                      : Border.all(
                                          color: ink.withValues(alpha: .16)),
                                  // 稿子 `.cmode.on` 还有一层 accent 投影：
                                  // `0 8px 22px -8px rgba(var(--acc),.55)`。
                                  boxShadow: selected
                                      ? [
                                          BoxShadow(
                                              color: s.accent
                                                  .withValues(alpha: .55),
                                              offset: Offset(0, Design.dz(8)),
                                              blurRadius: Design.dz(22),
                                              spreadRadius: Design.dz(-8))
                                        ]
                                      : null,
                                  gradient: selected
                                      ? LinearGradient(
                                          begin: Alignment.topCenter,
                                          end: Alignment.bottomCenter,
                                          transform: GradientRotation(
                                              -10 * math.pi / 180),
                                          colors: [s.accentHi, s.accentLo])
                                      : null),
                              child: content(fg)))));
            }

            return SingleChildScrollView(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                  // 头部：标题 21 / 副标题 12.5 / 右上 36 圆形关闭。
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('空调与座椅',
                              style: TextStyle(
                                  fontSize: Design.dz(21),
                                  fontWeight: FontWeight.w500,
                                  color: ink.withValues(alpha: .92))),
                          if (demo) ...[
                            SizedBox(height: Design.dz(4)),
                            Text('操作预览 · 不控制车辆',
                                style: TextStyle(
                                    fontSize: Design.dz(12.5),
                                    color: ink.withValues(alpha: .42)))
                          ]
                        ]),
                    const Spacer(),
                    Tooltip(
                        message: '关闭空调',
                        child: Semantics(
                        button: true,
                        label: '关闭空调',
                        child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () => Navigator.pop(context),
                            child: Container(
                                width: Design.dz(36),
                                height: Design.dz(36),
                                decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: ink.withValues(alpha: .06),
                                    border: Border.all(
                                        color: ink.withValues(alpha: .09))),
                                child: Center(
                                    child: Icon(Icons.close,
                                        size: Design.dz(15),
                                        color:
                                            ink.withValues(alpha: .70)))))))
                  ]),
                  SizedBox(height: Design.dz(16)),
                  _caption(context, '温度与风量', top: 0),
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    for (final zone in ['left', 'fan', 'right']) ...[
                      if (zone != 'left') SizedBox(width: Design.dz(14)),
                      Expanded(
                          flex: zone == 'fan' ? 11 : 10,
                          child: zone == 'fan'
                              ? _fanCard(n, automatic, rememberedValue,
                                  valueLive, demo, ink, s, c)
                              : _tempCard(zone, rememberedValue, valueLive, ink,
                                  s, n, c))
                    ]
                  ]),
                  _caption(context, '空调模式', top: 16),
                  Row(children: [
                    modePill('ac', 'A/C 制冷',
                        selected: (demo ||
                                VehicleField.fromNative(n, 'ac').valid ||
                                climate.containsKey('ac')) &&
                            climate['ac'] == true,
                        flex: 1),
                    SizedBox(width: Design.dz(14)),
                    modePill('auto', 'AUTO',
                        selected: automatic, flex: 1),
                    SizedBox(width: Design.dz(14)),
                    Builder(builder: (context) {
                      final field = VehicleField.fromNative(n, 'recirc');
                      final recirc = demo
                          ? climate['recirc'] as bool?
                          : (field.valid
                              ? field.value as bool?
                              : climate['recirc'] as bool?);
                      return modePill('recirc',
                          recirc == null
                              ? '循环状态未知'
                              : recirc
                                  ? '内循环'
                                  : '外循环',
                          selected: recirc != null,
                          flex: 1.25,
                          icon: (fg) => CirculationIcon(
                              key: const ValueKey('climate-circulation-icon'),
                              recirculating: recirc,
                              color: fg,
                              size: Design.dz(20)));
                    }),
                    SizedBox(width: Design.dz(14)),
                    modePill('sync', 'SYNC 双区同步',
                        selected: climate['sync'] == true, flex: 1.1),
                    SizedBox(width: Design.dz(14)),
                    modePill('power', '电源',
                        selected: climate['power'] == true,
                        flex: .9,
                        icon: (fg) => UniIcon('power',
                            size: Design.dz(18), color: fg))
                  ]),
                  _caption(context, '座椅舒适', top: 16),
                  SeatControls(controller: c, native: n),
                  if (!demo && vehicleCommandLabel(n).isNotEmpty)
                    Padding(
                        padding: EdgeInsets.only(top: Design.dz(16)),
                        child: Text(vehicleCommandLabel(n),
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                fontSize: Design.dz(12),
                                color: ink.withValues(alpha: .42)))),
                ]));
          }));
}

Widget _caption(BuildContext context, String text, {double top = 16}) => Padding(
    padding: EdgeInsets.only(top: Design.dz(top), bottom: Design.dz(10)),
    child: Text(text,
        style: TextStyle(
            fontSize: Design.dz(12.5),
            letterSpacing: Design.dz(1),
            color: SurfaceStyle.of(context).muted)));

/// 主驾 / 副驾温度卡：42 加减键夹一个 40/200 的大数字，下面一根冷热渐变条。
Widget _tempCard(String zone, String Function(String) value,
    bool Function(String) live, Color ink, SurfaceStyle s, Map<String, dynamic> n,
    LauncherController c) {
  final title = zone == 'left' ? '主驾温度' : '副驾温度';
  final raw = value(zone);
  final temp = double.tryParse(raw.replaceAll('°', ''));
  // 16–32°C 映射到 0–1；读不到时停在 46%，与设计稿的旋钮位置一致。
  final pos = temp == null ? .46 : ((temp - 16) / 16).clamp(0.0, 1.0);
  return KeyedSubtree(
      key: ValueKey('climate-card-$zone'),
      child: SpecPanel(
      padding: EdgeInsets.fromLTRB(
          Design.dz(16), Design.dz(14), Design.dz(16), Design.dz(15)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title,
            style: TextStyle(
                fontSize: Design.dz(12.5),
                color: ink.withValues(alpha: .42))),
        SizedBox(height: Design.dz(8)),
        // 与风量卡那 44 高的虚线圆环同高，三张卡的中线才对得齐。
        SizedBox(
            height: Design.dz(44),
            child: Row(children: [
          SpecStepButton(
              icon: Icons.remove,
              label: '降低$title',
              onTap: climateWritable(n, zone)
                  ? () => c.command('temp-down', zone: zone)
                  : null),
          Expanded(
              child: Center(
                  child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text('$raw°',
                          maxLines: 1,
                          softWrap: false,
                          style: TextStyle(
                              fontSize: Design.dz(40),
                              height: 1.0,
                              fontWeight: FontWeight.w200,
                              letterSpacing: Design.dz(-.8),
                              color: live(zone)
                                  ? ink.withValues(alpha: .95)
                                  : ink.withValues(alpha: .3)))))),
          SpecStepButton(
              icon: Icons.add,
              label: '提高$title',
              onTap: climateWritable(n, zone)
                  ? () => c.command('temp-up', zone: zone)
                  : null)
        ])),
        SizedBox(height: Design.dz(10)),
        Row(children: [
          Icon(Icons.ac_unit,
              size: Design.dz(11), color: const Color(0xFF6FD3FF).withValues(alpha: .6)),
          SizedBox(width: Design.dz(8)),
          Expanded(child: _TempBar(position: pos)),
          SizedBox(width: Design.dz(8)),
          Icon(Icons.wb_sunny_outlined,
              size: Design.dz(11),
              color: const Color(0xFFFFB057).withValues(alpha: .65))
        ])
      ])));
}

/// 冷热渐变条：4 高，左侧冷蓝、右侧暖橙，中间过渡到墨色，旋钮 9 见方。
class _TempBar extends StatelessWidget {
  final double position;
  const _TempBar({required this.position});
  @override
  Widget build(BuildContext context) {
    final ink = SurfaceStyle.of(context).text;
    return LayoutBuilder(builder: (context, box) {
      final w = box.maxWidth;
      return SizedBox(
          height: Design.dz(11),
          child: Stack(clipBehavior: Clip.none, children: [
            Positioned(
                left: 0,
                right: 0,
                top: Design.dz(3.5),
                child: Container(
                    height: Design.dz(4),
                    decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(Design.dz(2)),
                        gradient: LinearGradient(colors: [
                          const Color(0xFF6FD3FF).withValues(alpha: .55),
                          ink.withValues(alpha: .08),
                          ink.withValues(alpha: .08),
                          const Color(0xFFFFB057).withValues(alpha: .60)
                        ], stops: const [
                          0,
                          .45,
                          .55,
                          1
                        ])))),
            Positioned(
                left: (w * position - Design.dz(4.5))
                    .clamp(0.0, math.max(0, w - Design.dz(9))),
                top: 0,
                child: Container(
                    width: Design.dz(9),
                    height: Design.dz(11),
                    alignment: Alignment.center,
                    child: Container(
                        width: Design.dz(9),
                        height: Design.dz(9),
                        decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: ink,
                            boxShadow: [
                              BoxShadow(
                                  color: ink.withValues(alpha: .45),
                                  blurRadius: Design.dz(8))
                            ]))))
          ]));
    });
  }
}

/// 风量卡：虚线圆环里一枚风扇 + AUTO/档位，下面七段刻度。
Widget _fanCard(Map<String, dynamic> n, bool automatic,
    String Function(String) value, bool Function(String) live, bool demo,
    Color ink, SurfaceStyle s, LauncherController c) {
  // 稿子里七段刻度的透明度就是这一串，最后一段 100%。
  const steps = [.14, .24, .36, .50, .66, .82, 1.0];
  final writable = climateWritable(n, 'fan');
  final level = automatic ? 7 : (int.tryParse(value('fan')) ?? 0);
  return KeyedSubtree(
      key: const ValueKey('climate-card-fan'),
      child: SpecPanel(
      padding: EdgeInsets.fromLTRB(
          Design.dz(16), Design.dz(14), Design.dz(16), Design.dz(15)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('风量',
            style: TextStyle(
                fontSize: Design.dz(12.5), color: ink.withValues(alpha: .42))),
        SizedBox(height: Design.dz(8)),
        Row(children: [
          SpecStepButton(
              icon: Icons.remove,
              label: '降低风量',
              onTap: writable ? () => c.command('fan-down') : null),
          Expanded(
              child: Center(
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
            CustomPaint(
                painter: _DashedCircle(s.accent.withValues(alpha: .40)),
                child: SizedBox(
                    width: Design.dz(44),
                    height: Design.dz(44),
                    child: Center(
                        child: UniIcon('fan',
                            key: const ValueKey('climate-fan-icon'),
                            size: Design.dz(32),
                            color: s.accent)))),
            SizedBox(width: Design.dz(10)),
            FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(automatic ? 'AUTO' : value('fan'),
                    key: const ValueKey('climate-fan-value'),
                    maxLines: 1,
                    softWrap: false,
                    style: TextStyle(
                        fontSize: Design.dz(28),
                        fontWeight: FontWeight.w300,
                        letterSpacing: Design.dz(1.1),
                        color: automatic || live('fan')
                            ? ink.withValues(alpha: .92)
                            : ink.withValues(alpha: .3))))
          ]))),
          SpecStepButton(
              icon: Icons.add,
              label: '提高风量',
              onTap: writable ? () => c.command('fan-up') : null)
        ]),
        SizedBox(height: Design.dz(10)),
        Row(children: [
          for (int i = 0; i < 7; i++) ...[
            if (i > 0) SizedBox(width: Design.dz(5)),
            Expanded(
                child: Container(
                    height: Design.dz(3),
                    decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(Design.dz(2)),
                        color: s.accent.withValues(
                            alpha: i < level ? steps[i] : .14)))),
          ],
          SizedBox(width: Design.dz(6)),
          Text('1-7 档',
              maxLines: 1,
              softWrap: false,
              style: TextStyle(
                  fontSize: Design.dz(10.5),
                  height: 1.0,
                  letterSpacing: Design.dz(.6),
                  color: s.accent.withValues(alpha: .75)))
        ])
      ])));
}

/// 风量卡里的虚线圆环（设计稿 `border:1px dashed` 的等价物）。
class _DashedCircle extends CustomPainter {
  final Color color;
  const _DashedCircle(this.color);
  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero),
        radius = size.width / 2 - .5;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = color;
    const segments = 26;
    for (int i = 0; i < segments; i++) {
      final start = i * 2 * math.pi / segments;
      canvas.drawArc(Rect.fromCircle(center: center, radius: radius), start,
          math.pi / segments * .85, false, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _DashedCircle old) => old.color != color;
}

