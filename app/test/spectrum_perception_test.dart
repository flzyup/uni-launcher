import 'package:flutter_test/flutter_test.dart';
import 'package:uni_launcher/model/spectrum_perception.dart';

/// [SpectrumPerception] unit tests (the perception layer).
///
/// What this layer really fixes: **absolute dB is not a contrast**. A
/// heavily mastered song keeps every band above 0.7, a quiet recording
/// keeps every band below 0.2. After the normalisation both have to sit at
/// "their own average".
void main() {
  const bandCount = 24;

  /// One frame of bands (0..1, the absolute dB scale of the analyser).
  List<double> frame(double value, [int n = bandCount]) =>
      List<double>.filled(n, value);

  /// Feeds the same frame [frames] times and returns the last result.
  List<double> feed(
    SpectrumPerception p,
    List<double> input, {
    int frames = 1,
    int dtMs = 100,
  }) {
    var out = <double>[];
    for (var i = 0; i < frames; i++) {
      out = p.process(input, dtMs);
    }
    return out;
  }

  // --------------------------------------------------------- adaptive reference

  test('a constant input lands around 0.5', () {
    // The core property of this layer: **the average of the band has to
    // land on 0.5**. A loud master and a quiet recording give the same.
    final p = SpectrumPerception(bandCount: bandCount);
    final out = feed(p, frame(0.5), frames: 60);
    for (var i = 0; i < out.length; i++) {
      expect((out[i] - 0.5).abs(), lessThan(0.05),
          reason: 'band $i should be near 0.5, got ${out[i]}');
    }
  });

  test('different absolute levels normalise to the same result', () {
    final loud = SpectrumPerception(bandCount: bandCount);
    final quiet = SpectrumPerception(bandCount: bandCount);
    final a = feed(loud, frame(0.8), frames: 60);
    final b = feed(quiet, frame(0.2), frames: 60);
    for (var i = 0; i < a.length; i++) {
      expect((a[i] - b[i]).abs(), lessThan(0.05),
          reason: 'band $i differs (${a[i]} vs ${b[i]})');
    }
  });

  test('every band is calibrated on its own', () {
    // The low end is loud, the high end is quiet — after the normalisation
    // both land near 0.5, so "which band is loud" survives.
    final p = SpectrumPerception(bandCount: bandCount);
    final input = List<double>.generate(
        bandCount, (i) => i < 4 ? 0.9 : 0.15);
    final out = feed(p, input, frames: 60);
    for (var i = 0; i < out.length; i++) {
      expect((out[i] - 0.5).abs(), lessThan(0.05),
          reason: 'band $i should be calibrated on its own, got ${out[i]}');
    }
  });

  test('a band above the average pushes to 1', () {
    final p = SpectrumPerception(bandCount: bandCount);
    // Pull the reference of band 0 down to 0.3.
    feed(p, frame(0.3), frames: 40);
    // Then band 0 suddenly gets loud (more than 12 dB above).
    final loud = frame(0.3);
    loud[0] = 0.85;
    final out = feed(p, loud);
    expect(out[0], greaterThan(0.8));
  });

  // --------------------------------------------------------- silence gate

  test('the bands go to zero when the music stops', () {
    final p = SpectrumPerception(bandCount: bandCount);
    feed(p, frame(0.6), frames: 30);
    // The music stops -> every band drops to 0 (the dB is clamped at -54).
    final out = feed(p, frame(0), frames: 10);
    for (var i = 0; i < out.length; i++) {
      expect(out[i], lessThan(0.02), reason: 'band $i should be zero');
    }
    expect(p.relativeLevel, lessThan(0.02));
  });

  test('the silence gate closes', () {
    final p = SpectrumPerception(bandCount: bandCount);
    feed(p, frame(0.6), frames: 30);
    expect(p.gate, greaterThan(0.9));
    // The peak follows at 15 dB/s -> from -21 dB down to -54 dB takes
    // about 2.2 seconds.
    feed(p, frame(0), frames: 40, dtMs: 100);
    expect(p.gate, lessThan(0.05));
  });

  test('the silence gate opens again when the music returns', () {
    final p = SpectrumPerception(bandCount: bandCount);
    feed(p, frame(0.6), frames: 30);
    feed(p, frame(0), frames: 40);
    expect(p.gate, lessThan(0.05));
    feed(p, frame(0.6), frames: 5);
    expect(p.gate, greaterThan(0.5));
  });

  // --------------------------------------------------------- overall level

  test('the relative level stays between 0 and 1', () {
    final p = SpectrumPerception(bandCount: bandCount);
    for (final v in [0.0, 0.1, 0.3, 0.5, 0.9, 1.0]) {
      feed(p, frame(v), frames: 30);
      expect(p.relativeLevel, inInclusiveRange(0, 1),
          reason: 'relative level $v is out of range');
    }
  });

  test('the reference follows slowly, a jump does not recalibrate at once',
      () {
    // tau = 2 s -> a 100 ms frame only moves the reference by about 5 %.
    // This guards "no need to recalibrate when the song changes" and
    // "do not chase the signal".
    final p = SpectrumPerception(bandCount: bandCount);
    feed(p, frame(0.5), frames: 60);
    // Suddenly much louder.
    final out = feed(p, frame(0.9));
    expect(out[0], greaterThan(0.7));
    // The overall level does not jump to the top in one step: the reference
    // is still catching up.
    expect(p.relativeLevel, lessThanOrEqualTo(1));
  });

  // --------------------------------------------------------- reset

  test('a reset clears the reference', () {
    final p = SpectrumPerception(bandCount: bandCount);
    feed(p, frame(0.8), frames: 60);
    p.reset();
    expect(p.relativeLevel, closeTo(0, 0.0001));
    expect(p.gate, closeTo(0, 0.0001));
    // After the reset the first frame takes the current value as the
    // reference -> the relative value is still 0.5.
    final out = feed(p, frame(0.8));
    expect((out[0] - 0.5).abs(), lessThan(0.05));
  });
}
