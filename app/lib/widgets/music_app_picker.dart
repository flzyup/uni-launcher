import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../controller/launcher_controller.dart';
import '../theme/design_tokens.dart';
import '../theme/launcher_theme.dart';
import 'launcher_dialog.dart';
import 'picker_row.dart';

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
          raw['enabled'] != false &&
          (raw['isMusic'] == true || sessions.contains(raw['package'])) &&
          seen.add(raw['package'] as String))
        Map<String, dynamic>.from(raw)
  ];
}

Future<void> showMusicPicker(BuildContext context, LauncherController c) async {
  if (await c.presentGlobalPanel('music-picker') || !context.mounted) return;
  final selected = await showLauncherSheet<String>(context,
      title: '选择音乐应用',
      // 与导航选择器同构，取稿子的 600（见 navigation_app_picker.dart 注释）。
      width: Design.px(720),
      compact: true,
      builder: (_) => MusicAppPicker(controller: c));
  if (selected != null) await c.command('select-player', value: selected);
}

class MusicAppPicker extends StatefulWidget {
  final LauncherController controller;
  const MusicAppPicker({super.key, required this.controller});
  @override
  State<MusicAppPicker> createState() => _MusicAppPickerState();
}

class _MusicAppPickerState extends State<MusicAppPicker> {
  bool _showAll = false;

  @override
  Widget build(BuildContext context) =>
      ValueListenableBuilder<Map<String, dynamic>>(
          valueListenable: widget.controller.native,
          builder: (context, state, _) {
            final accent = SurfaceStyle.of(context).accent;
            final prefs = state['integrationPreferences'] is Map
                ? state['integrationPreferences'] as Map
                : const {};
            final selected = '${prefs['mediaPackage'] ?? 'auto'}';
            final apps = musicAppOptions(state);
            final known = {for (final a in apps) '${a['package']}'};
            final rest = (state['apps'] is List
                    ? state['apps'] as List
                    : const [])
                .whereType<Map<String, dynamic>>()
                .where((a) => a['enabled'] != false)
                .where((a) => a['isSystem'] != true)
                .where((a) => a['launchable'] != false)
                .where((a) => a['package'] is String)
                .where((a) => !known.contains('${a['package']}'))
                .toList()
              ..sort((a, b) => widget.controller
                  .appName(a)
                  .compareTo(widget.controller.appName(b)));

            final rows = <Widget>[
              PickerRow(
                  key: const ValueKey('music-option-auto'),
                  leading: PickerIcon(
                      fallback: Icons.auto_awesome_outlined, brand: accent),
                  name: '自动选择',
                  detail: '按已安装的音乐应用自动切换',
                  tag: selected == 'auto' ? '使用中' : null,
                  selected: selected == 'auto',
                  onTap: () => Navigator.pop(context, 'auto')),
              for (final app in apps)
                PickerRow(
                    key: ValueKey('music-option-${app['package']}'),
                    leading: PickerIcon(
                        bytes: app['iconBytes'] is Uint8List
                            ? app['iconBytes'] as Uint8List
                            : null,
                        fallback: Icons.music_note_outlined,
                        brand: accent),
                    name: widget.controller.appName(app),
                    detail: selected == app['package'] ? '当前播放源' : '已安装',
                    tag: selected == app['package'] ? '使用中' : null,
                    selected: selected == app['package'],
                    onTap: () =>
                        Navigator.pop(context, '${app['package']}')),
              for (final app in _showAll ? rest : const <Map<String, dynamic>>[])
                PickerRow(
                    key: ValueKey('music-option-${app['package']}'),
                    leading: PickerIcon(
                        bytes: app['iconBytes'] is Uint8List
                            ? app['iconBytes'] as Uint8List
                            : null,
                        fallback: Icons.apps,
                        brand: accent),
                    name: widget.controller.appName(app),
                    detail: '已安装',
                    selected: selected == app['package'],
                    onTap: () =>
                        Navigator.pop(context, '${app['package']}')),
            ];

            return ListView(
                shrinkWrap: true,
                padding: EdgeInsets.zero,
                children: [
                  for (var i = 0; i < rows.length; i++)
                    Padding(
                        padding:
                            EdgeInsets.only(top: i == 0 ? 0 : Design.dz(6)),
                        child: rows[i]),
                  if (!_showAll && rest.isNotEmpty)
                    PickerGoRow(
                        key: const ValueKey('music-show-all'),
                        label: '其他已安装应用',
                        onTap: () => setState(() => _showAll = true)),
                  if (apps.isEmpty && !_showAll)
                    const PickerEmpty('未识别到音乐应用；可先打开播放器并授权媒体访问'),
                  const PickerFoot('切换后音乐卡片与控制同步跟随；'
                      '默认应用在「设置 · 导航与媒体」修改。')
                ]);
          });
}
