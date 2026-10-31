import 'package:flutter_test/flutter_test.dart';
import 'package:uni_launcher/model/ambient_light.dart';
import 'package:uni_launcher/model/ambient_presets.dart';

/// The **V2** functions of [AmbientPalette] (spectral centroid, lightness
/// window, decoupled chroma) and the presets.
///
/// This complements the legacy tests: those cover the old chain (the
/// discrete `bassHue`, the linear `brightnessFor`), this one covers the
/// functions that replace them.
void main() {
  const bandCount = 24;

  /// One frame where **only** [loudBand] has energy, the rest is 0.
  ///
  /// The other bands have to be really 0 — a little noise floor would sum
  /// up over 24 bands and pull the centroid back to the middle (that is
  /// "music with a noise floor", not "the energy sits in one band").
  List<double> frame(int loudBand, [double value = 0.9]) =>
      List<double>.generate(bandCount, (i) => i == loudBand ? value : 0);

  // --------------------------------------------------------- spectral centroid

  test('the centroid of equal bands is in the middle', () {
    final bands = List<double>.filled(bandCount, 0.5);
    expect(AmbientPalette.spectralCentroid(bands), closeTo(0.5, 0.02));
  });

  test('the centroid sits near 0 when all the energy is in the lowest band',
      () {
    expect(AmbientPalette.spectralCentroid(frame(0)), lessThan(0.1));
  });

  test('the centroid sits near 1 when all the energy is in the highest band',
      () {
    expect(
        AmbientPalette.spectralCentroid(frame(bandCount - 1)), greaterThan(0.9));
  });

  test('the centroid is continuous and never jumps a band', () {
    // The legacy `bassHue` picks the loudest band, so the hue jumps when
    // the band changes. The centroid has to be continuous: the energy
    // moving from band 0 to band 1 only nudges it.
    final a = frame(0);
    final b = frame(1);
    final d =
        (AmbientPalette.spectralCentroid(a) - AmbientPalette.spectralCentroid(b))
            .abs();
    expect(d, lessThan(0.1), reason: 'the centroid jumped by $d');
  });

  test('the centroid uses the band centre, not the index', () {
    // The centre of the first band is (0 + 0.5) / 24 = 0.0208.
    expect(AmbientPalette.spectralCentroid(frame(0)),
        closeTo(0.5 / bandCount, 0.01));
  });

  test('an empty spectrum has the centroid in the middle', () {
    expect(AmbientPalette.spectralCentroid([]), closeTo(0.5, 0.001));
  });

  // --------------------------------------------------------- centroid to hue

  test('the hue always stays inside the safe band', () {
    // 170..320 degrees (cyan -> blue -> violet -> magenta): the glaring
    // yellow is avoided and 150 degrees of travel are left.
    for (var i = 0; i < bandCount; i++) {
      final hue = AmbientPalette.centroidHue(frame(i), 0);
      var h = hue;
      if (h < AmbientPalette.hueBandLow - 1) h += 360;
      expect(
        h,
        inInclusiveRange(
            AmbientPalette.hueBandLow - 1, AmbientPalette.hueBandHigh + 1),
        reason: 'the hue $hue of band $i is outside the safe band',
      );
    }
  });

  test('the bass leans magenta and the treble leans cyan', () {
    final low = AmbientPalette.centroidHue(frame(0), 0);
    final high = AmbientPalette.centroidHue(frame(bandCount - 1), 0);
    expect(low, greaterThan(280), reason: 'the bass should lean magenta');
    expect(high, lessThan(220), reason: 'the treble should lean cyan');
    expect(low, greaterThan(high));
  });

  test('the low centroid only looks at the first bands', () {
    // A change inside the first eight bands moves the hue; a louder high
    // end must not drag the "follow the bass" mode away.
    final a = frame(2);
    final b = frame(6);
    final hueA = AmbientPalette.lowCentroidHue(a, 0);
    final hueB = AmbientPalette.lowCentroidHue(b, 0);
    expect((hueA - hueB).abs(), greaterThan(1));
  });

  // --------------------------------------------------------- lightness window

  test('below the window only the base light is left', () {
    const floor = 8.0;
    final level = AmbientPalette.levelFromRelative(
        relative: 0, sensitivity: 1.4, floorPercent: floor);
    expect(level, closeTo(floor / 100, 0.001));
  });

  test('a relative level of one is full', () {
    expect(
      AmbientPalette.levelFromRelative(
          relative: 1, sensitivity: 1.4, floorPercent: 8),
      closeTo(1, 0.001),
    );
  });

  test('the lightness rises monotonically with the relative level', () {
    var last = -1.0;
    for (var r = 0.0; r <= 1.0001; r += 0.05) {
      final v = AmbientPalette.levelFromRelative(
          relative: r, sensitivity: 1.4, floorPercent: 8);
      expect(v, greaterThanOrEqualTo(last - 0.0001),
          reason: 'the lightness at $r went from $last to $v');
      last = v;
    }
  });

  test('the lightness of a typical level does not sit at the top', () {
    // This is the constraint behind "the brightness really changes":
    // the legacy `brightnessFor` already reached 0.9 at a typical level,
    // which left a dynamic range of 10 %.
    final level = AmbientPalette.levelFromRelative(
        relative: 0.55, sensitivity: 1.4, floorPercent: 8);
    expect(level, lessThan(0.6));
    expect(level, greaterThan(0.2));
  });

  test('a higher sensitivity makes the quiet parts brighter', () {
    final sensitive = AmbientPalette.levelFromRelative(
        relative: 0.3, sensitivity: 3, floorPercent: 0);
    final dull = AmbientPalette.levelFromRelative(
        relative: 0.3, sensitivity: 0.3, floorPercent: 0);
    expect(sensitive, greaterThan(dull));
  });

  test('the base light survives the window', () {
    // The base light is the breathing floor: the strip may never go dark.
    final level = AmbientPalette.levelFromRelative(
        relative: 0, sensitivity: 1.4, floorPercent: 20);
    expect(level, greaterThanOrEqualTo(0.2 - 0.001));
  });

  // --------------------------------------------------------- perceptual lightness

  test('the perceptual lightness keeps a floor in the dark', () {
    // L = level * 0.92 + 0.04: level 0 gives L = 0.04, not pure black;
    // level 1 gives L = 0.96 — the top keeps 4 % of room as well.
    expect(AmbientPalette.perceptualLightness(0), closeTo(0.04, 0.001));
    expect(AmbientPalette.perceptualLightness(1), closeTo(0.96, 0.001));
    expect(AmbientPalette.perceptualLightness(0), greaterThan(0));
  });

  // --------------------------------------------------------- decoupled chroma

  test('the chroma follows the high frequency transient', () {
    // A loud high end (the cymbals) lifts the chroma higher than a quiet
    // high end — that is the decoupling of the saturation from the hue and
    // the lightness.
    final dull = List<double>.filled(bandCount, 0.1);
    final bright = List<double>.filled(bandCount, 0.1);
    for (var i = bandCount * 2 ~/ 3; i < bandCount; i++) {
      bright[i] = 0.9;
    }
    final cDull = AmbientPalette.chromaTarget(dull, 0.8);
    final cBright = AmbientPalette.chromaTarget(bright, 0.8);
    expect(cBright, greaterThan(cDull));
  });

  test('the chroma never goes over the cap', () {
    final bands = List<double>.filled(bandCount, 1);
    expect(AmbientPalette.chromaTarget(bands, 1),
        lessThanOrEqualTo(AmbientPalette.maxChroma + 0.0001));
  });

  test('a higher saturation setting gives a higher chroma', () {
    final bands = List<double>.filled(bandCount, 0.4);
    expect(AmbientPalette.chromaTarget(bands, 1),
        greaterThan(AmbientPalette.chromaTarget(bands, 0)));
  });

  // --------------------------------------------------------- OKLCH output

  test('the OKLCH output stays between 0 and 255', () {
    for (final h in [0.0, 90.0, 180.0, 270.0]) {
      for (final l in [0.0, 0.5, 1.0]) {
        final c = AmbientPalette.colorOfOklch(h, l, 0.2);
        expect(c.r, inInclusiveRange(0, 255));
        expect(c.g, inInclusiveRange(0, 255));
        expect(c.b, inInclusiveRange(0, 255));
      }
    }
  });

  test('a higher lightness gives a brighter colour', () {
    final dark = AmbientPalette.colorOfOklch(200, 0.2, 0.15);
    final bright = AmbientPalette.colorOfOklch(200, 0.8, 0.15);
    expect(dark.r + dark.g + dark.b, lessThan(bright.r + bright.g + bright.b));
  });

  // --------------------------------------------------------- presets

  group('the presets', () {
    test('all six presets are there', () {
      expect(AmbientPresets.all.length, 6);
      expect(AmbientPresets.names,
          AmbientPresets.all.map((preset) => preset.name).toList());
    });

    test('the preset names are unique', () {
      expect(AmbientPresets.names.toSet().length,
          AmbientPresets.names.length);
    });

    test('a preset is recognised when the parameters match exactly', () {
      for (var index = 0; index < AmbientPresets.all.length; index++) {
        final p = AmbientPresets.all[index];
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
        expect(got, index, reason: '「${p.name}」should be recognised');
      }
    });

    test('a changed parameter matches no preset', () {
      final p = AmbientPresets.balanced;
      final got = AmbientPresets.match(
        attackMs: p.attackMs + 5,
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
      expect(got, -1);
    });

    test('the preset parameters stay inside the legal ranges', () {
      // A preset outside the range would be clamped silently by the
      // settings model, so the page would show a value that is not the one
      // in effect.
      for (final p in AmbientPresets.all) {
        expect(p.attackMs, inInclusiveRange(10, 300));
        expect(p.decayMs, inInclusiveRange(60, 1200));
        expect(p.hueTauMs, inInclusiveRange(60, 1200));
        expect(p.hueMaxDeg, inInclusiveRange(10, 180));
        expect(p.hueMaxAccel, inInclusiveRange(30, 800));
        expect(p.maxDeltaE, inInclusiveRange(0.2, 6.0));
        expect(p.floor, inInclusiveRange(0, 30));
        expect(p.breath, inInclusiveRange(0, 0.4));
        expect(p.saturation, inInclusiveRange(0, 1));
        // The rainbow levers must obey the same ranges as the sliders,
        // otherwise the page would show a value that is not in effect.
        expect(p.hueSpanDeg, inInclusiveRange(150, 360));
        expect(p.centroidWindowLowHundredths, inInclusiveRange(0, 70));
        expect(p.centroidWindowSpanHundredths, inInclusiveRange(10, 100));
        expect(p.hueRotateDegPerSec, inInclusiveRange(0, 30));
        expect(p.maxChromaHundredths, inInclusiveRange(10, 40));
        // The jump levers obey the same ranges as the new sliders.
        expect(p.hueJumpDeg, inInclusiveRange(0, 180));
        expect(p.pulseGainHundredths, inInclusiveRange(0, 200));
        expect(p.beatMinGapMs, inInclusiveRange(80, 600));
      }
    });

    test('the rainbow is as wide as any, the most vivid, only rotating preset',
        () {
      final r = AmbientPresets.rainbow;
      expect(r.hueSpanDeg, 360);
      for (final p in AmbientPresets.all.where((p) => p != r)) {
        // The jump also spans the whole circle, so "widest" is a tie: the
        // point is that no preset is wider than the rainbow.
        expect(p.hueSpanDeg, lessThanOrEqualTo(r.hueSpanDeg),
            reason: '「${p.name}」should not be wider than the rainbow');
        expect(p.hueRotateDegPerSec, 0,
            reason: '「${p.name}」should not rotate');
      }
      expect(r.maxChromaHundredths,
          greaterThan(AmbientPresets.balanced.maxChromaHundredths),
          reason: 'the rainbow should be more vivid than balanced');
      expect(r.centroidWindowSpanHundredths,
          lessThan(AmbientPresets.balanced.centroidWindowSpanHundredths),
          reason: 'the rainbow should narrow the centroid window');
      // All seventeen fields have to match to be recognised as the rainbow.
      expect(
          AmbientPresets.match(
            attackMs: r.attackMs,
            decayMs: r.decayMs,
            hueTauMs: r.hueTauMs,
            hueMaxDeg: r.hueMaxDeg,
            hueMaxAccel: r.hueMaxAccel,
            maxDeltaE: r.maxDeltaE,
            floor: r.floor,
            breath: r.breath,
            saturation: r.saturation,
            hueSpanDeg: r.hueSpanDeg,
            centroidWindowLowHundredths: r.centroidWindowLowHundredths,
            centroidWindowSpanHundredths: r.centroidWindowSpanHundredths,
            hueRotateDegPerSec: r.hueRotateDegPerSec,
            maxChromaHundredths: r.maxChromaHundredths,
            hueJumpDeg: r.hueJumpDeg,
            pulseGainHundredths: r.pulseGainHundredths,
            beatMinGapMs: r.beatMinGapMs,
          ),
          AmbientPresets.all.indexOf(r));
      // Forcing the span back to 150° is no longer the rainbow, so the chip
      // does not stay lit after the user changes the span.
      expect(
          AmbientPresets.match(
            attackMs: r.attackMs,
            decayMs: r.decayMs,
            hueTauMs: r.hueTauMs,
            hueMaxDeg: r.hueMaxDeg,
            hueMaxAccel: r.hueMaxAccel,
            maxDeltaE: r.maxDeltaE,
            floor: r.floor,
            breath: r.breath,
            saturation: r.saturation,
            hueSpanDeg: 150,
            centroidWindowLowHundredths: r.centroidWindowLowHundredths,
            centroidWindowSpanHundredths: r.centroidWindowSpanHundredths,
            hueRotateDegPerSec: r.hueRotateDegPerSec,
            maxChromaHundredths: r.maxChromaHundredths,
            hueJumpDeg: r.hueJumpDeg,
            pulseGainHundredths: r.pulseGainHundredths,
            beatMinGapMs: r.beatMinGapMs,
          ),
          -1);
    });

    test('night driving is more conservative than balanced', () {
      // Night driving: slower changes, a tighter colour difference cap and
      // a lower base light — those three are what "not glaring" means.
      final n = AmbientPresets.night;
      final b = AmbientPresets.balanced;
      expect(n.attackMs, greaterThan(b.attackMs));
      expect(n.decayMs, greaterThan(b.decayMs));
      expect(n.hueTauMs, greaterThan(b.hueTauMs));
      expect(n.hueMaxDeg, lessThan(b.hueMaxDeg));
      expect(n.maxDeltaE, lessThan(b.maxDeltaE));
    });

    test('cyber high contrast is more aggressive than balanced', () {
      final c = AmbientPresets.cyber;
      final b = AmbientPresets.balanced;
      expect(c.attackMs, lessThan(b.attackMs));
      expect(c.decayMs, lessThan(b.decayMs));
      expect(c.hueMaxDeg, greaterThan(b.hueMaxDeg));
      expect(c.hueMaxAccel, greaterThan(b.hueMaxAccel));
      expect(c.saturation, greaterThan(b.saturation));
    });
  });

  // --------------------------------------------------------- the settings model

  group('the settings model', () {
    test('the defaults are the new engine', () {
      const settings = AmbientLightSettings();
      expect(settings.engine, AmbientLightSettings.engineV2);
      expect(settings.zoneChoreo, isFalse,
          reason: 'the zone choreography is off while driving');
    });

    test('every V2 parameter survives a JSON round trip', () {
      const settings = AmbientLightSettings(
        engine: AmbientLightSettings.engineLegacy,
        attackMs: 70,
        decayMs: 520,
        hueTauMs: 420,
        hueMaxDeg: 32,
        hueMaxAccel: 120,
        maxDeltaE: 1.2,
        floor: 5,
        saturation: 0.55,
        breath: 0.16,
        hueSpanDeg: 360,
        centroidWindowLowHundredths: 20,
        centroidWindowSpanHundredths: 45,
        hueRotateDegPerSec: 18,
        maxChromaHundredths: 32,
        zoneChoreo: true,
        zoneDwellMs: 1200,
      );
      final back = AmbientLightSettings.fromJson(settings.toJson());
      expect(back, settings);
    });

    test('the five rainbow fields default to the old look', () {
      const settings = AmbientLightSettings();
      expect(settings.hueSpanDeg, 150);
      expect(settings.centroidWindowLowHundredths, 0);
      expect(settings.centroidWindowSpanHundredths, 100);
      expect(settings.hueRotateDegPerSec, 0);
      expect(settings.maxChromaHundredths, 22);
      // The derived fractions keep the old window/ceiling.
      expect(settings.centroidWindowLow, 0);
      expect(settings.centroidWindowSpan, 1);
      expect(settings.maxChromaValue, closeTo(0.22, 1e-9));
    });

    test('the rainbow fields use the cardesk keys and clamp on read', () {
      final json = const AmbientLightSettings().toJson();
      expect(json['ambient_hue_span_deg'], 150);
      expect(json['ambient_centroid_low'], 0);
      expect(json['ambient_centroid_span'], 100);
      expect(json['ambient_hue_rotate'], 0);
      expect(json['ambient_max_chroma'], 22);
      final clamped = AmbientLightSettings.fromJson({
        'ambient_hue_span_deg': 999,
        'ambient_centroid_low': 99,
        'ambient_centroid_span': 1,
        'ambient_hue_rotate': 999,
        'ambient_max_chroma': 999,
      });
      expect(clamped.hueSpanDeg, 360);
      expect(clamped.centroidWindowLowHundredths, 70);
      expect(clamped.centroidWindowSpanHundredths, 10);
      expect(clamped.hueRotateDegPerSec, 30);
      expect(clamped.maxChromaHundredths, 40);
    });

    test('the engine switch does not touch the other parameters', () {
      const settings = AmbientLightSettings(attackMs: 70, hueMaxDeg: 32);
      final legacy = settings.copyWith(
          engine: AmbientLightSettings.engineLegacy);
      expect(legacy.engine, AmbientLightSettings.engineLegacy);
      expect(legacy.attackMs, 70);
      expect(legacy.hueMaxDeg, 32);
    });
  });
}
