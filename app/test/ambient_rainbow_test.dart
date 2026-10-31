import 'package:flutter_test/flutter_test.dart';
import 'package:uni_launcher/model/ambient_light.dart';
import 'package:uni_launcher/model/ambient_motion.dart';

/// The 「五彩」 (rainbow) parameters of [AmbientPalette]: hue span, centroid
/// expansion, chroma cap and hue self-rotation.
///
/// This is the Dart translation of cardesk's `AmbientPaletteRainbowTest.kt`.
/// The three levers each solve one problem, and one without the others only
/// gives "a little more movement":
///
/// 1. **span** (150° → 360°): how far the hue may travel at most;
/// 2. **centroid expansion** (0.20..0.65 → 0..1): whether real music can
///    actually use that span;
/// 3. **chroma cap** (0.22 → 0.32): whether the reds/greens are vivid enough.
///
/// Plus **self-rotation**: when the centroid stops moving (a repeated
/// chorus), time alone pushes the hue around.
void main() {
  const bandCount = 24;

  /// One frame where **only** [loud] has energy.
  List<double> singleBand(int loud, [double value = 0.9]) =>
      List<double>.generate(bandCount, (i) => i == loud ? value : 0);

  /// A "real music" wideband spectrum: a noise floor, one band a bit louder.
  List<double> broadband(int focus, [double base = 0.1, double peak = 1.0]) =>
      List<double>.generate(bandCount, (i) => i == focus ? peak : base);

  double normalize(double hue) {
    var h = hue % 360;
    if (h < 0) h += 360;
    return h;
  }

  /// The covered angle on the circle = 360° − the largest gap.
  double coverage(List<double> hues) {
    final sorted = hues.map(normalize).toList()..sort();
    var maxGap = 0.0;
    for (var i = 0; i < sorted.length; i++) {
      final gap = i == sorted.length - 1
          ? sorted[0] + 360 - sorted[i]
          : sorted[i + 1] - sorted[i];
      if (gap > maxGap) maxGap = gap;
    }
    return 360 - maxGap;
  }

  double shortestDelta(double a, double b) {
    var d = normalize(b - a);
    if (d > 180) d -= 360;
    return d;
  }

  test('the default arguments are bit for bit the old formula', () {
    // Default span=150° and window 0..1 ⇒ the expansion is the identity, so
    // the hue formula is exactly the pre-rainbow one.
    for (var loud = 0; loud < bandCount; loud++) {
      final bands = singleBand(loud);
      final centroid = AmbientPalette.spectralCentroid(bands);
      final expected = normalize(AmbientPalette.hueBandHigh -
          (AmbientPalette.hueBandHigh - AmbientPalette.hueBandLow) * centroid);
      expect(AmbientPalette.centroidHue(bands, 42), closeTo(expected, 1e-4),
          reason: 'band $loud');
      expect(
          AmbientPalette.centroidHue(bands, 42,
              spanDeg: AmbientPalette.hueBandSpan),
          closeTo(expected, 1e-4),
          reason: 'band $loud (explicit span)');
    }
  });

  test('the default window is the identity map', () {
    for (final c in [0.0, 0.2, 0.425, 0.66, 1.0]) {
      expect(AmbientPalette.expandCentroid(c, 0, 1), closeTo(c, 1e-6));
    }
  });

  test('the rainbow window stretches 0.20..0.65 to 0..1', () {
    expect(AmbientPalette.expandCentroid(0.20, 0.20, 0.45), closeTo(0, 1e-5));
    expect(AmbientPalette.expandCentroid(0.65, 0.20, 0.45), closeTo(1, 1e-5));
    expect(AmbientPalette.expandCentroid(0.425, 0.20, 0.45),
        closeTo(0.5, 1e-4));
    // Outside the window it is clamped, never out of range.
    expect(AmbientPalette.expandCentroid(0.05, 0.20, 0.45), closeTo(0, 1e-5));
    expect(AmbientPalette.expandCentroid(0.95, 0.20, 0.45), closeTo(1, 1e-5));
  });

  test('the rainbow parameters cover the whole circle with single bands', () {
    final rainbow = [
      for (var i = 0; i < bandCount; i++)
        AmbientPalette.centroidHue(
          singleBand(i),
          0,
          spanDeg: AmbientPalette.hueSpanMax,
          windowLow: AmbientPalette.rainbowCentroidWindowLow,
          windowSpan: AmbientPalette.rainbowCentroidWindowSpan,
        )
    ];
    final cov = coverage(rainbow);
    expect(cov, greaterThanOrEqualTo(300),
        reason: '24 samples should cover ≥300°, got ${cov.toStringAsFixed(1)}');
  });

  test('the expansion at least doubles the hue travel of a real spectrum', () {
    // Span only: the centroid only moves inside ~0.37..0.63, so the hue
    // walks ~90°.
    final spanOnly = [
      for (var i = 0; i < bandCount; i++)
        AmbientPalette.centroidHue(broadband(i), 0,
            spanDeg: AmbientPalette.hueSpanMax)
    ];
    // With the expansion: the same spectrum now travels >200°.
    final rainbow = [
      for (var i = 0; i < bandCount; i++)
        AmbientPalette.centroidHue(
          broadband(i),
          0,
          spanDeg: AmbientPalette.hueSpanMax,
          windowLow: AmbientPalette.rainbowCentroidWindowLow,
          windowSpan: AmbientPalette.rainbowCentroidWindowSpan,
        )
    ];
    final spanCov = coverage(spanOnly);
    final rainbowCov = coverage(rainbow);
    expect(rainbowCov, greaterThanOrEqualTo(spanCov * 2),
        reason: 'the expansion should lift ${spanCov.toStringAsFixed(1)}° '
            'to more than twice, got ${rainbowCov.toStringAsFixed(1)}°');
    expect(rainbowCov, greaterThanOrEqualTo(180),
        reason: 'the rainbow should still travel ≥180° on real music');
  });

  test('the chroma may rise to 0.32 but the hard cap is 0.40', () {
    final loud = List<double>.filled(bandCount, 1.0);
    // The default cap still stops at 0.22.
    expect(AmbientPalette.chromaTarget(loud, 1),
        lessThanOrEqualTo(AmbientPalette.maxChroma + 1e-5));
    // The rainbow cap really is more vivid (otherwise the reds/greens are
    // grey).
    final rainbow = AmbientPalette.chromaTarget(loud, 1,
        maxChroma: AmbientPalette.rainbowMaxChroma);
    expect(rainbow, greaterThan(AmbientPalette.maxChroma),
        reason: 'the rainbow chroma should be >0.22, got $rainbow');
    expect(rainbow, lessThanOrEqualTo(AmbientPalette.rainbowMaxChroma + 1e-5),
        reason: 'the rainbow chroma should be ≤0.32, got $rainbow');
    // Whoever asks for more is clamped by the hard ceiling.
    expect(AmbientPalette.chromaTarget(loud, 1, maxChroma: 10),
        lessThanOrEqualTo(AmbientPalette.maxChromaHard + 1e-5));
  });

  test('the rotation phase integrates per second and normalizes', () {
    expect(AmbientPalette.rotationPhase(0, 18, 1000), closeTo(18, 1e-4));
    expect(AmbientPalette.rotationPhase(350, 18, 1000), closeTo(8, 1e-4));
    expect(AmbientPalette.rotationPhase(100, 0, 1000), closeTo(100, 1e-4));
    // dt is clamped to 1 s: coming back from the background must not jump
    // dozens of degrees in one frame.
    expect(AmbientPalette.rotationPhase(0, 18, 60000), closeTo(18, 1e-4));
    // The speed is clamped to 30 °/s.
    expect(AmbientPalette.rotationPhase(0, 1000, 1000), closeTo(30, 1e-4));
  });

  test('a minute of self-rotation travels more than 300 degrees', () {
    // Simulate the controller's 60 Hz render: target hue = base + phase,
    // then through the second order motion.
    final motion = AmbientMotion(
      hueTauMs: 240,
      hueMaxDegPerSec: 90,
      hueMaxAccelDegPerSec2: 360,
      attackMs: 40,
      decayMs: 240,
      bassTauMs: 160,
      pulseTauMs: 170,
      pulseGain: 0.35,
      beatFloor: 0.12,
      beatRatio: 1.25,
      beatMinGapMs: 240,
      jumpHoldMs: 0,
      breathAmount: 0.08,
    );
    const dt = 16;
    const rotateDegPerSec = 18.0;
    var state = const AmbientMotionState();
    var phase = 0.0;
    var travel = 0.0;
    var now = 0;
    for (var i = 0; i < 60 * 1000 ~/ dt; i++) {
      phase = AmbientPalette.rotationPhase(phase, rotateDegPerSec, dt);
      final target = AmbientPalette.normalizeHue(200 + phase);
      state = motion.step(
        prev: state,
        targetHue: target,
        targetLevel: 0.6,
        targetChroma: 0.26,
        bass: 0.2,
        dtMs: dt,
        nowMs: now,
        silent: false,
      );
      travel += shortestDelta(state.hue, normalize(200 + phase)).abs();
      now += dt;
    }
    const expected = rotateDegPerSec * 60;
    expect(travel, greaterThanOrEqualTo(300),
        reason: '60 s at 18°/s should travel ≈$expected°, '
            'got ${travel.toStringAsFixed(0)}°');
    expect(travel, greaterThanOrEqualTo(expected * 0.8),
        reason: 'the travel should not fall far behind the target, '
            'got ${travel.toStringAsFixed(0)}°');
  });

  test('the rainbow chroma reaches the lamp (no 0.22 clamp in the motion)', () {
    // The art layer asks for 0.32 when the rainbow preset is selected; the
    // motion layer must only enforce the hard ceiling (0.40). If it clamps
    // back to 0.22 the lamp stays grey no matter what the preset says.
    final motion = AmbientMotion(
      hueTauMs: 240,
      hueMaxDegPerSec: 90,
      hueMaxAccelDegPerSec2: 360,
      attackMs: 40,
      decayMs: 240,
      bassTauMs: 160,
      pulseTauMs: 170,
      pulseGain: 0.35,
      beatFloor: 0.12,
      beatRatio: 1.25,
      beatMinGapMs: 240,
      jumpHoldMs: 0,
      breathAmount: 0.08,
    );
    var state = const AmbientMotionState();
    var now = 0;
    for (var i = 0; i < 200; i++) {
      state = motion.step(
        prev: state,
        targetHue: 200,
        targetLevel: 0.6,
        targetChroma: 0.32,
        bass: 0,
        dtMs: 16,
        nowMs: now,
        silent: false,
      );
      now += 16;
    }
    expect(state.chroma, greaterThan(AmbientPalette.maxChroma),
        reason: 'the rainbow asks for 0.32, the state must not squash it back '
            'to 0.22, got ${state.chroma}');
    expect(state.chroma, lessThanOrEqualTo(AmbientPalette.maxChromaHard));
  });
}
