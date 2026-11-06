import 'dart:typed_data';

import 'package:flutter/material.dart';
import '../controller/launcher_controller.dart';
import '../theme/design_tokens.dart';
import '../theme/launcher_theme.dart';
import 'glass_surface.dart';
import 'launcher_dialog.dart';
import 'setting_block.dart';

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
            final modes = <String>[
              for (final raw in live)
                if (raw is String && raw.isNotEmpty) raw
            ];

            final driveEnabled = memory['driveModeEnabled'] == true,
                stopEnabled = memory['startStopEnabled'] == true,
                stopTarget = memory['startStop'] != false,
                target = '${memory['driveMode'] ?? ''}',
                demo = native['demo'] == true,
                connected = vehicle['connected'] == true;

            final currentMode =
                drive['readable'] == true ? '${drive['current']}' : null;
            final currentStop =
                stop['readable'] == true ? stop['current'] == true : null;

            return SingleChildScrollView(
                key: const PageStorageKey('vehicle-memory-scroll'),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SettingBlock(
                          title: '记忆配置',
                          note: demo
                              ? '演示模式'
                              : connected
                                  ? '已连接原车'
                                  : '等待原车连接',
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Text(
                                    '启动桌面时把下列项目恢复到固定位置。每一项单独开关，关掉的那一项不会发送任何写入；'
                                    '打开后只在启动时应用一次，不会在行车中反复调用。',
                                    style: TextStyle(
                                        color: s.muted,
                                        fontSize: Design.px(19),
                                        height: 1.6)),
                                SizedBox(height: Design.px(6)),
                                Text(
                                    '车辆接口：驾驶模式 0x22010100 / 读回 0x21403018；'
                                    '自动启停 0x20020100 / 读回 0x2170f200。'
                                    '写入需要原车在 P 档且未行驶。',
                                    style: TextStyle(
                                        color: s.muted,
                                        fontSize: Design.px(17),
                                        height: 1.6)),
                              ])),
                      SizedBox(height: Design.px(16)),
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
                                    current: currentMode)),
                            SizedBox(width: Design.px(16)),
                            Expanded(
                                child: _stopCard(context, c, s,
                                    enabled: stopEnabled,
                                    stopTarget: stopTarget,
                                    outcome: stopOutcome,
                                    current: currentStop)),
                          ]),
                      SizedBox(height: Design.px(12)),
                      Row(children: [
                        Expanded(
                            child: SizedBox(
                                height: Design.px(58),
                                child: OutlinedButton(
                                    key: const ValueKey(
                                        'memory-apply-drive-mode'),
                                    onPressed: driveEnabled && target.isNotEmpty
                                        ? () => c.command('memory-apply-now',
                                            value: 'driveMode')
                                        : null,
                                    child: const Text('立即应用驾驶模式')))),
                        SizedBox(width: Design.px(16)),
                        Expanded(
                            child: SizedBox(
                                height: Design.px(58),
                                child: OutlinedButton(
                                    key: const ValueKey(
                                        'memory-apply-start-stop'),
                                    onPressed: stopEnabled
                                        ? () => c.command('memory-apply-now',
                                            value: 'startStop')
                                        : null,
                                    child: const Text('立即应用启停设置')))),
                      ]),
                      SizedBox(height: Design.px(16)),
                      _bootBlock(context, c, s, bootEnabled, plans, appsById,
                          demo: demo, boot: boot),
                      SizedBox(height: Design.px(16)),
                      _autoPlayCard(context, c, s, native['integrationPreferences']),
                      SizedBox(height: Design.px(16)),
                      _wirelessAdbCard(context, c, s, native['wirelessAdb']),
                    ]));
          });

  /// 驾驶模式卡片（与自动启停并排，左）。
  Widget _driveCard(BuildContext context, LauncherController c, SurfaceStyle s,
      {required bool enabled,
      required List<String> modes,
      required String target,
      required Object? supported,
      required Map<String, dynamic> outcome,
      required String? current}) {
    final supportedModes =
        supported is List && supported.isNotEmpty ? supported : null;
    return SettingBlock(
        title: '驾驶模式',
        note: enabled ? '启动时切换' : '不生效',
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DesignSwitchTile(
                  key: const ValueKey('memory-drive-mode-enabled'),
                  contentPadding: EdgeInsets.zero,
                  title: const Text('启动时切换到记忆的驾驶模式'),
                  subtitle: Text(_note(
                      outcome, current == null ? null : _label(current), '当前：')),
                  value: enabled,
                  onChanged: (v) =>
                      c.command('memory-drive-mode-enabled', enabled: v)),
              SizedBox(height: Design.px(14)),
              if (modes.isEmpty)
                Text('原车尚未报告可用的驾驶模式',
                    style:
                        TextStyle(color: s.muted, fontSize: Design.px(18)))
              else
                Wrap(
                    spacing: Design.px(12),
                    runSpacing: Design.px(12),
                    children: [
                      for (final mode in modes)
                        SizedBox(
                            height: Design.px(58),
                            child: OutlinedButton(
                                key: ValueKey('memory-mode-$mode'),
                                style: s.selectionStyle(mode == target),
                                onPressed: () => c.command(
                                    'memory-drive-mode-target',
                                    value: mode),
                                child: Text(_label(mode))))
                    ]),
              if (supportedModes == null)
                Padding(
                    padding: EdgeInsets.only(top: Design.px(10)),
                    child: Text('原车暂未报告可用的驾驶模式，先列出全部；写入前仍会按原车支持列表校验。',
                        style: TextStyle(
                            color: s.muted,
                            fontSize: Design.px(17),
                            height: 1.5))),
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
        note: enabled ? '启动时设置' : '不生效',
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DesignSwitchTile(
                  key: const ValueKey('memory-start-stop-enabled'),
                  contentPadding: EdgeInsets.zero,
                  title: const Text('启动时设置自动启停'),
                  subtitle: Text(_note(
                      outcome,
                      current == null ? null : current ? '开启' : '关闭',
                      '当前：')),
                  value: enabled,
                  onChanged: (v) =>
                      c.command('memory-start-stop-enabled', enabled: v)),
              SizedBox(height: Design.px(14)),
              Row(children: [
                for (final (index, option) in [
                  (true, '开启'),
                  (false, '关闭')
                ].indexed)
                  Expanded(
                      child: Padding(
                          padding: EdgeInsets.only(
                              right: index == 0 ? Design.px(12) : 0),
                          child: SizedBox(
                              height: Design.px(58),
                              child: OutlinedButton(
                                  key: ValueKey(
                                      'memory-start-stop-${option.$1}'),
                                  style:
                                      s.selectionStyle(option.$1 == stopTarget),
                                  onPressed: () => c.command(
                                      'memory-start-stop-target',
                                      value: option.$1 ? 'on' : 'off'),
                                  child: Text(option.$2)))))
              ]),
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
        note: enabled ? '开机后恢复' : '不生效',
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DesignSwitchTile(
                  key: const ValueKey('auto-play-music'),
                  contentPadding: EdgeInsets.zero,
                  title: const Text('开机后自动播放上次的音乐'),
                  subtitle: const Text('启动后先拉起关联播放器，约 12 秒后恢复播放；播放器不会留在前台'),
                  value: enabled,
                  onChanged: (v) =>
                      c.command('auto-play-music', enabled: v)),
              SizedBox(height: Design.px(10)),
              Text('关联播放器在「导航与媒体」里选择。请在播放器中先播放一首歌曲并授权媒体访问。',
                  style: TextStyle(
                      color: s.muted, fontSize: Design.px(17), height: 1.5)),
            ]));
  }

  /// 开机自动启动无线 adb：把 adbd 拉到 5555，PC 直接 adb connect。
  Widget _wirelessAdbCard(BuildContext context, LauncherController c,
      SurfaceStyle s, Object? raw) {
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
      'missing' => reason.isEmpty
          ? '还要装同签名的小桥 UNI-AdbBridge（uid 1000）才能改调试端口'
          : reason,
      'off' => '打开后每次开机自动把无线 adb 拉到 $port 端口，PC 直接 adb connect',
      _ => '开机后自动尝试，失败每 20 秒重试（最多 6 次）',
    };
    return SettingBlock(
        title: '开机自动启动无线 adb',
        note: labels[state] ?? state,
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DesignSwitchTile(
                  key: const ValueKey('wireless-adb-enabled'),
                  contentPadding: EdgeInsets.zero,
                  title: const Text('开机后自动打开无线调试'),
                  subtitle: Text(detail),
                  value: enabled,
                  onChanged: (v) =>
                      c.command('wireless-adb-enabled', enabled: v)),
              SizedBox(height: Design.px(10)),
              Row(children: [
                if (attempts > 0)
                  Text('已尝试 $attempts 次',
                      style: TextStyle(
                          color: s.muted, fontSize: Design.px(16))),
                if (!bridge)
                  Text('桥组件未安装',
                      style:
                          TextStyle(color: s.accent, fontSize: Design.px(16))),
                const Spacer(),
                TextButton(
                    key: const ValueKey('wireless-adb-run'),
                    onPressed: () => c.command('wireless-adb-run'),
                    child: const Text('立即开启无线 adb')),
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

  /// 开机自启动：一行一个「应用 + 开机后多少秒」。
  Widget _bootBlock(BuildContext context, LauncherController c,
      SurfaceStyle s, bool enabled, List<Map<String, dynamic>> plans,
      Map<String, Map<String, dynamic>> appsById,
      {required bool demo, required Map<String, dynamic> boot}) {
    String label(Map<String, dynamic> plan) {
      final app = appsById[plan['id']];
      return app == null ? '${plan['package'] ?? plan['id']}' : c.appName(app);
    }

    final maxDelay = boot['maxDelay'] is int ? boot['maxDelay'] as int : 600;
    return SettingBlock(
        title: '开机自启动',
        note: enabled ? '${plans.length} 个计划' : '不生效',
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DesignSwitchTile(
                  key: const ValueKey('boot-launch-enabled'),
                  contentPadding: EdgeInsets.zero,
                  title: const Text('开机后按计划启动应用'),
                  subtitle: Text(demo
                      ? '演示模式不启动应用'
                      : '以开机时刻为准，每个计划每次开机只启动一次；桌面重启不会重放。'),
                  value: enabled,
                  onChanged: (v) =>
                      c.command('boot-launch-enabled', enabled: v)),
              SizedBox(height: Design.px(14)),
              if (plans.isEmpty)
                Text('还没有计划。可以添加「开机立刻」「开机后 5 秒」「开机后 8 秒」这样任意条。',
                    style: TextStyle(
                        color: s.muted,
                        fontSize: Design.px(18),
                        height: 1.6))
              else
                for (final plan in plans)
                  Container(
                      key: ValueKey('boot-plan-${plan['key']}'),
                      margin: EdgeInsets.only(bottom: Design.px(10)),
                      padding: EdgeInsets.symmetric(
                          horizontal: Design.px(16), vertical: Design.px(12)),
                      decoration: BoxDecoration(
                          color: s.soft,
                          borderRadius: BorderRadius.circular(Design.px(16))),
                      child: Row(children: [
                        SizedBox(
                            width: Design.px(38),
                            height: Design.px(38),
                            child: _appIcon(
                                appsById[plan['id']], s.muted)),
                        SizedBox(width: Design.px(14)),
                        Expanded(
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                              Text(label(plan),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                      fontSize: Design.px(21), color: s.text)),
                              SizedBox(height: Design.px(4)),
                              Text(
                                  [
                                    timing(plan['delay']),
                                    _bootState('${plan['state'] ?? ''}'),
                                    if (plan['installed'] == false) '应用未安装',
                                    if ('${plan['reason'] ?? ''}'.isNotEmpty &&
                                        '${plan['state'] ?? ''}' != 'launched')
                                      '${plan['reason']}',
                                  ].where((part) => part.isNotEmpty).join(' · '),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                      color: s.muted,
                                      fontSize: Design.px(17),
                                      height: 1.4)),
                            ])),
                        SizedBox(width: Design.px(8)),
                        IconButton(
                            key: ValueKey('boot-plan-run-${plan['key']}'),
                            tooltip: '立刻启动一次',
                            visualDensity: VisualDensity.compact,
                            onPressed: demo
                                ? null
                                : () => c.command('boot-launch-run',
                                    value: '${plan['key']}'),
                            icon: Icon(Icons.play_arrow_rounded,
                                size: Design.px(28),
                                color: demo ? s.muted : s.accent)),
                        IconButton(
                            key: ValueKey('boot-plan-remove-${plan['key']}'),
                            tooltip: '删除计划',
                            visualDensity: VisualDensity.compact,
                            onPressed: () => c.command('boot-launch-remove',
                                value: '${plan['key']}'),
                            icon: Icon(Icons.close_rounded,
                                size: Design.px(26), color: s.muted)),
                      ])),
              SizedBox(height: Design.px(8)),
              Align(
                  alignment: Alignment.centerRight,
                  child: OutlinedButton.icon(
                      key: const ValueKey('boot-launch-add'),
                      onPressed: () =>
                          _addPlan(context, c, appsById, maxDelay),
                      icon: Icon(Icons.add_rounded, size: Design.px(24)),
                      label: const Text('添加计划'))),
            ]));
  }

  Widget _appIcon(Map<String, dynamic>? app, Color fallback) {
    final bytes = app?['iconBytes'];
    if (bytes is Uint8List)
      return Image.memory(bytes,
          gaplessPlayback: true,
          errorBuilder: (_, __, ___) =>
              Icon(Icons.apps_rounded, size: Design.px(30), color: fallback));
    return Icon(Icons.apps_rounded, size: Design.px(30), color: fallback);
  }

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
            for (final raw in (native['apps'] is List
                ? native['apps'] as List
                : const []))
              if (raw is Map &&
                  raw['id'] is String &&
                  raw['enabled'] != false)
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
                        style: TextStyle(
                            fontSize: Design.px(21), color: s.text)),
                    subtitle: Text('${app['package'] ?? ''}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: Design.px(16), color: s.muted)),
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
              color: s.muted, fontSize: Design.px(18), height: 1.6)),
      SizedBox(height: Design.px(14)),
      Wrap(spacing: Design.px(10), runSpacing: Design.px(10), children: [
        for (final preset in _presets)
          SizedBox(
              height: Design.px(54),
              child: OutlinedButton(
                  key: ValueKey('boot-delay-$preset'),
                  style: s.selectionStyle(_value == preset),
                  onPressed: () =>
                      setState(() => _seconds.text = '$preset'),
                  child: Text(preset == 0 ? '立刻' : '$preset 秒')))
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
