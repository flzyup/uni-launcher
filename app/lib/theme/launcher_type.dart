import 'package:flutter/painting.dart';

/// 字号与行高标定：**不内置字体，跟随车机系统字体**。
///
/// 设计稿（`theme-styles/eclipse/simulator.html`）的字体栈是
/// `HarmonyOS Sans SC → MiSans → PingFang SC → Microsoft YaHei UI`，
/// 我们没有嵌入任何字体，实际渲染的是车机系统字体。手册里常说的
/// 「换字体要重标字号」在这套系统里只对了一半，实测数据说明了原因。
///
/// 本机实测（字宽按 em 归一，直接读 TTF / TTC 的 head + hhea + hmtx + cmap）：
///
/// | 字体 | 默认行高 | 汉字「中」 | 数字「0」 |
/// |---|---|---|---|
/// | 雅黑 Regular | 1.320 | 1.000 em | 0.586 em |
/// | 雅黑 Bold | 1.320 | 1.000 em | 0.617 em |
/// | 雅黑 Light | 1.330 | 1.000 em | 0.556 em |
/// | 等线 DengXian | 1.042 | 1.000 em | 0.527 em |
/// | Segoe UI | 1.330 | — | 0.539 em |
/// | Noto Sans CJK（车机常见） | ≈1.448 | 1.000 em | 0.500 em |
/// | Roboto（Android 拉丁默认） | ≈1.171 | — | 0.556 em |
///
/// 三条结论决定了下面这套取值：
///
/// 1. **汉字的 advance 恒为 1.000 em**（所有中文字体都一样），所以换字体
///    *不会*改变汉字宽度，字号本身不需要做等比缩放。需要重标的是行高、
///    字重和数字宽度，不是字号。
/// 2. **默认行高在字体之间差 30%**（Roboto 1.17 → Noto CJK 1.45）。不显式钉死
///    [lineBody]，同一份代码在不同车机上中文行距会明显不一样。这是「用系统字体」
///    最需要补的一课。
/// 3. **数字宽度随字重变**（雅黑 400 → 700 差 5.3%，且不同字体 0.50~0.62 em）。
///    时间、温度、车速这类数字为主的组件必须显式用 [tabular]，否则读数会跳。
abstract final class LauncherType {
  /// 显式声明「不指定字族」，跟随平台默认。
  ///
  /// 留成常量是为了让后来的人一眼看到这是有意为之，而不是漏配：
  /// 嵌入 HarmonyOS Sans / MiSans 需要商用授权，且两家协议都禁止修改字体
  /// （等于禁止子集化裁剪），完整简中一个字重就是 10 MB 量级，暂不采用。
  static const String? family = null;

  // ── 字号阶梯 ────────────────────────────────────────────────────────────
  //
  // 单位与 [Design.dz] 一致（1600 画布单位）；1920 屏上乘 1.2 就是物理像素。
  // 设计稿实际用了 26 个零散字号（9.5 / 10 / 10.5 / 11 / 11.5 / 12 / 12.5 / 13 /
  // 13.5 / 14 / 14.5 / 15 / 15.5 / 16 / 19 / 20 / 21 / 21.67 / 22 / 23 / 24 /
  // 26 / 30 / 44 / 88 …），这里归并成 13 档，覆盖设计稿的 0.5 步长网格。
  //
  // 存量页面**照设计稿原值写**（像素对齐优先，所以还能在代码里看到 14、15.5
  // 这类零散值）；新写组件从这个阶梯里挑，不要再造第 14 档。

  /// 最小可读：设计稿的 9.5 / 10 归到这里。物理 12.6 px，是车机强光下
  /// 中文仍能分辨笔画的底线，不再往下走。
  static const double micro = 10.5;

  /// 次要说明、单位、角标（设计稿 11 / 11.5）。
  static const double caption = 11.5;

  /// 常规标签、表格单元（设计稿 12 / 12.5 / 13）。
  static const double label = 12.5;

  /// 正文（设计稿 13 / 13.5）。
  static const double body = 13.5;

  /// 稍大的正文、列表主行（设计稿 14 / 14.5）。
  static const double bodyLarge = 14.5;

  /// 小标题（设计稿 15 / 15.5）。
  static const double title = 15.5;

  /// 区块内的强调行（设计稿 16，出现 12 次）。
  static const double titleLarge = 16;

  /// 区块标题（设计稿 19，出现 16 次）。
  static const double heading = 19;

  /// 页面级小标题（设计稿 20 / 21 / 22 归到这里）。
  static const double headline = 22;

  /// 大标题（设计稿 23 / 24 / 26）。
  static const double display = 26;

  /// 数字展示（车速、倒计时一类）。
  static const double numeral = 30;

  /// 超大读数（时钟、主视觉数字）。
  static const double hero = 44;

  /// 主视觉巨型数字。
  static const double heroLarge = 88;

  // ── 行高 ────────────────────────────────────────────────────────────────

  /// 单行标签 / 按钮：1.2 是雅黑 ascent 1.058 之上留 0.14 em 的余量，
  /// 既不会裁到汉字上伸部，也不会把一行的行盒撑得太高。
  static const double lineTight = 1.2;

  /// 中文正文：等于雅黑实测行高 1.320。显式写死是为了在 Noto CJK（1.448）
  /// 和等线（1.042）上得到同样的行距，不随车机字体漂移。
  static const double lineBody = 1.32;

  /// 说明段落（设计稿里的 1.6 / 1.66）。
  static const double lineLoose = 1.6;

  // ── 字重 ────────────────────────────────────────────────────────────────
  //
  // 设计稿用了大量 200 / 250 / 300。系统 CJK 字体通常只有 Regular 与 Bold
  // （雅黑另有 Light，但车机未必带），Flutter 遇到缺失字重会做合成加粗/减细：
  // 笔画发虚、横向宽度还会变（雅黑 400→700 数字宽 +5.3%），所以这里只保留
  // 三档真实存在的字重，层级靠字号与颜色做。

  static const FontWeight regular = FontWeight.w400;
  static const FontWeight medium = FontWeight.w500;
  static const FontWeight strong = FontWeight.w700;

  /// 把设计稿里的细字重收进系统字体真实存在的档位。
  ///
  /// 200 / 250 / 300 一律落到 Regular：宁可少一点「精致」，也不要合成出来的
  /// 毛边笔画——那在车机屏上会被放大成「糊」。
  static FontWeight harmonize(FontWeight weight) =>
      weight.value < regular.value ? regular : weight;

  // ── 数字 ────────────────────────────────────────────────────────────────

  /// 等宽数字。数字为主的读数必须带上，否则数值变化时整串会左右抖。
  static const List<FontFeature> tabular = [FontFeature.tabularFigures()];

  /// 读数样式：等宽数字 + 单行行高。
  static TextStyle numeralStyle(
    double size, {
    Color? color,
    FontWeight weight = medium,
    double height = lineTight,
  }) =>
      TextStyle(
        fontSize: size,
        fontWeight: harmonize(weight),
        fontFeatures: tabular,
        height: height,
        color: color,
      );
}
