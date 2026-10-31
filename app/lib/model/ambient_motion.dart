import 'dart:math' as math;

/// The state of the motion layer, kept across frames.
///
/// * [hue] the current hue (0..360)
/// * [level] the smoothed loudness (0..1)
/// * [pulse] the onset envelope (0..1, 1 means just hit)
/// * [bassSlow] the slow low frequency envelope (0..1), used for onsets
/// * [brightness] the final brightness (0..1, level times the onset gain)
/// * [initialized] whether a frame has been produced yet. The first frame
///   snaps into place, so switching on does not sweep the colour in from
///   red.
class AmbientMotionState {
  final double hue;
  final double level;
  final double pulse;
  final double bassSlow;
  final double brightness;
  final bool initialized;

  const AmbientMotionState({
    this.hue = 0,
    this.level = 0,
    this.pulse = 0,
    this.bassSlow = 0,
    this.brightness = 0,
    this.initialized = false,
  });

  /// A copy with the given fields replaced.
  AmbientMotionState copyWith({
    double? hue,
    double? level,
    double? pulse,
    double? bassSlow,
    double? brightness,
    bool? initialized,
  }) =>
      AmbientMotionState(
        hue: hue ?? this.hue,
        level: level ?? this.level,
        pulse: pulse ?? this.pulse,
        bassSlow: bassSlow ?? this.bassSlow,
        brightness: brightness ?? this.brightness,
        initialized: initialized ?? this.initialized,
      );
}

/// The motion layer of the ambient light: it turns the jittering spectrum
/// targets into a smooth flow of light.
///
/// ## Why this layer exists
///
/// The spectrum arrives ten times a second and the mapping used to be one
/// step:
///
/// ```text
/// spectrum (10 Hz) -> loudest low band -> hue -> scale by brightness -> car
/// ```
///
/// Three things in that chain are inherently step shaped:
///
/// 1. **The hue is picked discretely.** The bass mode takes the loudest low
///    band, and the bands are `360 / count` degrees apart, so every kick
///    swaps the band and the hue jumps.
/// 2. **The brightness is multiplied into the RGB.** The raw spectrum
///    strength becomes the visible brightness, so the strip shakes along
///    with the 10 Hz steps.
/// 3. **The head unit only has three brightness steps.** Every continuous
///    change has to come from the RGB we write, and each write is a step.
///
/// The result is a light that jumps instead of flowing.
///
/// ## What this layer does
///
/// | | how | effect |
/// |---|---|---|
/// | **hue** | exponential smoothing, **shortest path**, rate limit | the colour flows along the ring instead of jumping between bands; 359° to 1° travels 2° instead of going all the way around |
/// | **brightness** | **fast attack, slow decay** (two time constants) | a kick lights up at once, and the strip fades slowly when the music stops, instead of shaking with the spectrum |
/// | **beat** | low frequency **onset detection** with a decaying envelope | every kick adds a "heartbeat", so the strip breathes |
///
/// ## Why it is a pure state machine
///
/// This layer touches no platform API: it eats the previous state, the
/// current target and the elapsed time, and produces the next state. That
/// makes it fully unit testable.
///
/// The frame rate does not matter: the smoothing factor is `1 - e^(-dt/tau)`,
/// so a dropped frame or a different rate looks the same.
class AmbientMotion {
  /// Time constant of the hue smoothing (milliseconds). Larger is stickier.
  final double hueTauMs;

  /// Upper bound on the hue speed (degrees per second), so a big jump does
  /// not make the strip whip across the ring.
  final double hueMaxDegPerSec;

  /// Time constant of the brightness **rise** (milliseconds). A kick has to
  /// show up at once.
  final double attackTauMs;

  /// Time constant of the brightness **fall** (milliseconds). When the
  /// music stops the strip has to fade slowly.
  final double decayTauMs;

  /// Time constant of the low frequency envelope, used to spot an onset.
  final double bassTauMs;

  /// Decay time constant of the onset envelope, so one beat fades in about
  /// 170 ms.
  final double pulseTauMs;

