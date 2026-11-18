import 'dart:async';
import 'package:flutter/material.dart';
import '../theme/design_tokens.dart';
import '../theme/launcher_theme.dart';
import '../widgets/choice_button.dart';
import '../widgets/setting_block.dart';
import '../widgets/launcher_dialog.dart';
import 'update_controller.dart';

class AboutPanel extends StatefulWidget {
  final UpdateController update;
  const AboutPanel({super.key, required this.update});
  @override
  State<AboutPanel> createState() => _AboutPanelState();
}

class _AboutPanelState extends State<AboutPanel> {
  @override
  void initState() {
    super.initState();
    widget.update.refreshContributors();
  }

  String _stateLabel(UpdateController u) => switch (u.state) {
        'checking' => '正在检查更新…',
        'latest' => '当前已是最新版本',
        'found' => '发现新版本 ${u.release?['version_name'] ?? ''}',
        'downloading' => '正在下载 ${(u.progress * 100).toStringAsFixed(0)}%',
        'error' => u.error,
        'incompatible' => '当前设备暂无兼容更新',
        _ => '尚未检查更新'
      };

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
      animation: widget.update,
      builder: (context, _) {
        final u = widget.update, s = SurfaceStyle.of(context);
        final version = '${u.info['versionName'] ?? '—'}';
        return SingleChildScrollView(
            key: const PageStorageKey('about-scroll'),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // 页头不是块：标题 15 → 44 的版本号（版本号吃主题色）→ 构建信息。
                  Text('关于 UNI 桌面',
                      style:
                          TextStyle(fontSize: Design.dz(15), color: s.muted)),
                  SizedBox(height: Design.dz(8)),
                  Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Text('UNI桌面 ',
                            style: TextStyle(
                                fontSize: Design.dz(44),
                                height: 1.1,
                                fontWeight: FontWeight.w300)),
                        Text(version,
                            style: TextStyle(
                                fontSize: Design.dz(44),
                                height: 1.1,
                                fontWeight: FontWeight.w300,
                                color: s.accent))
                      ]),
                  SizedBox(height: Design.dz(6)),
                  Text(
                      'UNI Desktop · feat/lynkco-05 · 领克 05 PHEV · 构建 ${u.info['versionCode'] ?? '—'}',
                      style:
                          TextStyle(fontSize: Design.dz(13), color: s.muted)),
                  SizedBox(height: Design.dz(16)),
                  SettingBlock(
                      title: '软件更新',
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            SettingRow(
                                label: _stateLabel(u),
                                trailing: DesignSmallAction('检查更新',
                                    onPressed: () => showUpdateDialog(
                                        context, u,
                                        manual: true))),
                            SettingRow(
                                label: '自动检查更新',
                                note: '桌面启动时会静默检查一次',
                                trailing: DesignSwitch(
                                    key: const ValueKey('auto-update'),
                                    value: u.enabled,
                                    onChanged: u.setEnabled)),
                            SettingRow(
                                label: '检查周期',
                                trailing: u.enabled
                                    ? _intervalPicker(u, s)
                                    : Text('—',
                                        style: TextStyle(
                                            fontSize: Design.dz(13.5),
                                            color: s.muted))),
                            SettingRow(
                                label: '上次检查',
                                divider: false,
                                trailing: Text(
                                    u.lastChecked == null
                                        ? '—'
                                        : u.lastChecked!
                                            .toLocal()
                                            .toString()
                                            .substring(0, 16),
                                    style: TextStyle(
                                        fontSize: Design.dz(13.5),
                                        color: s.text.withValues(alpha: .7))))
                          ])),
                  SizedBox(height: Design.dz(11.67)),
                  SettingBlock(
                      title: '贡献者',
                      child: SettingRow(
                          label: u.contributors.isEmpty
                              ? 'UNI Desktop Contributors'
                              : u.contributors.join(' · '),
                          divider: false,
                          trailing: Text('设计与工程',
                              style: TextStyle(
                                  fontSize: Design.dz(13), color: s.muted))))
                ]));
      });

  Widget _intervalPicker(UpdateController u, SurfaceStyle s) {
    const options = {30: '30 分钟', 120: '2 小时', 720: '半天', 1440: '1 天'};
    return PopupMenuButton<int>(
        initialValue: u.intervalMinutes,
        onSelected: u.setInterval,
        color: s.strong,
        itemBuilder: (context) => [
              for (final entry in options.entries)
                PopupMenuItem(value: entry.key, child: Text(entry.value))
            ],
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text(options[u.intervalMinutes] ?? '${u.intervalMinutes} 分钟',
              style: TextStyle(
                  fontSize: Design.dz(13.5),
                  color: s.text.withValues(alpha: .8))),
          SizedBox(width: Design.dz(2)),
          Icon(Icons.chevron_right,
              size: Design.dz(16), color: s.text.withValues(alpha: .3))
        ]));
  }
}

