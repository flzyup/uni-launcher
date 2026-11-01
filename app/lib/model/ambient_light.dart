import 'dart:math' as math;

import 'ambient_color_space.dart';

/// A colour the ambient strip can show: RGB plus an independent brightness.
///
/// The head unit drives one LED strip with a shared brightness level, so the
/// brightness must stay separate from the colour. Folding it into the RGB
/// would make it impossible to dim the strip without shifting its hue.
class AmbientColor {
  final int r, g, b, brightness;

  const AmbientColor(this.r, this.g, this.b, this.brightness);

  /// Packed `0xRRGGBB`, the encoding the vendor SDK expects.
  int get packed =>
      ((r.clamp(0, 255)) << 16) |
      ((g.clamp(0, 255)) << 8) |
      (b.clamp(0, 255)).clamp(0, 255);

  /// `#RRGGBB` for diagnostics and the settings preview.
  String get hex => '#${r.clamp(0, 255).toRadixString(16).padLeft(2, '0')}'
      '${g.clamp(0, 255).toRadixString(16).padLeft(2, '0')}'
      '${b.clamp(0, 255).toRadixString(16).padLeft(2, '0')}';

  @override
  bool operator ==(Object other) =>
      other is AmbientColor &&
      other.r == r &&
      other.g == g &&
      other.b == b &&
      other.brightness == brightness;

  @override
  int get hashCode => Object.hash(r, g, b, brightness);

  @override
  String toString() => 'AmbientColor($hex, brightness: $brightness)';
}

/// Spectrum to colour mapping. Pure functions only, so the whole curve is
/// covered by unit tests without an Android device or a running FFT.
///
/// Three colour modes:
///
/// | mode | hue source | brightness source |
/// | --- | --- | --- |
/// | [AmbientPalette.modeBass] follow the bass | the loudest low band | bass energy |
/// | [AmbientPalette.modeSpectrum] follow the spectrum | circular energy weighted average | overall level |
/// | [AmbientPalette.modeFixed] fixed colour | the configured hue | overall level |
///
/// Following the bass is the common music-ambience behaviour: the strip jumps
/// to the colour of the band that just hit. Following the spectrum reads more
/// like a rainbow flowing with the track.
///
/// Hue is a circle: 359 degrees and 1 degree are 2 degrees apart, but an
/// arithmetic mean returns 180 degrees (green) for that pair. Every average
/// here is therefore a circular mean over cos/sin.
class AmbientPalette {
  /// Follow the bass.
  static const int modeBass = 0;

  /// Follow the whole spectrum.
  static const int modeSpectrum = 1;

  /// Fixed colour.
  static const int modeFixed = 2;

  /// Mode labels, in mode order.
  static const List<String> modeLabels = ['跟随低频', '跟随频谱', '固定色'];

  /// Fixed hue presets (hue to label).
  static const List<(double, String)> fixedColors = [
    (30, '橙'),
    (0, '红'),
    (330, '粉'),
    (280, '紫'),
    (210, '蓝'),
    (180, '青'),
    (120, '绿'),
  ];

  /// Fixed hue preset labels.
  static List<String> get fixedColorLabels =>
      fixedColors.map((entry) => entry.$2).toList(growable: false);

  /// The lowest bands count as bass. The native spectrum uses 24 logarithmic
  /// bands from 60 Hz, so four bands cover roughly 60 Hz to 150 Hz: the kick
  /// drum fundamental.
  static const int bassBands = 4;

  /// Lower bound for the sensitivity curve exponent.
  static const double minSensitivity = 0.3;

  /// Upper bound for the sensitivity curve exponent.
  static const double maxSensitivity = 3;

  /// Colour saturation. Fixed: the ambient strip is a set of LEDs, and a
  /// washed out colour looks dirty on them.
  static const double saturation = 0.85;

  /// Hue of the intensity fallback when the audio is quiet.
  static const double intensityHueCold = 260;

  /// Hue of the intensity fallback when the audio is loud.
  static const double intensityHueWarm = 20;

  /// Tolerance for "two bands read exactly the same energy".
  static const double degenerateEpsilon = 0.02;

  /// Maps one spectrum frame to a colour.
  ///
  /// The RGB channels carry the full value colour and the brightness stays in
  /// its own field. [scaleByBrightness] is what turns that brightness into a
  /// visible dimming; the motion layer uses [colorOf] instead, which does
  /// both in one step.
  ///
  /// [bands] are normalised band energies (0..1), [level] is the overall
  /// level (0..1). [fallbackHue] keeps the previous hue when the frame is
  /// silent, so the strip does not jump around while nothing plays.
  static AmbientColor colorFrom({
    required List<double> bands,
    required double level,
    required int mode,
    required double fixedHue,
    required double sensitivity,
    required int minBrightness,
    required int maxBrightness,
    double fallbackHue = 0,
  }) {
    final hue = targetHue(
      bands: bands,
      mode: mode,
      fixedHue: fixedHue,
      fallbackHue: fallbackHue,
    );
    final brightness = targetLevel(
      bands: bands,
      level: level,
      mode: mode,
      sensitivity: sensitivity,
      minBrightness: minBrightness,
      maxBrightness: maxBrightness,
    );
    final rgb = hsvToRgb(hue, saturation, 1);
    return AmbientColor(rgb[0], rgb[1], rgb[2], brightness);
  }

  /// The target hue (0..360).
  ///
  /// Split out from [colorFrom] so the motion layer can smooth the hue
  /// itself. Smoothing an RGB triple and converting it back to a hue loses
  /// precision, and the hue is what actually moves.
  static double targetHue({
    required List<double> bands,
    required int mode,
    required double fixedHue,
    double fallbackHue = 0,
  }) {
    if (mode == modeSpectrum) return spectrumHue(bands, fallbackHue);
    if (mode == modeFixed) return normalizeHue(fixedHue);
    return bassHue(bands, fallbackHue);
  }

  /// The target brightness (0..100).
  ///
  /// The source follows the colour mode: the overall level for the spectrum
  /// and fixed modes, the bass energy for the bass mode, so a kick lights the
  /// strip up right away.
  static int targetLevel({
    required List<double> bands,
    required double level,
    required int mode,
    required double sensitivity,
    required int minBrightness,
    required int maxBrightness,
  }) {
    final lo = minBrightness.clamp(0, 100);
    final hi = maxBrightness.clamp(0, 100);
    final source =
        (mode == modeSpectrum || mode == modeFixed) ? level : bassEnergy(bands);
    return brightnessFor(source, sensitivity, lo, hi);
  }

