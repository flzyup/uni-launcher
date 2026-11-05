import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:uni_launcher/model/appearance.dart';
import 'vehicle_card_gallery.dart';

/// Standalone review only: no launcher, gateway, stored layout or car commands.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('vehicle cards export light dark minimum and disconnected boards',
      (tester) async {
    bool converted = false;
    final shots = <String>[];
    final cases = [
      for (final mode in ['dark', 'light'])
        for (final state in VehicleGalleryState.values)
          (Appearance(mode: mode), state, '$mode-${state.name}'),
      (
        const Appearance(mode: 'light', palette: 'blue', radius: 0),
        VehicleGalleryState.live,
        'radius-0'
      ),
      (
        const Appearance(
            mode: 'dark', palette: 'blue', radius: 40, glass: true),
        VehicleGalleryState.live,
        'radius-40'
      ),
    ];
    await tester.pumpWidget(const VehicleCardGallery());
    await tester.runAsync(() => precacheImage(
        const AssetImage('assets/art/lynk-05-top-line.webp'),
        tester.element(find.byType(VehicleCardGallery))));
    await tester.pumpAndSettle();
    for (final (appearance, state, suffix) in cases) {
      await tester
          .pumpWidget(VehicleCardGallery(appearance: appearance, state: state));
      await tester.pumpAndSettle();
      expect(find.textContaining('示例数据'), findsOneWidget);
      expect(find.text('紧凑 / 最小 3 × 2'), findsOneWidget);
      expect(find.text('驾驶模式'), findsNWidgets(2));
      expect(find.text('能量流'), findsNWidgets(2));
      expect(find.text('外接充电'), findsNWidgets(2));
      expect(find.text('待同步'), findsAtLeastNWidgets(2));
      final batteryValues = tester.widgetList<Text>(
          find.byKey(const ValueKey('vehicle-value-batteryPercent')));
      expect(batteryValues.map((t) => t.data),
          everyElement(state == VehicleGalleryState.live ? '95' : '—'));
      expect(tester.takeException(), isNull);
      if (!converted && defaultTargetPlatform == TargetPlatform.android) {
        await binding.convertFlutterSurfaceToImage();
        await tester.pumpAndSettle();
        converted = true;
      }
      final name = 'vehicle-cards-$suffix';
      await binding.takeScreenshot(name);
      shots.add(name);
    }
    await tester.pumpWidget(const SizedBox.shrink());
    final screenshots = binding.reportData?['screenshots'];
    binding.reportData = {
      'screenshots': screenshots,
      'gallery': 'vehicle-cards',
      'shots': shots,
      'data':
          'review examples only; no gateway, vehicle commands or layout writes',
    };
  });
}
