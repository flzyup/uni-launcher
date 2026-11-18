import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uni_launcher/model/appearance.dart';
import 'package:uni_launcher/theme/launcher_theme.dart';
import 'package:uni_launcher/widgets/card_glyph.dart';
import 'package:uni_launcher/widgets/vehicle_cards.dart';
import 'package:uni_launcher/widgets/vehicle_visuals.dart';

/// 设计稿的圆环（`rc-mint` / `rc-cyan`）在 sim 的 `migrateSvgColors` 里被改过色：
/// `#3BE2C0` → `rgb(var(--acc))`，`#6FD3FF` 保持固定。所以环是「一端固定青、
/// 一端跟主题配色」——换「玫瑰 / 琥珀」时弧尖那段跟着变，起弧那段青不动。
///
/// 这个效果**三套皮肤都要有**（用户 2026-11-13 晚：之前只有暗夜实现）。
void main() {
  Map<String, dynamic> native78() {
    final now = DateTime.now().millisecondsSinceEpoch;
    Map<String, dynamic> f(num v, String unit) =>
        {'value': v, 'unit': unit, 'valid': true, 'updatedAtMs': now};
    return {
      'vehicle': {
        'connected': true,
        'fields': {
          'batteryPercent': f(78, '%'),
          'range': f(342, 'km'),
          'odometer': f(12345, 'km'),
        },
        'writable': false,
      }
    };
  }

  Future<CardRing> ring(WidgetTester t, Appearance look) async {
    final style = SurfaceStyle.from(look, look.mode == 'dark');
    await t.pumpWidget(MaterialApp(
        theme: launcherTheme(style),
        home: Scaffold(
            body: SizedBox(
                width: 500,
                height: 420,
                child: BatteryCard(native: native78())))));
    // 主题是走 ThemeData 下发的，第一帧还拿的是上一套（换皮肤时尤其明显）。
    await t.pumpAndSettle();
    return t.widget<CardRing>(find.byType(CardRing));
  }

  testWidgets('三套皮肤：起弧端固定青，弧尖跟着主题配色', (t) async {
    const looks = [
      Appearance(mode: 'light', themeStyle: 'classic'),
      Appearance(mode: 'dark', themeStyle: 'classic'),
      Appearance(mode: 'dark', themeStyle: 'blueGlass'),
      Appearance(mode: 'dark', themeStyle: 'nocturne'),
      Appearance(mode: 'dark', themeStyle: 'nocturne', palette: 'rose'),
    ];
    for (final look in looks) {
      final tag = '${look.themeStyle}/${look.mode}/${look.palette}';
      final r = await ring(t, look);
      expect(r.fraction, closeTo(.78, .001), reason: tag);
      expect(r.color, CardTint.cyan, reason: tag);
      expect(r.colorEnd, SurfaceStyle.from(look, look.mode == 'dark').accent,
          reason: tag);
    }
    expect(t.takeException(), isNull);
  });

  testWidgets('换配色时弧尖颜色真的变了，固定那段不变', (t) async {
    final mint =
        await ring(t, const Appearance(mode: 'dark', themeStyle: 'nocturne'));
    final rose = await ring(
        t,
        const Appearance(
            mode: 'dark', themeStyle: 'nocturne', palette: 'rose'));
    expect(mint.colorEnd, isNot(rose.colorEnd));
    expect(mint.color, rose.color, reason: '固定那段不该变');
    // 经典皮肤换配色同样生效。
    final classic = await ring(t,
        const Appearance(mode: 'dark', themeStyle: 'classic', palette: 'rose'));
    expect(classic.colorEnd, isNot(mint.colorEnd));
  });
}