  /// Builds the colour from a hue and a brightness.
  ///
  /// The brightness scales the whole colour, so the loud and quiet parts of
  /// the music show as a continuous change in brightness rather than a step.
  static AmbientColor colorOf(double hue, int brightness,
      [double? colorSaturation]) {
    final rgb =
        hsvToRgb(hue, (colorSaturation ?? saturation).clamp(0.0, 1.0), 1);
    final b = brightness.clamp(0, 100);
    return scaleByBrightness(AmbientColor(rgb[0], rgb[1], rgb[2], b));
  }

  /// Bass energy: the loudest of the lowest [bassBands] bands.
  static double bassEnergy(List<double> bands) {
    if (bands.isEmpty) return 0;
    final n = math.min(bassBands, bands.length);
    var peak = 0.0;
    for (var i = 0; i < n; i++) {
      if (bands[i] > peak) peak = bands[i];
    }
    return peak;
  }

  /// Bass mode hue: the hue of the loudest low band.
  static double bassHue(List<double> bands, double fallbackHue) {
    if (bands.isEmpty) return normalizeHue(fallbackHue);
    final n = math.min(bassBands, bands.length);
    var best = 0;
    var bestValue = 0.0;
    for (var i = 0; i < n; i++) {
      if (bands[i] > bestValue) {
        bestValue = bands[i];
        best = i;
      }
    }
    if (bestValue <= 0) return normalizeHue(fallbackHue);
    // The spectrum cannot resolve the low range: do not pretend it has
    // information.
    //
    // With too few capture points (512 at 44.1 kHz means an 86 Hz bin) the
    // four low bands all land in the same bin, so their powers are always
    // equal and "the loudest band" is always band zero. The hue would be
    // stuck at 0 degrees (red) and the bass energy would be saturated.
    //
    // Pitch to hue is then fake information, so the bass *intensity* maps to
    // the hue instead: quiet is deep violet, loud is orange red. A coarse
    // but real curve beats a curve that is stuck and looks like silence.
    if (isBassUnresolvable(bands, n)) return intensityHue(bestValue);
    return hueForBand(best, bands.length);
  }

  /// Whether the low bands cannot be told apart.
  ///
  /// The test is that the first [count] bands carry the *same* energy
  /// (within [degenerateEpsilon]) and that energy is not zero. Zero means
  /// "silence", which is a different case.
  ///
  /// Equal energies mean those bands read the same FFT bins, so the hardware
  /// cannot resolve that range at all.
  static bool isBassUnresolvable(List<double> bands, [int count = bassBands]) {
    final n = math.min(count, bands.length);
    if (n <= 1) return false;
    final first = bands[0];
    if (first <= 0) return false;
    for (var i = 1; i < n; i++) {
      if ((bands[i] - first).abs() > degenerateEpsilon) return false;
    }
    return true;
  }

  /// Bass intensity to hue, used when the spectrum cannot resolve the bass.
  ///
  /// Quiet (0) is deep violet at 260 degrees, loudest (1) is orange red at
  /// 20 degrees. The interpolation is linear, so the middle runs through
  /// blue, cyan and green, which matches the intuition that quiet is cool
  ///  and loud is warm.
  static double intensityHue(double level) {
    final t = level.clamp(0.0, 1.0);
    return normalizeHue(
        intensityHueCold - (intensityHueCold - intensityHueWarm) * t);
  }

  /// Spectrum mode hue: circular mean weighted by band energy.
  static double spectrumHue(List<double> bands, double fallbackHue) {
    if (bands.isEmpty) return normalizeHue(fallbackHue);
    var sumWeight = 0.0, sumX = 0.0, sumY = 0.0;
    for (var i = 0; i < bands.length; i++) {
      final weight = bands[i];
      if (weight <= 0) continue;
      final radians = hueForBand(i, bands.length) * math.pi / 180;
      sumX += weight * math.cos(radians);
      sumY += weight * math.sin(radians);
      sumWeight += weight;
    }
    if (sumWeight <= 0.0001) return normalizeHue(fallbackHue);
    return normalizeHue(math.atan2(sumY, sumX) * 180 / math.pi);
  }

  /// The hue of band [index] out of [count] (0..360, low bands lean red and
  /// high bands lean violet).
  static double hueForBand(int index, int count) {
    if (count <= 0) return 0;
    return normalizeHue(360 * index / count);
  }

  /// Level to brightness: `min + (max - min) * level^(1/sensitivity)`.
  ///
  /// Sensitivity 1 is linear. Above 1 the quiet parts light up too and the
  /// strip keeps up with the music; below 1 only loud passages light it.
  static int brightnessFor(double level, double sensitivity, int min, int max) {
    final lo = min.clamp(0, 100);
    final hi = max.clamp(0, 100);
    if (hi <= lo) return lo;
    final s = sensitivity.clamp(minSensitivity, maxSensitivity);
    final t = level.clamp(0.0, 1.0);
    final curve = t <= 0 ? 0.0 : math.pow(t, 1 / s).toDouble();
    return (lo + (hi - lo) * curve).round().clamp(lo, hi);
  }

  /// Scales the colour by its brightness.
  ///
  /// The head unit offers three brightness steps, so the brightness written
  /// to it is the user's absolute value, not the spectrum derived one. The
  /// music reaction has to show somewhere else, and it shows here: the
  /// louder the music, the brighter the colour.
  ///
  /// Without this step the sensitivity and the brightness bounds would have
  /// no effect at all, because the strip would always show the same hue at
  /// the same brightness.
  static AmbientColor scaleByBrightness(AmbientColor color) {
    final k = color.brightness.clamp(0, 100) / 100;
    return AmbientColor(
      (color.r * k).round().clamp(0, 255),
      (color.g * k).round().clamp(0, 255),
      (color.b * k).round().clamp(0, 255),
      color.brightness,
    );
  }

  /// Normalises a hue into 0..360.
  /// The HSV saturation of a `#RRGGBB` colour (0..1), or null when unparsable.
  static double? saturationOfHex(String hex) {
    if (hex.length != 7) return null;
    final value = int.tryParse(hex.substring(1), radix: 16);
    if (value == null) return null;
    final r = (value >> 16) & 0xFF;
    final g = (value >> 8) & 0xFF;
    final b = value & 0xFF;
    final maxc = math.max(r, math.max(g, b)).toDouble();
    final minc = math.min(r, math.min(g, b)).toDouble();
    return maxc <= 0 ? 0 : (maxc - minc) / maxc;
  }

