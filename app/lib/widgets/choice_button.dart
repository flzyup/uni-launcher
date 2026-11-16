import 'package:flutter/material.dart';

import '../theme/design_tokens.dart';
import '../theme/launcher_theme.dart';

/// 设计稿里设置页的四种「可选控件」形态。选中态是四套不同的画法，不是
/// 同一个样式换透明度——之前把这些混成一套，所以每页的选中态都跟稿子对不上。
///
/// | 形态 | 设计稿 | 未选中 | 选中 |
/// |---|---|---|---|
/// | [filled] | `.opt` `.chip` `.seg` | 白 6% 底 + 白 17% 描边 | **渐变实心**（acc-hi→acc-lo）+ 深色字 + 600 |
/// | [tinted] | `.tcar` `.pcol` `.fxcard` `.spcard` | 透明或白 5% 底 + 白 10~16% 描边 | accent 5% 底 + accent 85% 描边 + 一圈光 |
/// | [nav] | `.ss-nav .tb` | 透明 | accent 12% 底、无描边、accent 字 |
/// | [tile] | `.tile` `.cl-row` | 白 2% 底、无描边 | 同未选中（由内容自己表达选中） |
enum ChoiceKind { filled, tinted, nav, tile }

/// 设置页唯一的选择控件。三皮肤共用一套尺寸，配色按皮肤分派：
/// blueGlass 的选中态是四角短弧（[SurfaceStyle.selectionStyle]），
/// 走 OutlinedButton；暗夜是渐变实心/描边淡底，自绘 Container 才画得出来。
class ChoiceButton extends StatelessWidget {
  final bool selected;
  final VoidCallback? onPressed;
  final Widget child;
  final ChoiceKind kind;

  /// 高度 / 圆角 / 内边距都是设计稿画布单位（1600 宽），直接写 [Design.dz]。
  /// 传 null 表示由内容撑高（`.fxcard` / `.spcard` 这类卡片用）。
  final double? height;
  final double? radius;
  final EdgeInsetsGeometry? padding;
  final Alignment alignment;

  /// true = 按内容宽（`.chip` / `.opt` 这类塞进 Wrap 的小控件），
  /// false = 撑满给到的宽度（导航项、等分卡片）。
  final bool shrink;

  /// 未选中态覆盖：个别控件（`.pcol` 无底、`.tcar` 5% 底）不合默认值。
  final Color? fill;
  final Color? border;

  /// 选中态覆盖：`.pcol.on` 要 90% 描边，`.tcar.on` 只要 70%。
  final Color? selectedBorder;
  final Color? selectedFill;

  const ChoiceButton({
    super.key,
    required this.selected,
    required this.onPressed,
    required this.child,
    this.kind = ChoiceKind.filled,
    this.height = 47,
    this.radius,
    this.padding,
    this.alignment = Alignment.center,
    this.shrink = false,
    this.fill,
    this.border,
    this.selectedBorder,
    this.selectedFill,
  });

  /// 选中/未选中的文字色：实心渐变必须压深色（`.opt.on` 用的是 `--acc-d`），
  /// 描边淡底保持正文色，导航项用 accent。
  ///
  /// 静态是为了让调用方在自建子组件（导航项的图标 + 文字、卡片的标题行）时
  /// 取到**完全同一套**颜色，而不是各写一份 if。
  static Color foregroundOf(SurfaceStyle s, ChoiceKind kind, bool selected) {
    if (s.nocturne) {
      return switch (kind) {
        ChoiceKind.filled =>
          selected ? s.accentText : s.text.withValues(alpha: .86),
        ChoiceKind.tinted => selected ? s.text : s.text.withValues(alpha: .82),
        ChoiceKind.nav => selected ? s.accent : s.text.withValues(alpha: .58),
        ChoiceKind.tile => s.text.withValues(alpha: .82),
      };
    }
    // 经典 / 蓝玻璃走 OutlinedButton 的 selectionStyle：底色与字色成对算好，
    // 这里只解出前景色，避免出现「实心底 + 同色字」。
    return s
            .selectionStyle(selected)
            .foregroundColor
            ?.resolve(const <WidgetState>{}) ??
        s.text;
  }

