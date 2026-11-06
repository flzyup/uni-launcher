import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uni_launcher/model/appearance.dart';
import 'package:uni_launcher/model/lyric_timeline.dart';
import 'package:uni_launcher/theme/launcher_theme.dart';
import 'package:uni_launcher/widgets/lyric_karaoke.dart';

/// The payload shape `LyricTimeline.toJson()` produces on the Android side.
const _payload = '{"v":1,"lines":['
    '{"t":1000,"d":2000,"x":"你好世界","tr":"line one",'
    '"w":[[1000,500,"你"],[1500,500,"好"],[2000,1000,"世界"]]},'
    '{"t":5000,"d":3000,"x":"第二行","tr":"line two",'
    '"w":[[5000,1000,"第"],[6000,2000,"二行"]]}]}';

void main() {
  test('parses word timing and translation from the native payload', () {
    final timeline = LyricTimeline.parse(_payload);
    expect(timeline.lineCount, 2);
    expect(timeline.hasWordTiming, isTrue);
    expect(timeline.hasTranslation, isTrue);
    expect(timeline.at(1600).text, '你好世界');
    expect(timeline.at(1600).translation, 'line one');
  });

  test('splits sung text from the word being sung', () {
    final cursor = LyricTimeline.parse(_payload).at(1750);
    expect(cursor.completed, '你');
    expect(cursor.currentWord, '好');
    expect(cursor.wordStartMs, 1500);
    expect(cursor.wordProgressPermille, 500);
    // Half of a single-glyph word rounds up to the whole glyph: the fill leads by <1 glyph.
    expect(cursor.sungPrefix, '你好');
  });

  test('partial fill inside a multi-glyph word stays proportional', () {
    final cursor = LyricTimeline.parse(_payload).at(2500);
    expect(cursor.currentWord, '世界');
    expect(cursor.completed, '你好');
    expect(cursor.sungPrefix, '你好世');
  });

  test('a plain document never claims a word fill it cannot know', () {
    final timeline = LyricTimeline.parse('{"v":1,"lines":['
        '{"t":1000,"d":4000,"x":"only line"},'
        '{"t":6000,"d":2000,"x":"second"}]}');
    final cursor = timeline.at(2000);
    expect(cursor.wordTimed, isFalse);
    expect(cursor.sungPrefix, '');
    // The opt-in estimate splits the line evenly instead of doing nothing.
    // 9 runes, a quarter of the line elapsed: the estimate fills two of them.
    expect(cursor.estimatedSungPrefix, 'on');
  });

  test('a long break is reported as an interlude', () {
    final timeline = LyricTimeline.parse('{"v":1,"lines":['
        '{"t":1000,"d":1000,"x":"a"},'
        '{"t":20000,"d":1000,"x":"b"}]}');
    final cursor = timeline.at(8000);
    expect(cursor.interlude, isTrue);
    expect(cursor.text, '');
    expect(cursor.next, 'b');
    expect(cursor.nearby.length, greaterThanOrEqualTo(2));
  });

  test('unusable payloads degrade to empty', () {
    expect(LyricTimeline.parse(null).isEmpty, isTrue);
    expect(LyricTimeline.parse('').isEmpty, isTrue);
    expect(LyricTimeline.parse('not json').isEmpty, isTrue);
    expect(LyricTimeline.parse('{"lines":"nope"}').isEmpty, isTrue);
    expect(LyricTimeline.empty.at(1234), LyricCursor.empty);
  });

  testWidgets('karaoke layer clips the sung prefix instead of repainting the line',
      (tester) async {
    const style = TextStyle(fontSize: 24, color: Colors.white);
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 320,
          child: KaraokeText(
            text: '你好世界',
            sung: '你好',
            style: style,
            sungStyle: style,
          ),
        ),
      ),
    ));
    expect(find.text('你好世界'), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('panel shows the active line and its translation', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: launcherTheme(SurfaceStyle.from(const Appearance(), true)),
      home: Scaffold(
        body: SizedBox(
          width: 320,
          child: LyricKaraokePanel(
            timeline: LyricTimeline.parse(_payload),
            positionMs: 1600,
          ),
        ),
      ),
    ));
    expect(find.byType(KaraokeText), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}

