import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uni_launcher/theme/design_tokens.dart';
import 'package:uni_launcher/widgets/marquee_text.dart';

void main() {
  testWidgets('fitting music metadata stays static', (tester) async {
    await tester.pumpWidget(const MaterialApp(
        home: Center(
            child: SizedBox(
                width: 300,
                child: MarqueeText(
                    key: ValueKey('short-title'),
                    data: '短标题',
                    style: TextStyle(fontSize: 20))))));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('短标题'), findsOneWidget);
    expect(
        find.byKey(const ValueKey('marquee-paint-short-title')), findsNothing);
  });

  testWidgets('overflowing title and album scroll continuously',
      (tester) async {
    const title = '特别长的歌名用于验证音乐卡片会在超出宽度后自动滚动显示完整内容';
    await tester.pumpWidget(MaterialApp(
        home: Center(
            child: SizedBox(
                width: 180,
                child: MarqueeText(
                    key: const ValueKey('long-title'),
                    data: title,
                    style: TextStyle(
                        fontSize: Design.px(20),
                        height: 1.2,
                        fontWeight: FontWeight.w500))))));
    await tester.pump();
    final before = _offset(tester, 'marquee-paint-long-title');
    await tester.pump(const Duration(milliseconds: 500));
    final after = _offset(tester, 'marquee-paint-long-title');
    expect(after, greaterThan(before));
    expect(tester.takeException(), isNull);
  });

  testWidgets('overflowing text has width and inherits the theme text color',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Material(
        child: DefaultTextStyle(
          style: TextStyle(color: Colors.white, fontFamily: 'Roboto'),
          child: Center(
            child: SizedBox(
              width: 180,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  MarqueeText(
                    key: ValueKey('inherited'),
                    data:
                        'long text that exceeds the available width repeatedly',
                    style: TextStyle(fontSize: 20),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 100));
    final finder = find.byKey(const ValueKey('marquee-paint-inherited'));
    final paint = tester.widget<CustomPaint>(finder);
    expect(tester.getSize(finder).width, 180);
    final span = (paint.painter as MarqueePainter).text.text as TextSpan;
    expect(span.style?.color, Colors.white);
    expect(span.style?.fontFamily, 'Roboto');
  });
}

double _offset(WidgetTester tester, String key) {
  final paint = tester.widget<CustomPaint>(find.byKey(ValueKey(key)));
  return (paint.painter as MarqueePainter).offset;
}