  Color foreground(SurfaceStyle s) => foregroundOf(s, kind, selected);

  FontWeight get weight =>
      selected && (kind == ChoiceKind.filled || kind == ChoiceKind.nav)
          ? FontWeight.w600
          : FontWeight.w400;

  @override
  Widget build(BuildContext context) {
    final s = SurfaceStyle.of(context);
    final r = radius ?? 14.0;
    final pad = padding ??
        EdgeInsets.symmetric(horizontal: Design.dz(14));
    if (!s.nocturne) return _classic(s, r, pad);
    final fg = foreground(s);
    final isFilled = kind == ChoiceKind.filled;
    final bg = selected
        ? (selectedFill ??
            switch (kind) {
              ChoiceKind.filled => null,
              ChoiceKind.tinted => s.accent.withValues(alpha: .05),
              ChoiceKind.nav => s.accent.withValues(alpha: .12),
              ChoiceKind.tile => s.text.withValues(alpha: .02),
            })
        : (fill ??
            switch (kind) {
              ChoiceKind.filled => s.text.withValues(alpha: .06),
              ChoiceKind.tinted => null,
              ChoiceKind.nav => null,
              ChoiceKind.tile => s.text.withValues(alpha: .02),
            });
    final side = selected
        ? switch (kind) {
            ChoiceKind.filled => BorderSide.none,
            ChoiceKind.tinted => BorderSide(
                color: selectedBorder ?? s.accent.withValues(alpha: .85)),
            _ => BorderSide.none,
          }
        : BorderSide(
            color: border ??
                s.text.withValues(
                    alpha: kind == ChoiceKind.filled ? .17 : .10));
    final shadows = !selected
        ? null
        : switch (kind) {
            // 实心选中态只留一层「隐隐的光」：贴下缘一点微光。
            //
            // 原来是 alpha .45 / blur 22 / offset 8——那已经是一块明显的光斑，
            // 摆在设置页里像按钮自己发光；而且 BoxShadow 的模糊是 raster 里的
            // 高斯，每重绘一次算一次。收到 .26 / 12 / 4 一半以下的面积，
            // 观感只剩贴着下缘的一层薄光，性能也顺带省了。
            ChoiceKind.filled => [
                BoxShadow(
                    color: s.accent.withValues(alpha: .26),
                    offset: Offset(0, Design.dz(4)),
                    blurRadius: Design.dz(12),
                    spreadRadius: -Design.dz(6)),
              ],
            ChoiceKind.tinted => [
                BoxShadow(
                    color: s.accent.withValues(alpha: .30),
                    blurRadius: 0,
                    spreadRadius: Design.dz(1)),
                BoxShadow(
                    color: s.accent.withValues(alpha: .40),
                    offset: Offset(0, Design.dz(14)),
                    blurRadius: Design.dz(34),
                    spreadRadius: -Design.dz(14)),
              ],
            _ => null,
          };
    final radiusValue = BorderRadius.circular(Design.dz(r));
    return SizedBox(
        height: height == null ? null : Design.dz(height!),
        child: DecoratedBox(
            decoration: BoxDecoration(
                borderRadius: radiusValue,
                color: bg,
                gradient: selected && isFilled ? s.accentFill : null,
                border:
                    side == BorderSide.none ? null : Border.fromBorderSide(side),
                boxShadow: shadows),
            child: Material(
                type: MaterialType.transparency,
                child: InkWell(
                    borderRadius: radiusValue,
                    onTap: onPressed,
                    child: Padding(
                        padding: pad,
                        child: Align(
                            alignment: alignment,
                            widthFactor: shrink ? 1 : null,
                            heightFactor: shrink ? 1 : null,
                            child: DefaultTextStyle.merge(
                                style: TextStyle(
                                    color: fg, fontWeight: weight),
                                child: IconTheme.merge(
                                    data: IconThemeData(color: fg),
                                    child: child))))))));
  }

