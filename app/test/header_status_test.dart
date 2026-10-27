import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uni_launcher/controller/launcher_controller.dart';
import 'package:uni_launcher/launcher_app.dart';
import 'package:uni_launcher/model/appearance.dart';
import 'package:uni_launcher/theme/launcher_theme.dart';
import 'package:uni_launcher/widgets/system_status_row.dart';
import 'package:uni_launcher/widgets/card_content.dart';
import 'package:uni_launcher/model/card_layout.dart';
import 'fake_gateway.dart';

void main() {
  testWidgets(
      'settings shortcut bootstrap opens settings without a header gear',
      (t) async {
    t.view.physicalSize = const Size(1920, 1080);
    t.view.devicePixelRatio = 1;
    final g = FakeGateway();
    g.state['initialSettings'] = true;
    final controller = LauncherController(g);
    await controller.initialize();
    await t.pumpWidget(LauncherApp(controller: controller));
    await t.pumpAndSettle();
    expect(controller.settings, isTrue);
    expect(find.byKey(const ValueKey('desktop-settings-entry')), findsNothing);
    expect(find.text('桌面设置'), findsOneWidget);
    await t.pumpWidget(const SizedBox());
    controller.dispose();
    await g.dispose();
    t.view.resetPhysicalSize();
    t.view.resetDevicePixelRatio();
  });
  test(
      'desktop name migrates old preferences, strips newlines and bounds input',
      () {
    expect(Appearance.fromJson({}).desktopName, Appearance.defaultDesktopName);
    expect(Appearance.fromJson({'desktopName': '\n '}).desktopName,
        Appearance.defaultDesktopName);
    expect(const Appearance().copyWith(desktopName: ' 我的领克\n05 ').desktopName,
        '我的领克 05');
    final a = const Appearance().copyWith(desktopName: '领克' * 40);
    expect(a.desktopName.runes.length, 24);
    expect(Appearance.fromJson(a.toJson()).desktopName, a.desktopName);
  });
  testWidgets(
      'long press edits the desktop name and persists across controller reload',
      (t) async {
    t.view.physicalSize = const Size(1920, 1080);
    t.view.devicePixelRatio = 1;
    final g = FakeGateway(), c = LauncherController(g);
    await c.initialize();
    await t.pumpWidget(LauncherApp(controller: c));
    await t.pumpAndSettle();
    await t.longPress(find.byKey(const ValueKey('desktop-name')));
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const ValueKey('desktop-name-input')), '我的领克');
    await t.tap(find.byKey(const ValueKey('desktop-name-save')));
    await t.pumpAndSettle();
    expect(find.text('我的领克'), findsOneWidget);
    expect(jsonDecode(g.saved!)['preferences']['desktopName'], '我的领克');
    g.state['savedDesign'] = g.saved;
    final reloaded = LauncherController(g);
    await reloaded.initialize();
    expect(reloaded.appearance.desktopName, '我的领克');
    await t.tap(find.byKey(const ValueKey('system-back')));
    expect(g.commands.last['action'], 'system-back');
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox.shrink());
    c.dispose();
    reloaded.dispose();
    await g.dispose();
    t.view.resetPhysicalSize();
    t.view.resetDevicePixelRatio();
  });
  testWidgets('member card reuses the same live account as the header',
      (t) async {
    final g = FakeGateway();
    g.state['demo'] = false;
    g.state['systemStatus'] = {
      'account': {'known': true, 'loggedIn': true, 'name': '我的账号'}
    };
    final c = LauncherController(g);
    await c.initialize();
    await t.pumpWidget(MaterialApp(
        theme: launcherTheme(SurfaceStyle.from(const Appearance(), true)),
        home: Scaffold(
            body: SizedBox(
                width: 600,
                height: 600,
                child: CardContent(
                    card:
                        LauncherCard('account', 'member', '账号', 0, 0, 4, 4, 0),
                    controller: c)))));
    await t.pumpAndSettle();
    expect(find.text('我的账号'), findsOneWidget);
    expect(find.text('已登录'), findsOneWidget);
    expect(find.text('账号状态未同步'), findsNothing);
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox.shrink());
    c.dispose();
    await g.dispose();
  });
  testWidgets(
      'status area renders real slots and no placeholders for unknown values',
      (t) async {
    t.view.physicalSize = const Size(1920, 1080);
    t.view.devicePixelRatio = 1;
    Future<void> show(Map<String, dynamic> state) async {
      await t.pumpWidget(MaterialApp(
          theme: launcherTheme(SurfaceStyle.from(const Appearance(), true)),
          home: Scaffold(body: SystemStatusRow(status: state))));
      await t.pumpAndSettle();
    }

    await show({});
    expect(find.byIcon(Icons.bluetooth), findsNothing);
    expect(find.text('4G'), findsNothing);
    await show({
      'network': {
        'mobileKnown': true,
        'mobileEnabled': true,
        'mobileLevel': 3,
        'mobileLabel': '4G',
        'hotspot': true,
        'clients': 2
      },
      'bluetooth': {'known': true, 'enabled': true, 'connected': true},
      'charging': {'visible': true, 'error': false},
      'usb': {'visible': true, 'count': 1},
      'dvr': {'visible': true, 'recording': true},
      'messages': {'count': 3},
      'account': {'known': true, 'loggedIn': true, 'name': '车主'},
    });
    for (final slot in [
      'mobile',
      'hotspot',
      'bluetooth',
      'charging',
      'usb',
      'dvr',
      'messages',
      'account'
    ]) {
      expect(find.byKey(ValueKey('status-$slot')), findsOneWidget);
    }
    expect(find.text('车主'), findsOneWidget);
    expect(find.text('4G'), findsOneWidget);
    expect(t.takeException(), isNull);
    t.view.resetPhysicalSize();
    t.view.resetDevicePixelRatio();
  });
}
