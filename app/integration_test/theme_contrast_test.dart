import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:uni_launcher/controller/launcher_controller.dart';
import '../test/fake_gateway.dart';
import 'package:uni_launcher/launcher_app.dart';
import 'package:uni_launcher/model/appearance.dart';
import 'package:uni_launcher/widgets/climate_panel.dart';
import 'package:uni_launcher/widgets/bottom_dock.dart';
import 'package:uni_launcher/widgets/card_content.dart';

/// Production rendering on an emulator. Theme changes are not persisted.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('theme text and controls on Android 9', (t) async {
    final gateway = FakeGateway();
    gateway.state['apps'] = [
      {'id': 'test.player', 'package': 'test.player', 'label': '音乐'},
      {'id': 'test.map', 'package': 'test.map', 'label': '地图'},
    ];
    final c = LauncherController(gateway);
    await c.initialize();
    c.openSettings();
    await t.pumpWidget(LauncherApp(controller: c));
    await t.pumpAndSettle();
    await binding.convertFlutterSurfaceToImage();
    await t.pumpAndSettle();
    var screenshots = 0;
    final files = <String>[];
    final output = Directory('${Directory.systemTemp.path}/theme-contrast')
      ..createSync(recursive: true);
    Future<void> shot(String name) async {
      expect(t.takeException(), isNull, reason: name);
      final filename = 'theme-$name.png';
      final bytes = await binding.takeScreenshot('theme-$name');
      await File('${output.path}/$filename').writeAsBytes(bytes);
      files.add(filename);
      // Keep the VM service response bounded: screenshots are pulled as files.
      binding.reportData?.remove('screenshots');
      screenshots++;
    }

    const quick = bool.fromEnvironment('UNI_THEME_VERIFY_QUICK');
    for (final skin in Appearance.themeStyles) {
      for (final mode in ['dark', 'light']) {
        for (final palette in (quick
            ? ['blue', 'amber']
            : ['mint', 'blue', 'violet', 'amber', 'rose', 'custom'])) {
          c.setAppearance(
              Appearance(
                  themeStyle: skin,
                  mode: mode,
                  palette: palette,
                  custom: '#FFFF00',
                  radius: 28,
                  glass: true,
                  wallpaper: mode == 'dark' ? 'coastal' : 'graphite'),
              save: false);
          c.openSettings();
          c.tab('appearance');
          await t.pumpAndSettle();
          expect(c.appearance.themeStyle, skin);
          expect(c.appearance.palette, palette);
          expect(c.appearance.mode, mode);
          await shot('$skin-$mode-$palette-appearance');
        }
        for (final tab in (quick
            ? <String>[]
            : [
                'dock',
                'connections',
                'motion',
                'ambient',
                'cluster',
                'memory',
                'cleaner',
                'system',
                'about'
              ])) {
          c.tab(tab);
          await t.pumpAndSettle();
          await shot('$skin-$mode-$tab');
        }
        c.home();
        await t.pumpAndSettle();
        showClimatePanel(t.element(find.byType(Scaffold).first), c);
        await t.pumpAndSettle();
        await shot('$skin-$mode-climate');
        await t.tap(find.byTooltip('关闭空调'));
        await t.pumpAndSettle();
        final menu = showUniDockMenu(t.element(find.byType(Scaffold).first), c);
        await t.pumpAndSettle();
        await shot('$skin-$mode-menu');
        await t.tapAt(const Offset(8, 180));
        await t.pumpAndSettle();
        await menu;
        final apps = showAppsPanel(t.element(find.byType(Scaffold).first), c);
        await t.pumpAndSettle();
        await shot('$skin-$mode-apps');
        Navigator.of(t.element(find.byType(AppPanel))).pop();
        await t.pumpAndSettle();
        await apps;
      }
    }
    binding.reportData = {
      ...?binding.reportData,
      'screenshotsChecked': screenshots,
      'screenshotDirectory': output.path,
      'files': files,
      'scope':
          'Android 9 emulator; production widgets with synthetic telemetry; no car test'
    };
    await t.pumpWidget(const SizedBox());
    c.dispose();
    await gateway.dispose();
  });
}
