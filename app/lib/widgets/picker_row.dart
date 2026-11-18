import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../theme/design_tokens.dart';
import '../theme/launcher_theme.dart';
import 'uni_icon.dart';

/// 选择器弹层（导航 / 音乐）里的一行。
///
/// 数值全部直取 `theme-styles/eclipse/simulator.html` 的 `.dlg-row` /
/// `.pick-ic` / `.pick-tag` / `.dlg-row.go` / `.pick-foot`：稿子画布就是
/// 1600×900，和 [Design.dz] 的 1:1 口径同一个坐标系，所以这里是原值，
/// 不乘 1920 稿的 5/6。
class PickerRow extends StatelessWidget {
  final Widget leading;
  final String name;
  final String? detail;

  /// 右侧角标（稿子的「使用中」）。null 就不显示。
  final String? tag;
  final bool selected;
  final VoidCallback onTap;

  const PickerRow({
    super.key,
    required this.leading,
    required this.name,
    this.detail,
    this.tag,
    this.selected = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final s = SurfaceStyle.of(context);
    final ink = s.text;
    return Semantics(
        button: true,
        selected: selected,
        label: name,
        child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onTap,
            child: Container(
                height: Design.dz(64),
                padding: EdgeInsets.symmetric(horizontal: Design.dz(16)),
                decoration: BoxDecoration(
                    color: selected
                        ? ink.withValues(alpha: .055)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(Design.dz(16))),
                child: Row(children: [
                  leading,
                  SizedBox(width: Design.dz(16)),
                  Expanded(
                      child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                        Text(name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: Design.dz(16),
                                color: ink.withValues(alpha: .88))),
                        if (detail != null)
                          Padding(
                              padding: EdgeInsets.only(top: Design.dz(3)),
                              child: Text(detail!,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                      fontSize: Design.dz(12), color: s.muted)))
                      ])),
                  if (tag != null) PickerTag(tag!)
                ]))));
  }
}

/// 稿子的 `.pick-tag`：accent 系的细边框小角标。
class PickerTag extends StatelessWidget {
  final String text;
  const PickerTag(this.text, {super.key});
  @override
  Widget build(BuildContext context) {
    final accent = SurfaceStyle.of(context).accent;
    return Container(
        padding: EdgeInsets.symmetric(
            horizontal: Design.dz(9), vertical: Design.dz(4)),
        decoration: BoxDecoration(
            color: accent.withValues(alpha: .10),
            border: Border.all(color: accent.withValues(alpha: .26)),
            borderRadius: BorderRadius.circular(Design.dz(7))),
        child: Text(text,
            style: TextStyle(
                fontSize: Design.dz(10.5),
                letterSpacing: Design.dz(10.5) * .10,
                color: accent.withValues(alpha: .92))));
  }
}

/// 稿子的 `.pick-ic`：42×42 / 圆角 12 / 品牌色底 + 160° 明暗渐变 +
/// 左上角径向高光 + 外投影。装了应用就贴真实图标，没有才画这块色板。
class PickerIcon extends StatelessWidget {
  final Uint8List? bytes;

  /// `assets/icons` 下的品牌矢量名（不含扩展名），稿子四家地图的原图。
  /// null 时退回 [fallback] 的项目线条图标。
  final String? svg;
  final IconData fallback;
  final Color? brand;
  const PickerIcon(
      {super.key, this.bytes, this.svg, required this.fallback, this.brand});

  /// 一块纯色圆角底 + 白图标。
  ///
  /// 稿子的 `.pick-ic` 还叠了一层 160° 渐变、一道径向高光和一圈同色外投影，
  /// 但那是单张弹层的展示稿；这里一屏要画十几行，每行挂三层额外的绘制不划算，
  /// 42px 见方上也根本分辨不出来。只留底色，视觉结论一样。
  @override
  Widget build(BuildContext context) {
    final base = brand ?? SurfaceStyle.of(context).accent;
    final size = Design.dz(42);
    final radius = BorderRadius.circular(Design.dz(12));
    final glyph = svg != null
        ? SvgPicture.asset('assets/icons/$svg.svg',
            width: Design.dz(23),
            height: Design.dz(23),
            colorFilter:
                const ColorFilter.mode(Colors.white, BlendMode.srcIn),
            excludeFromSemantics: true)
        : DesignIcon(fallback, size: Design.dz(23), color: Colors.white);
    final tile = Container(
        width: size,
        height: size,
        decoration: BoxDecoration(color: base, borderRadius: radius),
        child: Center(child: glyph));
    final data = bytes;
    if (data == null) return tile;
    // 装了应用就贴真实图标，盖住色板。
    return ClipRRect(
        borderRadius: radius,
        child: SizedBox(
            width: size,
            height: size,
            child: Image.memory(data,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => tile)));
  }
}

/// 稿子的 `.dlg-row.go`：「其他已安装应用」。
class PickerGoRow extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const PickerGoRow(
      {super.key, required this.label, required this.onTap});
  @override
  Widget build(BuildContext context) {
    final s = SurfaceStyle.of(context);
    final ink = s.text;
    return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
            height: Design.dz(56),
            margin: EdgeInsets.only(top: Design.dz(14)),
            padding: EdgeInsets.only(
                top: Design.dz(14),
                left: Design.dz(16),
                right: Design.dz(16)),
            decoration: BoxDecoration(
                border: Border(
                    top: BorderSide(color: ink.withValues(alpha: .07)))),
            child: Row(children: [
              Expanded(
                  child: Text(label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: Design.dz(16),
                          color: ink.withValues(alpha: .60)))),
              Icon(Icons.chevron_right,
                  size: Design.dz(18), color: ink.withValues(alpha: .50))
            ])));
  }
}

/// 稿子的 `.pick-foot`：弹层底部的说明小字。
class PickerFoot extends StatelessWidget {
  final String text;
  const PickerFoot(this.text, {super.key});
  @override
  Widget build(BuildContext context) {
    final ink = SurfaceStyle.of(context).text;
    return Container(
        margin: EdgeInsets.only(top: Design.dz(12)),
        padding: EdgeInsets.only(top: Design.dz(12)),
        decoration: BoxDecoration(
            border: Border(
                top: BorderSide(color: ink.withValues(alpha: .06)))),
        child: Text(text,
            style: TextStyle(
                fontSize: Design.dz(11.5),
                height: 1.6,
                letterSpacing: Design.dz(11.5) * .02,
                color: ink.withValues(alpha: .30))));
  }
}

/// 列表为空时的占位，用稿子副标题那档字色。
class PickerEmpty extends StatelessWidget {
  final String text;
  const PickerEmpty(this.text, {super.key});
  @override
  Widget build(BuildContext context) => Padding(
      padding: EdgeInsets.symmetric(
          horizontal: Design.dz(16), vertical: Design.dz(18)),
      child: Text(text,
          style: TextStyle(
              fontSize: Design.dz(12),
              color: SurfaceStyle.of(context).muted)));
}
