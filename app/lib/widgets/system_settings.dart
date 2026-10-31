import 'package:flutter/material.dart';
import '../controller/launcher_controller.dart';
import '../theme/design_tokens.dart';
import '../theme/launcher_theme.dart';
import 'glass_surface.dart';
import 'integration_settings.dart';
import 'native_slice_builder.dart';
import 'dock_size_settings.dart';

/// System-owned labels come from the native adapter.
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
        final entries = (settings['entries'] as List? ?? const [])
            .whereType<Map>()
            .map(_map)
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
          {'officialRoot': true},
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
                if (entry['officialRoot'] == true) {
                  return Padding(
                      padding: EdgeInsets.only(bottom: Design.px(6)),
                      child: GlassSurface(
                          padding: EdgeInsets.symmetric(horizontal: Design.px(8)),
                          child: ListTile(
                              key: const ValueKey('system-setting-official-root'),
                              leading: const Icon(Icons.settings_outlined),
                              title: const Text('原车系统设置'),
                              trailing: const Icon(Icons.chevron_right),
                              onTap: () => controller.command('open-official', value: 'settings'))));
                }
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
                    DockSizeSettings(controller: controller),
                    SizedBox(height: Design.px(22)),
                    Row(children: [
                      Text('原车系统设置&安卓设置', style: TextStyle(fontSize: Design.px(26))),
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
