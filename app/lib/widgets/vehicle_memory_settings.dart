import 'dart:typed_data';

import 'package:flutter/material.dart';
import '../controller/launcher_controller.dart';
import '../theme/design_tokens.dart';
import '../theme/launcher_type.dart';
import '../theme/launcher_theme.dart';
import 'launcher_dialog.dart';
import 'setting_block.dart';
import 'choice_button.dart';

/// 记忆配置：启动桌面时把驾驶模式与自动启停恢复到固定位置。
///
/// 两项各自独立开关，关掉的那一项完全不发送任何车辆写入，也不会因为另一项
/// 生效而被牵连。取值来自原车只读通道（DID 0x21403018 / PA 0x2170f200），
/// 写入走 DM_FUNC_DRIVE_MODE_SELECT 与 SETTING_FUNC_ENGINE_STOP_START。
class VehicleMemorySettings extends StatelessWidget {
  final LauncherController controller;
  const VehicleMemorySettings({super.key, required this.controller});

  static const _modeLabels = {
    'ECO': '经济',
    'COMFORT': '舒适',
    'DYNAMIC': '运动',
    'INDIVIDUAL': '自定义',
    'XC': '越野',
    'HDC': '陡坡缓降',
    'PURE': '纯电',
    'HYBRID': '混动',
    'POWER': '动力',
    'RACE': '赛道',
    'ECO_HEV_PHEV': '插混经济',
    'COMFORT_HEV': '插混舒适',
  };

  /// 开机记忆只该出现「用得上的主模式」，顺序固定。
  ///
  /// `memory.driveModes` 是 `CommandPolicy.DRIVE_MODES`——协议允许写入的**全集**
  /// （12 个）。直接铺出来会冒出 INDIVIDUAL（自定义参数集）、HDC（陡坡缓降，
  /// 是个功能开关）和 XC（地形模式）这类不该开机自动切进去的项。这里只收主模式，
  /// 并限三个，和原码的三颗按钮对齐。
  static const _memoryModes = [
    'ECO',
    'COMFORT',
    'DYNAMIC',
    'PURE',
    'HYBRID',
    'POWER'
  ];
  static const _memoryModeLimit = 3;

  static String _label(String mode) => _modeLabels[mode] ?? mode;

  static String _stateLabel(Object? raw) {
    switch ('$raw') {
      case 'queued':
        return '等待发送';
      case 'sent':
        return '已发送，等待读回';
      case 'confirmed':
        return '已应用';
      case 'unchanged':
        return '已是记忆值';
      case 'failed':
        return '未生效';
      case 'timeout':
        return '读回超时';
      case 'skipped':
        return '已跳过';
      default:
        return '';
    }
  }

