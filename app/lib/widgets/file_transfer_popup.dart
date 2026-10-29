import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../controller/launcher_controller.dart';
import '../theme/design_tokens.dart';
import '../theme/launcher_theme.dart';
import 'glass_surface.dart';
import 'dock_window_scope.dart';

/// A compact, right-aligned panel above the global dock.
Future<void> showFileTransferPopup(
    BuildContext context, LauncherController c) async {
  if (await c.presentGlobalPanel('transfer') || !context.mounted) return;
  final scope = DockWindowScope.of(context);
  final closed = Navigator.of(context).push(_TransferRoute(c));
  if (scope?.onPresented != null) {
    await WidgetsBinding.instance.endOfFrame;
    if (context.mounted) await scope!.onPresented!();
  }
  await closed;
}

class _TransferRoute extends PopupRoute<void> {
  final LauncherController launcherController;
  _TransferRoute(this.launcherController);
  @override
  Color? get barrierColor => null;
  @override
  bool get barrierDismissible => true;
  @override
  String get barrierLabel => '关闭传文件';
  @override
  Duration get transitionDuration => const Duration(milliseconds: 180);
  @override
  Widget buildPage(BuildContext context, Animation<double> animation,
      Animation<double> secondaryAnimation) {
    final panel = launcherController.native.value['hostMode'] == 'global-panel';
    return Stack(children: [
      Positioned(
          right: Design.px(14),
          bottom: Design.px(panel ? 14 : 110),
          child: SizedBox(
              width: Design.px(640),
              height: Design.px(860),
              child: GlassSurface(
                  key: const ValueKey('transfer-popup'),
                  padding: EdgeInsets.all(Design.px(24)),
                  child: _TransferPanel(controller: launcherController))))
    ]);
  }

  @override
  Widget buildTransitions(BuildContext context, Animation<double> animation,
          Animation<double> secondaryAnimation, Widget child) =>
      FadeTransition(opacity: animation, child: child);
}

class _TransferPanel extends StatelessWidget {
  final LauncherController controller;
  const _TransferPanel({required this.controller});

  /// 待下载任务的状态文案；失败时带原因，避免只看到一个红字。
  static String _linkStatus(Map link) {
    final status = '${link['status'] ?? 'queued'}';
    final error = '${link['error'] ?? ''}'.trim();
    return switch (status) {
      'downloading' => '下载中…',
      'failed' => error.isEmpty ? '下载失败' : '失败：$error',
      _ => '待下载',
    };
  }

