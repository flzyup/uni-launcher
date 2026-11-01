import 'dart:math' as math;

/// The **perceptual colour space** helpers of the ambient light.
///
/// Pure functions, no Flutter and no platform API, so the whole curve is
/// covered by unit tests without a device.
///
/// ## Why not HSV plus a linear RGB scale
///
/// The old path was "HSV for the hue, then scale the RGB linearly". Two
/// problems:
///
/// 1. **A linear scale is not perceptually uniform.** At V=0.1 the strip gets
///    25/255, which is nearly black on a physical LED. The quiet passages
///    therefore look like "the light is off", and the visible brightness
///    range is squashed.
/// 2. **An HSV hue interpolation crosses the grey axis.** Going from 50° to
///    70° drops the saturation on the way, so the colour visibly fades and
///    comes back. That is a kind of harshness too.
///
/// OKLab (Ottosson) is perceptually uniform: a change in L is a uniform
/// change in perceived brightness, so the brightness range is linear on the
/// actual LEDs.
///
/// ## What CIEDE2000 is for
///
/// Limiting the perceived difference between two neighbouring frames. The
/// Euclidean RGB distance is not proportional to what the eye sees (deep blue
/// to light blue is a large RGB distance but barely a visible change).
/// Delta E00 is the formula that is closest to human perception, so it is
/// the right yardstick for "how much may one frame jump".
///
/// Reference: Ottosson, B. (2020). A perceptual color space for image
/// processing.
class AmbientColorSpace {
  AmbientColorSpace._();

  // ------------------------------------------------------------------ sRGB

  /// An sRGB component (0..1) to linear light.
  static double srgbToLinear(double c) =>
      c <= 0.04045 ? c / 12.92 : math.pow((c + 0.055) / 1.055, 2.4).toDouble();

  /// Linear light to an sRGB component (0..1).
  static double linearToSrgb(double c) =>
      c <= 0.0031308 ? c * 12.92 : 1.055 * math.pow(c, 1 / 2.4) - 0.055;

  // ------------------------------------------------------------------ OKLab

  /// Linear RGB to OKLab. Returns `(L, a, b)`.
  static (double, double, double) linearRgbToOklab(
      double r, double g, double b) {
    final l = 0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b;
    final m = 0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b;
    final s = 0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b;
    final l_ = _cbrt(l);
    final m_ = _cbrt(m);
    final s_ = _cbrt(s);
    return (
      0.2104542553 * l_ + 0.7936177850 * m_ - 0.0040720468 * s_,
      1.9779984951 * l_ - 2.4285922050 * m_ + 0.4505937099 * s_,
      0.0259040371 * l_ + 0.7827717662 * m_ - 0.8086757660 * s_,
    );
  }

  /// OKLab to linear RGB. **Not clamped**: the caller converges the gamut.
  static (double, double, double) oklabToLinearRgb(
      double l, double a, double b) {
    final l_ = l + 0.3963377774 * a + 0.2158037573 * b;
    final m_ = l - 0.1055613458 * a - 0.0638541728 * b;
    final s_ = l - 0.0894841775 * a - 1.2914855480 * b;
    final ll = l_ * l_ * l_;
    final mm = m_ * m_ * m_;
    final ss = s_ * s_ * s_;
    return (
      4.0767416621 * ll - 3.3077115913 * mm + 0.2309699292 * ss,
      -1.2684380046 * ll + 2.6097574011 * mm - 0.3413193965 * ss,
      -0.0041960863 * ll - 0.7034186147 * mm + 1.7076147010 * ss,
    );
  }

  // ------------------------------------------------------------------ CIELAB

