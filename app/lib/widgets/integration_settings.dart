import 'package:flutter/material.dart';
import '../controller/launcher_controller.dart';
import '../theme/design_tokens.dart';
import '../theme/launcher_theme.dart';
import 'glass_surface.dart';

/// Installed-app identity is the key; labels may be duplicated or localized.
class IntegrationSettings extends StatelessWidget {
  final LauncherController controller;
  final Map<String, dynamic> native;
  const IntegrationSettings(
      {super.key, required this.controller, required this.native});
  Map<String, dynamic> map(Object? value) =>
      value is Map ? Map<String, dynamic>.from(value) : {};
  @override
  Widget build(BuildContext context) {
    final s = SurfaceStyle.of(context),
        nav = map(native['navigation']),
        prefs = map(native['integrationPreferences']);
    final apps = <String, String>{};
    for (final raw
        in native['apps'] is List ? native['apps'] as List : const []) {
      final app = map(raw),
          pkg =
              '${app['package'] ?? app['id']?.toString().split('/').first ?? ''}';
      if (pkg.isNotEmpty) {
        apps.putIfAbsent(pkg, () => controller.appName(app));
      }
    }
    Widget picker(String key, String label, String action, String selected) {
      final entries = {'auto': '自动选择', ...apps};
      if (!entries.containsKey(selected)) entries[selected] = '所选应用已卸载';
      return DropdownButtonFormField<String>(
          key: ValueKey(key),
          initialValue: selected,
          isExpanded: true,
          decoration: InputDecoration(labelText: label),
          items: entries.entries
              .map((e) => DropdownMenuItem(
                  value: e.key,
                  child: Text(e.value,
                      maxLines: 1, overflow: TextOverflow.ellipsis)))
              .toList(),
          onChanged: (v) {
            if (v != null) controller.command(action, value: v);
          });
    }

    return GlassSurface(
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text('导航与播放器', style: TextStyle(fontSize: Design.px(26))),
      SizedBox(height: Design.px(22)),
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
              picker('navigation-source', '导航应用', 'select-navigation',
                  '${nav['preferredPackage'] ?? 'auto'}'),
              DesignSwitchTile(
                  key: const ValueKey('embed-navigation'),
                  contentPadding: EdgeInsets.zero,
                  title: const Text('在地图卡片中显示导航'),
                  subtitle: Text('${nav['reason'] ?? '需要 Android 9 与车机嵌入权限'}'),
                  value: nav['enabled'] != false,
                  onChanged: (v) =>
                      controller.command('embed-navigation', enabled: v)),
              TextButton(
                  onPressed: () => controller.command('launch-navigation'),
                  child: const Text('打开导航应用')),
            ])),
        SizedBox(width: Design.px(30)),
        Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
              picker('media-source', '关联的音乐播放器', 'select-player',
                  '${prefs['mediaPackage'] ?? 'auto'}'),
              SizedBox(height: Design.px(16)),
              Text(
                  '选择网易云、QQ 音乐或原车音乐后，歌曲、封面、歌词和播放控制均跟随该应用。请先在播放器中播放一首歌曲并授权媒体访问。',
                  style: TextStyle(
                      color: s.muted, fontSize: Design.px(19), height: 1.6)),
              TextButton(
                  onPressed: () => controller.command('launch-player'),
                  child: const Text('打开关联播放器')),
            ]))
      ]),
      if (native['demo'] == true)
        Text('当前为演示模式；关闭演示数据后读取真实播放器与车辆信息。',
            style: TextStyle(color: s.accent, fontSize: Design.px(18))),
    ]));
  }
}

/// Operational preferences formerly grouped under the removed 功能接入 tab.
class RuntimeSettings extends StatelessWidget {
  final LauncherController controller;
  const RuntimeSettings({super.key, required this.controller});
  @override
  Widget build(BuildContext context) =>
      ValueListenableBuilder<Map<String, dynamic>>(
          valueListenable: controller.native,
          builder: (context, n, _) {
            final c = controller, s = SurfaceStyle.of(context);
            Map<String, dynamic> mapOf(Object? v) =>
                v is Map ? Map<String, dynamic>.from(v) : {};
            return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  IntegrationSettings(controller: c, native: n),
                  SizedBox(height: Design.px(16)),
                  GlassSurface(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                        Row(children: [
                          Expanded(
                              child: Text(
                                  '${mapOf(n['vehicle'])['reason'] ?? '未连接原车服务'}',
                                  style: TextStyle(
                                      fontSize: Design.px(20),
                                      color: s.muted))),
                          TextButton(
                              onPressed: () => c.command('refresh'),
                              child: const Text('刷新连接')),
                          TextButton(
                              onPressed: () => c.command('media-access'),
                              child: const Text('授权媒体访问'))
                        ]),
                        DesignSwitchTile(
                            key: const ValueKey('global-dock'),
                            title: const Text('全局底栏'),
                            subtitle: Text(
                                mapOf(n['globalDock'])['allowed'] == true
                                    ? '在其他应用中使用相同的首页、空调和音乐控制'
                                    : '开启后需允许悬浮显示'),
                            value: mapOf(n['globalDock'])['enabled'] == true,
                            onChanged: (v) =>
                                c.command('global-dock', enabled: v)),
                        DesignSwitchTile(
                            key: const ValueKey('system-navigation-hidden'),
                            title: const Text('隐藏系统原有导航栏'),
                            subtitle: Text(n['systemNavigationGranted'] == true
                                ? '关闭后恢复原有显示；与全局底栏分别设置'
                                : '需要系统授予导航栏管理权限'),
                            value: n['systemNavigationHidden'] == true,
                            onChanged: n['systemNavigationGranted'] == true
                                ? (v) => c.command('system-navigation-hidden',
                                    enabled: v)
                                : null),
                        Row(children: [
                          Text('UNI · xyz.i4o.uni.launcher',
                              style: TextStyle(
                                  fontSize: Design.px(18), color: s.muted)),
                          const Spacer(),
                          TextButton(
                              onPressed: () =>
                                  c.command('open-official', value: 'settings'),
                              child: const Text('打开原车设置'))
                        ])
                      ]))
                ]);
          });
}
