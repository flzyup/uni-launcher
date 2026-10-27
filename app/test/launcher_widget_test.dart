import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uni_launcher/controller/launcher_controller.dart';
import 'package:uni_launcher/launcher_app.dart';
import 'package:uni_launcher/widgets/glass_surface.dart';
import 'package:uni_launcher/model/card_layout.dart';
import 'fake_gateway.dart';

void main() {
  Future<(LauncherController, FakeGateway)> launch(WidgetTester t) async {
    t.view.physicalSize = const Size(1920, 1080);
    t.view.devicePixelRatio = 1;
    final g = FakeGateway(), c = LauncherController(g);
    await c.initialize();
    await t.pumpWidget(LauncherApp(controller: c));
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

  testWidgets('home uses Flutter cards with zero blur filters by default',
      (t) async {
    await launch(t);
    expect(find.byType(BackdropFilter), findsNothing);
    expect(find.byKey(const ValueKey('nav-1')), findsOneWidget);
    final dock = t.getRect(find.byKey(const ValueKey('bottom-dock')));
    expect(dock.right, greaterThan(1850));
    expect(dock.bottom, greaterThan(1000));
    expect(t.takeException(), null);
  });
  testWidgets('home hold opens settings; blur switch adds and removes filters',
      (t) async {
    final (c, g) = await launch(t);
    c.setAppearance(c.appearance.copyWith(themeStyle: 'classic'), save: false);
    await t.longPress(find.byKey(const ValueKey('home')));
    await t.pumpAndSettle();
    expect(c.settings, true);
    await t.scrollUntilVisible(find.byKey(const ValueKey('glass-switch')), 180,
        scrollable: find.byType(Scrollable).first);
    await t.tap(find.byKey(const ValueKey('glass-switch')));
    await t.pumpAndSettle();
    expect(c.appearance.glass, true);
    expect(find.byType(BackdropFilter), findsWidgets);
    await t.tap(find.byKey(const ValueKey('glass-switch')));
    await t.pumpAndSettle();
    expect(c.appearance.glass, false);
    expect(find.byType(BackdropFilter), findsNothing);
    expect(g.saved, contains('"glass":false'));
    expect(t.takeException(), null);
  });
  testWidgets(
      'edit mode allows horizontal page swipes without starting card placement',
      (t) async {
    final (c, _) = await launch(t);
    c.beginEdit();
    await t.pumpAndSettle();
    await t.dragFrom(const Offset(1269, 700), const Offset(-700, 0));
    await t.pumpAndSettle();
    expect(c.page, 1);
    expect(c.editing, isTrue);
    expect(c.placing, isFalse);
    await t.dragFrom(const Offset(1269, 700), const Offset(700, 0));
    await t.pumpAndSettle();
    expect(c.page, 0);
  });
  testWidgets('native navigation switch sends platform action', (t) async {
    final (c, g) = await launch(t);
    c.openSettings();
    c.tab('system');
    await t.pumpAndSettle();
    await t.scrollUntilVisible(
        find.byKey(const ValueKey('system-navigation-hidden')), 300,
        scrollable: find.byType(Scrollable).first);
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('system-navigation-hidden')));
    await t.pumpAndSettle();
    expect(g.commands.last['action'], 'system-navigation-hidden');
    expect(c.native.value['systemNavigationHidden'], true);
  });
  testWidgets('card library adds card and completes persistent layout',
      (t) async {
    final (c, g) = await launch(t);
    await t.longPress(find.byKey(const ValueKey('music-1')));
    await t.pumpAndSettle();
    expect(c.editing, true);
    await t.tap(find.byKey(const ValueKey('add-card')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('add-air')));
    await t.pumpAndSettle();
    expect(c.cards.length, 10);
    await t.tap(find.byKey(const ValueKey('finish-edit')));
    await t.pumpAndSettle();
    expect(c.editing, false);
    expect(g.saved, contains('"type":"air"'));
    expect(t.takeException(), null);
  });
  testWidgets('live mode contains no illustrative navigation or weather values',
      (t) async {
    final (c, g) = await launch(t);
    g.state['demo'] = false;
    g.state['media'] = {};
    g.stream.add(Map.of(g.state));
    await t.pumpAndSettle();
    expect(find.text('600 米后右转'), findsNothing);
    expect(find.text('24°'), findsNothing);
    expect(find.text('—°').evaluate().length, greaterThanOrEqualTo(2));
    final play = t.widget<IconAction>(find.byKey(const ValueKey('play-pause')));
    expect(play.onTap, null);
    expect(c.native.value['demo'], false);
    expect(t.takeException(), null);
  });
  testWidgets('square radius and both themes render without overflow',
      (t) async {
    final (c, _) = await launch(t);
    c.setAppearance(c.appearance.copyWith(mode: 'light', radius: 0));
    await t.pumpAndSettle();
    expect(t.takeException(), null);
    c.setAppearance(c.appearance.copyWith(mode: 'dark', glass: true));
    await t.pumpAndSettle();
    expect(t.takeException(), null);
  });
  testWidgets('all card templates fit their minimum editable dimensions',
      (t) async {
    final (c, g) = await launch(t);
    t.view.physicalSize = const Size(1920, 1000);
    for (final demo in [true, false]) {
      g.state['demo'] = demo;
      g.stream.add(Map.of(g.state));
      for (final spec in cardSpecs) {
        c.cards = [
          LauncherCard('minimum-${spec.type}', spec.type, spec.label, 0, 0,
              spec.minW, spec.minH, 0)
        ];
        c.pageCount = 1;
        c.page = 0;
        c.beginEdit();
        await t.pumpAndSettle();
        expect(t.takeException(), null,
            reason: '${spec.type} at minimum size, demo=$demo');
      }
    }
  });
}
