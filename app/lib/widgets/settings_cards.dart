import 'package:flutter/material.dart';

import '../theme/design_tokens.dart';
import '../theme/launcher_theme.dart';
import 'choice_button.dart';
import 'spectrum_painter.dart';

/// 设置页里「可视图卡」的公共骨架：sim `.fxcard` / `.spcard`。
///
/// 两张卡尺寸与描边一致（半径 16、内边距 15、选中描边 accent .85 + 5% 底），
/// 只有中间那块预览不同，所以合并成一个组件，避免两处各写一遍色值。
/// 颜色只取 [SurfaceStyle] 令牌，三皮肤通用：classic 浅色下描边走 edge、
/// 选中底走 accent 5%，不会出现「某皮肤某明暗态下卡片消失」。
class SettingsChoiceCard extends StatelessWidget {
  final String? title, detail;
  final Widget preview;
  final bool selected;
  final VoidCallback onTap;

  /// spcard 的预览区高 64、fxcard 的预览区高 78；文字只有一行时用 compact。
  final bool compact;
  const SettingsChoiceCard({
    super.key,
    this.title,
    this.detail,
    required this.preview,
    required this.selected,
    required this.onTap,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final s = SurfaceStyle.of(context);
    // 设计稿 `.fxcard` / `.spcard`：16 圆角、白 10% 描边、透明底；
    // 选中换成 accent 85% 描边 + accent 5% 底 + 一圈光，标题转 accent。
    return ChoiceButton(
        kind: ChoiceKind.tinted,
        selected: selected,
        onPressed: onTap,
        // 卡片由内容撑高（`.fxcard` / `.spcard` 没有固定高度）；
        // 不写 null 会落到 ChoiceButton 默认的 47，标题+预览会被压成 18。
        height: null,
        radius: 16,
        padding: EdgeInsets.fromLTRB(Design.dz(15), Design.dz(15),
            Design.dz(15), Design.dz(compact ? 13 : 14)),
        alignment: Alignment.topLeft,
        border: s.text.withValues(alpha: .1),
        selectedBorder: s.accent.withValues(alpha: .85),
        selectedFill: s.accent.withValues(alpha: .05),
        child: Stack(children: [
          Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (title != null)
                  Padding(
                      padding: EdgeInsets.only(right: Design.dz(22)),
                      child: Text(title!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: Design.dz(compact ? 15 : 19),
                              color: selected
                                  ? s.accent
                                  : s.text.withValues(alpha: compact ? .7 : .82)))),
                if (detail != null) ...[
                  SizedBox(height: Design.dz(3)),
                  Text(detail!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: Design.dz(13.5),
                          color: s.text.withValues(alpha: .38)))
                ],
                SizedBox(height: Design.dz(compact ? 9 : 10)),
                preview
              ]),
          if (selected)
            Positioned(
                top: 0,
                right: 0,
                child:
                    Icon(Icons.check_circle, size: Design.dz(20), color: s.accent))
        ]));
  }
}