Future<void> showUpdateDialog(BuildContext context, UpdateController u,
    {bool manual = false}) async {
  if (u.dialogOpen) return;
  u.dialogOpen = true;
  if (manual) unawaitedCheck(u);
  try {
    await showLauncherSheet(context,
        title: '软件更新',
        titleWidget: Row(children: [
          CustomPaint(
              size: Size.square(Design.px(35)),
              painter: _UpdateIconPainter(SurfaceStyle.of(context).accent)),
          SizedBox(width: Design.px(16)),
          Text('软件更新',
              style: TextStyle(
                  fontSize: Design.px(34), fontWeight: FontWeight.w500)),
        ]),
        width: 1000,
        builder: (context) => AnimatedBuilder(
            animation: u,
            builder: (context, _) {
              final s = SurfaceStyle.of(context);
              final r = u.release, a = r?['artifact'];
              final busy = u.state == 'downloading' || u.state == 'verifying';
              Widget badge(String label, String v, Color color) => DecoratedBox(
                  decoration: BoxDecoration(
                      border: Border.all(color: color),
                      color: color.withValues(alpha: .12)),
                  child: Padding(
                      padding: EdgeInsets.all(Design.px(10)),
                      child: Text('$label  $v',
                          style: TextStyle(
                              color: color, fontSize: Design.px(20)))));
              return SingleChildScrollView(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                    if (r != null) ...[
                      Text('UNI桌面 ${r['version_name']}',
                          style: TextStyle(fontSize: Design.px(28))),
                      SizedBox(height: Design.px(14)),
                      Wrap(spacing: Design.px(12), children: [
                        badge('当前', '${u.info['versionName'] ?? '—'}', s.muted),
                        badge('新版本', '${r['version_name']}', s.accent)
                      ]),
                      SizedBox(height: Design.px(20))
                    ],
                    if (u.state == 'found' && r != null)
                      _UpdateNotes(text: '${r['notes'] ?? ''}'),
                    if (busy) ...[
                      Text(
                          u.state == 'verifying'
                              ? '正在校验安装包'
                              : '正在下载 ${(u.progress * 100).toStringAsFixed(0)}%',
                          style: TextStyle(fontSize: Design.px(22))),
                      if (u.state == 'downloading' &&
                          a is Map &&
                          a['size_bytes'] is num)
                        Text(
                            '${((a['size_bytes'] as num) * u.progress / 1024 / 1024).toStringAsFixed(1)} / ${((a['size_bytes'] as num) / 1024 / 1024).toStringAsFixed(1)} MB',
                            style: TextStyle(
                                color: s.muted, fontSize: Design.px(18))),
                      SizedBox(height: Design.px(15)),
                      LinearProgressIndicator(
                          value: u.state == 'verifying' ? null : u.progress)
                    ],
                    if (u.state == 'checking') const Text('正在检查更新…'),
                    if (u.state == 'latest') const Text('当前已是最新版本'),
                    if (u.state == 'incompatible') const Text('当前设备暂无兼容更新'),
                    if (u.state == 'idle') const Text('尚未检查更新'),
                    if (u.state == 'permission')
                      const Text('请允许此应用安装软件，返回后点击重新打开安装'),
                    if (u.state == 'install') const Text('已打开系统安装界面，请确认安装'),
                    if (u.state == 'error' || u.state == 'invalid-package')
                      Text(u.error, style: TextStyle(color: s.muted)),
                    SizedBox(height: Design.px(22)),
                    Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                      if (busy && u.state == 'downloading')
                        OutlinedButton(
                            onPressed: u.cancel, child: const Text('取消下载')),
                      if (u.state == 'found') ...[
                        OutlinedButton(
                            onPressed: () {
                              u.dismiss();
                              Navigator.pop(context);
                            },
                            child: const Text('稍后提醒')),
                        SizedBox(width: Design.px(12)),
                        FilledButton(
                            onPressed: () => u.download(),
                            child: Text(
                                '下载更新${a is Map && a['size_bytes'] is num ? '  ${(a['size_bytes'] / 1024 / 1024).toStringAsFixed(1)} MB' : ''}'))
                      ],
                      if (u.state == 'error' ||
                          u.state == 'invalid-package' ||
                          u.state == 'idle' ||
                          u.state == 'incompatible' ||
                          u.state == 'latest')
                        OutlinedButton(
                            onPressed: () => u.check(manual: true),
                            child: const Text('重新检查')),
                      if (u.state == 'permission' || u.state == 'install')
                        OutlinedButton(
                            onPressed: u.install, child: const Text('重新打开安装'))
                    ])
                  ]));
            }));
  } finally {
    u.dialogOpen = false;
  }
}

