import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:uni_launcher/controller/launcher_controller.dart';
import 'package:uni_launcher/launcher_app.dart';
import 'package:uni_launcher/model/card_layout.dart';
import '../test/fake_gateway.dart';

/// Renders production desktop widgets with explicitly synthetic signal data.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('desktop page indicator and 4x2 signals', (tester) async {
    final gateway = FakeGateway();
    final controller = LauncherController(gateway);
    await controller.initialize();
    controller.cards = defaultCards();
    expect(
        controller.cards
            .where((card) => card.page == 0)
            .map((card) => card.type),
        ['nav', 'music', 'trafficLight']);
    controller.pageCount = 2;
    expect(controller.appearance.themeStyle, 'blueGlass');
    expect(controller.appearance.radius, 0);
    controller.setAppearance(controller.appearance.copyWith(mode: 'dark'),
        save: false);
    await tester.pumpWidget(LauncherApp(controller: controller));
    await tester.pumpAndSettle();
    await binding.convertFlutterSurfaceToImage();
    for (final count in [1, 2, 3]) {
      controller.native.value = {
        ...controller.native.value,
        'demo': false,
        'trafficLights': {
          'available': true,
          'ageMs': 0,
          'ttlMs': 5000,
          'sequence': count,
          'enumVerified': true,
          'lights': [
            {'direction': 'left', 'lamp': 'red', 'countdownSeconds': 60},
            if (count > 1)
              {
                'direction': 'straight',
                'lamp': 'green',
                'countdownSeconds': 24
              },
            if (count > 2)
              {'direction': 'right', 'lamp': 'amber', 'countdownSeconds': 18},
          ]
        }
      };
      await tester.pump();
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 700)));
      await tester.pump(const Duration(milliseconds: 100));
      expect(
          find.byKey(const ValueKey('page-indicator-active')), findsOneWidget);
      expect(find.text('60'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await binding.takeScreenshot('traffic-lights-desktop-$count');
    }
    await controller.switchPage(1);
    await tester.pumpAndSettle();
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 900)));
    await tester.pump();
    expect(controller.page, 1);
    expect(find.byKey(const ValueKey('clock-weather-card-open')).hitTestable(),
        findsOneWidget);
    expect(
        find.byKey(const ValueKey('shortcuts-edit-shortcuts-1')).hitTestable(),
        findsOneWidget);
    await binding.takeScreenshot('traffic-lights-desktop-page2');
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
    await gateway.dispose();
  });
}
