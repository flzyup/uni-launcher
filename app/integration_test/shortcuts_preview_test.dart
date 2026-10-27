import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:uni_launcher/controller/launcher_controller.dart';
import 'package:uni_launcher/launcher_app.dart';
import 'package:uni_launcher/model/card_layout.dart';
import 'package:uni_launcher/platform/native_gateway.dart';
import '../test/fake_gateway.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('shortcut card selection, capacity, removal and persistence',
      (t) async {
    // Use the emulator's actual app list/icons; intercept launch and persistence
    // so the test cannot change another app or a user's saved desktop.
    final native = await AndroidGateway().bootstrap();
    final apps = (native['apps'] as List)
        .whereType<Map>()
        .where((a) => a['id'] is String)
        .map((a) => Map<String, dynamic>.from(a))
        .toList();
    expect(apps.length, greaterThanOrEqualTo(5));
    apps.sort((a, b) => (a['package'] == 'com.android.calculator2' ? 0 : 1)
        .compareTo(b['package'] == 'com.android.calculator2' ? 0 : 1));
    expect(apps.first['package'], 'com.android.calculator2');
    final gateway = FakeGateway()..state['apps'] = apps;
    final c = LauncherController(gateway);
    await c.initialize();
    c.cards = [
      const LauncherCard('nav', 'nav', '导航', 0, 0, 8, 6, 0),
      const LauncherCard('music', 'music', '正在播放', 8, 0, 4, 4, 0),
      const LauncherCard('quick', 'shortcuts', '快捷应用', 8, 4, 4, 2, 0),
    ];
    c.pageCount = 1;
    c.setAppearance(
        c.appearance.copyWith(themeStyle: 'blueGlass', mode: 'dark'),
        save: false);
    await t.pumpWidget(LauncherApp(controller: c));
    await t.pumpAndSettle();
    await binding.convertFlutterSurfaceToImage();
    await t.pumpAndSettle();
    await binding.takeScreenshot('shortcuts-empty-4x2');
    await t.tap(find.byKey(const ValueKey('shortcuts-add-quick')));
    await t.pumpAndSettle();
    await binding.takeScreenshot('shortcuts-picker');
    for (final app in apps.take(4)) {
      final option = find.byKey(ValueKey('shortcut-option-${app['id']}'));
      await t.ensureVisible(option);
      await t.tap(option);
      await t.pumpAndSettle();
    }
    final fifth = find.byKey(ValueKey('shortcut-option-${apps[4]['id']}'));
    await t.ensureVisible(fifth);
    expect(t.widget<ListTile>(fifth).enabled, isFalse);
    await t.tap(find.byKey(const ValueKey('shortcut-picker-save')));
    await t.pumpAndSettle();
    expect(c.cards.last.shortcutApps.length, 4);
    expect((jsonDecode(gateway.saved!)['cards'] as List).last['shortcutApps'],
        hasLength(4));
    await binding.takeScreenshot('shortcuts-four-4x2');
    final firstId = apps.first['id'] as String;
    await t.tap(find.byKey(ValueKey('shortcut-$firstId')));
    await t.pumpAndSettle();
    expect(
        gateway.commands
            .any((v) => v['action'] == 'launch-app' && v['value'] == firstId),
        isTrue);
    await t.tap(find.byKey(const ValueKey('shortcuts-edit-quick')));
    await t.pumpAndSettle();
    final firstOption = find.byKey(ValueKey('shortcut-option-$firstId'));
    await t.ensureVisible(firstOption);
    await t.tap(firstOption);
    await t.tap(find.byKey(const ValueKey('shortcut-picker-save')));
    await t.pumpAndSettle();
    expect(c.cards.last.shortcutApps, hasLength(3));
    expect(find.byKey(ValueKey('shortcut-$firstId')), findsNothing);
    gateway.state['savedDesign'] = gateway.saved;
    final restored = LauncherController(gateway);
    await restored.initialize();
    expect(restored.cards.last.shortcutApps, c.cards.last.shortcutApps);
    restored.dispose();
    for (final height in [3, 4]) {
      c.cards = [
        LauncherCard('quick', 'shortcuts', '快捷应用', 0, 0, 4, height, 0,
            shortcutApps: apps
                .take(height == 3 ? 8 : 12)
                .map((a) => a['id'] as String)
                .toList())
      ];
      c.setAppearance(c.appearance, save: false);
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      await binding.takeScreenshot('shortcuts-full-4x$height');
    }
    c.beginEdit();
    c.remove('quick');
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('add-card')));
    await t.pumpAndSettle();
    final addShortcuts = find.byKey(const ValueKey('add-shortcuts'));
    await t.ensureVisible(addShortcuts);
    await t.tap(addShortcuts);
    await t.pumpAndSettle();
    expect(c.cards.where((card) => card.type == 'shortcuts'), hasLength(1));
    expect((c.cards.single.w, c.cards.single.h), (4, 2));
    c.finishEdit();
    await t.pumpAndSettle();
    await t.pumpWidget(const SizedBox.shrink());
    c.dispose();
    await gateway.dispose();
  });
}
