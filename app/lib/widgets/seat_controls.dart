import 'dart:math' as math;

import 'package:flutter/material.dart';
import '../controller/launcher_controller.dart';
import '../model/seat_control.dart';
import '../theme/design_tokens.dart';
import '../theme/launcher_theme.dart';
import 'choice_button.dart';
import 'oem_climate_icon.dart';
import 'spec_panel.dart';

/// 设计稿 `.sg`：44 高、圆角 12、15px；通风是青色系（`.b`）、加热是橙色系
/// （`.h`）、中性「关」是墨色系；选中态换成实色渐变 + 深色字。
///
/// 主驾一条七档（通风 3/2/1、关、加热 1/2/3），副驾四条（关、加热 1/2/3）。
class SeatControls extends StatelessWidget {
  final LauncherController controller;
  final Map<String, dynamic> native;
  const SeatControls(
      {super.key, required this.controller, required this.native});

  static const _ventColor = Color(0xFF64C8FF);
  static const _heatColor = Color(0xFFFFB25C);
  // 稿子 `.sg.b.on / .sg.h.on` 的渐变上下端与深色字，不是简单压暗。
  static const _ventDeep = Color(0xFF3D9BE0);
  static const _heatDeep = Color(0xFFE8933A);
  static const _ventInk = Color(0xFF04121E);
  static const _heatInk = Color(0xFF1F1104);

  @override
  Widget build(BuildContext context) {
    final driverHeat = SeatControlState.fromNative(native, 'driverHeat');
    final driverVent = SeatControlState.fromNative(native, 'driverVent');
    final passengerHeat = SeatControlState.fromNative(native, 'passengerHeat');
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Expanded(
          flex: 122,
          child: _SeatCard(
              key: const ValueKey('seat-driver-card'),
              title: '主驾',
              leadingChip: true,
              unknown: [
                if (driverVent.level == null) 'driverVent',
                if (driverHeat.level == null) 'driverHeat'
              ],
              chips: [
                _SeatChip(
                    icon: OemSeatIcon(
                        ventilation: true,
                        level: driverVent.level,
                        color: _ventColor,
                        size: Design.dz(22)),
                    color: _ventColor,
                    label: driverVent.level == null
                        ? '通风 · —'
                        : (driverVent.level == 0
                            ? '通风 · 关'
                            : '通风 · ${driverVent.level}')),
                _SeatChip(
                    icon: OemSeatIcon(
                        level: driverHeat.level,
                        color: _heatColor,
                        size: Design.dz(22)),
                    color: _heatColor,
                    label: driverHeat.level == null
                        ? '加热 · —'
                        : (driverHeat.level == 0
                            ? '加热 · 关'
                            : '加热 · ${driverHeat.level}')),
              ],
              writable: driverHeat.writable || driverVent.writable,
              steps: [
                for (final level in [3, 2, 1])
                  _SeatStep(
                      key: ValueKey('seat-driverVent-$level'),
                      enabled: driverVent.writable,
                      label: '$level',
                      selected: driverVent.level == level,
                      color: _ventColor,
                      onTap: () => controller.command('seat-vent',
                          zone: 'left', value: '$level')),
                _SeatStep(
                    key: const ValueKey('seat-driver-off'),
                    enabled: (driverHeat.level != null &&
                            driverHeat.level! > 0 &&
                            driverHeat.writable) ||
                        (driverVent.level != null &&
                            driverVent.level! > 0 &&
                            driverVent.writable),
                    label: '关',
                    selected: driverHeat.level == 0 && driverVent.level == 0,
                    onTap: () {
                      if ((driverHeat.level ?? 0) > 0) {
                        controller.command('seat-heat',
                            zone: 'left', value: '0');
                      } else if ((driverVent.level ?? 0) > 0) {
                        controller.command('seat-vent',
                            zone: 'left', value: '0');
                      }
                    }),
                for (final level in [1, 2, 3])
                  _SeatStep(
                      key: ValueKey('seat-driverHeat-$level'),
                      enabled: driverHeat.writable,
                      label: '$level',
                      selected: driverHeat.level == level,
                      color: _heatColor,
                      onTap: () => controller.command('seat-heat',
                          zone: 'left', value: '$level')),
              ],
              footer: const [
                _SeatFooter(label: '‹ 通风', flex: 3, color: _ventColor),
                Spacer(flex: 1),
                _SeatFooter(label: '加热 ›', flex: 3, color: _heatColor),
              ])),
      SizedBox(width: Design.dz(14)),
      Expanded(
          flex: 100,
          child: _SeatCard(
              key: const ValueKey('seat-passenger-card'),
              title: '副驾',
              unknown: [if (passengerHeat.level == null) 'passengerHeat'],
              chips: [
                _SeatChip(
                    icon: OemSeatIcon(
                        passenger: true,
                        level: passengerHeat.level,
                        color: _heatColor,
                        size: Design.dz(22)),
                    color: _heatColor,
                    label: passengerHeat.level == null
                        ? '加热 · —'
                        : (passengerHeat.level == 0
                            ? '加热 · 关'
                            : '加热 · ${passengerHeat.level}')),
              ],
              writable: passengerHeat.writable,
              steps: [
                _SeatStep(
                    key: const ValueKey('seat-passengerHeat-0'),
                    label: '关',
                    selected: passengerHeat.level == 0,
                    onTap: () => controller.command('seat-heat',
                        zone: 'right', value: '0')),
                for (final level in [1, 2, 3])
                  _SeatStep(
                      key: ValueKey('seat-passengerHeat-$level'),
                      label: '$level',
                      selected: passengerHeat.level == level,
                      color: _heatColor,
                      onTap: () => controller.command('seat-heat',
                          zone: 'right', value: '$level')),
              ],
              footer: const [
                Spacer(flex: 1),
                _SeatFooter(label: '加热 ›', flex: 3, color: _heatColor),
              ]))
    ]);
  }
}

