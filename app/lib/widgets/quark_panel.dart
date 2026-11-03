import 'package:flutter/material.dart';
import 'dart:convert';
import 'dart:typed_data';

import '../controller/launcher_controller.dart';
import '../theme/design_tokens.dart';
import '../theme/launcher_theme.dart';

/// 夸克网盘：扫码登录 → 目录浏览 → 勾选后交给传文件队列。
///
/// 这里只画界面：登录轮询、cookie 刷新、取下载链全在原生 [QuarkPan] 里，
/// 因为传文件面板关掉时 FlutterEngine 会被销毁，而下载不该跟着断。
class QuarkBrowser extends StatefulWidget {
  final LauncherController controller;

  /// 未登录时给一个「从手机上传」的出口，由外层面板切回第一个标签。
  final VoidCallback? onShowPhone;
  const QuarkBrowser({super.key, required this.controller, this.onShowPhone});

  @override
  State<QuarkBrowser> createState() => _QuarkBrowserState();
}

class _QuarkBrowserState extends State<QuarkBrowser> {
  final Set<String> _selected = <String>{};
  String _pdir = '';
  bool _autoListed = false;

  static Map<String, dynamic> _map(Object? v) =>
      v is Map ? Map<String, dynamic>.from(v) : {};

  static String _size(num bytes) {
    final b = bytes.toDouble();
    if (b >= 1 << 30) return '${(b / (1 << 30)).toStringAsFixed(2)} GB';
    if (b >= 1 << 20) return '${(b / (1 << 20)).toStringAsFixed(1)} MB';
    if (b >= 1 << 10) return '${(b / (1 << 10)).toStringAsFixed(0)} KB';
    return '${bytes.toInt()} B';
  }

