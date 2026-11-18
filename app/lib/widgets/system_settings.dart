import 'package:flutter/material.dart';
import '../controller/launcher_controller.dart';
import '../theme/design_tokens.dart';
import '../theme/launcher_theme.dart';
import 'choice_button.dart';
import 'diagnostics_settings.dart';
import 'native_slice_builder.dart';
import 'setting_block.dart';
import 'simulation_settings.dart';

/// sim f14 · 系统与调试：左边诊断日志，右边原车/安卓设置入口。
///
/// 两栏各自滚动：两边内容都可能很长（日志预览、系统入口数量），
/// 共用一个滚动条会把左边顶到看不见。
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
        final ordered = groups.entries.toList()
          ..sort((a, b) {
            int rank(String source) => source == '原车设置'
                ? 0
                : source == 'Android 设置'
                    ? 1
                    : 2;
            final order = rank(a.key).compareTo(rank(b.key));
            return order == 0 ? a.key.compareTo(b.key) : order;
          });
        // sim f14：左栏定宽 660（诊断日志一列），右栏吃掉剩余宽度。
        // 两块都撑到页面高度——设计稿里它们是两条通高的栏，不是两张随内容
        // 缩小的卡片，否则右边短的时候左边会「悬」出一截。
        return LayoutBuilder(
            builder: (context, box) =>
                Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  SizedBox(
                      width: Design.dz(660),
                      child: SingleChildScrollView(
                          key: const PageStorageKey('diagnostics-scroll'),
                          child: ConstrainedBox(
                              constraints:
                                  BoxConstraints(minHeight: box.maxHeight),
                              child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    SimulationSettings(controller: controller),
                                    const DiagnosticsSettings(),
                                  ])))),
                  SizedBox(width: Design.dz(11.67)),
                  Expanded(
                      child: SingleChildScrollView(
                          key: const PageStorageKey('system-settings-scroll'),
                          child: ConstrainedBox(
                              constraints:
                                  BoxConstraints(minHeight: box.maxHeight),
                              child: SettingBlock(
                                  title: '原车系统设置&安卓设置',
                                  note: '按系统应用提供的名称列出设置入口。',
                                  trailing: DesignTextAction('重新检索',
                                      key: const ValueKey(
                                          'refresh-system-settings'),
                                      chevron: false,
                                      onPressed: () => controller
                                          .command('refresh-system-settings')),
                                  child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: [
                                        // 原车系统设置是唯一的「大入口」，给一块主题色淡底。
                                        Material(
                                            color: Colors.transparent,
                                            child: InkWell(
                                                key: const ValueKey(
                                                    'system-setting-official-root'),
                                                onTap: () => controller.command(
                                                    'open-official',
                                                    value: 'settings'),
                                                borderRadius:
                                                    BorderRadius.circular(
                                                        s.controlRadius),
                                                child: Container(
                                                    height: Design.dz(46),
                                                    padding: EdgeInsets.symmetric(
                                                        horizontal:
                                                            Design.dz(14)),
                                                    decoration: BoxDecoration(
                                                        color: s.accent.withValues(
                                                            alpha: .07),
                                                        borderRadius: BorderRadius.circular(
                                                            s.controlRadius),
                                                        border: Border.all(
                                                            color: s.accent.withValues(alpha: .26))),
                                                    child: Row(children: [
                                                      Icon(
                                                          Icons
                                                              .settings_outlined,
                                                          size: Design.dz(20),
                                                          color: s.accent),
                                                      SizedBox(
                                                          width: Design.dz(11)),
                                                      Text('原车系统设置',
                                                          style: TextStyle(
                                                              fontSize:
                                                                  Design.dz(
                                                                      15.5),
                                                              color: s.accent)),
                                                      const Spacer(),
                                                      Icon(Icons.chevron_right,
                                                          size: Design.dz(18),
                                                          color: s.accent
                                                              .withValues(
                                                                  alpha: .7))
                                                    ])))),
                                        SizedBox(height: Design.dz(10)),
                                        if (groups.isEmpty)
                                          Padding(
                                              padding: EdgeInsets.symmetric(
                                                  vertical: Design.dz(16)),
                                              child: Text('未找到可直接打开的系统设置入口',
                                                  style: TextStyle(
                                                      fontSize: Design.dz(13.5),
                                                      color: s.text.withValues(
                                                          alpha: .42)))),
                                        for (final group in ordered) ...[
                                          Padding(
                                              padding: EdgeInsets.only(
                                                  top: Design.dz(6),
                                                  bottom: Design.dz(4)),
                                              child: Text(group.key,
                                                  style: TextStyle(
                                                      fontSize: Design.dz(11),
                                                      letterSpacing:
                                                          Design.dz(1.2),
                                                      color: s.text.withValues(
                                                          alpha: .32)))),
                                          for (final entry in group.value)
                                            SettingRow(
                                                key: ValueKey(
                                                    'system-setting-${entry['id']}'),
                                                tile: true,
                                                height: 46,
                                                label: '${entry['label']}',
                                                leading: Icon(
                                                    Icons.tune_outlined,
                                                    size: Design.dz(18),
                                                    color: s.text.withValues(
                                                        alpha: .34)),
                                                trailing: Icon(
                                                    Icons.chevron_right,
                                                    size: Design.dz(16),
                                                    color: s.text
                                                        .withValues(alpha: .3)),
                                                onTap: () => controller.command(
                                                    'open-system-setting',
                                                    value: '${entry['id']}')),
                                        ],
                                        SizedBox(height: Design.dz(8)),
                                        Text('系统应用提供的入口不会随时都在，缺失时「重新检索」。',
                                            style: TextStyle(
                                                fontSize: Design.dz(11.5),
                                                color: s.muted))
                                      ]))))),
                ]));
      });
}
