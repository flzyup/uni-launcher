import 'dart:math' as math;

import 'ambient_light.dart';

/// The state of the V2 motion layer, kept across frames.
///
/// * [hue] the current hue (0..360)
/// * [hueVel] the current angular velocity (degrees per second), the second
///   order state of the hue
/// * [level] the smoothed lightness (0..1)
/// * [chroma] the smoothed chroma (the C of OKLab)
/// * [pulse] the onset envelope (0..1, 1 means just hit)
/// * [bassSlow] the slow low frequency envelope (0..1), used for onsets
/// * [brightness] the final lightness (0..1)
/// * [lastBeatAt] the moment of the last onset (milliseconds, monotonic)
/// * [initialized] whether a frame has been produced yet. The first frame
///   snaps into place, so switching on does not sweep the colour in from
///   red.
class AmbientMotionState {
  final double hue;
  final double hueVel;

  /// The accumulated "one step per onset" offset of the jump mode (degrees,
  /// 0..360).
  ///
  /// The hue is recomputed from the target on every frame
  /// (`snapHue(hueTarget, hueJumpDeg)`), so adding the step to [hue] alone
  /// would be overwritten on the next frame and the jump light would fall
  /// back to the previous step. The offset has to be carried separately.
  /// Always 0 outside the jump mode.
  final double beatHueOffsetDeg;

  final double level;
  final double chroma;
  final double pulse;
  final double bassSlow;
  final double brightness;
  final int lastBeatAt;

  /// When the jump mode last **changed colour** (monotonic milliseconds).
  ///
  /// The forced colour change interval ([AmbientMotion.jumpHoldMs]) is timed
  /// from here. Always 0 outside the jump mode.
  final int lastHopAt;

  final bool initialized;

  const AmbientMotionState({
    this.hue = 0,
    this.hueVel = 0,
    this.beatHueOffsetDeg = 0,
    this.level = 0,
    this.chroma = 0,
    this.pulse = 0,
    this.bassSlow = 0,
    this.brightness = 0,
    this.lastBeatAt = 0,
    this.lastHopAt = 0,
    this.initialized = false,
  });

  /// A copy with the given fields replaced.
  AmbientMotionState copyWith({
    double? hue,
    double? hueVel,
    double? beatHueOffsetDeg,
    double? level,
    double? chroma,
    double? pulse,
    double? bassSlow,
    double? brightness,
    int? lastBeatAt,
    int? lastHopAt,
    bool? initialized,
  }) =>
      AmbientMotionState(
        hue: hue ?? this.hue,
        hueVel: hueVel ?? this.hueVel,
        beatHueOffsetDeg: beatHueOffsetDeg ?? this.beatHueOffsetDeg,
        level: level ?? this.level,
        chroma: chroma ?? this.chroma,
        pulse: pulse ?? this.pulse,
        bassSlow: bassSlow ?? this.bassSlow,
        brightness: brightness ?? this.brightness,
        lastBeatAt: lastBeatAt ?? this.lastBeatAt,
        lastHopAt: lastHopAt ?? this.lastHopAt,
        initialized: initialized ?? this.initialized,
      );
}

/// The **motion layer (V2)** of the ambient light: it turns the jittering
/// spectrum targets into a smooth flow of light.
///
/// ## The three differences to the legacy layer
///
/// | | legacy | V2 |
/// |---|---|---|
/// | hue | first order smoothing plus a **rate limit** | **second order** (rate limit plus an **acceleration limit**) |
/// | onset | fixed threshold `bass > 0.08 && bass > slow * 1.15` | **adaptive threshold** plus a **minimum gap** |
/// | idle | frozen on the last colour | **slow drift plus a breathing base light** |
///
/// ## Why the hue has to be second order
///
/// A first order system can only bound the **speed**, not the
/// **acceleration**: on a big change the strip whips across, and when it
/// changes direction half way it visibly stutters. That stutter is a kind
/// of harshness on its own.
///
/// A second order system carries the angular velocity (`hueVel`) as well, so
/// the angular acceleration is bounded too. The strip then **turns** to the
/// new colour instead of being thrown at it and then stopping.
///
/// ## This layer is a pure state machine
///
/// It touches no platform API (no Context, no Handler): it eats the previous
/// state, the current target and the elapsed time, and produces the next
/// state, so it can be unit tested directly.
///
/// The frame rate does not matter: the smoothing factor is `1 - e^(-dt/tau)`,
/// so a dropped frame or a different rate looks the same.
class AmbientMotion {
  /// Time constant of the hue smoothing (milliseconds). Larger is stickier.
  final double hueTauMs;

