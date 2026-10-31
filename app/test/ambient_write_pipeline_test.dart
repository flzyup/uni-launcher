import 'dart:math' as math;

import 'package:fake_async/fake_async.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uni_launcher/model/ambient_color_space.dart';
import 'package:uni_launcher/model/ambient_light.dart';
import 'package:uni_launcher/model/ambient_motion.dart';
import 'package:uni_launcher/model/spectrum_perception.dart';
import 'package:uni_launcher/platform/ambient_light.dart';
import 'package:uni_launcher/platform/audio_spectrum.dart';

/// Diagnostic: does the **write path** make the colour on the car drift away
/// from the colour the engine computed?
///
/// The complaint was: "the strip keeps one base colour and only the
/// brightness moves" — and the suspicion was a **Delta E00 limiter that pulls
/// the colour back**, so the write layer and the render layer disagree and
/// the difference piles up frame after frame.
///
/// This test walks the **real** chain (perception → motion → OKLCH palette →
/// Delta E00 limiter → platform channel) and then replays the resulting
/// 60 Hz stream through the two write rules that exist in the product:
///
/// | | limiter | base | budget |
/// | --- | --- | --- | --- |
/// | `AmbientLightWriter` (uni) | none — a pure pipe | — | — |
/// | `AdaptapiAmbientLightApi` (cardesk) | Delta E00 pull back | the last **written** colour | the full `maxDeltaE` |
///
/// and answers three questions with numbers instead of opinions:
///
/// 1. does the render layer really cap **every frame** at `maxDeltaE × 16/50`?
/// 2. does the colour that reaches the car stay in step with the engine?
/// 3. does the gap between "written" and "engine" **grow** over time?
///
/// ## Why the clock is injected
///
/// Same reason as [ambient_hue_motion_test]: the chain is time based, and a
/// test that waits on the wall clock measures the machine's load as much as
/// the engine. Here the clock is injected **and** the render timer is driven
/// in 16 ms steps, so every frame sees the same `dt` on every machine.
class _Sample {
  _Sample(this.tMs, this.r, this.g, this.b);

  final int tMs;
  final int r;
  final int g;
  final int b;
}

/// One synthetic music frame: a kick in the low end, a melody that walks
/// through the lower midrange and cymbals on the off beat.
List<double> musicFrame(double phase) {
  final bands = List<double>.filled(24, 0.06);
  final beat = phase % 1.0;
  final kick = math.exp(-beat * 14);
  for (var i = 0; i < 3; i++) {
    bands[i] = 0.35 + 0.62 * kick;
  }
  final melodyBand = 3 + (phase * 6).round() % 8;
  bands[melodyBand] = 0.80;
  if (melodyBand + 1 < 24) bands[melodyBand + 1] = 0.55;
  final off = (phase + 0.5) % 1.0;
  final cymbal = math.exp(-off * 20);
  for (var i = 16; i < 24; i++) {
    bands[i] = 0.10 + 0.55 * cymbal;
  }
  return bands;
}

double deltaE(int r1, int g1, int b1, int r2, int g2, int b2) =>
    AmbientColorSpace.deltaE00(
      AmbientColorSpace.rgbToLab(r1, g1, b1),
      AmbientColorSpace.rgbToLab(r2, g2, b2),
    );