  /// 经典与玻璃皮肤走原来的按钮：蓝玻璃的选中态是 `TechnicalFrameBorder`
  /// 的四角短弧，自绘会把那层框抹掉。
  Widget _classic(SurfaceStyle s, double r, EdgeInsetsGeometry pad) {
    // 字色显式写进 DefaultTextStyle：OutlinedButton 只把前景色算在
    // ButtonStyle 里，`Text.style.color` 拿到的是 null，选中/未选中在
    // 组件树上看不出来（截图能对、契约测试对不上，改动一次就没人敢动了）。
    final fg = foregroundOf(s, kind, selected);
    return SizedBox(
        height: height == null ? null : Design.dz(height!),
        child: OutlinedButton(
            onPressed: onPressed,
            style: s.selectionStyle(selected).copyWith(
                padding: WidgetStatePropertyAll(pad),
                minimumSize: const WidgetStatePropertyAll(Size.zero),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                alignment: alignment),
            child: DefaultTextStyle.merge(
                style: TextStyle(color: fg, fontWeight: weight),
                child: IconTheme.merge(
                    data: IconThemeData(color: fg), child: child))));
  }
}

/// `.tbtn`：行尾的主题色文字动作（「时间轴 ›」「接管明细 ›」「查看全部 24 ›」）。
class DesignTextAction extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool chevron;
  const DesignTextAction(this.label,
      {super.key, this.onPressed, this.chevron = true});
  @override
  Widget build(BuildContext context) {
    final s = SurfaceStyle.of(context);
    final color = onPressed == null ? s.disabled : s.accent;
    return InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(Design.dz(8)),
        child: Padding(
            padding: EdgeInsets.symmetric(
                horizontal: Design.dz(4), vertical: Design.dz(4)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Text(label,
                  style: TextStyle(
                      fontSize: Design.dz(15), color: color)),
              if (chevron) ...[
                SizedBox(width: Design.dz(4)),
                Icon(Icons.chevron_right,
                    size: Design.dz(16), color: color)
              ]
            ])));
  }
}

/// `.lbtn`：30 高的小胶囊按钮（「刷新连接」「授权媒体访问」「检查更新」）。
class DesignSmallAction extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  const DesignSmallAction(this.label,
      {super.key, this.icon, this.onPressed});
  @override
  Widget build(BuildContext context) {
    final s = SurfaceStyle.of(context);
    final enabled = onPressed != null;
    final color = enabled ? s.accent : s.disabled;
    return InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(Design.dz(9)),
        child: Container(
            height: Design.dz(30),
            padding: EdgeInsets.symmetric(horizontal: Design.dz(11.67)),
            decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(Design.dz(9)),
                color: s.accent.withValues(alpha: enabled ? .07 : .03),
                border: Border.all(
                    color: s.accent.withValues(alpha: enabled ? .26 : .12))),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              if (icon != null) ...[
                Icon(icon, size: Design.dz(14), color: color),
                SizedBox(width: Design.dz(5))
              ],
              Text(label, style: TextStyle(fontSize: Design.dz(12.5), color: color))
            ])));
  }
}

/// `.blk .lb` / 表单行左标签：15 号、白 40%。
class DesignFieldLabel extends StatelessWidget {
  final String text;
  const DesignFieldLabel(this.text, {super.key});
  @override
  Widget build(BuildContext context) {
    final s = SurfaceStyle.of(context);
    return Text(text,
        style: TextStyle(
            fontSize: Design.dz(15), color: s.text.withValues(alpha: .4)));
  }
}

