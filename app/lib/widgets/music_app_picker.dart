import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../controller/launcher_controller.dart';
import '../theme/design_tokens.dart';
import 'launcher_dialog.dart';

/// Only packages with an installed media capability or an active session.
List<Map<String, dynamic>> musicAppOptions(Map<String, dynamic> state) {
  final media = state['media'] is Map ? state['media'] as Map : const {};
  final sessions =
      (media['sessions'] is List ? media['sessions'] as List : const [])
          .whereType<Map>()
          .map((e) => '${e['package'] ?? ''}')
          .toSet();
  final seen = <String>{};
  return [
    for (final raw in (state['apps'] is List ? state['apps'] as List : const [])
        .whereType<Map>())
      if (raw['package'] is String &&
          (raw['isMusic'] == true || sessions.contains(raw['package'])) &&
          seen.add(raw['package'] as String))
        Map<String, dynamic>.from(raw)
  ];
}

Future<void> showMusicPicker(BuildContext context, LauncherController c) async {
  if (await c.presentGlobalPanel('music-picker') || !context.mounted) return;
  final selected = await showLauncherSheet<String>(context,
      title: '选择音乐应用',
      subtitle: '选择后音乐卡片和控制将跟随该播放器',
      width: Design.px(760),
      height: Design.px(650),
      builder: (_) => MusicAppPicker(controller: c));
  if (selected != null) await c.command('select-player', value: selected);
}

class MusicAppPicker extends StatelessWidget {
  final LauncherController controller;
  const MusicAppPicker({super.key, required this.controller});
  @override
  Widget build(BuildContext context) =>
      ValueListenableBuilder<Map<String, dynamic>>(
          valueListenable: controller.native,
          builder: (context, state, _) {
            final prefs = state['integrationPreferences'] is Map
                ? state['integrationPreferences'] as Map
                : const {};
            final selected = prefs['mediaPackage'] ?? 'auto';
            final apps = musicAppOptions(state);
            return ListView(children: [
              ListTile(
                  key: const ValueKey('music-option-auto'),
                  leading: const Icon(Icons.auto_awesome_outlined),
                  title: const Text('自动选择'),
                  trailing: selected == 'auto' ? const Icon(Icons.check) : null,
                  onTap: () => Navigator.pop(context, 'auto')),
              for (final app in apps)
                ListTile(
                    key: ValueKey('music-option-${app['package']}'),
                    leading: SizedBox.square(
                        dimension: Design.px(36),
                        child: app['iconBytes'] is Uint8List
                            ? Image.memory(app['iconBytes'] as Uint8List,
                                errorBuilder: (_, __, ___) =>
                                    const Icon(Icons.music_note_outlined))
                            : const Icon(Icons.music_note_outlined)),
                    title: Text(controller.appName(app)),
                    trailing: selected == app['package']
                        ? const Icon(Icons.check)
                        : null,
                    onTap: () =>
                        Navigator.pop(context, app['package'] as String)),
              if (apps.isEmpty)
                const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('未识别到音乐应用；可先打开播放器并授权媒体访问')),
            ]);
          });
}
