import 'package:flutter/material.dart';

import '../controller/launcher_controller.dart';
import '../model/storage_cleaner.dart';
import '../theme/design_tokens.dart';
import '../theme/launcher_theme.dart';
import 'launcher_dialog.dart';
import 'uni_icon.dart';

/// 右下角 UNI 菜单的第四项入口。全局底栏开着时交给独立面板窗口渲染（同一个面板），
/// 否则在本窗口弹一张和「车辆信息」同规格的玻璃面板。
Future<void> showCleanerPanel(
    BuildContext context, LauncherController c) async {
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

/// sim f34：左「可清理」汇总卡（392 宽）+ 右类目列表，底部一条操作栏。
///
/// 设计稿是整页的 `scr-sheet`，自带标题栏；本项目把它挂在设置页的
/// 「垃圾清理」导航项里，外壳由 [SettingsScreen] 提供，这里只画内容区。
class CleanerPanel extends StatefulWidget {
  final LauncherController controller;
  const CleanerPanel({super.key, required this.controller});
  @override
  State<CleanerPanel> createState() => _CleanerPanelState();
}

class _CleanerPanelState extends State<CleanerPanel> {
  /// 本界面自己的勾选状态。原生只负责给出「默认是否勾选」和「能不能勾」。
  final Set<String> _selected = {};

  /// 用户手动关掉的类目：重新扫描后不再自动勾回来。
  ///
  /// 早先这里是「出现过的类目」都算，结果是清理完再扫一遍时，剩下的垃圾
  /// 一个都不会勾上——用户没做过选择，却被当成「他不要这些」。
  final Set<String> _deselected = {};
  int _rev = -1;
  bool _confirming = false;

  /// 清理完成的一次性反馈：f36 那张「清理完成」大圆环不做，改成一句 toast。
  /// 不这么做的话，清理结束那一刻界面只是数字变了，看不出「刚清完」。
  ///
  /// 不用「cleaning → 非 cleaning」直接判断：原生清完会在原地再统计一遍，
  /// 中间会短暂变成 `phase=scan / running=true`，那样这一跳就被吞掉了。
  /// 改成「这一轮见过 cleaning，等它彻底停下再报」。
  bool _cleanSeen = false;
  int _announcedAt = 0;

  LauncherController get controller => widget.controller;

  @override
  void initState() {
    super.initState();
    // 面板可能是在清理中途打开的：这种情况也要记住「正在清理」，
    // 否则结束那一下不会给完成提示。
    final initial = CleanerState.fromNative(controller.native.value);
    _cleanSeen = initial.cleaning;
    _announcedAt = initial.lastCleanAt;
    controller.native.addListener(_watchCompletion);
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

  @override
  void dispose() {
    controller.native.removeListener(_watchCompletion);
    super.dispose();
  }

  /// 清理从「进行中」落到「结束」时给一句反馈，替代设计稿 f36 的大圆环。
  void _watchCompletion() {
    final state = CleanerState.fromNative(controller.native.value);
    if (state.cleaning) {
      _cleanSeen = true;
      return;
    }
    // 原生清完会原地再统计一遍（phase=scan / running=true），等它彻底停下。
    if (!_cleanSeen || state.running) return;
    _cleanSeen = false;
    if (state.lastCleanAt == _announcedAt) return;
    _announcedAt = state.lastCleanAt;
    final bytes = state.lastCleanBytes;
    final stopped = _stopRequested;
    _stopRequested = false;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      showLauncherToast(
          context,
          stopped
              ? (bytes > 0 ? '已停止 · 释放 ${formatBytes(bytes)}' : '已停止清理')
              : (bytes > 0 ? '清理完成 · 释放 ${formatBytes(bytes)}' : '清理完成'));
    });
  }

  /// 用户是不是按过「停止」：停下之后原生照样会把已删的量记进 lastClean，
  /// 这时候说「清理完成」会误导。
  bool _stopRequested = false;

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
      if (_deselected.contains(category.id)) continue;
      if (category.defaultSelected) next.add(category.id);
    }
    // 已经没有体积的类目不再记「用户不要」：下次又长出来时该怎么勾怎么勾。
    final live = {
      for (final category in state.categories)
        if (category.bytes > 0) category.id
    };
    _deselected.removeWhere((id) => !live.contains(id));
    _selected
      ..clear()
      ..addAll(next);
    if (next.isEmpty) _confirming = false;
  }

  void _toggle(CleanerCategory category) {
    setState(() {
      _confirming = false;
      if (_selected.remove(category.id)) {
        _deselected.add(category.id);
      } else {
        _deselected.remove(category.id);
        _selected.add(category.id);
      }
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
            final selected = [
              for (final category in state.categories)
                if (_selected.contains(category.id)) category
            ];
            final selectedBytes =
                selected.fold<int>(0, (sum, category) => sum + category.bytes);
            // 设置页里是 1250 宽，两列正好；从 UNI 菜单弹出的面板只有 733 宽，
            // 两列会把右卡挤到 210 —— 那里改成上下堆叠、整块可滚。
            return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: LayoutBuilder(builder: (context, box) {
                    // 设置页里 1250 宽，左卡按设计稿 392；从 UNI 菜单弹出的面板
                    // 只有 733 宽，左卡收到 296 并且只留「可清理 + 存储占用」，
                    // 右卡自己滚 —— 上下堆叠会把类目列表顶出弹窗。
                    final wide = box.maxWidth >= Design.dz(760);
                    return Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          SizedBox(
                              width: Design.dz(wide ? 392 : 296),
                              child: _Summary(
                                  state: state,
                                  selectedBytes: selectedBytes,
                                  compact: !wide)),
                          SizedBox(width: Design.dz(wide ? 18.33 : 14)),
                          Expanded(
                              child: _ListCard(
                                  state: state,
                                  selected: _selected,
                                  iconFor: _iconFor,
                                  onToggle: _toggle)),
                        ]);
                  })),
                  SizedBox(height: Design.dz(14)),
                  _FootBar(
                      state: state,
                      selected: selected,
                      selectedBytes: selectedBytes,
                      confirming: _confirming,
                      onCancelConfirm: () =>
                          setState(() => _confirming = false),
                      onConfirm: () => setState(() => _confirming = true),
                      onClean: () => _clean(selected),
                      onStop: () {
                        _stopRequested = true;
                        controller.command('cleaner-cancel');
                      },
                      onGrant: _openPermission,
                      onRescan: () => controller.command('cleaner-scan')),
                ]);
          });
}

