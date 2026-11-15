import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uni_launcher/model/appearance.dart';
import 'package:uni_launcher/theme/launcher_theme.dart';
import 'package:uni_launcher/widgets/glass_surface.dart';

/// 卡底压暗带**只属于桌面卡片**。
///
/// 设计稿里它是 `.card` 的装饰，设置面板、弹窗、列表块（`.blk`）上都没有。
/// 这条测试就是那个约束的守卫：漏了 `card: true` 的卡片会被抓到，
/// 而面板/弹窗多画了一条压暗带也会被抓到。
///
/// 右上角那道 45° 弧线（`.tick`）已经整条删掉：它纯装饰，摆在卡片角落却像
/// 一个可点的「关闭」控件。这里顺手钉住"不许再回来"。
void main() {
  Future<void> pump(WidgetTester t, String themeStyle,
      {required bool asCard, bool dark = true}) async {
    final appearance = Appearance().copyWith(themeStyle: themeStyle);
    await t.pumpWidget(MaterialApp(
        theme: launcherTheme(SurfaceStyle.from(appearance, dark)),
        home: Scaffold(
            body: Center(
                child: SizedBox(
                    width: 400,
                    height: 300,
                    child: GlassSurface(
                        card: asCard, child: const Text('内容')))))));
    await t.pumpAndSettle();
  }

  for (final style in Appearance.themeStyles) {
    testWidgets('$style：卡片与面板都不再画角刻线', (t) async {
      for (final asCard in [true, false]) {
        await pump(t, style, asCard: asCard);
        expect(find.byKey(const ValueKey('card-corner-tick')), findsNothing,
            reason: '${asCard ? '卡片' : '面板'}上又出现了角刻线');
        expect(t.takeException(), isNull);
      }
    });
  }

  testWidgets('classic 浅色卡片不压暗底部', (t) async {
    await pump(t, 'classic', asCard: true, dark: false);
    // 浅底主题的 cardShade = 0，不应出现黑色渐变层。
    final shades = t
        .widgetList<DecoratedBox>(find.byType(DecoratedBox))
        .where((box) {
      final d = box.decoration;
      if (d is! BoxDecoration) return false;
      final g = d.gradient;
      return g is LinearGradient &&
          g.colors.last != const Color(0x00000000) &&
          g.colors.last.a > 0 &&
          g.colors.last.r == 0 &&
          g.colors.last.g == 0 &&
          g.colors.last.b == 0;
    });
    expect(shades, isEmpty);
    expect(t.takeException(), isNull);
  });
}