/// 标题右侧那枚「通风 · 关」小标签：7% 同色底 + 22% 描边 + 11.5 字号。
class _SeatChip extends StatelessWidget {
  final Widget icon;
  final String label;
  final Color color;
  const _SeatChip(
      {required this.icon, required this.label, required this.color});
  @override
  Widget build(BuildContext context) => Container(
      padding: EdgeInsets.fromLTRB(
          Design.dz(6), Design.dz(3), Design.dz(9), Design.dz(3)),
      decoration: BoxDecoration(
          color: color.withValues(alpha: .07),
          border: Border.all(color: color.withValues(alpha: .22)),
          borderRadius: BorderRadius.circular(Design.dz(9))),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        icon,
        SizedBox(width: Design.dz(5)),
        Text(label,
            style: TextStyle(
                fontSize: Design.dz(11.5), color: color.withValues(alpha: .85)))
      ]));
}

class _SeatCard extends StatelessWidget {
  final String title;
  final List<_SeatChip> chips;
  final List<String> unknown;
  final bool writable;

  /// 稿子里主驾的「通风」标签紧跟车名，其余（主驾的加热、副驾的加热）都靠右。
  final bool leadingChip;
  final List<_SeatStep> steps;
  final List<Widget> footer;
  const _SeatCard(
      {super.key,
      required this.title,
      required this.writable,
      required this.steps,
      required this.footer,
      this.chips = const [],
      this.unknown = const [],
      this.leadingChip = false});
  @override
  Widget build(BuildContext context) {
    final s = SurfaceStyle.of(context), ink = s.text;
    return SpecPanel(
        padding: EdgeInsets.fromLTRB(
            Design.dz(16), Design.dz(14), Design.dz(16), Design.dz(16)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Text(title,
                style: TextStyle(
                    fontSize: Design.dz(14.5),
                    color: ink.withValues(alpha: .85))),
            // 读不到车辆状态时在名字后面点一个破折号，与稿子的空值一致。
            for (final key in unknown)
              Padding(
                  padding: EdgeInsets.only(left: Design.dz(6)),
                  child: Text('—',
                      key: ValueKey('seat-unknown-$key'),
                      style: TextStyle(
                          fontSize: Design.dz(13),
                          color: ink.withValues(alpha: .35)))),
            // 稿子里第一枚标签紧跟车名（左），其余靠右（主驾的「加热」）。
            if (leadingChip && chips.isNotEmpty) ...[
              SizedBox(width: Design.dz(12)),
              chips.first
            ],
            const Spacer(),
            for (final (i, chip) in (leadingChip ? chips.skip(1) : chips)
                .indexed) ...[if (i > 0) SizedBox(width: Design.dz(8)), chip]
          ]),
          SizedBox(height: Design.dz(12)),
          Row(children: [
            for (final (index, step) in steps.indexed)
              Expanded(
                  child: Padding(
                      padding:
                          EdgeInsets.only(left: index == 0 ? 0 : Design.dz(8)),
                      child: SizedBox(
                          height: Design.dz(44), child: _step(step, s, ink))))
          ]),
          SizedBox(height: Design.dz(7)),
          Row(children: footer)
        ]));
  }

  /// `.sg` 的选中/未选中两套底：选中是实色渐变 + 深字，未选中是同色 4% 底 +
  /// 35% 描边 + 同色 75% 字。按钮本体仍用 [OutlinedButton]，方便读屏和测试
  /// 直接读 `onPressed`。
  Widget _step(_SeatStep step, SurfaceStyle s, Color ink) {
    final accent = step.color;
    final on = step.selected;
    final radius = BorderRadius.circular(s.controlRadius);
    // 经典 / 蓝玻璃没有「通风青」「加热橙」这套档位色，交给统一的选择控件，
    // 选中态由皮肤自己给（蓝玻璃是四角短弧框），与同页的空调模式一致。
    if (!s.nocturne) {
      return ChoiceButton(
          key: step.key,
          selected: on,
          onPressed: writable && step.enabled ? step.onTap : null,
          kind: ChoiceKind.filled,
          height: 44,
          radius: 12,
          padding: EdgeInsets.zero,
          child: Text(step.label, style: TextStyle(fontSize: Design.dz(15))));
    }
    final deep = accent == SeatControls._ventColor
        ? SeatControls._ventDeep
        : accent == SeatControls._heatColor
            ? SeatControls._heatDeep
            : accent == null
                ? null
                : Color.lerp(accent, Colors.black, .16);
    final onInk = accent == SeatControls._ventColor
        ? SeatControls._ventInk
        : SeatControls._heatInk;
    final List<Color>? gradient =
        on && accent != null ? [accent, deep ?? accent] : null;
    final foreground = !step.enabled || !writable
        ? ink.withValues(alpha: .22)
        : on
            ? (accent != null ? onInk : s.accent)
            : accent?.withValues(
                    alpha: accent == SeatControls._ventColor ? .75 : .8) ??
                ink.withValues(alpha: .6);
    return DecoratedBox(
        decoration: BoxDecoration(
            borderRadius: radius,
            color: gradient != null
                ? null
                : on
                    ? s.accent.withValues(alpha: .10)
                    : accent?.withValues(alpha: .04) ??
                        ink.withValues(alpha: .02),
            gradient: gradient == null
                ? null
                : LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    transform: GradientRotation(-10 * math.pi / 180),
                    colors: gradient),
            // 稿子选中档还有一层同色投影：`0 6px 16px -8px rgba(...,.55)`。
            boxShadow: gradient == null
                ? null
                : [
                    BoxShadow(
                        color: accent!.withValues(alpha: .55),
                        offset: Offset(0, Design.dz(6)),
                        blurRadius: Design.dz(16),
                        spreadRadius: Design.dz(-8))
                  ],
            border: Border.all(
                color: gradient != null
                    ? Colors.transparent
                    : on
                        ? s.accent.withValues(alpha: .55)
                        : accent?.withValues(alpha: .35) ??
                            ink.withValues(alpha: .08))),
        child: OutlinedButton(
            key: step.key,
            onPressed: writable && step.enabled ? step.onTap : null,
            style: OutlinedButton.styleFrom(
                backgroundColor: Colors.transparent,
                disabledBackgroundColor: Colors.transparent,
                side: BorderSide.none,
                padding: EdgeInsets.zero,
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                shape: RoundedRectangleBorder(borderRadius: radius),
                foregroundColor: foreground,
                disabledForegroundColor: foreground),
            child: Text(step.label,
                style: TextStyle(
                    fontSize: Design.dz(15),
                    fontWeight: on && gradient != null
                        ? FontWeight.w600
                        : on
                            ? FontWeight.w500
                            : FontWeight.w400))));
  }
}

class _SeatFooter extends StatelessWidget {
  final String label;
  final int flex;
  final Color color;
  const _SeatFooter(
      {required this.label, required this.flex, required this.color});
  @override
  Widget build(BuildContext context) => Expanded(
      flex: flex,
      child: Text(label,
          textAlign: TextAlign.center,
          style: TextStyle(
              fontSize: Design.dz(10.5),
              letterSpacing: Design.dz(1.05),
              color: color.withValues(alpha: .55))));
}

class _SeatStep {
  final Key? key;
  final String label;
  final bool selected;
  final bool enabled;
  final Color? color;
  final VoidCallback onTap;
  const _SeatStep(
      {this.key,
      required this.label,
      required this.selected,
      required this.onTap,
      this.enabled = true,
      this.color});
}
