import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uni_launcher/model/appearance.dart';
import 'package:uni_launcher/controller/launcher_controller.dart';
import 'package:uni_launcher/launcher_app.dart';
import 'package:uni_launcher/model/card_layout.dart';
import 'package:uni_launcher/model/traffic_light.dart';
import 'package:uni_launcher/theme/launcher_theme.dart';
import 'package:uni_launcher/widgets/embedded_navigation.dart';
import 'package:uni_launcher/widgets/glass_surface.dart';
import 'package:uni_launcher/widgets/traffic_light_card.dart';
import 'package:uni_launcher/widgets/editable_card.dart';
import 'fake_gateway.dart';

Map<String, dynamic> signalState(
        {int age = 0, int ttl = 5000, Object? count = 60}) =>
    {
      'trafficLights': {
        'available': true,
        'reason': 'live',
        'ageMs': age,
        'ttlMs': ttl,
        'enumVerified': false,
        'lights': [
          {
            'rawDirection': 8,
            'rawStatus': 2,
            'direction': 'straight',
            'lamp': 'green',
            'countdownSeconds': count
          }
        ]
      }
    };

Widget review(TrafficLightSnapshot data,
    {Size size = const Size(480, 300),
    bool visible = true,
    bool editing = false,
    VoidCallback? onOpen,
    Appearance appearance = const Appearance(mode: 'dark')}) {
  final s = SurfaceStyle.from(appearance, true);
  return MaterialApp(
      theme: launcherTheme(s),
      home: Scaffold(
          body: Center(
              child: TickerMode(
                  enabled: visible,
                  child: EmbeddedContentPolicy(
                      enabled: true,
                      visible: visible,
                      child: SizedBox.fromSize(
                          size: size,
                          child: GlassSurface(
                              padding: EdgeInsets.zero,
                              child: TrafficLightCard(
                                  snapshot: data,
                                  editing: editing,
                                  onOpenMap: onOpen))))))));
}

