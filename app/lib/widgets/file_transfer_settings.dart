import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../controller/launcher_controller.dart';
import '../theme/design_tokens.dart';
import '../theme/launcher_theme.dart';
import 'glass_surface.dart';

/// 局域网传文件：开启后本机起一个微型 HTTP 服务器，把地址编进二维码，
/// 手机扫码后在浏览器里把 APK 上传到车机，车机端可选择安装或删除。
class FileTransferSettings extends StatelessWidget {
  final LauncherController controller;
  const FileTransferSettings({super.key, required this.controller});

  static Map<String, dynamic> _map(Object? v) =>
      v is Map ? Map<String, dynamic>.from(v) : {};

  static String _size(int bytes) {
    if (bytes >= 1 << 30) return '${(bytes / (1 << 30)).toStringAsFixed(1)} GB';
    if (bytes >= 1 << 20) return '${(bytes / (1 << 20)).toStringAsFixed(1)} MB';
    if (bytes >= 1 << 10) return '${(bytes / (1 << 10)).toStringAsFixed(1)} KB';
    return '$bytes B';
  }

  static String _time(int ms) {
    final d = DateTime.fromMillisecondsSinceEpoch(ms);
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(d.month)}-${two(d.day)} ${two(d.hour)}:${two(d.minute)}';
  }

  static String _mode(String m) => switch (m) {
        'wifi' => 'WiFi 局域网',
        'hotspot' => '车机热点',
        'other' => '当前网络',
        _ => '未检测到网络',
      };

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Map<String, dynamic>>(
        valueListenable: controller.native,
        builder: (context, n, _) {
          final c = controller, s = SurfaceStyle.of(context);
          final t = _map(n['transfer']);
          final running = t['running'] == true;
          final url = '${t['url'] ?? ''}';
          final mode = _mode('${t['mode'] ?? 'none'}');
          final files = t['files'] is List ? t['files'] as List : const [];

          return LayoutBuilder(builder: (context, box) {
            return SingleChildScrollView(
                child: SizedBox(
                    height: box.maxHeight < Design.px(620)
                        ? Design.px(620)
                        : box.maxHeight,
                    child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(
                              flex: 2,
                              child: GlassSurface(
                                  padding: EdgeInsets.all(Design.px(30)),
                                  child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: [
                                        DesignSwitchTile(
                                            key: const ValueKey(
                                                'transfer-switch'),
                                            contentPadding: EdgeInsets.zero,
                                            title: Text('开启传文件',
                                                style: TextStyle(
                                                    fontSize: Design.px(26),
                                                    fontWeight:
                                                        FontWeight.w500)),
                                            subtitle: Text(
                                                running
                                                    ? '服务器运行中，手机与车机需在同一网络'
                                                    : '开启后在车机屏幕显示二维码',
                                                style: TextStyle(
                                                    fontSize: Design.px(18),
                                                    color: s.muted)),
                                            value: running,
                                            onChanged: (v) => v
                                                ? c.command('transfer-start')
                                                : c.command('transfer-stop')),
                                        SizedBox(height: Design.px(20)),
                                        Expanded(
                                            child: running && url.isNotEmpty
                                                ? Center(
                                                    child: Column(
                                                        mainAxisSize:
                                                            MainAxisSize.min,
                                                        children: [
                                                          Container(
                                                              padding:
                                                                  EdgeInsets.all(
                                                                      Design
                                                                          .px(14)),
                                                              color: Colors
                                                                  .white,
                                                              child: QrImageView(
                                                                  data: url,
                                                                  version: QrVersions
                                                                      .auto,
                                                                  size: Design
                                                                      .px(360),
                                                                  backgroundColor:
                                                                      Colors
                                                                          .white,
                                                                  gapless:
                                                                      false)),
                                                          SizedBox(
                                                              height:
                                                                  Design.px(
                                                                      18)),
                                                          Text(url,
                                                              style: TextStyle(
                                                                  fontSize: Design
                                                                      .px(22),
                                                                  color: s.accent)),
                                                          SizedBox(
                                                              height: Design
                                                                  .px(6)),
                                                          Text('$mode · 手机扫码后浏览器打开上传页',
                                                              style: TextStyle(
                                                                  fontSize:
                                                                      Design.px(
                                                                          18),
                                                                  color:
                                                                      s.muted))
                                                        ]))
                                                : Center(
                                                    child: Text(
                                                        running
                                                            ? '未检测到可用网络地址\n请确认已连接 WiFi 或开启车机热点后重试'
                                                            : '开启后此处显示二维码\n手机扫码即可向车机上传 APK',
                                                        textAlign:
                                                            TextAlign.center,
                                                        style: TextStyle(
                                                            fontSize: Design.px(
                                                                20),
                                                            color: s.muted,
                                                            height: 1.7))))
                                      ]))),
                          SizedBox(width: Design.px(16)),
                          Expanded(
                              child: GlassSurface(
                                  padding: EdgeInsets.all(Design.px(30)),
                                  child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: [
                                        Row(children: [
                                          Text('已接收文件',
                                              style: TextStyle(
                                                  fontSize: Design.px(26),
                                                  fontWeight: FontWeight.w500)),
                                          const Spacer(),
                                          Text('${files.length} 个',
                                              style: TextStyle(
                                                  fontSize: Design.px(18),
                                                  color: s.muted))
                                        ]),
                                        SizedBox(height: Design.px(16)),
                                        Expanded(
                                            child: files.isEmpty
                                                ? Center(
                                                    child: Text('尚未收到文件',
                                                        style: TextStyle(
                                                            fontSize: Design.px(
                                                                20),
                                                            color: s.muted)))
                                                : ListView.separated(
                                                    itemCount: files.length,
                                                    separatorBuilder: (_, __) =>
                                                        SizedBox(
                                                            height:
                                                                Design.px(10)),
                                                    itemBuilder: (context, i) {
                                                      final f = _map(files[i]);
                                                      final name =
                                                          '${f['name'] ?? ''}';
                                                      return Container(
                                                          padding: EdgeInsets
                                                              .symmetric(
                                                                  horizontal: Design
                                                                      .px(16),
                                                                  vertical:
                                                                      Design.px(
                                                                          12)),
                                                          decoration: BoxDecoration(
                                                              color: s.soft,
                                                              borderRadius:
                                                                  BorderRadius
                                                                      .circular(
                                                                          Design
                                                                              .px(10))),
                                                          child: Row(children: [
                                                            Expanded(
                                                                child: Column(
                                                                    crossAxisAlignment:
                                                                        CrossAxisAlignment
                                                                            .start,
                                                                    children: [
                                                                      Text(name,
                                                                          maxLines: 1,
                                                                          overflow:
                                                                              TextOverflow.ellipsis,
                                                                          style: TextStyle(
                                                                              fontSize: Design.px(20))),
                                                                      SizedBox(
                                                                          height:
                                                                              Design.px(4)),
                                                                      Text(
                                                                          '${_size((f['size'] as num?)?.toInt() ?? 0)} · ${_time((f['time'] as num?)?.toInt() ?? 0)}',
                                                                          style: TextStyle(
                                                                              fontSize: Design.px(16),
                                                                              color: s.muted))
                                                                    ])),
                                                            TextButton(
                                                                onPressed: () => c
                                                                    .command(
                                                                        'transfer-install',
                                                                        value:
                                                                            name),
                                                                child: const Text(
                                                                    '安装')),
                                                            TextButton(
                                                                onPressed: () => c
                                                                    .command(
                                                                        'transfer-delete',
                                                                        value:
                                                                            name),
                                                                child: const Text(
                                                                    '删除'))
                                                          ]));
                                                    }))
                                      ])))
                        ])));
          });
        });
  }
}
