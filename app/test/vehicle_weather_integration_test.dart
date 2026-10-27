import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uni_launcher/controller/launcher_controller.dart';
import 'package:uni_launcher/launcher_app.dart';
import 'package:uni_launcher/model/vehicle_data.dart';
import 'package:uni_launcher/model/seat_control.dart';
import 'package:uni_launcher/model/weather_condition.dart';
import 'package:uni_launcher/theme/launcher_theme.dart';
import 'package:uni_launcher/model/appearance.dart';
import 'package:uni_launcher/widgets/weather_icon.dart';
import 'package:uni_launcher/widgets/embedded_navigation.dart';
import 'package:uni_launcher/widgets/card_content.dart';
import 'fake_gateway.dart';

void main() {
  testWidgets('OEM inset fluctuations never move the dock', (t) async {
    t.view.physicalSize = const Size(1920, 944);
    t.view.devicePixelRatio = 1;
    t.view.padding = const FakeViewPadding(bottom: 136);
    final g = FakeGateway();
    final controller = LauncherController(g);
    g.state['contentReservesSystemBars'] = false;
    await controller.initialize();
    await t.pumpWidget(LauncherApp(controller: controller));
    await t.pumpAndSettle();
    final before = t.getRect(find.byKey(const ValueKey('bottom-dock'))).bottom;
    g.state['contentReservesSystemBars'] = true;
    g.stream.add(Map.of(g.state));
    await t.pumpAndSettle();
    final after = t.getRect(find.byKey(const ValueKey('bottom-dock'))).bottom;
    expect(after, before);
    expect(after, greaterThan(920));
    expect(after, closeTo(944, .1));
    // Some Android 9 car builds report the reserved bar as a keyboard inset.
    t.view.padding = const FakeViewPadding();
    t.view.viewInsets = const FakeViewPadding(bottom: 136);
    g.state['contentReservesSystemBars'] = false;
    g.stream.add(Map.of(g.state));
    await t.pumpAndSettle();
    final keyboardBefore =
        t.getRect(find.byKey(const ValueKey('bottom-dock'))).bottom;
    g.state['contentReservesSystemBars'] = true;
    g.stream.add(Map.of(g.state));
    await t.pumpAndSettle();
    final keyboardAfter =
        t.getRect(find.byKey(const ValueKey('bottom-dock'))).bottom;
    expect(keyboardBefore, before);
    expect(keyboardAfter, before);
    expect(keyboardAfter, greaterThan(920));
    // ActivityView can temporarily report a full-height Flutter viewport while
    // the real native content frame still stops above the OEM bottom bar.
    t.view.physicalSize = const Size(1920, 1080);
    g.state['contentHeightPx'] = 1080;
    g.state['viewportHeightPx'] = 944;
    g.stream.add(Map.of(g.state));
    await t.pumpAndSettle();
    expect(t.getRect(find.byKey(const ValueKey('bottom-dock'))).bottom, before);
    await t.pumpWidget(const SizedBox.shrink());
    controller.dispose();
    await g.dispose();
    t.view.resetPadding();
    t.view.resetViewInsets();
    t.view.resetPhysicalSize();
    t.view.resetDevicePixelRatio();
  });
  test('Each climate control requires its own fresh writable reading', () {
    final now = DateTime.now().millisecondsSinceEpoch;
    final n = <String, dynamic>{
      'vehicle': {
        'connected': true,
        'writable': true,
        'climateCapabilities': {
          'left': {'writable': true},
          'right': {'writable': false}
        },
        'fields': {
          'left': {'valid': true, 'value': 22.5, 'updatedAtMs': now},
          'right': {'valid': true, 'value': 22.5, 'updatedAtMs': now},
        }
      }
    };
    expect(climateWritable(n, 'left'), true);
    expect(climateWritable(n, 'right'), false);
    expect(climateWritable(n, 'power'), false);
  });
  test('Demo seats use simulator levels even with an unavailable vehicle map',
      () {
    final n = <String, dynamic>{
      'demo': true,
      'climate': {'driverHeat': 2, 'driverVent': 0, 'passengerHeat': 3},
      'vehicle': {'connected': false, 'fields': <String, dynamic>{}}
    };
    expect(SeatControlState.fromNative(n, 'driverHeat').level, 2);
    expect(SeatControlState.fromNative(n, 'driverVent').level, 0);
    expect(SeatControlState.fromNative(n, 'passengerHeat').level, 3);
    n['demo'] = false;
    expect(SeatControlState.fromNative(n, 'driverHeat').level, null);
  });
  test('Music source label follows the associated installed application', () {
    final n = <String, dynamic>{
      'media': {'source': 'com.tencent.qqmusic'},
      'apps': [
        {'package': 'com.tencent.qqmusic', 'label': 'QQ 音乐'}
      ]
    };
    expect(mediaSourceLabel(n), 'QQ 音乐');
    n['media'] = {};
    n['integrationPreferences'] = {'mediaPackage': 'com.tencent.qqmusic'};
    expect(mediaSourceLabel(n), 'QQ 音乐');
  });
  test(
      'All weather labels and stable IDs map, provider numeric codes stay unknown',
      () {
    for (final k in WeatherKind.values) {
      expect(WeatherKind.fromText(k.label), k);
      expect(WeatherKind.fromText(k.name), k);
    }
    expect(WeatherKind.fromText('小到中雨'), WeatherKind.moderateRain);
    expect(WeatherKind.fromText('晴转暴雪'), WeatherKind.blizzard);
    expect(WeatherKind.fromText('123456'), WeatherKind.unknown);
    expect(WeatherKind.fromText(null), WeatherKind.unknown);
    expect(WeatherKind.fromText('新天气代码'), WeatherKind.unknown);
    expect(WeatherKind.fromWmo(0), WeatherKind.clear);
    expect(WeatherKind.fromWmo(65), WeatherKind.heavyRain);
    expect(WeatherKind.fromWmo(96), WeatherKind.hail);
    expect(WeatherKind.fromWmo(1234), WeatherKind.unknown);
  });
  testWidgets('Every weather icon paints visible pixels by day and night',
      (t) async {
    final signatures = <WeatherKind, int>{};
    for (final night in [false, true])
      for (final k in WeatherKind.values) {
        final recorder = ui.PictureRecorder(), canvas = Canvas(recorder);
        WeatherPainter(k, night, const Color(0xff71e4ce))
            .paint(canvas, const Size(128, 128));
        final picture = recorder.endRecording();
        final bytes = await t.runAsync(() async {
          final image = await picture.toImage(128, 128);
          final data =
              await image.toByteData(format: ui.ImageByteFormat.rawRgba);
          image.dispose();
          return data!;
        });
        picture.dispose();
        final pixels = bytes!.buffer.asUint8List();
        int visible = 0, signature = 0;
        for (int i = 3; i < pixels.length; i += 4) {
          if (pixels[i] > 0) {
            visible++;
            signature = (signature + i * pixels[i]) & 0x7fffffff;
          }
        }
        expect(visible, greaterThan(100),
            reason: '${k.name} $night has visible vector artwork');
        if (!night) signatures[k] = signature;
      }
    expect(signatures[WeatherKind.clear],
        isNot(signatures[WeatherKind.partlyCloudy]));
    expect(signatures[WeatherKind.lightRain],
        isNot(signatures[WeatherKind.heavyRain]));
    expect(signatures[WeatherKind.lightSnow],
        isNot(signatures[WeatherKind.blizzard]));
    expect(signatures[WeatherKind.fog], isNot(signatures[WeatherKind.haze]));
    expect(signatures[WeatherKind.hot], isNot(signatures[WeatherKind.cold]));
  });
  test('Weather never fabricates live weather and tolerates unknown conditions',
      () {
    final empty = WeatherSnapshot.fromNative({'demo': false});
    expect(empty.temperature, null);
    expect(empty.condition, WeatherKind.unknown);
    final value = WeatherSnapshot.fromNative({
      'weather': {
        'available': true,
        'condition': '冻雨',
        'night': true,
        'temperature': -3,
        'city': '北京',
        'source': 'fixture'
      }
    });
    expect(value.condition, WeatherKind.freezingRain);
    expect(value.temperature, -3);
    expect(value.night, true);
  });
  test('Weather forecast parses separately from OEM condition codes', () {
    final value = WeatherSnapshot.fromNative({
      'weather': {
        'available': true,
        'condition': '多云',
        'temperature': 23,
        'city': '杭州',
        'humidity': 68,
        'forecastSource': 'Open-Meteo',
        'forecastLocation': '上海市',
        'forecastCityFallback': true,
        'forecastUpdatedAtMs': 1000,
        'forecasts': [
          {
            'date': '2026-10-26',
            'wmoCode': 61,
            'minimum': 17.2,
            'maximum': 25.4,
            'precipitation': 70,
            'windSpeed': 13
          }
        ]
      }
    });
    expect(value.humidity, 68);
    expect(value.forecastSource, 'Open-Meteo');
    expect(value.forecastLocation, '上海市');
    expect(value.forecastCityFallback, true);
    expect(value.forecasts, hasLength(1));
    expect(value.forecasts.single.condition, WeatherKind.lightRain);
    expect(value.forecasts.single.minimum, 17.2);
    expect(value.forecasts.single.precipitation, 70);
  });
  test('Vehicle fields expire individually and disconnect removes readings',
      () {
    final n = <String, dynamic>{
      'vehicle': {
        'connected': true,
        'fields': {
          'left': {'valid': true, 'value': 22.5, 'updatedAtMs': 10000},
          'fan': {'valid': false, 'value': 5, 'updatedAtMs': 11000},
          'pressureFrontLeft': {
            'valid': true,
            'value': 2.46,
            'unit': 'bar',
            'updatedAtMs': 10000
          }
        }
      }
    };
    expect(VehicleField.fromNative(n, 'left', nowMs: 12000).display(), '22.5');
    expect(VehicleField.fromNative(n, 'left', nowMs: 16000).valid, false);
    expect(VehicleField.fromNative(n, 'fan', nowMs: 12000).display(), '—');
    expect(VehicleField.fromNative(n, 'pressureFrontLeft', nowMs: 12000).unit,
        'bar');
    (n['vehicle'] as Map)['connected'] = false;
    expect(VehicleField.fromNative(n, 'left', nowMs: 12000).display(), '—');
  });
  testWidgets(
      'Live nav uses actual map container fallback and never illustrative map',
      (t) async {
    t.view.physicalSize = const Size(1920, 1080);
    t.view.devicePixelRatio = 1;
    final g = FakeGateway();
    g.state['demo'] = false;
    g.state['navigation'] = {
      'canEmbed': false,
      'reason': '需要车机系统嵌入授权',
      'package': 'com.autonavi.amapauto',
      'enabled': true
    };
    final c = LauncherController(g);
    await c.initialize();
    await t.pumpWidget(LauncherApp(controller: c));
    await t.pumpAndSettle();
    expect(find.byType(EmbeddedNavigationCard), findsOneWidget);
    expect(find.text('600 米后右转'), findsNothing);
    await t.tap(find.text('全屏打开导航'));
    await t.pumpAndSettle();
    expect(g.commands.last['action'], 'launch-navigation');
    c.openSettings();
    c.tab('system');
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('media-source')), findsOneWidget);
    expect(find.byKey(const ValueKey('navigation-source')), findsOneWidget);
    await t.pumpWidget(const SizedBox.shrink());
    c.dispose();
    await g.dispose();
    t.view.resetPhysicalSize();
    t.view.resetDevicePixelRatio();
  });
  testWidgets(
      'Pages settings and modals retain one live map without overlay leakage',
      (t) async {
    t.view.physicalSize = const Size(1920, 1080);
    t.view.devicePixelRatio = 1;
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final g = FakeGateway();
    g.state['demo'] = false;
    g.state['navigation'] = {
      'canEmbed': true,
      'package': 'com.autonavi.amapauto',
      'reason': '未授权'
    };
    final visibility = <bool>[];
    var creates = 0;
    const host = MethodChannel('xyz.i4o.uni.launcher/navigation');
    const channel = MethodChannel('xyz.i4o.uni.launcher/map/99');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(host, (call) async {
      if (call.method == 'create') {
        creates++;
        return {'id': 99, 'textureId': 99, 'phase': 'ready', 'ready': true};
      }
      return null;
    });
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'visible') visibility.add(call.arguments == true);
      return call.method == 'status'
          ? {'id': 99, 'textureId': 99, 'phase': 'ready', 'ready': true}
          : null;
    });
    addTearDown(() {
      messenger.setMockMethodCallHandler(host, null);
      messenger.setMockMethodCallHandler(channel, null);
    });
    final c = LauncherController(g);
    await c.initialize();
    await t.pumpWidget(LauncherApp(controller: c));
    await t.pumpAndSettle();
    final original = t.state(find.byType(EmbeddedNavigationCard));
    expect(visibility.last, true);
    final dock = t.getRect(find.byKey(const ValueKey('bottom-dock')));
    await c.switchPage(1);
    await t.pumpAndSettle();
    expect(visibility.last, false);
    await c.switchPage(0);
    await t.pumpAndSettle();
    expect(identical(t.state(find.byType(EmbeddedNavigationCard)), original),
        true);
    expect(visibility.last, true);
    expect(t.getRect(find.byKey(const ValueKey('bottom-dock'))), dock);
    c.openSettings();
    await t.pumpAndSettle();
    expect(visibility.last, false,
        reason: 'Settings must not forward input to the live map');
    expect(
        find
            .byType(EmbeddedNavigationCard, skipOffstage: false)
            .evaluate()
            .any((e) => e is StatefulElement && identical(e.state, original)),
        true);
    c.home();
    await t.pumpAndSettle();
    expect(identical(t.state(find.byType(EmbeddedNavigationCard)), original),
        true);
    expect(visibility.last, true);
    await t.tap(find.byKey(const ValueKey('music-info')));
    await t.pumpAndSettle();
    expect(visibility.last, false,
        reason: 'A modal owns input while the map stays composited below');
    await t.tap(find.byTooltip('关闭音乐详情'));
    await t.pumpAndSettle();
    expect(visibility.last, true);
    expect(creates, 1);
    await t.pumpWidget(const SizedBox.shrink());
    c.dispose();
    await g.dispose();
    messenger.setMockMethodCallHandler(channel, null);
    debugDefaultTargetPlatformOverride = null;
    t.view.resetPhysicalSize();
    t.view.resetDevicePixelRatio();
  });
  testWidgets('Fresh vehicle readings appear at correct tire corners',
      (t) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await t.pumpWidget(MaterialApp(
        theme: launcherTheme(SurfaceStyle.from(const Appearance(), true)),
        home: Scaffold(
            body: SizedBox(
                width: 700,
                height: 400,
                child: TireDiagram(native: {
                  'vehicle': {
                    'connected': true,
                    'fields': {
                      'pressureFrontLeft': {
                        'valid': true,
                        'value': 2.41,
                        'unit': 'bar',
                        'updatedAtMs': now
                      },
                      'pressureFrontRight': {
                        'valid': true,
                        'value': 2.42,
                        'unit': 'bar',
                        'updatedAtMs': now
                      },
                      'pressureRearLeft': {
                        'valid': true,
                        'value': 2.43,
                        'unit': 'bar',
                        'updatedAtMs': now
                      },
                      'pressureRearRight': {
                        'valid': true,
                        'value': 2.44,
                        'unit': 'bar',
                        'updatedAtMs': now
                      }
                    }
                  }
                })))));
    await t.pumpAndSettle();
    for (final v in ['2.41', '2.42', '2.43', '2.44']) {
      expect(find.text(v), findsOneWidget);
    }
    expect(find.text('bar'), findsNWidgets(4));
    // The Lynk 05 top view points to the right: left-side wheels are above the
    // vehicle and the front axle is at the right-hand side of the card.
    expect(t.getCenter(find.text('2.43')).dx,
        lessThan(t.getCenter(find.text('2.41')).dx));
    expect(t.getCenter(find.text('2.41')).dy,
        lessThan(t.getCenter(find.text('2.42')).dy));
    expect(find.byKey(const ValueKey('lynk-05-horizontal-vehicle')),
        findsOneWidget);
    final vehicleRect =
        t.getRect(find.byKey(const ValueKey('lynk-05-horizontal-vehicle')));
    for (final field in const [
      'pressureFrontLeft',
      'pressureFrontRight',
      'pressureRearLeft',
      'pressureRearRight'
    ]) {
      final pressureRect =
          t.getRect(find.byKey(ValueKey('tire-pressure-$field')));
      expect(pressureRect.overlaps(vehicleRect), isFalse,
          reason: '$field must remain outside the vehicle artwork');
      expect(pressureRect.center.dx,
          inInclusiveRange(vehicleRect.left, vehicleRect.right),
          reason: '$field stays aligned with its axle');
    }
    final traces = t.widgetList<Image>(find.descendant(
        of: find.byKey(const ValueKey('lynk-05-horizontal-vehicle')),
        matching: find.byType(Image)));
    expect(traces, hasLength(1));
    expect(
        traces.every((image) =>
            (image.image as AssetImage).assetName ==
            'assets/art/lynk-05-top-line.png'),
        isTrue);
    expect(t.takeException(), null);
  });

  testWidgets('Optional door fields render without changing the TPMS contract',
      (t) async {
    const now = 1800000000000;
    final native = <String, dynamic>{
      'vehicle': {
        'connected': true,
        'fields': {
          'doorFrontLeft': {'valid': true, 'value': true, 'updatedAtMs': now},
          'doorFrontRight': {'valid': true, 'value': false, 'updatedAtMs': now},
          'tailgateOpen': {'valid': true, 'value': 'OPEN', 'updatedAtMs': now},
        }
      }
    };
    final doors = VehicleDoorSnapshot.fromNative(native, nowMs: now);
    expect(doors.hasData, isTrue);
    expect(doors.anyOpen, isTrue);
    expect(doors.statusLabel, contains('左前门'));
    expect(doors.statusLabel, contains('尾门'));
    await t.pumpWidget(MaterialApp(
        theme: launcherTheme(SurfaceStyle.from(const Appearance(), true)),
        home: Scaffold(
            body: SizedBox(
                width: 700,
                height: 400,
                child: TireDiagram(native: native, nowMs: now)))));
    await t.pump();
    expect(find.byKey(const ValueKey('vehicle-opening-alert')), findsOneWidget);
    expect(find.text('车门开启'), findsOneWidget);
    expect(t.takeException(), isNull);
  });
}