  /// How much extra brightness an onset adds (as a ratio).
  final double pulseGain;

  /// Low frequency energy below this is not an onset, so the noise floor
  /// does not make the strip flicker.
  final double beatFloor;

  /// The low frequency energy has to be this much higher than the slow
  /// envelope to count as "louder than a moment ago".
  final double beatRatio;

  const AmbientMotion({
    this.hueTauMs = 320,
    this.hueMaxDegPerSec = 90,
    this.attackTauMs = 50,
    this.decayTauMs = 320,
    this.bassTauMs = 160,
    this.pulseTauMs = 170,
    this.pulseGain = 0.45,
    this.beatFloor = 0.08,
    this.beatRatio = 1.15,
  });

  /// Advances one frame.
  ///
  /// [targetHue] is the hue to move towards (0..360), [targetLevel] the
  /// brightness to move towards (0..100), [bass] the low frequency energy
  /// (0..1) and [dtMs] the milliseconds since the previous frame.
  AmbientMotionState step({
    required AmbientMotionState prev,
    required double targetHue,
    required int targetLevel,
    required double bass,
    required int dtMs,
    double? onset,
    double? impact,
    double? pulseDecayMs,
    double? pulseGain,
  }) {
    // Clamp the elapsed time: coming back from the background may take
    // minutes, and catching up in one step would look like a jump.
    final dt = dtMs.clamp(1, maxDtMs).toDouble();
    final target = targetLevel.clamp(0, 100) / 100;
    final bassNow = bass.clamp(0.0, 1.0);

    // Brightness: fast attack, slow decay.
    final tau = target > prev.level ? attackTauMs : decayTauMs;
    final level =
        prev.level + (target - prev.level) * (1 - math.exp(-dt / tau));

    // Hue: exponential smoothing, then the shortest path, then the rate
    // limit.
    double hue;
    if (!prev.initialized) {
      // The first frame lands on the target, so the colour appears instead
      // of being swept in.
      hue = normalizeHue(targetHue);
    } else {
      final delta = shortestDelta(prev.hue, targetHue);
      final eased = delta * (1 - math.exp(-dt / hueTauMs));
      final maxStep = hueMaxDegPerSec * dt / 1000;
      hue = normalizeHue(prev.hue + eased.clamp(-maxStep, maxStep));
    }

    // Onset: the low frequency jumped above the slow envelope.
    final bassSlow = prev.bassSlow +
        (bassNow - prev.bassSlow) * (1 - math.exp(-dt / bassTauMs));
    final beat = bassNow > beatFloor && bassNow > bassSlow * beatRatio;
    final detected = onset == null ? (beat ? 1.0 : 0.0) : onset.clamp(0.0, 1.0);
    final trigger = math.max(detected, (impact ?? 0).clamp(0.0, 1.0));
    final pulse = math.max(
        trigger, prev.pulse * math.exp(-dt / (pulseDecayMs ?? pulseTauMs)));

    // Final brightness: the level plus the onset gain.
    final brightness =
        (level * (1 + pulse * (pulseGain ?? this.pulseGain))).clamp(0.0, 1.0);

    return AmbientMotionState(
      hue: hue,
      level: level.clamp(0.0, 1.0),
      pulse: pulse.clamp(0.0, 1.0),
      bassSlow: bassSlow.clamp(0.0, 1.0),
      brightness: brightness,
      initialized: true,
    );
  }

  /// The upper bound of one frame's elapsed time (milliseconds).
  static const int maxDtMs = 1000;

  /// The shortest angle between two hues, in `(-180, 180]`.
  ///
  /// The hue is a circle: 359° to 1° is 2° apart, but going the long way
  /// would be 358° through the whole ring. So the interpolation has to
  /// take the short way round.
  static double shortestDelta(double from, double to) {
    var d = (to - from) % 360;
    if (d > 180) d -= 360;
    if (d <= -180) d += 360;
    return d;
  }

  /// Normalises a hue into 0..360.
  static double normalizeHue(double hue) {
    var h = hue % 360;
    if (h < 0) h += 360;
    return h;
  }
}
