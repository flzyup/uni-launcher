import 'package:flutter/material.dart';
import '../controller/launcher_controller.dart';
import '../theme/design_tokens.dart';
import '../theme/launcher_theme.dart';
import 'glass_surface.dart';
import 'integration_settings.dart';
import 'native_slice_builder.dart';

/// System-owned labels and available audio modes come from the native adapter.
/// Never invent an enabled setting when this device cannot provide it.
class SystemSettingsPanel extends StatelessWidget {
  final LauncherController controller;
  const SystemSettingsPanel({super.key, required this.controller});

  static Map<String, dynamic> _map(Object? value) =>
      value is Map ? Map<String, dynamic>.from(value) : {};

  @override
  Widget build(BuildContext context) => NativeSliceBuilder(
      valueListenable: controller.native,
      select: (native) => native['systemSettings'],
      builder: (context, native) {
        final s = SurfaceStyle.of(context);
        final settings = _map(native['systemSettings']);
        final audio = _map(settings['navigationAudio']);
        final entries = (settings['entries'] as List? ?? const [])
            .whereType<Map>()
            .map(_map)
            .toList();
        final modes = (audio['modes'] as List? ?? const [])
            .whereType<Map>()
            .map(_map)
            .where((m) => m['value'] is int && m['label'] is String)
            .toList();
        final groups = <String, List<Map<String, dynamic>>>{};
        for (final entry in entries) {
          groups
              .putIfAbsent('${entry['source'] ?? '系统设置'}', () => [])
              .add(entry);
        }
        final orderedGroups = groups.entries.toList()
          ..sort((a, b) {
            int rank(String source) => source == '原车设置'
                ? 0
                : source == 'Android 设置'
                    ? 1
                    : 2;
            final order = rank(a.key).compareTo(rank(b.key));
            return order == 0 ? a.key.compareTo(b.key) : order;
          });
        final rows = <Map<String, dynamic>>[
          for (final group in orderedGroups) ...[
            {'group': group.key},
            ...group.value,
          ]
        ];
        return ListView.builder(
            key: const PageStorageKey('system-settings-scroll'),
            itemCount: rows.length + 1,
            itemBuilder: (context, index) {
              if (index > 0) {
                final entry = rows[index - 1];
                if (entry.containsKey('group')) {
                  return Padding(
                      padding: EdgeInsets.symmetric(vertical: Design.px(14)),
                      child: Text('${entry['group']}',
                          style: TextStyle(color: s.muted)));
                }
                return Padding(
                    padding: EdgeInsets.only(bottom: Design.px(6)),
                    child: GlassSurface(
                        padding: EdgeInsets.symmetric(horizontal: Design.px(8)),
                        child: ListTile(
                            key: ValueKey('system-setting-${entry['id']}'),
                            shape: RoundedRectangleBorder(
                                borderRadius:
                                    BorderRadius.circular(s.controlRadius)),
                            leading: const Icon(Icons.tune_outlined),
                            title: Text('${entry['label']}'),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () => controller.command(
                                'open-system-setting',
                                value: '${entry['id']}'))));
              }
              return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Column(
                        key: const ValueKey('system-app-controls'),
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Padding(
                              padding: EdgeInsets.symmetric(
                                  horizontal: Design.px(16),
                                  vertical: Design.px(12)),
                              child: Text('应用与底栏',
                                  style: TextStyle(fontSize: Design.px(26)))),
                          RuntimeSettings(controller: controller),
                        ]),
                    SizedBox(height: Design.px(22)),
                    GlassSurface(
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                          Text('导航与音乐',
                              style: TextStyle(fontSize: Design.px(26))),
                          SizedBox(height: Design.px(12)),
                          Text('导航播报时保持音乐音量',
                              style: TextStyle(
                                  color: s.muted, fontSize: Design.px(19))),
                          SizedBox(height: Design.px(18)),
                          if (audio['available'] == true && modes.isNotEmpty)
                            Wrap(
                                spacing: Design.px(14),
                                runSpacing: Design.px(12),
                                children: [
                                  for (final mode in modes)
                                    ChoiceChip(
                                        key: ValueKey(
                                            'navigation-audio-${mode['value']}'),
                                        label: Text('${mode['label']}'),
                                        selected:
                                            mode['value'] == audio['mode'],
                                        side: s.technicalFrame
                                            ? s.controlSide(
                                                mode['value'] == audio['mode'])
                                            : null,
                                        shape: s.controlShape(
                                            selected:
                                                mode['value'] == audio['mode']),
                                        onSelected: audio['busy'] == true
                                            ? null
                                            : (selected) {
                                                if (selected)
                                                  controller.command(
                                                      'navigation-audio-mode',
                                                      value:
                                                          '${mode['value']}');
                                              })
                                ])
                          else
                            Text('${audio['reason'] ?? '此设备尚未提供导航混音接口'}',
                                key: const ValueKey(
                                    'navigation-audio-unavailable'),
                                style: TextStyle(color: s.muted)),
                        ])),
                    SizedBox(height: Design.px(22)),
                    Row(children: [
                      Text('系统设置入口', style: TextStyle(fontSize: Design.px(26))),
                      const Spacer(),
                      TextButton.icon(
                          key: const ValueKey('refresh-system-settings'),
                          onPressed: () =>
                              controller.command('refresh-system-settings'),
                          icon: const Icon(Icons.refresh),
                          label: const Text('重新检索'))
                    ]),
                    Padding(
                        padding: EdgeInsets.only(bottom: Design.px(18)),
                        child: Text('按系统应用提供的名称列出设置入口。',
                            style: TextStyle(
                                color: s.muted, fontSize: Design.px(19)))),
                    if (groups.isEmpty)
                      const Padding(
                          padding: EdgeInsets.all(24),
                          child: Text('未找到可直接打开的系统设置入口')),
                  ]);
            });
      });
}
