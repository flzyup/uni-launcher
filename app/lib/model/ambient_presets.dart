/// One set of ambient light preset parameters.
///
/// * [name] the label shown on the chip
/// * [attackMs] the time constant of the lightness rise (milliseconds)
/// * [decayMs] the time constant of the lightness fall (milliseconds)
/// * [hueTauMs] the time constant of the hue smoothing (milliseconds)
/// * [hueMaxDeg] the hue speed limit (degrees per second)
/// * [hueMaxAccel] the hue acceleration limit (degrees per second squared)
/// * [maxDeltaE] the colour difference cap (Delta E00)
/// * [floor] the base lightness (percent)
/// * [breath] the idle breathing (0..0.4)
/// * [saturation] the saturation cap (0..1)
/// * [hueSpanDeg] the hue span in degrees (150..360)
/// * [centroidWindowLowHundredths] the centroid expansion lower edge
///   (hundredths, 0..70)
/// * [centroidWindowSpanHundredths] the centroid expansion width
///   (hundredths, 10..100)
/// * [hueRotateDegPerSec] the hue self-rotation (0..30 °/s)
/// * [maxChromaHundredths] the chroma cap (hundredths, 10..40)
/// * [hueJumpDeg] the hue jump step (degrees, 0..180); 0 is continuous
///   smoothing, above 0 the hue snaps onto the nearest step
/// * [pulseGainHundredths] the kick flash gain (hundredths, 0..200); 100 is
///   1.00× and the old fixed value 0.35× is the default 35
/// * [beatMinGapMs] the shortest gap between two kicks (milliseconds,
///   80..600)
/// * [jumpHoldMs] the forced colour change interval of the jump mode
///   (milliseconds, 0 = only follow the beats)
class AmbientPreset {
  final String name;
  final int attackMs;
  final int decayMs;
  final int hueTauMs;
  final int hueMaxDeg;
  final int hueMaxAccel;
  final double maxDeltaE;
  final int floor;
  final double breath;
  final double saturation;
  final int hueSpanDeg;
  final int centroidWindowLowHundredths;
  final int centroidWindowSpanHundredths;
  final int hueRotateDegPerSec;
  final int maxChromaHundredths;
  final int hueJumpDeg;
  final int pulseGainHundredths;
  final int beatMinGapMs;
  final int jumpHoldMs;

  /// A one-line description of what the preset feels like in the car.
  ///
  /// The preset page shows this instead of the parameter list: in a car the
  /// user picks a mood, not a set of time constants.
  String get summary {
    switch (name) {
      case '均衡':
        return '默认观感：节奏和明暗都克制，日常听歌最稳。';
      case '夜驾柔和':
        return '更慢、更暗、色差更紧：夜里不刺眼，也不容易分心。';
      case '赛博高对比':
        return '快而艳、对比强：灯贴着鼓点跳，适合展示。';
      case '呼吸感':
        return '慢而软，像一次呼吸：驻车、怠速时最舒服。';
      case '彩虹':
        return '色相走满整圈，跟着歌一路换色，五彩但不闪。';
      case '跳跃':
        return '颜色硬切、每拍再前进一档：一直在闪，驻车展示用，夜里别开。';
    }
    return '自定义参数：把所有滑杆都放开，随便调。';
  }

  const AmbientPreset(
    this.name,
    this.attackMs,
    this.decayMs,
    this.hueTauMs,
    this.hueMaxDeg,
    this.hueMaxAccel,
    this.maxDeltaE,
    this.floor,
    this.breath,
    this.saturation, [
    this.hueSpanDeg = 150,
    this.centroidWindowLowHundredths = 0,
    this.centroidWindowSpanHundredths = 100,
    this.hueRotateDegPerSec = 0,
    this.maxChromaHundredths = 22,
    this.hueJumpDeg = 0,
    this.pulseGainHundredths = 35,
    this.beatMinGapMs = 240,
    this.jumpHoldMs = 0,
  ]);
}

/// The **parameter presets** of the ambient light V2.
///
/// ## Why there are presets
///
/// V2 has seventeen parameters (attack, decay, hue tau, the rate limit, the
/// acceleration limit, the colour difference cap, the base light, the
/// saturation, the idle breathing, the hue span, the two centroid window
/// numbers, the hue self-rotation, the chroma cap, the hue jump step, the
/// kick flash gain and the shortest kick gap). Each of them has a sensible
/// range, but making the user drag fifteen sliders in the car is not
/// realistic.
///
/// The presets give six ready made starting points for the typical
/// situations:
///
/// | preset | situation | what it trades for |
/// | --- | --- | --- |
/// | [balanced] balanced | every day | the defaults of the scheme document |
/// | [night] night driving | night, low speed | slower and weaker changes, nothing glares |
/// | [cyber] cyber high contrast | demos, performance cars | fast, strong contrast |
/// | [breathe] breathing | parked, idling | slow and soft, close to a breath |
/// | [rainbow] rainbow | demos, parked | the whole hue circle, wide and vivid |
/// | [jump] jump | demos, parked | the hue jumps in 60° steps, a flash on every kick |
///
/// ## What a preset does not touch
///
/// The engine, the colour mode, the brightness and the zone choreography are
/// **not** part of a preset: those are the user's choices, not look and feel
/// parameters. Switching a preset must not wipe them out.
class AmbientPresets {
  AmbientPresets._();

