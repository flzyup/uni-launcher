import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uni_launcher/controller/launcher_controller.dart';
import 'package:uni_launcher/model/appearance.dart';
import 'package:uni_launcher/model/card_layout.dart';
import 'package:uni_launcher/theme/launcher_theme.dart';
import 'package:uni_launcher/widgets/card_content.dart';
import 'package:uni_launcher/widgets/glass_surface.dart';
import 'fake_gateway.dart';

void main() {
  for (final type in ['calendar', 'cleanup']) {
    testWidgets('$type has an OEM entry without claiming live fields',
        (t) async {
      final g = FakeGateway()..state['demo'] = false;
      final c = LauncherController(g);
      await c.initialize();
      final style = SurfaceStyle.from(const Appearance(mode: 'dark'), true);
      final card =
          LauncherCard('entry', type, specFor(type).label, 0, 0, 4, 3, 0);
      await t.pumpWidget(MaterialApp(
          theme: launcherTheme(style),
          home: Scaffold(
              body: Center(
                  child: SizedBox(
                      width: 360,
                      height: 230,
                      child: GlassSurface(
                          padding: EdgeInsets.zero,
                          child: CardContent(card: card, controller: c)))))));
      await t.pumpAndSettle();
      final button = find.widgetWithText(
          OutlinedButton,
          switch (type) {
            'cleanup' => '打开清理',
            'calendar' => '打开日历',
            _ => '打开日历',
          });
      expect(button, findsOneWidget);
      expect(find.textContaining('未同步'), findsNothing);
      expect(find.textContaining('已同步'), findsNothing);
      await t.tap(button);
      await t.pumpAndSettle();
      expect(g.commands.last['action'], 'official-widget');
      expect(g.commands.last['value'], type);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox.shrink());
      c.dispose();
      await g.dispose();
    });
  }
  testWidgets('member card shows account summary and opens unified details',
      (t) async {
    t.view.physicalSize = const Size(1920, 1080);
    t.view.devicePixelRatio = 1;
    final g = FakeGateway()
      ..state['demo'] = false
      ..state['systemStatus'] = {
        'account': {
          'known': true,
          'loggedIn': true,
          'name': '车主账号',
          'memberLevel': 4,
          'memberLevelName': '银卡会员',
          'source': 'member-provider'
        }
      };
    final c = LauncherController(g);
    await c.initialize();
    final style = SurfaceStyle.from(const Appearance(mode: 'dark'), true);
    const card = LauncherCard('member-live', 'member', '账号', 0, 0, 4, 3, 0);
    await t.pumpWidget(MaterialApp(
        theme: launcherTheme(style),
        home: Scaffold(
            body: Center(
                child: SizedBox(
                    width: 500,
                    height: 380,
                    child: GlassSurface(
                        padding: EdgeInsets.zero,
                        child: CardContent(card: card, controller: c)))))));
    await t.pumpAndSettle();
    expect(find.text('车主账号'), findsOneWidget);
    expect(find.text('已登录'), findsOneWidget);
    expect(find.text('银卡会员'), findsOneWidget);
    expect(find.text('点击查看账号详情'), findsOneWidget);
    expect(find.text('打开账号中心'), findsNothing);

    await t.tap(find.byKey(const ValueKey('member-card-open')));
    await t.pumpAndSettle();
    expect(find.text('账号详情'), findsOneWidget);
    expect(
        find.byKey(const ValueKey('account-profile-detail')), findsOneWidget);
    expect(
        t.widget<GlassSurface>(
            find.byKey(const ValueKey('account-profile-detail'))),
        isA<GlassSurface>());
    expect(
        find.descendant(
            of: find.byKey(const ValueKey('account-profile-detail')),
            matching: find.text('车主账号')),
        findsNWidgets(2));
    expect(find.text('原车会员中心'), findsOneWidget);
    expect(find.text('会员等级'), findsOneWidget);
    expect(find.text('银卡会员'), findsNWidgets(2));

    await t.tap(find.byKey(const ValueKey('account-open-center')));
    await t.pumpAndSettle();
    expect(g.commands.last['action'], 'official-widget');
    expect(g.commands.last['value'], 'member');
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox.shrink());
    c.dispose();
    await g.dispose();
    t.view.resetPhysicalSize();
    t.view.resetDevicePixelRatio();
  });
  testWidgets('weather card opens the detailed forecast sheet', (t) async {
    t.view.physicalSize = const Size(1920, 1080);
    t.view.devicePixelRatio = 1;
    final g = FakeGateway();
    final c = LauncherController(g);
    await c.initialize();
    final style = SurfaceStyle.from(const Appearance(mode: 'dark'), true);
    const card = LauncherCard('weather-live', 'weather', '天气', 0, 0, 4, 2, 0);
    await t.pumpWidget(MaterialApp(
        theme: launcherTheme(style),
        home: Scaffold(
            body: Center(
                child: SizedBox(
                    width: 620,
                    height: 300,
                    child: GlassSurface(
                        padding: EdgeInsets.zero,
                        child: CardContent(card: card, controller: c)))))));
    await t.pumpAndSettle();
    expect(find.text('打开天气'), findsNothing);
    await t.tap(find.byKey(const ValueKey('weather-card-open')));
    await t.pumpAndSettle();
    expect(find.text('天气详情'), findsOneWidget);
    expect(
        find.byKey(const ValueKey('weather-current-detail')), findsOneWidget);
    expect(find.byKey(const ValueKey('weather-forecast-0')), findsOneWidget);
    expect(
        t.widget<GlassSurface>(
            find.byKey(const ValueKey('weather-current-detail'))),
        isA<GlassSurface>());
    expect(
        t.widget<GlassSurface>(
            find.byKey(const ValueKey('weather-forecast-0'))),
        isA<GlassSurface>());
    expect(find.text('未来天气'), findsOneWidget);
    expect(g.commands.last['action'], 'weather-forecast-refresh');
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox.shrink());
    c.dispose();
    await g.dispose();
    t.view.resetPhysicalSize();
    t.view.resetDevicePixelRatio();
  });
  testWidgets('calendar renders system date and upcoming agenda', (t) async {
    final g = FakeGateway()
      ..state['demo'] = false
      ..state['calendar'] = {
        'available': true,
        'authorized': true,
        'day': 26,
        'weekday': '星期一',
        'monthLabel': '2026 年 10 月',
        'eventAvailable': true,
        'title': '车辆保养',
        'location': '领克中心',
        'beginMs': DateTime(2026, 10, 26, 10, 30).millisecondsSinceEpoch,
      };
    final c = LauncherController(g);
    await c.initialize();
    final style = SurfaceStyle.from(const Appearance(mode: 'dark'), true);
    const card = LauncherCard('calendar-live', 'calendar', '日历', 0, 0, 4, 3, 0);
    await t.pumpWidget(MaterialApp(
        theme: launcherTheme(style),
        home: Scaffold(
            body: SizedBox(
                width: 480,
                height: 360,
                child: GlassSurface(
                    padding: EdgeInsets.zero,
                    child: CardContent(card: card, controller: c))))));
    await t.pumpAndSettle();
    expect(find.text('26'), findsOneWidget);
    expect(find.text('星期一'), findsOneWidget);
    expect(find.text('车辆保养'), findsOneWidget);
    expect(find.text('10:30 · 领克中心'), findsOneWidget);
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox.shrink());
    c.dispose();
    await g.dispose();
  });
}
