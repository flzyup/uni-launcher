import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uni_launcher/controller/launcher_controller.dart';
import 'package:uni_launcher/launcher_app.dart';
import 'package:uni_launcher/widgets/file_transfer_popup.dart';
import 'fake_gateway.dart';

/// 夸克页的行为边界：未登录只推登录命令；已登录时目录项点进去、文件勾选才入队。
/// 登录轮询、cookie 刷新、取下载链都在原生侧，这里只验证界面把命令拼对了。
void main() {
  Map<String, dynamic> quark({
    String state = 'idle',
    String qrImage = '',
    String nickname = '',
    List<dynamic> entries = const [],
    List<dynamic> crumbs = const [
      {'fid': '0', 'name': '根目录'}
    ],
    String error = '',
    int total = 0,
  }) =>
      {
        'state': state,
        'qrImage': qrImage,
        'expiresIn': 120,
        'nickname': nickname,
        'memberType': 'SUPER_VIP',
        'totalCapacity': 10 * 1024 * 1024 * 1024,
        'useCapacity': 1024 * 1024 * 1024,
        'pdir': '0',
        'page': 1,
        'total': total == 0 ? entries.length : total,
        'crumbs': crumbs,
        'entries': entries,
        'error': error,
      };

  Map<String, dynamic> entry(String fid, String name,
          {bool dir = false, int size = 1024}) =>
      {
        'fid': fid,
        'name': name,
        'size': size,
        'dir': dir,
        'updatedAt': 1793000000000,
        'category': 0
      };

  Future<(LauncherController, FakeGateway)> openQuark(WidgetTester t,
      {required Map<String, dynamic> state}) async {
    t.view.physicalSize = const Size(1920, 1080);
    t.view.devicePixelRatio = 1;
    final g = FakeGateway();
    g.state = {
      ...g.state,
      'transfer': {
        'running': false,
        'ip': '',
        'port': -1,
        'url': '',
        'mode': 'none',
        'files': const [],
        'links': const [],
      },
      'quark': state,
    };
    final c = LauncherController(g);
    await c.initialize();
    await t.pumpWidget(LauncherApp(controller: c));
    await t.pumpAndSettle();
    unawaited(
        showFileTransferPopup(t.element(find.byKey(const ValueKey('home'))), c));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('transfer-tab-quark')));
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

  testWidgets('默认落在手机扫码，切到夸克页才出现登录按钮', (t) async {
    final (_, g) = await openQuark(t, state: quark());
    expect(find.byKey(const ValueKey('quark-login')), findsOneWidget);
    expect(find.text('扫码登录后可浏览夸克网盘目录'), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('quark-login')));
    await t.pumpAndSettle();
    expect(
        g.commands,
        contains(predicate(
            (Map<String, dynamic> m) => m['action'] == 'quark-login')));
  });

  testWidgets('等待扫码时显示二维码与刷新入口', (t) async {
    final (_, g) = await openQuark(
        t,
        state: quark(
            state: 'waiting',
            // 1×1 PNG：长度 96，能被 base64 正常解出一帧
            qrImage: 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4'
                '2mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg=='));
    expect(find.text('刷新二维码'), findsOneWidget);
    expect(find.text('已扫码，请在手机上确认'), findsNothing);
    await t.tap(find.byKey(const ValueKey('quark-login')));
    await t.pumpAndSettle();
    expect(
        g.commands,
        contains(predicate((Map<String, dynamic> m) =>
            m['action'] == 'quark-login-refresh')));
  });

  testWidgets('登录失效的错误文案原样透出，并给重新扫码的按钮', (t) async {
    await openQuark(t,
        state: quark(state: 'error', error: '夸克登录已失效，请重新扫码'));
    expect(find.text('夸克登录已失效，请重新扫码'), findsOneWidget);
    expect(find.text('扫码登录'), findsOneWidget);
  });

  testWidgets('文件夹点进去带 fid|名字，文件勾选后才入队', (t) async {
    final (_, g) = await openQuark(
        t,
        state: quark(state: 'authorized', nickname: '阿柑', entries: [
          entry('dir1', '电影', dir: true),
          entry('f1', 'app.apk', size: 4096),
        ]));
    expect(find.text('阿柑'), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('quark-entry-dir1')));
    await t.pumpAndSettle();
    expect(
        g.commands,
        contains(predicate((Map<String, dynamic> m) =>
            m['action'] == 'quark-open' && m['value'] == 'dir1|电影')));

    await t.tap(find.byKey(const ValueKey('quark-entry-f1')));
    await t.pumpAndSettle();
    expect(find.text('已选 1 个文件'), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('quark-enqueue')));
    await t.pumpAndSettle();
    expect(
        g.commands,
        contains(predicate((Map<String, dynamic> m) =>
            m['action'] == 'quark-enqueue' && m['value'] == 'f1')));
  });

  testWidgets('更多分页按钮只在还有剩余时出现', (t) async {
    final (_, g) = await openQuark(
        t,
        state: quark(state: 'authorized', entries: [entry('f1', 'a.bin')], total: 5));
    expect(find.byKey(const ValueKey('quark-more')), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('quark-more')));
    await t.pumpAndSettle();
    expect(
        g.commands,
        contains(
            predicate((Map<String, dynamic> m) => m['action'] == 'quark-more')));
  });
}