  @override
  Widget build(BuildContext context) =>
      ValueListenableBuilder<Map<String, dynamic>>(
          valueListenable: controller.native,
          builder: (context, native, _) {
            final c = controller, s = SurfaceStyle.of(context);
            Map<String, dynamic> map(Object? value) =>
                value is Map ? Map<String, dynamic>.from(value) : {};

            final memory = map(native['vehicleMemory']),
                vehicle = map(native['vehicle']),
                settings = map(vehicle['settings']),
                drive = map(settings['driveMode']),
                stop = map(settings['startStop']),
                outcomes = map(vehicle['memory']),
                driveOutcome = map(outcomes['driveMode']),
                stopOutcome = map(outcomes['startStop']);

            final boot = map(native['bootLaunch']),
                bootEnabled = boot['enabled'] == true,
                plans = <Map<String, dynamic>>[
                  for (final raw in (boot['plans'] is List
                      ? boot['plans'] as List
                      : const []))
                    if (raw is Map) Map<String, dynamic>.from(raw)
                ],
                appsById = <String, Map<String, dynamic>>{
                  for (final raw in (native['apps'] is List
                      ? native['apps'] as List
                      : const []))
                    if (raw is Map && raw['id'] is String)
                      raw['id'] as String: Map<String, dynamic>.from(raw)
                };

            final live = drive['supported'] is List &&
                    (drive['supported'] as List).isNotEmpty
                ? drive['supported'] as List
                : memory['driveModes'] is List
                    ? memory['driveModes'] as List
                    : const [];
            final available = <String>{
              for (final raw in live)
                if (raw is String && raw.isNotEmpty) raw
            };
            final target = '${memory['driveMode'] ?? ''}';
            final modes = <String>[
              for (final mode in _memoryModes)
                if (available.contains(mode)) mode,
            ];
            if (modes.isEmpty) {
              // 少见的车型一个主模式都没报：退回原车列表，同样只留三个。
              modes.addAll(available.take(_memoryModeLimit));
            } else if (modes.length > _memoryModeLimit) {
              modes.removeRange(_memoryModeLimit, modes.length);
            }
            if (target.isNotEmpty && !modes.contains(target)) {
              // 记忆值不在前三颗里也要露出来，否则选中态整个消失、看着像没设置成功。
              if (modes.length >= _memoryModeLimit) modes.removeLast();
              modes.add(target);
            }

            final driveEnabled = memory['driveModeEnabled'] == true,
                stopEnabled = memory['startStopEnabled'] == true,
                stopTarget = memory['startStop'] != false,
                demo = native['demo'] == true,
                connected = vehicle['connected'] == true;

            final currentMode =
                drive['readable'] == true ? '${drive['current']}' : null;
            final currentStop =
                stop['readable'] == true ? stop['current'] == true : null;

            // sim f37：两列网格。驾驶模式 / 自动启停 一行，开机自动播放 / 开机无线 adb
            // 一行，开机自启动横跨两列。原来那句"记忆配置"总说明块在设计稿里不存在，
            // 说明下放到各块副标题，省掉一整块高度。
            return SingleChildScrollView(
                key: const PageStorageKey('vehicle-memory-scroll'),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                                child: _driveCard(context, c, s,
                                    enabled: driveEnabled,
                                    modes: modes,
                                    target: target,
                                    supported: drive['supported'],
                                    outcome: driveOutcome,
                                    connected: connected,
                                    current: currentMode)),
                            SizedBox(width: Design.dz(12)),
                            Expanded(
                                child: _stopCard(context, c, s,
                                    enabled: stopEnabled,
                                    stopTarget: stopTarget,
                                    outcome: stopOutcome,
                                    current: currentStop)),
                          ]),
                      SizedBox(height: Design.dz(12)),
                      // 两张卡高度对齐：IntrinsicHeight 把同一行的卡拉到等高，
                      // 否则一块长一块短，格子看起来是歪的。
                      IntrinsicHeight(
                          child: Row(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                            Expanded(
                                child: _autoPlayCard(context, c, s,
                                    native['integrationPreferences'])),
                            SizedBox(width: Design.dz(12)),
                            Expanded(
                                child: _wirelessAdbCard(
                                    context, c, s, native['wirelessAdb'])),
                          ])),
                      SizedBox(height: Design.dz(12)),
                      _bootBlock(context, c, s, bootEnabled, plans, appsById,
                          demo: demo, boot: boot),
                    ]));
          });

  /// 驾驶模式卡片（与自动启停并排，左）。
  Widget _driveCard(BuildContext context, LauncherController c, SurfaceStyle s,
      {required bool enabled,
      required List<String> modes,
      required String target,
      required Object? supported,
      required Map<String, dynamic> outcome,
      required bool connected,
      required String? current}) {
    final supportedModes =
        supported is List && supported.isNotEmpty ? supported : null;
    return SettingBlock(
        title: '驾驶模式',
        // sim f37：开关在标题行右端，说明在标题下方。
        note: _note(outcome, current == null ? null : _label(current), '当前：'),
        trailing: DesignSwitch(
            key: const ValueKey('memory-drive-mode-enabled'),
            value: enabled,
            onChanged: (v) =>
                c.command('memory-drive-mode-enabled', enabled: v)),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (modes.isEmpty)
            Text('原车尚未报告可用的驾驶模式',
                style: TextStyle(color: s.muted, fontSize: Design.px(18)))
          else
            Wrap(spacing: Design.px(12), runSpacing: Design.px(12), children: [
              for (final mode in modes)
                SizedBox(
                    width: Design.dz(86),
                    child: ChoiceButton(
                        key: ValueKey('memory-mode-$mode'),
                        height: 42,
                        selected: mode == target,
                        onPressed: () =>
                            c.command('memory-drive-mode-target', value: mode),
                        child: Text(_label(mode),
                            style: TextStyle(fontSize: Design.dz(14)))))
            ]),
          if (supportedModes == null)
            Padding(
                padding: EdgeInsets.only(top: Design.dz(9)),
                child: Text('原车暂未报告可用的驾驶模式，先列出全部；写入前仍会按原车支持列表校验。',
                    style: TextStyle(
                        color: s.muted,
                        fontSize: Design.dz(11.5),
                        height: LauncherType.lineLoose))),
          SizedBox(height: Design.dz(6)),
          // 设计稿把「立即应用」放在本块底部（原来是两根独立全宽按钮），
          // 链路地址跟在右边，一眼能对上这条写入走的是哪个 DID。
          Row(children: [
            // 设计稿 `.tbtn`：accent 15 号纯文字。之前用 `TextButton`，被主题的
            // `minimumSize: 60` 撑成一枚 60 高的胶囊，字还是 `muted` 灰——
            // 既占了整页三分之一的多余高度，在暗夜上也几乎看不清。
            DesignTextAction('立即应用驾驶模式',
                key: const ValueKey('memory-apply-drive-mode'),
                onPressed: enabled && target.isNotEmpty
                    ? () => c.command('memory-apply-now', value: 'driveMode')
                    : null),
            const Spacer(),
            Text('0x22010100 → 0x21403018',
                style: TextStyle(fontSize: Design.dz(10.5), color: s.muted))
          ]),
        ]));
  }

  /// 自动启停卡片（与驾驶模式并排，右）。
  Widget _stopCard(BuildContext context, LauncherController c, SurfaceStyle s,
      {required bool enabled,
      required bool stopTarget,
      required Map<String, dynamic> outcome,
      required bool? current}) {
    return SettingBlock(
        title: '自动启停',
        note: _note(
            outcome,
            current == null
                ? null
                : current
                    ? '开启'
                    : '关闭',
            '当前：'),
        trailing: DesignSwitch(
            key: const ValueKey('memory-start-stop-enabled'),
            value: enabled,
            onChanged: (v) =>
                c.command('memory-start-stop-enabled', enabled: v)),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            for (final (index, option) in [(true, '开启'), (false, '关闭')].indexed)
              Expanded(
                  child: Padding(
                      padding:
                          EdgeInsets.only(right: index == 0 ? Design.dz(9) : 0),
                      child: ChoiceButton(
                          key: ValueKey('memory-start-stop-${option.$1}'),
                          height: 42,
                          selected: option.$1 == stopTarget,
                          onPressed: () => c.command('memory-start-stop-target',
                              value: option.$1 ? 'on' : 'off'),
                          child: Text(option.$2,
                              style: TextStyle(fontSize: Design.dz(14))))))
          ]),
          // 文字链接自带 4 的上下内边距；这里再留 8，不然会贴着上面按钮的下沿。
          SizedBox(height: Design.dz(8)),
          Align(
              alignment: Alignment.centerLeft,
              child: DesignTextAction('立即应用启停设置',
                  key: const ValueKey('memory-apply-start-stop'),
                  onPressed: enabled
                      ? () => c.command('memory-apply-now', value: 'startStop')
                      : null)),
          Text('写入 0x20020100，读回 0x2170f200 校验；原车未报告可用值时只记不改。',
              style: TextStyle(
                  fontSize: Design.dz(11.5),
                  color: s.muted,
                  height: LauncherType.lineLoose)),
        ]));
  }

  /// 开机自动播放音乐：原本在「导航与媒体」里，挪进记忆配置，和自启动计划放一起。
  Widget _autoPlayCard(BuildContext context, LauncherController c,
      SurfaceStyle s, Object? preferences) {
    final prefs = preferences is Map
        ? Map<String, dynamic>.from(preferences)
        : <String, dynamic>{};
    final enabled = prefs['autoPlayMusic'] == true;
    return SettingBlock(
        title: '开机自动播放音乐',
        note: '启动后先拉起关联播放器，约 12 秒后恢复播放；播放器不会留在前台',
        trailing: DesignSwitch(
            key: const ValueKey('auto-play-music'),
            value: enabled,
            onChanged: (v) => c.command('auto-play-music', enabled: v)),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('关联播放器在「导航与媒体」里选择。请在播放器中先播放一首歌曲并授权媒体访问。',
              style: TextStyle(
                  color: s.muted,
                  fontSize: Design.px(17),
                  height: LauncherType.lineLoose)),
        ]));
  }

  /// 开机自动启动无线 adb：把 adbd 拉到 5555，PC 直接 adb connect。
  Widget _wirelessAdbCard(
      BuildContext context, LauncherController c, SurfaceStyle s, Object? raw) {
    final adb =
        raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};
    final enabled = adb['enabled'] == true,
        state = '${adb['state'] ?? (enabled ? 'idle' : 'off')}',
        address = '${adb['address'] ?? ':5555'}',
        reason = '${adb['reason'] ?? ''}',
        port = adb['port'] ?? 5555,
        bridge = adb['bridge'] != false,
        attempts = adb['attempt'] is int ? adb['attempt'] as int : 0;
    const labels = {
      'ready': '已就绪',
      'pending': '等待中',
      'blocked': '被系统拦下',
      'failed': '执行失败',
      'idle': '待执行',
      'missing': '缺少桥组件',
      'off': '不生效',
    };
    final detail = switch (state) {
      'ready' => 'adbd 已在 $port 端口监听 · adb connect $address',
      'pending' => reason.isEmpty
          ? '已通知桥组件，等 adbd 在 $port 端口监听'
          : '已通知桥组件，等 adbd 在 $port 端口监听 · $reason',
      'blocked' || 'failed' => reason.isEmpty ? '系统没有允许修改调试端口' : reason,
      'missing' =>
        reason.isEmpty ? '还要装同签名的小桥 UNI-AdbBridge（uid 1000）才能改调试端口' : reason,
      'off' => '打开后每次开机自动把无线 adb 拉到 $port 端口，PC 直接 adb connect',
      _ => '开机后自动尝试，失败每 20 秒重试（最多 6 次）',
    };
    return SettingBlock(
        title: '开机自动启动无线 adb',
        note: detail,
        trailing: DesignSwitch(
            key: const ValueKey('wireless-adb-enabled'),
            value: enabled,
            onChanged: (v) => c.command('wireless-adb-enabled', enabled: v)),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          // sim f37：状态标签，adb 监听成功时是 accent 小胶囊。
          Container(
              height: Design.dz(24),
              padding: EdgeInsets.symmetric(horizontal: Design.dz(9)),
              decoration: BoxDecoration(
                  color: s.accent.withValues(alpha: .07),
                  borderRadius: BorderRadius.circular(Design.dz(8)),
                  border: Border.all(color: s.accent.withValues(alpha: .26))),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Container(
                    width: Design.dz(5),
                    height: Design.dz(5),
                    decoration:
                        BoxDecoration(shape: BoxShape.circle, color: s.accent)),
                SizedBox(width: Design.dz(6)),
                Text('adb ${labels[state] ?? state} · $port 监听',
                    style: TextStyle(fontSize: Design.dz(12), color: s.accent))
              ])),
          SizedBox(height: Design.dz(10)),
          Row(children: [
            if (attempts > 0)
              Text('已尝试 $attempts 次',
                  style: TextStyle(color: s.muted, fontSize: Design.px(16))),
            if (!bridge)
              Text('桥组件未安装',
                  style: TextStyle(color: s.accent, fontSize: Design.px(16))),
            const Spacer(),
            DesignTextAction('立即开启无线 adb',
                key: const ValueKey('wireless-adb-run'),
                chevron: false,
                onPressed: () => c.command('wireless-adb-run')),
          ]),
        ]));
  }

  String _note(Map<String, dynamic> field, String? current, String present) {
    final state = _stateLabel(field['state']);
    final reason = '${field['reason'] ?? ''}';
    final parts = <String>[
      current == null ? '当前值尚未读到' : '$present$current',
      if (state.isNotEmpty) '启动应用：$state',
      if (reason.isNotEmpty) reason,
    ];
    return parts.join(' · ');
  }

  /// 开机自启动：标题行 + 计划小卡（`.plan`）+ 启动执行顺序时间轴。
  ///
  /// sim f37 把「一行一个计划」压成四张并排的 64 高小卡，开关挪到标题行右端；
  /// 时间轴的节点直接用计划里的「开机后第几秒」，不编造设计稿上那两个
  /// +0.8s / +1.2s —— 那两条是「驾驶模式」「自动启停」的实际耗时，本项目没测。
  Widget _bootBlock(
      BuildContext context,
      LauncherController c,
      SurfaceStyle s,
      bool enabled,
      List<Map<String, dynamic>> plans,
      Map<String, Map<String, dynamic>> appsById,
      {required bool demo,
      required Map<String, dynamic> boot}) {
    String label(Map<String, dynamic> plan) {
      final app = appsById[plan['id']];
      return app == null ? '${plan['package'] ?? plan['id']}' : c.appName(app);
    }

    final maxDelay = boot['maxDelay'] is int ? boot['maxDelay'] as int : 600;
    final sorted = [...plans]..sort((a, b) {
        final left = a['delay'] is int ? a['delay'] as int : 0;
        final right = b['delay'] is int ? b['delay'] as int : 0;
        return left.compareTo(right);
      });
    return SettingBlock(
        title: '开机自启动',
        note: '以开机时刻为基准，桌面进程晚起来也能补上'
            '${enabled ? '' : ' · 当前不生效'}',
        trailing: DesignSwitch(
            key: const ValueKey('boot-launch-enabled'),
            value: enabled,
            onChanged: (v) => c.command('boot-launch-enabled', enabled: v)),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SizedBox(height: Design.dz(2)),
          SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: [
                for (final plan in sorted) ...[
                  _planTile(c, s, plan, name: label(plan), demo: demo),
                  SizedBox(width: Design.dz(10)),
                ],
                _addPlanTile(context, c, appsById, maxDelay, s),
              ])),
          SizedBox(height: Design.dz(22)),
          _bootTimeline(s, sorted, label),
        ]));
  }

  /// 一张计划卡：`.plan`（168×64、14 圆角、白 2.2% 底）。
  Widget _planTile(
      LauncherController c, SurfaceStyle s, Map<String, dynamic> plan,
      {required String name, required bool demo}) {
    final state = '${plan['state'] ?? ''}';
    final reason = '${plan['reason'] ?? ''}'.trim();
    return Tooltip(
        message: [
          timing(plan['delay']),
          _bootState(state),
          if (reason.isNotEmpty) reason
        ].where((part) => part.isNotEmpty).join(' · '),
        child: Container(
            key: ValueKey('boot-plan-${plan['key']}'),
            width: Design.dz(168),
            height: Design.dz(64),
            padding: EdgeInsets.fromLTRB(
                Design.dz(14), Design.dz(9), Design.dz(8), Design.dz(9)),
            decoration: BoxDecoration(
                color: s.text.withValues(alpha: .022),
                border: Border.all(color: s.text.withValues(alpha: .08)),
                borderRadius: BorderRadius.circular(Design.dz(14))),
            child: Row(children: [
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                    Text(timing(plan['delay']),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: Design.dz(11),
                            letterSpacing: Design.dz(1.4),
                            color: s.text.withValues(alpha: .34))),
                    SizedBox(height: Design.dz(5)),
                    Text(name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: Design.dz(15),
                            color: s.text.withValues(
                                alpha: state == 'failed' ? .5 : .82)))
                  ])),
              Column(mainAxisSize: MainAxisSize.min, children: [
                _tileIcon(
                    key: ValueKey('boot-plan-run-${plan['key']}'),
                    icon: Icons.play_arrow_rounded,
                    tooltip: '立刻启动一次',
                    color: demo ? s.disabled : s.accent,
                    onTap: demo
                        ? null
                        : () => c.command('boot-launch-run',
                            value: '${plan['key']}')),
                SizedBox(height: Design.dz(4)),
                _tileIcon(
                    key: ValueKey('boot-plan-remove-${plan['key']}'),
                    icon: Icons.close_rounded,
                    tooltip: '删除计划',
                    color: s.text.withValues(alpha: .34),
                    onTap: () => c.command('boot-launch-remove',
                        value: '${plan['key']}'))
              ])
            ])));
  }

  Widget _tileIcon(
          {required Key key,
          required IconData icon,
          required String tooltip,
          required Color color,
          VoidCallback? onTap}) =>
      Tooltip(
          message: tooltip,
          child: InkWell(
              key: key,
              borderRadius: BorderRadius.circular(Design.dz(8)),
              onTap: onTap,
              child: SizedBox(
                  width: Design.dz(22),
                  height: Design.dz(20),
                  child: Icon(icon, size: Design.dz(16), color: color))));

  /// 「＋ 添加计划」小卡（`.plan.add`，虚线框在 Flutter 里用弱实线代替）。
  Widget _addPlanTile(
          BuildContext context,
          LauncherController c,
          Map<String, Map<String, dynamic>> appsById,
          int maxDelay,
          SurfaceStyle s) =>
      InkWell(
          key: const ValueKey('boot-launch-add'),
          borderRadius: BorderRadius.circular(Design.dz(14)),
          onTap: () => _addPlan(context, c, appsById, maxDelay),
          child: Container(
              width: Design.dz(104),
              height: Design.dz(64),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                  border: Border.all(color: s.text.withValues(alpha: .16)),
                  borderRadius: BorderRadius.circular(Design.dz(14))),
              child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text('＋',
                        style: TextStyle(
                            fontSize: Design.dz(16),
                            color: s.text.withValues(alpha: .4))),
                    SizedBox(height: Design.dz(3)),
                    Text('添加计划',
                        style: TextStyle(
                            fontSize: Design.dz(12.5),
                            color: s.text.withValues(alpha: .4)))
                  ])));

  /// 启动执行顺序：一条渐隐细线 + 等距节点。
  Widget _bootTimeline(SurfaceStyle s, List<Map<String, dynamic>> plans,
      String Function(Map<String, dynamic>) label) {
    final nodes = <(String, String, bool)>[
      ('0 s', '桌面启动', false),
      for (final plan in plans)
        (
          '+${plan['delay'] is int ? plan['delay'] : 0} s',
          label(plan),
          '${plan['state'] ?? ''}' == 'failed'
        ),
    ];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text('启动执行顺序',
                style: TextStyle(
                    fontSize: Design.dz(19), fontWeight: FontWeight.w500)),
            const Spacer(),
            Text('以开机时刻为基准 · 桌面进程晚起会按序补齐',
                style: TextStyle(
                    fontSize: Design.dz(11.5),
                    color: s.text.withValues(alpha: .3)))
          ]),
      SizedBox(height: Design.dz(22)),
      // 一个节点（还没加计划）时不能按「等分居中」摆：那会把唯一的圆点吊在
      // 正中间、线长度为零，看着像画坏了。这种情况左对齐，线从节点往右渐隐。
      if (nodes.length == 1)
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Stack(children: [
            Positioned(
                left: Design.dz(4),
                right: 0,
                top: Design.dz(4),
                child: Container(
                    height: Design.dz(1),
                    decoration: BoxDecoration(
                        gradient: LinearGradient(colors: [
                      s.text.withValues(alpha: .22),
                      s.text.withValues(alpha: .04)
                    ])))),
            _bootDot(s, first: true, failed: false)
          ]),
          SizedBox(height: Design.dz(11)),
          Text(nodes.first.$1,
              style: TextStyle(
                  fontSize: Design.dz(10.5),
                  letterSpacing: Design.dz(.2),
                  color: s.text.withValues(alpha: .34))),
          SizedBox(height: Design.dz(4)),
          Text(nodes.first.$2,
              style: TextStyle(
                  fontSize: Design.dz(13),
                  color: s.text.withValues(alpha: .72)))
        ])
      else
        LayoutBuilder(builder: (context, constraints) {
          final inset = constraints.maxWidth / (2 * nodes.length);
          return Stack(children: [
            Positioned(
                left: inset,
                right: inset,
                top: Design.dz(4),
                child: Container(
                    height: Design.dz(1),
                    decoration: BoxDecoration(
                        gradient: LinearGradient(colors: [
                      s.accent.withValues(alpha: .5),
                      s.accent.withValues(alpha: .18),
                      s.text.withValues(alpha: .08)
                    ])))),
            Row(children: [
              for (final (index, node) in nodes.indexed)
                Expanded(
                    child: Column(children: [
                  _bootDot(s, first: index == 0, failed: node.$3),
                  SizedBox(height: Design.dz(11)),
                  Text(node.$1,
                      style: TextStyle(
                          fontSize: Design.dz(10.5),
                          letterSpacing: Design.dz(.2),
                          color: s.text.withValues(alpha: .34))),
                  SizedBox(height: Design.dz(4)),
                  Text(node.$2,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: Design.dz(13),
                          color: s.text.withValues(
                              alpha: index == 0 ? .72 : (node.$3 ? .5 : .72))))
                ]))
            ])
          ]);
        }),
    ]);
  }

  /// 时间轴上的圆点：首个节点是实白，失败是暗灰，其余是带光晕的主题色。
  Widget _bootDot(SurfaceStyle s, {required bool first, required bool failed}) =>
      Container(
          width: Design.dz(9),
          height: Design.dz(9),
          decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: first
                  ? s.text
                  : (failed ? s.text.withValues(alpha: .22) : s.accent),
              boxShadow: first || failed
                  ? null
                  : [
                      BoxShadow(
                          color: s.accent.withValues(alpha: .55),
                          blurRadius: Design.dz(10))
                    ]));

  /// 先选应用，再选时机；两步都可以取消。
  Future<void> _addPlan(BuildContext context, LauncherController c,
      Map<String, Map<String, dynamic>> appsById, int maxDelay) async {
    final picked = await showLauncherSheet<String>(context,
        title: '选择要自动启动的应用',
        subtitle: '按名称筛选，选中后设置开机后第几秒启动',
        width: Design.px(780),
        height: Design.px(700),
        glowType: 'apps',
        builder: (_) => _BootLaunchAppPicker(controller: c));
    if (picked == null || !context.mounted) return;
    final delay = await showLauncherSheet<int>(context,
        title: '启动时机',
        subtitle: '从开机那一刻开始计时，最大 $maxDelay 秒',
        width: Design.px(660),
        height: Design.px(560),
        glowType: 'apps',
        builder: (_) => _BootLaunchDelayPicker(maxDelay: maxDelay));
    if (delay == null) return;
    await c.command('boot-launch-add', value: picked, zone: '$delay');
  }

  static String timing(Object? delay) {
    final seconds = delay is int ? delay : int.tryParse('$delay') ?? 0;
    return seconds <= 0 ? '开机立刻' : '开机后 $seconds 秒';
  }

  static String _bootState(String state) {
    switch (state) {
      case 'launched':
        return '已启动';
      case 'failed':
        return '上次未启动';
      case 'skipped':
        return '上次已跳过';
      default:
        return '';
    }
  }

  /// 记忆里已经存了一个可用的驾驶模式值。
  static String mode(Map<String, dynamic> memory) =>
      '${memory['driveMode'] ?? ''}';
}

