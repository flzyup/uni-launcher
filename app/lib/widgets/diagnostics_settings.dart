import 'package:flutter/material.dart';

import '../platform/log_tools.dart';
import '../platform/uni_log.dart';
import '../theme/design_tokens.dart';
import '../theme/launcher_theme.dart';
import 'glass_surface.dart';
import 'launcher_dialog.dart';

/// Diagnostics panel: export the log package, share it, and inspect the log
/// system state.
///
/// A head unit often has no debugger attached, so the package is the only way
/// to get evidence off the car: it carries the log files plus a runtime
/// snapshot (permissions, vehicle channel, spectrum, ambient light, anchors,
/// every setting key).
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
    });
  }

  /// 弹系统授权框要存储权限。
  ///
  /// 返回是否拿到了权限。
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

  /// 导出前先把存储权限要到手。
  ///
  /// Android 9 及以下要把包写进公共 Download 目录，没有写权限会直接失败。
  /// 让用户在系统弹窗里点一次「允许」，比只看到一句「需要存储权限」强。
  Future<void> _export(String label, Future<LogExportResult> Function() action) async {
    if (_busy) return;
    if (!_storageWritable) {
      final granted = await _requestPermission();
      if (!granted) return;
    }
    await _run(label, action);
  }

  Future<void> _run(String label, Future<LogExportResult> Function() action) async {
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
    final level = (status['level'] as String?) ?? 'INFO';

    return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          GlassSurface(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(children: [
                      Text('诊断日志',
                          style: TextStyle(fontSize: Design.px(26))),
                      const Spacer(),
                      if (_busy)
                        SizedBox(
                            width: Design.px(22),
                            height: Design.px(22),
                            child: CircularProgressIndicator(strokeWidth: 2))
                      else
                        IconAction(
                            icon: Icons.refresh,
                            label: '刷新日志状态',
                            onTap: _refresh,
                            size: Design.px(34)),
                    ]),
                    SizedBox(height: Design.px(14)),
                    Text('导出目录：Download/UNI/　当前占用 ${bytes ~/ 1024} KB　锚点节点 $anchors 个',
                        style:
                            TextStyle(color: s.muted, fontSize: Design.px(19))),
                    Padding(
                        padding: EdgeInsets.only(top: Design.px(8)),
                        child: Text(
                            _storageWritable
                                ? '存储权限：已授予'
                                : '⚠ 存储权限未授予，导出诊断包需要先授权',
                            style: TextStyle(
                                color: _storageWritable
                                    ? s.muted
                                    : Theme.of(context).colorScheme.error,
                                fontSize: Design.px(19)))),
                    if (degraded)
                      Padding(
                          padding: EdgeInsets.only(top: Design.px(10)),
                          child: Text(
                              '⚠ 日志落盘已降级：磁盘剩余空间不足，只写 Logcat 不写文件',
                              style: TextStyle(
                                  color: Theme.of(context).colorScheme.error,
                                  fontSize: Design.px(19)))),
                    SizedBox(height: Design.px(18)),
                    Row(children: [
                      Text('落盘级别',
                          style: TextStyle(fontSize: Design.px(21))),
                      SizedBox(width: Design.px(20)),
                      DropdownButton<String>(
                          value: level,
                          items: const [
                            DropdownMenuItem(value: 'DEBUG', child: Text('调试')),
                            DropdownMenuItem(value: 'INFO', child: Text('信息')),
                            DropdownMenuItem(value: 'WARN', child: Text('警告')),
                            DropdownMenuItem(value: 'ERROR', child: Text('仅错误')),
                          ],
                          onChanged: _busy
                              ? null
                              : (value) {
                                  if (value == null) return;
                                  LogTools.setLevel(value == 'DEBUG'
                                      ? UniLogLevel.debug
                                      : value == 'WARN'
                                          ? UniLogLevel.warn
                                          : value == 'ERROR'
                                              ? UniLogLevel.error
                                              : UniLogLevel.info);
                                  _refresh();
                                }),
                      const Spacer(),
                    ]),
                    SizedBox(height: Design.px(12)),
                    Text('「调试」会把全部细节写入文件，车机存储紧张时建议用「信息」。',
                        style: TextStyle(color: s.muted, fontSize: Design.px(18))),
                    SizedBox(height: Design.px(18)),
                    Wrap(spacing: Design.px(14), runSpacing: Design.px(12), children: [
                      FilledButton(
                          onPressed: _busy
                              ? null
                              : () => _export('导出诊断包', LogTools.export),
                          child: const Text('导出诊断包')),
                      OutlinedButton(
                          onPressed: _busy
                              ? null
                              : () => _export(
                                  '导出并分享诊断包', LogTools.exportAndShare),
                          child: const Text('导出并分享')),
                      OutlinedButton(
                          onPressed: _busy ? null : _loadPreview,
                          child: const Text('预览最近日志')),
                      TextButton(
                          onPressed: _busy ? null : _clear,
                          child: const Text('清空日志')),
                      if (!_storageWritable)
                        OutlinedButton(
                            onPressed: _busy ? null : _requestPermission,
                            child: const Text('申请存储权限')),
                    ]),
                    if (_previewOpen) ...[
                      SizedBox(height: Design.px(16)),
                      Container(
                          width: double.infinity,
                          padding: EdgeInsets.all(Design.px(14)),
                          decoration: BoxDecoration(
                              color: s.dark
                                  ? const Color(0x14000000)
                                  : const Color(0x14FFFFFF),
                              borderRadius:
                                  BorderRadius.circular(s.controlRadius)),
                          child: Text(_preview,
                              style: TextStyle(
                                  fontFamily: 'monospace',
                                  fontSize: Design.px(16),
                                  height: 1.4,
                                  color: s.muted))),
                    ],
                  ])),
        ]);
  }
}
