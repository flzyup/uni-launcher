import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../controller/launcher_controller.dart';
import '../theme/design_tokens.dart';
import '../theme/launcher_theme.dart';
import 'launcher_dialog.dart';
import 'navigation_options.dart';
import 'picker_row.dart';

Future<void> showNavigationPicker(
    BuildContext context, LauncherController c) async {
  if (await c.presentGlobalPanel('navigation') || !context.mounted) return;
  final picked = await showLauncherSheet<String>(context,
      title: '选择导航应用',
      // 稿子 `.dlg.pick` 收窄到 600（1600 画布），比 760×5/6 的 633 窄 33：
      // 该块单独写死了宽度和更小的内边距，是手工调过的值，不是换算笔误。
      width: Design.px(720),
      // 高度交给内容撑：稿子里就是几行 + 说明，固定 541 会在底部空一大块。
      compact: true,
      builder: (_) => NavigationAppPicker(controller: c));
  if (picked != null) await c.command('select-navigation', value: picked);
}

/// 四家地图的品牌色与矢量名，色取自稿子 `.pick-ic` 的 `--a`、图标是稿子内联
/// 的那几个原图（已抄进 `assets/icons/map-*.svg`）。装了没列到的地图就退回
/// 强调色 + 项目线条图标——色板只是图标底，真图标贴上去之后它基本看不见。
const _brand = <String, (Color, String)>{
  'com.autonavi.amapauto': (Color(0xFF1B86FF), 'map-amap'),
  'com.autonavi.amap': (Color(0xFF1B86FF), 'map-amap'),
  'com.baidu.naviauto': (Color(0xFF2932E1), 'map-baidu'),
  'com.baidu.BaiduMap': (Color(0xFF2932E1), 'map-baidu'),
  'com.tencent.mapauto': (Color(0xFF12B7F5), 'map-tencent'),
  'com.tencent.map': (Color(0xFF12B7F5), 'map-tencent'),
  'com.huawei.petalmap': (Color(0xFFE24A3C), 'map-petal'),
};

class NavigationAppPicker extends StatefulWidget {
  final LauncherController controller;
  const NavigationAppPicker({super.key, required this.controller});
  @override
  State<NavigationAppPicker> createState() => _NavigationAppPickerState();
}

class _NavigationAppPickerState extends State<NavigationAppPicker> {
  /// 「其他已安装应用」展开后列出全部应用，不再区分导航。
  bool _showAll = false;

  @override
  Widget build(BuildContext context) =>
      ValueListenableBuilder<Map<String, dynamic>>(
          valueListenable: widget.controller.native,
          builder: (context, n, _) {
            final accent = SurfaceStyle.of(context).accent;
            final nav = n['navigation'] as Map? ?? {};
            final selected = '${nav['preferredPackage'] ?? 'auto'}';
            final apps = (n['apps'] as List? ?? [])
                .whereType<Map<String, dynamic>>()
                .toList();
            final options = navigationOptions(widget.controller, n);
            // 和「应用」面板同一套过滤：只列能点的、非系统的已启用应用，
            // 否则「其他已安装应用」里会混进一堆系统组件。
            final rest = apps
                .where((a) => a['enabled'] != false)
                .where((a) => a['isSystem'] != true)
                .where((a) => a['launchable'] != false)
                .where((a) => a['package'] is String)
                .where((a) => !options.containsKey(a['package']))
                .toList()
              ..sort((a, b) => widget.controller
                  .appName(a)
                  .compareTo(widget.controller.appName(b)));

            final rows = <Widget>[
              PickerRow(
                  key: const ValueKey('nav-option-auto'),
                  leading: PickerIcon(
                      fallback: Icons.auto_awesome_outlined, brand: accent),
                  name: '自动选择',
                  detail: '按已安装的导航应用自动切换',
                  tag: selected == 'auto' ? '使用中' : null,
                  selected: selected == 'auto',
                  onTap: () => Navigator.pop(context, 'auto')),
              for (final entry in options.entries)
                PickerRow(
                    key: ValueKey('nav-option-${entry.key}'),
                    leading: PickerIcon(
                        bytes: _iconBytes(apps, entry.key),
                        svg: _brand[entry.key]?.$2,
                        fallback: Icons.navigation_outlined,
                        brand: _brand[entry.key]?.$1),
                    name: entry.value,
                    detail: selected == entry.key ? '默认应用' : '已安装',
                    tag: selected == entry.key ? '使用中' : null,
                    selected: selected == entry.key,
                    onTap: () => Navigator.pop(context, entry.key)),
              for (final app in _showAll ? rest : const <Map<String, dynamic>>[])
                PickerRow(
                    key: ValueKey('nav-option-${app['package']}'),
                    leading: PickerIcon(
                        bytes: app['iconBytes'] is Uint8List
                            ? app['iconBytes'] as Uint8List
                            : null,
                        svg: _brand['${app['package']}']?.$2,
                        fallback: Icons.apps,
                        brand: _brand['${app['package']}']?.$1),
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
                        key: const ValueKey('nav-show-all'),
                        label: '其他已安装应用',
                        onTap: () => setState(() => _showAll = true)),
                  if (options.isEmpty && !_showAll)
                    const PickerEmpty('尚未识别到已安装的导航应用'),
                  const PickerFoot('切换后地图卡与红绿灯卡同步换源；'
                      '默认应用在「设置 · 导航与媒体」修改。')
                ]);
          });

  Uint8List? _iconBytes(List<Map> apps, String pkg) {
    final app = apps.where((a) => a['package'] == pkg).firstOrNull;
    final bytes = app?['iconBytes'];
    return bytes is Uint8List ? bytes : null;
  }
}
