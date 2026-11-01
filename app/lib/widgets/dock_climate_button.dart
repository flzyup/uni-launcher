import 'package:flutter/material.dart';
import '../controller/launcher_controller.dart';
import '../model/vehicle_data.dart';
import '../theme/design_tokens.dart';
import '../theme/launcher_theme.dart';
import 'climate_panel.dart';
import 'glass_surface.dart';
import 'uni_icon.dart';

class DockClimateButton extends StatelessWidget {
  final LauncherController controller;
  final Map<String, dynamic> native;
  final double scale;
  const DockClimateButton({
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
    final fanRaw = demo ? climate['fan'] : fanField.value;
    final fanKnown = demo || fanField.valid;
    final fanText = fanKnown ? '$fanRaw' : '—';
    final fanLevel = fanKnown ? int.tryParse(fanText) ?? 0 : 0;
    final content = automatic
        ? Text('AUTO',
            key: const ValueKey('dock-fan-auto'),
            style: TextStyle(
                fontSize: Design.px(18 * scale),
                fontWeight: FontWeight.w700,
                letterSpacing: Design.px(1 * scale),
                color: s.accent))
        : Column(mainAxisSize: MainAxisSize.min, children: [
            UniIcon('fan',
                size: Design.px(23 * scale),
                color: fanKnown ? s.accent : s.muted),
            SizedBox(height: Design.px(4 * scale)),
            _FanLevelIndicator(
                active: fanLevel.clamp(0, 7).toInt(),
                enabled: fanKnown,
                scale: scale,
                color: s.accent,
                inactive: s.edge)
          ]);
    return IconAction(
        key: const ValueKey('climate'),
        icon: Icons.air,
        label:
            '空调与座椅，${automatic ? "自动风量" : "风量 ${fanKnown ? "$fanLevel" : "未知"} 档"}',
        size: Design.px(72),
        active: false,
        framed: false,
        onTap: () => showClimatePanel(context, controller),
        child: FittedBox(fit: BoxFit.scaleDown, child: content));
  }
}

class _FanLevelIndicator extends StatelessWidget {
  final int active;
  final bool enabled;
  final double scale;
  final Color color;
  final Color inactive;
  const _FanLevelIndicator({
    required this.active,
    required this.enabled,
    required this.scale,
    required this.color,
    required this.inactive,
  });

  @override
  Widget build(BuildContext context) {
    final segments = <Widget>[];
    for (var index = 1; index <= 7; index++) {
      segments.add(Padding(
          key: ValueKey('dock-fan-segment-$index'),
          padding: EdgeInsets.only(right: index == 7 ? 0 : 4 * scale),
          child: Transform.rotate(
              angle: -0.55,
              child: Container(
                  width: 3 * scale,
                  height: 7 * scale,
                  decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(scale),
                      color: enabled && index <= active ? color : inactive)))));
    }
    return Row(mainAxisSize: MainAxisSize.min, children: segments);
  }
}
