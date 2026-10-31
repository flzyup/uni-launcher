import 'dart:async';
import 'package:flutter/material.dart';
import '../theme/design_tokens.dart';
import '../theme/launcher_theme.dart';
import '../widgets/glass_surface.dart';
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

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
      animation: widget.update,
      builder: (context, _) {
        final u = widget.update, s = SurfaceStyle.of(context);
        return SingleChildScrollView(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
              GlassSurface(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Text('关于 UNI 桌面',
                        style: TextStyle(fontSize: Design.px(26))),
                    SizedBox(height: Design.px(15)),
                    Text('UNI桌面  ${u.info['versionName'] ?? '—'}',
                        style: TextStyle(fontSize: Design.px(30))),
                    Text(
                        '构建 ${u.info['versionCode'] ?? '—'}   ·   Android API ${u.info['sdk'] ?? '—'}',
                        style:
                            TextStyle(color: s.muted, fontSize: Design.px(20)))
                  ])),
              SizedBox(height: Design.px(20)),
              GlassSurface(
                  child: Column(children: [
                Row(children: [
                  Expanded(
                      child: Text('软件更新',
                          style: TextStyle(fontSize: Design.px(26)))),
                  OutlinedButton(
                      onPressed: () {
                        showUpdateDialog(context, u, manual: true);
                      },
                      child: const Text('检查更新'))
                ]),
                SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('自动检查更新'),
                    subtitle: const Text('后台每 5 分钟检查一次'),
                    value: u.enabled,
                    onChanged: u.setEnabled),
                if (u.lastChecked != null)
                  Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                          '上次检查：${u.lastChecked!.toLocal().toString().substring(0, 16)}',
                          style: TextStyle(color: s.muted)))
              ])),
              SizedBox(height: Design.px(20)),
              GlassSurface(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Text('贡献者', style: TextStyle(fontSize: Design.px(26))),
                    SizedBox(height: Design.px(16)),
                    Wrap(
                        spacing: Design.px(28),
                        runSpacing: Design.px(12),
                        children: [
                          for (final name in u.contributors)
                            Text(name,
                                style: TextStyle(
                                    fontSize: Design.px(21), color: s.text))
                        ])
                  ]))
            ]));
      });
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
                    if (u.state == 'error')
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
