import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uni_launcher/controller/launcher_controller.dart';
import 'package:uni_launcher/launcher_app.dart';
import 'fake_gateway.dart';

void main() {
  Future<(LauncherController, FakeGateway)> open(WidgetTester t,
      {bool available = true}) async {
    t.view.physicalSize = const Size(1920, 1080);
    t.view.devicePixelRatio = 1;
    final g = FakeGateway();
    g.state['systemSettings'] = {
      'entries': [
        {
          'id': 'oem/wifi',
          'label': '无线网络',
          'source': '车辆设置',
          'package': 'test.settings',
          'activity': 'test.settings.Main',
          'action': 'test.settings.WIFI'
        },
        {
          'id': 'android/display',
          'label': '屏幕显示',
          'source': 'Android 设置',
          'package': 'com.android.settings',
          'activity': 'DisplaySettings',
          'action': 'android.settings.DISPLAY_SETTINGS'
        }
      ],
      'navigationAudio': {
        'available': available,
        'mode': 2,
        'modes': [
          {'value': 1, 'label': '自动混音'},
          {'value': 2, 'label': '导航混音'}
        ],
        'reason': '设备未提供可用的导航混音接口'
      }
    };
    final c = LauncherController(g);
    await c.initialize();
    await t.pumpWidget(LauncherApp(controller: c));
    c.openSettings();
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('tab-system')));
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

  testWidgets('settings uses resource labels and launches selected entry',
      (t) async {
    final (_, g) = await open(t);
    expect(g.commands,
        contains(containsPair('action', 'refresh-system-settings')));
    await t.scrollUntilVisible(
        find.byKey(const ValueKey('system-setting-oem/wifi')), 350,
        scrollable: find
            .descendant(
                of: find.byKey(const PageStorageKey('system-settings-scroll')),
                matching: find.byType(Scrollable))
            .first);
    await t.pumpAndSettle();
    expect(find.text('无线网络'), findsOneWidget);
    expect(find.text('屏幕显示'), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('system-setting-oem/wifi')));
    await t.pumpAndSettle();
    expect(g.commands.last, containsPair('action', 'open-system-setting'));
    expect(g.commands.last, containsPair('value', 'oem/wifi'));
    expect(t.takeException(), isNull);
  });

  testWidgets('audio mode reflects state and sends only explicit selection',
      (t) async {
    final (_, g) = await open(t);
    expect(
        t
            .widget<ChoiceChip>(
                find.byKey(const ValueKey('navigation-audio-2')))
            .selected,
        isTrue);
    expect(g.commands.where((c) => c['action'] == 'navigation-audio-mode'),
        isEmpty);
    await t.ensureVisible(find.byKey(const ValueKey('navigation-audio-1')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('navigation-audio-1')));
    await t.pumpAndSettle();
    expect(g.commands.last, containsPair('action', 'navigation-audio-mode'));
    expect(g.commands.last, containsPair('value', '1'));
  });

  testWidgets('unavailable OEM interface cannot change navigation mixing',
      (t) async {
    final (_, g) = await open(t, available: false);
    expect(find.byType(ChoiceChip), findsNothing);
    expect(find.byKey(const ValueKey('navigation-audio-unavailable')),
        findsOneWidget);
    expect(g.commands.where((c) => c['action'] == 'navigation-audio-mode'),
        isEmpty);
  });
  testWidgets(
      'telemetry-only event preserves explicitly fetched settings catalog',
      (t) async {
    final (c, g) = await open(t);
    final catalog = c.native.value['systemSettings'];
    final event = Map<String, dynamic>.from(g.state)..remove('systemSettings');
    event['media'] = {'title': '新歌曲'};
    g.stream.add(event);
    await t.pumpAndSettle();
    expect(identical(c.native.value['systemSettings'], catalog), isTrue);
    await t.scrollUntilVisible(
        find.byKey(const ValueKey('system-setting-oem/wifi')), 350,
        scrollable: find
            .descendant(
                of: find.byKey(const PageStorageKey('system-settings-scroll')),
                matching: find.byType(Scrollable))
            .first);
    await t.pumpAndSettle();
    expect(find.text('无线网络'), findsOneWidget);
    expect((c.native.value['media'] as Map)['title'], '新歌曲');
  });
}
