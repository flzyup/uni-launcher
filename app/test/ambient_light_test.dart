import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uni_launcher/model/ambient_color_space.dart';
import 'package:uni_launcher/model/ambient_light.dart';
import 'package:uni_launcher/platform/ambient_light.dart';
import 'package:uni_launcher/platform/audio_spectrum.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const methods = MethodChannel('test/ambient-light');
  const spectrumMethods = MethodChannel('test/spectrum-control');
  const spectrumEvents = EventChannel('test/spectrum-events');
  final calls = <MethodCall>[];
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  setUp(() {
    calls.clear();
    messenger.setMockMethodCallHandler(methods, (call) async {
      calls.add(call);
      if (call.method == 'status') {
        return {'available': false, 'reason': '此设备没有原车氛围灯接口'};
      }
      return null;
    });
    messenger.setMockMethodCallHandler(spectrumMethods, (call) async {
      calls.add(call);
      if (call.method == 'status') {
        return {
          'granted': true,
          'available': true,
          'status': 'listening',
          'levels': List.filled(24, .3)
        };
      }
      return null;
    });
    messenger.setMockMethodCallHandler(MethodChannel(spectrumEvents.name),
        (call) async {
      calls.add(call);
      return null;
    });
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(methods, null);
    messenger.setMockMethodCallHandler(spectrumMethods, null);
    messenger.setMockMethodCallHandler(MethodChannel(spectrumEvents.name), null);
  });

  group('AmbientPalette', () {
    test('bass energy only reads the lowest bands', () {
      expect(AmbientPalette.bassEnergy([.2, .4, .9, .8, .95]), .9,
          reason: 'the fifth band is above the bass range');
      expect(AmbientPalette.bassEnergy([]), 0);
    });

    test('bass hue follows the loudest low band', () {
      final bands = List<double>.filled(24, 0);
      bands[2] = .8;
      expect(AmbientPalette.bassHue(bands, 0), closeTo(30, .001));
    });

    test('a silent frame keeps the previous hue', () {
      expect(AmbientPalette.bassHue(List.filled(24, 0), 123), closeTo(123, .001));
      expect(AmbientPalette.spectrumHue(List.filled(24, 0), 123),
          closeTo(123, .001));
    });

    test('the spectrum hue is a circular mean, not an arithmetic one', () {
      // Two bands on either side of zero must not average out to 180.
      final bands = List<double>.filled(24, 0);
      bands[0] = 1;
      bands[23] = 1;
      final hue = AmbientPalette.spectrumHue(bands, 0);
      expect(hue > 330 || hue < 30, isTrue,
          reason: 'wrapping hues must stay near zero, got $hue');
    });

    test('the spectrum hue is weighted by energy', () {
      final bands = List<double>.filled(24, 0);
      bands[0] = 1;
      bands[12] = .5;
      final hue = AmbientPalette.spectrumHue(bands, 0);
      expect(hue, closeTo(AmbientPalette.hueForBand(0, 24), 40));
    });

    test('brightness honours the bounds and the curve', () {
      expect(AmbientPalette.brightnessFor(0, 1, 20, 80), 20);
      expect(AmbientPalette.brightnessFor(1, 1, 20, 80), 80);
      expect(AmbientPalette.brightnessFor(.5, 1, 20, 80), 50);
      // A higher sensitivity lifts the quiet parts.
      expect(AmbientPalette.brightnessFor(.2, 2, 0, 100),
          greaterThan(AmbientPalette.brightnessFor(.2, .5, 0, 100)));
      // A degenerate range never leaves the bounds.
      expect(AmbientPalette.brightnessFor(.7, 1, 60, 60), 60);
      expect(AmbientPalette.brightnessFor(.7, 1, 80, 20), 80);
    });

    test('the fixed mode keeps the configured hue', () {
      final color = AmbientPalette.colorFrom(
        bands: List.filled(24, .5),
        level: .8,
        mode: AmbientPalette.modeFixed,
        fixedHue: 210,
        sensitivity: 1,
        minBrightness: 0,
        maxBrightness: 100,
      );
      expect(AmbientPalette.hueForBand(0, 1), 0);
      final rgb = AmbientPalette.hsvToRgb(210, .85, 1);
      expect(color.r, rgb[0]);
      expect(color.g, rgb[1]);
      expect(color.b, rgb[2]);
      expect(color.brightness, 80);
    });

    test('the colour is packed as 0xRRGGBB', () {
      const color = AmbientColor(0x12, 0x34, 0x56, 40);
      expect(color.packed, 0x123456);
      expect(color.hex, '#123456');
    });

    test('the colour distance grows with the difference', () {
      const a = AmbientColor(0, 0, 0, 0);
      const b = AmbientColor(3, 4, 0, 0);
      expect(AmbientPalette.colorDistance(a, b), 5);
      expect(AmbientPalette.colorDistance(a, a), 0);
    });

    test('the colour is scaled by its brightness', () {
      const loud = AmbientColor(200, 100, 50, 100);
      final scaled = AmbientPalette.scaleByBrightness(loud);
      expect(scaled.r, 200);
      expect(scaled.g, 100);
      expect(scaled.b, 50);
      expect(scaled.brightness, 100);

      const half = AmbientColor(200, 100, 50, 50);
      final dim = AmbientPalette.scaleByBrightness(half);
      expect(dim.r, 100);
      expect(dim.g, 50);
      expect(dim.b, 25);
      // The brightness itself is not changed by the scaling.
      expect(dim.brightness, 50);
    });

    test('the scaled colour keeps the hue', () {
      final bands = List<double>.filled(24, .02);
      for (var i = 4; i < 8; i++) {
        bands[i] = .9;
      }
      final computed = AmbientPalette.colorFrom(
        bands: bands,
        level: .9,
        mode: AmbientPalette.modeBass,
        fixedHue: 210,
        sensitivity: 1.4,
        minBrightness: 15,
        maxBrightness: 100,
      );
      final scaled = AmbientPalette.scaleByBrightness(computed);
      expect(scaled.brightness, computed.brightness);
      // The hue survives the scaling: the channels keep their ratio.
      expect(scaled.g / scaled.r, closeTo(computed.g / computed.r, .02));
    });
  });

  group('AmbientLightSettings', () {
    test('round trips through json', () {
      const settings = AmbientLightSettings(
          enabled: true,
          mode: AmbientPalette.modeFixed,
          fixedHue: 330,
          sensitivity: 2.2,
          minBrightness: 10,
          maxBrightness: 90);
      final restored =
          AmbientLightSettings.fromJson(settings.toJson());
      expect(restored, settings);
    });

    test('out of range values are clamped', () {
      final settings = AmbientLightSettings.fromJson({
        'mode': 9,
        'fixedHue': 400,
        'sensitivity': 99,
        'minBrightness': -5,
        'maxBrightness': 500,
      });
      expect(settings.mode, AmbientPalette.modeBass);
      expect(settings.fixedHue, closeTo(40, .001));
      expect(settings.sensitivity, AmbientPalette.maxSensitivity);
      expect(settings.minBrightness, 0);
      expect(settings.maxBrightness, 100);
    });

    test('a missing payload keeps the defaults', () {
      expect(AmbientLightSettings.fromJson(null),
          const AmbientLightSettings());
    });

    test('the rhythm regions round trip through json', () {
      const settings = AmbientLightSettings(
          modeConfigured: true,
          bassHue: 20,
          bassCustom: '#20b2aa',
          midHue: 130,
          midCustom: '#87ceeb',
          trebleHue: 260,
          trebleCustom: '#ffb6c1',
          beatLeadMs: 180);
      final restored =
          AmbientLightSettings.fromJson(settings.toJson());
      expect(restored, settings);
      expect(restored.bassHue, closeTo(20, .001));
      expect(restored.bassCustom, '#20b2aa');
      expect(restored.beatLeadMs, 180);
    });

    test('the rhythm regions are clamped and validated', () {
      final settings = AmbientLightSettings.fromJson({
        'bassHue': 500,
        'bassCustom': 'invalid',
        'midCustom': '#87CEEB',
        'trebleCustom': '#nope',
        'beatLeadMs': 300,
      });
      expect(settings.bassHue, closeTo(140, .001));
      expect(settings.bassCustom, isEmpty);
      expect(settings.midCustom, '#87ceeb');
      expect(settings.trebleCustom, isEmpty);
      expect(settings.beatLeadMs, 250);
      // 默认值不因合并改变：仍是「跟随低频」，旧负载不迁移。
      expect(const AmbientLightSettings().mode, AmbientPalette.modeBass);
      expect(AmbientLightSettings.fromJson({'mode': 0}).mode,
          AmbientPalette.modeBass);
    });
  });

  group('AmbientLightService', () {
    late AudioSpectrumService spectrum;
    late AmbientLightService service;

    setUp(() {
      spectrum = AudioSpectrumService(
          methods: spectrumMethods, events: spectrumEvents);
      service = AmbientLightService(methods: methods, spectrum: spectrum);
    });

    tearDown(() {
      service.dispose();
      spectrum.dispose();
    });

    test('the capability of the head unit channel is reported', () async {
      await service.refreshStatus();
      expect(service.channelAvailable, isFalse);
      expect(service.reason, '此设备没有原车氛围灯接口');
    });

    test('switching on starts the capture and the strip', () async {
      await service.applySettings(const AmbientLightSettings(enabled: true));
      expect(spectrum.activeConsumers, 1);
      expect(calls.where((c) => c.method == 'enable').map((c) => c.arguments),
          [true]);
    });

    test('switching off stops the capture and the strip', () async {
      await service.applySettings(const AmbientLightSettings(enabled: true));
      calls.clear();
      await service.applySettings(const AmbientLightSettings(enabled: false));
      expect(spectrum.activeConsumers, 0);
      expect(calls.where((c) => c.method == 'enable').map((c) => c.arguments),
          [false]);
    });

    test('a spectrum frame becomes colour writes', () async {
      await service.applySettings(const AmbientLightSettings(enabled: true));
      calls.clear();
      spectrum.accept({
        'granted': true,
        'available': true,
        'status': 'listening',
        'levels': List.filled(24, .5),
        'peakLevel': .5,
      });
      // The V2 engine renders on its own 60 Hz clock: a spectrum frame only
      // moves the **targets**, the colour itself is written by the next
      // render tick. A single microtask is not enough to see it.
      await Future<void>.delayed(const Duration(milliseconds: 80));
      final colors =
          calls.where((c) => c.method == 'color').map((c) => c.arguments);
      expect(colors, isNotEmpty);
      final arguments = colors.first as Map;
      expect(arguments['r'], isA<int>());
      expect(arguments['g'], isA<int>());
      expect(arguments['b'], isA<int>());
      // The head unit brightness is the user's absolute value, so it is not
      // written again on every frame.
      expect(calls.where((c) => c.method == 'brightness'), isEmpty);
      expect(service.color.value, isNotNull);
      expect(service.spectrumReady, isTrue);
    });

    test('the absolute brightness is written once when the strip is switched on',
        () async {
      await service.applySettings(const AmbientLightSettings(enabled: true));
      final brightness =
          calls.where((c) => c.method == 'brightness').map((c) => c.arguments);
      expect(brightness, [100]);
      // A new absolute brightness is written again.
      calls.clear();
      await service.applySettings(
          const AmbientLightSettings(enabled: true, vehicleBrightness: 40));
      expect(
          calls.where((c) => c.method == 'brightness').map((c) => c.arguments),
          [40]);
    });

    test('no colour is written while the ambience is off', () async {
      calls.clear();
      spectrum.accept({
        'granted': true,
        'available': true,
        'status': 'listening',
        'levels': List.filled(24, .5),
      });
      await Future<void>.delayed(Duration.zero);
      expect(calls.where((c) => c.method == 'color'), isEmpty);
      expect(service.color.value, isNull);
    });

    test('unchanged settings are not written again', () async {
      await service.applySettings(const AmbientLightSettings(enabled: true));
      calls.clear();
      await service.applySettings(const AmbientLightSettings(enabled: true));
      expect(calls.where((c) => c.method == 'enable'), isEmpty);
      expect(calls.where((c) => c.method == 'color'), isEmpty);
    });

    test('the adjacent frames stay inside the shared colour budget', () async {
      // ## What this guards
      //
      // The render clock runs at 60 Hz, the write cadence is 50 ms. If both
      // layers used the **same** budget, the candidate would run twice as
      // fast as the writes could follow, and the difference between the
      // written colour and the real colour would pile up frame after frame.
      //
      // So the render budget is the total budget divided by the number of
      // render frames per write window:
      // `maxDeltaE * renderIntervalMs / writeIntervalMs`.
      const maxDeltaE = 0.4;
      await service.applySettings(
          const AmbientLightSettings(enabled: true, maxDeltaE: maxDeltaE));
      calls.clear();
      // A pulsing spectrum — a constant one would settle and the limiter
      // would never have anything to do.
      for (var i = 0; i < 12; i++) {
        spectrum.accept({
          'granted': true,
          'available': true,
          'status': 'listening',
          'levels': List.filled(24, i.isEven ? .9 : .1),
          'peakLevel': i.isEven ? .9 : .1,
        });
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
      final colors = calls
          .where((c) => c.method == 'color')
          .map((c) => c.arguments as Map)
          .toList();
      expect(colors.length, greaterThan(5));
      final cap = maxDeltaE *
          AmbientLightService.renderIntervalMs /
          AmbientLightService.writeIntervalMs;
      var prev = AmbientColorSpace.rgbToLab(
          colors.first['r'] as int,
          colors.first['g'] as int,
          colors.first['b'] as int);
      for (final color in colors.skip(1)) {
        final lab = AmbientColorSpace.rgbToLab(
            color['r'] as int, color['g'] as int, color['b'] as int);
        final de = AmbientColorSpace.deltaE00(prev, lab);
        expect(de, lessThanOrEqualTo(cap + 0.05),
            reason: 'two adjacent frames differ by $de, over the cap $cap');
        prev = lab;
      }
    });

    test('the legacy chain is not rate limited', () async {
      // ## What this guards
      //
      // The legacy chain is the production look that was verified on the
      // car: 10 Hz hard jumps. The Delta E00 limiter is a V2 thing — putting
      // it on the legacy chain as well would flatten it into a slow ramp
      // and make the "old vs new" comparison meaningless.
      await service.applySettings(const AmbientLightSettings(
          enabled: true,
          engine: AmbientLightSettings.engineLegacy,
          maxDeltaE: 0.2));
      calls.clear();
      // Alternate the spectrum so the legacy chain really jumps.
      for (var i = 0; i < 6; i++) {
        final bands = List<double>.filled(24, 0.1);
        bands[i.isEven ? 1 : 3] = 0.95;
        spectrum.accept({
          'granted': true,
          'available': true,
          'status': 'listening',
          'levels': bands,
          'peakLevel': 0.95,
        });
        await Future<void>.delayed(const Duration(milliseconds: 120));
      }
      final colors = calls
          .where((c) => c.method == 'color')
          .map((c) => c.arguments as Map)
          .toList();
      expect(colors.length, greaterThan(2));
      // The limiter would have held every step at 0.1 Delta E00.
      final first = AmbientColorSpace.rgbToLab(
          colors.first['r'] as int,
          colors.first['g'] as int,
          colors.first['b'] as int);
      final second = AmbientColorSpace.rgbToLab(
          colors[1]['r'] as int, colors[1]['g'] as int, colors[1]['b'] as int);
      final de = AmbientColorSpace.deltaE00(first, second);
      expect(de, greaterThan(1.0),
          reason: 'the legacy chain must keep its jumps, got $de');
    });

    test('a native state push updates the capability and the reason',
        () async {
      var notified = 0;
      service.addListener(() => notified++);
      await service.handleNativeCall(MethodCall('state', {
        'available': true,
        'reason': '',
        'switchApplied': true,
        'unresolved': ['SETTING_FUNC_AMBIENCE_LIGHT_COLOR_SET'],
        'lastWrite': {'ok': true},
      }));
      expect(service.channelAvailable, isTrue);
      expect(service.reason, isEmpty);
      expect(service.switchApplied, isTrue);
      expect(service.unresolved, ['SETTING_FUNC_AMBIENCE_LIGHT_COLOR_SET']);
      expect(notified, greaterThan(0));
    });

    test('the reason of a failed write reaches the settings page', () async {
      messenger.setMockMethodCallHandler(methods, (call) async {
        calls.add(call);
        if (call.method == 'status') {
          return {
            'available': true,
            'reason': '氛围灯颜色功能号按名解析不到',
            'switchApplied': false,
            'unresolved': ['SETTING_FUNC_AMBIENCE_LIGHT_COLOR_SET'],
          };
        }
        return null;
      });
      await service.refreshStatus();
      expect(service.channelAvailable, isTrue);
      expect(service.reason, '氛围灯颜色功能号按名解析不到');
      expect(service.switchApplied, isFalse);
    });
  });
}