  static String _time(num ms) {
    if (ms <= 0) return '';
    final d = DateTime.fromMillisecondsSinceEpoch(ms.toInt());
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(d.month)}-${two(d.day)} ${two(d.hour)}:${two(d.minute)}';
  }

  static String _member(String type) => switch (type) {
        'SUPER_VIP' => '超级会员',
        'Z_VIP' => '会员',
        'EXP_SVIP' => '体验会员',
        '' => '普通用户',
        _ => type,
      };

  void _command(String action, [String? value]) =>
      widget.controller.command(action, value: value);

  Widget _button(String label,
          {VoidCallback? onTap, bool filled = false, Key? key, double? width}) =>
      SizedBox(
          width: width,
          child: TextButton(
              key: key,
              style: TextButton.styleFrom(
                  minimumSize: Size(Design.px(width == null ? 64 : 40), Design.px(44)),
                  backgroundColor: filled
                      ? SurfaceStyle.of(context).accent.withValues(alpha: 0.16)
                      : null,
                  padding: EdgeInsets.symmetric(horizontal: Design.px(10)),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap),
              onPressed: onTap,
              child: Text(label,
                  style: TextStyle(
                      fontSize: Design.px(18),
                      color: onTap == null
                          ? SurfaceStyle.of(context).muted
                          : null))));

  Widget _status(String text, SurfaceStyle s, {Color? color, Key? key}) => Padding(
      key: key,
      padding: EdgeInsets.symmetric(vertical: Design.px(6)),
      child: Text(text,
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: Design.px(17), color: color ?? s.muted)));

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Map<String, dynamic>>(
        valueListenable: widget.controller.native,
        builder: (context, native, _) {
          final s = SurfaceStyle.of(context);
          final q = _map(native['quark']);
          final state = '${q['state'] ?? 'idle'}';
          final authorized = state == 'authorized';
          final waiting = state == 'waiting' || state == 'scanned';
          final qrImage = '${q['qrImage'] ?? ''}';
          // 服务端给的图偶尔会截断，解不出来就当没有；不能让一次坏数据把整页打崩。
          Uint8List? qrBytes;
          if (qrImage.isNotEmpty) {
            try {
              qrBytes = base64Decode(qrImage);
            } catch (_) {
              qrBytes = null;
            }
          }
          final errorText = '${q['error'] ?? ''}';
          final pdir = '${q['pdir'] ?? '0'}';
          // 换目录就清空勾选，避免把上一层的 fid 提交上去。
          if (pdir != _pdir) {
            _pdir = pdir;
            _selected.clear();
          }
          final entries = q['entries'] is List ? q['entries'] as List : const [];
          final crumbs = q['crumbs'] is List ? q['crumbs'] as List : const [];
          final total = (q['total'] as num?)?.toInt() ?? entries.length;
          // 登录态是原生侧静默恢复的，进面板时列表还是空的：替用户拉一次根目录。
          if (!authorized) {
            _autoListed = false;
          } else if (entries.isEmpty && !_autoListed) {
            _autoListed = true;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) _command('quark-list');
            });
          }

          if (!authorized) {
            return Center(
                child: SingleChildScrollView(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
              if (waiting && qrBytes != null) ...[
                Container(
                    color: Colors.white,
                    padding: EdgeInsets.all(Design.px(8)),
                    child: Image.memory(
                        qrBytes,
                        key: const ValueKey('quark-qr'),
                        width: Design.px(260),
                        height: Design.px(260),
                        gaplessPlayback: true,
                        filterQuality: FilterQuality.none)),
                _status(
                    state == 'scanned'
                        ? '已扫码，请在手机上确认'
                        : '手机夸克 App › 扫一扫 › 确认授权',
                    s),
              ] else ...[
                Icon(Icons.qr_code_2, size: Design.px(96), color: s.muted),
                _status(
                    errorText.isNotEmpty
                        ? errorText
                        : state == 'expired'
                            ? '二维码已过期'
                            : '扫码登录后可浏览夸克网盘目录',
                    s,
                    key: const ValueKey('quark-status'),
                    color: errorText.isNotEmpty ? s.accent : null),
              ],
              SizedBox(height: Design.px(12)),
              Row(mainAxisSize: MainAxisSize.min, children: [
                _button(waiting ? '刷新二维码' : '扫码登录',
                    key: const ValueKey('quark-login'),
                    filled: true,
                    width: 150,
                    onTap: () => _command(
                        waiting ? 'quark-login-refresh' : 'quark-login')),
                SizedBox(width: Design.px(10)),
                _button('从手机上传',
                    width: 130,
                    onTap: widget.onShowPhone),
              ]),
              if (state == 'waiting')
                _status('登录一次长期有效，失效时再来扫一次', s),
            ])));
          }

          final nickname = '${q['nickname'] ?? ''}';
          final memberType = '${q['memberType'] ?? ''}';
          final totalCap = (q['totalCapacity'] as num?)?.toDouble() ?? 0;
          final useCap = (q['useCapacity'] as num?)?.toDouble() ?? 0;
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Icon(Icons.cloud_done_outlined, size: Design.px(22), color: s.accent),
              SizedBox(width: Design.px(8)),
              Expanded(
                  child: Text(
                      nickname.isEmpty ? '已登录夸克网盘' : nickname,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: Design.px(20)))),
              if (totalCap > 0)
                Text('${_size(useCap)} / ${_size(totalCap)}',
                    style: TextStyle(fontSize: Design.px(15), color: s.muted)),
              SizedBox(width: Design.px(8)),
              Text(_member(memberType),
                  style: TextStyle(fontSize: Design.px(15), color: s.accent)),
              SizedBox(width: Design.px(6)),
              _button('退出',
                  key: const ValueKey('quark-logout'),
                  onTap: () => _command('quark-logout')),
            ]),
            SizedBox(height: Design.px(6)),
            SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(children: [
                  for (var i = 0; i < crumbs.length; i++)
                    Row(children: [
                      if (i > 0)
                        Padding(
                            padding: EdgeInsets.symmetric(horizontal: Design.px(4)),
                            child: Text('›',
                                style: TextStyle(color: s.muted, fontSize: Design.px(16)))),
                      _button('${_map(crumbs[i])['name'] ?? '目录'}',
                          onTap: () => _command('quark-open',
                              '${_map(crumbs[i])['fid'] ?? '0'}|')),
                    ]),
                  if (pdir != '0')
                    _button('返回上级', onTap: () => _command('quark-open', '..')),
                ])),
            if (errorText.isNotEmpty)
              _status(errorText, s, color: s.accent,
                  key: const ValueKey('quark-error')),
            Expanded(
                child: entries.isEmpty
                    ? Center(
                        child: Text('这个目录是空的',
                            style: TextStyle(fontSize: Design.px(18), color: s.muted)))
                    : ListView.separated(
                        itemCount: entries.length + (entries.length < total ? 1 : 0),
                        separatorBuilder: (_, __) => SizedBox(height: Design.px(2)),
                        itemBuilder: (context, i) {
                          if (i >= entries.length) {
                            return Center(
                                child: _button('加载更多',
                                    key: const ValueKey('quark-more'),
                                    onTap: () => _command('quark-more')));
                          }
                          final e = _map(entries[i]);
                          final fid = '${e['fid'] ?? ''}';
                          final isDir = e['dir'] == true;
                          final name = '${e['name'] ?? ''}';
                          final picked = _selected.contains(fid);
                          return InkWell(
                              key: ValueKey('quark-entry-$fid'),
                              borderRadius: BorderRadius.circular(Design.px(8)),
                              onTap: () {
                                if (isDir) {
                                  _command('quark-open', '$fid|$name');
                                  return;
                                }
                                setState(() {
                                  if (picked) {
                                    _selected.remove(fid);
                                  } else {
                                    _selected.add(fid);
                                  }
                                });
                              },
                              child: Container(
                                  padding: EdgeInsets.symmetric(
                                      horizontal: Design.px(10),
                                      vertical: Design.px(9)),
                                  decoration: BoxDecoration(
                                      color: picked ? s.soft : null,
                                      borderRadius:
                                          BorderRadius.circular(Design.px(8))),
                                  child: Row(children: [
                                    Icon(
                                        isDir
                                            ? Icons.folder_outlined
                                            : Icons.insert_drive_file_outlined,
                                        size: Design.px(22),
                                        color: isDir ? s.accent : s.muted),
                                    SizedBox(width: Design.px(10)),
                                    Expanded(
                                        child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                          Text(name,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style:
                                                  TextStyle(fontSize: Design.px(19))),
                                          Text(
                                              isDir
                                                  ? '文件夹'
                                                  : '${_size((e['size'] as num?) ?? 0)} · ${_time((e['updatedAt'] as num?) ?? 0)}',
                                              style: TextStyle(
                                                  fontSize: Design.px(14),
                                                  color: s.muted)),
                                        ])),
                                    if (!isDir)
                                      _button(picked ? '取消' : '选择',
                                          onTap: () => setState(() {
                                                if (picked) {
                                                  _selected.remove(fid);
                                                } else {
                                                  _selected.add(fid);
                                                }
                                              })),
                                  ])));
                        })),
            if (_selected.isNotEmpty)
              Padding(
                  padding: EdgeInsets.only(top: Design.px(6)),
                  child: Row(children: [
                    Expanded(
                        child: Text('已选 ${_selected.length} 个文件',
                            style: TextStyle(fontSize: Design.px(17), color: s.muted))),
                    _button('下载选中',
                        key: const ValueKey('quark-enqueue'),
                        filled: true,
                        width: 130,
                        onTap: () {
                          _command('quark-enqueue', _selected.join(','));
                          setState(_selected.clear);
                        }),
                  ])),
          ]);
        });
  }
}
