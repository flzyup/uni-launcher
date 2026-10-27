import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uni_launcher/controller/launcher_controller.dart';
import 'package:uni_launcher/model/appearance.dart';
import 'package:uni_launcher/model/card_layout.dart';
import 'package:uni_launcher/model/vehicle_card_data.dart';
import 'package:uni_launcher/theme/launcher_theme.dart';
import 'package:uni_launcher/widgets/card_content.dart';
import 'package:uni_launcher/widgets/editable_card.dart';
import 'package:uni_launcher/widgets/glass_surface.dart';
import 'package:uni_launcher/widgets/vehicle_cards.dart';
import '../integration_test/vehicle_card_gallery.dart';
import 'fake_gateway.dart';

Map<String, dynamic> field(Map<String, dynamic> native, String key) =>
    (native['vehicle']['fields'][key] as Map<String, dynamic>);

VehicleCardReading reading(Map<String, dynamic> native, String key,
        {int now = vehicleGalleryNow}) =>
    VehicleCardReading.fromNative(native, key, nowMs: now);

Widget surface(Widget child,
    {Size size = const Size(480, 300),
    Appearance appearance = const Appearance(mode: 'dark'),
    double textScale = 1}) {
  final style = SurfaceStyle.from(appearance, true);
  return MaterialApp(
      theme: launcherTheme(style),
      home: Scaffold(
          body: MediaQuery(
              data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
              child: Center(
                  child: SizedBox.fromSize(
                      size: size,
                      child: GlassSurface(
                          padding: EdgeInsets.zero, child: child))))));
}

