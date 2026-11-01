import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../controller/launcher_controller.dart';
import '../theme/design_tokens.dart';
import 'launcher_dialog.dart';

Future<void> showNavigationPicker(
    BuildContext context, LauncherController c) async {
  if (await c.presentGlobalPanel('navigation') || !context.mounted) return;
  final picked = await showLauncherSheet<String>(context,
      title: '选择导航应用',
      subtitle: '保存在地图卡片中，点击标题即可打开',
      width: Design.px(760),
      height: Design.px(650),
      glowType: 'nav',
      builder: (_) => NavigationAppPicker(controller: c));
  if (picked != null) await c.command('select-navigation', value: picked);
}

class NavigationAppPicker extends StatefulWidget {
  final LauncherController controller;
  const NavigationAppPicker({super.key, required this.controller});
  @override
  State<NavigationAppPicker> createState() => _NavigationAppPickerState();
}

class _NavigationAppPickerState extends State<NavigationAppPicker> {
  bool showAll = false;
  @override
  Widget build(BuildContext context) =>
      ValueListenableBuilder<Map<String, dynamic>>(
          valueListenable: widget.controller.native,
          builder: (context, n, _) {
            final nav = n['navigation'] as Map? ?? {};
            final selected = nav['preferredPackage'] ?? 'auto';
            final apps = (n['apps'] as List? ?? []).whereType<Map>().toList();
            final options = <String, Map>{
              for (final a in (nav['options'] as List? ?? []).whereType<Map>())
                '${a['package']}': a
            };
            if (showAll) {
              for (final app in apps) {
                if (app['package'] != null)
                  options.putIfAbsent('${app['package']}', () => app);
              }
            }
            return ListView(children: [
              ListTile(
                  key: const ValueKey('nav-option-auto'),
                  leading: const Icon(Icons.auto_awesome_outlined),
                  title: const Text('自动选择'),
                  trailing: selected == 'auto' ? const Icon(Icons.check) : null,
                  onTap: () => Navigator.pop(context, 'auto')),
              for (final entry in options.entries)
                Builder(builder: (context) {
                  final app =
                      apps.where((a) => a['package'] == entry.key).firstOrNull;
                  final bytes = app?['iconBytes'];
                  final displayApp =
                      Map<String, dynamic>.from(app ?? entry.value)
                        ..putIfAbsent('package', () => entry.key);
                  return ListTile(
                      key: ValueKey('nav-option-${entry.key}'),
                      leading: SizedBox(
                          width: Design.px(36),
                          height: Design.px(36),
                          child: bytes is Uint8List
                              ? Image.memory(bytes,
                                  errorBuilder: (_, __, ___) =>
                                      const Icon(Icons.navigation_outlined))
                              : const Icon(Icons.navigation_outlined)),
                      title: Text(widget.controller.appName(displayApp)),
                      trailing: selected == entry.key
                          ? const Icon(Icons.check)
                          : null,
                      onTap: () => Navigator.pop(context, entry.key));
                }),
              if (options.isEmpty)
                const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('尚未识别到导航应用，可从其他已安装应用中选择')),
              if (!showAll)
                TextButton.icon(
                    key: const ValueKey('nav-show-all'),
                    icon: const Icon(Icons.apps),
                    label: const Text('其他已安装应用'),
                    onPressed: () => setState(() => showAll = true)),
            ]);
          });
}