  /// Linear RGB to CIELAB (D65, 8 bit components: 0..255).
  static (double, double, double) rgbToLab(int r, int g, int b) {
    final lr = srgbToLinear(r / 255);
    final lg = srgbToLinear(g / 255);
    final lb = srgbToLinear(b / 255);
    final x = (lr * 0.4124564 + lg * 0.3575761 + lb * 0.1804375) / 0.95047;
    final y = lr * 0.2126729 + lg * 0.7151522 + lb * 0.0721750;
    final z = (lr * 0.0193339 + lg * 0.1191920 + lb * 0.9503041) / 1.08883;
    const e = 216 / 24389;
    const k = 24389 / 27;
    final fx = _labF(x, e, k);
    final fy = _labF(y, e, k);
    final fz = _labF(z, e, k);
    return (116 * fy - 16, 500 * (fx - fy), 200 * (fy - fz));
  }

  static double _labF(double t, double e, double k) =>
      t > e ? _cbrt(t) : (k * t + 16) / 116;

  // ------------------------------------------------------------------ CIEDE2000

  /// The CIEDE2000 colour difference (Delta E00).
  ///
  /// Reading: 0 is the same colour, about 1 is just noticeable, 2 to 3 is
  /// clearly different, above 5 is very different.
  ///
  /// Implemented after Sharma, Wu and Dalal (2005).
  static double deltaE00(
    (double, double, double) lab1,
    (double, double, double) lab2,
  ) {
    final (l1, a1, b1) = lab1;
    final (l2, a2, b2) = lab2;

    final c1 = math.sqrt(a1 * a1 + b1 * b1);
    final c2 = math.sqrt(a2 * a2 + b2 * b2);
    final cBar = (c1 + c2) / 2;
    final cBar7 = math.pow(cBar, 7).toDouble();
    // 25^7
    final g = 0.5 * (1 - math.sqrt(cBar7 / (cBar7 + 6103515625)));

    final a1p = (1 + g) * a1;
    final a2p = (1 + g) * a2;
    final c1p = math.sqrt(a1p * a1p + b1 * b1);
    final c2p = math.sqrt(a2p * a2p + b2 * b2);

    var h1p = c1p == 0 ? 0.0 : _hueAngle(b1, a1p);
    var h2p = c2p == 0 ? 0.0 : _hueAngle(b2, a2p);

    final dLp = l2 - l1;
    final dCp = c2p - c1p;

    var dhp = 0.0;
    if (c1p * c2p != 0) {
      dhp = h2p - h1p;
      if (dhp > 180) {
        dhp -= 360;
      } else if (dhp < -180) {
        dhp += 360;
      }
    }
    final dHp = 2 * math.sqrt(c1p * c2p) * math.sin(dhp / 2 * math.pi / 180);

    final lBarP = (l1 + l2) / 2;
    final cBarP = (c1p + c2p) / 2;

    var hBarP = h1p + h2p;
    if (c1p * c2p != 0) {
      if ((h1p - h2p).abs() > 180) {
        hBarP += (h1p + h2p < 360) ? 360 : -360;
      }
      hBarP /= 2;
    }

    final t = 1 -
        0.17 * math.cos((hBarP - 30) * math.pi / 180) +
        0.24 * math.cos(2 * hBarP * math.pi / 180) +
        0.32 * math.cos((3 * hBarP + 6) * math.pi / 180) -
        0.20 * math.cos((4 * hBarP - 63) * math.pi / 180);

    final dTheta = 30 * math.exp(-math.pow((hBarP - 275) / 25, 2));
    final cBarP7 = math.pow(cBarP, 7).toDouble();
    final rc = 2 * math.sqrt(cBarP7 / (cBarP7 + 6103515625));
    final rt = -rc * math.sin(2 * dTheta * math.pi / 180);

    final sl = 1 + (0.015 * math.pow(lBarP - 50, 2)) /
        math.sqrt(20 + math.pow(lBarP - 50, 2));
    final sc = 1 + 0.045 * cBarP;
    final sh = 1 + 0.015 * cBarP * t;

    final tl = dLp / sl;
    final tc = dCp / sc;
    final th = dHp / sh;
    return math.sqrt(tl * tl + tc * tc + th * th + rt * tc * th);
  }