void main() {
  test(
      'yh per-field verification is independent; unknown values remain neutral',
      () {
    final native = signalState();
    final raw = native['trafficLights'] as Map;
    raw['lights'] = [
      {
        'direction': 'left',
        'directionVerified': true,
        'lamp': 'red',
        'lampVerified': true,
        'countdownSeconds': 60
      },
      {
        'direction': 'right',
        'directionVerified': true,
        'lamp': 'green',
        'lampVerified': false,
        'countdownSeconds': 24
      },
    ];
    final data = TrafficLightSnapshot.fromNative(native);
    expect(data.lights.map((s) => s.direction), ['left', 'right']);
    expect(data.lights.map((s) => s.lamp), ['red', 'unknown']);
  });

  testWidgets('shows at most three signals with the same icon treatment',
      (t) async {
    final signals = List.generate(
        8,
        (i) => TrafficSignal(
            direction: ['left', 'straight', 'right'][i % 3],
            lamp: 'red',
            countdownSeconds: 60 + i));
    await t.pumpWidget(review(
        TrafficLightSnapshot(available: true, demo: true, lights: signals)));
    await t.pump();
    expect(find.text('60'), findsOneWidget);
    expect(find.text('61'), findsOneWidget);
    expect(find.text('62'), findsOneWidget);
    expect(find.text('63'), findsNothing);
    final left =
        t.getRect(find.byKey(const ValueKey('traffic-reading-left')).first);
    final straight =
        t.getRect(find.byKey(const ValueKey('traffic-reading-straight')).first);
    final right =
        t.getRect(find.byKey(const ValueKey('traffic-reading-right')).first);
    expect(straight.left - left.right, greaterThan(8));
    expect(right.left - straight.right, greaterThan(8));
    expect(find.text('左转'), findsNothing);
    expect(find.text('红灯'), findsNothing);
    expect(find.text('秒'), findsNothing);
    expect(t.takeException(), isNull);
  });
  test('unknown enums stay neutral, validity is bounded and monotonic', () {
    final data = TrafficLightSnapshot.fromNative(signalState(age: 1200));
    expect(data.lights.single.lamp, 'unknown');
    expect(data.lights.single.direction, 'unknown');
    expect(data.lights.single.remaining(data.elapsedAt(1800)), 57);
    expect(data.liveAt(3799), isTrue);
    expect(data.liveAt(3800), isFalse);
    expect(data.lights.single.remaining(60000), isNull);
    for (final bad in [
      -1,
      1000,
      '60',
      true,
      double.nan,
      double.infinity,
      1.5
    ]) {
      expect(
          TrafficLightSnapshot.fromNative(signalState(count: bad))
              .lights
              .single
              .countdownSeconds,
          isNull);
    }
    expect(TrafficLightSnapshot.fromNative(signalState(age: 5000)).available,
        isFalse);
    expect(TrafficLightSnapshot.fromNative(signalState(ttl: 6000)).available,
        isFalse);
    expect(
        TrafficLightSnapshot.fromNative({'trafficLights': 'invalid'}).available,
        isFalse);
    expect(TrafficLightSnapshot.fromNative({}).lights, isEmpty);
    final demo = TrafficLightSnapshot.fromNative({'demo': true});
    expect(demo.demo, isTrue);
    expect(demo.lights.length, 2);
    expect(demo.liveAt(9999999), isTrue);
    expect(TrafficLightSnapshot.fromNative({'demo': false}).lights, isEmpty);
  });

  test('default card and legacy sizes support layout serialization', () {
    final spec = specFor('trafficLight');
    expect((spec.w, spec.h, spec.minW, spec.minH), (4, 2, 4, 2));
    expect(defaultCards().any((c) => c.type == 'trafficLight'), isTrue);
    for (final size in [(4, 2), (4, 3), (8, 3), (8, 6)]) {
      final card = LauncherCard(
          'signal', 'trafficLight', '路口', 0, 0, size.$1, size.$2, 0);
      expect(validLayout([LauncherCard.fromJson(card.toJson())]), isTrue);
    }
  });

  testWidgets('minimum/default sizes fit both themes and square/glass surfaces',
      (t) async {
    t.view.physicalSize = const Size(1920, 1080);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    for (final mode in ['light', 'dark']) {
      for (final size in [
        const Size(360, 150),
        const Size(480, 300),
        const Size(960, 300)
      ]) {
        for (final native in [
          {'demo': true},
          signalState(),
          <String, dynamic>{}
        ]) {
          await t.pumpWidget(review(TrafficLightSnapshot.fromNative(native),
              size: size,
              appearance: Appearance(
                  mode: mode,
                  glass: mode == 'dark',
                  radius: mode == 'light' ? 0 : 24)));
          await t.pump();
          expect(t.takeException(), isNull, reason: '$mode / $size / $native');
        }
      }
    }
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('header opens associated map and editing disables the action',
      (t) async {
    var opens = 0;
    final data = TrafficLightSnapshot.fromNative({'demo': true});
    await t.pumpWidget(review(data, onOpen: () => opens++));
    await t.tap(find.byKey(const ValueKey('traffic-light-open-map')));
    await t.pump();
    expect(opens, 1);
    await t.pumpWidget(review(data, editing: true, onOpen: () => opens++));
    await t.tap(find.byKey(const ValueKey('traffic-light-open-map')));
    await t.pump();
    expect(opens, 1);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets(
      'off-page card cancels countdown timer and shows stale data on reveal',
      (t) async {
    final data = TrafficLightSnapshot.fromNative(signalState(age: 4980));
    await t.pumpWidget(review(data));
    await t.pump();
    await t.pumpWidget(review(data, visible: false));
    await t
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 40)));
    await t.pumpWidget(review(data));
    await t.pump();
    expect(find.text('信号暂未更新'), findsOneWidget);
    expect(find.byKey(const ValueKey('traffic-light-seconds')), findsNothing);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('unrelated parent rebuild cannot restart a received countdown',
      (t) async {
    await t.pumpWidget(
        review(TrafficLightSnapshot.fromNative(signalState(age: 4960))));
    await t
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 70)));
    // A new model for the same native sequence retains its monotonic age.
    await t.pumpWidget(
        review(TrafficLightSnapshot.fromNative(signalState(age: 4960))));
    expect(find.text('信号暂未更新'), findsOneWidget);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('library adds traffic card and persisted layout reloads',
      (t) async {
    t.view.physicalSize = const Size(1920, 1080);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    final gateway = FakeGateway();
    final controller = LauncherController(gateway);
    await controller.initialize();
    await t.pumpWidget(LauncherApp(controller: controller));
    await t.pumpAndSettle();
    controller.beginEdit();
    controller.remove('traffic-light-1');
    await t.pumpAndSettle();
    showCardLibrary(t.element(find.byType(EditableCard).first), controller);
    await t.pumpAndSettle();
    await t.ensureVisible(find.text('红绿灯').last);
    await t.pumpAndSettle();
    await t.tap(find.text('红绿灯').last);
    await t.pumpAndSettle();
    expect(controller.cards.where((card) => card.type == 'trafficLight'),
        hasLength(1));
    controller.finishEdit();
    await t.pumpAndSettle();
    expect(gateway.saved, contains('trafficLight'));
    gateway.state = {...gateway.state, 'savedDesign': gateway.saved};
    final loaded = LauncherController(gateway);
    await loaded.initialize();
    expect(loaded.cards.where((card) => card.type == 'trafficLight'),
        hasLength(1));
    await t.pumpWidget(const SizedBox());
    controller.dispose();
    loaded.dispose();
    await gateway.dispose();
  });
}
