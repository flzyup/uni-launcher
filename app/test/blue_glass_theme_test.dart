import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uni_launcher/controller/launcher_controller.dart';
import 'package:uni_launcher/launcher_app.dart';
import 'package:uni_launcher/model/appearance.dart';
import 'package:uni_launcher/screens/global_dock_app.dart';
import 'package:uni_launcher/screens/global_panel_app.dart';
import 'package:uni_launcher/widgets/scene_background.dart';
import 'package:uni_launcher/theme/design_tokens.dart';
import 'package:uni_launcher/theme/launcher_theme.dart';
import 'package:uni_launcher/theme/technical_frame.dart';
import 'package:uni_launcher/widgets/glass_surface.dart';
import 'package:uni_launcher/widgets/bottom_dock.dart';
import 'fake_gateway.dart';

void main() {
  testWidgets('dock layout is centered and uses the card radius', (t) async {
    t.view.physicalSize = const Size(1920, 1080);
    t.view.devicePixelRatio = 1;
    final gateway = FakeGateway(), controller = LauncherController(gateway);
    await controller.initialize();
    addTearDown(() async {
      await t.pumpWidget(const SizedBox.shrink());
      controller.dispose();
      await gateway.dispose();
      t.view.resetPhysicalSize();
      t.view.resetDevicePixelRatio();
    });
    for (final theme in Appearance.themeStyles) {
      for (final radius in [0.0, 25.0]) {
        final appearance = Appearance(
            themeStyle: theme, radius: radius, dockLayout: 'floating');
        controller.setAppearance(appearance, save: false);
        await t.pumpWidget(MaterialApp(
            theme: launcherTheme(SurfaceStyle.from(appearance, true)),
            home: Scaffold(
                body: Align(
                    alignment: Alignment.bottomCenter,
                    child: BottomDock(controller: controller)))));
        await t.pumpAndSettle();
        final strip = t.getRect(find.byKey(const ValueKey('bottom-dock')));
        final surface = t.getRect(find.byKey(const ValueKey('dock-surface')));
        expect(surface.center.dy, closeTo(strip.center.dy, .01));
        final widget =
            t.widget<GlassSurface>(find.byKey(const ValueKey('dock-surface')));
        expect(widget.radius, SurfaceStyle.from(appearance, true).radius);
        expect(widget.dockFramed, isTrue);
        expect(t.takeException(), isNull);
      }
    }
    final full = controller.appearance.copyWith(dockLayout: 'full');
    controller.setAppearance(full, save: false);
    await t.pumpWidget(MaterialApp(
        theme: launcherTheme(SurfaceStyle.from(full, true)),
        home: Scaffold(
            body: Align(
                alignment: Alignment.bottomCenter,
                child: BottomDock(controller: controller)))));
    await t.pumpAndSettle();
    expect(t.getRect(find.byKey(const ValueKey('dock-surface'))),
        t.getRect(find.byKey(const ValueKey('bottom-dock'))));
    expect(Appearance.fromJson(full.toJson()).dockLayout, 'full');
    expect(t.takeException(), isNull);
  });

  testWidgets('global dock extends wallpaper and adapts only climate width',
      (t) async {
    t.view.physicalSize = const Size(1920, 1080);
    t.view.devicePixelRatio = 1;
    final gateway = FakeGateway(), controller = LauncherController(gateway);
    await controller.initialize();
    addTearDown(() async {
      await t.pumpWidget(const SizedBox.shrink());
      controller.dispose();
      await gateway.dispose();
      t.view.resetPhysicalSize();
      t.view.resetDevicePixelRatio();
    });
    controller.setAppearance(
        controller.appearance.copyWith(wallpaper: 'coastal'),
        save: false);
    await t.pumpWidget(GlobalDockApp(controller: controller));
    await t.pumpAndSettle();
    expect(find.byType(SceneBackground), findsOneWidget);
    expect(t.widget<Scaffold>(find.byType(Scaffold)).backgroundColor,
        Colors.transparent);
    expect(find.byType(ClipRect), findsWidgets);
    expect(find.byType(OverflowBox), findsOneWidget);

    Widget dockAt(double width) => MaterialApp(
        theme: launcherTheme(SurfaceStyle.from(controller.appearance, true)),
        home: Scaffold(
            body: Align(
                alignment: Alignment.bottomCenter,
                child: SizedBox(
                    width: width,
                    height: Design.px(96),
                    child: BottomDock(controller: controller)))));
    await t.pumpWidget(dockAt(1600));
    await t.pumpAndSettle();
    final music = t.getRect(find.byKey(const ValueKey('dock-music-frame'))),
        climate = t.getRect(find.byKey(const ValueKey('dock-climate-frame'))),
        uni = t.getRect(find.byKey(const ValueKey('uni-menu')));
    expect(music.width, closeTo(722.051, .1));
    await t.pumpWidget(dockAt(1420));
    await t.pumpAndSettle();
    final narrowMusic =
            t.getRect(find.byKey(const ValueKey('dock-music-frame'))),
        narrowClimate =
            t.getRect(find.byKey(const ValueKey('dock-climate-frame'))),
        narrowUni = t.getRect(find.byKey(const ValueKey('uni-menu')));
    expect(narrowMusic.width, lessThan(music.width));
    expect(narrowUni.width, closeTo(uni.width, .1));
    expect(climate.width - narrowClimate.width, closeTo(69.231, .1));

    await t.pumpWidget(dockAt(1600));
    await t.pumpAndSettle();
    controller.setAppearance(
        controller.appearance.copyWith(dockMusicVisual: false),
        save: false);
    await t.pumpWidget(dockAt(1600));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('dock-music-visual-pages')), findsNothing);
    final compactMusic =
        t.getRect(find.byKey(const ValueKey('dock-music-frame')));
    final expandedClimate =
        t.getRect(find.byKey(const ValueKey('dock-climate-frame')));
    expect(compactMusic.width, lessThan(music.width));
    expect(expandedClimate.width, greaterThan(climate.width));
    expect(Appearance.fromJson(controller.appearance.toJson()).dockMusicVisual,
        isFalse);
    expect(t.takeException(), isNull);
  });

  test('new defaults use square blue glass; old preferences and styles survive',
      () {
    expect(const Appearance().themeStyle, 'blueGlass');
    expect(const Appearance().radius, 0);
    expect(Appearance.fromJson({}).themeStyle, 'classic');
    expect(
        Appearance.fromJson({'themeStyle': 'unknown'}).themeStyle, 'classic');
    const original = Appearance(
        themeStyle: 'classic',
        mode: 'smart',
        palette: 'custom',
        custom: '#4488AB',
        wallpaper: 'custom',
        wallpaperPath: '/data/wall.jpg',
        wallpaperLuminance: .2,
        desktopName: '我的领克',
        radius: 12,
        glass: true,
        pageTransition: 'slide');
    final themed = Appearance.fromJson(jsonDecode(
        jsonEncode(original.copyWith(themeStyle: 'blueGlass').toJson())));
    expect(themed.themeStyle, 'blueGlass');
    expect(themed.copyWith(themeStyle: 'classic').toJson(), original.toJson());
  });

  test('blue glass uses readable light/dark tokens and bounded control radii',
      () {
    for (final dark in [true, false]) {
      final style = SurfaceStyle.from(
          Appearance(
              themeStyle: 'blueGlass',
              mode: dark ? 'dark' : 'light',
              palette: 'blue',
              radius: 40,
              glass: true),
          false);
      final fg = style.text.computeLuminance(),
          bg = style.strong.computeLuminance();
      final contrast =
          (fg > bg ? (fg + .05) / (bg + .05) : (bg + .05) / (fg + .05));
      expect(contrast, greaterThan(7));
      expect(style.controlRadius, Design.px(16));
      expect(style.liveBlur, false);
      expect(style.background,
          dark ? const Color(0xFF07111F) : const Color(0xFFE8EEF5));
    }
  });

  test('frame corner paths meet the actual outline including at radius zero',
      () {
    for (final radius in [0.0, 12.0, 24.0, 40.0]) {
      final shape =
          TechnicalFrameBorder(radius: radius, cornerColor: Colors.blue);
      const rect = Rect.fromLTWH(10, 20, 300, 200);
      final paths = shape.cornerPaths(rect);
      expect(paths, hasLength(4));
      final first = paths.first.getBounds();
      expect(first.left, greaterThanOrEqualTo(rect.left));
      expect(first.top, greaterThanOrEqualTo(rect.top));
      if (radius == 0) {
        expect(first.right, rect.left + 12);
        expect(first.bottom, rect.top + 12);
      }
      for (final path in paths) {
        expect(path.computeMetrics().single.length,
            lessThanOrEqualTo(radius > 0 ? 12.1 : 24.1));
      }
      for (final path in paths) {
        final bounds = path.getBounds();
        expect(rect.contains(bounds.center), isTrue);
      }
      if (radius > 0) {
        expect(
            shape
                .getOuterPath(rect)
                .contains(rect.topLeft + const Offset(1, 1)),
            false);
      }
    }
  });

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

  testWidgets(
      'theme picker persists style, preserves layout and removes source tab',
      (t) async {
    final (c, g) = await launch(t);
    final layout = jsonEncode(c.cards.map((c) => c.toJson()).toList());
    c.openSettings();
    await t.pumpAndSettle();
    expect(find.text('功能接入'), findsNothing);
    expect(find.byKey(const ValueKey('tab-sources')), findsNothing);
    expect(
        t.getTopLeft(find.byKey(const ValueKey('theme-style-blueGlass'))).dx,
        lessThan(t
            .getTopLeft(find.byKey(const ValueKey('theme-style-classic')))
            .dx));
    await t.tap(find.byKey(const ValueKey('theme-style-blueGlass')));
    await t.pumpAndSettle();
    expect(c.appearance.themeStyle, 'blueGlass');
    expect(c.appearance.palette, 'mint');
    expect(jsonEncode(c.cards.map((c) => c.toJson()).toList()), layout);
    await c.persist();
    expect(jsonDecode(g.saved!)['preferences']['themeStyle'], 'blueGlass');
    g.state['savedDesign'] = g.saved;
    final restored = LauncherController(g);
    await restored.initialize();
    expect(restored.appearance.themeStyle, 'blueGlass');
    expect(jsonEncode(restored.cards.map((c) => c.toJson()).toList()), layout);
    restored.dispose();
    expect(t.takeException(), null);
  });

  testWidgets('dark light radius and static glass fit home, settings and modal',
      (t) async {
    final (c, _) = await launch(t);
    for (final mode in ['dark', 'light']) {
      for (final radius in [0.0, 12.0, 24.0, 40.0]) {
        c.setAppearance(c.appearance.copyWith(
            themeStyle: 'blueGlass',
            palette: 'blue',
            mode: mode,
            radius: radius,
            glass: true));
        c.home();
        await t.pumpAndSettle();
        final dock = t.getRect(find.byKey(const ValueKey('bottom-dock')));
        expect(dock.bottom, 1080);
        expect(dock.height, 96);
        await t.tap(find.byKey(const ValueKey('climate')));
        await t.pumpAndSettle();
        expect(find.byType(BackdropFilter), findsNothing);
        expect(t.takeException(), null);
        await t.tap(find.byTooltip('关闭空调'));
        await t.pumpAndSettle();
        c.openSettings();
        await t.pumpAndSettle();
        final option = find.byKey(ValueKey('mode-$mode'));
        final material = t.widget<Material>(
            find.descendant(of: option, matching: find.byType(Material)).first);
        expect(material.shape, isA<TechnicalFrameBorder>());
        final frame = material.shape! as TechnicalFrameBorder;
        expect(frame.radius, Design.px(radius * .5).clamp(0, Design.px(16)));
        expect(frame.cornerColor, SurfaceStyle.of(t.element(option)).accent);
        expect(find.byType(BackdropFilter), findsNothing);
        expect(t.takeException(), null);
      }
    }
  });

  testWidgets(
      'every settings selection shares weak outline and short arc geometry',
      (t) async {
    final (c, _) = await launch(t);
    c.setAppearance(c.appearance.copyWith(
        themeStyle: 'blueGlass', mode: 'dark', palette: 'blue', radius: 40));
    c.openSettings();
    await t.pumpAndSettle();
    void inspect(String key) {
      final option = find.byKey(ValueKey(key));
      final descendants =
          find.descendant(of: option, matching: find.byType(Material));
      final material = t.widget<Material>(descendants.evaluate().isNotEmpty
          ? descendants.first
          : find.ancestor(of: option, matching: find.byType(Material)).first);
      final frame = material.shape! as TechnicalFrameBorder;
      final s = SurfaceStyle.of(t.element(option));
      expect(frame.cornerColor, s.accent, reason: key);
      expect(frame.side.color, s.controlSide(true).color, reason: key);
      expect(frame.side.color, isNot(s.accent),
          reason:
              'continuous outline must stay weaker than corner marks: $key');
      for (final path
          in frame.cornerPaths(const Rect.fromLTWH(0, 0, 150, 80))) {
        expect(path.computeMetrics().single.length,
            lessThanOrEqualTo(frame.cornerLength + .1),
            reason: key);
      }
    }

    for (final key in ['theme-style-blueGlass', 'mode-dark', 'palette-blue'])
      inspect(key);
    final wallpaper = find.byKey(const ValueKey('wallpaper-gradient'));
    await t.ensureVisible(wallpaper);
    await t.pumpAndSettle();
    inspect('wallpaper-gradient');
    c.tab('motion');
    await t.pumpAndSettle();
    inspect('transition-slide');
    expect(t.takeException(), null);
  });

  testWidgets(
      'selected dock and neutral play share frame; press never moves dock',
      (t) async {
    final (c, _) = await launch(t);
    c.setAppearance(
        c.appearance.copyWith(themeStyle: 'blueGlass', palette: 'blue'));
    await t.pumpAndSettle();
    final home = find.byKey(const ValueKey('home'));
    final play = find.byKey(const ValueKey('play-pause'));
    Material material(Finder f) => t.widget<Material>(
        find.descendant(of: f, matching: find.byType(Material)).first);
    expect(material(home).shape, isNull);
    expect(material(play).shape, isNull);
    expect(material(play).color, Colors.transparent);
    final power = find.byKey(const ValueKey('climate-power'));
    expect(material(power).shape, isNull);
    expect(material(power).color, Colors.transparent);
    final climateGroup = t
        .widget<GlassSurface>(find.byKey(const ValueKey('dock-climate-frame')));
    expect(climateGroup.tone, SurfaceTone.soft);
    expect(climateGroup.shadow, false);

    final rect = t.getRect(play),
        dock = t.getRect(find.byKey(const ValueKey('bottom-dock')));
    final gesture = await t.startGesture(rect.center);
    await t.pump(const Duration(milliseconds: 120));
    expect(t.getRect(play), rect);
    expect(t.getRect(find.byKey(const ValueKey('bottom-dock'))), dock);
    await gesture.up();
    await t.pumpAndSettle();
    c.openSettings();
    await t.pumpAndSettle();
    expect(t.widget<IconAction>(home.last).active, false);
  });

  testWidgets('settings categories split dock, connections and system',
      (t) async {
    final (c, g) = await launch(t);
    c.openSettings();
    await t.pumpAndSettle();
    final tabIds = [
      'appearance',
      'dock',
      'connections',
      'motion',
      'ambient',
      'system',
      'about'
    ];
    var previousTab = t.getRect(find.byKey(const ValueKey('tab-appearance')));
    for (final id in tabIds.skip(1)) {
      final tab = t.getRect(find.byKey(ValueKey('tab-$id')));
      expect(tab.left, closeTo(previousTab.left, .1));
      expect(tab.top, greaterThan(previousTab.top));
      previousTab = tab;
    }
    expect(t.getRect(find.byKey(const ValueKey('tab-appearance'))).left,
        lessThan(Design.px(260)));
    expect(find.byKey(const ValueKey('dock-layout-floating')), findsNothing);

    await t.tap(find.byKey(const ValueKey('tab-dock')));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('dock-layout-floating')), findsOneWidget);
    expect(find.byKey(const ValueKey('dock-size-large')), findsOneWidget);
    expect(find.byKey(const ValueKey('global-dock')), findsOneWidget);
    expect(find.byKey(const ValueKey('media-source')), findsNothing);
    await t.ensureVisible(find.byKey(const ValueKey('global-dock')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('global-dock')));
    await t.pumpAndSettle();
    expect(g.commands, contains(containsPair('action', 'global-dock')));

    await t.tap(find.byKey(const ValueKey('tab-connections')));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('media-source')), findsOneWidget);
    expect(find.byKey(const ValueKey('navigation-source')), findsOneWidget);
    expect(find.byKey(const ValueKey('global-dock')), findsNothing);

    await t.tap(find.byKey(const ValueKey('tab-system')));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('system-setting-official-root')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('media-source')), findsNothing);
    expect(find.byKey(const ValueKey('global-dock')), findsNothing);
    await t.scrollUntilVisible(
        find.byKey(const ValueKey('refresh-system-settings')), 260,
        scrollable: find.byType(Scrollable).first);
    await t.pumpAndSettle();
    expect(find.text('原车系统设置&安卓设置'), findsOneWidget);

    await t.tap(find.byKey(const ValueKey('tab-motion')));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('transition-slide')), findsOneWidget);
    expect(find.byKey(const ValueKey('spectrum-style-bars')), findsOneWidget);
    await t.scrollUntilVisible(
        find.byKey(const ValueKey('dock-music-visual-switch')), 260,
        scrollable: find.byType(Scrollable).first);
    await t.pumpAndSettle();
    expect(
        find.byKey(const ValueKey('dock-music-visual-switch')), findsOneWidget);
    expect(t.takeException(), null);
  });
  testWidgets(
      'independent global dock and modal engines consume the same theme',
      (t) async {
    t.view.devicePixelRatio = 1;
    final g = FakeGateway();
    const appearance = Appearance(
        themeStyle: 'blueGlass',
        mode: 'smart',
        palette: 'blue',
        wallpaper: 'precision',
        radius: 24,
        glass: true);
    final dock = LauncherController(g);
    g.state['hostMode'] = 'global-dock';
    g.state['desktopSelected'] = true;
    await dock.initialize();
    dock.setAppearance(appearance);
    t.view.physicalSize = const Size(1920, 96);
    await t.pumpWidget(GlobalDockApp(controller: dock));
    await t.pumpAndSettle();
    final style =
        SurfaceStyle.of(t.element(find.byKey(const ValueKey('bottom-dock'))));
    expect(style.technicalFrame, true);
    expect(style.dark, isFalse);
    expect(t.getRect(find.byKey(const ValueKey('bottom-dock'))),
        const Rect.fromLTWH(0, 0, 1920, 96));
    expect(find.byType(BackdropFilter), findsNothing);
    await t.pumpWidget(const SizedBox.shrink());
    dock.dispose();
    g.state['hostMode'] = 'global-panel';
    g.state['globalDock'] = {'panel': 'media', 'panelRevision': 1};
    final panel = LauncherController(g);
    await panel.initialize();
    panel.setAppearance(appearance);
    t.view.physicalSize = const Size(1920, 984);
    await t.pumpWidget(GlobalPanelApp(controller: panel));
    await t.pumpAndSettle();
    expect(
        SurfaceStyle.of(t.element(find.byType(Scaffold).first)).dark, isFalse);
    expect(find.byTooltip('关闭音乐详情'), findsOneWidget);
    expect(find.byType(BackdropFilter), findsNothing);
    expect(t.takeException(), null);
    await t.pumpWidget(const SizedBox.shrink());
    await g.dispose();
    t.view.resetPhysicalSize();
    t.view.resetDevicePixelRatio();
  });
}
