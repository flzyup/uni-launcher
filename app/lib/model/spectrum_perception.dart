import 'dart:math' as math;

/// The **perception layer** of the spectrum: it turns "absolute dB" into
/// "how strong this band is compared to its own average".
///
/// ## Why this layer exists
///
/// The native capture hands out **absolute** dB calibration: `(db + 54) / 54`.
/// An absolute scale means "how loud the kick drum of this recording is"
/// depends on the **mastering level**:
///
/// - a heavily compressed master has every band above 0.7, so the strip is
///   always bright and the movement is invisible;
/// - a quiet recording has every band below 0.2, so the strip is always dim.
///
/// That is one of the reasons the old version was called "the brightness does
/// not move much": **an absolute level carries no contrast**.
///
/// ## What this layer does
///
/// ### 1. One slow reference level per band (symmetric EMA, tau = 2000 ms)
///
/// ```dart
/// bandRef[i] += (rawDb[i] - bandRef[i]) * (1 - exp(-dtMs / 2000))
/// relative[i] = ((rawDb[i] - bandRef[i] + 12) / 24).clamp(0, 1)
/// ```
///
/// Every band **calibrates itself**: the average of the band lands on 0.5,
/// 12 dB above the average is 1, 12 dB below is 0. Quiet passages still move,
/// and a new song needs no re-calibration.
///
/// ### 2. A silence gate (the overall peak follows, falling 15 dB per second)
///
/// When the music stops, every band falls to the floor together and the gate
/// closes to 0, so the strip fades to its base light instead of **freezing
/// on the last colour**.
///
/// ## Why not a min/max AGC
///
/// A min/max pair of trackers was tried before: when the signal stays high
/// the lower tracker runs along with it (it rises faster than it falls), the
/// normalised band ends up constantly zero, and a wrong initial value takes
/// more than ten seconds to settle. A symmetric EMA has neither problem: it
/// always centres on the current average.
///
/// ## The same formula as the demo and the cardesk build
///
/// The numbers measured on the demo (`docs/ambient-spectrum/demo.html`) come
/// from this exact formula. The car build has to run the same one, otherwise
/// the behaviour on the road has no reference to compare against.
class SpectrumPerception {
  /// The slow reference level of every band (dB).
  final List<double> _bandRefDb;

  /// The perceptual weights: the low end gets a boost, the high end a cut.
  ///
  /// The ear is more sensitive to the low end, but the low end already
  /// carries more energy. Without the weights the overall level would be
  /// owned by the bass and the movement up top would be invisible.
  final List<double> _weights;

  /// The overall peak follower (dB).
  double _peakDb;

  /// Whether the reference levels have been primed yet.
  bool _refInitialized = false;

  /// The **relative** level of the last frame (0..1).
  ///
  /// This is what the art layer maps to a brightness.
  double relativeLevel = 0;

  /// The silence gate of the last frame (0..1).
  double gate = 0;

  /// The overall raw level of the last frame (dB). For diagnostics.
  double overallDb = _silentDb;

  SpectrumPerception({int bandCount = 24})
      : _bandRefDb = List<double>.filled(bandCount, 0),
        _weights = List<double>.generate(
          bandCount,
          (i) => i < 4 ? 3.0 : (i < 12 ? 1.6 : 0.7),
        ),
        _peakDb = _silentDb;