  /// Upper bound on the hue speed (degrees per second), so a big jump does
  /// not make the strip whip across the ring.
  final double hueMaxDegPerSec;

  /// Upper bound on the hue angular acceleration (degrees per second
  /// squared). This is the core of the second order system and the cure for
  /// the stutter.
  final double hueMaxAccelDegPerSec2;

  /// Step of the hue jump (degrees). 0 is continuous smoothing; above 0 the
  /// hue snaps to the nearest step instead of tracking the target.
  ///
  /// The 「跳跃」 preset uses it: the colour does not slide, it **jumps**.
  /// Only speeding the smoothing up (a smaller tau, a higher rate limit, a
  /// higher acceleration limit) cannot produce a real jump: the smoother
  /// exists precisely to smear a jump into a slide.
  final double hueJumpDeg;

  /// Time constant of the lightness **rise** (milliseconds). A kick has to
  /// show up at once.
  final double attackMs;

  /// Time constant of the lightness **fall** (milliseconds). When the music
  /// stops the strip has to fade slowly.
  final double decayMs;

  /// Time constant of the low frequency envelope, used to spot an onset.
  final double bassTauMs;

  /// Decay time constant of the onset envelope, so one beat fades in about
  /// 170 ms.
  final double pulseTauMs;

  /// How much extra lightness an onset adds (as a ratio).
  final double pulseGain;

  /// Low frequency energy below this is not an onset, so the noise floor
  /// does not make the strip flicker.
  final double beatFloor;

  /// The low frequency energy has to be this much higher than the slow
  /// envelope to count as "louder than a moment ago".
  final double beatRatio;

  /// The shortest gap between two onsets (milliseconds).
  ///
  /// Without it the eighth notes of a 120 BPM track (about 250 ms apart)
  /// would each count as an onset.
  final int beatMinGapMs;

  /// How much the idle breathing moves the lightness (0..0.4).
  final double breathAmount;

  /// The forced colour change interval of the jump mode (milliseconds).
  ///
  /// 0 = only follow the beats. Onset detection is content driven: no kick
  /// in the music, or a kick the adaptive threshold has already accepted as
  /// normal, and the hue stops changing — the strip freezes again. This caps
  /// the wait, so the jump mode **keeps flashing**.
  final int jumpHoldMs;

  const AmbientMotion({
    this.hueTauMs = 260,
    this.hueMaxDegPerSec = 60,
    this.hueMaxAccelDegPerSec2 = 240,
    this.hueJumpDeg = 0,
    this.attackMs = 45,
    this.decayMs = 260,
    this.bassTauMs = 160,
    this.pulseTauMs = 170,
    this.pulseGain = 0.35,
    this.beatFloor = 0.12,
    this.beatRatio = 1.25,
    this.beatMinGapMs = 240,
    this.breathAmount = 0.10,
    this.jumpHoldMs = 0,
  });