  /// 文件名前面的来源标：链接任务用来源主机，手机上传的直接标「手机上传」。
  Widget _sourceTag(String label, SurfaceStyle s) => ConstrainedBox(
      constraints: BoxConstraints(maxWidth: Design.px(170)),
      child: Container(
          padding: EdgeInsets.symmetric(
              horizontal: Design.px(9), vertical: Design.px(3)),
          decoration: BoxDecoration(
              border: Border.all(color: s.edge),
              borderRadius: BorderRadius.circular(Design.px(7))),
          child: Text(label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: Design.px(15), color: s.muted))));

  /// 下载 / 安装 / 删除 共用同一套按钮尺寸，行与行之间才不会参差。
  Widget _button(String label, VoidCallback? onTap) => TextButton(
      style: TextButton.styleFrom(
          minimumSize: Size(Design.px(56), Design.px(40)),
          padding: EdgeInsets.symmetric(horizontal: Design.px(8)),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap),
      onPressed: onTap,
      child: Text(label, style: TextStyle(fontSize: Design.px(18))));

  Widget _row(SurfaceStyle s,
          {Key? key,
          required String source,
          required String title,
          String? note,
          List<Widget> actions = const []}) =>
      Padding(
          key: key,
          padding: EdgeInsets.symmetric(vertical: Design.px(5)),
          child: Row(children: [
            _sourceTag(source, s),
            SizedBox(width: Design.px(10)),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: Design.px(19))),
                  if (note != null && note.isNotEmpty)
                    Text(note,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: Design.px(15), color: s.muted)),
                ])),
            ...actions,
          ]));

  Widget _linkRow(SurfaceStyle s, Map link) {
    final id = '${link['id'] ?? ''}';
    final host = '${link['host'] ?? ''}';
    final status = '${link['status'] ?? 'queued'}';
    final busy = status == 'downloading';
    final name = '${link['name'] ?? ''}'.trim();
    return _row(s,
        key: ValueKey('transfer-link-$id'),
        source: host,
        title: name.isEmpty ? host : name,
        note: _linkStatus(link),
        actions: [
          // 手机只能入队；真正开始下载必须由车机点这一下触发。
          _button(busy ? '下载中' : '下载',
              busy ? null : () => controller.command('transfer-link-download', value: id)),
          _button('删除', () => controller.command('transfer-link-remove', value: id)),
        ]);
  }

  Widget _fileRow(SurfaceStyle s, Map file, String? host) {
    final name = '${file['name'] ?? ''}';
    return _row(s,
        key: ValueKey('transfer-file-$name'),
        source: (host == null || host.isEmpty) ? '手机上传' : host,
        title: name,
        actions: [
          _button('安装', () => controller.command('transfer-install', value: name)),
          _button('删除', () => controller.command('transfer-delete', value: name)),
        ]);
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<
          Map<String, dynamic>>(
      valueListenable: controller.native,
      builder: (context, native, _) {
        final s = SurfaceStyle.of(context);
        final data = native['transfer'] is Map
            ? Map<String, dynamic>.from(native['transfer'] as Map)
            : <String, dynamic>{};
        final running = data['running'] == true;
        final url = '${data['url'] ?? ''}';
        final files = data['files'] is List ? data['files'] as List : [];
        final allLinks = data['links'] is List ? data['links'] as List : [];
        final links = [
          for (final link in allLinks)
            if (link is Map && '${link['status']}' != 'done') link
        ];
        // 下载完成的链接已经落到文件里，用主机名给那一行当来源标，避免重复列一行。
        final sources = <String, String>{
          for (final link in allLinks)
            if (link is Map && '${link['status']}' == 'done')
              '${link['name'] ?? ''}': '${link['host'] ?? ''}'
        };
        final rows = <Widget>[
          for (final link in links) _linkRow(s, link),
          for (final file in files)
            _fileRow(s, file is Map ? file : const {},
                sources['${(file is Map ? file : const {})['name'] ?? ''}']),
        ];
        return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(children: [
                Expanded(
                    child: Text('传文件',
                        style: TextStyle(
                            fontSize: Design.px(26),
                            fontWeight: FontWeight.w500))),
                IconAction(
                    icon: Icons.close,
                    label: '关闭传文件',
                    size: Design.px(48),
                    framed: false,
                    onTap: () => Navigator.pop(context)),
              ]),
              DesignSwitchTile(
                  key: const ValueKey('transfer-switch'),
                  contentPadding: EdgeInsets.zero,
                  title: const Text('开启传文件'),
                  subtitle: Text(running ? '手机与车机连接同一网络' : '开启后扫码上传文件'),
                  value: running,
                  onChanged: (v) => controller
                      .command(v ? 'transfer-start' : 'transfer-stop')),
              SizedBox(height: Design.px(10)),
              if (running && url.isNotEmpty)
                Center(
                    child: Column(children: [
                  Container(
                      color: Colors.white,
                      padding: EdgeInsets.all(Design.px(5)),
                      child: QrImageView(
                          data: url,
                          size: Design.px(300),
                          padding: EdgeInsets.zero,
                          backgroundColor: Colors.white)),
                  SizedBox(height: Design.px(8)),
                  SelectableText(url,
                      key: const ValueKey('transfer-url'),
                      style:
                          TextStyle(color: s.accent, fontSize: Design.px(19))),
                ]))
              else
                Center(
                    child: Padding(
                        padding: EdgeInsets.symmetric(vertical: Design.px(20)),
                        child: Text(running ? '未检测到可用网络地址' : '开启后显示二维码与访问地址',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: s.muted)))),
              SizedBox(height: Design.px(10)),
              Expanded(
                  child: rows.isEmpty
                      ? Center(
                          child: Text('还没有文件，扫码上传或让手机发送链接',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: s.muted)))
                      : ListView(children: rows)),
            ]);
      });
}
