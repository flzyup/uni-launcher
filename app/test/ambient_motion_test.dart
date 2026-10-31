import 'package:flutter_test/flutter_test.dart';
import 'package:uni_launcher/model/ambient_light.dart';
import 'package:uni_launcher/model/ambient_motion.dart';

/// The motion layer and the low frequency fallback.
///
/// These are pure functions, so the whole curve is covered without a device
/// or a running FFT.
void main() {
  group('AmbientMotion', () {
    const motion = AmbientMotion();

    test('the first frame lands on the target', () {
      final state = motion.step(
        prev: const AmbientMotionState(),
        targetHue: 210,
        targetLevel: 80,
        bass: 0,
        dtMs: 100,
      );
      expect(state.initialized, isTrue);
      expect(state.hue, closeTo(210, .001));
    });

    test('the hue moves towards the target instead of jumping', () {
      var state = motion.step(
        prev: const AmbientMotionState(),
        targetHue: 0,
        targetLevel: 50,
        bass: 0,
        dtMs: 100,
      );
      state = motion.step(
        prev: state,
        targetHue: 180,
        targetLevel: 50,
        bass: 0,
        dtMs: 100,
      );
      // One frame at 100 ms with a 320 ms time constant moves a long way
      // towards the target, but it does not arrive there.
      expect(state.hue, greaterThan(0));
      expect(state.hue, lessThan(180));
    });

    test('the hue speed is limited', () {
      var state = motion.step(
        prev: const AmbientMotionState(),
        targetHue: 0,
        targetLevel: 50,
        bass: 0,
        dtMs: 100,
      );
      state = motion.step(
        prev: state,
        targetHue: 180,
        targetLevel: 50,
        bass: 0,
        dtMs: 100,
      );
      // 90 degrees per second is 9 degrees per 100 ms frame.
      expect(state.hue - 0, lessThanOrEqualTo(9.001));
    });

    test('the hue takes the short way round the circle', () {
      expect(AmbientMotion.shortestDelta(359, 1), closeTo(2, .001));
      expect(AmbientMotion.shortestDelta(1, 359), closeTo(-2, .001));
      expect(AmbientMotion.shortestDelta(0, 180), closeTo(180, .001));
      expect(AmbientMotion.shortestDelta(0, 181), closeTo(-179, .001));
    });

    test('the hue travels across the zero point the short way', () {
      var state = motion.step(
        prev: const AmbientMotionState(),
        targetHue: 355,
        targetLevel: 50,
        bass: 0,
        dtMs: 100,
      );
      state = motion.step(
        prev: state,
        targetHue: 5,
        targetLevel: 50,
        bass: 0,
        dtMs: 100,
      );
      // It went from 355 up over the zero point instead of backwards
      // through the whole ring.
      expect(state.hue, greaterThan(355));
      expect(state.hue, lessThanOrEqualTo(360));
    });

    test('the brightness rises fast and falls slowly', () {
      var up = const AmbientMotionState();
      for (var i = 0; i < 10; i++) {
        up = motion.step(
          prev: up,
          targetHue: 0,
          targetLevel: 100,
          bass: 0,
          dtMs: 100,
        );
      }
      var down = up;
      for (var i = 0; i < 10; i++) {
        down = motion.step(
          prev: down,
          targetHue: 0,
          targetLevel: 0,
          bass: 0,
          dtMs: 100,
        );
      }
      // After a second the rise is nearly full, the fall is far from it.
      expect(up.level, greaterThan(.95));
      expect(down.level, lessThan(.2));
    });

    test('the brightness always stays between 0 and 1', () {
      var state = const AmbientMotionState();
      for (var i = 0; i < 50; i++) {
        state = motion.step(
          prev: state,
          targetHue: 0,
          targetLevel: 100,
          bass: 1,
          dtMs: 100,
        );
      }
      expect(state.level, inInclusiveRange(0, 1));
      expect(state.brightness, inInclusiveRange(0, 1));
      for (var i = 0; i < 50; i++) {
        state = motion.step(
          prev: state,
          targetHue: 0,
          targetLevel: 0,
          bass: 0,
          dtMs: 100,
        );
      }
      expect(state.level, inInclusiveRange(0, 1));
      expect(state.brightness, inInclusiveRange(0, 1));
    });

    test('the hue does not jitter along with the target', () {
      // The opposite of "stiff": the target flips between 0 and 30 degrees,
      // but the actual hue must barely move.
      var state = motion.step(
        prev: const AmbientMotionState(),
        targetHue: 0,
        targetLevel: 80,
        bass: .3,
        dtMs: 100,
      );
      var maxStep = 0.0;
      for (var i = 0; i < 20; i++) {
        final target = i % 2 == 0 ? 0.0 : 30.0;
        final before = state.hue;
        state = motion.step(
          prev: state,
          targetHue: target,
          targetLevel: 80,
          bass: .3,
          dtMs: 100,
        );
        final moved =
            (state.hue - before).abs() % 360;
        final step = moved > 180 ? 360 - moved : moved;
        if (step > maxStep) maxStep = step;
      }
      // The rate limit is 9 degrees per 100 ms frame.
      expect(maxStep, lessThanOrEqualTo(9.01));
    });

    test('a bass onset adds a pulse that fades', () {
      var state = motion.step(
        prev: const AmbientMotionState(),
        targetHue: 0,
        targetLevel: 50,
        bass: 0,
        dtMs: 100,
      );
      // Build the slow low frequency envelope up first, otherwise a single
      // loud frame is not an onset but simply the envelope catching up.
      for (var i = 0; i < 5; i++) {
        state = motion.step(
          prev: state,
          targetHue: 0,
          targetLevel: 50,
          bass: .5,
          dtMs: 100,
        );
      }
      state = motion.step(
        prev: state,
        targetHue: 0,
        targetLevel: 50,
        bass: .95,
        dtMs: 100,
      );
      expect(state.pulse, closeTo(1, .001));
      // The onset has to be brighter than the plain level.
      expect(state.brightness, greaterThan(state.level));
      final withBeat = state.brightness;
      // The low frequency falls back, so the pulse decays.
      state = motion.step(
        prev: state,
        targetHue: 0,
        targetLevel: 50,
        bass: 0,
        dtMs: 100,
      );
      expect(state.pulse, lessThan(1));
      expect(state.pulse, greaterThan(0));
      expect(state.brightness, lessThan(withBeat));
    });

    test('without an onset the brightness is the level itself', () {
      const flat = AmbientMotion(pulseGain: 0);
      var state = const AmbientMotionState();
      for (var i = 0; i < 20; i++) {
        state = flat.step(
          prev: state,
          targetHue: 0,
          targetLevel: 80,
          bass: .05,
          dtMs: 100,
        );
      }
      expect(state.pulse, lessThan(.01));
      expect(state.brightness, closeTo(state.level, .001));
    });

    test('a quiet low band is not an onset', () {
      var state = motion.step(
        prev: const AmbientMotionState(),
        targetHue: 0,
        targetLevel: 40,
        bass: 0,
        dtMs: 100,
      );
      state = motion.step(
        prev: state,
        targetHue: 0,
        targetLevel: 40,
        bass: 0.05,
        dtMs: 100,
      );
      expect(state.pulse, lessThan(1));
    });

    test('the elapsed time is clamped', () {
      final state = motion.step(
        prev: const AmbientMotionState(),
        targetHue: 0,
        targetLevel: 100,
        bass: 0,
        // Coming back from the background after minutes.
        dtMs: 600000,
      );
      // The clamp keeps the step at one second, so the level is still
      // moving towards the target rather than jumping straight to it.
      expect(state.level, lessThan(1));
      expect(state.level, greaterThan(0));
    });
  });

  group('the low frequency fallback', () {
    test('equal low bands mean the spectrum cannot resolve them', () {
      final bands = List<double>.filled(24, 0.02);
      for (var i = 0; i < 4; i++) {
        bands[i] = 0.4;
      }
      expect(AmbientPalette.isBassUnresolvable(bands), isTrue);
    });

    test('different low bands mean the spectrum resolves them', () {
      final bands = List<double>.filled(24, 0.02);
      bands[0] = 0.4;
      bands[1] = 0.2;
      bands[2] = 0.6;
      bands[3] = 0.1;
      expect(AmbientPalette.isBassUnresolvable(bands), isFalse);
    });

    test('silence is not an unresolvable spectrum', () {
      expect(AmbientPalette.isBassUnresolvable(List.filled(24, 0)), isFalse);
    });

    test('an unresolvable bass falls back to the intensity', () {
      final bands = List<double>.filled(24, 0.02);
      for (var i = 0; i < 4; i++) {
        bands[i] = 0.6;
      }
      // Without the fallback the hue would be stuck at zero degrees, red.
      final hue = AmbientPalette.bassHue(bands, 0);
      expect(hue, closeTo(AmbientPalette.intensityHue(0.6), .001));
      expect(hue, isNot(closeTo(0, .001)));
    });

    test('the intensity hue runs from cold to warm', () {
      expect(AmbientPalette.intensityHue(0), closeTo(260, .001));
      expect(AmbientPalette.intensityHue(1), closeTo(20, .001));
      final middle = AmbientPalette.intensityHue(0.5);
      expect(middle, greaterThan(20));
      expect(middle, lessThan(260));
    });

    test('a resolvable bass keeps the band hue', () {
      final bands = List<double>.filled(24, 0.02);
      bands[1] = 0.6;
      bands[2] = 0.1;
      bands[3] = 0.2;
      bands[0] = 0.05;
      expect(AmbientPalette.bassHue(bands, 0),
          closeTo(AmbientPalette.hueForBand(1, 24), .001));
    });
  });

  group('the palette targets', () {
    test('the target hue and level are split out of the colour', () {
      final bands = List<double>.filled(24, 0.02);
      for (var i = 4; i < 8; i++) {
        bands[i] = 0.9;
      }
      final hue = AmbientPalette.targetHue(
        bands: bands,
        mode: AmbientPalette.modeSpectrum,
        fixedHue: 210,
      );
      final level = AmbientPalette.targetLevel(
        bands: bands,
        level: 0.9,
        mode: AmbientPalette.modeSpectrum,
        sensitivity: 1.4,
        minBrightness: 15,
        maxBrightness: 100,
      );
      final color = AmbientPalette.colorOf(hue, level);
      expect(color.brightness, level);
      expect(color.hex, isNot('#000000'));
    });

    test('the bass mode takes its level from the bass energy', () {
      final bands = List<double>.filled(24, 0.02);
      for (var i = 0; i < 4; i++) {
        bands[i] = 0.8;
      }
      final level = AmbientPalette.targetLevel(
        bands: bands,
        level: 0.1,
        mode: AmbientPalette.modeBass,
        sensitivity: 1.4,
        minBrightness: 15,
        maxBrightness: 100,
      );
      expect(level, greaterThan(50));
    });
  });

  group('the motion layer against the direct mapping', () {
    test('the motion layer jumps far less than the direct mapping', () {
      // A synthetic kick: the loudest low band flips between two bands,
      // which is exactly what makes the strip jump in real music.
      final bands = List<double>.filled(16, .05);

      // The old chain: the spectrum goes straight to the colour.
      var lastHue = 0.0;
      AmbientColor? previousOld;
      var maxOld = 0;
      // The new chain: target -> motion layer -> colour.
      var state = const AmbientMotionState();
      AmbientColor? previousNew;
      var maxNew = 0;

      for (var i = 0; i < 40; i++) {
        for (var b = 0; b < bands.length; b++) {
          bands[b] = .05;
        }
        bands[i % 2 == 0 ? 0 : 3] = .9;

        final old = AmbientPalette.scaleByBrightness(
          AmbientPalette.colorFrom(
            bands: bands,
            level: .5,
            mode: AmbientPalette.modeBass,
            fixedHue: 0,
            sensitivity: 1,
            minBrightness: 0,
            maxBrightness: 100,
            fallbackHue: lastHue,
          ),
        );
        lastHue = AmbientPalette.spectrumHue(bands, lastHue);
        final before = previousOld;
        if (before != null) {
          final distance = AmbientPalette.colorDistance(before, old);
          if (distance > maxOld) maxOld = distance;
        }
        previousOld = old;

        final targetHue = AmbientPalette.targetHue(
          bands: bands,
          mode: AmbientPalette.modeBass,
          fixedHue: 0,
          fallbackHue: state.hue,
        );
        final targetLevel = AmbientPalette.targetLevel(
          bands: bands,
          level: .5,
          mode: AmbientPalette.modeBass,
          sensitivity: 1,
          minBrightness: 0,
          maxBrightness: 100,
        );
        state = const AmbientMotion().step(
          prev: state,
          targetHue: targetHue,
          targetLevel: targetLevel,
          bass: AmbientPalette.bassEnergy(bands),
          dtMs: 100,
        );
        final next =
            AmbientPalette.colorOf(state.hue, (state.brightness * 100).round());
        final beforeNew = previousNew;
        if (beforeNew != null) {
          final distance = AmbientPalette.colorDistance(beforeNew, next);
          if (distance > maxNew) maxNew = distance;
        }
        previousNew = next;
      }

      // The direct mapping jumps between two band hues every frame, the
      // motion layer only walks there.
      expect(maxOld, greaterThan(maxNew * 3));
      // It still moves, otherwise the strip would look frozen.
      expect(maxNew, greaterThan(0));
    });
  });
}