/// The RGB euclidean distance — the metric both write layers gate on.
int rgbDistance(_Sample a, _Sample b) {
  final dr = a.r - b.r;
  final dg = a.g - b.g;
  final db = a.b - b.b;
  return math.sqrt((dr * dr + dg * dg + db * db).toDouble()).floor();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<_Sample> stream;
  late AudioSpectrumService spectrum;
  late int now;

  setUp(() {
    stream = <_Sample>[];
    now = 0;
    final methods = MethodChannel('uni.test/ambient');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(methods, (call) async {
      if (call.method == 'color') {
        final args = call.arguments as Map;
        stream.add(_Sample(
          now,
          (args['r'] as num).toInt(),
          (args['g'] as num).toInt(),
          (args['b'] as num).toInt(),
        ));
      }
      return null;
    });
    final spectrumMethods = const MethodChannel('uni.test/spectrum');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(spectrumMethods, (call) async => null);
    spectrum = AudioSpectrumService(
        methods: spectrumMethods, events: const EventChannel('uni.test/events'));
  });

  tearDown(() {
    spectrum.dispose();
  });

  test('the write path keeps the car in step with the engine', () {
    fakeAsync((async) {
      final service = AmbientLightService(
        methods: MethodChannel('uni.test/ambient'),
        spectrum: spectrum,
        clock: () => now,
      );
      addTearDown(service.dispose);
      service.applySettings(const AmbientLightSettings(enabled: true));
      async.flushMicrotasks();

      /// A second copy of the engine chain, run **in parallel** with the
      /// service: the same perception layer, the same motion layer, the same
      /// palette. It produces the colour **before** the Delta E00 limiter,
      /// which is what tells us whether the limiter is the thing that holds
      /// the colour back (it should be: the cap is 0.576 dE per frame).
      final perception = SpectrumPerception();
      final motion = AmbientMotion();
      var motionState = const AmbientMotionState();
      var engineHue = 0.0;
      var engineLevel = 0.0;
      var engineChroma = 0.0;
      var engineBass = 0.0;
      var engineSilent = false;
      final engineSteps = <double>[];
      AmbientColor? lastEngine;

      /// Advances one render frame (16 ms) and lets the timer fire.
      void frame() {
        now += 16;
        async.elapse(const Duration(milliseconds: 16));
        motionState = motion.step(
          prev: motionState,
          targetHue: engineHue,
          targetLevel: engineLevel,
          targetChroma: engineChroma,
          bass: engineBass,
          dtMs: 16,
          nowMs: now,
          silent: engineSilent,
        );
        final engineColor = AmbientPalette.colorOfOklch(
          motionState.hue,
          AmbientPalette.perceptualLightness(motionState.level),
          motionState.chroma,
        );
        final previous = lastEngine;
        if (previous != null) {
          engineSteps.add(deltaE(
            previous.r, previous.g, previous.b,
            engineColor.r, engineColor.g, engineColor.b,
          ));
        }
        lastEngine = engineColor;
      }

      /// The spectrum is 10 Hz: one packet every six render frames.
      void spectrumFrame(int index) {
        final bands = musicFrame((index / 60) % 4.0);
        spectrum.accept({
          'granted': true,
          'available': true,
          'status': 'listening',
          'levels': bands,
          'peakLevel': .95,
        });
        final perceived = perception.process(bands, 100);
        engineHue = AmbientPalette.lowCentroidHue(perceived, motionState.hue);
        engineLevel = AmbientPalette.levelFromRelative(
          relative: perception.relativeLevel,
          sensitivity: 1.4,
          floorPercent: 8,
        );
        engineChroma = AmbientPalette.chromaTarget(perceived, 0.8);
        engineBass = AmbientPalette.bassEnergy(perceived);
        engineSilent = perception.relativeLevel < 0.02;
      }

      // Phase 1: a steady signal so the perception layer can settle its
      // per band reference (tau = 2 s). Without it the relative levels are
      // still chasing the average and the centroid means nothing.
      for (var i = 0; i < 120; i++) {
        if (i % 6 == 0) spectrumFrame(i);
        frame();
      }
      stream.clear();

      // Phase 2: ten seconds of music, measured.
      for (var i = 0; i < 600; i++) {
        if (i % 6 == 0) spectrumFrame(i + 120);
        frame();
      }
      final frames = List<_Sample>.from(stream);
      expect(frames.length, greaterThan(400),
          reason: 'only ${frames.length} render frames reached the channel');

      // ---- 1. the render layer limiter ----
      const maxDeltaE = 1.8;
      const cap = maxDeltaE * 16 / 50;
      final perFrame = <double>[];
      for (var i = 1; i < frames.length; i++) {
        perFrame.add(deltaE(
          frames[i - 1].r, frames[i - 1].g, frames[i - 1].b,
          frames[i].r, frames[i].g, frames[i].b,
        ));
      }
      final maxPerFrame = perFrame.reduce(math.max);
      final overCap = perFrame.where((d) => d > cap + 0.02).length;

      // The frames that went over the cap, with what the limiter itself
      // would say about the same pair. If the limiter returns the candidate
      // unchanged, it never saw a step that big.
      var printed = 0;
      for (var i = 1; i < frames.length && printed < 3; i++) {
        final d = perFrame[i - 1];
        if (d <= cap + 0.02) continue;
        printed++;
        final a = frames[i - 1];
        final b = frames[i];
        final limited = AmbientColorSpace.limitByDeltaE(
          a.r, a.g, a.b,
          b.r, b.g, b.b,
          cap,
        );
        // ignore: avoid_print
        print('over cap #$i: ${a.r},${a.g},${a.b} -> ${b.r},${b.g},${b.b} '
            'dE ${d.toStringAsFixed(3)} '
            'limiter says ${limited.$1},${limited.$2},${limited.$3} '
            '${limited.$1 == b.r && limited.$2 == b.g && limited.$3 == b.b ? "(unchanged)" : "(changed)"}');
      }

      // ---- 2. what the car actually gets ----
      //
      // uni: `AmbientLightWriter` is a pure pipe — a 50 ms window and a
      // "did it change at all" gate (RGB distance < 2). The colour itself is
      // never modified.
      final carWrites = <_Sample>[];
      int? lastWriteT;
      _Sample? lastWritten;
      for (final s in frames) {
        if (lastWriteT != null && s.tMs - lastWriteT < 50) continue;
        if (lastWritten != null && rgbDistance(lastWritten, s) < 2) continue;
        lastWriteT = s.tMs;
        lastWritten = s;
        carWrites.add(s);
      }

      // The staleness of the colour on the car: how long the strip shows an
      // older colour than the engine has already produced.
      var maxStale = 0;
      for (final w in carWrites) {
        final next = carWrites
            .where((c) => c.tMs > w.tMs)
            .cast<_Sample?>()
            .firstWhere((c) => true, orElse: () => null);
        if (next != null && next.tMs - w.tMs > maxStale) {
          maxStale = next.tMs - w.tMs;
        }
      }

      // ---- 3. cardesk's write layer on the same stream ----
      //
      // The write layer pulls the candidate back towards the **last written**
      // colour with the **full** budget. If the render layer is not really
      // capped, this pulls every frame back and the difference piles up.
      final written = <_Sample>[];
      int? lastWriteT2;
      _Sample? lastWritten2;
      final gaps = <double>[];
      for (final s in frames) {
        if (lastWriteT2 != null && s.tMs - lastWriteT2 < 50) continue;
        var target = s;
        if (lastWritten2 != null) {
          final (r, g, b) = AmbientColorSpace.limitByDeltaE(
            lastWritten2.r, lastWritten2.g, lastWritten2.b,
            s.r, s.g, s.b,
            maxDeltaE,
          );
          target = _Sample(s.tMs, r, g, b);
        }
        if (lastWritten2 != null && rgbDistance(lastWritten2, target) < 2) {
          continue;
        }
        lastWriteT2 = s.tMs;
        lastWritten2 = target;
        written.add(target);
        // How far the colour that lands on the car is from the colour the
        // engine has at that moment. This is the "the car drifts away from
        // the music" number.
        gaps.add(deltaE(
          target.r, target.g, target.b,
          s.r, s.g, s.b,
        ));
      }

      final gapFirst = gaps.take(gaps.length ~/ 3).fold(0.0, math.max);
      final gapLast = gaps.skip(gaps.length * 2 ~/ 3).fold(0.0, math.max);
      final gapMax = gaps.fold(0.0, math.max);

      // ignore: avoid_print
      print('render frames: ${frames.length}');
      // ignore: avoid_print
      print('per-frame dE: max ${maxPerFrame.toStringAsFixed(3)} '
          '(cap ${cap.toStringAsFixed(3)}), over cap: $overCap');
      final sortedEngine = [...engineSteps]..sort();
      // ignore: avoid_print
      print('engine step per frame: median '
          '${sortedEngine[sortedEngine.length ~/ 2].toStringAsFixed(3)}, '
          'max ${sortedEngine.last.toStringAsFixed(3)}');
      // ignore: avoid_print
      print('car writes (uni pipe): ${carWrites.length}, max staleness ${maxStale}ms');
      // ignore: avoid_print
      print('cardesk write layer: ${written.length} writes, '
          'gap first third ${gapFirst.toStringAsFixed(2)}, '
          'last third ${gapLast.toStringAsFixed(2)}, max ${gapMax.toStringAsFixed(2)}');

      // The render layer has to cap **every** frame, otherwise the write
      // layer on the car has to pull it back — and then the two disagree.
      //
      // The tolerance is one **8 bit RGB step**: at these dark blues a
      // single step of the colour grid is already worth ~0.63 dE, which is
      // more than the 0.576 cap. The limiter interpolates in OKLab and then
      // rounds to 8 bit, so a frame can overshoot the cap by that much —
      // it cannot be smaller, the grid does not offer a smaller step.
      expect(maxPerFrame, lessThanOrEqualTo(cap + 0.25),
          reason: 'a render frame moved $maxPerFrame dE, the cap is $cap');
      expect(overCap, lessThan(perFrame.length ~/ 10),
          reason: '$overCap frames went over the cap — the limiter is not working');

      // The gap between the written colour and the engine's colour must not
      // grow: that is the difference between "the strip lags a frame" and
      // "the strip has nothing to do with the music any more".
      expect(gapLast, lessThan(gapFirst + 0.5),
          reason: 'the written colour drifts further away over time '
              '($gapFirst → $gapLast)');
      // The bound: the write layer pulls the colour back to about half of
      // its budget, and the dead zone can let one write window pass, so the
      // colour on the car may be a couple of windows behind the engine —
      // but never more, and never by more as time goes by.
      expect(gapMax, lessThan(maxDeltaE * 3),
          reason: 'the written colour is $gapMax dE away from the engine');
    });
  });
}
