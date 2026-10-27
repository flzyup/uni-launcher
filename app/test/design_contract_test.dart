import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uni_launcher/controller/launcher_controller.dart';
import 'package:uni_launcher/launcher_app.dart';
import 'package:uni_launcher/model/seat_control.dart';
import 'package:uni_launcher/platform/native_gateway.dart';
import 'package:uni_launcher/screens/settings_screen.dart';
import 'package:uni_launcher/theme/launcher_theme.dart';
import 'package:uni_launcher/widgets/launcher_dialog.dart';
import 'package:uni_launcher/widgets/climate_panel.dart';
import 'package:uni_launcher/widgets/seat_controls.dart';
import 'package:uni_launcher/widgets/scene_background.dart';
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

  testWidgets(
      'reviewed palette uses rectangular corners, modes and palette have separate heights',
      (t) async {
    final (c, _) = await launch(t);
    c.setAppearance(c.appearance.copyWith(themeStyle: 'classic', radius: 28),
        save: false);
    c.openSettings();
    await t.pumpAndSettle();
    final palette = find.byKey(const ValueKey('palette-mint'));
    final material = t.widget<Material>(
        find.descendant(of: palette, matching: find.byType(Material)).first);
    expect(material.shape, isA<RoundedRectangleBorder>());
    final shape = material.shape! as RoundedRectangleBorder;
    expect(shape.borderRadius.resolve(TextDirection.ltr).topLeft.x,
        closeTo(14.9333, .02));
    expect(t.getRect(palette).height, closeTo(138, .1));
    expect(t.getRect(find.byKey(const ValueKey('mode-system'))).height,
        closeTo(66, .1));
    expect(find.byType(DesktopPreview), findsOneWidget);
    final indicator =
        t.getRect(find.byKey(const ValueKey('tab-indicator-appearance')));
    expect(indicator.left, closeTo(62, .1));
    expect(indicator.width, closeTo(96, .1));
    await t.ensureVisible(find.byKey(const ValueKey('radius-number-28')));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('radius-number-28')).hitTestable(),
        findsOneWidget);
    expect(t.takeException(), null);
  });
  testWidgets(
      'zero radius reaches palette and input controls while color chips stay circular',
      (t) async {
    final (c, _) = await launch(t);
    c.setAppearance(c.appearance.copyWith(themeStyle: 'classic'), save: false);
    c.openSettings();
    c.setAppearance(c.appearance.copyWith(radius: 0));
    await t.pumpAndSettle();
    for (final name in ['palette-mint', 'mode-system']) {
      final m = t.widget<Material>(find
          .descendant(
              of: find.byKey(ValueKey(name)), matching: find.byType(Material))
          .first);
      expect(
          (m.shape! as RoundedRectangleBorder)
              .borderRadius
              .resolve(TextDirection.ltr),
          BorderRadius.zero);
    }
    final field = t.widget<TextField>(find.byKey(const ValueKey('hex-field')));
    final border = field.decoration?.border ??
        Theme.of(t.element(find.byType(DesktopPreview)))
            .inputDecorationTheme
            .border;
    expect((border! as OutlineInputBorder).borderRadius, BorderRadius.zero);
    expect(t.takeException(), null);
  });
  testWidgets('wallpaper presets update the persisted appearance', (t) async {
    final (c, g) = await launch(t);
    c.openSettings();
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('wallpaper-overlay')), findsNothing);
    final dawn = find.byKey(const ValueKey('wallpaper-dawn'));
    await t.ensureVisible(dawn);
    await t.pumpAndSettle();
    await t.tap(dawn);
    await t.pumpAndSettle();
    expect(c.appearance.wallpaper, 'dawn');
    expect(c.appearance.mode, 'smart');
    expect(find.text('叠加主题渐变'), findsNothing);
    expect(jsonDecode(g.saved!)['preferences']['wallpaper'], 'dawn');
    expect(jsonDecode(g.saved!)['preferences'],
        isNot(contains('wallpaperOverlay')));
    expect(find.byKey(const ValueKey('wallpaper-neon')), findsOneWidget);
    expect(find.byKey(const ValueKey('wallpaper-precision')), findsOneWidget);
    expect(find.byKey(const ValueKey('wallpaper-terrain')), findsOneWidget);
    final preview =
        t.getSize(find.byKey(const ValueKey('wallpaper-preview-dawn')));
    expect(preview.width / preview.height, closeTo(16 / 9, .01));
    expect(find.byType(WallpaperImage), findsWidgets);
    expect(t.takeException(), null);
  });
  testWidgets('desktop text contrast follows built-in and custom wallpapers',
      (t) async {
    final (c, g) = await launch(t);
    c.setAppearance(c.appearance.copyWith(mode: 'smart', wallpaper: 'neon'));
    await t.pumpAndSettle();
    expect(
        SurfaceStyle.of(t.element(find.byKey(const ValueKey('desktop-name'))))
            .dark,
        true);
    c.setAppearance(
        c.appearance.copyWith(mode: 'smart', wallpaper: 'precision'));
    await t.pumpAndSettle();
    expect(
        SurfaceStyle.of(t.element(find.byKey(const ValueKey('desktop-name'))))
            .dark,
        false);
    c.setAppearance(c.appearance.copyWith(mode: 'dark'));
    await t.pumpAndSettle();
    expect(
        SurfaceStyle.of(t.element(find.byKey(const ValueKey('desktop-name'))))
            .dark,
        true);
    c.openSettings();
    g.wallpaper = const PickedWallpaper('/tmp/dark-wallpaper.jpg', .16);
    await t.pumpAndSettle();
    final custom = find.byKey(const ValueKey('wallpaper-custom'));
    await t.ensureVisible(custom);
    await t.tap(custom);
    await t.pumpAndSettle();
    expect(c.appearance.wallpaper, 'custom');
    expect(c.appearance.mode, 'smart');
    expect(c.appearance.wallpaperLuminance, .16);
    c.home();
    await t.pumpAndSettle();
    expect(
        SurfaceStyle.of(t.element(find.byKey(const ValueKey('desktop-name'))))
            .dark,
        true);
    expect(t.takeException(), null);
  });
  testWidgets(
      'standard theme color picker exposes swatches and full color field',
      (t) async {
    final (c, _) = await launch(t);
    c.openSettings();
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('custom-color')));
    await t.pumpAndSettle();
    expect(
        find.byKey(const ValueKey('saturation-value-field')), findsOneWidget);
    expect(find.byKey(const ValueKey('hue-field')), findsOneWidget);
    expect(find.byKey(const ValueKey('color-picker-hex')), findsOneWidget);
    expect(
        find.byKey(const ValueKey('standard-color-#F44336')), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('standard-color-#F44336')));
    await t.pump();
    await t.tap(find.text('应用颜色'));
    await t.pumpAndSettle();
    expect(c.appearance.palette, 'custom');
    expect(c.appearance.custom, '#F44336');
    expect(t.takeException(), null);
  });
  test('general HVAC permission never grants seat read or write access', () {
    final n = <String, dynamic>{
      'demo': false,
      'vehicle': {'writable': true},
      'climate': {'driverHeat': 3}
    };
    final state = SeatControlState.fromNative(n, 'driverHeat');
    expect(state.writable, false);
    expect(state.level, null);
    n['vehicle'] = {
      'writable': true,
      'seatCapabilities': {
        'driverHeat': {'supported': true, 'readable': true, 'writable': false}
      }
    };
    final read = SeatControlState.fromNative(n, 'driverHeat');
    expect(read.writable, false);
    expect(read.level, 3);
    expect(SeatControlState.fromNative(n, 'passengerHeat').writable, false);
  });
  testWidgets(
      'three seat selectors route explicit levels with correct zones and match sheet width',
      (t) async {
    final (c, g) = await launch(t);
    showClimatePanel(t.element(find.byKey(const ValueKey('climate'))), c);
    await t.pumpAndSettle();
    expect(find.byType(LauncherSheet), findsOneWidget);
    expect(find.byType(SeatControls), findsOneWidget);
    for (final item in [
      ('driverHeat', 'seat-heat', 'left', 2),
      ('driverVent', 'seat-vent', 'left', 3),
      ('passengerHeat', 'seat-heat', 'right', 1)
    ]) {
      await t.ensureVisible(find.byKey(ValueKey('seat-${item.$1}-${item.$4}')));
      await t.tap(find.byKey(ValueKey('seat-${item.$1}-${item.$4}')));
      await t.pumpAndSettle();
      expect(g.commands.last, containsPair('action', item.$2));
      expect(g.commands.last, containsPair('zone', item.$3));
      expect(g.commands.last, containsPair('value', '${item.$4}'));
    }
    expect(find.text('副驾通风'), findsNothing);
    final sheet = t.widget<LauncherSheet>(find.byType(LauncherSheet));
    expect(sheet.width, closeTo(933.333, .01));
    expect(t.takeException(), null);
  });
  testWidgets(
      'live unavailable seats show unknown and cannot send commands despite HVAC writable',
      (t) async {
    final (c, g) = await launch(t);
    g.state['demo'] = false;
    g.state['vehicle'] = {'writable': true};
    g.stream.add(Map.of(g.state));
    await t.pumpAndSettle();
    showClimatePanel(t.element(find.byKey(const ValueKey('climate'))), c);
    await t.pumpAndSettle();
    for (final key in ['driverHeat', 'driverVent', 'passengerHeat']) {
      expect(find.byKey(ValueKey('seat-unknown-$key')), findsOneWidget);
      for (int level = 0; level <= 3; level++)
        expect(
            t
                .widget<OutlinedButton>(
                    find.byKey(ValueKey('seat-$key-$level')))
                .onPressed,
            null);
    }
    expect(t.takeException(), null);
  });
}