/// 左卡：`.cl-sum`（392 宽、25 圆角、196 度白 5%→1.6% 的渐变底）。
class _Summary extends StatelessWidget {
  final CleanerState state;
  final int selectedBytes;

  /// 窄屏（面板弹窗）里不等高拉伸：去掉 Spacer 与最小高度，跟着内容走。
  final bool compact;

  const _Summary(
      {required this.state, required this.selectedBytes, this.compact = false});

  @override
  Widget build(BuildContext context) {
    final s = SurfaceStyle.of(context);
    final total =
        state.cleanableBytes > 0 ? state.cleanableBytes : selectedBytes;
    final shown = total > 0 ? total : state.cleanableBytes;
    // 扫描 / 清理中：大字位临时让给百分比，把设计稿 f35 的雷达环并进这张卡。
    // 两屏分开画需要逐项回报，本项目原生给的是「阶段 + 百分比 + 当前项」，
    // 用大字百分比表达已经够看，也不必在页面之间跳。
    final percent = (state.progress * 100).round().clamp(0, 100);
    final running = state.running;
    final (value, unit) = running ? ('$percent', '%') : splitBytes(shown);
    final label = state.scanning
        ? '已扫描'
        : state.cleaning
            ? '清理中'
            : '可清理';
    final used = state.usedBytes;
    final capacity = state.totalBytes;
    final releaseFraction =
        capacity > 0 ? (shown / capacity).clamp(0.0, 1.0) : 0.0;
    final usedFraction =
        capacity > 0 ? ((used - shown).clamp(0, capacity) / capacity) : 0.0;
    final hit =
        state.categories.where((c) => c.available && c.bytes > 0).length;
    final last = lastCleanLabel(state.lastCleanAt);
    final note = state.scanning
        ? '正在遍历存储 · 完成后自动勾选安全项'
        : state.cleaning
            ? (state.purgeLabel.isEmpty ? '正在清理选中类目' : state.purgeLabel)
            : shown > 0
                ? '${state.categories.length} 个类目 · $hit 项命中'
                    '${last.isEmpty ? '' : ' · 上次清理 $last'}'
                : '已清理干净';
    return Container(
        padding: EdgeInsets.fromLTRB(
            Design.dz(24), Design.dz(22), Design.dz(24), Design.dz(22)),
        clipBehavior: Clip.hardEdge,
        decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(Design.dz(25)),
            border: Border.all(color: s.text.withValues(alpha: .08)),
            gradient: LinearGradient(
                begin: const Alignment(-.2, -1),
                end: const Alignment(.2, 1),
                colors: [
                  s.text.withValues(alpha: .05),
                  s.text.withValues(alpha: .016)
                ])),
        // 车内这块高度有限，字体回退到系统字体时内容会高出一截：内容不够
        // 高时用 minHeight 把「不会动的」压到底，够了就让它自己滚。
        child: LayoutBuilder(builder: (context, box) {
          final body =
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label.toUpperCase(),
                key: const ValueKey('cleaner-headline-label'),
                style: TextStyle(
                    fontSize: Design.dz(11.5),
                    fontWeight: FontWeight.w600,
                    letterSpacing: Design.dz(2),
                    color: s.muted)),
            SizedBox(height: Design.dz(8)),
            Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(value,
                      key: const ValueKey('cleaner-headline'),
                      style: TextStyle(
                          fontSize: Design.dz(compact ? 60 : 96),
                          fontWeight: FontWeight.w200,
                          height: .95,
                          letterSpacing: Design.dz(-.4),
                          color: s.text.withValues(alpha: .95))),
                  SizedBox(width: Design.dz(8)),
                  Text(unit,
                      style: TextStyle(
                          fontSize: Design.dz(compact ? 17 : 22),
                          fontWeight: FontWeight.w300,
                          color: s.muted))
                ]),
            SizedBox(height: Design.dz(8)),
            Text(note,
                key: const ValueKey('cleaner-headline-note'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: Design.dz(13.5), color: s.muted)),
            // 进度条：f35 那张雷达环不做，但「还在动」这件事必须有可见反馈，
            // 否则一次性快照的下法在扫描的十几秒里看着就是卡死。
            if (running) ...[
              SizedBox(height: Design.dz(12)),
              ClipRRect(
                  borderRadius: BorderRadius.circular(Design.dz(3)),
                  child: SizedBox(
                      height: Design.dz(4),
                      child: Stack(children: [
                        Positioned.fill(
                            child: ColoredBox(
                                color: s.text.withValues(alpha: .07))),
                        Positioned.fill(
                            child: FractionallySizedBox(
                                alignment: Alignment.centerLeft,
                                widthFactor: state.progress.clamp(0.02, 1.0),
                                child: DecoratedBox(
                                    decoration:
                                        BoxDecoration(gradient: s.accentFill))))
                      ]))),
            ],
            SizedBox(height: Design.dz(26)),
            _kv(s, '存储占用',
                capacity > 0 ? '${gbLabel(used)} / ${gbLabel(capacity)}' : '—',
                mono: true),
            SizedBox(height: Design.dz(10)),
            ClipRRect(
                borderRadius: BorderRadius.circular(Design.dz(3)),
                child: SizedBox(
                    height: Design.dz(6),
                    child: Row(children: [
                      if (releaseFraction > 0)
                        Expanded(
                            flex: (releaseFraction * 1000).round(),
                            child: DecoratedBox(
                                decoration:
                                    BoxDecoration(gradient: s.accentFill))),
                      if (usedFraction > 0)
                        Expanded(
                            flex: (usedFraction * 1000).round(),
                            child: ColoredBox(
                                color: s.text.withValues(alpha: .22))),
                      if (releaseFraction + usedFraction < 1)
                        Expanded(
                            flex: ((1 - releaseFraction - usedFraction) * 1000)
                                .round()
                                .clamp(1, 1000),
                            child: ColoredBox(
                                color: s.text.withValues(alpha: .06)))
                    ]))),
            SizedBox(height: Design.dz(11)),
            Row(children: [
              _legendDot(s, s.accent, '本次可释放'),
              SizedBox(width: Design.dz(18)),
              _legendDot(s, s.text.withValues(alpha: .22), '已占用')
            ]),
            // 窄屏（面板弹窗）只留「可清理 + 存储占用」：体积分布、四项统计
            // 在 733 宽的弹窗里会把类目列表顶到屏幕外。
            if (!compact) ...[
              SizedBox(height: Design.dz(26)),
              _kv(s, '体积分布', '按类目', tiny: true),
              SizedBox(height: Design.dz(11)),
              ClipRRect(
                  borderRadius: BorderRadius.circular(Design.dz(5)),
                  child: SizedBox(
                      height: Design.dz(9),
                      child: Row(children: [
                        for (final (index, group)
                            in cleanerGroupOrder.indexed) ...[
                          if (index > 0) const SizedBox(width: 2),
                          Expanded(
                              flex: _groupFlex(state, group),
                              child: ColoredBox(color: _groupColor(s, group)))
                        ]
                      ]))),
              SizedBox(height: Design.dz(13)),
              Wrap(spacing: Design.dz(16), runSpacing: Design.dz(8), children: [
                for (final group in cleanerGroupOrder)
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    Container(
                        width: Design.dz(6),
                        height: Design.dz(6),
                        decoration: BoxDecoration(
                            color: _groupColor(s, group),
                            borderRadius: BorderRadius.circular(Design.dz(2)))),
                    SizedBox(width: Design.dz(7)),
                    Text(
                        '${cleanerGroupLabels[group]} ${formatBytes(_groupBytes(state, group))}',
                        style:
                            TextStyle(fontSize: Design.dz(11), color: s.muted))
                  ])
              ]),
              SizedBox(height: Design.dz(24)),
              Row(children: [
                Expanded(child: _stat(s, '遍历条目', _thousands(state.scanned))),
                SizedBox(width: Design.dz(12)),
                Expanded(child: _stat(s, '命中类目', '$hit'))
              ]),
              SizedBox(height: Design.dz(14)),
              Row(children: [
                Expanded(
                    child: _stat(s, '可清理', splitBytes(shown).$1,
                        tail: splitBytes(shown).$2)),
                SizedBox(width: Design.dz(12)),
                Expanded(
                    child: _stat(
                        s, '扫描用时', (state.scanMs / 1000).toStringAsFixed(1),
                        tail: 's', dim: true))
              ]),
            ],
            if (compact) SizedBox(height: Design.dz(18)) else const Spacer(),
            Container(
                padding: EdgeInsets.only(top: Design.dz(16)),
                decoration: BoxDecoration(
                    border: Border(
                        top: BorderSide(color: s.text.withValues(alpha: .07)))),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('不会动的',
                          style: TextStyle(
                              fontSize: Design.dz(10.5),
                              letterSpacing: Design.dz(2),
                              color: s.muted)),
                      SizedBox(height: Design.dz(11)),
                      Wrap(
                          spacing: Design.dz(7),
                          runSpacing: Design.dz(7),
                          children: [
                            for (final keep in const [
                              '照片与行车记录',
                              '导航离线地图',
                              '用户媒体'
                            ])
                              _keep(s, keep)
                          ]),
                      SizedBox(height: Design.dz(13)),
                      Text(
                        '共 10 条 never 规则（含 OTA 包、系统备份、数据库），清单里勾不到也删不掉。'
                        '勾选「需确认」项前请核对；清理不可撤销。',
                        style: TextStyle(
                            fontSize: Design.dz(11.5),
                            height: 1.66,
                            color: s.text.withValues(alpha: .28)),
                      )
                    ])),
          ]);
          if (compact) return SingleChildScrollView(child: body);
          return SingleChildScrollView(
              child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: box.maxHeight),
                  child: IntrinsicHeight(child: body)));
        }));
  }

  static int _groupBytes(CleanerState state, String group) => state.categories
      .where((c) => _group(c) == group && c.available)
      .fold<int>(0, (sum, c) => sum + c.bytes);

  static int _groupFlex(CleanerState state, String group) {
    final total = state.categories
        .where((c) => c.available)
        .fold<int>(0, (sum, c) => sum + c.bytes);
    if (total <= 0) return 1;
    final value = _groupBytes(state, group);
    return (value <= 0 ? 1 : (value / total * 1000).round().clamp(1, 1000));
  }

  static String _group(CleanerCategory category) =>
      cleanerGroupOrder.contains(category.group) ? category.group : 'junk';

  static Color _groupColor(SurfaceStyle s, String group) => switch (group) {
        'cache' => s.accent.withValues(alpha: .8),
        'junk' => s.accent.withValues(alpha: .42),
        'leftover' => const Color(0x75FF5FA8),
        _ => s.text.withValues(alpha: .18),
      };

  static Widget _legendDot(SurfaceStyle s, Color color, String label) =>
      Row(mainAxisSize: MainAxisSize.min, children: [
        Container(
            width: Design.dz(6),
            height: Design.dz(6),
            decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        SizedBox(width: Design.dz(7)),
        Text(label, style: TextStyle(fontSize: Design.dz(11.5), color: s.muted))
      ]);

  static Widget _kv(SurfaceStyle s, String label, String value,
          {bool mono = false, bool tiny = false}) =>
      Row(children: [
        Text(label,
            style: TextStyle(
                fontSize: Design.dz(tiny ? 11.5 : 12.5),
                color: s.text.withValues(alpha: tiny ? .32 : .42))),
        const Spacer(),
        Flexible(
            child: Text(value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: Design.dz(tiny ? 11.5 : 12),
                    letterSpacing: Design.dz(.2),
                    color: s.text.withValues(alpha: tiny ? .32 : .42))))
      ]);

  static Widget _stat(SurfaceStyle s, String label, String value,
          {String? tail, bool dim = false}) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label,
            style: TextStyle(
                fontSize: Design.dz(10),
                letterSpacing: Design.dz(1.8),
                color: s.text.withValues(alpha: .28))),
        SizedBox(height: Design.dz(5)),
        Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(value,
                  style: TextStyle(
                      fontSize: Design.dz(23),
                      fontWeight: FontWeight.w200,
                      color: s.text.withValues(alpha: dim ? .6 : .88))),
              if (tail != null) ...[
                SizedBox(width: Design.dz(4)),
                Text(tail,
                    style: TextStyle(
                        fontSize: Design.dz(12),
                        fontWeight: FontWeight.w300,
                        color: s.muted))
              ]
            ])
      ]);

  static Widget _keep(SurfaceStyle s, String label) => Container(
      padding: EdgeInsets.symmetric(
          horizontal: Design.dz(9), vertical: Design.dz(4)),
      decoration: BoxDecoration(
          color: s.text.withValues(alpha: .025),
          border: Border.all(color: s.text.withValues(alpha: .09)),
          borderRadius: BorderRadius.circular(Design.dz(8))),
      child: Text(label,
          style: TextStyle(fontSize: Design.dz(11.5), color: s.muted)));
}

