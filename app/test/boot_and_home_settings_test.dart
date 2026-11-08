import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uni_launcher/controller/launcher_controller.dart';
import 'package:uni_launcher/launcher_app.dart';
import 'package:uni_launcher/screens/settings_screen.dart';
import 'fake_gateway.dart';

void main() {
  testWidgets('BootAndHomeSettings displays toggles and dispatches commands',
      (tester) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1;
    final gateway = FakeGateway();
    gateway.state['integrationPreferences'] = {
      'bootAutostart': true,
      'homeKeyTarget': 'uni',
    };
    final controller = LauncherController(gateway);
    await controller.initialize();
    await tester.pumpWidget(LauncherApp(controller: controller));
    await tester.pumpAndSettle();
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
      await gateway.dispose();
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    expect(controller.bootAutostart, isTrue);
    expect(controller.homeKeyTarget, equals('uni'));

    // Navigate to settings -> dock tab
    controller.openSettings();
    controller.tab('dock');
    await tester.pumpAndSettle();

    // Verify BootAndHomeSettings widgets exist by scrolling them into view
    final dockScrollable = find.descendant(
        of: find.byType(DockSettings), matching: find.byType(Scrollable));
    final bootSwitchFinder = find.byKey(const ValueKey('boot-autostart-switch'));
    await tester.scrollUntilVisible(bootSwitchFinder, 300,
        scrollable: dockScrollable);
    expect(bootSwitchFinder, findsOneWidget);

    final uniTargetFinder = find.byKey(const ValueKey('home-target-uni'));
    final oemTargetFinder = find.byKey(const ValueKey('home-target-oem'));
    expect(uniTargetFinder, findsOneWidget);
    expect(oemTargetFinder, findsOneWidget);

    final openSettingsFinder =
        find.byKey(const ValueKey('open-home-settings-button'));
    await tester.scrollUntilVisible(openSettingsFinder, 300,
        scrollable: dockScrollable);
    expect(openSettingsFinder, findsOneWidget);

    // Tap boot autostart switch to turn it off
    await tester.tap(bootSwitchFinder);
    await tester.pumpAndSettle();
    expect(
        gateway.commands
            .any((c) => c['action'] == 'boot-autostart' && c['enabled'] == false),
        isTrue);

    // Tap OEM target
    await tester.tap(oemTargetFinder);
    await tester.pumpAndSettle();
    expect(
        gateway.commands
            .any((c) => c['action'] == 'home-key-target' && c['value'] == 'oem'),
        isTrue);

    // Tap Open home settings button
    await tester.tap(openSettingsFinder);
    await tester.pumpAndSettle();
    expect(
        gateway.commands.any((c) => c['action'] == 'open-home-settings'),
        isTrue);
  });
}