  /// Processes one spectrum frame.
  ///
  /// [input] holds the **absolute dB calibrated** bands (0..1, the
  /// `(db + 54) / 54` convention) and [dtMs] the milliseconds since the
  /// previous frame.
  ///
  /// Returns the normalised relative bands (0..1).
  List<double> process(List<double> input, int dtMs) {
    final n = math.min(input.length, _bandRefDb.length);
    final out = List<double>.filled(n, 0);
    if (n == 0) {
      relativeLevel = 0;
      gate = 0;
      overallDb = _silentDb;
      return out;
    }
    // Clamp the elapsed time: coming back from the background may take
    // minutes, and catching up in one step would look like a jump.
    final dt = dtMs.clamp(1, maxDtMs).toDouble();
    final dtS = dt / 1000;
    final alpha = 1 - math.exp(-dt / defaultRefTauMs);

    // —— 1. Back to dB, and the overall raw level (perceptually weighted). ——
    //
    // `calibrate()` is `(db - DB_FLOOR) / DB_RANGE`, so the inverse is
    // `db = v * DB_RANGE + DB_FLOOR`.
    var ps = 0.0;
    var wsum = 0.0;
    for (var i = 0; i < n; i++) {
      final db = input[i] * dbRange + dbFloor;
      final w = _weights[i];
      // Add in the power domain (averaging dB directly would be wrong).
      ps += math.pow(10, db / 10).toDouble() * w;
      wsum += w;
    }
    overallDb = ps > 0 && wsum > 0 ? 10 * math.log(ps / wsum) / math.ln10 : _silentDb;

    // —— 2. The overall peak follower feeds the silence gate. ——
    _peakDb = math.max(overallDb, _peakDb - peakFallDbPerSec * dtS);
    final g = ((_peakDb + gateSilentDb) / gateRangeDb).clamp(0.0, 1.0);
    gate = g;

    // —— 3. One adaptive reference per band, then the relative value. ——
    var sum = 0.0;
    for (var i = 0; i < n; i++) {
      final db = input[i] * dbRange + dbFloor;
      if (!_refInitialized) {
        _bandRefDb[i] = db;
      } else {
        _bandRefDb[i] += (db - _bandRefDb[i]) * alpha;
      }
      // 12 dB above the average is 1, 12 dB below is 0.
      final x = ((db - _bandRefDb[i] + relHalfSpanDb) / relSpanDb)
          .clamp(0.0, 1.0);
      final v = x * g;
      out[i] = v;
      sum += v * v * _weights[i];
    }
    _refInitialized = true;

    // —— 4. The overall relative level is a perceptually weighted RMS. ——
    //
    // RMS instead of a mean: it is more sensitive to "several bands are loud
    // at once", so a kick (the whole low end lifts) pushes the level up.
    relativeLevel =
        wsum > 0 ? math.sqrt(sum / wsum).clamp(0.0, 1.0) : 0.0;
    return out;
  }

  /// Resets the state (a new song, or the capture restarted).
  void reset() {
    for (var i = 0; i < _bandRefDb.length; i++) {
      _bandRefDb[i] = 0;
    }
    _peakDb = _silentDb;
    _refInitialized = false;
    relativeLevel = 0;
    gate = 0;
    overallDb = _silentDb;
  }

  /// The time constant of the per band reference (milliseconds).
  static const double defaultRefTauMs = 2000;

  /// How fast the overall peak falls (dB per second).
  static const double peakFallDbPerSec = 15;

  /// The span of the relative value (dB).
  ///
  /// 12 dB above the reference is 1, 12 dB below is 0, so the window is
  /// 24 dB wide.
  static const double relSpanDb = 24;

  /// Half of the relative span (plus or minus 12 dB).
  static const double relHalfSpanDb = 12;

  /// The dB calibration floor, matching `SpectrumBands` on the native side.
  static const double dbFloor = -54;

  /// The dB calibration range, matching `SpectrumBands` on the native side.
  static const double dbRange = 54;

  /// The level at which the silence gate closes (dB).
  ///
  /// ## Why not the -70 dB of the demo
  ///
  /// The demo reads the raw dB of Web Audio, which reaches -140. Here the
  /// native side hands out `(db + 54) / 54` and **clamps it to 0..1**, so the
  /// dB is pinned between **-54 and 0** and everything below -54 dB is lost.
  ///
  /// So the threshold has to live inside -54 dB: -54 dB is "completely
  /// silent" and -48 dB or above counts as "there is sound". The 6 dB in
  /// between is the ramp, so the gate does not snap on and off.
  static const double gateSilentDb = 54;

  /// The width of the silence gate ramp (dB).
  static const double gateRangeDb = 6;

  /// The level of "completely no sound" (dB).
  static const double _silentDb = -60;

  /// The upper bound of one frame's elapsed time (milliseconds).
  static const int maxDtMs = 1000;
}
