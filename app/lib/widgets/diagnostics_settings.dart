import 'package:flutter/material.dart';

import '../platform/log_tools.dart';
import '../platform/uni_log.dart';
import '../theme/design_tokens.dart';
import '../theme/launcher_theme.dart';
import '../widgets/choice_button.dart';
import '../widgets/launcher_dialog.dart';
import '../widgets/setting_block.dart';

/// Diagnostics panel: export the log package, share it, and inspect the log
/// system state.
///
/// A head unit often has no debugger attached, so the package is the only way
/// to get evidence off the car: it carries the log files plus a runtime
/// snapshot (permissions, vehicle channel, spectrum, ambient light, anchors,
/// every setting key).
///
/// 版式按 sim f14：三列统计 → 导出目录 → 落盘级别四段 → 四个动作按钮 →
/// 磁盘余量三行 → 「包内有什么」两张说明卡。
class DiagnosticsSettings extends StatefulWidget {
  const DiagnosticsSettings({super.key});

  @override
  State<DiagnosticsSettings> createState() => _DiagnosticsSettingsState();
}

class _DiagnosticsSettingsState extends State<DiagnosticsSettings> {
  Map<String, dynamic>? _status;
  String _preview = '';
  bool _previewOpen = false;
  bool _busy = false;

  /// 能不能往公共目录写文件（导出诊断包的前提）。
  bool _storageWritable = true;

