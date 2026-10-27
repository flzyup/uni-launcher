import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:uni_launcher/main.dart' as app;
import 'package:uni_launcher/launcher_app.dart';
import 'package:uni_launcher/widgets/glass_surface.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('Global dock controls and full-width home dock', (t) async {
    await app.main();
    await t.pumpAndSettle();
    final c = t.widget<LauncherApp>(find.byType(LauncherApp)).controller;
    await c.command('demo-mode', enabled: true);
    c.home();
    await t.pumpAndSettle();
    // Inline dock is the only bar until the global overlay is enabled.
    final inline = t.getRect(find.byKey(const ValueKey('bottom-dock')));
    final size = t.view.physicalSize / t.view.devicePixelRatio;
    expect(inline.left, 0);
    expect(inline.right, size.width);
    expect(inline.bottom,
        (c.native.value['viewportHeightPx'] as num) / t.view.devicePixelRatio);
    final surface = t.widget<GlassSurface>(find
        .descendant(
            of: find.byKey(const ValueKey('bottom-dock')),
            matching: find.byType(GlassSurface))
        .first);
    expect(surface.radius, 0);
    expect(surface.shadow, false);
    c.openSettings();
    c.tab('system');
    await t.pumpAndSettle();
    await binding.convertFlutterSurfaceToImage();
    await t.scrollUntilVisible(find.byKey(const ValueKey('global-dock')), 250,
        scrollable: find.byType(Scrollable).first);
    await t.pumpAndSettle();
    expect((c.native.value['globalDock'] as Map)['allowed'], true);
    expect(c.native.value['systemNavigationGranted'], true);
    await t.tap(find.byKey(const ValueKey('system-navigation-hidden')));
    await t.pumpAndSettle();
    expect(c.native.value['systemNavigationHidden'], true);
    await t.tap(find.byKey(const ValueKey('system-navigation-hidden')));
    await t.pumpAndSettle();
    expect(c.native.value['systemNavigationHidden'], false);
    final enabled = (c.native.value['globalDock'] as Map)['enabled'] == true;
    if (!enabled) await t.tap(find.byKey(const ValueKey('global-dock')));
    for (int i = 0;
        i < 30 && (c.native.value['globalDock'] as Map)['running'] != true;
        i++) {
      await t.pump(const Duration(milliseconds: 100));
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    final dock = c.native.value['globalDock'] as Map;
    expect(dock['running'], true);
    expect(dock['visible'], true,
        reason: 'The overlay is the single bar, home included');
    expect(dock['y'], 1080 - 96, reason: 'physical bottom strip');
    expect(find.byKey(const ValueKey('bottom-dock')), findsNothing,
        reason: 'inline dock must not duplicate the global overlay');
    await binding.takeScreenshot('global-dock-settings');
    c.home();
    await t.pumpAndSettle();
    await binding.takeScreenshot('global-dock-home');
    expect(t.takeException(), null);
    // Restore the pre-test state: global dock off returns the system bar.
    c.openSettings();
    c.tab('system');
    await t.pumpAndSettle();
    await t.scrollUntilVisible(find.byKey(const ValueKey('global-dock')), 250,
        scrollable: find.byType(Scrollable).first);
    await t.pumpAndSettle();
    if ((c.native.value['globalDock'] as Map)['enabled'] == true) {
      await t.tap(find.byKey(const ValueKey('global-dock')));
      await t.pumpAndSettle();
    }
    for (int i = 0;
        i < 30 && (c.native.value['globalDock'] as Map)['running'] == true;
        i++) {
      await t.pump(const Duration(milliseconds: 100));
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    expect((c.native.value['globalDock'] as Map)['running'], false);
    c.home();
    await t.pumpAndSettle();
    final screenshots = binding.reportData?['screenshots'];
    binding.reportData = {
      'screenshots': screenshots,
      'passed': 10,
      'checks': [
        'full-width',
        'zero bottom gap',
        'square outer surface',
        'no outer shadow',
        'system hide',
        'system restore',
        'overlay grant',
        'service starts',
        'no duplicate on home',
        'no Flutter exception'
      ],
      'externalAppVerification': 'next: emulator adb UI script'
    };
  });
}
