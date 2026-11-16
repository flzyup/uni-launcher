import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uni_launcher/theme/launcher_type.dart';

void main() {
  test('字号阶梯单调，且最小档在物理 12 px 以上', () {
    const ladder = [
      LauncherType.micro,
      LauncherType.caption,
      LauncherType.label,
      LauncherType.body,
      LauncherType.bodyLarge,
      LauncherType.title,
      LauncherType.titleLarge,
      LauncherType.heading,
      LauncherType.headline,
      LauncherType.display,
      LauncherType.numeral,
      LauncherType.hero,
      LauncherType.heroLarge,
    ];
    for (var i = 1; i < ladder.length; i++) {
      expect(ladder[i], greaterThan(ladder[i - 1]),
          reason: '第 $i 档 ${ladder[i]} 没有大于前一档 ${ladder[i - 1]}');
    }
    // 画布单位 × 1.2 = 1920 屏上的物理像素；低于 12 px 的中文在车机强光下会糊。
    expect(LauncherType.micro * 1.2, greaterThanOrEqualTo(12));
  });

  test('细字重收敛到系统字体真实存在的档位', () {
    // 系统 CJK 字体一般只有 Regular / Bold，请求 200~300 会落到 Regular；
    // harmonize 显式做这件事，免得预览（雅黑 Light）和车机（Regular）不一致。
    expect(LauncherType.harmonize(FontWeight.w100), LauncherType.regular);
    expect(LauncherType.harmonize(FontWeight.w200), LauncherType.regular);
    expect(LauncherType.harmonize(FontWeight.w300), LauncherType.regular);
    expect(LauncherType.harmonize(FontWeight.w400), LauncherType.regular);
    expect(LauncherType.harmonize(FontWeight.w500), LauncherType.medium);
    expect(LauncherType.harmonize(FontWeight.w600), FontWeight.w600);
    expect(LauncherType.harmonize(FontWeight.w700), LauncherType.strong);
  });

  test('读数样式带等宽数字与单行行高', () {
    final style = LauncherType.numeralStyle(LauncherType.numeral);
    expect(style.fontFeatures, isNotNull);
    expect(style.fontFeatures!.any((f) => f.feature == 'tnum'), isTrue);
    expect(style.height, LauncherType.lineTight);
    expect(style.fontSize, LauncherType.numeral);
    expect(style.fontWeight, LauncherType.medium);
  });

  test('字族留空，跟随车机系统字体', () {
    expect(LauncherType.family, isNull);
  });

  test('行高符合实测：单行 1.2 / 正文 1.32 / 说明 1.6', () {
    expect(LauncherType.lineTight, 1.2);
    expect(LauncherType.lineBody, 1.32);
    expect(LauncherType.lineLoose, 1.6);
    expect(LauncherType.lineTight, lessThan(LauncherType.lineBody));
    expect(LauncherType.lineBody, lessThan(LauncherType.lineLoose));
  });
}