void unawaitedCheck(UpdateController u) {
  u.check(manual: true);
}

class _UpdateIconPainter extends CustomPainter {
  final Color color;
  const _UpdateIconPainter(this.color);
  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 64, size.height / 64);
    final p = Paint()
      ..color = color
      ..strokeWidth = 2.6
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawArc(const Rect.fromLTWH(13, 13, 38, 38), -2.9, 1.45, false, p);
    canvas.drawArc(const Rect.fromLTWH(13, 13, 38, 38), .2, 1.45, false, p);
    canvas.drawPath(
        Path()
          ..moveTo(32, 43)
          ..lineTo(32, 23)
          ..moveTo(25, 30)
          ..lineTo(32, 23)
          ..lineTo(39, 30),
        p);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _UpdateIconPainter oldDelegate) =>
      color != oldDelegate.color;
}

class _UpdateNotes extends StatefulWidget {
  final String text;
  const _UpdateNotes({required this.text});
  @override
  State<_UpdateNotes> createState() => _UpdateNotesState();
}

class _UpdateNotesState extends State<_UpdateNotes> {
  final scroll = ScrollController();
  Timer? timer;
  DateTime pausedUntil = DateTime.now().add(const Duration(seconds: 2));
  int direction = 1;
  bool reducedMotion = false;
  bool hovering = false;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    reducedMotion = MediaQuery.disableAnimationsOf(context);
    timer ??= Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (reducedMotion ||
          hovering ||
          DateTime.now().isBefore(pausedUntil) ||
          !scroll.hasClients) return;
      final max = scroll.position.maxScrollExtent;
      if (max <= 0) return;
      if (scroll.offset >= max && direction > 0 ||
          scroll.offset <= 0 && direction < 0) {
        direction = -direction;
        pausedUntil = DateTime.now().add(const Duration(seconds: 2));
        return;
      }
      scroll.jumpTo((scroll.offset + direction.toDouble()).clamp(0.0, max));
    });
  }

  @override
  void dispose() {
    timer?.cancel();
    scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MouseRegion(
      onEnter: (_) => hovering = true,
      onExit: (_) {
        hovering = false;
        pausedUntil = DateTime.now().add(const Duration(seconds: 5));
      },
      child: Listener(
          onPointerDown: (_) =>
              pausedUntil = DateTime.now().add(const Duration(seconds: 5)),
          onPointerMove: (_) =>
              pausedUntil = DateTime.now().add(const Duration(seconds: 5)),
          onPointerSignal: (_) =>
              pausedUntil = DateTime.now().add(const Duration(seconds: 5)),
          child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: Design.px(240)),
              child: SingleChildScrollView(
                  controller: scroll,
                  child: Text(widget.text,
                      style: TextStyle(
                          fontSize: Design.px(21),
                          height: 1.6,
                          color: SurfaceStyle.of(context).muted))))));
}
