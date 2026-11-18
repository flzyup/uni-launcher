import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uni_launcher/model/appearance.dart';
import 'package:uni_launcher/model/card_layout.dart';
import 'package:uni_launcher/theme/launcher_theme.dart';
import 'package:uni_launcher/widgets/clock_weather_card.dart';
import 'package:uni_launcher/widgets/weather_icon.dart';

/// 2026-11-13 实车反馈：右下天气块被放大到卡高 1/3 后「太大了」，要退回放大前
/// 的一档。这条用例把「图标相对卡高」钉在一个窄区间里，再放大就会红。
void main() {
  const native = {
    'weather': {
      'available': true,
      'condition': '多云',
      'temperature': 24,
      'city': '杭州',
      'night': false,
    }
  };

  testWidgets('右下天气图标是原尺寸档，不再占卡高三分之一', (t) async {
    const card = LauncherCard('clock', 'clockWeather', '时间', 0, 0, 4, 4, 0);
    await t.pumpWidget(MaterialApp(
        theme: launcherTheme(SurfaceStyle.from(const Appearance(), true)),
        home: Scaffold(
            body: Center(
                child: SizedBox(
                    width: 600,
                    height: 420,
                    child: ClockWeatherCard(
                        card: card, native: native, editing: false))))));
    await t.pump();
    final icon = t.widget<WeatherIcon>(find.byType(WeatherIcon));
    // 放大那版是「卡高 1/3 × 1.02」≈ 0.34×卡高；原尺寸档在 0.12~0.16 之间
    // （卡高 420、上下各留 26 的内边距）。
    expect(icon.size, lessThan(420 * .2));
    expect(icon.size, greaterThan(420 * .1));
    // 温度与描述仍在这一块里。
    expect(find.text('24°'), findsOneWidget);
    expect(find.text('多云'), findsOneWidget);
    expect(t.takeException(), isNull);
  });
}
