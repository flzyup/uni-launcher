import 'package:flutter_test/flutter_test.dart';
import 'package:uni_launcher/model/ambient_color_space.dart';
import 'package:uni_launcher/model/ambient_light.dart';
import 'package:uni_launcher/model/ambient_motion.dart';

/// The **V2** motion layer.
///
/// V2 has three things the legacy layer does not have, and each of them has
/// an assertion here:
///
/// 1. the **second order** hue (a rate limit plus an *acceleration* limit);
/// 2. the **adaptive** onset (a threshold that follows the slow envelope
///    plus a minimum gap);
/// 3. the **idle breathing** (a slow drift instead of a frozen colour).
void main() {
  /// The per frame colour difference cap, the same as the controller.
  const maxDeltaE = 1.8;

  AmbientMotion motion({
    double hueTauMs = 260,
    double hueMaxDegPerSec = 60,
    double hueMaxAccelDegPerSec2 = 240,
    double attackMs = 45,
    double decayMs = 260,
    double bassTauMs = 160,
    double pulseTauMs = 170,
    double pulseGain = 0.35,
    double beatFloor = 0.12,
    double beatRatio = 1.25,
    int beatMinGapMs = 240,
    double breathAmount = 0.10,
  }) =>
      AmbientMotion(
        hueTauMs: hueTauMs,
        hueMaxDegPerSec: hueMaxDegPerSec,
        hueMaxAccelDegPerSec2: hueMaxAccelDegPerSec2,
        attackMs: attackMs,
        decayMs: decayMs,
        bassTauMs: bassTauMs,
        pulseTauMs: pulseTauMs,
        pulseGain: pulseGain,
        beatFloor: beatFloor,
        beatRatio: beatRatio,
        beatMinGapMs: beatMinGapMs,
        breathAmount: breathAmount,
      );

  group('AmbientMotion V2', () {
    test('the hue takes the short way round the circle', () {
      expect(AmbientMotion.shortestDelta(359, 1), closeTo(2, .001));
      expect(AmbientMotion.shortestDelta(1, 359), closeTo(-2, .001));
      expect(AmbientMotion.shortestDelta(0, 90), closeTo(90, .001));
    });

    test('the hue is normalised into 0 to 360', () {
      expect(AmbientMotion.normalizeHue(360), closeTo(0, .001));
      expect(AmbientMotion.normalizeHue(-10), closeTo(350, .001));
    });

    test('the first frame lands on the target', () {
      // The colour appears when the strip switches on, it is not swept in.
      final state = motion().step(
        prev: const AmbientMotionState(),
        targetHue: 200,
        targetLevel: .5,
        targetChroma: 0,
        bass: 0,
        dtMs: 16,
        nowMs: 10000,
      );
      expect(state.hue, closeTo(200, .001));
      expect(state.hueVel, closeTo(0, .001));
      expect(state.initialized, isTrue);
    });

    test('one frame does not move the hue past the rate limit', () {
      final m = motion(hueMaxDegPerSec: 60);
      var state = m.step(
        prev: const AmbientMotionState(),
        targetHue: 0,
        targetLevel: .5,
        targetChroma: 0,
        bass: 0,
        dtMs: 16,
        nowMs: 10000,
      );
      state = m.step(
        prev: state,
        targetHue: 180,
        targetLevel: .5,
        targetChroma: 0,
        bass: 0,
        dtMs: 16,
        nowMs: 10016,
      );
      // 16 ms at 60 degrees per second is 0.96 degrees.
      expect(state.hue, lessThanOrEqualTo(.961));
    });

    test('the acceleration limit slows the start down', () {
      // This is the key difference to the legacy layer: a first order system
      // can only bound the speed, so the strip whips across and stutters when
      // it changes direction half way. The acceleration limit is the cure.
      final m = motion(hueMaxDegPerSec: 60, hueMaxAccelDegPerSec2: 240);
      var state = m.step(
        prev: const AmbientMotionState(),
        targetHue: 0,
        targetLevel: .5,
        targetChroma: 0,
        bass: 0,
        dtMs: 16,
        nowMs: 10000,
      );
      state = m.step(
        prev: state,
        targetHue: 180,
        targetLevel: .5,
        targetChroma: 0,
        bass: 0,
        dtMs: 16,
        nowMs: 10016,
      );
      final moved = (state.hue - 0).abs();
      final speedLimitAllows = 60 * .016;
      expect(moved, lessThan(speedLimitAllows * .5));
      // 240 degrees per second squared over 16 ms is 3.84 degrees per second,
      // so the first frame moves about 0.06 degrees.
      expect(moved, lessThanOrEqualTo(.07));
    });

    test('the velocity builds up and the target is still reached', () {
      // The acceleration limit must not turn into "never arrives".
      final m = motion();
      var state = const AmbientMotionState();
      var now = 10000;
      for (var i = 0; i < 200; i++) {
        now += 16;
        state = m.step(
          prev: state,
          targetHue: 180,
          targetLevel: .5,
          targetChroma: 0,
          bass: 0,
          dtMs: 16,
          nowMs: now,
        );
      }
      expect((state.hue - 180).abs(), lessThan(2));
    });

    test('the hue catches up with a target it did not start on', () {
      // The test above starts from the default state, and the first frame
      // lands **on** the target — so the tracker is never measured at all.
      // That is how a hue that crawled at a 64th of its intended speed
      // survived: the gap was always zero.
      //
      // Here the first frame lands on 200 and the target then moves to 280.
      // The hue has to cover 80 degrees, and with tau = 260 ms it has to be
      // there within a second or two.
      final m = motion();
      var state = m.step(
        prev: const AmbientMotionState(),
        targetHue: 200,
        targetLevel: .5,
        targetChroma: 0,
        bass: 0,
        dtMs: 16,
        nowMs: 10000,
      );
      expect(state.hue, closeTo(200, .001));
      var now = 10000;
      for (var i = 0; i < 120; i++) {
        now += 16;
        state = m.step(
          prev: state,
          targetHue: 280,
          targetLevel: .5,
          targetChroma: 0,
          bass: 0,
          dtMs: 16,
          nowMs: now,
        );
      }
      expect((state.hue - 280).abs(), lessThan(3),
          reason: 'the hue only reached ${state.hue}');
    });

    test('the hue still filters out a target that jitters', () {
      // The opposite requirement: the tracker has to be fast enough to
      // follow the music but slow enough not to copy every 10 Hz frame.
      // A target that flips between 0 and 30 degrees every frame must not
      // move the hue by more than a degree per frame.
      final m = motion();
      var state = m.step(
        prev: const AmbientMotionState(),
        targetHue: 0,
        targetLevel: .5,
        targetChroma: 0,
        bass: 0,
        dtMs: 16,
        nowMs: 10000,
      );
      var maxStep = 0.0;
      for (var i = 0; i < 30; i++) {
        final target = i % 2 == 0 ? 0.0 : 30.0;
        final before = state.hue;
        state = m.step(
          prev: state,
          targetHue: target,
          targetLevel: .5,
          targetChroma: 0,
          bass: 0,
          dtMs: 16,
          nowMs: 10000 + (i + 1) * 16,
        );
        final moved = (state.hue - before).abs() % 360;
        final step = moved > 180 ? 360 - moved : moved;
        if (step > maxStep) maxStep = step;
      }
      expect(maxStep, lessThanOrEqualTo(.97));
    });

    test('the hue does not jitter along with the target', () {
      // The opposite of "stiff": the target flips between 0 and 30 degrees,
      // but the actual hue must barely move.
      final m = motion();
      var state = m.step(
        prev: const AmbientMotionState(),
        targetHue: 0,
        targetLevel: .5,
        targetChroma: 0,
        bass: .3,
        dtMs: 16,
        nowMs: 10000,
      );
      var maxStep = 0.0;
      for (var i = 0; i < 30; i++) {
        final target = i % 2 == 0 ? 0.0 : 30.0;
        final before = state.hue;
        state = m.step(
          prev: state,
          targetHue: target,
          targetLevel: .5,
          targetChroma: 0,
          bass: .3,
          dtMs: 16,
          nowMs: 10000 + (i + 1) * 16,
        );
        final moved = (state.hue - before).abs() % 360;
        final step = moved > 180 ? 360 - moved : moved;
        if (step > maxStep) maxStep = step;
      }
      expect(maxStep, lessThanOrEqualTo(.97));
    });

    test('the elapsed time is clamped', () {
      final state = motion().step(
        prev: const AmbientMotionState(),
        targetHue: 0,
        targetLevel: 1,
        targetChroma: 0,
        bass: 0,
        // Coming back from the background after minutes.
        dtMs: 600000,
        nowMs: 10000,
      );
      expect(state.level, lessThan(1));
      expect(state.level, greaterThan(0));
    });

    test('the lightness rises fast and falls slowly', () {
      final m = motion();
      var up = const AmbientMotionState();
      for (var i = 0; i < 30; i++) {
        up = m.step(
          prev: up,
          targetHue: 0,
          targetLevel: 1,
          targetChroma: 0,
          bass: 0,
          dtMs: 16,
          nowMs: 10000 + i * 16,
        );
      }
      var down = up;
      for (var i = 0; i < 30; i++) {
        down = m.step(
          prev: down,
          targetHue: 0,
          targetLevel: 0,
          targetChroma: 0,
          bass: 0,
          dtMs: 16,
          nowMs: 10000 + (30 + i) * 16,
        );
      }
      expect(up.level, greaterThan(.95));
      expect(down.level, lessThan(.2));
    });

    test('the lightness always stays between 0 and 1', () {
      final m = motion();
      var state = const AmbientMotionState();
      for (var i = 0; i < 200; i++) {
        state = m.step(
          prev: state,
          targetHue: 0,
          targetLevel: 1,
          targetChroma: 0,
          bass: 1,
          dtMs: 16,
          nowMs: 10000 + i * 16,
        );
      }
      expect(state.level, inInclusiveRange(0, 1));
      expect(state.brightness, inInclusiveRange(0, 1));
    });

    test('a kick reaches 90 percent within 120 ms', () {
      // The acceptance criterion of the scheme document.
      final m = motion(attackMs: 45);
      var state = const AmbientMotionState();
      var now = 10000;
      var elapsed = 0;
      while (state.level < .9 && elapsed < 500) {
        now += 16;
        elapsed += 16;
        state = m.step(
          prev: state,
          targetHue: 0,
          targetLevel: 1,
          targetChroma: 0,
          bass: 0,
          dtMs: 16,
          nowMs: now,
        );
      }
      expect(elapsed, lessThanOrEqualTo(120));
    });

    test('a low frequency jump is an onset', () {
      final m = motion();
      var state = const AmbientMotionState();
      var now = 10000;
      // The baseline has to stay under the absolute floor, otherwise the very
      // first frame would already be an onset.
      for (var i = 0; i < 10; i++) {
        now += 16;
        state = m.step(
          prev: state,
          targetHue: 200,
          targetLevel: .5,
          targetChroma: 0,
          bass: .05,
          dtMs: 16,
          nowMs: now,
        );
      }
      now += 16;
      state = m.step(
        prev: state,
        targetHue: 200,
        targetLevel: .5,
        targetChroma: 0,
        bass: .95,
        dtMs: 16,
        nowMs: now,
      );
      expect(state.pulse, closeTo(1, .001));
    });

    test('the noise floor is not an onset', () {
      final m = motion();
      var state = const AmbientMotionState();
      var now = 10000;
      for (var i = 0; i < 20; i++) {
        now += 16;
        state = m.step(
          prev: state,
          targetHue: 200,
          targetLevel: .5,
          targetChroma: 0,
          bass: .05,
          dtMs: 16,
          nowMs: now,
        );
      }
      expect(state.pulse, closeTo(0, .001));
    });

    test('the minimum gap suppresses a second onset', () {
      // 240 ms keeps the eighth notes of a 120 BPM track (about 250 ms
      // apart) from counting as two onsets.
      final m = motion();
      var state = const AmbientMotionState();
      var now = 10000;
      for (var i = 0; i < 10; i++) {
        now += 16;
        state = m.step(
          prev: state,
          targetHue: 200,
          targetLevel: .5,
          targetChroma: 0,
          bass: .05,
          dtMs: 16,
          nowMs: now,
        );
      }
      now += 16;
      state = m.step(
        prev: state,
        targetHue: 200,
        targetLevel: .5,
        targetChroma: 0,
        bass: .95,
        dtMs: 16,
        nowMs: now,
      );
      expect(state.pulse, closeTo(1, .001));
      now += 100;
      state = m.step(
        prev: state,
        targetHue: 200,
        targetLevel: .5,
        targetChroma: 0,
        bass: .95,
        dtMs: 16,
        nowMs: now,
      );
      expect(state.pulse, lessThan(1));
    });

    test('the pulse fades', () {
      final m = motion();
      var state = const AmbientMotionState();
      var now = 10000;
      for (var i = 0; i < 10; i++) {
        now += 16;
        state = m.step(
          prev: state,
          targetHue: 200,
          targetLevel: .5,
          targetChroma: 0,
          bass: .05,
          dtMs: 16,
          nowMs: now,
        );
      }
      now += 16;
      state = m.step(
        prev: state,
        targetHue: 200,
        targetLevel: .5,
        targetChroma: 0,
        bass: .95,
        dtMs: 16,
        nowMs: now,
      );
      expect(state.pulse, closeTo(1, .001));
      state = m.step(
        prev: state,
        targetHue: 200,
        targetLevel: .5,
        targetChroma: 0,
        bass: 0,
        dtMs: 16,
        nowMs: now + 16,
      );
      expect(state.pulse, lessThan(1));
      expect(state.pulse, greaterThan(0));
    });

    test('an onset pushes the hue towards the warm end', () {
      // The kick is visible, but not glaring: 14 degrees.
      final m = motion();
      var state = const AmbientMotionState();
      var now = 10000;
      for (var i = 0; i < 20; i++) {
        now += 16;
        state = m.step(
          prev: state,
          targetHue: 200,
          targetLevel: .5,
          targetChroma: 0,
          bass: .05,
          dtMs: 16,
          nowMs: now,
        );
      }
      final before = state.hue;
      now += 16;
      state = m.step(
        prev: state,
        targetHue: 200,
        targetLevel: .5,
        targetChroma: 0,
        bass: .95,
        dtMs: 16,
        nowMs: now,
      );
      expect(state.hue, greaterThan(before));
    });

    test('the hue drifts slowly while nothing plays', () {
      final m = motion();
      var state = const AmbientMotionState();
      var now = 10000;
      for (var i = 0; i < 20; i++) {
        now += 16;
        state = m.step(
          prev: state,
          targetHue: 200,
          targetLevel: .5,
          targetChroma: 0,
          bass: 0,
          dtMs: 16,
          nowMs: now,
        );
      }
      final before = state.hue;
      for (var i = 0; i < 125; i++) {
        now += 16;
        state = m.step(
          prev: state,
          targetHue: 200,
          targetLevel: 0,
          targetChroma: 0,
          bass: 0,
          dtMs: 16,
          nowMs: now,
          silent: true,
        );
      }
      final drifted = (state.hue - before).abs();
      // 2.2 degrees per second over two seconds is about 4.4 degrees.
      expect(drifted, greaterThan(1));
      expect(drifted, lessThan(15));
    });

    test('the idle state falls back to the breathing base light', () {
      final m = motion(breathAmount: .10);
      var state = const AmbientMotionState();
      var now = 10000;
      for (var i = 0; i < 60; i++) {
        now += 16;
        state = m.step(
          prev: state,
          targetHue: 200,
          targetLevel: 1,
          targetChroma: 0,
          bass: 0,
          dtMs: 16,
          nowMs: now,
        );
      }
      for (var i = 0; i < 300; i++) {
        now += 16;
        state = m.step(
          prev: state,
          targetHue: 200,
          targetLevel: 0,
          targetChroma: 0,
          bass: 0,
          dtMs: 16,
          nowMs: now,
          silent: true,
        );
      }
      expect(state.level, greaterThan(0));
      expect(state.level, lessThan(.2));
    });

    test('the chroma smooths slowly', () {
      final m = motion();
      var state = m.step(
        prev: const AmbientMotionState(),
        targetHue: 200,
        targetLevel: .5,
        targetChroma: 0,
        bass: 0,
        dtMs: 16,
        nowMs: 10000,
      );
      state = m.step(
        prev: state,
        targetHue: 200,
        targetLevel: .5,
        targetChroma: .22,
        bass: 0,
        dtMs: 16,
        nowMs: 10016,
      );
      expect(state.chroma, lessThan(.22));
      expect(state.chroma, greaterThan(0));
    });
  });

  group('the V2 chain against the legacy chain', () {
    test('one frame changes far less than the legacy chain', () {
      // A synthetic kick: the loudest low band flips between two bands,
      // which is exactly what makes the strip jump in real music.
      final bands = List<double>.filled(16, 0);

      // The legacy chain: the spectrum goes straight to the colour.
      var lastHue = 0.0;
      AmbientColor? previousOld;
      var maxOld = 0.0;
      // The V2 chain: target -> motion layer -> OKLCH.
      var state = const AmbientMotionState();
      AmbientColor? previousLimited;
      (double, double, double)? previousRawLab;
      var maxNewRaw = 0.0;
      var maxNewLimited = 0.0;
      var now = 10000;

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
          if (distance > maxOld) maxOld = distance.toDouble();
        }
        previousOld = old;

        final targetHue = AmbientPalette.lowCentroidHue(bands, state.hue);
        // 60 Hz: six render frames between two spectrum frames.
        for (var _ = 0; _ < 6; _++) {
          now += 16;
          state = const AmbientMotion().step(
            prev: state,
            targetHue: targetHue,
            targetLevel: .5,
            targetChroma: .18,
            bass: AmbientPalette.bassEnergy(bands),
            dtMs: 16,
            nowMs: now,
          );
          final raw = AmbientPalette.colorOfOklch(
            state.hue,
            AmbientPalette.perceptualLightness(state.level),
            state.chroma,
          );
          final previous = previousLimited;
          var limited = raw;
          if (previous != null) {
            final (r, g, b) = AmbientColorSpace.limitByDeltaE(
              previous.r,
              previous.g,
              previous.b,
              raw.r,
              raw.g,
              raw.b,
              maxDeltaE,
            );
            limited = AmbientColor(r, g, b, raw.brightness);
            final previousLab = AmbientColorSpace.rgbToLab(
              previous.r,
              previous.g,
              previous.b,
            );
            final limitedLab =
                AmbientColorSpace.rgbToLab(limited.r, limited.g, limited.b);
            final de = AmbientColorSpace.deltaE00(previousLab, limitedLab);
            if (de > maxNewLimited) maxNewLimited = de;
          }
          previousLimited = limited;

          final rawLab = AmbientColorSpace.rgbToLab(raw.r, raw.g, raw.b);
          final previousRaw = previousRawLab;
          if (previousRaw != null) {
            final de = AmbientColorSpace.deltaE00(previousRaw, rawLab);
            if (de > maxNewRaw) maxNewRaw = de;
          }
          previousRawLab = rawLab;
        }
      }

      // The legacy chain jumps between two band hues every frame, the V2
      // chain only walks there.
      expect(maxOld, greaterThan(maxNewLimited * 4));
      // After the speed limit every frame stays within the cap.
      expect(maxNewLimited, lessThanOrEqualTo(maxDeltaE + .05));
      // And the limiter really did have to do something.
      expect(maxNewRaw, greaterThan(maxDeltaE));
    });
  });
}