/// 右卡：`.cl-list`（白 2.8% 底、25 圆角，行 45 高）。
class _ListCard extends StatelessWidget {
  final CleanerState state;
  final Set<String> selected;
  final IconData Function(String id) iconFor;
  final ValueChanged<CleanerCategory> onToggle;

  const _ListCard(
      {required this.state,
      required this.selected,
      required this.iconFor,
      required this.onToggle});

  @override
  Widget build(BuildContext context) {
    final s = SurfaceStyle.of(context);
    final groups = <String, List<CleanerCategory>>{};
    for (final category in state.categories) {
      final group =
          cleanerGroupOrder.contains(category.group) ? category.group : 'junk';
      groups.putIfAbsent(group, () => []).add(category);
    }
    final rows = <Widget>[];
    // 重新扫描时列表里是上一轮的结果：先说清楚，别让人以为新数据已经出来了。
    if (state.scanning && state.categories.isNotEmpty) {
      rows.add(_hint(s, '正在重新扫描 · 下面是上一次的结果'));
      rows.add(SizedBox(height: Design.dz(10)));
    }
    for (final group in cleanerGroupOrder) {
      final items = groups[group];
      if (items == null || items.isEmpty) continue;
      if (rows.isNotEmpty) rows.add(SizedBox(height: Design.dz(9)));
      rows.add(_header(s, group, items.length));
      for (final item in items) {
        rows.add(_row(s, item));
      }
    }
    return Container(
        padding: EdgeInsets.fromLTRB(
            Design.dz(20), Design.dz(14), Design.dz(20), Design.dz(8)),
        decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(Design.dz(25)),
            border: Border.all(color: s.text.withValues(alpha: .08)),
            color: s.text.withValues(alpha: .028)),
        child: rows.isEmpty
            ? Center(
                child: Text(state.scanning ? '正在扫描…' : '还没有扫描结果',
                    style: TextStyle(fontSize: Design.dz(14), color: s.muted)))
            : ListView(
                key: const PageStorageKey('cleaner-list-scroll'),
                padding: EdgeInsets.zero,
                children: rows));
  }

  Widget _hint(SurfaceStyle s, String text) => Container(
      padding: EdgeInsets.symmetric(
          horizontal: Design.dz(10), vertical: Design.dz(7)),
      decoration: BoxDecoration(
          color: s.accent.withValues(alpha: .08),
          borderRadius: BorderRadius.circular(Design.dz(9))),
      child: Text(text,
          style: TextStyle(
              fontSize: Design.dz(11.5),
              color: s.accent.withValues(alpha: .8))));

  Widget _header(SurfaceStyle s, String group, int count) => Row(children: [
        Text(cleanerGroupLabels[group] ?? group,
            style: TextStyle(
                fontSize: Design.dz(10.5),
                letterSpacing: Design.dz(2),
                color: s.muted)),
        SizedBox(width: Design.dz(10)),
        Expanded(
            child: Container(height: 1, color: s.text.withValues(alpha: .055))),
        SizedBox(width: Design.dz(10)),
        Text('$count 项',
            style: TextStyle(
                fontSize: Design.dz(10.5),
                letterSpacing: Design.dz(.6),
                color: s.muted))
      ]);

  Widget _row(SurfaceStyle s, CleanerCategory category) {
    final selectable = category.available && category.bytes > 0;
    final isSelected = selected.contains(category.id);
    return Semantics(
        checked: isSelected,
        enabled: selectable && !state.running,
        child: InkWell(
            key: ValueKey('cleaner-item-${category.id}'),
            onTap:
                selectable && !state.running ? () => onToggle(category) : null,
            child: Opacity(
                opacity: selectable ? 1 : .55,
                child: Container(
                    height: Design.dz(45),
                    decoration: BoxDecoration(
                        border: Border(
                            bottom: BorderSide(
                                color: s.text.withValues(alpha: .045)))),
                    child: Row(children: [
                      _check(s, isSelected && selectable, selectable),
                      SizedBox(width: Design.dz(12)),
                      SizedBox(
                          width: Design.dz(26),
                          height: Design.dz(26),
                          child: Center(
                              child: DesignIcon(iconFor(category.id),
                                  size: Design.dz(21),
                                  color: s.text.withValues(alpha: .34)))),
                      SizedBox(width: Design.dz(12)),
                      Expanded(
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                            Text(category.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    fontSize: Design.dz(14.5),
                                    height: 1.2,
                                    color: s.text.withValues(
                                        alpha: selectable ? .86 : .5))),
                            if (category.note.isNotEmpty) ...[
                              SizedBox(height: Design.dz(2)),
                              Text(category.note,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                      fontSize: Design.dz(11), color: s.muted))
                            ]
                          ])),
                      if (category.needsReview) ...[
                        _risk(s, '需确认', const Color(0xD1FF5FA8),
                            const Color(0x42FF5FA8)),
                        SizedBox(width: Design.dz(10)),
                      ] else if (!category.verified) ...[
                        _risk(s, '待确认', const Color(0xD1FFB057),
                            const Color(0x42FFB057)),
                        SizedBox(width: Design.dz(10)),
                      ],
                      SizedBox(
                          width: Design.dz(86),
                          child: Text(
                              category.bytes > 0
                                  ? formatBytes(category.bytes)
                                  : '—',
                              textAlign: TextAlign.right,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontSize: Design.dz(15),
                                  fontWeight: FontWeight.w300,
                                  color: s.text.withValues(
                                      alpha: category.bytes > 0 ? .8 : .3))))
                    ])))));
  }

  Widget _check(SurfaceStyle s, bool on, bool enabled) => Container(
      width: Design.dz(21),
      height: Design.dz(21),
      decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: on ? s.accentFill : null,
          border: on ? null : Border.all(color: s.text.withValues(alpha: .2))),
      child: on
          ? Icon(Icons.check, size: Design.dz(13), color: s.accentText)
          : null);

  Widget _risk(SurfaceStyle s, String label, Color fg, Color border) =>
      Container(
          padding: EdgeInsets.symmetric(
              horizontal: Design.dz(7), vertical: Design.dz(3)),
          decoration: BoxDecoration(
              color: border.withValues(alpha: .12),
              border: Border.all(color: border),
              borderRadius: BorderRadius.circular(Design.dz(7))),
          child: Text(label,
              style: TextStyle(
                  fontSize: Design.dz(10),
                  height: 1,
                  letterSpacing: Design.dz(1),
                  color: fg)));
}

