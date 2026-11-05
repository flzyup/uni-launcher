import 'package:flutter/material.dart';

import '../controller/launcher_controller.dart';
import '../model/storage_cleaner.dart';
import '../theme/design_tokens.dart';
import '../theme/launcher_theme.dart';
import 'launcher_dialog.dart';
import 'uni_icon.dart';
/// 右下角 UNI 菜单的第四项入口。全局底栏开着时交给独立面板窗口渲染（同一个面板），
/// 否则在本窗口弹一张和「车辆信息」同规格的玻璃面板。
Future<void> showCleanerPanel(BuildContext context, LauncherController c) async {
  if (await c.presentGlobalPanel('cleaner') || !context.mounted) return;
  await showLauncherSheet<void>(context,
      title: '垃圾清理',
      subtitle: '扫全机缓存、临时文件与残留；照片、导航离线地图和行车记录不动',
      closeLabel: '关闭垃圾清理',
      width: Design.px(880),
      height: Design.px(780),
      glowType: 'broom',
      builder: (context) => CleanerPanel(controller: c));
}

class CleanerPanel extends StatefulWidget {
  final LauncherController controller;
  const CleanerPanel({super.key, required this.controller});
  @override
  State<CleanerPanel> createState() => _CleanerPanelState();
}

class _CleanerPanelState extends State<CleanerPanel> {
  /// 本界面自己的勾选状态。原生只负责给出「默认是否勾选」和「能不能勾」。
  final Set<String> _selected = {};
  /// 出现过的类目：用户取消过一次的类目，重新扫描后不再自动勾回来。
  final Set<String> _seen = {};
  int _rev = -1;
  bool _confirming = false;

  LauncherController get controller => widget.controller;

