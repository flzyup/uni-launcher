import 'package:flutter/material.dart';
import '../controller/launcher_controller.dart';
import '../theme/design_tokens.dart';
import '../theme/launcher_theme.dart';
import 'glass_surface.dart';

/// Raw candidate values are read only and intentionally do not imply door state.
class BodyDiagnostics extends StatelessWidget {
  final LauncherController controller;
  const BodyDiagnostics({super.key, required this.controller});
  static const labels = {
    'driver': '驾驶员前门',
    'driverRear': '驾驶员后门',
    'passenger': '乘客前门',
    'passengerRear': '乘客后门',
    'trunk': '尾门',
  };

  @override
  Widget build(BuildContext context) =>
      ValueListenableBuilder<Map<String, dynamic>>(
          valueListenable: controller.native,
          builder: (context, native, _) {
            final s = SurfaceStyle.of(context);
            final vehicle =
                native['vehicle'] is Map ? native['vehicle'] as Map : const {};
            final probe = vehicle['bodyProbe'] is Map
                ? vehicle['bodyProbe'] as Map
                : const {};
            final observed = probe['observedAtMs'];
            final age = observed is num
                ? DateTime.now().millisecondsSinceEpoch - observed.toInt()
                : -1;
            final fresh =
                vehicle['connected'] == true && age >= -1000 && age <= 10000;
            final values = probe['properties'] is List
                ? probe['properties'] as List
                : const [];
            return GlassSurface(
                child: ExpansionTile(
              key: const ValueKey('body-diagnostics'),
              title: const Text('车门数据诊断'),
              subtitle: const Text('只读原始值，开关含义待实车核对'),
              children: [
                for (final entry in labels.entries)
                  Builder(builder: (context) {
                    final candidates = values
                        .whereType<Map>()
                        .where((v) => v['name'] == entry.key);
                    final sample =
                        candidates.isEmpty ? const {} : candidates.first;
                    final active = fresh && sample['active'] == true;
                    final raw = active ? '${sample['raw'] ?? '—'}' : '—';
                    final reason = !fresh
                        ? '等待数据'
                        : '${sample['reason'] ?? (active ? '待核对' : '不可用')}';
                    return ListTile(
                        key: ValueKey('body-diagnostic-${entry.key}'),
                        title: Text('${entry.value}  原始值 $raw'),
                        subtitle: Text(reason,
                            style: TextStyle(
                                color: s.muted, fontSize: Design.px(16))));
                  }),
              ],
            ));
          });
}