  /// Advances one frame.
  ///
  /// [targetHue] is the hue to move towards (0..360), [targetLevel] the
  /// lightness to move towards (0..1), [targetChroma] the chroma of OKLab,
  /// [bass] the low frequency energy (0..1), [dtMs] the milliseconds since
  /// the previous frame and [nowMs] the current monotonic time.
  ///
  /// [silent] marks the "no sound" state, which runs the idle breathing.
  ///
  /// [onset] and [impact] let an external beat detector (the rhythm engine)
  /// supply the beat instead of the adaptive threshold computed here: a
  /// value above zero means "there is a beat now". [pulseDecayMs] and
  /// [pulseGain] override the built in envelope, so a slow song can flash
  /// longer and a fast one brighter. All four are optional; when they are
  /// null the local onset detection is used unchanged.
  AmbientMotionState step({
    required AmbientMotionState prev,
    required double targetHue,
    required double targetLevel,
    required double targetChroma,
    required double bass,
    required int dtMs,
    required int nowMs,
    bool silent = false,
    double? onset,
    double? impact,
    double? pulseDecayMs,
    double? pulseGain,
  }) {
    // Clamp the elapsed time: coming back from the background may take
    // minutes, and catching up in one step would look like a jump.
    final dt = dtMs.clamp(1, maxDtMs).toDouble();
    final dtS = dt / 1000;
    final tgt = targetLevel.clamp(0.0, 1.0);
    final bassNow = bass.clamp(0.0, 1.0);

    // —— Onset: an adaptive threshold plus the shortest gap. ——
    final bassSlow =
        prev.bassSlow + (bassNow - prev.bassSlow) * (1 - math.exp(-dt / bassTauMs));
    final threshold = math.max(beatFloor, bassSlow * beatRatio);
    final gapOk = nowMs - prev.lastBeatAt > beatMinGapMs;
    final detected = onset == null
        ? (bassNow > threshold && gapOk ? 1.0 : 0.0)
        : onset.clamp(0.0, 1.0);
    final trigger = math.max(detected, (impact ?? 0.0).clamp(0.0, 1.0));
    final beat = (bassNow > threshold && gapOk) || trigger > 0.05;
    final pulse = math.max(
        trigger, prev.pulse * math.exp(-dt / (pulseDecayMs ?? pulseTauMs)));
    final lastBeatAt = beat ? nowMs : prev.lastBeatAt;

    // —— Hue: second order (rate limit plus acceleration limit). ——
    // An onset pushes the hue a little towards the warm end: the kick is
    // visible, but not glaring.
    //
    // While nothing plays the hue stops chasing the last target: it only
    // drifts (see the idle branch below). The tracker would otherwise pull
    // it back and the idle drift would cancel itself out.
    final hueTarget = silent
        ? prev.hue
        : normalizeHue(targetHue + pulse * beatHuePushDeg);
    var hue = prev.hue;
    var hueVel = prev.hueVel;
    var beatHueOffsetDeg = hueJumpDeg > 0 ? prev.beatHueOffsetDeg : 0.0;
    var lastHopAt = prev.lastHopAt;
    if (hueJumpDeg > 0) {
      // 「跳跃」: no tracking, snap the hue onto the nearest step — the
      // colour **jumps**. The smoother would only smear the jump into a
      // slide, which is not a jump light.
      //
      // On top of that, **every onset advances one step**. Following the
      // spectral centroid alone changes the colour once every few dozen
      // seconds; stepping on the beat is what makes it a jump light.
      //
      // And the wait is capped: onset detection is content driven, so with
      // no kick — or a kick the adaptive threshold accepted as normal — the
      // hue would stop changing and the strip freezes. [jumpHoldMs] forces
      // one step every so often, so the jump light **keeps** flashing.
      final hop =
          beat || (jumpHoldMs > 0 && nowMs - prev.lastHopAt >= jumpHoldMs);
      if (hop) {
        beatHueOffsetDeg = normalizeHue(beatHueOffsetDeg + hueJumpDeg);
        lastHopAt = nowMs;
      }
      hue = normalizeHue(snapHue(hueTarget, hueJumpDeg) + beatHueOffsetDeg);
      hueVel = 0;
    } else if (!prev.initialized) {
      // The first frame lands on the target (the colour appears instead of
      // being swept in when the strip switches on).
      hue = hueTarget;
      hueVel = 0;
    } else {
      final delta = shortestDelta(prev.hue, hueTarget);
      // The wanted speed of a first order tracker: the gap divided by the
      // time constant, i.e. `delta / tauSeconds`.
      //
      // `1 - exp(-dt / tau)` is the **share of the gap that closes in one
      // frame** — a dimensionless ratio. Dividing it by the frame length
      // turns it into the speed at which that share is closed per second.
      // Without that division the number is a *distance* but is used as a
      // *speed*: the hue then crawls at a 64th of the intended rate and the
      // strip keeps one base colour no matter what the music does.
      final share = 1 - math.exp(-dt / hueTauMs);
      final vDesired = (delta * share / dtS)
          .clamp(-hueMaxDegPerSec, hueMaxDegPerSec);
      // The acceleration limit: this is the cure for the stutter.
      final dv = (vDesired - prev.hueVel)
          .clamp(-hueMaxAccelDegPerSec2 * dtS, hueMaxAccelDegPerSec2 * dtS);
      hueVel = prev.hueVel + dv;
      hue = normalizeHue(prev.hue + hueVel * dtS);
    }

    // —— Lightness: an asymmetric attack/decay envelope plus the onset. ——
    final base = silent ? _idleLevel(nowMs) : tgt;
    final withPulse =
        (base * (1 + pulse * (pulseGain ?? this.pulseGain))).clamp(0.0, 1.0);
    final tau = withPulse > prev.level ? attackMs : decayMs;
    final level = prev.level + (withPulse - prev.level) * (1 - math.exp(-dt / tau));

    // —— Chroma: slow smoothing (the "vividness" must not jump). ——
    // The art layer already clamped the target by the user's setting, so
    // this layer only enforces the hard ceiling: the rainbow is allowed to
    // ask for 0.32, but nothing may ever exceed 0.40.
    final chromaTarget =
        targetChroma.clamp(0.0, AmbientPalette.maxChromaHard);
    final chroma = prev.chroma +
        (chromaTarget - prev.chroma) * (1 - math.exp(-dt / chromaTauMs));

    // —— Idle: the hue drifts slowly, so the strip is never frozen. ——
    if (silent) {
      hue = normalizeHue(hue + silentHueDriftDegPerSec * dtS);
      hueVel = 0;
    }

    return AmbientMotionState(
      hue: hue,
      hueVel: hueVel,
      beatHueOffsetDeg: beatHueOffsetDeg,
      level: level.clamp(0.0, 1.0),
      chroma: chroma.clamp(0.0, AmbientPalette.maxChromaHard),
      pulse: pulse.clamp(0.0, 1.0),
      bassSlow: bassSlow.clamp(0.0, 1.0),
      brightness: level.clamp(0.0, 1.0),
      lastBeatAt: lastBeatAt,
      lastHopAt: lastHopAt,
      initialized: true,
    );
  }

