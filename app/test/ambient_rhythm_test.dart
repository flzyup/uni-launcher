import 'package:flutter_test/flutter_test.dart';
import 'package:uni_launcher/model/ambient_rhythm.dart';

void main() {
  test('separates bass and treble and detects timed transients', () {
    final rhythm = AmbientRhythm();
    final silence = List<double>.filled(24, 0);
    final bass = List<double>.filled(24, 0)..fillRange(0, 5, 1);
    rhythm.step(silence, 0);
    RhythmFrame frame = const RhythmFrame();
    for (var t = 500; t <= 2500; t += 500) {
      frame = rhythm.step(bass, t);
      expect(frame.onset, greaterThan(0));
      expect(frame.impact, greaterThan(.6));
      expect(frame.bass, greaterThan(frame.treble));
      expect(frame.band, AmbientRhythm.bassBand);
      rhythm.step(silence, t + 100);
    }
    expect(frame.bpm, closeTo(120, 1));
    expect(frame.nextBeatMs, 3000);
    final treble = List<double>.filled(24, 0)..fillRange(15, 24, 1);
    final high = rhythm.step(treble, 3000);
    expect(high.treble, greaterThan(high.bass));
    expect(high.impact, greaterThan(.6));
    expect(high.band, AmbientRhythm.trebleBand);
    final mid = List<double>.filled(24, 0)..fillRange(5, 15, 1);
    rhythm.step(silence, 3100);
    final centre = rhythm.step(mid, 3300);
    expect(centre.mid, greaterThan(centre.bass));
    expect(centre.impact, greaterThan(.6));
    expect(centre.band, AmbientRhythm.midBand);
  });

  test('sustained sound and silence do not invent beats', () {
    final rhythm = AmbientRhythm();
    final signal = List<double>.filled(24, .5);
    rhythm.step(signal, 0);
    for (var t = 100; t < 2000; t += 100) {
      expect(rhythm.step(signal, t).onset, 0);
    }
    rhythm.reset();
    expect(rhythm.step(List.filled(24, 0), 3000).onset, 0);
  });
}
