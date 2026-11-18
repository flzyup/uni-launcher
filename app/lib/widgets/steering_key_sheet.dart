import 'package:flutter/material.dart';

import '../controller/launcher_controller.dart';
import '../theme/design_tokens.dart';
import '../theme/launcher_theme.dart';
import 'card_content.dart' show mapOf;
import 'choice_button.dart';
import 'launcher_dialog.dart';
import 'uni_icon.dart';

/// 方控接管（eclipse 设计稿 f39）。
///
/// 真实链路已经存在：`SteeringKeyPolicy` 定义被接管的键码，
/// `SteeringKeyBridge` 负责登记回调与 250ms 回环抑制，开关走
/// `command('steering-keys', enabled:)`。这一页只做可视化，不新增行为。
///
/// 源码暂时给不了的两块，按「看得见但不假装有数」处理：
///   · 按键注入 / 回环折叠 / 响应延迟三项统计 —— `SteeringKeyBridge.snapshot()`
///     目前只进诊断日志，没有进 Dart 的 native state，页面显示「待接入」；
///   · 「已接管 N 个键」的实时计数同理，改为静态说明。
Future<void> showSteeringKeySheet(
        BuildContext context, LauncherController controller) =>
    showLauncherSheet<void>(
      context,
      title: '方控接管',
      subtitle: '方向盘媒体键交给桌面；原车媒体中心照旧收到，250ms 内折叠',
      closeLabel: '关闭方控接管',
      width: Design.px(1440),
      glowType: 'music',
      builder: (context) => ValueListenableBuilder<Map<String, dynamic>>(
          valueListenable: controller.native,
          builder: (context, native, _) {
            final prefs = mapOf(native['integrationPreferences']);
            final media = mapOf(native['media']);
            final enabled = prefs['steeringKeysEnabled'] != false;
            return _SteeringKeyBody(
                enabled: enabled,
                // 真实诊断数据早就在 media 里了：MediaAdapter.snapshot() 把
                // SteeringKeyBridge.snapshot()（接入方式/接受键数/收到次数/
                // 每个键码的计数）和 SteeringKeyInjector.snapshot()（注入次数/
                // 执行次数/失败次数）一起塞进来了。之前以为要改原生，是我看漏。
                keys: mapOf(media['steeringKeys']),
                inject: mapOf(media['steeringInject']),
                onToggle: (v) =>
                    controller.command('steering-keys', enabled: v));
          }),
    );

/// 被接管的键码来自 `core/SteeringKeyPolicy.interceptKeys()`，这里按组展示。
/// 改键码时两边要一起改——所以把类名写进注释，避免有人只改这一张表。
const _mapping = <(String, String, String, bool)>[
  ('上一首', '200088 · 88（AOSP）', 'back', true),
  ('播放 / 暂停', '200085 · 85 / 126 / 127', 'pause', true),
  ('下一首', '200087 · 87 · 210005（快进）', 'next', true),
  ('音量与旋钮', '200024 · 200025 · 110007-10', 'fan', false),
  ('语音键', '留给原车语音助手，桌面不抢', 'phone', false),
  ('媒体源键（中控）', '110003 · 210003', 'music', false),
];

class _SteeringKeyBody extends StatelessWidget {
  final bool enabled;

  /// `media.steeringKeys` ← SteeringKeyBridge.snapshot()
  final Map<String, dynamic> keys;

  /// `media.steeringInject` ← SteeringKeyInjector.snapshot()（含 kugou 旁路）
  final Map<String, dynamic> inject;
  final ValueChanged<bool> onToggle;
  const _SteeringKeyBody(
      {required this.enabled,
      required this.keys,
      required this.inject,
      required this.onToggle});

  /// 统计三格。三项里只有前两项源码给了计数器：
  /// · 按键注入 → steeringInject.injected（真实）
  /// · 注入失败 → steeringInject.failed（真实，代替设计稿的「回环折叠」）
  /// · 响应延迟 → 原生没有任何计时，只能写待接入，不能编数字。
  bool get _hasDiagnostics => keys.isNotEmpty || inject.isNotEmpty;

  /// `seen` 是 {键码字符串: 次数}，由 SteeringKeyBridge 在每次回调时累加。
  Map<String, dynamic> get _seen => mapOf(keys['seen']);

  static String _number(Object? value) => value is num ? '${value.toInt()}' : '—';

  Widget _status(SurfaceStyle s) {
    if (!enabled) {
      return Text('已关闭：所有方向键盘交回原车，桌面不再接管',
          style: TextStyle(fontSize: Design.px(17), color: s.muted));
    }
    final installed = keys['installed'] == true;
    final accepted = keys['accepted'];
    final mode = keys['mode'];
    final reason = keys['reason'];
    final text = installed && accepted is num
        ? '已接管 ${accepted.toInt()} 个键'
            '${mode is String && mode.isNotEmpty ? ' · 接入方式 $mode' : ''}'
        : reason is String && reason.isNotEmpty
            ? '未接入：$reason'
            : '已接管：播放/暂停、上一首、下一首；音量与语音键留给原车';
    return Text(text,
        style: TextStyle(
            fontSize: Design.px(17),
            color: installed ? s.accent : s.muted));
  }