  @override
  void initState() {
    super.initState();
    // 打开面板先要权限：拿不到就由原生 MainActivity 直接弹系统框（不跳设置页）；
    // 授权回调会触发一次重扫，所以这条路径下不再重复发 scan。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final state = CleanerState.fromNative(controller.native.value);
      if (!state.storageGranted) {
        controller.command('cleaner-grant');
        return;
      }
      if (!state.running) controller.command('cleaner-scan');
    });
  }

  /// 每次 revision 变化才重新对齐勾选，避免进度刷新把用户的选择冲掉。
  void _syncSelection(CleanerState state) {
    if (state.rev == _rev) return;
    _rev = state.rev;
    final next = <String>{};
    for (final category in state.categories) {
      if (!category.available || category.bytes <= 0) continue;
      if (_selected.contains(category.id)) {
        next.add(category.id);
        continue;
      }
      if (_seen.contains(category.id)) continue;
      if (category.defaultSelected) next.add(category.id);
    }
    _selected
      ..clear()
      ..addAll(next);
    _seen
      ..clear()
      ..addAll(state.categories.map((category) => category.id));
    if (next.isEmpty) _confirming = false;
  }

  void _toggle(CleanerCategory category) {
    setState(() {
      _confirming = false;
      if (!_selected.remove(category.id)) _selected.add(category.id);
    });
  }

  void _clean(List<CleanerCategory> categories) {
    final ids = [
      for (final category in categories)
        if (_selected.contains(category.id)) category.id
    ];
    if (ids.isEmpty) return;
    setState(() => _confirming = false);
    controller.command('cleaner-clean', value: ids.join(','));
  }

  void _openPermission() {
    // 重新走一次授权：系统框可能已经"不再询问"，此时只能在应用信息页手动开。
    controller.command('cleaner-grant');
  }

  static IconData _iconFor(String id) => switch (id) {
        'self-cache' => Icons.cleaning_services_outlined,
        'app-cache' => Icons.apps,
        'system-cache' => Icons.settings_outlined,
        'external-cache' => Icons.sd_storage_outlined,
        'thumbnails' => Icons.image_outlined,
        'log' || 'oem-log' => Icons.description_outlined,
        'ad-cache' => Icons.campaign_outlined,
        'empty-dir' => Icons.folder_off_outlined,
        'orphan-data' => Icons.delete_sweep_outlined,
        'apk-leftover' => Icons.android,
        'large-unused' => Icons.folder_zip_outlined,
        _ => Icons.cleaning_services_outlined,
      };

  @override
  Widget build(BuildContext context) =>
      ValueListenableBuilder<Map<String, dynamic>>(
          valueListenable: controller.native,
          builder: (context, native, _) {
            final state = CleanerState.fromNative(native);
            _syncSelection(state);
            final s = SurfaceStyle.of(context);
            final selected = [
              for (final category in state.categories)
                if (_selected.contains(category.id)) category
            ];
            final selectedBytes = selected.fold<int>(
                0, (sum, category) => sum + category.bytes);
            final progress = state.running ? state.progress : 0.0;
            return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _headline(s, state, selectedBytes),
                  SizedBox(height: Design.px(16)),
                  _bar(s, state.running ? progress : _usedFraction(state),
                      height: Design.px(8),
                      accent: !state.running),
                  SizedBox(height: Design.px(18)),
                  Expanded(
                      child: state.categories.isEmpty
                          ? Center(
                              child: Text(
                                  state.scanning ? '正在扫描…' : '还没有扫描结果',
                                  style: TextStyle(
                                      fontSize: Design.px(21),
                                      color: s.muted)))
                          : ListView(children: _list(s, state))),
                  SizedBox(height: Design.px(12)),
                  _footer(s, state, selected, selectedBytes),
                ]);
          });

  Widget _headline(SurfaceStyle s, CleanerState state, int selectedBytes) {
    final total = state.cleanableBytes;
    final headline = state.running
        ? '${state.phaseLabel} ${(state.progress * 100).round()}%'
        : total > 0
            ? formatBytes(total)
            : '已清理干净';
    final detail = state.running
        ? (state.current.isEmpty ? '正在统计' : state.current)
        : total > 0
            ? '可清理 · ${state.categories.where((c) => c.available && c.bytes > 0).length} 项'
            : '当前没有可清理的缓存与临时文件';
    final capacity = state.totalBytes > 0
        ? '已用 ${formatBytes(state.usedBytes)} / ${formatBytes(state.totalBytes)}'
        : '';
    return Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
      Expanded(
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
            Text(headline,
                key: const ValueKey('cleaner-headline'),
                style: TextStyle(
                    fontSize: Design.px(46),
                    fontWeight: FontWeight.w600,
                    height: 1.05)),
            SizedBox(height: Design.px(6)),
            Text(detail,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: Design.px(18), color: s.muted)),
          ])),
      if (capacity.isNotEmpty)
        Text(capacity,
            style: TextStyle(fontSize: Design.px(18), color: s.muted)),
    ]);
  }

  double _usedFraction(CleanerState state) {
    if (state.totalBytes <= 0) return 0;
    return (state.usedBytes / state.totalBytes).clamp(0.0, 1.0);
  }

  Widget _bar(SurfaceStyle s, double value,
          {double height = 8, bool accent = true}) =>
      ClipRRect(
          borderRadius: BorderRadius.circular(height),
          child: Container(
              height: height,
              color: s.muted.withValues(alpha: .16),
              child: FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: value.clamp(0.0, 1.0),
                  child: Container(
                      color: accent
                          ? s.accent
                          : s.accent.withValues(alpha: .55)))));

  Widget _box(SurfaceStyle s, bool selected, {required bool enabled}) =>
      Container(
          width: Design.px(28),
          height: Design.px(28),
          decoration: BoxDecoration(
              color: selected && enabled
                  ? s.accent.withValues(alpha: .22)
                  : Colors.transparent,
              border: Border.all(
                  color: !enabled
                      ? s.edge
                      : selected
                          ? s.accent
                          : s.muted.withValues(alpha: .6),
                  width: selected && enabled ? 2 : 1.5),
              borderRadius: BorderRadius.circular(Design.px(8))),
          child: selected && enabled
              ? Icon(Icons.check, size: Design.px(20), color: s.accent)
              : null);

  Widget _tag(SurfaceStyle s, String label) => Container(
      padding: EdgeInsets.symmetric(
          horizontal: Design.px(7), vertical: Design.px(1)),
      decoration: BoxDecoration(
          border: Border.all(color: s.edge),
          borderRadius: BorderRadius.circular(Design.px(6))),
      child: Text(label,
          style: TextStyle(fontSize: Design.px(14), color: s.muted)));

  Widget _row(SurfaceStyle s, CleanerState state, CleanerCategory category) {
    final selectable = category.available && category.bytes > 0;
    final selected = _selected.contains(category.id);
    return Semantics(
        checked: selected,
        enabled: selectable && !state.running,
        child: InkWell(
            key: ValueKey('cleaner-item-${category.id}'),
            borderRadius: BorderRadius.circular(s.controlRadius),
            onTap: selectable && !state.running
                ? () => _toggle(category)
                : null,
            child: Padding(
                padding: EdgeInsets.symmetric(
                    horizontal: Design.px(6), vertical: Design.px(9)),
                child: Row(children: [
                  _box(s, selected, enabled: selectable),
                  SizedBox(width: Design.px(14)),
                  SizedBox(
                      width: Design.px(40),
                      height: Design.px(40),
                      child: Center(
                          child: DesignIcon(_iconFor(category.id),
                              size: Design.px(27),
                              color: selectable ? s.text : s.disabled))),
                  SizedBox(width: Design.px(12)),
                  Expanded(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                        Row(children: [
                          Flexible(
                              child: Text(category.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                      fontSize: Design.px(22),
                                      fontWeight: FontWeight.w500,
                                      color: selectable ? s.text : s.disabled))),
                          if (category.needsReview) ...[
                            SizedBox(width: Design.px(8)),
                            _tag(s, '需确认')
                          ],
                          if (!category.verified) ...[
                            SizedBox(width: Design.px(6)),
                            _tag(s, '待实车确认')
                          ],
                        ]),
                        if (category.note.isNotEmpty)
                          Text(category.note,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontSize: Design.px(16),
                                  color: selectable ? s.muted : s.disabled)),
                      ])),
                  SizedBox(width: Design.px(12)),
                  Text(category.bytes > 0 ? formatBytes(category.bytes) : '—',
                      style: TextStyle(
                          fontSize: Design.px(21),
                          color: selectable ? s.text : s.disabled)),
                ]))));
  }

  /// 按分组渲染：类目多了以后一列平铺看不出层次，分组标题带该类目的合计。
  List<Widget> _list(SurfaceStyle s, CleanerState state) {
    final known = cleanerGroupOrder.toSet();
    final groups = <String, List<CleanerCategory>>{};
    for (final category in state.categories) {
      final group = known.contains(category.group) ? category.group : 'junk';
      groups.putIfAbsent(group, () => []).add(category);
    }
    final widgets = <Widget>[];
    for (final group in cleanerGroupOrder) {
      final items = groups[group];
      if (items == null || items.isEmpty) continue;
      widgets.add(_groupHeader(s, group, items));
      for (final item in items) {
        widgets.add(_row(s, state, item));
      }
    }
    return widgets;
  }

  Widget _groupHeader(SurfaceStyle s, String group, List<CleanerCategory> items) {
    final bytes = items.fold<int>(
        0, (sum, item) => sum + (item.available ? item.bytes : 0));
    return Padding(
        padding: EdgeInsets.only(
            left: Design.px(6), top: Design.px(14), bottom: Design.px(2)),
        child: Row(children: [
          Text(cleanerGroupLabels[group] ?? group,
              style: TextStyle(
                  fontSize: Design.px(17),
                  letterSpacing: Design.px(1),
                  color: s.muted)),
          SizedBox(width: Design.px(10)),
          Expanded(child: Container(height: 1, color: s.edge)),
          SizedBox(width: Design.px(10)),
          if (bytes > 0)
            Text(formatBytes(bytes),
                style: TextStyle(fontSize: Design.px(16), color: s.muted)),
        ]));
  }

  Widget _footer(SurfaceStyle s, CleanerState state,
      List<CleanerCategory> selected, int selectedBytes) {
    final last = lastCleanLabel(state.lastCleanAt);
    final waitingPermission = !state.storageGranted;
    final status = waitingPermission
        ? '正在获取存储权限…'
        : state.cleaning && state.purgeTotal > 0
            ? state.purgeLabel
            : state.running
                ? (state.current.isEmpty
                    ? state.phaseLabel
                    : '${state.phaseLabel} · ${state.current}')
                : selectedBytes > 0
                    ? '已选 ${selected.length} 项 · ${formatBytes(selectedBytes)}'
                    : '没有选中任何内容';
    final note = [
      if (state.error.isNotEmpty) state.error,
      if (state.rulesIssue.isNotEmpty) state.rulesIssue,
      if (!state.running && state.lastCleanBytes > 0 && last.isNotEmpty)
        '上次清理 $last，释放 ${formatBytes(state.lastCleanBytes)}',
      if (state.scanLabel.isNotEmpty) state.scanLabel,
    ].join(' · ');
    final canClean = !state.running && !waitingPermission && selectedBytes > 0;
    return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (note.isNotEmpty)
            Padding(
                padding: EdgeInsets.only(bottom: Design.px(10)),
                child: Text(note,
                    key: const ValueKey('cleaner-note'),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: Design.px(16), color: s.muted))),
          Row(children: [
            Expanded(
                child: Text(status,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: Design.px(19),
                        color: state.error.isNotEmpty ? s.accent : s.muted))),
            if (waitingPermission) ...[
              _secondary(s, '重试授权', _openPermission),
              SizedBox(width: Design.px(10)),
            ],
            if (state.running) ...[
              _secondary(s, '停止', () => controller.command('cleaner-cancel')),
              SizedBox(width: Design.px(10)),
            ],
            SizedBox(
                width: Design.px(300),
                child: _confirming
                    ? Row(children: [
                        Expanded(
                            child: _secondary(
                                s, '取消', () => setState(() => _confirming = false))),
                        SizedBox(width: Design.px(8)),
                        Expanded(
                            flex: 2,
                            child: _primary(
                                s,
                                '确认清理 ${formatBytes(selectedBytes)}',
                                () => _clean(selected)))
                      ])
                    : _primary(
                        s,
                        waitingPermission
                            ? '等待存储权限'
                            : state.running
                                ? '${state.phaseLabel} ${(state.progress * 100).round()}%'
                                : selectedBytes > 0
                                    ? '清理 ${formatBytes(selectedBytes)}'
                                    : '暂无可清理内容',
                        canClean ? () => setState(() => _confirming = true) : null)),
          ])
        ]);
  }

  Widget _primary(SurfaceStyle s, String label, VoidCallback? onTap) => InkWell(
      borderRadius: BorderRadius.circular(s.controlRadius),
      onTap: onTap,
      child: Container(
          height: Design.px(62),
          alignment: Alignment.center,
          padding: EdgeInsets.symmetric(horizontal: Design.px(14)),
          decoration: BoxDecoration(
              color: onTap == null
                  ? s.muted.withValues(alpha: .10)
                  : s.accent.withValues(alpha: .18),
              border: Border.all(
                  color: onTap == null
                      ? s.edge
                      : s.accent.withValues(alpha: .85),
                  width: onTap == null ? 1 : 1.5),
              borderRadius: BorderRadius.circular(s.controlRadius)),
          child: Text(label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: Design.px(22),
                  fontWeight: FontWeight.w600,
                  color: onTap == null ? s.muted : s.text))));

  Widget _secondary(SurfaceStyle s, String label, VoidCallback onTap) => InkWell(
      borderRadius: BorderRadius.circular(s.controlRadius),
      onTap: onTap,
      child: Container(
          height: Design.px(62),
          alignment: Alignment.center,
          padding: EdgeInsets.symmetric(horizontal: Design.px(16)),
          decoration: BoxDecoration(
              border: Border.all(color: s.edge),
              borderRadius: BorderRadius.circular(s.controlRadius)),
          child: Text(label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: Design.px(20), color: s.muted))));
}