  static double normalizeHue(double hue) {
    var h = hue % 360;
    if (h < 0) h += 360;
    return h;
  }

  /// HSV to RGB at full value. Returns `[r, g, b]`.
  static List<int> hsvToRgb(double hue, double saturation, double value) {
    final h = normalizeHue(hue) / 60;
    final c = value * saturation;
    final x = c * (1 - (h % 2 - 1).abs());
    final m = value - c;
    final (r1, g1, b1) = switch (h.toInt()) {
      0 => (c, x, 0.0),
      1 => (x, c, 0.0),
      2 => (0.0, c, x),
      3 => (0.0, x, c),
      4 => (x, 0.0, c),
      _ => (c, 0.0, x),
    };
    return [
      ((r1 + m) * 255).round().clamp(0, 255),
      ((g1 + m) * 255).round().clamp(0, 255),
      ((b1 + m) * 255).round().clamp(0, 255),
    ];
  }

  /// Euclidean distance between two colours (0..441).
  static int colorDistance(AmbientColor a, AmbientColor b) {
    final dr = a.r - b.r, dg = a.g - b.g, db = a.b - b.b;
    return math.sqrt((dr * dr + dg * dg + db * db).toDouble()).toInt();
  }

  // ==================================================================
  // V2: the perceptual mapping
  //
  // The functions below replace the two that made the old chain stiff:
  // [bassHue] (a discrete pick) and [brightnessFor] (a linear map).
  // The old ones stay, because the legacy chain and its tests still use
  // them.
  // ==================================================================

  /// The low end of the hue band (degrees).
  ///
  /// The hue band runs from cyan through blue and violet to magenta. That
  /// skips the bright yellow around 570 nm, which is the most glaring colour
  /// for the eye and the worst one for night driving, while still leaving
  /// 150 degrees of travel, which is enough for the colour to visibly move.
  static const double hueBandLow = 170;

  /// The high end of the hue band (degrees).
  static const double hueBandHigh = 320;

  /// The width of the safe band in degrees (=150°), the default hue span.
  static const double hueBandSpan = hueBandHigh - hueBandLow;

  /// The widest hue span: the whole circle, for the 「五彩」 look.
  static const double hueSpanMax = 360;

  /// The narrowest hue span: the safe band itself.
  ///
  /// It is also the default of [centroidHue], so a caller that does not pass
  /// a span keeps the exact old formula (and the old 150° band).
  static const double hueSpanMin = hueBandSpan;

  /// How many low bands the low centroid looks at.
  static const int lowCentroidBands = 8;

  /// The lower edge of the lightness window (a relative level).
  static const double levelWindowLow = 0.22;

  /// The width of the lightness window (a relative level).
  static const double levelWindowSpan = 0.78;

  /// The base of the contrast exponent.
  static const double levelGammaBase = 1.45;

  /// How much the sensitivity tilts the contrast exponent.
  static const double levelGammaSlope = 0.5;

  /// The upper bound of the chroma (the C of OKLab).
  static const double maxChroma = 0.22;

  /// The lower edge of the **rainbow** centroid window.
  ///
  /// Real music only moves its spectral centroid inside roughly 0.20..0.65,
  /// so a plain 360° span still walks only ~100° of hue. Stretching this
  /// window to 0..1 is what lets the colour cross the whole circle.
  static const double rainbowCentroidWindowLow = 0.20;

  /// The width of the **rainbow** centroid window (0.20..0.65).
  static const double rainbowCentroidWindowSpan = 0.45;

  /// The chroma cap of the **rainbow** preset.
  static const double rainbowMaxChroma = 0.32;

  /// The hard upper bound of the chroma.
  ///
  /// The art layer already clamps by the user's setting; the motion layer
  /// only enforces this hard ceiling, so a bad value can never blow up the
  /// colour.
  static const double maxChromaHard = 0.40;

  /// The fastest hue self-rotation the setting allows (degrees per second).
  static const double maxHueRotateDegPerSec = 30;

  /// The **spectral centroid** (0..1): low bass is 0, high treble is 1.
  ///
  /// ## Why the centroid and not "the loudest band"
  ///
  /// The legacy [bassHue] is a **discrete pick**: it takes the loudest band
  /// out of the low range and uses its index as the hue. The bands are
  /// `360 / count` degrees apart (24 bands is 15 degrees), so every kick
  /// swaps the band and the hue **jumps**.
  ///
  /// The centroid is a **continuous** quantity: when the centre of gravity of
  /// the spectrum moves, the hue moves with it, and there is no step left.
  ///
  /// ## The band index is already a logarithmic frequency axis
  ///
  /// The bands are logarithmic (60 Hz to 14 kHz, equal ratios), so the
  /// normalised index is the normalised log frequency. That means the
  /// centroid needs no sample rate at all.
  ///
  /// ## The **centre** of the band, not the index
  ///
  /// Band `i` covers `[bottom * r^(i/N), bottom * r^((i+1)/N))`, and its
  /// centre sits at `(i + 0.5) / N` on the log axis. Using the centre
  /// instead of the index keeps the centroid symmetric (the first band
  /// centre is 0.021, the last is 0.979) and free of a half band offset.
  static double spectralCentroid(List<double> bands) {
    if (bands.length <= 1) return 0.5;
    var num = 0.0;
    var den = 0.0;
    final n = bands.length.toDouble();
    for (var i = 0; i < bands.length; i++) {
      final w = bands[i];
      if (w <= 0) continue;
      num += ((i + 0.5) / n) * w;
      den += w;
    }
    if (den <= 0.0001) return 0.5;
    return (num / den).clamp(0.0, 1.0);
  }

  /// The spectral centroid to a hue (the whole spectrum).
  ///
  /// The hue is limited to [hueBandLow] to [hueBandHigh] (cyan to blue to
  /// violet to magenta): the bass lands on magenta violet (320 degrees) and
  /// the treble on cyan (170 degrees).
  ///
  /// The optional window is the 「五彩」 expansion: [expandCentroid] spreads
  /// the centroid through `windowLow..windowLow+windowSpan` into 0..1 before
  /// it is mapped to the span. With the defaults (span 150°, window 0..1)
  /// the expansion is the identity, so the result is bit for bit the old
  /// formula.
  ///
  /// * [spanDeg] how many degrees the hue may travel (150..360)
  /// * [windowLow] the centroid treated as 0 after the expansion
  /// * [windowSpan] the centroid range that maps to 0..1
  static double centroidHue(
    List<double> bands,
    double fallbackHue, {
    double spanDeg = hueBandSpan,
    double windowLow = 0,
    double windowSpan = 1,
  }) {
    if (bands.isEmpty) return normalizeHue(fallbackHue);
    final u = expandCentroid(spectralCentroid(bands), windowLow, windowSpan);
    return normalizeHue(
        hueBandHigh - spanDeg.clamp(hueSpanMin, hueSpanMax) * u);
  }