/// 底部操作栏（`.cl-foot` 62 高 / `.cl-go` 渐变主按钮 / `.cl-ghost` 描边按钮）。
class _FootBar extends StatelessWidget {
  final CleanerState state;
  final List<CleanerCategory> selected;
  final int selectedBytes;
  final bool confirming;
  final VoidCallback onCancelConfirm;
  final VoidCallback onConfirm;
  final VoidCallback onClean;
  final VoidCallback onStop;
  final VoidCallback onGrant;
  final VoidCallback onRescan;

  const _FootBar(
      {required this.state,
      required this.selected,
      required this.selectedBytes,
      required this.confirming,
      required this.onCancelConfirm,
      required this.onConfirm,
      required this.onClean,
      required this.onStop,
      required this.onGrant,
      required this.onRescan});

  @override
  Widget build(BuildContext context) {
    final s = SurfaceStyle.of(context);
    final waitingPermission = !state.storageGranted;
    final last = lastCleanLabel(state.lastCleanAt);
    final note = [
      if (state.error.isNotEmpty) state.error,
      if (state.rulesIssue.isNotEmpty) state.rulesIssue,
      if (!state.running && state.lastCleanBytes > 0 && last.isNotEmpty)
        '上次清理 $last，释放 ${formatBytes(state.lastCleanBytes)}',
      if (state.scanLabel.isNotEmpty) state.scanLabel,
    ].join(' · ');
    final status = waitingPermission
        ? '正在获取存储权限…'
        : state.cleaning && state.purgeTotal > 0
            ? state.purgeLabel
            : state.running
                ? '${state.phaseLabel} ${(state.progress * 100).round()}%'
                    '${state.current.isEmpty ? '' : ' · ${state.current}'}'
                : selectedBytes > 0
                    ? '已选 ${selected.length} 项 · ${formatBytes(selectedBytes)}'
                    : '没有选中任何内容';
    final canClean = !state.running && !waitingPermission && selectedBytes > 0;
    return Container(
        height: Design.dz(62),
        padding: EdgeInsets.symmetric(horizontal: Design.dz(18)),
        decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(Design.dz(18)),
            border: Border.all(color: s.text.withValues(alpha: .08)),
            color: s.text.withValues(alpha: .035)),
        child: Row(children: [
          Container(
              width: Design.dz(6),
              height: Design.dz(6),
              decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: state.running || state.error.isNotEmpty
                      ? s.accent
                      : s.text.withValues(alpha: .3))),
          SizedBox(width: Design.dz(9)),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                Text(status,
                    key: const ValueKey('cleaner-status'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: Design.dz(13), color: s.muted)),
                if (note.isNotEmpty) ...[
                  SizedBox(height: Design.dz(2)),
                  Text(note,
                      key: const ValueKey('cleaner-note'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style:
                          TextStyle(fontSize: Design.dz(11.5), color: s.muted))
                ]
              ])),
          SizedBox(width: Design.dz(12)),
          if (waitingPermission) ...[
            _ghost(s, '重试授权', onGrant),
            SizedBox(width: Design.dz(10))
          ],
          if (state.running) ...[
            _ghost(s, state.cleaning ? '停止清理' : '停止扫描', onStop),
            SizedBox(width: Design.dz(10))
          ],
          // 设计稿把「重新扫描」放在页头，本页头的按钮位被设置页外壳占着，
          // 挪到底栏：扫完想再扫一次不必退出重进。确认态下不给，免得
          // 一边问「确认清理」一边又允许重扫，把勾选状态搅乱。
          if (!state.running && !waitingPermission && !confirming) ...[
            _ghost(s, '重新扫描', onRescan),
            SizedBox(width: Design.dz(10))
          ],
          if (confirming) ...[
            _ghost(s, '取消', onCancelConfirm),
            SizedBox(width: Design.dz(10))
          ],
          _primary(
              s,
              confirming
                  ? '确认清理 ${formatBytes(selectedBytes)}'
                  : waitingPermission
                      ? '等待存储权限'
                      : state.running
                          ? (state.cleaning ? '清理中…' : '扫描中…')
                          : selectedBytes > 0
                              ? '清理 ${formatBytes(selectedBytes)}'
                              : '暂无可清理内容',
              canClean ? (confirming ? onClean : onConfirm) : null)
        ]));
  }

  /// `.cl-go`：44 高、22 圆角、主题色渐变、深色字。
  Widget _primary(SurfaceStyle s, String label, VoidCallback? onTap) => InkWell(
      borderRadius: BorderRadius.circular(Design.dz(22)),
      onTap: onTap,
      child: Container(
          height: Design.dz(44),
          padding: EdgeInsets.symmetric(horizontal: Design.dz(26)),
          alignment: Alignment.center,
          decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(Design.dz(22)),
              gradient: onTap == null ? null : s.accentFill,
              color: onTap == null ? s.text.withValues(alpha: .06) : null,
              boxShadow: onTap == null
                  ? null
                  : [
                      BoxShadow(
                          color: s.accent.withValues(alpha: .55),
                          blurRadius: Design.dz(26),
                          spreadRadius: -Design.dz(12),
                          offset: Offset(0, Design.dz(10)))
                    ]),
          child: Text(label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: Design.dz(16),
                  fontWeight: FontWeight.w600,
                  color: onTap == null ? s.muted : s.accentText))));

  /// `.cl-ghost`：42 高、21 圆角、白 12% 描边。
  Widget _ghost(SurfaceStyle s, String label, VoidCallback onTap) => InkWell(
      borderRadius: BorderRadius.circular(Design.dz(21)),
      onTap: onTap,
      child: Container(
          height: Design.dz(42),
          padding: EdgeInsets.symmetric(horizontal: Design.dz(18)),
          alignment: Alignment.center,
          decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(Design.dz(21)),
              color: s.text.withValues(alpha: .04),
              border: Border.all(color: s.text.withValues(alpha: .12))),
          child: Text(label,
              maxLines: 1,
              style: TextStyle(fontSize: Design.dz(14.5), color: s.muted))));
}

/// 「4.01」/「862」这类拆成数字与单位两段：大字只放数字。
(String, String) splitBytes(int bytes) {
  if (bytes <= 0) return ('0', 'MB');
  if (bytes >= 1024 * 1024 * 1024) {
    return ((bytes / (1024 * 1024 * 1024)).toStringAsFixed(2), 'GB');
  }
  if (bytes >= 1024 * 1024) {
    return ((bytes / (1024 * 1024)).round().toString(), 'MB');
  }
  return ((bytes / 1024).round().toString(), 'KB');
}

String gbLabel(int bytes) =>
    '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';

String _thousands(int value) {
  final text = value.toString();
  final buffer = StringBuffer();
  for (var i = 0; i < text.length; i++) {
    if (i > 0 && (text.length - i) % 3 == 0) buffer.write(',');
    buffer.write(text[i]);
  }
  return buffer.toString();
}
