import 'package:flutter/material.dart';
import '../controller/launcher_controller.dart';
import '../theme/design_tokens.dart';
import '../theme/launcher_theme.dart';
import 'choice_button.dart';
import 'native_slice_builder.dart';
import 'setting_block.dart';

class SimulationSettings extends StatelessWidget {
  final LauncherController controller;
  const SimulationSettings({super.key, required this.controller});
  @override
  Widget build(BuildContext context) => NativeSliceBuilder(
      valueListenable: controller.native,
      select: (n) => [n['simulation'], n['simulationMode'], n['demo']],
      builder: (context, native) {
        final info = native['simulation'] is Map
            ? native['simulation'] as Map
            : const {};
        if (info['supported'] != true) return const SizedBox.shrink();
        final mode = native['simulationMode'] ??
            (native['demo'] == true ? 'demo' : 'live');
        final s = SurfaceStyle.of(context);
        return Padding(
            padding: EdgeInsets.only(bottom: Design.dz(12)),
            child: SettingBlock(
                title: '模拟器运行模式',
                note: '高保真：车辆模拟，音乐与红绿灯使用真实应用数据。',
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(children: [
                        for (final item in const [
                          ('live', '真实模式'),
                          ('demo', '演示模式'),
                          ('highFidelity', '高保真模式')
                        ]) ...[
                          if (item.$1 != 'live') SizedBox(width: Design.dz(8)),
                          Expanded(
                              child: ChoiceButton(
                                  key: ValueKey('simulation-${item.$1}'),
                                  selected: mode == item.$1,
                                  onPressed: () => controller.command(
                                      'simulation-mode',
                                      value: item.$1),
                                  child: Text(item.$2)))
                        ]
                      ]),
                      if (mode == 'highFidelity') ...[
                        SizedBox(height: Design.dz(12)),
                        Text(
                            info['locationActive'] == true
                                ? '${info['locationLabel']} · 静止定位'
                                : '${info['reason'] ?? '正在启用模拟定位'}',
                            style: TextStyle(
                                color: s.muted, fontSize: Design.dz(15)))
                      ]
                    ])));
      });
}
