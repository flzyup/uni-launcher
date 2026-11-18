import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uni_launcher/controller/launcher_controller.dart';
import 'package:uni_launcher/launcher_app.dart';
import 'fake_gateway.dart';

/// 计划书 §2.4：设置页左导航 6 → 10 分类。垃圾清理必须是一级分类，
/// 不能只藏在右下角 UNI 菜单里；进页即触发一次扫描（与面板入口同一条链路）。
void main() {
  Future<(LauncherController, FakeGateway)> open(WidgetTester t,
      {String theme = 'nocturne', String tab = 'cleaner'}) async {
    t.view.physicalSize = const Size(1920, 1080);
    t.view.devicePixelRatio = 1;
    final g = FakeGateway();
    g.state['demo'] = false;
    final c = LauncherController(g);
    await c.initialize();
    c.setAppearance(c.appearance.copyWith(themeStyle: theme), save: false);
    await t.pumpWidget(LauncherApp(controller: c));
    c.openSettings();
    await t.pumpAndSettle();
    await t.tap(find.byKey(ValueKey('tab-$tab')));
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

  testWidgets('settings nav carries all ten categories', (t) async {
    final (_, g) = await open(t, tab: 'appearance');
    for (final id in [
      'appearance',
      'dock',
      'connections',
      'motion',
      'ambient',
      'cluster',
      'memory',
      'cleaner',
      'system',
      'about',
    ]) {
      expect(find.byKey(ValueKey('tab-$id')), findsOneWidget,
          reason: '缺少一级分类 $id');
    }
    expect(g.commands.where((c) => c['action'] == 'cleaner-scan'), isEmpty);
    expect(t.takeException(), isNull);
  });

  testWidgets('cleaner tab mounts the panel and asks for a scan', (t) async {
    final (_, g) = await open(t);
    expect(find.byKey(const ValueKey('cleaner-headline')), findsOneWidget);
    expect(find.text('已清理干净'), findsOneWidget);
    expect(g.commands.where((c) => c['action'] == 'cleaner-scan'), isNotEmpty);
    expect(t.takeException(), isNull);
  });

  for (final theme in ['classic', 'blueGlass', 'nocturne']) {
    testWidgets('cleaner tab opens on $theme without leaking', (t) async {
      await open(t, theme: theme);
      expect(find.byKey(const ValueKey('cleaner-headline')), findsOneWidget);
      expect(t.takeException(), isNull);
    });
  }
}