/// 桌面翻屏效果的小样：sim `.fxv` 里那几张纸片的静态示意。
/// 五种效果各画各的，不跑动画——设置页里一次只挂 5 张，动画收益为零，
/// 但 820A 上每帧重绘的代价是实打实的。
class PageEffectPreview extends StatelessWidget {
  final String effect;
  const PageEffectPreview({super.key, required this.effect});
  @override
  Widget build(BuildContext context) {
    final s = SurfaceStyle.of(context);
    final lit = BoxDecoration(
        borderRadius: BorderRadius.circular(Design.dz(7)),
        gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              s.accent,
              Color.alphaBlend(Colors.black.withValues(alpha: .38), s.accent)
            ]));
    final dim = BoxDecoration(
        borderRadius: BorderRadius.circular(Design.dz(7)),
        color: s.text.withValues(alpha: .055),
        border: Border.all(
            color: selectedBorder(s), width: Design.dz(1)));
    Widget page(BoxDecoration decoration,
            {double width = 46, double height = 34, Widget? child}) =>
        Container(
            width: Design.dz(width),
            height: Design.dz(height),
            decoration: decoration,
            child: child);
    Widget pages(List<Widget> children) => Container(
        height: Design.dz(78),
        margin: EdgeInsets.only(top: Design.dz(2)),
        clipBehavior: Clip.hardEdge,
        decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(Design.dz(11)),
            color: Colors.black.withValues(alpha: .32)),
        child: Center(
            child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: children)));
    Widget arrow() => Padding(
        padding: EdgeInsets.symmetric(horizontal: Design.dz(4)),
        child: Icon(Icons.arrow_forward,
            size: Design.dz(16), color: s.accent.withValues(alpha: .8)));

    switch (effect) {
      case 'fade':
        return pages([
          SizedBox(
              width: Design.dz(66),
              height: Design.dz(34),
              child: Stack(children: [
                Positioned(left: 0, child: page(dim)),
                Positioned(
                    right: 0,
                    child: page(BoxDecoration(
                        borderRadius: BorderRadius.circular(Design.dz(7)),
                        gradient: LinearGradient(
                            begin: Alignment.centerLeft,
                            end: Alignment.centerRight,
                            colors: [
                              s.accent.withValues(alpha: .85),
                              s.accent.withValues(alpha: .25)
                            ]))))
              ]))
        ]);
      case 'zoom':
        return pages([
          SizedBox(
              width: Design.dz(46),
              height: Design.dz(34),
              child: Stack(alignment: Alignment.center, children: [
                Positioned.fill(
                    child: DecoratedBox(
                        decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(Design.dz(8)),
                            border: Border.all(
                                color: s.accent.withValues(alpha: .45),
                                width: Design.dz(1.4))))),
                Transform.scale(scale: .72, child: page(lit))
              ]))
        ]);
      case 'depth':
        return pages([
          Transform.translate(
              offset: Offset(Design.dz(14), 0),
              child: Transform.scale(scale: .92, child: page(dim))),
          Transform.translate(
              offset: Offset(Design.dz(7), 0),
              child: Transform.scale(
                  scale: .96,
                  child: page(dim.copyWith(
                      color: s.text.withValues(alpha: .08))))),
          page(lit)
        ]);
      case 'none':
        return pages([
          page(lit),
          Container(
              width: Design.dz(1.4),
              height: Design.dz(40),
              margin: EdgeInsets.symmetric(horizontal: Design.dz(8)),
              color: s.text.withValues(alpha: .18)),
          page(dim)
        ]);
      default: // slide
        return pages([page(lit), arrow(), page(dim)]);
    }
  }

  static Color selectedBorder(SurfaceStyle s) =>
      s.text.withValues(alpha: .08);
}

/// 频谱样式卡：复用真实画笔（[SpectrumStylePreview]），不另画一套示意图，
/// 否则设置页里的样子和底栏实际渲染会漂移。
class SpectrumChoiceCard extends StatelessWidget {
  final String style, label;
  final bool selected;
  final VoidCallback onTap;
  const SpectrumChoiceCard(
      {super.key,
      required this.style,
      required this.label,
      required this.selected,
      required this.onTap});
  @override
  Widget build(BuildContext context) {
    final s = SurfaceStyle.of(context);
    return SettingsChoiceCard(
        key: ValueKey('spectrum-style-$style'),
        title: label,
        selected: selected,
        onTap: onTap,
        compact: true,
        preview: SizedBox(
            height: Design.dz(64),
            child: SpectrumStylePreview(
                style: style, accent: s.accent, edge: s.edge)));
  }
}

/// Wrap 里按设计稿「flex:1 + min-width」的行为算列数：能塞几列塞几列，
/// 塞不下就掉行，不做等分压缩（压缩会让小样糊成一团）。
int fitColumns(double width, double gap, double minWidth, int maxColumns) {
  for (var n = maxColumns; n > 1; n--) {
    if ((width - gap * (n - 1)) / n >= minWidth) return n;
  }
  return 1;
}
