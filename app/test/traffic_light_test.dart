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
import 'package:uni_launcher/widgets/signal_arrow.dart';
import 'package:uni_launcher/widgets/traffic_light_card.dart';
import 'package:uni_launcher/widgets/uni_icon.dart';
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
  test('绿灯最后 3 秒按黄灯展示，红灯与无倒计时一律不动', () {
    const green = TrafficSignal(
        direction: 'straight', lamp: 'green', countdownSeconds: 10);
    expect(green.lampAt(0), 'green');
    expect(green.lampAt(6900), 'green'); // 剩 4 秒，还没到
    expect(green.lampAt(7000), 'amber'); // 剩 3 秒，切黄
    expect(green.lampAt(9000), 'amber'); // 剩 1 秒
    expect(green.lampLabelAt(7000), '黄灯');
    // 归零后没有秒数可依据，不猜——保持数据里的绿灯，等下一批广播。
    expect(green.lampAt(10000), 'green');
    expect(green.lampAt(99000), 'green');
    const red =
        TrafficSignal(direction: 'straight', lamp: 'red', countdownSeconds: 3);
    expect(red.lampAt(0), 'red');
    expect(red.lampLabelAt(0), '红灯');
    const noCount = TrafficSignal(direction: 'straight', lamp: 'green');
    expect(noCount.lampAt(0), 'green');
    const unknown = TrafficSignal(
        direction: 'unknown', lamp: 'unknown', countdownSeconds: 2);
    expect(unknown.lampAt(0), 'unknown');
  });

  testWidgets('绿灯最后 3 秒灯珠转黄、倒计时照常显示', (t) async {
    Future<Color> ringBorder(String lamp, int count) async {
      await t.pumpWidget(review(TrafficLightSnapshot(available: true, lights: [
        TrafficSignal(direction: 'left', lamp: lamp, countdownSeconds: count)
      ])));
      await t.pumpAndSettle();
      final box = t
          .widget<Container>(find.byKey(const ValueKey('traffic-ring-left')))
          .decoration! as BoxDecoration;
      return box.border!.top.color;
    }

    // 暗夜稿子色：绿 0xFF71E4B4 / 黄 0xFFFFD17D / 红 0xFFFF8C7F，环色压到 88%。
    Color dark(Color c) => c.withValues(alpha: .88);
    expect(await ringBorder('green', 10), dark(const Color(0xFF71E4B4)));
    expect(await ringBorder('green', 3), dark(const Color(0xFFFFD17D)));
    expect(await ringBorder('red', 3), dark(const Color(0xFFFF8C7F)));
    // 秒数照常是 3，不会变成「—」。
    expect(find.text('3'), findsOneWidget);
    expect(t.takeException(), isNull);
  });

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
    // 三列各画一颗稿子箭头（左转那条带弯角），不再用 assets/icons 的线性图。
    expect(find.byType(SignalArrow), findsNWidgets(3));
    expect(t.takeException(), isNull);
  });

  testWidgets('灯珠：箭头一律白色，浅色实心同色底、暗夜压暗', (t) async {
    const one = TrafficLightSnapshot(available: true, demo: true, lights: [
      TrafficSignal(direction: 'left', lamp: 'red', countdownSeconds: 30)
    ]);
    BoxDecoration ring() => t
        .widget<Container>(find.byKey(const ValueKey('traffic-ring-left')))
        .decoration! as BoxDecoration;
    await t
        .pumpWidget(review(one, appearance: const Appearance(mode: 'light')));
    await t.pumpAndSettle();
    // 浅色：45% 同色底——比实心灯珠淡，白箭头又看得清。
    expect(t.widget<SignalArrow>(find.byType(SignalArrow)).color, Colors.white);
    expect(ring().color!.a, closeTo(.45, .01));
    await t.pumpWidget(review(one, appearance: const Appearance(mode: 'dark')));
    await t.pumpAndSettle();
    // 暗夜：淡底（10%）+ 环压到 88% + 外发光只留一点点。
    expect(t.widget<SignalArrow>(find.byType(SignalArrow)).color, Colors.white);
    expect(ring().color!.a, closeTo(.10, .01));
    expect(ring().boxShadow!.single.color.a, closeTo(.12, .01));
    expect(t.takeException(), isNull);
  });

  testWidgets('未知方向退回通用红绿灯图标', (t) async {
    await t.pumpWidget(review(TrafficLightSnapshot(
        available: true,
        demo: true,
        lights: const [
          TrafficSignal(direction: 'unknown', lamp: 'red', countdownSeconds: 9)
        ])));
    await t.pump();
    expect(find.byType(SignalArrow), findsNothing);
    expect(find.byType(UniIcon), findsWidgets);
    expect(t.takeException(), isNull);
  });

  testWidgets('三路信号固定按 左转→直行→右转 排列，与到货顺序无关', (t) async {
    await t.pumpWidget(
        review(TrafficLightSnapshot(available: true, demo: true, lights: const [
      TrafficSignal(direction: 'right', lamp: 'green', countdownSeconds: 5),
      TrafficSignal(direction: 'straight', lamp: 'red', countdownSeconds: 30),
      TrafficSignal(direction: 'left', lamp: 'red', countdownSeconds: 60),
    ])));
    await t.pump();
    double x(String dir) =>
        t.getRect(find.byKey(ValueKey('traffic-reading-$dir'))).left;
    expect(x('left'), lessThan(x('straight')));
    expect(x('straight'), lessThan(x('right')));
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
    // minH 1：一格高时不画卡头，读数撑满整卡。
    expect((spec.w, spec.h, spec.minW, spec.minH), (4, 2, 4, 1));
    expect(defaultCards().any((c) => c.type == 'trafficLight'), isTrue);
    for (final size in [(4, 1), (4, 2), (4, 3), (8, 3), (8, 6)]) {
      final card = LauncherCard(
          'signal', 'trafficLight', '路口', 0, 0, size.$1, size.$2, 0);
      expect(validLayout([LauncherCard.fromJson(card.toJson())]), isTrue);
    }
  });

  test('high fidelity uses real map signals and never demo countdowns', () {
    final state = {
      ...signalState(count: 19),
      'demo': true,
      'simulationMode': 'highFidelity',
    };
    final live = TrafficLightSnapshot.fromNative(state);
    expect(live.demo, isFalse);
    expect(live.lights.single.countdownSeconds, 19);
    expect(
        TrafficLightSnapshot.fromNative({
          'demo': true,
          'simulationMode': 'highFidelity',
        }).lights,
        isEmpty);
    expect(
        TrafficLightSnapshot.fromNative({
          ...state,
          'trafficLights': {'available': false},
        }).lights,
        isEmpty);
    expect(
        TrafficLightSnapshot.fromNative({
          ...signalState(age: 6000),
          'demo': true,
          'simulationMode': 'highFidelity',
        }).lights,
        isEmpty);
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

  // 一格高（4×1）是 2026-11-15 新放开的档：卡高只有 ~100 px，卡头那一行会
  // 吃掉三分之一，所以这一档不画卡头，读数撑满整卡。4×2 仍然有卡头。
  testWidgets('one-row card drops the header and keeps readings inside',
      (t) async {
    t.view.physicalSize = const Size(1920, 1080);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    final data = TrafficLightSnapshot.fromNative({'demo': true});
    await t.pumpWidget(review(data, size: const Size(608, 100)));
    await t.pump();
    expect(t.takeException(), isNull);
    expect(find.text('红绿灯'), findsNothing, reason: '一格档不画标题');
    expect(find.byKey(const ValueKey('traffic-light-open-map')), findsNothing,
        reason: '卡头整行都不在，点击进地图的入口也一起消失');

    final card = t.getRect(find.byType(GlassSurface));
    final row =
        t.getRect(find.byKey(const ValueKey('traffic-light-directions')));
    expect(row.top, greaterThanOrEqualTo(card.top));
    expect(row.bottom, lessThanOrEqualTo(card.bottom));
    // 只有 6 画布（~5 px）的上下留白：读数基本贴着卡高排，没有半截空白。
    expect(row.height, greaterThan(card.height * .7));

    // 4×2 起卡头回来（回归：不能因为一格档把标题全局删了）。
    await t.pumpWidget(review(data, size: const Size(608, 220)));
    await t.pump();
    expect(find.text('红绿灯'), findsOneWidget);
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

  testWidgets('heading stays at the top for waiting and single signal',
      (t) async {
    await t.pumpWidget(review(TrafficLightSnapshot.fromNative({})));
    await t.pump();
    final waitingTop =
        t.getTopLeft(find.byKey(const ValueKey('traffic-light-open-map'))).dy;
    await t.pumpWidget(review(TrafficLightSnapshot.fromNative(signalState())));
    await t.pump();
    expect(
        t.getTopLeft(find.byKey(const ValueKey('traffic-light-open-map'))).dy,
        closeTo(waitingTop, .1));
    // 头部右侧不再写来源（用户 2026-11-13 实车反馈），只剩灯 + 标题。
    expect(find.text('高德地图'), findsNothing);
    expect(t.takeException(), isNull);
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