  @override
  Widget build(BuildContext context) {
    final s = SurfaceStyle.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        Text('方向盘媒体键接管',
            style: TextStyle(fontSize: Design.px(20), color: s.text)),
        SizedBox(width: Design.px(12)),
        DesignSwitch(
            key: const ValueKey('steering-keys-switch'),
            value: enabled,
            onChanged: onToggle),
        SizedBox(width: Design.px(12)),
        Expanded(child: _status(s)),
      ]),
      SizedBox(height: Design.px(18)),
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(
            width: Design.px(560),
            child: Container(
                padding: EdgeInsets.symmetric(vertical: Design.px(16)),
                decoration: BoxDecoration(
                    color: s.soft,
                    borderRadius: BorderRadius.circular(s.controlRadius * .8)),
                child: Column(children: [
                  SizedBox(
                      height: Design.px(460),
                      child: CustomPaint(
                          painter: _WheelPainter(
                              line: s.edge,
                              accent: s.accent,
                              muted: s.muted,
                              surface: s.strong),
                          child: const SizedBox.expand())),
                  SizedBox(height: Design.px(10)),
                  Text('左侧媒体键接管 · 右侧音量与语音留给原车',
                      style:
                          TextStyle(fontSize: Design.px(16), color: s.muted)),
                ]))),
        SizedBox(width: Design.px(18)),
        Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
              Row(children: [
                Text('按键映射',
                    style: TextStyle(
                        fontSize: Design.px(21),
                        fontWeight: FontWeight.w500,
                        color: s.text)),
                const Spacer(),
                Text('折叠组：媒体 / 音量',
                    style:
                        TextStyle(fontSize: Design.px(16), color: s.muted)),
              ]),
              SizedBox(height: Design.px(10)),
              for (final (label, code, icon, taken) in _mapping)
                _keyRow(s, label, code, icon, taken),
              SizedBox(height: Design.px(14)),
              Row(children: [
                Expanded(
                    child: _stat(
                        s,
                        '按键注入',
                        _number(inject['injected']),
                        '次',
                        live: inject['injected'] != null)),
                SizedBox(width: Design.px(10)),
                Expanded(
                    child: _stat(s, '注入失败', _number(inject['failed']), '次',
                        live: inject['failed'] != null)),
                SizedBox(width: Design.px(10)),
                Expanded(
                    child: _stat(s, '收到按键', _number(keys['events']), '次',
                        live: keys['events'] != null)),
                SizedBox(width: Design.px(10)),
                // 原生没有任何计时，不编数字。
                Expanded(child: _stat(s, '响应延迟', '—', '待接入', live: false)),
              ]),
              if (_seen.isNotEmpty) ...[
                SizedBox(height: Design.px(12)),
                Text('按键诊断 · 实车按下过的键码',
                    style: TextStyle(fontSize: Design.px(16), color: s.muted)),
                SizedBox(height: Design.px(8)),
                Wrap(
                    spacing: Design.px(8),
                    runSpacing: Design.px(8),
                    children: [
                      for (final entry in _seen.entries)
                        _chip(s, '${entry.key} × ${entry.value}')
                    ]),
              ],
              if (!_hasDiagnostics) ...[
                SizedBox(height: Design.px(12)),
                Text(
                    '当前没有诊断数据：演示模式或原车方控未接入时 media.steeringKeys 为空。',
                    style: TextStyle(fontSize: Design.px(15), color: s.muted)),
              ],
              SizedBox(height: Design.px(14)),
              Text(
                  '原车 requestKeysInterception 只登记回调、不改路由，所以一次按键会从两条通道回来；'
                  '注入时记下动作分组，250ms 内同组回调直接丢弃，避免「一按跳两首」。',
                  style: TextStyle(
                      fontSize: Design.px(16),
                      color: s.muted,
                      height: 1.65)),
            ])),
      ]),
      SizedBox(height: Design.px(16)),
      Wrap(spacing: Design.px(10), runSpacing: Design.px(10), children: [
        _chip(s, '传输控制 TransportControls'),
        _chip(s, '酷狗广播旁路'),
        _chip(s, '按键注入 injectInputEvent'),
        _chip(s, '回环抑制 250ms'),
      ]),
    ]);
  }

  Widget _keyRow(SurfaceStyle s, String label, String code, String icon,
          bool taken) =>
      Container(
          margin: EdgeInsets.only(bottom: Design.px(8)),
          padding: EdgeInsets.symmetric(
              horizontal: Design.px(14), vertical: Design.px(10)),
          decoration: BoxDecoration(
              color: taken ? s.accent.withValues(alpha: .07) : s.soft,
              borderRadius: BorderRadius.circular(s.controlRadius * .7)),
          child: Row(children: [
            UniIcon(icon,
                size: Design.px(24),
                color: taken ? s.accent : s.muted),
            SizedBox(width: Design.px(14)),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(label,
                      style: TextStyle(
                          fontSize: Design.px(19),
                          color: taken ? s.text : s.muted)),
                  SizedBox(height: Design.px(3)),
                  Text(code,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: Design.px(14), color: s.muted)),
                ])),
            Text(taken ? '已接管' : '不接管',
                style: TextStyle(
                    fontSize: Design.px(15),
                    color: taken ? s.accent : s.muted)),
          ]));

  Widget _stat(SurfaceStyle s, String label, String value, String unit,
          {bool live = true}) =>
      Container(
          padding: EdgeInsets.symmetric(
              horizontal: Design.px(14), vertical: Design.px(10)),
          decoration: BoxDecoration(
              color: s.soft,
              borderRadius: BorderRadius.circular(s.controlRadius * .6)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label,
                style: TextStyle(fontSize: Design.px(14), color: s.muted)),
            SizedBox(height: Design.px(4)),
            Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(value,
                      style: TextStyle(
                          fontSize: Design.px(26),
                          fontWeight: FontWeight.w300,
                          color: live ? s.text : s.muted)),
                  SizedBox(width: Design.px(6)),
                  Text(live ? unit : '待接入',
                      style:
                          TextStyle(fontSize: Design.px(14), color: s.muted)),
                ]),
          ]));

  Widget _chip(SurfaceStyle s, String text) => Container(
      padding: EdgeInsets.symmetric(
          horizontal: Design.px(14), vertical: Design.px(8)),
      decoration: BoxDecoration(
          color: s.soft,
          borderRadius: BorderRadius.circular(s.controlRadius * .5),
          border: Border.all(color: s.edge)),
      child: Text(text, style: TextStyle(fontSize: Design.px(15), color: s.text)));
}