  /// Spreads a spectral centroid through a window into 0..1.
  ///
  /// The music's centroid only moves inside a narrow slice of 0..1, so using
  /// it directly wastes most of the hue span. This is the "expansion" of the
  /// rainbow: `[windowLow, windowLow + windowSpan]` becomes `0..1` and
  /// everything outside is clamped.
  ///
  /// The window is never narrower than 0.05, otherwise a tiny span would
  /// amplify the centroid into noise.
  static double expandCentroid(
      double centroid, double windowLow, double windowSpan) {
    final span = windowSpan.clamp(0.05, 1.0);
    return ((centroid - windowLow) / span).clamp(0.0, 1.0);
  }

  /// Integrates the hue self-rotation phase (degrees).
  ///
  /// Used when the centroid stops moving (a repeated chorus): time alone
  /// keeps pushing the hue around the circle. Both the speed and the elapsed
  /// time are clamped, so a frame after the app comes back from the
  /// background cannot jump dozens of degrees at once.
  static double rotationPhase(
      double prevPhaseDeg, double rotateDegPerSec, int dtMs) {
    return normalizeHue(prevPhaseDeg +
        rotateDegPerSec.clamp(0.0, maxHueRotateDegPerSec) *
            dtMs.clamp(0, 1000) /
            1000);
  }

  /// The **low** centroid to a hue (only the first [lowCentroidBands]).
  ///
  /// The "follow the bass" mode uses this: the structure inside the low end
  /// still moves the hue, but the result stays on the bass side (magenta
  /// violet), which keeps it apart from "follow the spectrum".
  ///
  /// The span and the window have the same meaning (and the same defaults)
  /// as in [centroidHue].
  static double lowCentroidHue(
    List<double> bands,
    double fallbackHue, {
    double spanDeg = hueBandSpan,
    double windowLow = 0,
    double windowSpan = 1,
  }) {
    if (bands.isEmpty) return normalizeHue(fallbackHue);
    final n = math.min(lowCentroidBands, bands.length);
    if (n <= 1) return normalizeHue(fallbackHue);
    var num = 0.0;
    var den = 0.0;
    final total = n.toDouble();
    for (var i = 0; i < n; i++) {
      final w = bands[i];
      if (w <= 0) continue;
      num += ((i + 0.5) / total) * w;
      den += w;
    }
    if (den <= 0.0001) return normalizeHue(fallbackHue);
    final c = (num / den).clamp(0.0, 1.0);
    final u = expandCentroid(c, windowLow, windowSpan);
    return normalizeHue(
        hueBandHigh - spanDeg.clamp(hueSpanMin, hueSpanMax) * u);
  }

  /// The relative level to a target lightness (0..1).
  ///
  /// ## This is the key to "the brightness moves clearly"
  ///
  /// The legacy [brightnessFor] is `min + (max - min) * level^(1/sens)`:
  /// with a median low frequency energy of about 0.5 the result is already
  /// near the top, so the **dynamic range is only 10 percent** and the
  /// strip looks permanently full.
  ///
  /// The new version maps a window first and then applies a contrast curve:
  /// - a relative level below [levelWindowLow] (0.22) is 0 (the quiet part);
  /// - a relative level of about 0.55 (a typical passage) is about 0.4;
  /// - a relative level of 1.0 (a kick, the climax) is 1.
  ///
  /// A typical level must land near the middle: pinned to the top means the
  /// brightness range is squashed.
  ///
  /// * [relative] the relative level of the perception layer (0..1)
  /// * [sensitivity] the perception sensitivity (0.3 to 3, higher lights the
  ///   quiet parts more)
  /// * [floorPercent] the base lightness in percent, the breathing base
  ///   light. It must **not** be 0, the strip may never go fully dark.
  static double levelFromRelative({
    required double relative,
    required double sensitivity,
    required double floorPercent,
  }) {
    final u = ((relative - levelWindowLow) / levelWindowSpan).clamp(0.0, 1.0);
    // A higher sensitivity means a smaller gamma means a flatter curve, so
    // the quiet parts light up too.
    final gamma = levelGammaBase +
        levelGammaSlope *
            (1 - sensitivity.clamp(minSensitivity, maxSensitivity));
    final v = math.pow(u, gamma).toDouble();
    final floor = (floorPercent / 100).clamp(0.0, 1.0);
    return (floor + (1 - floor) * v).clamp(0.0, 1.0);
  }

  /// The high frequency transient (0..1): cymbals, consonants.
  ///
  /// It drives the **saturation**, which is on a different clock from the hue
  /// (seconds) and the lightness (10 to 100 ms). Three signals that are out
  /// of step read as a flow rather than as everything shaking together.
  static double transientOf(List<double> bands) {
    if (bands.length < 4) return 0;
    // `~/` is the integer division in Dart: `/` would give a double, and a
    // double cannot index a list.
    final from = bands.length * 2 ~/ 3;
    var sum = 0.0;
    var n = 0;
    for (var i = from; i < bands.length; i++) {
      sum += bands[i];
      n++;
    }
    if (n == 0) return 0;
    return (sum / n).clamp(0.0, 1.0);
  }

