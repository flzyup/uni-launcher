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
    final automatic = demo
        ? climate['auto'] == true
        : autoField.valid && autoField.value == true;
    final fan = demo
        ? '${climate['fan'] ?? '—'}'
        : VehicleField.fromNative(native, 'fan').display(decimals: 0);
    final content = automatic
        ? Column(mainAxisSize: MainAxisSize.min, children: [
            UniIcon('fan', size: Design.px(23 * scale), color: s.accent),
            Text('AUTO',
                key: const ValueKey('dock-fan-auto'),
                style: TextStyle(
                    fontSize: Design.px(12 * scale),
                    fontWeight: FontWeight.w600,
                    color: s.accent)),
          ])
        : Row(mainAxisSize: MainAxisSize.min, children: [
            UniIcon('fan', size: Design.px(23 * scale), color: s.text),
            SizedBox(width: Design.px(4)),
            Text(fan,
                key: const ValueKey('dock-fan-level'),
                style:
                    TextStyle(fontSize: Design.px(18 * scale), color: s.text)),
          ]);
    return IconAction(
        key: const ValueKey('climate'),
        icon: Icons.air,
        label: '空调与座椅，${automatic ? '自动风量' : '风量 $fan 档'}',
        size: Design.px(56),
        active: !s.technicalFrame,
        onTap: () => showClimatePanel(context, controller),
        child: FittedBox(fit: BoxFit.scaleDown, child: content));
  }
}
