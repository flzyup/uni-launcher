import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:uni_launcher/main.dart' as app;
import 'package:uni_launcher/launcher_app.dart';
import 'package:uni_launcher/model/appearance.dart';
import 'package:uni_launcher/widgets/glass_surface.dart';
import 'package:uni_launcher/widgets/seat_controls.dart';
import 'package:uni_launcher/screens/settings_screen.dart';
import 'package:uni_launcher/widgets/lyrics_view.dart';
import 'weather_gallery.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('Flutter launcher on Android 9 with persisted blur control',
      (tester) async {
    final checks = <String>[];
    void verify(String name, bool ok) {
      expect(ok, true, reason: name);
      checks.add(name);
    }

    Future<void> settle() async {
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 300));
    }

    await app.main();
    await settle();
    final c = tester.widget<LauncherApp>(find.byType(LauncherApp)).controller;
    c.resetLayout();
    c.setAppearance(const Appearance(mode: 'dark'));
    await c.command('demo-mode', enabled: true);
    await c.command('global-dock', enabled: false);
    await c.command('select-player', value: 'ecarx.xsf.mediacenter');
    await c.command('select-navigation', value: 'auto');
    await c.command('hide-navigation', enabled: false);
    await settle();
    await binding.convertFlutterSurfaceToImage();
    await settle();
    verify('Flutter home cards rendered',
        find.byKey(const ValueKey('nav-1')).evaluate().length == 1);
    verify('Blur defaults off with no BackdropFilter',
        find.byType(BackdropFilter).evaluate().isEmpty);
    final dock = tester.getRect(find.byKey(const ValueKey('bottom-dock')));
    final window = tester.view.physicalSize / tester.view.devicePixelRatio;
    verify('Desktop fills the usable emulator window',
        dock.right > window.width * .95 && dock.bottom > window.height * .9);
    verify('Android app list arrives through platform channel',
        (c.native.value['apps'] as List).isNotEmpty);
    final nav = c.native.value['navigation'] as Map;
    verify(
        'Native map permission fallback is explicit and no demo route is painted',
        nav['canEmbed'] == false && find.text('600 米后右转').evaluate().isEmpty);
    await binding.takeScreenshot('flutter-home-dark');
    c.setAppearance(c.appearance.copyWith(mode: 'light'));
    await settle();
    await binding.takeScreenshot('flutter-home-light');
    c.setAppearance(c.appearance.copyWith(mode: 'dark'));
    await settle();
    c.switchPage(1);
    await settle();
    await binding.takeScreenshot('flutter-secondary-dark');
    c.home();
    await settle();
    final keys = [
      'home',
      'all-apps',
      'recents',
      'camera',
      'climate',
      'play-pause',
      'music-info',
      'vehicle'
    ];
    final positions =
        keys.map((k) => tester.getCenter(find.byKey(ValueKey(k))).dx).toList();
    verify(
        'Bottom dock follows requested order',
        List.generate(
                positions.length - 1, (i) => positions[i] < positions[i + 1])
            .every((v) => v));
    await tester.longPress(find.byKey(const ValueKey('home')));
    await settle();
    verify('Holding Home enters desktop settings', c.settings);
    final paletteMaterial = tester.widget<Material>(find
        .descendant(
            of: find.byKey(const ValueKey('palette-mint')),
            matching: find.byType(Material))
        .first);
    verify(
        'Palette uses reviewed rectangular shape instead of Material stadium',
        paletteMaterial.shape is RoundedRectangleBorder &&
            ((paletteMaterial.shape! as RoundedRectangleBorder)
                            .borderRadius
                            .resolve(TextDirection.ltr)
                            .topLeft
                            .x -
                        14.9333)
                    .abs() <
                .03);
    verify('Settings previews the actual desktop renderer',
        find.byType(DesktopPreview).evaluate().length == 1);
    await binding.takeScreenshot('flutter-settings-dark');
    c.tab('motion');
    await settle();
    await tester.tap(find.byKey(const ValueKey('transition-slide')));
    await settle();
    await c.persist();
    final motion = await c.gateway.bootstrap();
    verify(
        'Page transition preference persists in native storage',
        jsonDecode(motion['savedDesign'])['preferences']['pageTransition'] ==
            'slide');
    await binding.takeScreenshot('flutter-settings-motion');
    c.home();
    await settle();
    final fixedDock = tester.getRect(find.byKey(const ValueKey('bottom-dock')));
    await tester.fling(
        find.byKey(const ValueKey('card-grid')), const Offset(-550, 0), 1000);
    await settle();
    verify(
        'Swipe changes page while dock remains fixed',
        c.page == 1 &&
            tester.getRect(find.byKey(const ValueKey('bottom-dock'))) ==
                fixedDock);
    c.setAppearance(c.appearance.copyWith(pageTransition: 'fade'));
    c.switchPage(0);
    await settle();
    verify('Fade transition arrives at first page',
        find.byKey(const ValueKey('nav-1')).evaluate().length == 1);
    c.setAppearance(c.appearance.copyWith(pageTransition: 'none'));
    c.openSettings();
    c.tab('appearance');
    await settle();
    final radiusField = find.byKey(const ValueKey('radius-number-28'));
    await tester.ensureVisible(radiusField);
    await settle();
    await tester.enterText(radiusField, '0');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await settle();
    verify(
        'Radius number input applies square corners', c.appearance.radius == 0);
    await binding.takeScreenshot('flutter-settings-square');
    c.setAppearance(c.appearance.copyWith(radius: 28));
    await settle();
    await tester.scrollUntilVisible(
        find.byKey(const ValueKey('glass-switch')), 180,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(find.byKey(const ValueKey('glass-switch')));
    await settle();
    verify(
        'Blur switch creates clipped Flutter filters',
        c.appearance.glass &&
            find.byType(BackdropFilter).evaluate().isNotEmpty);
    await c.persist();
    final saved = await c.gateway.bootstrap();
    verify('Blur setting committed to Android preferences',
        jsonDecode(saved['savedDesign'])['preferences']['glass'] == true);
    await binding.takeScreenshot('flutter-settings-blur-on');
    await tester.tap(find.byKey(const ValueKey('glass-switch')));
    await settle();
    verify('Disabling blur removes every filter',
        !c.appearance.glass && find.byType(BackdropFilter).evaluate().isEmpty);
    c.setAppearance(
        c.appearance.copyWith(mode: 'light', palette: 'blue', radius: 0));
    c.home();
    await settle();
    verify('Light theme and zero radius applied',
        c.appearance.mode == 'light' && c.appearance.radius == 0);
    await binding.takeScreenshot('flutter-home-light-square');
    await tester.longPress(find.byKey(const ValueKey('music-1')));
    await settle();
    verify('Card hold opens edit mode', c.editing);
    await tester.tap(find.byTooltip('编辑正在播放'));
    await settle();
    await binding.takeScreenshot('flutter-card-settings');
    await tester.tap(find.byTooltip('关闭卡片设置'));
    await settle();
    await binding.takeScreenshot('flutter-edit-mode');
    await tester.tap(find.byKey(const ValueKey('add-card')));
    await settle();
    await binding.takeScreenshot('flutter-card-library');
    await tester.tap(find.byKey(const ValueKey('add-air')));
    await settle();
    verify('Card library allocates page when full',
        c.page == 2 && c.pageCount == 3 && c.cards.length == 10);
    final air = c.cards.last,
        grid = tester.getSize(find.byKey(const ValueKey('grid-bounds')));
    await tester.drag(
        find.byKey(ValueKey('move-${air.id}')), Offset(grid.width / 12 * 2, 0));
    await settle();
    verify('Touch drag moves card on grid', c.cards.last.x == 2);
    await tester.drag(find.byKey(ValueKey('resize-${air.id}')),
        Offset(grid.width / 12, grid.height / 6));
    await settle();
    verify('Touch resize updates card spans',
        c.cards.last.w == 5 && c.cards.last.h == 4);
    await tester.tap(find.byKey(const ValueKey('finish-edit')));
    await settle();
    await c.persist();
    final layout = await c.gateway.bootstrap();
    verify('Edited card layout committed to Android preferences',
        (jsonDecode(layout['savedDesign'])['cards'] as List).length == 10);
    await binding.takeScreenshot('flutter-card-edited');
    c.home();
    await settle();
    await tester.tap(find.byKey(const ValueKey('all-apps')));
    await settle();
    verify('Real installed application drawer opens',
        find.text('全部应用').evaluate().isNotEmpty);
    await binding.takeScreenshot('flutter-apps');
    await tester.tap(find.byTooltip('关闭应用列表'));
    await settle();
    await tester.tap(find.byKey(const ValueKey('music-info')));
    await settle();
    verify(
        'Music card dock and detail share native demo lyrics',
        find.byType(LyricsView).evaluate().length >= 3 &&
            (c.native.value['media'] as Map)['lyricsSource'] == 'demo');
    await binding.takeScreenshot('flutter-music');
    await tester.tap(find.byTooltip('关闭音乐详情'));
    await settle();
    await tester.tap(find.byKey(const ValueKey('vehicle')));
    await settle();
    await binding.takeScreenshot('flutter-vehicle');
    await tester.tap(find.byTooltip('关闭车辆信息'));
    await settle();
    await tester.tap(find.byKey(const ValueKey('camera')));
    await settle();
    await binding.takeScreenshot('flutter-camera');
    verify('Dock camera opens the OEM 360 directly without a dialog',
        find.byTooltip('关闭影像面板').evaluate().isEmpty);
    await c.command('temp-up', zone: 'left');
    await settle();
    verify('Native climate simulator confirms command',
        (c.native.value['climate'] as Map)['left'] == 23.0);
    c.setAppearance(c.appearance
        .copyWith(mode: 'dark', palette: 'mint', radius: 28, glass: false));
    await settle();
    await tester.tap(find.byKey(const ValueKey('climate')));
    await settle();
    verify(
        'Seat panel exposes three requested controls',
        find.byType(SeatControls).evaluate().length == 1 &&
            find
                    .byKey(const ValueKey('seat-passengerHeat-1'))
                    .evaluate()
                    .length ==
                1 &&
            find.text('副驾通风').evaluate().isEmpty);
    await tester.tap(find.byKey(const ValueKey('seat-driverHeat-2')));
    await settle();
    verify('Driver heating selection confirmed by native simulator',
        (c.native.value['climate'] as Map)['driverHeat'] == 2);
    await tester.tap(find.byKey(const ValueKey('seat-passengerHeat-1')));
    await settle();
    verify('Passenger heating selection confirmed independently',
        (c.native.value['climate'] as Map)['passengerHeat'] == 1);
    await binding.takeScreenshot('flutter-climate');
    await tester.tap(find.byKey(const ValueKey('seat-driverVent-3')));
    await settle();
    verify(
        'Driver ventilation confirms and clears demo driver heating',
        (c.native.value['climate'] as Map)['driverVent'] == 3 &&
            (c.native.value['climate'] as Map)['driverHeat'] == 0);
    await binding.takeScreenshot('flutter-seats-vent');
    await tester.tap(find.byKey(const ValueKey('seat-driverVent-0')));
    await settle();
    verify(
        'Seat explicit off confirms without changing passenger heating',
        (c.native.value['climate'] as Map)['driverVent'] == 0 &&
            (c.native.value['climate'] as Map)['passengerHeat'] == 1);
    await tester.tap(find.byTooltip('关闭空调'));
    await settle();
    await c.command('demo-mode', enabled: false);
    await settle();
    verify('Live mode removes illustrative navigation',
        find.text('600 米后右转').evaluate().isEmpty);
    verify(
        'Unavailable live climate is disabled',
        tester
                .widgetList<IconAction>(find.byType(IconAction))
                .firstWhere((w) => w.label == '升高主驾温度')
                .onTap ==
            null);
    await binding.takeScreenshot('flutter-live-unavailable');
    await tester.tap(find.byKey(const ValueKey('climate')));
    await settle();
    verify(
        'Live unavailable seat controls are disabled and unknown',
        ['driverHeat', 'driverVent', 'passengerHeat'].every((key) =>
            tester
                    .widget<OutlinedButton>(find.byKey(ValueKey('seat-$key-1')))
                    .onPressed ==
                null &&
            find.byKey(ValueKey('seat-unknown-$key')).evaluate().length == 1));
    await binding.takeScreenshot('flutter-seats-unavailable');
    await tester.tap(find.byTooltip('关闭空调'));
    await settle();
    await c.command('refresh');
    await settle();
    verify(
        'Missing vehicle permission skips OEM SDK initialization',
        ((c.native.value['vehicle'] as Map)['reason'] as String)
                .contains('权限未授权') &&
            (c.native.value['vehicle'] as Map)['connected'] == false);
    final nativeMedia = c.native.value['media'] as Map;
    expect(nativeMedia['authorized'], true,
        reason:
            'Synthetic media listener grant must survive installation: $nativeMedia');
    expect(nativeMedia['available'], true,
        reason: 'Synthetic foreground session must stay alive: $nativeMedia');
    verify(
        'Synthetic MediaSession lyrics arrive through native adapter',
        nativeMedia['source'] == 'ecarx.xsf.mediacenter' &&
            (nativeMedia['lyrics'] as String)
                .contains('Fixture lyric second') &&
            nativeMedia['lyricsSource'] == 'media-session');
    verify(
        'Native playback position duration and clock are available',
        nativeMedia['positionKnown'] == true &&
            nativeMedia['durationMs'] == 180000 &&
            (nativeMedia['positionMs'] as num) >= 1000 &&
            (nativeMedia['sampledAtMs'] as num) > 0);
    verify('Selected source supplies real artwork through platform channel',
        (nativeMedia['artwork'] as String).isNotEmpty);
    await c.command('select-player', value: 'xyz.i4o.uni.fixture.player');
    await settle();
    verify(
        'Explicit alternate player reads only its own session',
        (c.native.value['media'] as Map)['source'] ==
            'xyz.i4o.uni.fixture.player');
    await c.command('toggle-play');
    await settle();
    verify('Transport pause reaches alternate player',
        (c.native.value['media'] as Map)['playing'] == false);
    await c.command('select-player', value: 'auto');
    await settle();
    verify('Automatic source chooses the remaining playing session',
        (c.native.value['media'] as Map)['source'] == 'ecarx.xsf.mediacenter');
    await c.command('toggle-play');
    await settle();
    verify(
        'Automatic source observes pause without a session list change',
        ((c.native.value['media'] as Map)['sessions'] as List)
            .every((raw) => (raw as Map)['playing'] == false));
    await c.command('toggle-play');
    await settle();
    await c.command('select-player', value: 'ecarx.xsf.mediacenter');
    await settle();
    verify('First player stays playing while alternate player was paused',
        (c.native.value['media'] as Map)['playing'] == true);
    final chosen = await c.gateway.bootstrap();
    verify(
        'Player preference is committed to native preferences',
        (chosen['integrationPreferences'] as Map)['mediaPackage'] ==
            'ecarx.xsf.mediacenter');
    await c.command('select-player', value: 'com.android.settings');
    await settle();
    verify(
        'App with no session stays unavailable without controlling another player',
        (c.native.value['media'] as Map)['available'] == false);
    await c.command('select-player', value: 'ecarx.xsf.mediacenter');
    await settle();
    await c.command('select-navigation', value: 'xyz.i4o.uni.fixture.player');
    await settle();
    final chosenNav = c.native.value['navigation'] as Map;
    verify(
        'Navigation choice persists and embedding stays disabled without system permission',
        chosenNav['preferredPackage'] == 'xyz.i4o.uni.fixture.player' &&
            chosenNav['installed'] == true &&
            chosenNav['canEmbed'] == false);
    await c.command('select-navigation', value: 'auto');
    await settle();
    await c.command('seek', value: '1000');
    await settle();
    verify('Native MediaSession exposes seek support',
        (c.native.value['media'] as Map)['canSeek'] == true);
    verify(
        'Native seek resets lyric highlight to first line',
        find
            .byKey(const ValueKey('lyric-line-0-active'))
            .evaluate()
            .isNotEmpty);
    await Future<void>.delayed(const Duration(seconds: 3));
    await settle();
    final advancing = c.native.value['media'] as Map;
    verify('Native playback clock advances after playing',
        (advancing['positionMs'] as num) >= 3000);
    final advancingLyric = find.byWidgetPredicate((w) =>
        w.key is ValueKey<String> &&
        RegExp(r'^lyric-line-[12]-active$')
            .hasMatch((w.key as ValueKey<String>).value));
    for (int i = 0; i < 30 && advancingLyric.evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    if (advancingLyric.evaluate().isEmpty)
      debugPrint(
          'Lyric clock=${(c.native.value['media'] as Map)['positionMs']} keys=${find.byWidgetPredicate((w) => w.key.toString().contains('lyric-line-')).evaluate().map((e) => e.widget.key).toList()}');
    verify('Playing native timeline scrolls beyond first lyric line',
        advancingLyric.evaluate().isNotEmpty);
    await c.command('toggle-play');
    await settle();
    verify('Media pause is confirmed by native source callback',
        (c.native.value['media'] as Map)['playing'] == false);
    await tester.tap(find.byKey(const ValueKey('music-info')));
    await settle();
    await binding.takeScreenshot('flutter-lyrics-session');
    await tester.tap(find.byTooltip('关闭音乐详情'));
    await settle();
    await c.command('toggle-play');
    await settle();
    c.openSettings();
    c.tab('system');
    await settle();
    await binding.takeScreenshot('flutter-integration-settings');
    await tester.scrollUntilVisible(
        find.byKey(const ValueKey('system-navigation-hidden')), 300,
        scrollable: find.byType(Scrollable).first);
    await settle();
    await tester.tap(find.byKey(const ValueKey('system-navigation-hidden')));
    await settle();
    verify('Native navigation setting applied',
        c.native.value['systemNavigationHidden'] == true);
    await tester.tap(find.byKey(const ValueKey('system-navigation-hidden')));
    await settle();
    verify('Native navigation setting restored',
        c.native.value['systemNavigationHidden'] == false);
    c.setAppearance(c.appearance
        .copyWith(mode: 'dark', palette: 'mint', radius: 28, glass: false));
    await c.persist();
    c.home();
    await settle();
    for (final night in [false, true]) {
      // Use MaterialApp's navigator context, not the parent LauncherApp element.
      final navigator =
          tester.state<NavigatorState>(find.byType(Navigator).first);
      navigator.push(MaterialPageRoute<void>(
          builder: (_) => WeatherGallery(night: night)));
      await settle();
      await binding
          .takeScreenshot(night ? 'weather-icons-night' : 'weather-icons-day');
      navigator.pop();
      await settle();
    }
    verify(
        'Weather day and night atlases render all icon conditions without exceptions',
        tester.takeException() == null);
    verify('No Flutter rendering exception', tester.takeException() == null);
    binding.reportData = {
      ...?binding.reportData,
      'renderer': 'Flutter Android',
      'api': 28,
      'mediaFixture': 'Synthetic MediaSession, not the OEM media center',
      'checks': checks,
      'passed': checks.length,
      'glassDefault': false,
      'carVerification': 'pending',
      'performance': 'Functional emulator checks; no real-car performance claim'
    };
  });
}
