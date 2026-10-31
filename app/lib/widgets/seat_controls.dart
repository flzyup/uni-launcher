import 'package:flutter/material.dart';
import '../controller/launcher_controller.dart';
import '../model/seat_control.dart';
import '../theme/design_tokens.dart';
import '../theme/launcher_theme.dart';
import 'uni_icon.dart';
import 'glass_surface.dart';

/// Seat climate cards per the latest climate-redesign spec:
/// driver uses one seven-step band (vent 3/2/1, off, heat 1/2/3) and the
/// passenger card uses four equal steps (off, heat 1/2/3).
class SeatControls extends StatelessWidget {
  final LauncherController controller;
  final Map<String, dynamic> native;
  const SeatControls(
      {super.key, required this.controller, required this.native});

  static const _ventColor = Color(0xFF64C8FF);
  static const _heatColor = Color(0xFFFFB25C);

  @override
  Widget build(BuildContext context) {
    final driverHeat = SeatControlState.fromNative(native, 'driverHeat');
    final driverVent = SeatControlState.fromNative(native, 'driverVent');
    final passengerHeat = SeatControlState.fromNative(native, 'passengerHeat');
    return Row(children: [
      Expanded(
          flex: 122,
          child: _SeatCard(
              key: const ValueKey('seat-driver-card'),
              title: '主驾',
              unknown: [
                if (driverVent.level == null) 'driverVent',
                if (driverHeat.level == null) 'driverHeat'
              ],
              titleIcon: _seatIcon('climate-seat-vent',
                  active: (driverVent.level ?? 0) > 0, color: _ventColor),
              trailingIcon: _seatIcon('climate-seat-heat',
                  active: (driverHeat.level ?? 0) > 0, color: _heatColor),
              writable: driverHeat.writable || driverVent.writable,
              steps: [
                _SeatStep(
                    key: const ValueKey('seat-driverVent-3'),
                    enabled: driverVent.writable,
                    label: '3',
                    selected: driverVent.level == 3,
                    color: _ventColor,
                    onTap: () => controller.command('seat-vent',
                        zone: 'left', value: '3')),
                _SeatStep(
                    key: const ValueKey('seat-driverVent-2'),
                    enabled: driverVent.writable,
                    label: '2',
                    selected: driverVent.level == 2,
                    color: _ventColor,
                    onTap: () => controller.command('seat-vent',
                        zone: 'left', value: '2')),
                _SeatStep(
                    key: const ValueKey('seat-driverVent-1'),
                    enabled: driverVent.writable,
                    label: '1',
                    selected: driverVent.level == 1,
                    color: _ventColor,
                    onTap: () => controller.command('seat-vent',
                        zone: 'left', value: '1')),
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
                _SeatStep(
                    key: const ValueKey('seat-driverHeat-1'),
                    enabled: driverHeat.writable,
                    label: '1',
                    selected: driverHeat.level == 1,
                    color: _heatColor,
                    onTap: () => controller.command('seat-heat',
                        zone: 'left', value: '1')),
                _SeatStep(
                    key: const ValueKey('seat-driverHeat-2'),
                    enabled: driverHeat.writable,
                    label: '2',
                    selected: driverHeat.level == 2,
                    color: _heatColor,
                    onTap: () => controller.command('seat-heat',
                        zone: 'left', value: '2')),
                _SeatStep(
                    key: const ValueKey('seat-driverHeat-3'),
                    enabled: driverHeat.writable,
                    label: '3',
                    selected: driverHeat.level == 3,
                    color: _heatColor,
                    onTap: () => controller.command('seat-heat',
                        zone: 'left', value: '3')),
              ])),
      SizedBox(width: Design.px(24)),
      Expanded(
          flex: 100,
          child: _SeatCard(
              key: const ValueKey('seat-passenger-card'),
              title: '副驾',
              unknown: [if (passengerHeat.level == null) 'passengerHeat'],
              trailingIcon: _seatIcon('climate-seat-heat',
                  active: (passengerHeat.level ?? 0) > 0, color: _heatColor),
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
              ]))
    ]);
  }

  Widget _seatIcon(String id, {required bool active, required Color color}) =>
      UniIcon(id,
          size: Design.px(32),
          color: active ? color : color.withValues(alpha: .38));
}

class _SeatCard extends StatelessWidget {
  final String title;
  final Widget? titleIcon, trailingIcon;
  final bool writable;
  final List<String> unknown;
  final List<_SeatStep> steps;
  const _SeatCard(
      {super.key,
      required this.title,
      required this.writable,
      required this.steps,
      this.unknown = const [],
      this.titleIcon,
      this.trailingIcon});
  @override
  Widget build(BuildContext context) {
    final s = SurfaceStyle.of(context);
    return GlassSurface(
        padding: EdgeInsets.all(Design.px(18)),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Row(children: [
            Text(title,
                style: TextStyle(
                    fontSize: Design.px(23), fontWeight: FontWeight.w500)),
            if (titleIcon != null) ...[
              SizedBox(width: Design.px(10)),
              titleIcon!
            ],
            for (final key in unknown)
              Padding(
                  padding: EdgeInsets.only(left: Design.px(5)),
                  child: Text('—',
                      key: ValueKey('seat-unknown-$key'),
                      style: TextStyle(color: s.muted))),
            const Spacer(),
            if (trailingIcon != null) trailingIcon!
          ]),
          SizedBox(height: Design.px(24)),
          Row(children: [
            for (final (index, step) in steps.indexed)
              Expanded(
                  child: Padding(
                      padding:
                          EdgeInsets.only(left: index == 0 ? 0 : Design.px(8)),
                      child: SizedBox(
                          height: Design.px(60),
                          child: Semantics(
                              selected: step.selected,
                              child: DecoratedBox(
                                  position: DecorationPosition.foreground,
                                  decoration: const BoxDecoration(),
                                  child: OutlinedButton(
                                      key: step.key,
                                      style: s
                                          .weakSelectionStyle(step.selected)
                                          .copyWith(
                                              backgroundColor: WidgetStatePropertyAll(
                                                  step.color == null
                                                      ? (step.selected
                                                          ? s.accent.withValues(
                                                              alpha: .18)
                                                          : s.soft)
                                                      : step.color!.withValues(
                                                          alpha: step.selected
                                                              ? .29
                                                              : .12)),
                                              side: WidgetStatePropertyAll(BorderSide(
                                                  color: (step.color ?? s.accent)
                                                      .withValues(
                                                          alpha: step.selected
                                                              ? .7
                                                              : .24))),
                                              padding: const WidgetStatePropertyAll(EdgeInsets.zero),
                                              foregroundColor: WidgetStateProperty.resolveWith((states) => states.contains(WidgetState.disabled)
                                                  ? s.disabled
                                                  : step.selected
                                                      ? (step.color ?? s.accent)
                                                      : s.muted)),
                                      onPressed: writable && step.enabled ? step.onTap : null,
                                      child: Text(step.label, style: TextStyle(fontSize: Design.px(22), fontWeight: step.selected ? FontWeight.w600 : FontWeight.w400))))))))
          ])
        ]));
  }
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