/// 方向盘示意：外圈 + 两个按键面 + 四个功能位。只做示意，不承担交互。
class _WheelPainter extends CustomPainter {
  final Color line, accent, muted, surface;
  const _WheelPainter(
      {required this.line,
      required this.accent,
      required this.muted,
      required this.surface});
  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero), r = size.shortestSide * .42;
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..color = line;
    canvas.drawCircle(c, r, stroke);
    // 两条横辐 + 一条下辐
    final spoke = Paint()
      ..strokeWidth = size.shortestSide * .03
      ..strokeCap = StrokeCap.round
      ..color = line;
    canvas.drawLine(c, c + Offset(-r * .55, 0), spoke);
    canvas.drawLine(c, c + Offset(r * .55, 0), spoke);
    canvas.drawLine(c, c + Offset(0, r * .42), spoke);
    // 左右按键面
    final pad = Paint()..color = surface;
    for (final dx in [-1.0, 1.0]) {
      final rect = RRect.fromRectAndRadius(
          Rect.fromCenter(
              center: c + Offset(dx * r * .62, -r * .02),
              width: r * .56,
              height: r * .94),
          Radius.circular(r * .18));
      canvas.drawRRect(rect, pad);
      canvas.drawRRect(rect, stroke);
    }
    // 四个功能位：左二右二
    void button(Offset at, bool on, int kind) {
      final fill = Paint()
        ..color = on ? accent.withValues(alpha: .12) : surface;
      final edge = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..color = on ? accent.withValues(alpha: .55) : line;
      canvas.drawCircle(at, r * .12, fill);
      canvas.drawCircle(at, r * .12, edge);
      final glyph = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..strokeCap = StrokeCap.round
        ..color = on ? accent : muted;
      final g = r * .05;
      switch (kind) {
        case 0: // 上一首
          canvas.drawLine(at + Offset(-g * .9, -g), at + Offset(-g * .9, g), glyph);
          canvas.drawPath(
              Path()
                ..moveTo(at.dx + g, at.dy - g)
                ..lineTo(at.dx - g * .4, at.dy)
                ..lineTo(at.dx + g, at.dy + g),
              glyph);
          break;
        case 1: // 播放暂停
          canvas.drawLine(at + Offset(-g * .45, -g), at + Offset(-g * .45, g), glyph);
          canvas.drawLine(at + Offset(g * .45, -g), at + Offset(g * .45, g), glyph);
          break;
        case 2: // 下一首
          canvas.drawLine(at + Offset(g * .9, -g), at + Offset(g * .9, g), glyph);
          canvas.drawPath(
              Path()
                ..moveTo(at.dx - g, at.dy - g)
                ..lineTo(at.dx + g * .4, at.dy)
                ..lineTo(at.dx - g, at.dy + g),
              glyph);
          break;
        default: // 音量
          canvas.drawLine(at + Offset(0, -g), at + Offset(0, g), glyph);
          canvas.drawLine(at + Offset(-g, 0), at + Offset(g, 0), glyph);
          break;
      }
    }

    button(c + Offset(-r * .62, -r * .34), true, 0);
    button(c + Offset(-r * .62, r * .30), true, 1);
    button(c + Offset(r * .62, -r * .34), true, 2);
    button(c + Offset(r * .62, r * .30), false, 3);
  }

  @override
  bool shouldRepaint(covariant _WheelPainter old) =>
      old.line != line || old.accent != accent || old.surface != surface;
}