void main() {
  test(
      'PHEV statuses require their own fresh known enum and never infer charging',
      () {
    final native = vehicleGalleryFixture();
    String label(String key) =>
        vehicleStatusLabel(native, key, nowMs: vehicleGalleryNow);
    expect(label('driveMode'), '混动');
    expect(label('energyFlow'), '电力驱动');
    expect(label('charging'), '待同步');
    field(native, 'energyFlow')['value'] = 'ENGINE_ONLY_AND_CHARGE';
    expect(label('energyFlow'), '发动机驱动并发电');
    expect(label('charging'), '待同步');
    field(native, 'driveMode')['value'] = 'UNKNOWN';
    expect(label('driveMode'), '待同步');
    field(native, 'driveMode')['updatedAtMs'] = vehicleGalleryNow - 6000;
    expect(label('driveMode'), '等待更新');
    field(native, 'energyFlow')['updatedAtMs'] = 'bad';
    expect(label('energyFlow'), '待同步');
    native['vehicle']['connected'] = false;
    expect(label('driveMode'), '未连接');
    expect(label('energyFlow'), '未连接');
  });
  test(
      'current two-screen vehicle layout is the default and legacy layouts survive',
      () {
    expect(cardSpecs.map((s) => s.type).toSet(), {
      'nav',
      'trafficLight',
      'music',
      'weather',
      'calendar',
      'member',
      'cleanup',
      'tpms',
      'air',
      'ride',
      'clock',
      'clockWeather',
      'shortcuts',
      'vehicle',
      'battery'
    });
    expect(defaultCards().map((c) => c.type), [
      'nav',
      'music',
      'trafficLight',
      'tpms',
      'battery',
      'clockWeather',
      'shortcuts',
      'vehicle',
      'air'
    ]);
    for (final type in ['battery', 'air', 'vehicle']) {
      final spec = specFor(type);
      expect((spec.w, spec.h, spec.minW, spec.minH), (4, 3, 3, 2));
      final old = LauncherCard('old', type, '自定名称', 0, 0, 3, 2, 0);
      expect(validLayout([LauncherCard.fromJson(old.toJson())]), isTrue);
    }
  });

  test('seven live fields retain source values and independent confirmed units',
      () {
    final native = vehicleGalleryFixture();
    for (final key in [
      'batteryPercent',
      'pm25',
      'aqi',
      'speed',
      'odometer',
      'range',
      'maintenanceMileage'
    ]) {
      final r = reading(native, key);
      expect(r.state, VehicleReadingState.live, reason: key);
      expect(r.value, field(native, key)['value'], reason: key);
      expect(r.unit, field(native, key)['unit'], reason: key);
    }
    field(native, 'speed').addAll({'value': 18.5, 'unit': 'm/s'});
    field(native, 'odometer')['unit'] = 'mi';
    expect(reading(native, 'speed').display, '18.5');
    expect(reading(native, 'speed').unit, 'm/s');
    expect(reading(native, 'odometer').unit, 'mi');
    expect(reading(native, 'range').unit, 'km');
    field(native, 'speed')['unit'] = 'mph';
    expect(reading(native, 'speed').unit, 'mph');
  });

  test(
      'freshness is per field with the existing five second and clock tolerance',
      () {
    final native = vehicleGalleryFixture();
    field(native, 'batteryPercent')['updatedAtMs'] = vehicleGalleryNow - 5000;
    expect(reading(native, 'batteryPercent').available, isTrue);
    expect(reading(native, 'batteryPercent', now: vehicleGalleryNow + 1).state,
        VehicleReadingState.stale);
    expect(reading(native, 'pm25').available, isTrue);
    field(native, 'speed')['updatedAtMs'] = vehicleGalleryNow + 1000;
    expect(reading(native, 'speed').available, isTrue);
    field(native, 'speed')['updatedAtMs'] = vehicleGalleryNow + 1001;
    expect(reading(native, 'speed').available, isFalse);
    native['vehicle']['connected'] = false;
    expect(reading(native, 'batteryPercent').state,
        VehicleReadingState.disconnected);
    expect(reading(native, 'pm25').display, '—');
  });

  test(
      'raw samples, unknown units, invalid and malformed values never become readings',
      () {
    final native = vehicleGalleryFixture();
    field(native, 'range').addAll({
      'unit': 'raw',
      'unitVerified': false,
      'valid': false,
      'sampleValid': true,
      'sampleValue': 426,
      'raw': 426,
    });
    expect(reading(native, 'range').state, VehicleReadingState.unconfirmedUnit);
    expect(reading(native, 'range').unit, isEmpty);
    field(native, 'speed').remove('unitVerified');
    expect(reading(native, 'speed').display, '—');
    for (final bad in [
      null,
      '95',
      true,
      double.nan,
      double.infinity,
      -1,
      101
    ]) {
      field(native, 'batteryPercent')['value'] = bad;
      expect(reading(native, 'batteryPercent').display, '—', reason: '$bad');
    }
    field(native, 'batteryPercent')['value'] = 95;
    for (final bad in [null, 'today', double.nan, double.infinity, 0]) {
      field(native, 'batteryPercent')['updatedAtMs'] = bad;
      expect(reading(native, 'batteryPercent').available, isFalse);
    }
    expect(reading({'vehicle': 'invalid'}, 'batteryPercent').display, '—');
    expect(
        reading({
          'vehicle': {'connected': true, 'fields': []}
        }, 'pm25')
            .display,
        '—');
    field(native, 'aqi')['valid'] = false;
    expect(reading(native, 'aqi').display, '—');
    expect(reading(native, 'pm25').display, '12');
  });

  testWidgets('battery 0 95 100 and fractional levels occupy exact track width',
      (t) async {
    for (final value in [0.0, 95.0, 100.0, 95.5]) {
      final native = vehicleGalleryFixture();
      field(native, 'batteryPercent')['value'] = value;
      await t.pumpWidget(
          surface(BatteryCard(native: native, nowMs: () => vehicleGalleryNow)));
      await t.pumpAndSettle();
      final track =
          t.getSize(find.byKey(const ValueKey('battery-track'))).width;
      final fill = t.getSize(find.byKey(const ValueKey('battery-fill'))).width;
      expect(fill, closeTo(track * value / 100, .001));
      expect(find.text('驾驶模式'), findsOneWidget);
      expect(find.text('混动'), findsOneWidget);
      expect(find.text('电力驱动'), findsOneWidget);
      expect(find.text('外接充电'), findsOneWidget);
      expect(find.text('待同步'), findsNothing);
      expect(find.text('已同步'), findsNothing);
      expect(find.textContaining('充电中'), findsNothing);
    }
    await t.pumpWidget(surface(BatteryCard(
        native: vehicleGalleryFixture(VehicleGalleryState.disconnected),
        nowMs: () => vehicleGalleryNow)));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('vehicle-value-batteryPercent')),
        findsOneWidget);
    expect(t.getSize(find.byKey(const ValueKey('battery-fill'))).width, 0);
    await t.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
      'readings expire without a new event and recover on a fresh snapshot',
      (t) async {
    var now = vehicleGalleryNow;
    final native = vehicleGalleryFixture();
    field(native, 'pm25')['updatedAtMs'] = now - 4900;
    await t
        .pumpWidget(surface(AirQualityCard(native: native, nowMs: () => now)));
    await t.pumpAndSettle();
    expect(find.text('12'), findsOneWidget);
    now += 101;
    await t.pump(const Duration(milliseconds: 101));
    expect(
        t.widget<Text>(find.byKey(const ValueKey('vehicle-value-pm25'))).data,
        '—');
    expect(find.text('等待更新'), findsNothing);
    expect(find.text('28'), findsOneWidget);
    final next = vehicleGalleryFixture();
    field(next, 'pm25').addAll({'value': 7, 'updatedAtMs': now});
    await t.pumpWidget(surface(AirQualityCard(native: next, nowMs: () => now)));
    await t.pumpAndSettle();
    expect(find.text('7'), findsOneWidget);
    expect(find.text('等待更新'), findsNothing);
    await t.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
      'all cards fit minimum and edit space across scale theme glass and corners',
      (t) async {
    final cases = [
      (const Size(480, 300), const Appearance(mode: 'dark'), 1.0),
      (
        const Size(355, 580 / 3),
        const Appearance(mode: 'light', radius: 0),
        1.0
      ),
      // Edit controls reserve another 64 design pixels above the content.
      (
        const Size(355, 140),
        const Appearance(mode: 'dark', radius: 40, glass: true),
        1.0
      ),
      (
        const Size(240, 90),
        const Appearance(mode: 'light', palette: 'rose'),
        1.5
      ),
    ];
    for (final (size, appearance, scale) in cases) {
      for (final state in VehicleGalleryState.values) {
        final native = vehicleGalleryFixture(state);
        for (final card in [
          BatteryCard(
              native: native,
              title: '动力电池自定名称测试',
              nowMs: () => vehicleGalleryNow),
          AirQualityCard(native: native, nowMs: () => vehicleGalleryNow),
          DrivingInfoCard(native: native, nowMs: () => vehicleGalleryNow),
        ]) {
          await t.pumpWidget(surface(card,
              size: size, appearance: appearance, textScale: scale));
          await t.pumpAndSettle();
          expect(t.takeException(), isNull,
              reason: '$size $state ${card.runtimeType}');
        }
      }
    }
    await t.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
      'library adds all three, editor saves default/minimum and reloads without car commands',
      (t) async {
    t.view.physicalSize = const Size(1920, 1080);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    final g = FakeGateway();
    final controller = LauncherController(g);
    await controller.initialize();
    controller.beginEdit();
    late BuildContext context;
    await t.pumpWidget(MaterialApp(
        theme: launcherTheme(SurfaceStyle.from(const Appearance(), true)),
        home: Scaffold(body: Builder(builder: (ctx) {
          context = ctx;
          return const SizedBox.shrink();
        }))));
    for (final type in ['battery', 'air', 'vehicle']) {
      showCardLibrary(context, controller);
      await t.pumpAndSettle();
      await t.ensureVisible(find.byKey(ValueKey('add-$type')));
      await t.tap(find.byKey(ValueKey('add-$type')));
      await t.pumpAndSettle();
      final card = controller.cards.last;
      expect((card.type, card.w, card.h), (type, 4, 3));
      editCard(context, controller, card);
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('card-size-4-3')), findsOneWidget);
      await t.enterText(
          find.byKey(const ValueKey('card-title')), '我的${specFor(type).label}');
      await t.tap(find.byKey(const ValueKey('card-size-3-2')));
      await t.tap(find.text('保存卡片'));
      await t.pumpAndSettle();
      expect((controller.cards.last.w, controller.cards.last.h), (3, 2));
    }
    controller.finishEdit();
    await controller.persist();
    final loadedGateway = FakeGateway()..state['savedDesign'] = g.saved;
    final loaded = LauncherController(loadedGateway);
    await loaded.initialize();
    expect(
        jsonDecode(loaded.serialize())['cards'], jsonDecode(g.saved!)['cards']);
    expect(loaded.cards.take(defaultCards().length).map((c) => c.toJson()),
        defaultCards().map((c) => c.toJson()));
    expect(g.commands, isEmpty);
    expect(validLayout(loaded.cards), isTrue);
    // Compatibility names migrate only in presentation; stored custom titles stay intact.
    for (final (type, old, title) in [
      ('air', '空气质量', '车内空气'),
      ('vehicle', '车辆信息', '行车信息'),
    ]) {
      await t.pumpWidget(surface(CardContent(
          card: LauncherCard('legacy', type, old, 0, 0, 4, 3, 0),
          controller: loaded)));
      await t.pumpAndSettle();
      expect(find.text(title), findsOneWidget);
      expect(find.text('左前'), findsNothing);
    }
    await t.pumpWidget(const SizedBox.shrink());
    controller.dispose();
    loaded.dispose();
    await g.dispose();
    await loadedGateway.dispose();
  });

  testWidgets(
      'independent gallery renders and optionally exports eight review boards',
      (t) async {
    const output = String.fromEnvironment('VEHICLE_GALLERY_OUTPUT');
    if (output.isNotEmpty) {
      const fontPath = String.fromEnvironment('VEHICLE_GALLERY_FONT',
          defaultValue:
              '/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc');
      await t.runAsync(() async {
        final bytes = await File(fontPath).readAsBytes();
        final loader = FontLoader('VehicleGalleryReview')
          ..addFont(Future.value(ByteData.sublistView(bytes)));
        await loader.load();
      });
    }
    t.view.physicalSize = const Size(1920, 1080);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    final cases = [
      for (final mode in ['dark', 'light'])
        for (final state in VehicleGalleryState.values)
          (Appearance(mode: mode), state, '$mode-${state.name}'),
      (
        const Appearance(mode: 'light', radius: 0, palette: 'blue'),
        VehicleGalleryState.live,
        'radius-0'
      ),
      (
        const Appearance(
            mode: 'dark', radius: 40, palette: 'blue', glass: true),
        VehicleGalleryState.live,
        'radius-40'
      ),
    ];
    await t.pumpWidget(VehicleCardGallery(
        fontFamily: output.isEmpty ? null : 'VehicleGalleryReview'));
    await t.runAsync(() => precacheImage(
        const AssetImage('assets/art/lynk-05-top-line.png'),
        t.element(find.byType(VehicleCardGallery))));
    await t.pumpAndSettle();
    for (final (appearance, state, suffix) in cases) {
      await t.pumpWidget(VehicleCardGallery(
          appearance: appearance,
          state: state,
          fontFamily: output.isEmpty ? null : 'VehicleGalleryReview'));
      await t.pumpAndSettle();
      expect(find.textContaining('示例数据'), findsOneWidget);
      expect(find.text('紧凑 / 最小 3 × 2'), findsOneWidget);
      expect(t.takeException(), isNull);
      if (output.isNotEmpty) {
        final boundary = t.renderObject<RenderRepaintBoundary>(
            find.byKey(vehicleGalleryBoardKey));
        await t.runAsync(() async {
          final image = await boundary.toImage(pixelRatio: 1.2);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          final directory = Directory(output)..createSync(recursive: true);
          await File('${directory.path}/vehicle-cards-$suffix.png')
              .writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
    }
    await t.pumpWidget(const SizedBox.shrink());
  });
}
