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

  testWidgets('暗夜开关圆点同样是白色部件，靠投影与青轨道分开', (t) async {
    final s = SurfaceStyle.from(
        const Appearance(mode: 'dark', themeStyle: 'nocturne'), true);
    expect(s.dark, isTrue);
    await t.pumpWidget(host(s, const DesignSwitch(value: true)));

    // 开态曾经取 s.accentText —— 那是给青底上的**文字**用的深色，圆点
    // 于是变成一颗黑洞（用户 2026-11-19 在暗夜深色开关截图上指出来）。
    // 圆点一律白，不分明暗、不分开态。
    expect(knobColor(t), Colors.white);
    expect(knobColor(t), isNot(s.accentText), reason: '青底上那个深色圆点就是 bug');

    // 白点压在亮青轨道上，对比度天然到不了 4.5（白 vs 亮青只有 1 点几），
    // 所以边界靠一圈黑投影勾出来。这里锁住投影，避免以后有人为了「对比度」
    // 把圆点又改回深色。
    final box = t.widget<Container>(find
        .descendant(
            of: find.byType(DesignSwitch), matching: find.byType(Container))
        .last);
    expect((box.decoration as BoxDecoration).boxShadow, isNotNull,
        reason: '没有投影的话白点会糊进亮青轨道');
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
              of: find.byType(GlassSurface),
              matching: find.byType(DecoratedBox)))
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
