import 'package:flutter/material.dart';
import '../controller/launcher_controller.dart';
import '../model/vehicle_data.dart';
import '../theme/design_tokens.dart';
import '../theme/launcher_theme.dart';
import 'glass_surface.dart';

/// Read-only view of already collected OEM fields; no extra vehicle calls.
class TireDiagnostics extends StatelessWidget {
  final LauncherController controller;
  const TireDiagnostics({super.key, required this.controller});
  static const wheels = [
    ('pressureFrontLeft', '左前'),
    ('pressureFrontRight', '右前'),
    ('pressureRearLeft', '左后'),
    ('pressureRearRight', '右后')
  ];
  @override
  Widget build(BuildContext context) =>
      ValueListenableBuilder<Map<String, dynamic>>(
          valueListenable: controller.native,
          builder: (context, native, _) {
            final s = SurfaceStyle.of(context);
            final vehicle =
                native['vehicle'] is Map ? native['vehicle'] as Map : const {};
            final fields =
                vehicle['fields'] is Map ? vehicle['fields'] as Map : const {};
            return GlassSurface(
              child: ExpansionTile(
                key: const ValueKey('tire-diagnostics'),
                title: const Text('胎压数据诊断'),
                subtitle: const Text('对照原车胎压，查看四轮数据来源'),
                children: [
                  for (final (key, label) in wheels)
                    Builder(builder: (context) {
                      final raw =
                          fields[key] is Map ? fields[key] as Map : const {};
                      final value = VehicleField.fromNative(native, key);
                      final source = raw['source']?.toString() ?? '';
                      final reason = raw['reason']?.toString() ?? '';
                      final sample = raw['raw']?.toString() ?? '—';
                      return ListTile(
                        key: ValueKey('tire-diagnostic-$key'),
                        title: Text(
                            '$label  ${value.display(decimals: 2)}${value.valid ? ' ${value.unit}' : ''}'),
                        subtitle: Text(
                            '原始值 $sample · ${source.isEmpty ? '来源未知' : source}${!value.valid && reason.isNotEmpty ? ' · $reason' : ''}',
                            style: TextStyle(
                                color: s.muted, fontSize: Design.px(16))),
                      );
                    }),
                ],
              ),
            );
          });
}
