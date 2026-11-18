import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uni_launcher/model/appearance.dart';

void main() {
  /// 自定义强调色必须按 HSL 算，不能往白/黑插值。
  ///
  /// 旧实现是 `Color.lerp(seed, white, .42)`：以正红 `#D42A2A` 为例，得到
  /// `#E68383`——明度被顶到 .71、HSV 彩度从 .80 掉到 .43，屏幕上是一块浅粉。
  /// 注意 HSL 的 saturation 在这里几乎不变（.67 → .66），所以判据是**明度**
  /// 与**彩度**，不是 HSL 饱和度。
  test('custom accent keeps the picked hue and lands on the design lightness',
      () {
    const a = Appearance(palette: 'custom', custom: '#D42A2A');
    final dark = HSLColor.fromColor(a.accent(true));
    expect(dark.hue, closeTo(0, 6), reason: '暗底强调色丢了色相');
    expect(dark.lightness, closeTo(.66, .02), reason: '暗底强调色没落在稿子的明度');
    expect(dark.saturation, greaterThan(.6));

    final light = HSLColor.fromColor(a.accent(false));
    expect(light.hue, closeTo(0, 6), reason: '浅底强调色丢了色相');
    expect(light.lightness, closeTo(.26, .02));
    expect(light.saturation, greaterThan(.6));

    // 旧做法的偏差是「太亮」：明度被推到 .71，整颗色发白。
    final oldStyle = Color.lerp(const Color(0xFFD42A2A), Colors.white, .42)!;
    expect(HSLColor.fromColor(oldStyle).lightness,
        greaterThan(dark.lightness + .03),
        reason: '这条用例的意义就是证明旧的 lerp 确实偏亮');
  });

  /// 色球是「三段同色相、明度递减」，不是两段插值。
  ///
  /// board 09 给了每颗球 top / mid / bottom 三个字面值（青屿
  /// `#6FF0D4 → #31B9A2 → #1F937D`），中间的 mid 正好就是 `seed`。
  /// 这里只钉「明度单调递减」——具体色值改设计稿时不该被测试拦住。
  test('every preset carries three board-09 dot stops', () {
    for (final p in accentPresets) {
      final top = HSLColor.fromColor(p.dotTop);
      final mid = HSLColor.fromColor(p.seed);
      final bottom = HSLColor.fromColor(p.dotBottom);
      expect(top.lightness, greaterThan(mid.lightness), reason: '${p.id} top');
      expect(mid.lightness, greaterThan(bottom.lightness),
          reason: '${p.id} mid');
      // 三段同色相：换色相就等于换了另一颗球，那是设计稿的问题。
      for (final other in [top, bottom]) {
        final delta = (other.hue - mid.hue).abs();
        expect(delta < 8 || delta > 352, isTrue,
            reason: '${p.id} 的三段色相不一致');
      }
    }
  });

  /// 「自定义」球的彩虹环第三段是当前强调色，换色必须跟着换。
  test('custom dot rainbow carries the live accent', () {
    const red = Appearance(palette: 'custom', custom: '#D42A2A');
    final colors = customDotColors(red.accent(true));
    expect(colors.length, 6);
    expect(colors.first, colors.last, reason: '首尾同色才是闭合的环');
    expect(colors[2], red.accent(true));
  });

  test('all five presets plus custom stay selectable', () {
    expect(accentPresets.map((p) => p.id).toList(),
        ['mint', 'blue', 'violet', 'amber', 'rose']);
    for (final id in ['mint', 'blue', 'violet', 'amber', 'rose', 'custom']) {
      final a = Appearance.fromJson({'palette': id});
      expect(a.palette, id, reason: '$id 读回来丢了');
    }
    // 不认识的色板名回落到默认，不能崩。
    expect(Appearance.fromJson({'palette': 'nope'}).palette, 'mint');
  });
}
