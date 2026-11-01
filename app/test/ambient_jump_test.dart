import 'package:flutter_test/flutter_test.dart';
import 'package:uni_launcher/model/ambient_light.dart';
import 'package:uni_launcher/model/ambient_motion.dart';
import 'package:uni_launcher/model/ambient_presets.dart';

/// The 「跳跃」 (jump) preset: the hue **jumps** instead of sliding.
///
/// This is the Dart translation of cardesk's `AmbientJumpTest.kt`. Three
/// things are added to the motion layer, and each has an assertion here:
///
/// 1. the **hue jump** (`hueJumpDeg`): the hue snaps onto the nearest step
///    instead of tracking the target. Faster smoothing cannot do this — a
///    shorter tau or a higher limit only shortens the slide;
/// 2. the **kick flash gain** (`pulseGain`): how high an onset pushes the
///    lightness;
/// 3. the **shortest kick gap** (`beatMinGapMs`): how often the flash may
///    fire;
/// 4. the **forced colour change interval** (`jumpHoldMs`): onset detection
///    is content driven, so a track without kick drums would freeze on one
///    colour. The interval caps the wait, so the jump light keeps flashing.
///
/// The defaults stay 0 / 0.35 / 240, so every old preset looks exactly as
/// before.
void main() {
  AmbientMotion motion({
    double hueJumpDeg = 0,
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
    int jumpHoldMs = 0,
  }) =>
      AmbientMotion(
        hueJumpDeg: hueJumpDeg,
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
        jumpHoldMs: jumpHoldMs,
      );

  group('the hue jump', () {
    test('snapHue rounds onto the 60 degree steps', () {
      expect(AmbientMotion.snapHue(100, 60), closeTo(120, .001));
      expect(AmbientMotion.snapHue(10, 60), closeTo(0, .001));
      expect(AmbientMotion.snapHue(89, 60), closeTo(60, .001));
      expect(AmbientMotion.snapHue(90, 60), closeTo(120, .001));
      // Exactly half a step: Dart's `round` and Kotlin's `Math.round` both
      // go up at a half (towards positive infinity for a non negative
      // quotient), so the two apps jump to the same step.
      expect(AmbientMotion.snapHue(30, 60), closeTo(60, .001));
      // Six steps cover the circle: red, yellow, green, cyan, blue, magenta.
      final steps = <double>{
        for (var hue = 0.0; hue < 360; hue += 10) AmbientMotion.snapHue(hue, 60)
      };
      expect(steps.length, 6);
      // The step is clamped to 1..180: 0 means "every degree", 240 is the
      // same pair of poles as 180.
      expect(AmbientMotion.snapHue(100, 0), closeTo(100, .001));
      expect(AmbientMotion.snapHue(100, 240), closeTo(180, .001));
      // The result is always a hue in 0..360.
      expect(AmbientMotion.snapHue(359, 60), closeTo(0, .001));
    });

    test('one frame lands on the step and clears the velocity', () {
      // A jump is not "a very fast slide": the colour is on the new step in
      // the very first frame, with no angular velocity left over.
      final m = motion(hueJumpDeg: 60);
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
        targetHue: 100,
        targetLevel: .5,
        targetChroma: 0,
        bass: 0,
        dtMs: 16,
        nowMs: 10016,
      );
      expect(state.hue, closeTo(120, .001));
      expect(state.hueVel, closeTo(0, .001));
    });

    test('without a jump the same frame only slides a little', () {
      // The same input with the default hueJumpDeg 0: the second order
      // tracker moves a fraction of a degree, which is exactly why a jump
      // needs its own branch instead of a faster smoother.
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
      state = m.step(
        prev: state,
        targetHue: 100,
        targetLevel: .5,
        targetChroma: 0,
        bass: 0,
        dtMs: 16,
        nowMs: 10016,
      );
      expect(state.hue, greaterThan(0));
      expect(state.hue, lessThan(1));
      expect(state.hueVel, greaterThan(0));
    });
  });

  group('the forced colour change interval', () {
    /// Runs 12 frames of a steady 0.5 bass, which the adaptive threshold
    /// quickly accepts as "normal" so no onset is detected any more.
    List<double> hues(int holdMs) {
      final m = motion(hueJumpDeg: 120, beatMinGapMs: 120, jumpHoldMs: holdMs);
      var state = const AmbientMotionState();
      var now = 10000;
      for (var i = 0; i < 12; i++) {
        now += 100;
        state = m.step(
          prev: state,
          targetHue: 0,
          targetLevel: .5,
          targetChroma: 0,
          bass: .5,
          dtMs: 100,
          nowMs: now,
        );
      }
      final out = <double>[];
      for (var i = 0; i < 12; i++) {
        now += 100;
        state = m.step(
          prev: state,
          targetHue: 0,
          targetLevel: .5,
          targetChroma: 0,
          bass: .5,
          dtMs: 100,
          nowMs: now,
        );
        out.add(state.hue);
      }
      return out;
    }

    test('a steady sound still changes colour on its own', () {
      final capped = hues(380);
      final changes = <double>[
        for (var i = 1; i < capped.length; i++)
          if ((capped[i] - capped[i - 1]).abs() > 1) capped[i]
      ].length;
      expect(changes, greaterThanOrEqualTo(2),
          reason: 'the strip must not freeze: $capped');
      for (final hue in capped) {
        final off = hue % 120;
        expect(off < .01 || 120 - off < .01, isTrue,
            reason: 'every colour must be on a 120° step: $capped');
      }
    });

    test('zero means only follow the beats', () {
      final uncapped = hues(0);
      final changes = <double>[
        for (var i = 1; i < uncapped.length; i++)
          if ((uncapped[i] - uncapped[i - 1]).abs() > 1) uncapped[i]
      ].length;
      expect(changes, 0,
          reason: 'following only the beats must not change on its own: '
              '$uncapped');
    });
  });

  group('the kick flash', () {
    /// One onset frame after a quiet baseline: [gain] is the flash gain.
    AmbientMotionState onsetFrame(double gain) {
      final m = motion(pulseGain: gain);
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
      return m.step(
        prev: state,
        targetHue: 200,
        targetLevel: .5,
        targetChroma: 0,
        bass: .95,
        dtMs: 16,
        nowMs: now,
      );
    }

    test('a 1.20x flash is brighter than the old 0.35x one', () {
      final jump = onsetFrame(1.2);
      final old = onsetFrame(.35);
      expect(jump.pulse, closeTo(1, .001));
      expect(old.pulse, closeTo(1, .001));
      expect(jump.brightness, greaterThan(old.brightness));
      // The level is the same base light, so the whole gap comes from the
      // flash gain (0.85 of the base 0.5 = 0.425, partly smoothed).
      expect(jump.brightness - old.brightness, greaterThan(.05));
    });

    test('a 120 ms gap flashes more often than 240 ms', () {
      /// Onset frames in a 2 s window of a 150 ms pulse train: denser than
      /// 240 ms, sparser than 120 ms.
      int flashes(int beatMinGapMs) {
        final m = motion(beatMinGapMs: beatMinGapMs);
        var state = const AmbientMotionState();
        var count = 0;
        for (var i = 0; i < 125; i++) {
          final now = 10000 + i * 16;
          final high = (now - 10000) % 150 < 16;
          state = m.step(
            prev: state,
            targetHue: 200,
            targetLevel: .5,
            targetChroma: 0,
            bass: high ? .95 : .05,
            dtMs: 16,
            nowMs: now,
          );
          if (state.pulse > .999) count++;
        }
        return count;
      }

      expect(flashes(120), greaterThan(flashes(240)));
    });
  });

  group('the jump preset', () {
    test('is recognised field by field', () {
      final p = AmbientPresets.jump;
      final got = AmbientPresets.match(
        attackMs: p.attackMs,
        decayMs: p.decayMs,
        hueTauMs: p.hueTauMs,
        hueMaxDeg: p.hueMaxDeg,
        hueMaxAccel: p.hueMaxAccel,
        maxDeltaE: p.maxDeltaE,
        floor: p.floor,
        breath: p.breath,
        saturation: p.saturation,
        hueSpanDeg: p.hueSpanDeg,
        centroidWindowLowHundredths: p.centroidWindowLowHundredths,
        centroidWindowSpanHundredths: p.centroidWindowSpanHundredths,
        hueRotateDegPerSec: p.hueRotateDegPerSec,
        maxChromaHundredths: p.maxChromaHundredths,
        hueJumpDeg: p.hueJumpDeg,
        pulseGainHundredths: p.pulseGainHundredths,
        beatMinGapMs: p.beatMinGapMs,
        jumpHoldMs: p.jumpHoldMs,
      );
      expect(got, AmbientPresets.all.indexOf(p));
      expect(AmbientPresets.all.last, same(p));
    });

    test('forcing the jump back to 0 matches nothing', () {
      final p = AmbientPresets.jump;
      final got = AmbientPresets.match(
        attackMs: p.attackMs,
        decayMs: p.decayMs,
        hueTauMs: p.hueTauMs,
        hueMaxDeg: p.hueMaxDeg,
        hueMaxAccel: p.hueMaxAccel,
        maxDeltaE: p.maxDeltaE,
        floor: p.floor,
        breath: p.breath,
        saturation: p.saturation,
        hueSpanDeg: p.hueSpanDeg,
        centroidWindowLowHundredths: p.centroidWindowLowHundredths,
        centroidWindowSpanHundredths: p.centroidWindowSpanHundredths,
        hueRotateDegPerSec: p.hueRotateDegPerSec,
        maxChromaHundredths: p.maxChromaHundredths,
        hueJumpDeg: 0,
        pulseGainHundredths: p.pulseGainHundredths,
        beatMinGapMs: p.beatMinGapMs,
        jumpHoldMs: p.jumpHoldMs,
      );
      expect(got, -1);
    });

    test('is the only jumping preset, and the most dazzling', () {
      final jump = AmbientPresets.jump;
      expect(AmbientPresets.all.length, 6);
      expect(jump.name, '跳跃');
      expect(jump.hueJumpDeg, 120);
      expect(AmbientPresets.all.where((p) => p.hueJumpDeg > 0).length, 1,
          reason: 'only this preset may jump');
      // A dark base and no breathing: the flash is the whole show.
      expect(jump.floor, 0);
      expect(jump.breath, 0);
      expect(jump.saturation, 1.0);
      expect(jump.hueSpanDeg, 360);
      // The fastest kick of all presets.
      expect(jump.beatMinGapMs,
          lessThan(AmbientPresets.balanced.beatMinGapMs));
      expect(jump.pulseGainHundredths,
          greaterThan(AmbientPresets.balanced.pulseGainHundredths));
      // The forced colour change interval: a track without kick drums must
      // still flash instead of freezing on one colour.
      expect(jump.jumpHoldMs, inInclusiveRange(200, 600));
      expect(AmbientPresets.all.where((p) => p.jumpHoldMs > 0).length, 1,
          reason: 'only the jump preset forces a colour change');
    });

    test('the three fields default to the old look', () {
      const settings = AmbientLightSettings();
      expect(settings.hueJumpDeg, 0);
      expect(settings.pulseGainHundredths, 35);
      expect(settings.beatMinGapMs, 240);
      expect(settings.pulseGainValue, closeTo(.35, 1e-9));
      // The default look is still 均衡: no old preset grew a jump or a
      // flash, so an untouched configuration looks exactly as before.
      expect(
          AmbientPresets.match(
            attackMs: settings.attackMs,
            decayMs: settings.decayMs,
            hueTauMs: settings.hueTauMs,
            hueMaxDeg: settings.hueMaxDeg,
            hueMaxAccel: settings.hueMaxAccel,
            maxDeltaE: settings.maxDeltaE,
            floor: settings.floor,
            breath: settings.breath,
            saturation: settings.saturation,
            hueSpanDeg: settings.hueSpanDeg,
            centroidWindowLowHundredths: settings.centroidWindowLowHundredths,
            centroidWindowSpanHundredths:
                settings.centroidWindowSpanHundredths,
            hueRotateDegPerSec: settings.hueRotateDegPerSec,
            maxChromaHundredths: settings.maxChromaHundredths,
            hueJumpDeg: settings.hueJumpDeg,
            pulseGainHundredths: settings.pulseGainHundredths,
            beatMinGapMs: settings.beatMinGapMs,
            jumpHoldMs: settings.jumpHoldMs,
          ),
          AmbientPresets.all.indexOf(AmbientPresets.balanced));
      for (final p
          in AmbientPresets.all.where((p) => p != AmbientPresets.jump)) {
        expect(p.hueJumpDeg, 0, reason: '「${p.name}」should not jump');
        expect(p.pulseGainHundredths, 35,
            reason: '「${p.name}」should keep the old flash');
        expect(p.beatMinGapMs, 240,
            reason: '「${p.name}」should keep the old gap');
      }
    });

    test('the values round trip through json and clamp', () {
      const settings = AmbientLightSettings(
          hueJumpDeg: 60, pulseGainHundredths: 120, beatMinGapMs: 120);
      final json = settings.toJson();
      expect(json['ambient_hue_jump_deg'], 60);
      expect(json['ambient_pulse_gain'], 120);
      expect(json['ambient_beat_gap_ms'], 120);
      expect(AmbientLightSettings.fromJson(json), settings);
      final clamped = AmbientLightSettings.fromJson({
        'ambient_hue_jump_deg': 999,
        'ambient_pulse_gain': 999,
        'ambient_beat_gap_ms': 10,
      });
      expect(clamped.hueJumpDeg, 180);
      expect(clamped.pulseGainHundredths, 200);
      expect(clamped.beatMinGapMs, 80);
    });
  });

  group('one step per onset', () {
    test('every onset advances the hue by exactly one step', () {
      // A continuous loud bass is not an onset: the adaptive threshold
      // treats "still loud" as the state and stops firing. Real kicks are
      // "quiet -> suddenly loud", so the test feeds it the same way.
      final m = motion(hueJumpDeg: 60, beatMinGapMs: 120);
      var state = m.step(
        prev: const AmbientMotionState(),
        targetHue: 0,
        targetLevel: .5,
        targetChroma: 0,
        bass: 0,
        dtMs: 16,
        nowMs: 10000,
      );
      final hues = <double>[];
      var now = 10000;
      for (var i = 0; i < 4; i++) {
        now += 130;
        state = m.step(
          prev: state,
          targetHue: 0,
          targetLevel: .5,
          targetChroma: 0,
          bass: .05,
          dtMs: 130,
          nowMs: now,
        );
        now += 130;
        state = m.step(
          prev: state,
          targetHue: 0,
          targetLevel: .5,
          targetChroma: 0,
          bass: .95,
          dtMs: 130,
          nowMs: now,
        );
        hues.add(state.hue);
      }
      for (var i = 1; i < hues.length; i++) {
        expect((hues[i] - hues[i - 1]).abs(), greaterThanOrEqualTo(59.9),
            reason: 'hue must jump one step per onset, got $hues');
      }
      for (final h in hues) {
        final rem = h % 60;
        expect(rem < .01 || 60 - rem < .01, isTrue,
            reason: 'hue $h must sit on a 60 degree step, got $hues');
      }
    });

    test('no onset holds the step, and the offset stays 0 when the jump is off',
        () {
      final m = motion(hueJumpDeg: 60, beatMinGapMs: 120);
      var state = m.step(
        prev: const AmbientMotionState(),
        targetHue: 100,
        targetLevel: .5,
        targetChroma: 0,
        bass: 0,
        dtMs: 16,
        nowMs: 10000,
      );
      final first = state.hue;
      for (var i = 0; i < 6; i++) {
        state = m.step(
          prev: state,
          targetHue: 100,
          targetLevel: .5,
          targetChroma: 0,
          bass: 0,
          dtMs: 16,
          nowMs: 10000,
        );
      }
      expect(state.hue, closeTo(first, .001));
      expect(state.beatHueOffsetDeg, 0);

      // The continuous mode never accumulates an offset.
      final smooth = motion();
      final s = smooth.step(
        prev: const AmbientMotionState(),
        targetHue: 0,
        targetLevel: .5,
        targetChroma: 0,
        bass: .95,
        dtMs: 16,
        nowMs: 10000,
      );
      expect(s.beatHueOffsetDeg, 0);
    });
  });
}
