import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:uni_launcher/model/appearance.dart';
import 'package:uni_launcher/model/traffic_light.dart';
import 'package:uni_launcher/theme/launcher_theme.dart';
import 'package:uni_launcher/widgets/glass_surface.dart';
import 'package:uni_launcher/widgets/traffic_light_card.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
      'production traffic card exports themes, sizes and unknown/expired states',
      (t) async {
    var converted = false;
    for (final appearance in const [
      Appearance(mode: 'dark'),
      Appearance(mode: 'light'),
      Appearance(mode: 'light', radius: 0),
      Appearance(mode: 'dark', glass: true),
    ]) {
      await t.pumpWidget(_Gallery(appearance));
      await t.pumpAndSettle();
      expect(find.text('60'), findsOneWidget);
      expect(find.text('24'), findsOneWidget);
      expect(find.text('灯态待确认'), findsNothing);
      expect(find.text('信号暂未更新'), findsOneWidget);
      expect(find.text('等待路口信号'), findsOneWidget);
      expect(t.takeException(), isNull);
      if (!converted) {
        await binding.convertFlutterSurfaceToImage();
        await t.pumpAndSettle();
        converted = true;
      }
      await binding.takeScreenshot(
          'traffic-lights-${appearance.mode}-${appearance.radius.toInt()}-${appearance.glass}');
    }
    await t.pumpWidget(const SizedBox());
    binding.reportData = {
      'data': 'explicit gallery fixtures, not live AMap broadcasts',
      'themes': 2,
      'screenshots': binding.reportData?['screenshots'],
      'checks': [
        'minimum size',
        'multiple directions',
        'single direction',
        'unknown enums',
        'waiting',
        'expired',
        'square corners',
        'glass setting'
      ]
    };
  });
}

class _Gallery extends StatelessWidget {
  final Appearance appearance;
  const _Gallery(this.appearance);
  @override
  Widget build(BuildContext context) {
    final s = SurfaceStyle.from(appearance, true);
    Widget card(TrafficLightSnapshot snapshot, double height) => SizedBox(
        height: height,
        child: GlassSurface(
            padding: EdgeInsets.zero,
            child: TrafficLightCard(snapshot: snapshot)));
    const single = TrafficLightSnapshot(available: true, demo: true, lights: [
      TrafficSignal(direction: 'straight', lamp: 'red', countdownSeconds: 38)
    ]);
    const unknown = TrafficLightSnapshot(
        available: true,
        demo: true,
        lights: [TrafficSignal(countdownSeconds: 50)]);
    return MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: launcherTheme(s),
        home: Scaffold(
            body: SizedBox.expand(
                child: FittedBox(
                    child: SizedBox(
                        width: 1600,
                        height: 900,
                        child: Padding(
                            padding: const EdgeInsets.all(40),
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Text('UNI 桌面 · 红绿灯卡片',
                                      style: TextStyle(
                                          fontSize: 30, color: s.text)),
                                  const SizedBox(height: 10),
                                  Text(
                                      'Android 9 模拟器 / 示例数据 / ${appearance.mode} / 圆角 ${appearance.radius}',
                                      style: TextStyle(
                                          fontSize: 17, color: s.muted)),
                                  const SizedBox(height: 28),
                                  Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Expanded(
                                            child: card(
                                                TrafficLightSnapshot.fromNative(
                                                    {'demo': true}),
                                                300)),
                                        const SizedBox(width: 24),
                                        Expanded(
                                            child: Column(children: [
                                          card(single, 150),
                                          const SizedBox(height: 20),
                                          card(unknown, 150),
                                        ])),
                                      ]),
                                  const SizedBox(height: 28),
                                  Row(children: [
                                    Expanded(
                                        child: card(
                                            const TrafficLightSnapshot(), 190)),
                                    const SizedBox(width: 24),
                                    Expanded(
                                        child: card(
                                            const TrafficLightSnapshot(
                                                reason: 'expired'),
                                            190)),
                                  ]),
                                  const SizedBox(height: 28),
                                  Text(
                                      '方向和灯态以数据为准 · 未确认枚举用中性色 · 超时清空 · 真实路口接收待实车核对',
                                      style: TextStyle(
                                          fontSize: 18, color: s.muted)),
                                ])))))));
  }
}