  /// The breathing lightness while nothing plays (0..1).
  double _idleLevel(int nowMs) {
    if (breathAmount <= 0) return 0;
    final phase = (nowMs / 1000.0) * (2 * math.pi / silentBreathPeriodSec);
    return breathAmount * (0.5 + 0.5 * math.sin(phase));
  }

  /// The upper bound of one frame's elapsed time (milliseconds).
  static const int maxDtMs = 1000;

  /// How far an onset pushes the hue towards the warm end.
  static const double beatHuePushDeg = 14;

  /// How fast the hue drifts while nothing plays (degrees per second).
  static const double silentHueDriftDegPerSec = 2.2;

  /// The period of the idle breathing (seconds).
  static const double silentBreathPeriodSec = 6.0;

  /// The time constant of the chroma smoothing (milliseconds).
  static const double chromaTauMs = 220;

  /// The upper bound of the chroma (the C of OKLab).
  static const double maxChroma = 0.22;

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

  /// Snaps a hue onto the nearest `stepDeg` step (the result is 0..360).
  ///
  /// Six steps (60°) are red / yellow / green / cyan / blue / magenta, so a
  /// glance in the car tells "the colour changed"; a smaller step gives more
  /// steps and a finer jump. The step is clamped to `1..180`: 180 is only
  /// two poles (warm/cold), and 240 and above repeats the same pair of
  /// steps.
  static double snapHue(double hue, double stepDeg) {
    final step = stepDeg.clamp(1.0, 180.0);
    // Dart's `round` and Kotlin's `Math.round` both round a half towards
    // positive infinity for the non negative quotient here.
    return normalizeHue((hue / step).round() * step);
  }
}