  /// Balanced: the defaults of the scheme document.
  static const AmbientPreset balanced = AmbientPreset(
    '均衡',
    45,
    260,
    260,
    60,
    240,
    1.8,
    8,
    0.10,
    0.80,
  );

  /// Night driving: slower, weaker, a tighter colour difference cap.
  static const AmbientPreset night = AmbientPreset(
    '夜驾柔和',
    70,
    520,
    420,
    32,
    120,
    1.2,
    5,
    0.16,
    0.55,
  );

  /// Cyber high contrast: responsive and vivid.
  static const AmbientPreset cyber = AmbientPreset(
    '赛博高对比',
    28,
    180,
    160,
    120,
    520,
    3.2,
    10,
    0.06,
    1.00,
  );

  /// Breathing: slow and soft, close to a breath while parked.
  static const AmbientPreset breathe = AmbientPreset(
    '呼吸感',
    140,
    700,
    600,
    22,
    90,
    1.0,
    6,
    0.22,
    0.70,
  );

  /// Rainbow: the whole hue circle, wide and vivid, still fully smooth.
  ///
  /// It combines the four levers: a 360° span, a narrow centroid window
  /// (0.20..0.65 spread to 0..1), a chroma cap of 0.32 and an 18°/s self
  /// rotation. One lever alone only gives "a little more movement".
  static const AmbientPreset rainbow = AmbientPreset(
    '彩虹',
    40,
    240,
    240,
    90,
    360,
    2.2,
    12,
    0.08,
    1.00,
    360,
    20,
    45,
    18,
    32,
  );

  /// Jump mode: the hue does not slide, it **jumps** 120° at a time, and
  /// every kick gets a flash.
  ///
  /// This is the one preset with a hue jump (120° ⇒ three steps a full
  /// circle: a big visible jump every time). The smoothing is not made
  /// faster but bypassed: a shorter tau or a higher rate limit only shortens
  /// the slide, it cannot produce a jump. Both Delta E00 limiters are off in
  /// this mode too — a limiter smears one jump into a dozen frames of ramp,
  /// which is exactly the "still too smooth" look.
  ///
  /// The wait between colour changes is capped at [jumpHoldMs] (380 ms), so
  /// a track without kick drums still flashes instead of freezing on one
  /// colour. The rest is a dark base (floor 0, no breathing) so the flash
  /// stands out, plus a full 360° span, a narrow centroid window, a 0.32
  /// chroma cap and a kick flash of 1.20× every 120 ms at most. It is
  /// deliberately the most dazzling preset.
  static const AmbientPreset jump = AmbientPreset(
    '跳跃',
    10,
    60,
    60,
    180,
    800,
    6.0,
    0,
    0.0,
    1.00,
    360,
    20,
    45,
    0,
    32,
    120,
    120,
    120,
    380,
  );

  /// All the presets, in the order the settings page shows them.
  static const List<AmbientPreset> all = [
    balanced,
    night,
    cyber,
    breathe,
    rainbow,
    jump,
  ];

  /// The labels of the presets, for the chip row.
  static List<String> get names => all.map((preset) => preset.name).toList();

  /// Which preset the current parameters match, or -1 when they match none.
  ///
  /// The settings page uses it to highlight the chip. Once the user moves a
  /// slider the chip turns into "custom", which is the honest answer.
  static int match({
    required int attackMs,
    required int decayMs,
    required int hueTauMs,
    required int hueMaxDeg,
    required int hueMaxAccel,
    required double maxDeltaE,
    required int floor,
    required double breath,
    required double saturation,
    int hueSpanDeg = 150,
    int centroidWindowLowHundredths = 0,
    int centroidWindowSpanHundredths = 100,
    int hueRotateDegPerSec = 0,
    int maxChromaHundredths = 22,
    int hueJumpDeg = 0,
    int pulseGainHundredths = 35,
    int beatMinGapMs = 240,
    int jumpHoldMs = 0,
  }) {
    for (var index = 0; index < all.length; index++) {
      final p = all[index];
      if (p.attackMs == attackMs &&
          p.decayMs == decayMs &&
          p.hueTauMs == hueTauMs &&
          p.hueMaxDeg == hueMaxDeg &&
          p.hueMaxAccel == hueMaxAccel &&
          (p.maxDeltaE - maxDeltaE).abs() < 0.01 &&
          p.floor == floor &&
          (p.breath - breath).abs() < 0.001 &&
          (p.saturation - saturation).abs() < 0.001 &&
          p.hueSpanDeg == hueSpanDeg &&
          p.centroidWindowLowHundredths == centroidWindowLowHundredths &&
          p.centroidWindowSpanHundredths == centroidWindowSpanHundredths &&
          p.hueRotateDegPerSec == hueRotateDegPerSec &&
          p.maxChromaHundredths == maxChromaHundredths &&
          p.hueJumpDeg == hueJumpDeg &&
          p.pulseGainHundredths == pulseGainHundredths &&
          p.beatMinGapMs == beatMinGapMs &&
          p.jumpHoldMs == jumpHoldMs) {
        return index;
      }
    }
    return -1;
  }
}