  /// The target **chroma** (the C of OKLab, 0..[maxChroma]).
  ///
  /// ## Why the chroma is a signal of its own
  ///
  /// The hue (seconds) and the lightness (10 to 100 ms) are already two
  /// signals that are out of step. If the chroma followed the lightness, all
  /// three would shake together and the strip would read as "everything is
  /// jumping" instead of "the colour is flowing".
  ///
  /// The chroma follows the **high frequency transient** instead: a cymbal
  /// makes the colour more vivid, and that is out of step with the bass
  /// drum, so the strip has detail instead of only a beat.
  ///
  /// * [bands] the normalised bands of the perception layer (0..1)
  /// * [saturation] the saturation cap (0..1, the user setting)
  /// * [maxChroma] the chroma cap (0..[maxChromaHard]); when omitted the
  ///   historical [AmbientPalette.maxChroma] (0.22) is used, so the old
  ///   look does not change
  static double chromaTarget(List<double> bands, double saturation,
      {double? maxChroma}) {
    if (bands.isEmpty) return 0;
    var energy = 0.0;
    for (var i = 0; i < bands.length; i++) {
      energy += bands[i];
    }
    // The reference: every band at its typical value is 1.0.
    final energyNorm =
        (energy / (bands.length * typicalBandValue)).clamp(0.0, 1.0);
    final transient = (transientOf(bands) / typicalBandValue).clamp(0.0, 1.0);
    final sat = saturation.clamp(0.0, 1.0);
    final c = (chromaBase + chromaSatGain * sat) * (0.55 + 0.45 * energyNorm) +
        chromaTransientGain * transient;
    // Whoever asks for more than the hard ceiling is clamped; the setting
    // itself is clamped to 0.10..0.40 by [AmbientLightSettings].
    final cap =
        (maxChroma ?? AmbientPalette.maxChroma).clamp(0.0, maxChromaHard);
    return c.clamp(0.0, cap);
  }

  /// The motion level to the perceptual lightness L.
  ///
  /// The level of the motion layer is a relative energy. Used as L directly it
  /// would sit at 0 in the dark (the LEDs look black), so a floor is kept:
  /// `L = level * 0.92 + 0.04`.
  static double perceptualLightness(double level) =>
      (level.clamp(0.0, 1.0) * lightnessGain + lightnessBias).clamp(0.0, 1.0);

  /// OKLCH to a colour (with the 8 bit dither).
  ///
  /// The difference to the legacy [colorOf]:
  /// - the legacy one is HSV plus a **linear** RGB scale (the dark end is
  ///   nearly invisible);
  /// - this one is **OKLCH**, so L is the perceptual lightness and the
  ///   brightness range is linear on the physical LEDs.
  ///
  /// * [lightness] the perceptual lightness (0..1)
  /// * [chroma] the chroma of OKLab (0..0.4)
  static AmbientColor colorOfOklch(
    double hue,
    double lightness,
    double chroma, [
    double Function()? rand,
  ]) {
    final l = lightness.clamp(0.0, 1.0);
    final (r, g, b) = AmbientColorSpace.oklchToRgb(
        l, chroma.clamp(0.0, 0.4), normalizeHue(hue));
    return AmbientColor(
      AmbientColorSpace.dither(r.toDouble(), rand),
      AmbientColorSpace.dither(g.toDouble(), rand),
      AmbientColorSpace.dither(b.toDouble(), rand),
      (l * 100).round().clamp(0, 100),
    );
  }

  /// The typical band value (0.5 per band), the reference of the chroma
  /// normalisation.
  static const double typicalBandValue = 0.5;

  /// The base of the chroma (before the saturation setting).
  static const double chromaBase = 0.10;

  /// How much the saturation setting adds to the chroma.
  static const double chromaSatGain = 0.16;

  /// How much the high frequency transient adds to the chroma.
  static const double chromaTransientGain = 0.05;

  /// The gain of the motion level to the perceptual lightness L.
  static const double lightnessGain = 0.92;

  /// The bias of the perceptual lightness L, so the dark end is not black.
  static const double lightnessBias = 0.04;
}

/// User settings for the music-driven ambient light.
class AmbientLightSettings {
  /// Whether the strip follows the music.
  final bool enabled;

  /// Colour mode, one of [AmbientPalette.modeBass] and friends.
  final int mode;

  /// Whether the user has ever picked a colour mode explicitly.
  ///
  /// The settings payload has no such flag historically. It exists so a
  /// changed default does not override a deliberate choice: an installation
  /// that never touched the chips can be migrated, one that did cannot.
  final bool modeConfigured;

  /// Whether the tuning sliders are visible.
  ///
  /// Presets are the front door: picking one hides every slider and shows a
  /// read-only summary instead. Tapping 自定义 brings the sliders back. The
  /// flag is stored so a restart does not silently fold the user's tweaks
  /// back into a preset-shaped page.
  final bool customMode;

  /// Fixed hue in degrees, used by [AmbientPalette.modeFixed].
  final double fixedHue;

  /// Hue of the bass region (0..360) for the rhythm engine.
  ///
  /// The three regions are deliberately far apart on the wheel (bass warm,
  /// mid green, treble blue-violet). The old violet/cyan/pale-blue mapping
  /// sat inside one narrow blue family, so the strip looked frozen.
  final double bassHue;

  /// Hue of the mid region (0..360) for the rhythm engine.
  final double midHue;

  /// Hue of the treble region (0..360) for the rhythm engine.
  final double trebleHue;

  /// A custom colour for the bass region (`#RRGGBB`, empty = use [bassHue]).
  final String bassCustom;

  /// A custom colour for the mid region (`#RRGGBB`, empty = use [midHue]).
  final String midCustom;

  /// A custom colour for the treble region (`#RRGGBB`, empty = use [trebleHue]).
  final String trebleCustom;

  /// Curve exponent; higher means the quiet parts light up more.
  final double sensitivity;

  /// How much earlier a predicted beat is written (milliseconds, 0..250).
  ///
  /// The vendor strip low-passes a colour change, so a beat written at the
  /// moment it is heard arrives late. Writing the predicted beat a little
  /// before it happens compensates for that delay.
  final int beatLeadMs;

  /// The absolute brightness written to the head unit, 0 to 100.
  ///
  /// The head unit only offers three steps, so this is the user's value and
  /// not the spectrum derived one. The music shows in the colour instead.
  final int vehicleBrightness;

  /// Lowest brightness the spectrum may scale the colour down to.
  final int minBrightness;

  /// Highest brightness the spectrum may scale the colour up to.
  final int maxBrightness;

  /// Which engine drives the strip: [engineV2] or [engineLegacy].
  ///
  /// ## Why there is a switch
  ///
  /// The legacy chain has been verified on the car (the strip really does
  /// change colour with the music), but it was called "too stiff". The V2
  /// chain is a rewrite and the two look very different, so the user needs
  /// to be able to compare them **on the same car with the same song**
  /// instead of from memory.
  final int engine;

  /// The time constant of the lightness **rise** (milliseconds).
  final int attackMs;

  /// The time constant of the lightness **fall** (milliseconds).
  final int decayMs;

  /// The time constant of the hue smoothing (milliseconds).
  final int hueTauMs;

  /// The upper bound on the hue speed (degrees per second).
  final int hueMaxDeg;

  /// The upper bound on the hue angular acceleration (degrees per second
  /// squared).
  final int hueMaxAccel;