/// 设计稿的开关：`.sw` 46×26 胶囊 + 20 的圆滑块。Flutter 自带的 Switch
/// 是 52×32、滑块带描边，摆进 58 高的行里会整体偏大偏重，所以自绘。
class DesignSwitch extends StatelessWidget {
  final bool value;
  final ValueChanged<bool>? onChanged;
  final String? semanticLabel;
  const DesignSwitch(
      {super.key, required this.value, this.onChanged, this.semanticLabel});
  @override
  Widget build(BuildContext context) {
    final s = SurfaceStyle.of(context);
    final enabled = onChanged != null;
    final track = value
        ? s.accentFill
        : LinearGradient(colors: [
            s.text.withValues(alpha: .12),
            s.text.withValues(alpha: .12)
          ]);
    // 圆点是「白色部件」，不能拿 s.text 当颜色：暗色皮肤下 s.text 恰好是白，
    // 所以一直看不出问题；浅色下 s.text 是深墨色，圆点就成了深蓝块。浅色改用
    // 固定白 + 一圈轻投影，否则白点压在同为浅灰的轨道上边界全糊。
    final knob = s.dark
        ? (value ? s.text : s.text.withValues(alpha: .75))
        : Colors.white;
    return Semantics(
        label: semanticLabel,
        toggled: value,
        child: Opacity(
            opacity: enabled ? 1 : .45,
            child: GestureDetector(
                onTap: enabled ? () => onChanged!(!value) : null,
                child: AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    width: Design.dz(46),
                    height: Design.dz(26),
                    decoration: BoxDecoration(
                        gradient: track,
                        borderRadius: BorderRadius.circular(Design.dz(13))),
                    child: AnimatedAlign(
                        duration: const Duration(milliseconds: 160),
                        curve: Curves.easeOut,
                        alignment:
                            value ? Alignment.centerRight : Alignment.centerLeft,
                        child: Padding(
                            padding: EdgeInsets.all(Design.dz(3)),
                            child: Container(
                                width: Design.dz(20),
                                height: Design.dz(20),
                                decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: knob,
                                    boxShadow: s.dark
                                        ? null
                                        : [
                                            BoxShadow(
                                                color: Colors.black
                                                    .withValues(alpha: .18),
                                                blurRadius: Design.dz(3),
                                                offset: Offset(0, Design.dz(1)))
                                          ]))))))));
  }
}

/// 设计稿的行：`.set-row`（58 高、底部 5.5% 白细线）与 `.tile`（52 高卡片行）。
class SettingRow extends StatelessWidget {
  final String label;
  final String? note;
  final Widget? trailing;
  final Widget? leading;
  final VoidCallback? onTap;
  final bool tile;
  final double height;
  final bool divider;
  final int noteLines;

  /// 纵向内边距为零，行高由 [height] 控制；说明在标签下面 3。
  const SettingRow(
      {super.key,
      required this.label,
      this.note,
      this.trailing,
      this.leading,
      this.onTap,
      this.tile = false,
      this.height = 58,
      this.divider = true,
      this.noteLines = 2});

  @override
  Widget build(BuildContext context) {
    final s = SurfaceStyle.of(context);
    final content = Row(children: [
      if (leading != null) ...[
        SizedBox(width: Design.dz(tile ? 20 : 26), child: leading),
        SizedBox(width: Design.dz(tile ? 12 : 12))
      ],
      Expanded(
          child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
            Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: Design.dz(tile ? 16 : 15),
                    color: s.text.withValues(alpha: tile ? .78 : .82))),
            if (note != null)
              Padding(
                  padding: EdgeInsets.only(top: Design.dz(3)),
                  child: Text(note!,
                      maxLines: noteLines,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: Design.dz(tile ? 12.5 : 12),
                          color: s.text.withValues(alpha: .42))))
          ])),
      if (trailing != null) ...[
        SizedBox(width: Design.dz(12)),
        trailing!
      ]
    ]);
    final row = SizedBox(height: Design.dz(height), child: content);
    if (tile) {
      // `.tile`：52 高小卡片。这里必须把 onTap 接上——之前直接 return
      // Container，系统设置列表整列点了没反应。
      final box = Container(
          height: Design.dz(height),
          padding: EdgeInsets.symmetric(horizontal: Design.dz(15)),
          decoration: BoxDecoration(
              color: s.text.withValues(alpha: .02),
              borderRadius: BorderRadius.circular(Design.dz(14)),
              border: Border.all(color: s.text.withValues(alpha: .07))),
          child: content);
      return Padding(
          padding: EdgeInsets.only(bottom: Design.dz(6)),
          child: onTap == null
              ? box
              : Material(
                  color: Colors.transparent,
                  child: InkWell(
                      onTap: onTap,
                      borderRadius: BorderRadius.circular(Design.dz(14)),
                      child: box)));
    }
    final withLine = divider
        ? DecoratedBox(
            decoration: BoxDecoration(
                border: Border(
                    bottom: BorderSide(
                        color: s.text.withValues(alpha: .055)))),
            child: row)
        : row;
    if (onTap == null) return withLine;
    return InkWell(onTap: onTap, child: withLine);
  }
}
