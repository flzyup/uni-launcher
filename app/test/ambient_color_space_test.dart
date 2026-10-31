import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:uni_launcher/model/ambient_color_space.dart';

/// [AmbientColorSpace] unit tests (pure functions, no device).
///
/// Three things are checked:
/// 1. **CIEDE2000 is computed correctly** — against the standard test data
///    of Sharma, Wu and Dalal (2005);
/// 2. **The OKLCH round trip keeps the information** — back to RGB and back
///    again, L should barely move;
/// 3. **The gamut converges without a hue shift** — the chroma is pushed
///    down instead of clipping the RGB channels.
void main() {
  // ------------------------------------------------------------- CIEDE2000

  test('the same colour has no difference', () {
    const lab = (50.0, 2.5, 0.0);
    expect(AmbientColorSpace.deltaE00(lab, lab), closeTo(0, 0.0001));
  });

  test('CIEDE2000 matches the standard test data', () {
    // The test data of the Sharma, Wu and Dalal (2005) paper.
    // These are the combinations where both the chroma and the hue differ,
    // which is where a wrong formula shows up first.
    const cases = <(double, double, double, double, double, double, double)>[
      (50.0000, 2.6772, -79.7751, 50.0000, 0.0000, -82.7485, 2.0425),
      (50.0000, -1.3802, -84.2814, 50.0000, 0.0000, -82.7485, 1.0000),
      (50.0000, 2.5000, 0.0000, 50.0000, 0.0000, -2.5000, 4.3065),
      (50.0000, 2.5000, 0.0000, 73.0000, 25.0000, -18.0000, 27.1492),
      (50.0000, 2.5000, 0.0000, 50.0000, 3.1736, 0.5854, 1.0000),
    ];
    for (final c in cases) {
      final got = AmbientColorSpace.deltaE00(
        (c.$1, c.$2, c.$3),
        (c.$4, c.$5, c.$6),
      );
      expect(got, closeTo(c.$7, 0.0001), reason: 'expected ${c.$7}, got $got');
    }
  });

  test('CIEDE2000 is symmetric', () {
    const a = (40.0, 12.0, -30.0);
    const b = (70.0, -5.0, 20.0);
    expect(
      AmbientColorSpace.deltaE00(a, b),
      closeTo(AmbientColorSpace.deltaE00(b, a), 0.0001),
    );
  });

  // ------------------------------------------------------------- OKLCH round trip

  test('OKLCH to RGB and back keeps the lightness', () {
    for (final h in [0.0, 45.0, 120.0, 200.0, 270.0, 330.0]) {
      for (final l in [0.3, 0.5, 0.7]) {
        final (r, g, b) = AmbientColorSpace.oklchToRgb(l, 0.12, h);
        final back = AmbientColorSpace.linearRgbToOklab(
          AmbientColorSpace.srgbToLinear(r / 255),
          AmbientColorSpace.srgbToLinear(g / 255),
          AmbientColorSpace.srgbToLinear(b / 255),
        );
        expect((back.$1 - l).abs(), lessThan(0.03),
            reason: 'hue $h lightness $l drifted to ${back.$1}');
      }
    }
  });

  test('the gamut converges by chroma, not by clipping RGB', () {
    // A chroma of 0.4 is far beyond what sRGB can express — it has to
    // converge. The result stays **inside** the gamut and is still a
    // colourful colour (not some odd dark tone).
    final (r, g, b) = AmbientColorSpace.oklchToRgb(0.6, 0.4, 30);
    expect(r, inInclusiveRange(0, 255));
    expect(g, inInclusiveRange(0, 255));
    expect(b, inInclusiveRange(0, 255));
    expect(max(r, max(g, b)) - min(r, min(g, b)), greaterThan(30),
        reason: 'it should not be pushed to grey ($r/$g/$b)');
  });

  test('a chroma of zero is a grey ramp', () {
    final (r, g, b) = AmbientColorSpace.oklchToRgb(0.5, 0, 200);
    expect(max(r, max(g, b)) - min(r, min(g, b)), lessThanOrEqualTo(1));
  });

  // ------------------------------------------------------------- interpolation

  test('the ends of the interpolation are the ends', () {
    final a = AmbientColorSpace.lerpRgb(10, 20, 30, 200, 100, 50, 0);
    expect(a.$1, 10);
    expect(a.$2, 20);
    expect(a.$3, 30);
    final b = AmbientColorSpace.lerpRgb(10, 20, 30, 200, 100, 50, 1);
    expect(b.$1, 200);
    expect(b.$2, 100);
    expect(b.$3, 50);
  });

  test('the middle of the interpolation keeps the colour', () {
    // Two colours with a very different hue: the middle frame still has to
    // be a colour **between** the two — it must not turn grey.
    final mid = AmbientColorSpace.lerpRgb(255, 0, 0, 0, 0, 255, 0.5);
    final lab = AmbientColorSpace.rgbToLab(mid.$1, mid.$2, mid.$3);
    final chroma = sqrt(lab.$2 * lab.$2 + lab.$3 * lab.$3);
    expect(chroma, greaterThan(30), reason: 'the middle must not be grey');
  });

  // ------------------------------------------------------------- Delta E00 limit

  test('the limited colour stays within the cap of the previous frame', () {
    const maxDe = 1.8;
    var prev = (0, 0, 0);
    var prevLab = AmbientColorSpace.rgbToLab(0, 0, 0);
    // A walk from pure black to pure white — every frame has to be limited.
    for (var i = 0; i <= 255; i++) {
      final limited =
          AmbientColorSpace.limitByDeltaE(prev.$1, prev.$2, prev.$3, i, i, i, maxDe);
      final lab = AmbientColorSpace.rgbToLab(limited.$1, limited.$2, limited.$3);
      final de = AmbientColorSpace.deltaE00(prevLab, lab);
      expect(de, lessThanOrEqualTo(maxDe + 0.05),
          reason: 'frame $i differs by $de, over the cap $maxDe');
      prev = limited;
      prevLab = lab;
    }
  });

  test('a colour within the cap is returned unchanged', () {
    final same =
        AmbientColorSpace.limitByDeltaE(10, 20, 30, 10, 20, 30, 1.8);
    expect(same.$1, 10);
    expect(same.$2, 20);
    expect(same.$3, 30);
  });

  // ------------------------------------------------------------- dither

  test('the dither stays within one step', () {
    // Triangular noise: r() + r() - 1 is in (-1, 1).
    for (var i = 0; i < 500; i++) {
      final out = AmbientColorSpace.dither(128, () => Random().nextDouble());
      expect(out, inInclusiveRange(127, 129));
    }
  });

  test('the dither breaks up the steps', () {
    // The same input has to produce several outputs, otherwise the steps
    // are still there. Triangular noise plus rounding gives v-1 / v / v+1
    // with a probability of 1:2:1.
    final outs = <int>{};
    final random = Random(7);
    for (var i = 0; i < 500; i++) {
      outs.add(AmbientColorSpace.dither(100, () => random.nextDouble()));
    }
    expect(outs.length, 3, reason: 'the dither should give three values: $outs');
  });

  test('the dither is unbiased', () {
    // Half a step of bias is visible near black, so the mean has to sit on
    // the input value instead of half a step below it.
    var sum = 0;
    final random = Random(11);
    const n = 2000;
    for (var i = 0; i < n; i++) {
      sum += AmbientColorSpace.dither(100, () => random.nextDouble());
    }
    final mean = sum / n;
    expect((mean - 100).abs(), lessThan(0.15));
  });
}