  /// 刚点的落盘级别。原生回执（`status.level`）到达并与之相符之前，用它画选中
  /// 态：没有原生插件的环境（Windows 预览）`status` 恒为空，不这样处理就会
  /// 每次点完立刻弹回「信息」，看着像按钮不响应。
  String? _localLevel;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final status = await LogTools.status();
    if (!mounted) return;
    setState(() {
      _status = status;
      // 只有原生**明确说**不可写才拦：老原生侧没有这个字段，
      // 按「不可写」处理会让导出直接卡住，比让它按自己的报错走更糟。
      _storageWritable = status['storageWritable'] != false;
      if (status['level'] == _localLevel) _localLevel = null;
    });
  }

  Future<void> _setLevel(String name) async {
    setState(() => _localLevel = name);
    final applied = await LogTools.setLevel(name == 'DEBUG'
        ? UniLogLevel.debug
        : name == 'WARN'
            ? UniLogLevel.warn
            : name == 'ERROR'
                ? UniLogLevel.error
                : UniLogLevel.info);
    if (!mounted) return;
    setState(() => _localLevel = applied.toUpperCase());
    await _refresh();
  }

  /// 弹系统授权框要存储权限。
  Future<bool> _requestPermission() async {
    if (_busy) return false;
    setState(() => _busy = true);
    final granted = await LogTools.ensureStoragePermission();
    if (!mounted) return granted;
    setState(() {
      _busy = false;
      _storageWritable = granted;
    });
    UniLog.event(UniLogTags.log, '申请存储权限', fields: {'granted': granted});
    if (!granted) {
      showLauncherToast(context, '没有存储权限，请在系统设置里允许「文件和存储」');
    }
    return granted;
  }

  Future<void> _export(
      String label, Future<LogExportResult> Function() action) async {
    if (_busy) return;
    if (!_storageWritable) {
      final granted = await _requestPermission();
      if (!granted) return;
    }
    await _run(label, action);
  }

  Future<void> _run(
      String label, Future<LogExportResult> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    final result = await action();
    if (!mounted) return;
    setState(() => _busy = false);
    await _refresh();
    if (result.message.isNotEmpty) showLauncherToast(context, result.message);
    UniLog.event(UniLogTags.log, label, fields: {'ok': result.ok});
  }

  Future<void> _clear() async {
    if (_busy) return;
    setState(() => _busy = true);
    final message = await LogTools.clear();
    if (!mounted) return;
    setState(() => _busy = false);
    await _refresh();
    if (message.isNotEmpty) showLauncherToast(context, message);
    UniLog.event(UniLogTags.log, '清空日志');
  }

  Future<void> _loadPreview() async {
    final text = await LogTools.preview(lines: 40);
    if (!mounted) return;
    setState(() {
      _preview = text;
      _previewOpen = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = SurfaceStyle.of(context);
    final status = _status ?? const <String, dynamic>{};
    final bytes = (status['bytes'] as num?)?.toInt() ?? 0;
    final degraded = status['degraded'] == true;
    final anchors = (status['anchors'] as num?)?.toInt() ?? 0;
    final level = _localLevel ?? (status['level'] as String?) ?? 'INFO';
    // 份数与落盘策略由原生 status 提供；老原生侧还没这几个字段时显示「—」，
    // 不拿 0 顶上（0 份是「可以清空」的错觉，实际是没读到）。
    int? num_(String key) => (status[key] as num?)?.toInt();
    final files = num_('files'),
        maxFileBytes = num_('maxFileBytes'),
        maxFiles = num_('maxFiles'),
        maxTotalBytes = num_('maxTotalBytes'),
        minFreeBytes = num_('minFreeBytes');
    String kb(int? value) =>
        value == null ? '—' : '${(value / 1024).round()} KB';
    String mb(int? value) => value == null
        ? '—'
        : '${(value / 1024 / 1024).toStringAsFixed(value % (1024 * 1024) == 0 ? 0 : 1)} MB';
    return SettingBlock(
        title: '诊断日志',
        note: degraded ? '日志落盘已降级：磁盘空间不足，只写 Logcat' : null,
        trailing: _busy
            ? SizedBox(
                width: Design.dz(16),
                height: Design.dz(16),
                child: const CircularProgressIndicator(strokeWidth: 2))
            : DesignTextAction('刷新',
                chevron: false, onPressed: () => _refresh()),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          // 三列统计：k 10.5 小字 + v 19 的细数字。
          Row(children: [
            Expanded(child: _Stat('已落盘占用', '${bytes ~/ 1024}', 'KB')),
            Expanded(child: _Stat('锚点节点', '$anchors', '个')),
            Expanded(child: _Stat('日志文件', files == null ? '—' : '$files', '份')),
          ]),
          SizedBox(height: Design.dz(14)),
          Row(children: [
            DesignFieldLabel('导出目录'),
            SizedBox(width: Design.dz(10)),
            Expanded(
                child: Text('Download/UNI/',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: Design.dz(13),
                        color: s.text.withValues(alpha: .8)))),
            if (!_storageWritable) ...[
              SizedBox(width: Design.dz(8)),
              DesignSmallAction('申请存储权限',
                  icon: Icons.lock_open_outlined,
                  onPressed: _requestPermission),
            ],
            SizedBox(width: Design.dz(8)),
            _PermissionTag(granted: _storageWritable)
          ]),
          SizedBox(height: Design.dz(12)),
          const DesignFieldLabel('落盘级别'),
          SizedBox(height: Design.dz(8)),
          Row(children: [
            for (final (index, item) in [
              ('DEBUG', '调试'),
              ('INFO', '信息'),
              ('WARN', '警告'),
              ('ERROR', '仅错误')
            ].indexed) ...[
              if (index > 0) SizedBox(width: Design.dz(8)),
              Expanded(
                  child: ChoiceButton(
                      key: ValueKey('log-level-${item.$1}'),
                      height: 38,
                      radius: 11,
                      selected: level == item.$1,
                      onPressed: _busy ? null : () => _setLevel(item.$1),
                      child: Text(item.$2,
                          style: TextStyle(fontSize: Design.dz(13.5)))))
            ]
          ]),
          SizedBox(height: Design.dz(8)),
          Text('「调试」会把全部细节写入文件，车机存储紧张时建议用「信息」。',
              style: TextStyle(fontSize: Design.dz(13.5), color: s.muted)),
          SizedBox(height: Design.dz(12)),
          Wrap(spacing: Design.dz(9), runSpacing: Design.dz(8), children: [
            _DiagButton('导出诊断包',
                primary: true,
                icon: Icons.file_download_outlined,
                onPressed:
                    _busy ? null : () => _export('导出诊断包', LogTools.export)),
            _DiagButton('导出并分享',
                icon: Icons.ios_share,
                onPressed: _busy
                    ? null
                    : () => _export('导出并分享诊断包', LogTools.exportAndShare)),
            _DiagButton('预览最近日志',
                icon: Icons.visibility_outlined,
                onPressed: _busy ? null : _loadPreview),
            _DiagButton('清空日志', ghost: true, onPressed: _busy ? null : _clear),
          ]),
          if (_previewOpen) ...[
            SizedBox(height: Design.dz(10)),
            Container(
                width: double.infinity,
                constraints: BoxConstraints(maxHeight: Design.dz(150)),
                padding: EdgeInsets.all(Design.dz(12)),
                decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: .34),
                    borderRadius: BorderRadius.circular(Design.dz(12)),
                    border: Border.all(color: s.text.withValues(alpha: .07))),
                child: SingleChildScrollView(
                    child: Text(_preview,
                        style: TextStyle(
                            fontFamily: 'monospace',
                            fontSize: Design.dz(10.5),
                            height: 1.6,
                            color: s.muted)))),
          ],
          SizedBox(height: Design.dz(14)),
          const DesignFieldLabel('磁盘余量'),
          SizedBox(height: Design.dz(6)),
          _KvRow('日志目录', 'filesDir/logs/'),
          _KvRow('单文件 / 份数',
              '${kb(maxFileBytes)} · ${maxFiles == null ? '—' : '$maxFiles 份'}'),
          _KvRow('总字节上限', mb(maxTotalBytes), muted: '两道约束取更严'),
          _KvRow('余量保护',
              minFreeBytes == null ? '—' : '剩余 < ${mb(minFreeBytes)} 停写'),
          SizedBox(height: Design.dz(14)),
          const DesignFieldLabel('包内有什么'),
          SizedBox(height: Design.dz(8)),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
                child: _InfoCard(
                    'summary.txt', '环境、版本、权限、车机通道、子系统快照、锚点统计、设置全部取值')),
            SizedBox(width: Design.dz(9)),
            Expanded(
                child: _InfoCard(
                    'logs/', '全部日志文件，按超限后不超过 4 MB；超出了只在最新的一条写 summary 注明'))
          ])
        ]));
  }
}