  static double _hueAngle(double b, double a) {
    var h = math.atan2(b, a) * 180 / math.pi;
    if (h < 0) h += 360;
    return h;
  }

  // ------------------------------------------------------------------ OKLCH to RGB

  /// OKLCH to sRGB (0..255).
  ///
  /// ## Gamut convergence: why not "clip the RGB"
  ///
  /// Clamping the out of range linear RGB to 0..1 **shifts the hue** (a very
  /// saturated blue becomes some undefined dark colour). The right way is to
  /// **lower the chroma** until the colour fits: the hue and the lightness
  /// stay, only a little vividness is given up.
  ///
  /// * [l] the perceptual lightness, 0..1
  /// * [c] the chroma (OKLab C runs roughly 0..0.4)
  /// * [h] the hue angle in degrees
  static (int, int, int) oklchToRgb(double l, double c, double h) {
    final rad = h * math.pi / 180;
    final cosH = math.cos(rad);
    final sinH = math.sin(rad);

    (double, double, double) linear(double chroma) =>
        oklabToLinearRgb(l, chroma * cosH, chroma * sinH);

    bool inGamut((double, double, double) v) =>
        v.$1 >= -_eps &&
        v.$1 <= 1 + _eps &&
        v.$2 >= -_eps &&
        v.$2 <= 1 + _eps &&
        v.$3 >= -_eps &&
        v.$3 <= 1 + _eps;

    var v = linear(c);
    if (!inGamut(v)) {
      // Bisect the chroma: 16 steps is plenty (the chroma resolution is
      // 0.4/65536, far below the 8 bit resolution).
      var lo = 0.0;
      var hi = c;
      (double, double, double)? best;
      for (var i = 0; i < 16; i++) {
        final mid = (lo + hi) / 2;
        final t = linear(mid);
        if (inGamut(t)) {
          best = t;
          lo = mid;
        } else {
          hi = mid;
        }
      }
      v = best ?? linear(0);
    }
    return (_to8bit(v.$1), _to8bit(v.$2), _to8bit(v.$3));
  }

  static const double _eps = 0.001;

  static int _to8bit(double linear) {
    final s = linearToSrgb(linear.clamp(0.0, 1.0));
    return (s * 255 + 0.5).floor().clamp(0, 255);
  }

  // ------------------------------------------------------------------ Delta E00 speed limit

  /// Limits the candidate colour so it stays within [maxDeltaE] of the
  /// previous frame.
  ///
  /// ## How
  ///
  /// 1. Both colours go to CIELAB;
  /// 2. the Delta E00 is computed;
  /// 3. if it is over the limit the candidate is pulled back proportionally:
  ///    `k = 1 - (maxDeltaE / deltaE) * 0.5`, and the result is
  ///    `candidate * (1 - k) + previous * k`, interpolated in **OKLab**
  ///    (perceptually uniform, so the interpolation does not shift the hue)
  ///    and converted back to 8 bit sRGB.
  ///
  /// ## Why the factor 0.5
  ///
  /// A linear pull back lands exactly on the limit (Delta E equals maxDeltaE),
  /// but that is the **mathematical** limit: on the car every frame sitting
  /// on the limit still looks like a jump. The 0.5 leaves half the budget
  /// unused, so the real per frame difference is about half the limit and the
  /// light reads as a flow.
  ///
  /// ## Why OKLab and not RGB
  ///
  /// A direct RGB interpolation **crosses the grey axis** when the two ends
  /// differ a lot in hue, so the middle frame visibly fades. OKLab is
  /// perceptually uniform, so the perceived path is a straight line.
  ///
  /// Returns the limited colour; when no limiting is needed the candidate is
  /// returned unchanged.
  static (int, int, int) limitByDeltaE(
    int prevR,
    int prevG,
    int prevB,
    int curR,
    int curG,
    int curB,
    double maxDeltaE,
  ) {
    if (maxDeltaE <= 0) return (curR, curG, curB);
    final prevLab = rgbToLab(prevR, prevG, prevB);
    final curLab = rgbToLab(curR, curG, curB);
    final de = deltaE00(prevLab, curLab);
    if (de <= maxDeltaE) return (curR, curG, curB);
    final k = (1 - (maxDeltaE / de) * 0.5).clamp(0.0, 1.0);
    // The result is `candidate * (1 - k) + previous * k` (a bigger k means
    // closer to the previous frame). The argument order matters: swapped, it
    // would "barely pull back" and the limiter would be pointless.
    return lerpRgb(curR, curG, curB, prevR, prevG, prevB, k);
  }

