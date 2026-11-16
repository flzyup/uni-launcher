import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uni_launcher/model/appearance.dart';
import 'package:uni_launcher/theme/launcher_theme.dart';
import 'package:uni_launcher/widgets/choice_button.dart';
import 'package:uni_launcher/widgets/glass_surface.dart';

/// 开关圆点是「白色部件」。
///
/// 它以前取 `s.text`：暗色皮肤下 s.text 恰好是白，所以一直看不出问题；浅色下
/// s.text 是深墨，圆点就成了深蓝块（用户实测报的正是这个）。这里把两套皮肤的
/// 圆点色钉住，避免以后又有人拿正文色去画控件。
void main() {
  Widget host(SurfaceStyle style, Widget child) => MaterialApp(
        theme: launcherTheme(style),
        home: Scaffold(body: Center(child: child)),
      );

  Color knobColor(WidgetTester t) {
    final box = t.widget<Container>(find
        .descendant(
            of: find.byType(DesignSwitch), matching: find.byType(Container))
        .last);
    return (box.decoration as BoxDecoration).color!;
  }

  testWidgets('浅色皮肤下开关圆点是白色，不是正文色', (t) async {
    final s = SurfaceStyle.from(
        const Appearance(mode: 'light', themeStyle: 'classic'), false);
    expect(s.dark, isFalse, reason: '这一档必须是浅色，否则本测试没意义');
    await t.pumpWidget(host(s, const DesignSwitch(value: true)));
    expect(knobColor(t), Colors.white);
    expect(knobColor(t), isNot(s.text), reason: '深墨色圆点就是那个 bug');
  });

  testWidgets('暗夜皮肤保持原样：圆点仍是正文色（白）', (t) async {
    final s = SurfaceStyle.from(
        const Appearance(mode: 'dark', themeStyle: 'nocturne'), true);
    expect(s.dark, isTrue);
    await t.pumpWidget(host(s, const DesignSwitch(value: true)));
    expect(knobColor(t), s.text);
  });

  testWidgets('降级时暗夜卡片阴影收一半，正常态不动', (t) async {
    Future<List<BoxShadow>> shadows({required bool lowPower}) async {
      final s = SurfaceStyle.from(
          const Appearance(mode: 'dark', themeStyle: 'nocturne'), true,
          lowPower: lowPower);
      await t.pumpWidget(MaterialApp(
          theme: launcherTheme(s),
          home: const Scaffold(
              body: GlassSurface(
                  shadow: true, child: SizedBox(width: 40, height: 40)))));
      // MaterialApp 里是 AnimatedTheme：换主题后要等过渡结束，否则 Theme.of
      // 拿到的是 lerp(t=0) 的旧主题，lowPower 根本传不到卡片里。
      await t.pumpAndSettle();
      // 卡片里有好几层 DecoratedBox（底色/渐变/外阴影），带 boxShadow 的那个才是外层。
      final boxes = t
          .widgetList<DecoratedBox>(find.descendant(
              of: find.byType(GlassSurface), matching: find.byType(DecoratedBox)))
          .where((b) => (b.decoration as BoxDecoration).boxShadow != null);
      return (boxes.single.decoration as BoxDecoration).boxShadow!;
    }

    final normal = (await shadows(lowPower: false)).single;
    expect(normal.blurRadius, 54);
    expect(normal.spreadRadius, -26);

    // 宽高斯是 raster 里最贵的一笔，降级时砍半；视觉上只是浮起感弱一点。
    final degraded = (await shadows(lowPower: true)).single;
    expect(degraded.blurRadius, 26);
    expect(degraded.spreadRadius, -13);
  });
}
