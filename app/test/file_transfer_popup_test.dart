import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uni_launcher/controller/launcher_controller.dart';
import 'package:uni_launcher/launcher_app.dart';
import 'package:uni_launcher/widgets/file_transfer_popup.dart';
import 'fake_gateway.dart';

/// 手机端只能把链接入队；真正开始下载必须由车机上的点击触发。
void main() {
  Map<String, dynamic> transferPacket(List<dynamic> links,
          [List<dynamic> files = const []]) =>
      {
        'running': true,
        'ip': '192.168.1.5',
        'port': 8787,
        'url': 'http://192.168.1.5:8787/',
        'mode': 'wifi',
        'files': files,
        'links': links,
      };

  Map<String, dynamic> link(String id, String host, String name,
          {String status = 'queued', String error = ''}) =>
      {
        'id': id,
        'url': 'https://$host/$name',
        'host': host,
        'name': name,
        'status': status,
        'size': 0,
        'time': 0,
        'error': error
      };

  Map<String, dynamic> file(String name) =>
      {'name': name, 'size': 1024, 'time': 1793000000000};

  Future<(LauncherController, FakeGateway)> openPanel(WidgetTester t,
      {required List<dynamic> links, List<dynamic> files = const []}) async {
    t.view.physicalSize = const Size(1920, 1080);
    t.view.devicePixelRatio = 1;
    final g = FakeGateway();
    g.state = {
      ...g.state,
      'transfer': transferPacket(links, files)
    };
    final c = LauncherController(g);
    await c.initialize();
    await t.pumpWidget(LauncherApp(controller: c));
    await t.pumpAndSettle();
    // 真实入口是底部菜单的「传文件」，这里直接推同一个路由。
    unawaited(
        showFileTransferPopup(t.element(find.byKey(const ValueKey('home'))), c));
    await t.pumpAndSettle();
    addTearDown(() async {
      await t.pumpWidget(const SizedBox.shrink());
      c.dispose();
      await g.dispose();
      t.view.resetPhysicalSize();
      t.view.resetDevicePixelRatio();
    });
    return (c, g);
  }

  testWidgets('下载任务和已接收文件排在同一个列表里，各自带来源标', (t) async {
    await openPanel(t, links: [
      link('a1', 'dl.example.com', 'app.apk'),
      link('a2', 'files.example.com', 'movie.mkv', status: 'failed', error: 'HTTP 404'),
    ], files: [
      file('upload.apk'),
    ]);
    expect(find.byKey(const ValueKey('transfer-popup')), findsOneWidget);
    // 不再有分组标题，链接行和文件行同处一列。
    expect(find.textContaining('待下载链接'), findsNothing);
    expect(find.textContaining('已接收文件'), findsNothing);
    expect(find.byKey(const ValueKey('transfer-link-a1')), findsOneWidget);
    expect(find.byKey(const ValueKey('transfer-file-upload.apk')), findsOneWidget);
    // 来源标：链接用主机，上传的直接标「手机上传」。
    expect(find.text('dl.example.com'), findsOneWidget);
    expect(find.text('手机上传'), findsOneWidget);
    expect(find.text('待下载'), findsOneWidget);
    // 失败任务必须说明原因，不能只留一个红点。
    expect(find.text('失败：HTTP 404'), findsOneWidget);
    expect(t.takeException(), null);
  });

  testWidgets('只渲染队列不会触发下载，点按钮才下发命令', (t) async {
    final (_, g) = await openPanel(t, links: [
      link('a1', 'dl.example.com', 'app.apk')
    ], files: [
      file('upload.apk')
    ]);
    expect(g.commands, isEmpty, reason: '只渲染列表不该产生任何命令');
    await t.tap(find.descendant(
        of: find.byKey(const ValueKey('transfer-link-a1')),
        matching: find.text('下载')));
    await t.pumpAndSettle();
    expect(
        g.commands,
        contains(predicate((Map<String, dynamic> m) =>
            m['action'] == 'transfer-link-download' && m['value'] == 'a1')));
  });

  testWidgets('链接行和文件行的删除按钮走各自的命令', (t) async {
    final (_, g) =
        await openPanel(t, links: [link('a1', 'dl.example.com', 'app.apk')], files: [
      file('upload.apk')
    ]);
    await t.tap(find.descendant(
        of: find.byKey(const ValueKey('transfer-link-a1')),
        matching: find.text('删除')));
    await t.tap(find.descendant(
        of: find.byKey(const ValueKey('transfer-file-upload.apk')),
        matching: find.text('删除')));
    await t.pumpAndSettle();
    expect(
        g.commands,
        contains(predicate((Map<String, dynamic> m) =>
            m['action'] == 'transfer-link-remove' && m['value'] == 'a1')));
    expect(
        g.commands,
        contains(predicate((Map<String, dynamic> m) =>
            m['action'] == 'transfer-delete' && m['value'] == 'upload.apk')));
  });

  testWidgets('下载中的任务不能再点，按钮显示下载中', (t) async {
    await openPanel(t, links: [
      link('b1', 'dl.example.com', 'done.apk', status: 'downloading')
    ]);
    expect(find.text('下载中'), findsOneWidget);
    final button = t.widget<TextButton>(find
        .descendant(
            of: find.byKey(const ValueKey('transfer-link-b1')),
            matching: find.byType(TextButton))
        .first);
    expect(button.onPressed, isNull);
  });

  testWidgets('已下载完成的链接不再单独占一行，文件行标出来源主机', (t) async {
    await openPanel(t, links: [
      link('c1', 'dl.example.com', 'pulled.apk', status: 'done')
    ], files: [
      file('pulled.apk'),
      file('upload.apk'),
    ]);
    expect(find.byKey(const ValueKey('transfer-link-c1')), findsNothing);
    expect(find.text('dl.example.com'), findsOneWidget);
    expect(find.text('手机上传'), findsOneWidget);
    expect(find.text('安装'), findsNWidgets(2));
    expect(t.takeException(), null);
  });

  testWidgets('空列表给出一次说明', (t) async {
    await openPanel(t, links: const []);
    expect(find.text('还没有文件，扫码上传或让手机发送链接'), findsOneWidget);
    expect(t.takeException(), null);
  });
}