  // ------------------------------------------------------------------ interpolation

  /// Interpolates two 8 bit sRGB colours in **OKLab**.
  ///
  /// ## Why not in RGB directly
  ///
  /// A direct RGB interpolation **crosses the grey axis**: when the two ends
  /// differ a lot in hue, the middle frame fades visibly, and the eye sees
  /// the colour bleach and come back. That is exactly the harshness this
  /// work is about.
  ///
  /// OKLab is perceptually uniform, so the perceived path is a straight line:
  /// the middle frame neither fades nor shifts hue.
  ///
  /// [t] 0 takes a, 1 takes b.
  static (int, int, int) lerpRgb(
    int ar,
    int ag,
    int ab,
    int br,
    int bg,
    int bb,
    double t,
  ) {
    final k = t.clamp(0.0, 1.0);
    final a = linearRgbToOklab(
        srgbToLinear(ar / 255), srgbToLinear(ag / 255), srgbToLinear(ab / 255));
    final b = linearRgbToOklab(
        srgbToLinear(br / 255), srgbToLinear(bg / 255), srgbToLinear(bb / 255));
    final l = a.$1 + (b.$1 - a.$1) * k;
    final aa = a.$2 + (b.$2 - a.$2) * k;
    final bb2 = a.$3 + (b.$3 - a.$3) * k;
    final rgb = oklabToLinearRgb(l, aa, bb2);
    return (_to8bit(rgb.$1), _to8bit(rgb.$2), _to8bit(rgb.$3));
  }

  // ------------------------------------------------------------------ dither

  /// The **dither** of the 8 bit quantisation.
  ///
  /// ## Why it is needed
  ///
  /// The LEDs are 8 bit. In the dark, RGB going from 30 to 31 is a visible
  /// jump, and in a slowly changing scene that shows up as banding, which is
  /// one of the kinds of harshness.
  ///
  /// A **triangular** noise of about plus or minus one LSB breaks the steps
  /// up: the noise on one pixel is invisible, but the whole gradient becomes
  /// a smooth transition.
  ///
  /// ## Why rounding and not truncating
  ///
  /// The triangular noise is symmetric on (-1, 1):
  /// - truncating gives only `v` or `v - 1`, and the mean is **half a step
  ///   too dark** (and there are only two values, so the banding is barely
  ///   broken up);
  /// - rounding gives `v - 1`, `v` and `v + 1` with a 1:2:1 ratio, which is
  ///   **unbiased**.
  ///
  /// That bias matters in the dark: half a step is visible on a black LED.
  ///
  /// [rand] the random source (0..1); null uses [math.Random].
  static int dither(double value, [double Function()? rand]) {
    final r = rand ?? _defaultRandom;
    final n = r() + r() - 1;
    return (value + n).round().clamp(0, 255);
  }

  static final math.Random _random = math.Random();

  static double _defaultRandom() => _random.nextDouble();

  // ------------------------------------------------------------------ helpers

  /// The cube root, for negative values too.
  ///
  /// `dart:math` has no `cbrt`, and the negative branch is needed because
  /// OKLab takes the cube root of a linear value that can be negative.
  static double _cbrt(double x) {
    if (x == 0) return 0;
    final s = x < 0 ? -1.0 : 1.0;
    return s * math.pow(x.abs(), 1 / 3).toDouble();
  }
}