/// 开机自启动：挑应用。列表来自原生应用目录（含图标与启用状态）。
class _BootLaunchAppPicker extends StatefulWidget {
  final LauncherController controller;
  const _BootLaunchAppPicker({required this.controller});
  @override
  State<_BootLaunchAppPicker> createState() => _BootLaunchAppPickerState();
}

class _BootLaunchAppPickerState extends State<_BootLaunchAppPicker> {
  final _query = TextEditingController();

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller, s = SurfaceStyle.of(context);
    return ValueListenableBuilder<Map<String, dynamic>>(
        valueListenable: c.native,
        builder: (context, native, _) {
          final keyword = _query.text.trim().toLowerCase();
          final apps = [
            for (final raw
                in (native['apps'] is List ? native['apps'] as List : const []))
              if (raw is Map && raw['id'] is String && raw['enabled'] != false)
                Map<String, dynamic>.from(raw)
          ].where((app) {
            if (keyword.isEmpty) return true;
            final label = c.appName(app).toLowerCase(),
                pkg = '${app['package'] ?? ''}'.toLowerCase();
            return label.contains(keyword) || pkg.contains(keyword);
          }).toList();
          return Column(children: [
            Padding(
                padding: EdgeInsets.only(bottom: Design.px(12)),
                child: TextField(
                    key: const ValueKey('boot-app-search'),
                    controller: _query,
                    onChanged: (_) => setState(() {}),
                    style: TextStyle(fontSize: Design.px(20), color: s.text),
                    decoration: InputDecoration(
                        isDense: true,
                        hintText: '搜索应用名或包名',
                        hintStyle:
                            TextStyle(color: s.muted, fontSize: Design.px(19)),
                        prefixIcon: Icon(Icons.search_rounded,
                            size: Design.px(26), color: s.muted)))),
            Expanded(
                child: ListView(children: [
              for (final app in apps)
                ListTile(
                    key: ValueKey('boot-app-${app['id']}'),
                    contentPadding: EdgeInsets.symmetric(
                        horizontal: Design.px(10), vertical: Design.px(2)),
                    leading: SizedBox(
                        width: Design.px(40),
                        height: Design.px(40),
                        child: app['iconBytes'] is Uint8List
                            ? Image.memory(app['iconBytes'] as Uint8List,
                                gaplessPlayback: true,
                                errorBuilder: (_, __, ___) => Icon(
                                    Icons.apps_rounded,
                                    size: Design.px(30),
                                    color: s.muted))
                            : Icon(Icons.apps_rounded,
                                size: Design.px(30), color: s.muted)),
                    title: Text(c.appName(app),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style:
                            TextStyle(fontSize: Design.px(21), color: s.text)),
                    subtitle: Text('${app['package'] ?? ''}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style:
                            TextStyle(fontSize: Design.px(16), color: s.muted)),
                    onTap: () => Navigator.pop(context, app['id'])),
              if (apps.isEmpty)
                Padding(
                    padding: EdgeInsets.all(Design.px(18)),
                    child: Text('没有匹配的可启动应用',
                        style: TextStyle(
                            color: s.muted, fontSize: Design.px(19)))),
            ])),
          ]);
        });
  }
}