/// `.diag-tag`：24 高的小标签 + 5 的圆点。授予时是主题色，未授予时降成
/// 灰淡一档——灰色比主题色更「缺东西」，不会和右边的动作抢注意力。
class _PermissionTag extends StatelessWidget {
  final bool granted;
  const _PermissionTag({required this.granted});
  @override
  Widget build(BuildContext context) {
    final s = SurfaceStyle.of(context);
    final color = granted ? s.accent : s.muted;
    return Container(
        height: Design.dz(24),
        padding: EdgeInsets.symmetric(horizontal: Design.dz(9)),
        decoration: BoxDecoration(
            color: color.withValues(alpha: .07),
            borderRadius: BorderRadius.circular(Design.dz(8)),
            border: Border.all(color: color.withValues(alpha: .26))),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Container(
              width: Design.dz(5),
              height: Design.dz(5),
              decoration: BoxDecoration(shape: BoxShape.circle, color: color)),
          SizedBox(width: Design.dz(6)),
          Text(granted ? '存储权限已授予' : '存储权限未授予',
              style: TextStyle(fontSize: Design.dz(12), color: color))
        ]));
  }
}

class _Stat extends StatelessWidget {
  final String label, value, unit;
  const _Stat(this.label, this.value, this.unit);
  @override
  Widget build(BuildContext context) {
    final s = SurfaceStyle.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label,
          style: TextStyle(
              fontSize: Design.dz(10.5),
              letterSpacing: Design.dz(1.6),
              color: s.muted)),
      SizedBox(height: Design.dz(4)),
      Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(value,
                style: TextStyle(
                    fontSize: Design.dz(19),
                    fontWeight: FontWeight.w300,
                    color: s.text.withValues(alpha: .9))),
            SizedBox(width: Design.dz(2)),
            Text(unit,
                style: TextStyle(fontSize: Design.dz(11.5), color: s.muted))
          ])
    ]);
  }
}

class _KvRow extends StatelessWidget {
  final String name, value;
  final String? muted;
  const _KvRow(this.name, this.value, {this.muted});
  @override
  Widget build(BuildContext context) {
    final s = SurfaceStyle.of(context);
    return Padding(
        padding: EdgeInsets.symmetric(vertical: Design.dz(5)),
        child: Row(children: [
          SizedBox(
              width: Design.dz(104),
              child: Text(name,
                  style: TextStyle(fontSize: Design.dz(13), color: s.muted))),
          Expanded(
              child: Text(value,
                  textAlign: TextAlign.left,
                  style: TextStyle(
                      fontSize: Design.dz(13),
                      color: s.text.withValues(alpha: .8)))),
          if (muted != null)
            Text(muted!,
                style: TextStyle(fontSize: Design.dz(11.5), color: s.muted))
        ]));
  }
}

class _InfoCard extends StatelessWidget {
  final String name, body;
  const _InfoCard(this.name, this.body);
  @override
  Widget build(BuildContext context) {
    final s = SurfaceStyle.of(context);
    return Container(
        padding: EdgeInsets.fromLTRB(
            Design.dz(12), Design.dz(9), Design.dz(12), Design.dz(10)),
        decoration: BoxDecoration(
            color: s.text.withValues(alpha: .02),
            borderRadius: BorderRadius.circular(Design.dz(12)),
            border: Border.all(color: s.text.withValues(alpha: .07))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(name,
              style: TextStyle(fontSize: Design.dz(11.5), color: s.accent)),
          SizedBox(height: Design.dz(4)),
          Text(body,
              style: TextStyle(
                  fontSize: Design.dz(11), height: 1.6, color: s.muted))
        ]));
  }
}

/// `.diag-btn`：44 高的胶囊按钮；主按钮是主题色渐变，幽灵按钮无底无边。
class _DiagButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final bool primary, ghost;
  final VoidCallback? onPressed;
  const _DiagButton(this.label,
      {this.icon, this.primary = false, this.ghost = false, this.onPressed});
  @override
  Widget build(BuildContext context) {
    final content = Row(mainAxisSize: MainAxisSize.min, children: [
      if (icon != null) ...[
        Icon(icon, size: Design.dz(15)),
        SizedBox(width: Design.dz(7))
      ],
      Text(label, style: TextStyle(fontSize: Design.dz(13.5)))
    ]);
    if (ghost) return TextButton(onPressed: onPressed, child: content);
    return ChoiceButton(
        selected: primary,
        onPressed: onPressed,
        height: Design.controlHeight,
        shrink: true,
        child: content);
  }
}
