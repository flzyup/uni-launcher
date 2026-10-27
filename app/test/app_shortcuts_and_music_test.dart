import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uni_launcher/controller/launcher_controller.dart';
import 'package:uni_launcher/launcher_app.dart';
import 'package:uni_launcher/model/card_layout.dart';
import 'package:uni_launcher/widgets/music_app_picker.dart';
import 'fake_gateway.dart';

void main() {
  test('music options only contain detected players and live sessions', () {
    final options = musicAppOptions({
      'apps': [
        {'id': 'qq/.Main', 'package': 'qq', 'label': 'QQ', 'isMusic': true},
        {'id': 'maps/.Main', 'package': 'maps', 'label': 'Map'},
        {'id': 'session/.Main', 'package': 'session', 'label': 'Session'},
        {'id': 'qq/.Alt', 'package': 'qq', 'label': 'QQ'},
      ],
      'media': {
        'sessions': [
          {'package': 'session'}
        ]
      },
    });
    expect(options.map((a) => a['package']), ['qq', 'session']);
  });

  testWidgets('music card picker excludes non-players and changes source',
      (t) async {
    t.view.physicalSize = const Size(1920, 1080);
    t.view.devicePixelRatio = 1;
    final g = FakeGateway();
    g.state['apps'] = [
      {'id': 'qq/.Main', 'package': 'qq', 'label': 'QQ音乐', 'isMusic': true},
      {'id': 'map/.Main', 'package': 'map', 'label': '地图'},
    ];
    final c = LauncherController(g);
    await c.initialize();
    c.cards = [const LauncherCard('music-1', 'music', '音乐', 0, 0, 4, 3, 0)];
    await t.pumpWidget(LauncherApp(controller: c));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('music-app-picker')));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('music-option-qq')), findsOneWidget);
    expect(find.byKey(const ValueKey('music-option-map')), findsNothing);
    await t.tap(find.byKey(const ValueKey('music-option-qq')));
    await t.pumpAndSettle();
    expect(
        g.commands
            .any((v) => v['action'] == 'select-player' && v['value'] == 'qq'),
        isTrue);
    await t.pumpWidget(const SizedBox());
    c.dispose();
    await g.dispose();
    t.view.resetPhysicalSize();
    t.view.resetDevicePixelRatio();
  });

  testWidgets('settings entry in app list closes panel and opens settings',
      (t) async {
    t.view.physicalSize = const Size(1920, 1080);
    t.view.devicePixelRatio = 1;
    final g = FakeGateway();
    g.state['apps'] = [
      {
        'id': 'xyz.i4o.uni.launcher/.DesktopSettings',
        'package': 'xyz.i4o.uni.launcher',
        'label': 'UNI桌面设置'
      }
    ];
    final c = LauncherController(g);
    await c.initialize();
    await t.pumpWidget(LauncherApp(controller: c));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('all-apps')));
    await t.pumpAndSettle();
    await t
        .tap(find.byKey(const ValueKey('app-icon-ink-xyz.i4o.uni.launcher')));
    await t.pumpAndSettle();
    expect(c.settings, isTrue);
    expect(find.text('UNI桌面设置'), findsNothing);
    expect(find.text('桌面设置'), findsOneWidget);
    await t.pumpWidget(const SizedBox());
    c.dispose();
    await g.dispose();
    t.view.resetPhysicalSize();
    t.view.resetDevicePixelRatio();
  });

  testWidgets(
      'shortcut layouts render their supported capacities without overflow',
      (t) async {
    t.view.physicalSize = const Size(1920, 1080);
    t.view.devicePixelRatio = 1;
    final g = FakeGateway();
    g.state['apps'] = [
      for (var i = 0; i < 12; i++)
        {'id': 'p$i/.Main', 'package': 'p$i', 'label': '应用$i'}
    ];
    final c = LauncherController(g);
    await c.initialize();
    for (final height in [2, 3, 4]) {
      c.cards = [
        LauncherCard('short-1', 'shortcuts', '快捷应用', 0, 0, 4, height, 0,
            shortcutApps: [for (var i = 0; i < 12; i++) 'p$i/.Main'])
      ];
      await t.pumpWidget(LauncherApp(key: ValueKey(height), controller: c));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull, reason: '4x$height');
      expect(find.byKey(const ValueKey('shortcut-p0/.Main')), findsOneWidget);
    }
    await t.pumpWidget(const SizedBox());
    c.dispose();
    await g.dispose();
    t.view.resetPhysicalSize();
    t.view.resetDevicePixelRatio();
  });

  testWidgets('shortcut selection persists per card and launches selected app',
      (t) async {
    t.view.physicalSize = const Size(1920, 1080);
    t.view.devicePixelRatio = 1;
    final g = FakeGateway();
    g.state['apps'] = [
      {'id': 'one/.Main', 'package': 'one', 'label': '应用一'},
      {'id': 'two/.Main', 'package': 'two', 'label': '应用二'},
    ];
    final c = LauncherController(g);
    await c.initialize();
    c.cards = [
      const LauncherCard('short-1', 'shortcuts', '快捷应用', 0, 0, 4, 3, 0)
    ];
    await t.pumpWidget(LauncherApp(controller: c));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('shortcuts-edit-short-1')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('shortcut-option-one/.Main')));
    await t.tap(find.byKey(const ValueKey('shortcut-option-two/.Main')));
    await t.tap(find.byKey(const ValueKey('shortcut-picker-save')));
    await t.pumpAndSettle();
    expect(c.cards.first.shortcutApps, ['one/.Main', 'two/.Main']);
    expect((jsonDecode(g.saved!)['cards'] as List).first['shortcutApps'],
        ['one/.Main', 'two/.Main']);
    await t.tap(find.byKey(const ValueKey('shortcut-one/.Main')));
    await t.pumpAndSettle();
    expect(
        g.commands.any(
            (x) => x['action'] == 'launch-app' && x['value'] == 'one/.Main'),
        isTrue);
    await t.tap(find.byKey(const ValueKey('shortcuts-edit-short-1')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('shortcut-option-one/.Main')));
    await t.tap(find.byKey(const ValueKey('shortcut-picker-save')));
    await t.pumpAndSettle();
    expect(c.cards.first.shortcutApps, ['two/.Main']);
    g.state['savedDesign'] = g.saved;
    final restored = LauncherController(g);
    await restored.initialize();
    expect(restored.cards.first.shortcutApps, ['two/.Main']);
    restored.dispose();
    await t.pumpWidget(const SizedBox());
    c.dispose();
    await g.dispose();
    t.view.resetPhysicalSize();
    t.view.resetDevicePixelRatio();
  });
}