  /// The perceived colour difference allowed between two frames (Delta E00).
  final double maxDeltaE;

  /// The base lightness in percent, the breathing base light.
  final int floor;

  /// The saturation cap (0..1).
  final double saturation;

  /// How much the idle breathing moves the lightness (0..0.4).
  final double breath;

  /// The hue span in degrees (150..360).
  ///
  /// 150 is the safe band (cyan to magenta, no glaring yellow); 360 is the
  /// whole circle. Increasing the span alone is not enough for a rainbow:
  /// see [centroidWindowLowHundredths].
  final int hueSpanDeg;

  /// The lower edge of the centroid expansion window (hundredths, 0..0.70).
  ///
  /// Real music keeps its spectral centroid inside ~0.20..0.65, so the
  /// expansion is what turns a 360° span into an actual full circle.
  final int centroidWindowLowHundredths;

  /// The width of the centroid expansion window (hundredths, 0.10..1.00).
  final int centroidWindowSpanHundredths;

  /// The hue self-rotation in degrees per second (0..30).
  ///
  /// When the centroid stops moving (a repeated chorus), time alone keeps
  /// the hue walking around the circle.
  final int hueRotateDegPerSec;

  /// The chroma cap in hundredths (10..40).
  ///
  /// 22 is the historical maximum; a rainbow wants 0.32 so the reds and
  /// greens are not grey-ish.
  final int maxChromaHundredths;

  /// The hue jump step in degrees (0..180).
  ///
  /// 0 is continuous smoothing; above 0 the hue snaps onto the nearest step
  /// instead of tracking the target — the 「跳跃」 jump. Faster smoothing
  /// cannot do this: a shorter tau or a higher limit only shortens the
  /// slide, it never becomes a jump.
  final int hueJumpDeg;

  /// The kick flash gain in hundredths (0..200).
  ///
  /// 100 is 1.00×. The old fixed value was 0.35×, which is the default here,
  /// so an untouched configuration looks exactly as before.
  final int pulseGainHundredths;

  /// The shortest gap between two kicks in milliseconds (80..600).
  ///
  /// A smaller gap lets fast music flash more often; 120 ms (500 flashes per
  /// minute) is the 「跳跃」 value.
  final int beatMinGapMs;

  /// The forced colour change interval of the jump mode in milliseconds
  /// (0..1000, 0 = only follow the beats).
  ///
  /// Onset detection is content driven: no kick in the music, or a kick that
  /// the adaptive threshold has already accepted as "normal", and the hue
  /// stops changing — the strip freezes again. This caps the wait, so the
  /// jump mode **keeps flashing** instead of jumping once in a while.
  final int jumpHoldMs;

  /// Whether the zone choreography runs (the zones take turns).
  ///
  /// **Off by default**: a zone switch is a hard edge, and it is easily a
  /// distraction while driving. It is meant for parked cars, a welcome
  /// sequence or a static show.
  final bool zoneChoreo;

  /// How long a zone stays lit before the choreography moves on (milliseconds).
  ///
  /// Below 700 ms the hard edge becomes visible.
  final int zoneDwellMs;

  const AmbientLightSettings({
    this.enabled = false,
    this.mode = AmbientPalette.modeBass,
    this.modeConfigured = false,
    this.customMode = false,
    this.fixedHue = 210,
    this.bassHue = 12,
    this.midHue = 122,
    this.trebleHue = 252,
    this.bassCustom = '',
    this.midCustom = '',
    this.trebleCustom = '',
    this.sensitivity = 1.4,
    this.beatLeadMs = 140,
    this.vehicleBrightness = 100,
    this.minBrightness = 15,
    this.maxBrightness = 100,
    this.engine = engineV2,
    this.attackMs = 45,
    this.decayMs = 260,
    this.hueTauMs = 260,
    this.hueMaxDeg = 60,
    this.hueMaxAccel = 240,
    this.maxDeltaE = 1.8,
    this.floor = 8,
    this.saturation = 0.8,
    this.breath = 0.10,
    this.hueSpanDeg = 150,
    this.centroidWindowLowHundredths = 0,
    this.centroidWindowSpanHundredths = 100,
    this.hueRotateDegPerSec = 0,
    this.maxChromaHundredths = 22,
    this.hueJumpDeg = 0,
    this.pulseGainHundredths = 35,
    this.beatMinGapMs = 240,
    this.jumpHoldMs = 0,
    this.zoneChoreo = false,
    this.zoneDwellMs = 800,
  });

  /// The new engine: perceptual colour space plus a second order hue.
  static const int engineV2 = 0;

  /// The legacy engine: the chain that was verified on the car.
  static const int engineLegacy = 1;

  /// The rhythm engine: beat detection plus peak/valley writes (20 Hz).
  ///
  /// This is the chain that upstream's `AmbientRhythm` drives: every onset
  /// writes a peak colour and a high brightness step, a valley follows, and
  /// the strip is held between the two. It reads as an impact per beat
  /// rather than a flow.
  static const int engineRhythm = 2;

  /// The centroid window lower edge as a fraction (0..0.70).
  double get centroidWindowLow => centroidWindowLowHundredths / 100;

  /// The centroid window width as a fraction (0.10..1.00).
  double get centroidWindowSpan => centroidWindowSpanHundredths / 100;

  /// The chroma cap as a fraction (0.10..0.40).
  double get maxChromaValue => maxChromaHundredths / 100;

  /// The kick flash gain as a factor (0..2).
  double get pulseGainValue => pulseGainHundredths / 100;

