import 'dart:async';
import 'dart:math' as math;

import 'package:fake_async/fake_async.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uni_launcher/model/ambient_light.dart';
import 'package:uni_launcher/platform/ambient_light.dart';
import 'package:uni_launcher/platform/audio_spectrum.dart';

/// Switching the motion engine has to **hand the render loops over**.
///
/// The V2/legacy engines publish on the 60 Hz render clock; the rhythm engine
/// publishes from the spectrum callback and, while nothing plays, from a 1 s
/// fallback timer that writes a static colour. A car log showed the failure
/// mode when the hand-over was missing: the strip was turned on while
/// 「节奏」 was selected (so the render clock never started), then the engine
/// was switched to 「新版」 — V2 rendered exactly one frame while the rhythm
/// fallback timer kept overwriting it with its static blue (HSV 210°,
/// value 30 % = `#0B2A4D`), so the light sat on one colour and looked frozen.
class _Sample {
  _Sample(this.r, this.g, this.b);

  final int r;
  final int g;
  final int b;

  bool get isRhythmFallback => r == 11 && g == 44 && b == 77;
}

/// One synthetic frame: a kick in the low end plus some midrange energy.
List<double> musicFrame(double phase) {
  final bands = List<double>.filled(24, 0.05);
  final beat = phase % 1.0;
  final kick = math.exp(-beat * 14);
  for (var i = 0; i < 3; i++) {
    bands[i] = 0.30 + 0.62 * kick;
  }
  bands[4 + (phase * 5).round() % 5] = 0.30;
  bands[10] = 0.18;
  return bands;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<_Sample> stream;
  late AudioSpectrumService spectrum;
  late int now;

  setUp(() {
    stream = <_Sample>[];
    now = 0;
    final methods = MethodChannel('uni.test/engine-switch/ambient');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(methods, (call) async {
      if (call.method == 'color') {
        final args = call.arguments as Map;
        stream.add(_Sample(
          (args['r'] as num).toInt(),
          (args['g'] as num).toInt(),
          (args['b'] as num).toInt(),
        ));
      }
      return null;
    });
    final spectrumMethods =
        const MethodChannel('uni.test/engine-switch/spectrum');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(spectrumMethods, (call) async => null);
    spectrum = AudioSpectrumService(
      methods: spectrumMethods,
      events: const EventChannel('uni.test/engine-switch/events'),
    );
  });

  tearDown(() => spectrum.dispose());

  /// Advances [frames] render frames (16 ms each) and feeds the 10 Hz spectrum.
  void run(fakeAsync, int frames) {
    for (var i = 0; i < frames; i++) {
      if (i % 6 == 0) {
        spectrum.accept({
          'granted': true,
          'available': true,
          'status': 'listening',
          'levels': musicFrame((i / 60) % 4.0),
          'peakLevel': .9,
        });
      }
      now += 16;
      fakeAsync.elapse(const Duration(milliseconds: 16));
    }
  }

  test('节奏 → 新版 restarts the render clock and stops the fallback', () {
    fakeAsync((async) {
      final service = AmbientLightService(
        methods: MethodChannel('uni.test/engine-switch/ambient'),
        spectrum: spectrum,
        clock: () => now,
      );
      addTearDown(service.dispose);

      // Turn the strip on while 「节奏」 is selected: no render clock, but the
      // rhythm fallback timer starts writing the static colour once a second.
      unawaited(service.applySettings(
        const AmbientLightSettings(
          enabled: true,
          engine: AmbientLightSettings.engineRhythm,
        ),
      ));
      async.flushMicrotasks();
      run(async, 120);
      expect(stream, isNotEmpty, reason: 'the rhythm fallback never wrote');

      // Switch to 「新版」 while it is running.
      unawaited(service.applySettings(
        const AmbientLightSettings(
          enabled: true,
          engine: AmbientLightSettings.engineV2,
        ),
      ));
      async.flushMicrotasks();
      stream.clear();

      run(async, 300); // ~4.8 s of music

      expect(stream.length, greaterThan(30),
          reason: 'V2 only rendered once after the engine switch — '
              'the 60 Hz clock was never started');
      expect(stream.where((s) => s.isRhythmFallback), isEmpty,
          reason: 'the rhythm fallback timer kept overwriting V2');
    });
  });

  test('新版 → 节奏 stops the render clock and writes the static colour', () {
    fakeAsync((async) {
      final service = AmbientLightService(
        methods: MethodChannel('uni.test/engine-switch/ambient'),
        spectrum: spectrum,
        clock: () => now,
      );
      addTearDown(service.dispose);

      unawaited(service.applySettings(
        const AmbientLightSettings(enabled: true),
      ));
      async.flushMicrotasks();
      run(async, 120);
      expect(stream, isNotEmpty, reason: 'V2 never wrote');

      unawaited(service.applySettings(
        const AmbientLightSettings(
          enabled: true,
          engine: AmbientLightSettings.engineRhythm,
        ),
      ));
      async.flushMicrotasks();
      stream.clear();

      // Silence: no spectrum frames at all. The rhythm chain must fall back to
      // its static colour; V2's render clock must not keep publishing.
      for (var i = 0; i < 200; i++) {
        now += 16;
        async.elapse(const Duration(milliseconds: 16));
      }

      expect(stream.where((s) => s.isRhythmFallback), isNotEmpty,
          reason: 'the rhythm engine never wrote its static colour');
      expect(service.settings.engine, AmbientLightSettings.engineRhythm);
    });
  });
}
