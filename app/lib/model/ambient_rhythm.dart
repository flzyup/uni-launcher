import 'dart:math' as math;

/// Bounded streaming onset detector for already captured logarithmic bands.
/// No artificial beats are generated when the music has no reliable pulse.
class AmbientRhythm {
  static const bassBand = 0;
  static const midBand = 1;
  static const trebleBand = 2;

  List<double> _previous = const [];
  final List<int> _intervals = [];
  double _baseline = 0;
  double _bassBaseline = 0;
  double _midBaseline = 0;
  double _trebleBaseline = 0;
  int? _lastBeat;
  int? _lastBeatBand;
  int? _previousBeatBand;

  void reset() {
    _previous = const [];
    _intervals.clear();
    _baseline = 0;
    _bassBaseline = 0;
    _midBaseline = 0;
    _trebleBaseline = 0;
    _lastBeat = null;
    _lastBeatBand = null;
    _previousBeatBand = null;
  }

  RhythmFrame step(List<double> bands, int nowMs) {
    if (bands.isEmpty) return const RhythmFrame();

    /// Percussion and bells are narrow. An arithmetic mean over a whole
    /// region dilutes them; the strongest few bins preserve the hit while
    /// still requiring more than one FFT bin to agree.
    double topMean(List<double> values, int count) {
      if (values.isEmpty) return 0;
      final ordered = List<double>.of(values)..sort((a, b) => b.compareTo(a));
      var sum = 0.0;
      final n = count.clamp(1, ordered.length);
      for (var i = 0; i < n; i++) {
        sum += ordered[i].clamp(0.0, 1.0);
      }
      return sum / n;
    }

    double region(int start, int end) => topMean(
        bands
            .getRange(start.clamp(0, bands.length), end.clamp(0, bands.length))
            .map((value) => value.clamp(0.0, 1.0))
            .toList(growable: false),
        start == 0
            ? 3
            : start == 5
                ? 4
                : 3);

    final bass = region(0, 5), mid = region(5, 15), treble = region(15, 24);
    var flux = 0.0, bassFlux = 0.0, midFlux = 0.0, trebleFlux = 0.0;
    if (_previous.length == bands.length) {
      List<double> rises(int start, int end) => [
            for (var i = start; i < end && i < bands.length; i++)
              (bands[i] - _previous[i]).clamp(0.0, 1.0)
          ];

      bassFlux = topMean(rises(0, 5), 3);
      midFlux = topMean(rises(5, 15), 4);
      trebleFlux = topMean(rises(15, 24), 3);
      flux = (bassFlux * 2 + midFlux * 1.15 + trebleFlux * .65) / 3.8;
    }
    _previous = List<double>.of(bands);
    final threshold = math.max(.025, _baseline * 1.45);
    final bassThreshold = math.max(.04, _bassBaseline * 1.38);
    final midThreshold = math.max(.035, _midBaseline * 1.36);
    final trebleThreshold = math.max(.028, _trebleBaseline * 1.32);
    _baseline += (flux - _baseline) * .10;
    _bassBaseline += (bassFlux - _bassBaseline) * .08;
    _midBaseline += (midFlux - _midBaseline) * .08;
    _trebleBaseline += (trebleFlux - _trebleBaseline) * .07;
    final since = _lastBeat == null ? 9999 : nowMs - _lastBeat!;

    // Normalize each region against its own noise floor. Without this the
    // fixed priority order can hide the mid region whenever bass and treble
    // are also active.
    final bassScore =
        bassFlux / bassThreshold * 1.04 + math.max(0, bass - .06) * .35;
    final midScore =
        midFlux / midThreshold * 1.14 + math.max(0, mid - .05) * .30;
    final trebleScore =
        trebleFlux / trebleThreshold * 1.08 + math.max(0, treble - .04) * .25;
    final bassOnset = bassScore > 1.15 && bass > .06;
    final midOnset = midScore > 1.12 && mid > .05;
    final trebleOnset = trebleScore > 1.10 && treble > .04;
    final generalOnset = flux > threshold;
    final anyBandOnset = bassOnset || midOnset || trebleOnset;
    final onset = (anyBandOnset || generalOnset) && since >= 170;

    int band;
    double selectedFlux, selectedEnergy, selectedScore;
    if (bassOnset &&
        (!midOnset || bassScore >= midScore) &&
        (!trebleOnset || bassScore >= trebleScore)) {
      band = bassBand;
      selectedFlux = bassFlux;
      selectedEnergy = bass;
      selectedScore = bassScore;
    } else if (midOnset && (!trebleOnset || midScore >= trebleScore)) {
      band = midBand;
      selectedFlux = midFlux;
      selectedEnergy = mid;
      selectedScore = midScore;
    } else if (trebleOnset) {
      band = trebleBand;
      selectedFlux = trebleFlux;
      selectedEnergy = treble;
      selectedScore = trebleScore;
    } else if (generalOnset) {
      band = bass >= mid && bass >= treble
          ? bassBand
          : mid >= treble
              ? midBand
              : trebleBand;
      selectedFlux = flux;
      selectedEnergy = math.max(bass, math.max(mid, treble));
      selectedScore = flux / threshold;
    } else {
      band = _lastBeatBand ?? bassBand;
      selectedFlux = 0;
      selectedEnergy = 0;
      selectedScore = 0;
    }

    if (onset) {
      if (since >= 190 && since <= 1200) {
        _intervals.add(since);
        if (_intervals.length > 6) _intervals.removeAt(0);
      } else if (since > 2000) {
        _intervals.clear();
      }
      _lastBeat = nowMs;
      _previousBeatBand = _lastBeatBand;
      _lastBeatBand = band;
    }
    final sorted = List<int>.of(_intervals)..sort();
    final interval = sorted.isEmpty ? 500 : sorted[sorted.length ~/ 2];
    final bpm = sorted.length >= 3 ? 60000 / interval : null;
    final nextBeatMs =
        bpm == null || _lastBeat == null ? null : _lastBeat! + interval;
    final strength = (selectedScore / 2).clamp(.42, 1.0);
    final impact = onset
        ? (.60 + selectedFlux * .52 + selectedEnergy * .26).clamp(.70, 1.0)
        : 0.0;
    final predictedBand = _previousBeatBand == null || _lastBeatBand == null
        ? _lastBeatBand ?? bassBand
        : _previousBeatBand != _lastBeatBand
            ? (_lastBeatBand == bassBand
                ? trebleBand
                : _lastBeatBand == trebleBand
                    ? bassBand
                    : (bass >= treble ? bassBand : trebleBand))
            : _lastBeatBand!;
    return RhythmFrame(
        bass: bass,
        mid: mid,
        treble: treble,
        onset: onset ? strength : 0,
        impact: impact,
        band: band,
        predictedBand: predictedBand,
        bpm: bpm,
        intervalMs: interval,
        nextBeatMs: nextBeatMs);
  }
}

class RhythmFrame {
  final double bass, mid, treble, onset, impact;
  final int band, predictedBand;
  final double? bpm;
  final int intervalMs;
  final int? nextBeatMs;
  const RhythmFrame(
      {this.bass = 0,
      this.mid = 0,
      this.treble = 0,
      this.onset = 0,
      this.impact = 0,
      this.band = AmbientRhythm.bassBand,
      this.predictedBand = AmbientRhythm.bassBand,
      this.bpm,
      this.intervalMs = 500,
      this.nextBeatMs});
}