  factory AmbientLightSettings.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const AmbientLightSettings();
    final mode = json['mode'];
    final engine = json['engine'];
    return AmbientLightSettings(
      enabled: json['enabled'] == true,
      mode: mode is num && mode.toInt() >= 0 && mode.toInt() <= 2
          ? mode.toInt()
          : AmbientPalette.modeBass,
      modeConfigured: json['modeConfigured'] == true,
      customMode: json['customMode'] == true,
      fixedHue: json['fixedHue'] is num
          ? AmbientPalette.normalizeHue((json['fixedHue'] as num).toDouble())
          : 210,
      bassHue: json['bassHue'] is num
          ? AmbientPalette.normalizeHue((json['bassHue'] as num).toDouble())
          : 12,
      midHue: json['midHue'] is num
          ? AmbientPalette.normalizeHue((json['midHue'] as num).toDouble())
          : 122,
      trebleHue: json['trebleHue'] is num
          ? AmbientPalette.normalizeHue((json['trebleHue'] as num).toDouble())
          : 252,
      bassCustom: _hexColor(json['bassCustom']),
      midCustom: _hexColor(json['midCustom']),
      trebleCustom: _hexColor(json['trebleCustom']),
      sensitivity: json['sensitivity'] is num
          ? (json['sensitivity'] as num).toDouble().clamp(
              AmbientPalette.minSensitivity, AmbientPalette.maxSensitivity)
          : 1.4,
      beatLeadMs: json['beatLeadMs'] is num
          ? (json['beatLeadMs'] as num).toInt().clamp(0, 250)
          : 140,
      vehicleBrightness: json['vehicleBrightness'] is num
          ? (json['vehicleBrightness'] as num).toInt().clamp(0, 100)
          : 100,
      minBrightness: json['minBrightness'] is num
          ? (json['minBrightness'] as num).toInt().clamp(0, 100)
          : 15,
      maxBrightness: json['maxBrightness'] is num
          ? (json['maxBrightness'] as num).toInt().clamp(0, 100)
          : 100,
      engine: engine is num && engine.toInt() >= 0 && engine.toInt() <= 2
          ? engine.toInt()
          : engineV2,
      attackMs: json['attackMs'] is num
          ? (json['attackMs'] as num).toInt().clamp(10, 300)
          : 45,
      decayMs: json['decayMs'] is num
          ? (json['decayMs'] as num).toInt().clamp(60, 1200)
          : 260,
      hueTauMs: json['hueTauMs'] is num
          ? (json['hueTauMs'] as num).toInt().clamp(60, 1200)
          : 260,
      hueMaxDeg: json['hueMaxDeg'] is num
          ? (json['hueMaxDeg'] as num).toInt().clamp(10, 180)
          : 60,
      hueMaxAccel: json['hueMaxAccel'] is num
          ? (json['hueMaxAccel'] as num).toInt().clamp(30, 800)
          : 240,
      maxDeltaE: json['maxDeltaE'] is num
          ? (json['maxDeltaE'] as num).toDouble().clamp(0.2, 6.0)
          : 1.8,
      floor: json['floor'] is num
          ? (json['floor'] as num).toInt().clamp(0, 30)
          : 8,
      saturation: json['saturation'] is num
          ? (json['saturation'] as num).toDouble().clamp(0.0, 1.0)
          : 0.8,
      breath: json['breath'] is num
          ? (json['breath'] as num).toDouble().clamp(0.0, 0.4)
          : 0.10,
      // The keys of the five 「五彩」 fields and the three 「跳跃」 fields
      // follow the cardesk preference names, so the two apps describe the
      // same parameter identically.
      hueSpanDeg: json['ambient_hue_span_deg'] is num
          ? (json['ambient_hue_span_deg'] as num).toInt().clamp(150, 360)
          : 150,
      centroidWindowLowHundredths: json['ambient_centroid_low'] is num
          ? (json['ambient_centroid_low'] as num).toInt().clamp(0, 70)
          : 0,
      centroidWindowSpanHundredths: json['ambient_centroid_span'] is num
          ? (json['ambient_centroid_span'] as num).toInt().clamp(10, 100)
          : 100,
      hueRotateDegPerSec: json['ambient_hue_rotate'] is num
          ? (json['ambient_hue_rotate'] as num).toInt().clamp(0, 30)
          : 0,
      maxChromaHundredths: json['ambient_max_chroma'] is num
          ? (json['ambient_max_chroma'] as num).toInt().clamp(10, 40)
          : 22,
      hueJumpDeg: json['ambient_hue_jump_deg'] is num
          ? (json['ambient_hue_jump_deg'] as num).toInt().clamp(0, 180)
          : 0,
      pulseGainHundredths: json['ambient_pulse_gain'] is num
          ? (json['ambient_pulse_gain'] as num).toInt().clamp(0, 200)
          : 35,
      beatMinGapMs: json['ambient_beat_gap_ms'] is num
          ? (json['ambient_beat_gap_ms'] as num).toInt().clamp(80, 600)
          : 240,
      jumpHoldMs: json['ambient_jump_hold_ms'] is num
          ? ((json['ambient_jump_hold_ms'] as num).toInt() == 0
              ? 0
              : (json['ambient_jump_hold_ms'] as num).toInt().clamp(80, 1000))
          : 0,
      zoneChoreo: json['zoneChoreo'] == true,
      zoneDwellMs: json['zoneDwellMs'] is num
          ? (json['zoneDwellMs'] as num).toInt().clamp(700, 2000)
          : 800,
    );
  }

  Map<String, dynamic> toJson() => {
        'enabled': enabled,
        'mode': mode,
        'modeConfigured': modeConfigured,
        'customMode': customMode,
        'fixedHue': fixedHue.round(),
        'bassHue': bassHue.round(),
        'midHue': midHue.round(),
        'trebleHue': trebleHue.round(),
        'bassCustom': bassCustom,
        'midCustom': midCustom,
        'trebleCustom': trebleCustom,
        'sensitivity': double.parse(sensitivity.toStringAsFixed(2)),
        'beatLeadMs': beatLeadMs,
        'vehicleBrightness': vehicleBrightness,
        'minBrightness': minBrightness,
        'maxBrightness': maxBrightness,
        'engine': engine,
        'attackMs': attackMs,
        'decayMs': decayMs,
        'hueTauMs': hueTauMs,
        'hueMaxDeg': hueMaxDeg,
        'hueMaxAccel': hueMaxAccel,
        'maxDeltaE': double.parse(maxDeltaE.toStringAsFixed(2)),
        'floor': floor,
        'saturation': double.parse(saturation.toStringAsFixed(2)),
        'breath': double.parse(breath.toStringAsFixed(2)),
        'ambient_hue_span_deg': hueSpanDeg,
        'ambient_centroid_low': centroidWindowLowHundredths,
        'ambient_centroid_span': centroidWindowSpanHundredths,
        'ambient_hue_rotate': hueRotateDegPerSec,
        'ambient_max_chroma': maxChromaHundredths,
        'ambient_hue_jump_deg': hueJumpDeg,
        'ambient_pulse_gain': pulseGainHundredths,
        'ambient_beat_gap_ms': beatMinGapMs,
        'ambient_jump_hold_ms': jumpHoldMs,
        'zoneChoreo': zoneChoreo,
        'zoneDwellMs': zoneDwellMs,
      };

  AmbientLightSettings copyWith({
    bool? enabled,
    int? mode,
    bool? modeConfigured,
    bool? customMode,
    double? fixedHue,
    double? bassHue,
    double? midHue,
    double? trebleHue,
    String? bassCustom,
    String? midCustom,
    String? trebleCustom,
    double? sensitivity,
    int? beatLeadMs,
    int? vehicleBrightness,
    int? minBrightness,
    int? maxBrightness,
    int? engine,
    int? attackMs,
    int? decayMs,
    int? hueTauMs,
    int? hueMaxDeg,
    int? hueMaxAccel,
    double? maxDeltaE,
    int? floor,
    double? saturation,
    double? breath,
    int? hueSpanDeg,
    int? centroidWindowLowHundredths,
    int? centroidWindowSpanHundredths,
    int? hueRotateDegPerSec,
    int? maxChromaHundredths,
    int? hueJumpDeg,
    int? pulseGainHundredths,
    int? beatMinGapMs,
    int? jumpHoldMs,
    bool? zoneChoreo,
    int? zoneDwellMs,
  }) =>
      AmbientLightSettings(
        enabled: enabled ?? this.enabled,
        mode: mode ?? this.mode,
        modeConfigured: modeConfigured ?? this.modeConfigured,
        customMode: customMode ?? this.customMode,
        fixedHue: fixedHue ?? this.fixedHue,
        bassHue: bassHue ?? this.bassHue,
        midHue: midHue ?? this.midHue,
        trebleHue: trebleHue ?? this.trebleHue,
        bassCustom: bassCustom ?? this.bassCustom,
        midCustom: midCustom ?? this.midCustom,
        trebleCustom: trebleCustom ?? this.trebleCustom,
        sensitivity: sensitivity ?? this.sensitivity,
        beatLeadMs: beatLeadMs ?? this.beatLeadMs,
        vehicleBrightness: vehicleBrightness ?? this.vehicleBrightness,
        minBrightness: minBrightness ?? this.minBrightness,
        maxBrightness: maxBrightness ?? this.maxBrightness,
        engine: engine ?? this.engine,
        attackMs: attackMs ?? this.attackMs,
        decayMs: decayMs ?? this.decayMs,
        hueTauMs: hueTauMs ?? this.hueTauMs,
        hueMaxDeg: hueMaxDeg ?? this.hueMaxDeg,
        hueMaxAccel: hueMaxAccel ?? this.hueMaxAccel,
        maxDeltaE: maxDeltaE ?? this.maxDeltaE,
        floor: floor ?? this.floor,
        saturation: saturation ?? this.saturation,
        breath: breath ?? this.breath,
        hueSpanDeg: hueSpanDeg ?? this.hueSpanDeg,
        centroidWindowLowHundredths:
            centroidWindowLowHundredths ?? this.centroidWindowLowHundredths,
        centroidWindowSpanHundredths:
            centroidWindowSpanHundredths ?? this.centroidWindowSpanHundredths,
        hueRotateDegPerSec: hueRotateDegPerSec ?? this.hueRotateDegPerSec,
        maxChromaHundredths: maxChromaHundredths ?? this.maxChromaHundredths,
        hueJumpDeg: hueJumpDeg ?? this.hueJumpDeg,
        pulseGainHundredths: pulseGainHundredths ?? this.pulseGainHundredths,
        beatMinGapMs: beatMinGapMs ?? this.beatMinGapMs,
        jumpHoldMs: jumpHoldMs ?? this.jumpHoldMs,
        zoneChoreo: zoneChoreo ?? this.zoneChoreo,
        zoneDwellMs: zoneDwellMs ?? this.zoneDwellMs,
      );

  @override
  bool operator ==(Object other) =>
      other is AmbientLightSettings &&
      other.enabled == enabled &&
      other.mode == mode &&
      other.modeConfigured == modeConfigured &&
      other.customMode == customMode &&
      other.fixedHue == fixedHue &&
      other.bassHue == bassHue &&
      other.midHue == midHue &&
      other.trebleHue == trebleHue &&
      other.bassCustom == bassCustom &&
      other.midCustom == midCustom &&
      other.trebleCustom == trebleCustom &&
      other.sensitivity == sensitivity &&
      other.beatLeadMs == beatLeadMs &&
      other.vehicleBrightness == vehicleBrightness &&
      other.minBrightness == minBrightness &&
      other.maxBrightness == maxBrightness &&
      other.engine == engine &&
      other.attackMs == attackMs &&
      other.decayMs == decayMs &&
      other.hueTauMs == hueTauMs &&
      other.hueMaxDeg == hueMaxDeg &&
      other.hueMaxAccel == hueMaxAccel &&
      other.maxDeltaE == maxDeltaE &&
      other.floor == floor &&
      other.saturation == saturation &&
      other.breath == breath &&
      other.hueSpanDeg == hueSpanDeg &&
      other.centroidWindowLowHundredths == centroidWindowLowHundredths &&
      other.centroidWindowSpanHundredths == centroidWindowSpanHundredths &&
      other.hueRotateDegPerSec == hueRotateDegPerSec &&
      other.maxChromaHundredths == maxChromaHundredths &&
      other.hueJumpDeg == hueJumpDeg &&
      other.pulseGainHundredths == pulseGainHundredths &&
      other.beatMinGapMs == beatMinGapMs &&
      other.jumpHoldMs == jumpHoldMs &&
      other.zoneChoreo == zoneChoreo &&
      other.zoneDwellMs == zoneDwellMs;

  /// A `#RRGGBB` string from the payload, or an empty string.
  static String _hexColor(Object? value) {
    if (value is! String) return '';
    return RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch(value)
        ? value.toLowerCase()
        : '';
  }

  @override
  int get hashCode => Object.hashAll([
        enabled,
        mode,
        modeConfigured,
        customMode,
        fixedHue,
        bassHue,
        midHue,
        trebleHue,
        bassCustom,
        midCustom,
        trebleCustom,
        sensitivity,
        beatLeadMs,
        vehicleBrightness,
        minBrightness,
        maxBrightness,
        engine,
        attackMs,
        decayMs,
        hueTauMs,
        hueMaxDeg,
        hueMaxAccel,
        maxDeltaE,
        floor,
        saturation,
        breath,
        hueSpanDeg,
        centroidWindowLowHundredths,
        centroidWindowSpanHundredths,
        hueRotateDegPerSec,
        maxChromaHundredths,
        hueJumpDeg,
        pulseGainHundredths,
        beatMinGapMs,
        jumpHoldMs,
        zoneChoreo,
        zoneDwellMs,
      ]);
}