/// 开机自启动：选时机。预设几档常用秒数，也可自己填。
class _BootLaunchDelayPicker extends StatefulWidget {
  final int maxDelay;
  const _BootLaunchDelayPicker({required this.maxDelay});
  @override
  State<_BootLaunchDelayPicker> createState() => _BootLaunchDelayPickerState();
}

class _BootLaunchDelayPickerState extends State<_BootLaunchDelayPicker> {
  static const _presets = [0, 3, 5, 8, 10, 15, 30];
  final _seconds = TextEditingController(text: '5');

  @override
  void dispose() {
    _seconds.dispose();
    super.dispose();
  }

  int get _value => int.tryParse(_seconds.text.trim()) ?? 0;

  @override
  Widget build(BuildContext context) {
    final s = SurfaceStyle.of(context);
    final valid = _value >= 0 && _value <= widget.maxDelay;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text('以开机时刻为基准，桌面进程晚起来也能补上。',
          style: TextStyle(
              color: s.muted,
              fontSize: Design.px(18),
              height: LauncherType.lineLoose)),
      SizedBox(height: Design.px(14)),
      Wrap(spacing: Design.px(10), runSpacing: Design.px(10), children: [
        for (final preset in _presets)
          SizedBox(
              height: Design.px(54),
              // 弹层里的字号走 Design.px（不跟画布缩放），ChoiceButton 的 height
              // 走 dz，所以高度由外面的 SizedBox 定，这里传 null。
              child: ChoiceButton(
                  key: ValueKey('boot-delay-$preset'),
                  kind: ChoiceKind.filled,
                  height: null,
                  radius: 11,
                  shrink: true,
                  padding: EdgeInsets.symmetric(horizontal: Design.px(24)),
                  selected: _value == preset,
                  onPressed: () => setState(() => _seconds.text = '$preset'),
                  child: Text(preset == 0 ? '立刻' : '$preset 秒',
                      style: TextStyle(fontSize: Design.px(19)))))
      ]),
      SizedBox(height: Design.px(18)),
      Row(children: [
        Expanded(
            child: TextField(
                key: const ValueKey('boot-delay-input'),
                controller: _seconds,
                keyboardType: TextInputType.number,
                onChanged: (_) => setState(() {}),
                style: TextStyle(fontSize: Design.px(22), color: s.text),
                decoration: InputDecoration(
                    isDense: true,
                    hintText: '秒',
                    hintStyle:
                        TextStyle(color: s.muted, fontSize: Design.px(19)),
                    suffixText: '秒后启动'))),
      ]),
      SizedBox(height: Design.px(8)),
      Text(
          valid
              ? (VehicleMemorySettings.timing(_value))
              : '请输入 0 到 ${widget.maxDelay} 之间的秒数',
          style: TextStyle(
              color: valid ? s.muted : s.accent, fontSize: Design.px(18))),
      const Spacer(),
      Align(
          alignment: Alignment.centerRight,
          child: FilledButton(
              key: const ValueKey('boot-delay-confirm'),
              onPressed: valid ? () => Navigator.pop(context, _value) : null,
              child: const Text('加入计划'))),
    ]);
  }
}
