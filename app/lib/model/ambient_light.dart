import 'dart:math' as math;

/// A colour the ambient strip can show: RGB plus an independent brightness.
///
/// The head unit drives one LED strip with a shared brightness level, so the
/// brightness must stay separate from the colour. Folding it into the RGB
/// would make it impossible to dim the strip without shifting its hue.
class AmbientColor {
  final int r, g, b, brightness;

  const AmbientColor(this.r, this.g, this.b, this.brightness);

  /// Packed `0xRRGGBB`, the encoding the vendor SDK expects.
  int get packed => ((r.clamp(0, 255)) << 16) | ((g.clamp(0, 255)) << 8) |
      (b.clamp(0, 255)).clamp(0, 255);

  /// `#RRGGBB` for diagnostics and the settings preview.
  String get hex =>
      '#${r.clamp(0, 255).toRadixString(16).padLeft(2, '0')}'
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
  static AmbientColor colorOf(double hue, int brightness) {
    final rgb = hsvToRgb(hue, saturation, 1);
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
    return normalizeHue(intensityHueCold -
        (intensityHueCold - intensityHueWarm) * t);
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
  static int brightnessFor(
      double level, double sensitivity, int min, int max) {
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
}

/// User settings for the music-driven ambient light.
class AmbientLightSettings {
  /// Whether the strip follows the music.
  final bool enabled;

  /// Colour mode, one of [AmbientPalette.modeBass] and friends.
  final int mode;

  /// Fixed hue in degrees, used by [AmbientPalette.modeFixed].
  final double fixedHue;

  /// Curve exponent; higher means the quiet parts light up more.
  final double sensitivity;

  /// The absolute brightness written to the head unit, 0 to 100.
  ///
  /// The head unit only offers three steps, so this is the user's value and
  /// not the spectrum derived one. The music shows in the colour instead.
  final int vehicleBrightness;

  /// Lowest brightness the spectrum may scale the colour down to.
  final int minBrightness;

  /// Highest brightness the spectrum may scale the colour up to.
  final int maxBrightness;

  const AmbientLightSettings({
    this.enabled = false,
    this.mode = AmbientPalette.modeBass,
    this.fixedHue = 210,
    this.sensitivity = 1.4,
    this.vehicleBrightness = 100,
    this.minBrightness = 15,
    this.maxBrightness = 100,
  });

  factory AmbientLightSettings.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const AmbientLightSettings();
    final mode = json['mode'];
    return AmbientLightSettings(
      enabled: json['enabled'] == true,
      mode: mode is num && mode.toInt() >= 0 && mode.toInt() <= 2
          ? mode.toInt()
          : AmbientPalette.modeBass,
      fixedHue: json['fixedHue'] is num
          ? AmbientPalette.normalizeHue((json['fixedHue'] as num).toDouble())
          : 210,
      sensitivity: json['sensitivity'] is num
          ? (json['sensitivity'] as num)
              .toDouble()
              .clamp(AmbientPalette.minSensitivity, AmbientPalette.maxSensitivity)
          : 1.4,
      vehicleBrightness: json['vehicleBrightness'] is num
          ? (json['vehicleBrightness'] as num).toInt().clamp(0, 100)
          : 100,
      minBrightness: json['minBrightness'] is num
          ? (json['minBrightness'] as num).toInt().clamp(0, 100)
          : 15,
      maxBrightness: json['maxBrightness'] is num
          ? (json['maxBrightness'] as num).toInt().clamp(0, 100)
          : 100,
    );
  }

  Map<String, dynamic> toJson() => {
        'enabled': enabled,
        'mode': mode,
        'fixedHue': fixedHue.round(),
        'sensitivity': double.parse(sensitivity.toStringAsFixed(2)),
        'vehicleBrightness': vehicleBrightness,
        'minBrightness': minBrightness,
        'maxBrightness': maxBrightness,
      };

  AmbientLightSettings copyWith({
    bool? enabled,
    int? mode,
    double? fixedHue,
    double? sensitivity,
    int? vehicleBrightness,
    int? minBrightness,
    int? maxBrightness,
  }) =>
      AmbientLightSettings(
        enabled: enabled ?? this.enabled,
        mode: mode ?? this.mode,
        fixedHue: fixedHue ?? this.fixedHue,
        sensitivity: sensitivity ?? this.sensitivity,
        vehicleBrightness: vehicleBrightness ?? this.vehicleBrightness,
        minBrightness: minBrightness ?? this.minBrightness,
        maxBrightness: maxBrightness ?? this.maxBrightness,
      );

  @override
  bool operator ==(Object other) =>
      other is AmbientLightSettings &&
      other.enabled == enabled &&
      other.mode == mode &&
      other.fixedHue == fixedHue &&
      other.sensitivity == sensitivity &&
      other.vehicleBrightness == vehicleBrightness &&
      other.minBrightness == minBrightness &&
      other.maxBrightness == maxBrightness;

  @override
  int get hashCode => Object.hash(
      enabled,
      mode,
      fixedHue,
      sensitivity,
      vehicleBrightness,
      minBrightness,
      maxBrightness);
}
