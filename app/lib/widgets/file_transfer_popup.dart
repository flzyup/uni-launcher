import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../controller/launcher_controller.dart';
import '../theme/design_tokens.dart';
import '../theme/launcher_theme.dart';
import 'glass_surface.dart';

/// A compact, right-aligned panel above the global dock.
Future<void> showFileTransferPopup(
        BuildContext context, LauncherController c) =>
    Navigator.of(context).push(_TransferRoute(c));

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
              width: Design.px(600),
              height: Design.px(650),
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
              SizedBox(height: Design.px(12)),
              if (running && url.isNotEmpty)
                Center(
                    child: Column(children: [
                  Container(
                      color: Colors.white,
                      padding: EdgeInsets.all(Design.px(10)),
                      child: QrImageView(
                          data: url,
                          size: Design.px(190),
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
              SizedBox(height: Design.px(12)),
              Text('已接收文件（${files.length}）',
                  style: TextStyle(fontSize: Design.px(20))),
              SizedBox(height: Design.px(8)),
              Expanded(
                  child: files.isEmpty
                      ? Center(
                          child:
                              Text('尚未收到文件', style: TextStyle(color: s.muted)))
                      : ListView.builder(
                          itemCount: files.length,
                          itemBuilder: (context, i) {
                            final f =
                                files[i] is Map ? files[i] as Map : const {};
                            final name = '${f['name'] ?? ''}';
                            return Row(children: [
                              Expanded(
                                  child: Text(name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis)),
                              TextButton(
                                  onPressed: () => controller
                                      .command('transfer-install', value: name),
                                  child: const Text('安装')),
                              TextButton(
                                  onPressed: () => controller
                                      .command('transfer-delete', value: name),
                                  child: const Text('删除')),
                            ]);
                          })),
            ]);
      });
}
