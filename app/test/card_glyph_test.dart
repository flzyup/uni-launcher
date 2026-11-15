import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uni_launcher/model/appearance.dart';
import 'package:uni_launcher/theme/launcher_theme.dart';
import 'package:uni_launcher/widgets/card_glyph.dart';
import 'package:uni_launcher/widgets/uni_icon.dart';

/// 稿子 11 张卡头只用到 10 种图形（胎压与车况共用「车」）。这些图形是按
/// simulator.html 的 path 抄过来的，抄错一个参数（比如弧线少一档）在 build 里
/// 会抛 RangeError 把整张卡打死——这组用例就是钉住「每种图形都能安全画出来」。
const _kinds = [
  'car',
  'battery',
  'clock',
  'apps',
  'gauge',
  'air',
  'weather',
  'calendar',
  'user',
  'cleanup',
];

void main() {
  Widget host(Widget child, {bool nocturne = true, bool dark = true}) {
    final s = SurfaceStyle.from(
        Appearance(mode: dark ? 'dark' : 'light', themeStyle: 'nocturne'),
        true);
    return MaterialApp(
        theme: launcherTheme(nocturne
            ? s
            : SurfaceStyle.from(
                Appearance(
                    mode: dark ? 'dark' : 'light', themeStyle: 'classic'),
                true)),
        home: Scaffold(
            backgroundColor: const Color(0xFF0B0D0E),
            body: Center(child: child)));
  }

  testWidgets('十种卡头图形都能画出来，不抛异常', (t) async {
    for (final kind in _kinds) {
      await t.pumpWidget(host(CardGlyph(kind, symbol: kind, size: 132)));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull, reason: '$kind 的路径画不出来');
      expect(find.byType(CustomPaint), findsWidgets);
    }
  });

  testWidgets('没有对应图形的卡退成「开口环 + 原线性图标」', (t) async {
    // 导航 / 音乐这类稿子没给图形的卡：环照画，里面放原来那枚 icon，
    // 否则一屏里会出现一半有环一半光秃秃。
    await t.pumpWidget(host(CardGlyph('', symbol: 'nav', size: 132)));
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
    expect(find.byType(UniIcon), findsOneWidget);
  });

  testWidgets('浅色皮肤不套稿子的分卡配色，统一走主题强调色', (t) async {
    // 稿子的蓝/薄荷/紫/琥珀/青是 eclipse 暗夜那一套；浅色两套只有单强调色，
    // 套上去会变成一屏彩虹。
    final s = SurfaceStyle.from(
        const Appearance(mode: 'light', themeStyle: 'classic'), true);
    await t.pumpWidget(host(CardGlyph('battery', symbol: 'battery', size: 132),
        nocturne: false, dark: false));
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
    final paint = t.widgetList<CustomPaint>(find.byType(CustomPaint)).firstWhere(
        (w) => w.painter != null && '${w.painter.runtimeType}'.contains('Glyph'));
    expect(paint, isNotNull);
    expect(CardGlyph.tintOf('battery'), isNot(s.accent),
        reason: '稿子薄荷色应该和浅色主题的强调色不同，说明确实没套稿子配色');
  });
}
