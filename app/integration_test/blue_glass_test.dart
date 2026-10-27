import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:uni_launcher/main.dart' as app;
import 'package:uni_launcher/launcher_app.dart';
import 'package:uni_launcher/model/appearance.dart';
import 'package:uni_launcher/theme/launcher_theme.dart';
import 'package:uni_launcher/widgets/glass_surface.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('blue glass theme across Android 9 surfaces and persistence',
      (t) async {
    final checks = <String>[];
    void verify(String name, bool valid) {
      expect(valid, true, reason: name);
      checks.add(name);
    }

    Future<void> settle() async {
      await t.pumpAndSettle();
      await t.pump(const Duration(milliseconds: 200));
    }

    await app.main();
    await settle();
    final c = t.widget<LauncherApp>(find.byType(LauncherApp)).controller;
    verify(
        'target is Android emulator',
        c.native.value['device'] == null ||
            !'${c.native.value['device']}'.contains('IP753'));
    await c.command('global-dock', enabled: false);
    await c.command('demo-mode', enabled: true);
    await c.command('hide-navigation', enabled: true);
    c.resetLayout();
    c.setAppearance(const Appearance(
        themeStyle: 'blueGlass',
        mode: 'dark',
        palette: 'blue',
        radius: 24,
        glass: true));
    await settle();
    await binding.convertFlutterSurfaceToImage();
    await settle();
    final dockFinder = find.byKey(const ValueKey('bottom-dock'));
    final dock = t.getRect(dockFinder);
    final window = t.view.physicalSize / t.view.devicePixelRatio;
    final usableHeight =
        ((c.native.value['viewportHeightPx'] as num?)?.toDouble() ??
                t.getSize(find.byType(Scaffold).first).height *
                    t.view.devicePixelRatio) /
            t.view.devicePixelRatio;
    verify(
        'full width dock sits at usable bottom',
        (dock.bottom - usableHeight.clamp(0, window.height)).abs() < 1 &&
            dock.width > window.width * .99);
    verify('blue glass never inserts live backdrop filters',
        find.byType(BackdropFilter).evaluate().isEmpty);
    verify(
        'climate power uses icon state without nested frame',
        !t
            .widget<IconAction>(find.byKey(const ValueKey('climate-power')))
            .framed);
    await binding.takeScreenshot('blue-glass-home-dark-r24');
    c.switchPage(1);
    await settle();
    verify('page switch retains dock geometry',
        t.getRect(dockFinder) == dock && c.page == 1);
    await binding.takeScreenshot('blue-glass-vehicle-dark-r24');
    c.home();
    c.setAppearance(c.appearance.copyWith(mode: 'light'));
    await settle();
    await binding.takeScreenshot('blue-glass-home-light-r24');
    for (final radius in [0.0, 12.0, 40.0]) {
      c.setAppearance(c.appearance.copyWith(mode: 'dark', radius: radius));
      await settle();
      verify('radius $radius keeps dock fixed without layout error',
          t.getRect(dockFinder) == dock && t.takeException() == null);
      if (radius != 12)
        await binding.takeScreenshot('blue-glass-home-dark-r${radius.round()}');
    }
    c.setAppearance(c.appearance.copyWith(radius: 24));
    await settle();
    await t.tap(find.byKey(const ValueKey('climate')));
    await settle();
    verify('climate modal uses static surface with glass enabled',
        find.byType(BackdropFilter).evaluate().isEmpty);
    await binding.takeScreenshot('blue-glass-climate-dark');
    await t.tap(find.byTooltip('关闭空调'));
    await settle();
    await t.tap(find.byKey(const ValueKey('music-info')));
    await settle();
    await binding.takeScreenshot('blue-glass-music-dark');
    await t.tap(find.byTooltip('关闭音乐详情'));
    await settle();
    c.openSettings();
    await settle();
    verify(
        'removed source category is absent',
        find.text('功能接入').evaluate().isEmpty &&
            find.byKey(const ValueKey('tab-sources')).evaluate().isEmpty);
    verify('home icon is unselected in settings',
        !t.widget<IconAction>(find.byKey(const ValueKey('home')).last).active);
    verify(
        'blue glass is the first theme option',
        t.getTopLeft(find.byKey(const ValueKey('theme-style-blueGlass'))).dx <
            t.getTopLeft(find.byKey(const ValueKey('theme-style-classic'))).dx);
    await binding.takeScreenshot('blue-glass-settings-dark');
    await t.tap(find.byKey(const ValueKey('theme-style-classic')));
    await settle();
    verify('classic remains selectable', c.appearance.themeStyle == 'classic');
    await t.tap(find.byKey(const ValueKey('theme-style-blueGlass')));
    await settle();
    verify(
        'new theme selectable without clearing radius or palette',
        c.appearance.themeStyle == 'blueGlass' &&
            c.appearance.radius == 24 &&
            c.appearance.palette == 'blue');
    for (final effect in ['slide', 'fade', 'zoom', 'depth', 'none']) {
      c.setAppearance(c.appearance.copyWith(pageTransition: effect));
      await c.persist();
      final stored = jsonDecode((await c.gateway.bootstrap())['savedDesign']);
      verify('native storage accepts theme with $effect effect',
          stored['preferences']['pageTransition'] == effect);
    }
    c.setAppearance(c.appearance.copyWith(pageTransition: 'slide'));
    await c.persist();
    final state = await c.gateway.bootstrap();
    final saved = jsonDecode(state['savedDesign']);
    verify('Android storage retains independent theme identifier',
        saved['preferences']['themeStyle'] == 'blueGlass');
    await t.tap(find.byKey(const ValueKey('tab-system')));
    await settle();
    verify(
        'apps and dock is the first settings group',
        t.getTopLeft(find.byKey(const ValueKey('system-app-controls'))).dy <
            t.getTopLeft(find.text('导航与音乐')).dy);
    await binding.takeScreenshot('blue-glass-system-settings-top');
    await t.scrollUntilVisible(find.byKey(const ValueKey('media-source')), 320,
        scrollable: find.byType(Scrollable).first);
    await settle();
    verify(
        'player and navigation pickers moved to system settings',
        find.byKey(const ValueKey('media-source')).evaluate().isNotEmpty &&
            find
                .byKey(const ValueKey('navigation-source'))
                .evaluate()
                .isNotEmpty);
    await t.scrollUntilVisible(find.byKey(const ValueKey('global-dock')), 300,
        scrollable: find.byType(Scrollable).first);
    await settle();
    await t.ensureVisible(find.byKey(const ValueKey('global-dock')));
    await settle();
    verify(
        'system navigation control still available',
        find
            .byKey(const ValueKey('system-navigation-hidden'))
            .evaluate()
            .isNotEmpty);
    await binding.takeScreenshot('blue-glass-system-settings');
    verify(
        'no widget exceptions or live blur after all interactions',
        t.takeException() == null &&
            find.byType(BackdropFilter).evaluate().isEmpty);
    c.home();
    await settle();
    final style =
        SurfaceStyle.of(t.element(find.byKey(const ValueKey('bottom-dock'))));
    verify('production widgets use blue palette tokens',
        style.technicalFrame && style.accent == const Color(0xFF83B6FF));
    binding.reportData = {
      ...?binding.reportData,
      'version': '0.6.12',
      'dockBounds': {
        'left': dock.left,
        'top': dock.top,
        'right': dock.right,
        'bottom': dock.bottom
      },
      'usableHeight': usableHeight,
      'scope':
          'Android 9 emulator; actual Flutter widgets and native preference bridge; demo vehicle data, not 820A performance or real navigation/vehicle validation',
      'checks': checks
    };
  });
}
