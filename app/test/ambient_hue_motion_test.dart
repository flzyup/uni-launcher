import 'dart:math' as math;

import 'package:fake_async/fake_async.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uni_launcher/model/ambient_light.dart';
import 'package:uni_launcher/platform/ambient_light.dart';
import 'package:uni_launcher/platform/audio_spectrum.dart';

/// Diagnostic: does the V2 **hue** follow the music, or only the brightness?
///
/// The complaint was "the strip keeps one base colour and only the
/// brightness moves". The lightness is a different statistic than the hue,
/// so a test that only watches the brightness would pass even when the hue
/// is stuck. This one watches the hue.
///
/// The spectrum is fed directly (the perception layer, the motion layer and
/// the Delta E00 limiter all run for real), and the colour that reaches the
/// platform channel is the colour the head unit would get.
///
/// ## Why the clock is injected
///
/// The chain is time based: the perception layer has a 2 s reference, the
/// motion layer integrates at 60 Hz. A test that waits on the **wall clock**
/// therefore measures the machine's load as much as it measures the engine:
/// under a full test suite the timers do not fire often enough and the
/// colour travels less than it should.
///
/// So the clock is injected and the timers are driven by
/// [FakeAsync]. Every frame happens at exactly the same moments on every
/// machine, and the numbers below are reproducible.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<MethodCall> calls;
  late AudioSpectrumService spectrum;

  setUp(() {
    calls = [];
    final methods = MethodChannel('uni.test/ambient');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(methods, (call) async {
      calls.add(call);
      return null;
    });
    final spectrumMethods = const MethodChannel('uni.test/spectrum');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(spectrumMethods, (call) async {
      return null;
    });
    spectrum = AudioSpectrumService(
        methods: spectrumMethods, events: const EventChannel('uni.test/events'));
  });

  tearDown(() {
    spectrum.dispose();
  });

  /// The hue of a colour in degrees.
  double hueOf(Map arguments) {
    final r = (arguments['r'] as num).toDouble();
    final g = (arguments['g'] as num).toDouble();
    final b = (arguments['b'] as num).toDouble();
    final max = math.max(r, math.max(g, b));
    final min = math.min(r, math.min(g, b));
    final delta = max - min;
    if (delta < 1) return -1;
    double h;
    if (max == r) {
      h = 60 * (((g - b) / delta) % 6);
    } else if (max == g) {
      h = 60 * (((b - r) / delta) + 2);
    } else {
      h = 60 * (((r - g) / delta) + 4);
    }
    return (h + 360) % 360;
  }

  /// One spectrum frame: the energy sits either in the bass (a kick) or in
  /// the lower midrange (a voice). That moves the **low centroid**, which is
  /// what the "follow the bass" mode turns into a hue.
  List<double> frame({required bool kick}) {
    final bands = List<double>.filled(24, 0.35);
    for (var i = 0; i < 3; i++) {
      bands[i] = kick ? 0.9 : 0.45;
    }
    for (var i = 3; i < 8; i++) {
      bands[i] = kick ? 0.45 : 0.8;
    }
    return bands;
  }

  test('the V2 hue follows the music, not only the brightness', () {
    fakeAsync((async) {
      // The service reads the time from this clock, so every frame sees the
      // same elapsed time on every machine.
      var now = 0;
      final service = AmbientLightService(
          methods: MethodChannel('uni.test/ambient'),
          spectrum: spectrum,
          clock: () => now);
      addTearDown(service.dispose);

      service.applySettings(const AmbientLightSettings(enabled: true));
      async.flushMicrotasks();

      /// Advances the fake clock and lets the render timer run.
      void step(int ms) {
        now += ms;
        async.elapse(Duration(milliseconds: ms));
      }

      // Phase 1: a steady signal, so the perception layer can settle its
      // per band reference (tau = 2 s). Without this the relative levels are
      // still chasing the average and the centroid is meaningless.
      for (var i = 0; i < 30; i++) {
        spectrum.accept({
          'granted': true,
          'available': true,
          'status': 'listening',
          'levels': frame(kick: true),
          'peakLevel': .9,
        });
        step(100);
      }

      // Phase 2: alternate. Only the colours from here on are measured.
      final hues = <double>[];
      final brightness = <int>[];
      for (var i = 0; i < 30; i++) {
        calls.clear();
        spectrum.accept({
          'granted': true,
          'available': true,
          'status': 'listening',
          'levels': frame(kick: i.isEven),
          'peakLevel': .9,
        });
        step(100);
        final colors =
            calls.where((c) => c.method == 'color').map((c) => c.arguments);
        for (final arguments in colors) {
          final hue = hueOf(arguments as Map);
          if (hue >= 0) hues.add(hue);
        }
        final current = service.color.value;
        if (current != null) brightness.add(current.brightness);
      }

      // ignore the wrap at 0 degrees
      final sorted = [...hues]..sort();
      final spread = sorted.isEmpty ? 0.0 : sorted.last - sorted.first;
      final minBrightness =
          brightness.isEmpty ? 0 : brightness.reduce(math.min);
      final maxBrightness =
          brightness.isEmpty ? 0 : brightness.reduce(math.max);

      // ignore the label: the numbers are what matters here
      // ignore: avoid_print
      print('hue samples: ${hues.length}, spread: ${spread.toStringAsFixed(1)} deg');
      // ignore: avoid_print
      print('brightness: $minBrightness..$maxBrightness');

      expect(hues, isNotEmpty, reason: 'no colour reached the channel');
      expect(spread,
          greaterThan(10.0),
          reason: 'the hue only moved $spread degrees — it is stuck');
    });
  });
}
