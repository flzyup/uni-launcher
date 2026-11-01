import 'dart:ui';
import 'package:flutter/material.dart';
import '../theme/launcher_theme.dart';
import '../theme/design_tokens.dart';
import '../theme/technical_frame.dart';
import 'uni_icon.dart';

enum SurfaceTone { normal, strong, soft }

class GlassSurface extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double? radius;
  final SurfaceTone tone;
  final Color? borderColor;

  /// 暗夜卡片底部光晕色（一卡一色）。零滤镜的径向渐变，外溢用 box-shadow。
  final Color? glow;
  final bool shadow;
  final bool dock;
  const GlassSurface(
      {super.key,
      required this.child,
      this.padding = const EdgeInsets.all(22),
      this.radius,
      this.tone = SurfaceTone.normal,
      this.borderColor,
      this.glow,
      this.shadow = true,
      this.dock = false});
  /// 只向卡片内扩散的底部色光：设计稿是 radial-gradient 三段 stop，零滤镜。
  /// 820A 上不能为了这个光晕开离屏层或高斯。
  /// 范围锁在卡片下方 60%、强度再降到设计稿的六成：设计稿的卡底比这里亮，
  /// 同样的 alpha 压在近黑卡上会糊成一片色雾。
  Widget _glowLayer(Color glow) {
    final tint = glow.withValues(alpha: glow.a * .6);
    return Positioned.fill(
        child: IgnorePointer(
            child: Align(
                alignment: Alignment.bottomCenter,
                child: FractionallySizedBox(
                    heightFactor: .6,
                    widthFactor: 1,
                    child: Transform.scale(
                        // 设计稿的渐变是 66%×130% 的椭圆，这里横向拉开模拟，
                        // 溢出部分由外层 ClipRRect 裁掉，纯矩阵变换不产生滤镜。
                        scaleX: 1.6,
                        child: DecoratedBox(
                            decoration: BoxDecoration(
                                gradient: RadialGradient(
                                    center: const Alignment(0, 1.15),
                                    radius: .62,
                                    stops: const [0, .22, .76],
                                    colors: [
                          tint,
                          tint,
                          tint.withValues(alpha: 0)
                        ]))))))));
  }

  @override
  Widget build(BuildContext context) {
    final s = SurfaceStyle.of(context),
        shape = BorderRadius.circular(radius ?? s.radius);
    final glowColor = s.nocturne && !dock ? glow : null;
    final color = dock && (s.technicalFrame || s.nocturne)
        ? s.dock
        : switch (tone) {
            SurfaceTone.normal => s.surface,
            SurfaceTone.strong => s.strong,
            SurfaceTone.soft => s.soft,
          };
    final body = Padding(padding: padding, child: child);
    final content = DecoratedBox(
        decoration: BoxDecoration(
            color: color,
            gradient: s.nocturne
                // 暗夜玻璃：顶亮底暗的四段白叠加，取自设计稿 .card。
                ? LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    stops: const [0, .42, .74, 1],
                    colors: [
                        for (final alpha in const [.085, .032, .014, .038])
                          Color.alphaBlend(
                              Colors.white.withValues(alpha: alpha), color)
                      ])
                : s.technicalFrame && s.glass
                ? LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                        Color.alphaBlend(
                            Colors.white.withValues(alpha: s.dark ? .035 : .22),
                            color),
                        color
                      ])
                : null,
            borderRadius: shape,
            border: s.technicalFrame
                ? (dock ? Border(top: BorderSide(color: s.edge)) : null)
                : Border.all(
                    color: borderColor ??
                        (s.nocturne
                            ? const Color(0x13FFFFFF)
                            : s.edge))),
        child: Material(
            type: MaterialType.transparency,
            child: s.nocturne
                ? Stack(fit: StackFit.passthrough, children: [
                    if (glowColor != null) _glowLayer(glowColor),
                    // 顶部内高光：inset 0 1px rgba(255,255,255,.14)
                    Positioned(
                        top: 0,
                        left: 0,
                        right: 0,
                        child: IgnorePointer(
                            child: Container(
                                height: 1,
                                color: Colors.white.withValues(alpha: .14)))),
                    body,
                  ])
                : body));
    final framed = s.technicalFrame && !dock
        ? DecoratedBox(
            position: DecorationPosition.foreground,
            decoration: ShapeDecoration(
                shape: TechnicalFrameBorder(
                    radius: radius ?? s.radius,
                    cornerLength: Design.px(18),
                    side: BorderSide(
                        color: borderColor == null
                            ? s.edge
                            : Color.lerp(s.edge, borderColor, .24)!),
                    cornerColor: borderColor ?? s.corner)),
            child: content)
        : content;
    return DecoratedBox(
        decoration: BoxDecoration(
            borderRadius: shape,
            // A wide Gaussian is the single most expensive thing a card puts on
            // the raster pass here (Adreno 530 measured ~5-7ms per page). The
            // softer look is preserved at a third of the blur area.
            boxShadow: shadow
                ? [
                    BoxShadow(
                        color: s.shadow,
                        offset: Offset(0, Design.px(s.technicalFrame ? 5 : 10)),
                        blurRadius: Design.px(s.technicalFrame ? 12 : 20)),
                    // 设计稿 0 0 90px -34px var(--glow)：光只往卡外散一圈。
                    if (glowColor != null)
                      BoxShadow(
                          color: glowColor.withValues(
                              alpha: glowColor.a * .55),
                          blurRadius: Design.px(90),
                          spreadRadius: -Design.px(34))
                  ]
                : null),
        child: ClipRRect(
            borderRadius: shape,
            child: s.liveBlur
                ? BackdropFilter.grouped(
                    key: const ValueKey('glass-filter'),
                    filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                    child: framed)
                : framed));
  }
}

class IconAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap, onLongPress;
  final bool active, solid, soft, framed;
  final double size, iconSize;
  final Color? foregroundColor;
  final Widget? child;
  const IconAction(
      {super.key,
      required this.icon,
      required this.label,
      this.onTap,
      this.onLongPress,
      this.active = false,
      this.framed = true,
      this.solid = false,
      this.soft = false,
      this.size = 48,
      this.iconSize = 24,
      this.child,
      this.foregroundColor});
  @override
  Widget build(BuildContext context) {
    final s = SurfaceStyle.of(context),
        enabled = onTap != null || onLongPress != null;
    final fg = !enabled ? s.disabled
        : solid && !s.technicalFrame
            ? s.accentText
            : active
                ? s.accent
                : s.text;
    final effectiveColor = enabled ? (foregroundColor ?? fg) : fg;
    return Tooltip(
        message: label,
        child: Semantics(
            button: true,
            label: label,
            enabled: enabled,
            child: SizedBox(
                width: size,
                height: size,
                child: Material(
                    shape: s.technicalFrame && framed && (active || solid || soft)
                        ? s.controlShape(selected: active && enabled)
                        : null,
                    color: s.technicalFrame && framed && active && enabled
                        ? s.accent.withValues(alpha: .11)
                        : solid && s.technicalFrame
                            ? s.soft
                            : solid
                                ? (enabled ? s.accent : s.soft)
                                : (soft ? s.soft : Colors.transparent),
                    borderRadius:
                        s.technicalFrame && framed && (active || solid || soft)
                            ? null
                            : BorderRadius.circular(s.controlRadius),
                    child: InkWell(
                        borderRadius: BorderRadius.circular(s.controlRadius),
                        onTap: onTap,
                        onLongPress: onLongPress,
                        highlightColor: s.accent.withValues(alpha: .24),
                        hoverColor: s.accent.withValues(alpha: .08),
                        focusColor: s.accent.withValues(alpha: .16),
                        splashColor: s.accent.withValues(alpha: .16),
                        overlayColor: WidgetStateProperty.resolveWith<Color>(
                            (states) => s.accent.withValues(
                                alpha: states.contains(WidgetState.pressed)
                                    ? .24
                                    : .08)),
                        child: Center(
                            child: child ??
                                DesignIcon(icon,
                                    size: iconSize,
                                    color: effectiveColor)))))));
  }
}

class CardHeading extends StatelessWidget {
  final String title, source;
  final IconData icon;
  const CardHeading(this.title, this.source, this.icon, {super.key});
  @override
  Widget build(BuildContext context) {
    final s = SurfaceStyle.of(context);
    return Row(children: [
      DesignIcon(icon, size: Design.px(27), color: s.accent),
      SizedBox(width: Design.px(12)),
      Expanded(
          child: Text(title,
              style: TextStyle(fontSize: Design.px(25)),
              maxLines: 1,
              overflow: TextOverflow.ellipsis)),
      SizedBox(width: Design.px(14)),
      Flexible(
          child: Text(source,
              style: TextStyle(fontSize: Design.px(16), color: s.muted),
              maxLines: 1,
              overflow: TextOverflow.ellipsis))
    ]);
  }
}

class DesignToggle extends StatelessWidget {
  final String label;
  final bool value;
  final ValueChanged<bool>? onChanged;
  const DesignToggle(
      {super.key, required this.label, required this.value, this.onChanged});
  @override
  Widget build(BuildContext context) {
    final s = SurfaceStyle.of(context);
    return Semantics(
        label: label,
        toggled: value,
        enabled: onChanged != null,
        child: InkWell(
            onTap: onChanged == null ? null : () => onChanged!(!value),
            borderRadius: BorderRadius.circular(s.controlRadius),
            child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                width: Design.px(88),
                height: Design.px(48),
                padding: EdgeInsets.all(Design.px(6)),
                decoration: s.technicalFrame
                    ? ShapeDecoration(
                        color: value ? s.accent.withValues(alpha: .11) : s.soft,
                        shape: TechnicalFrameBorder(
                            radius: (s.radius * .25).clamp(0, Design.px(8)),
                            cornerLength: Design.px(5),
                            cornerColor: value ? s.accent : s.corner,
                            side: BorderSide(color: s.edge)))
                    : BoxDecoration(
                        color: value ? s.accent : s.soft,
                        border: Border.all(
                            color: value ? Colors.transparent : s.edge),
                        borderRadius: BorderRadius.circular(s.controlRadius)),
                child: Align(
                    alignment:
                        value ? Alignment.centerRight : Alignment.centerLeft,
                    child: Container(
                        width: Design.px(34),
                        height: Design.px(34),
                        decoration: BoxDecoration(
                            color: value
                                ? (s.technicalFrame ? s.accent : s.accentText)
                                : s.muted,
                            borderRadius: BorderRadius.circular(s.technicalFrame
                                ? (s.radius * .2).clamp(0, Design.px(6))
                                : s.radius * .42)))))));
  }
}

/// One switch layout across settings; classic retains the platform switch.
class DesignSwitchTile extends StatelessWidget {
  final Widget title;
  final Widget? subtitle;
  final EdgeInsetsGeometry? contentPadding;
  final bool value;
  final ValueChanged<bool>? onChanged;
  const DesignSwitchTile(
      {super.key,
      required this.title,
      this.subtitle,
      this.contentPadding,
      required this.value,
      this.onChanged});
  @override
  Widget build(BuildContext context) {
    if (!SurfaceStyle.of(context).technicalFrame) {
      return SwitchListTile(
          title: title,
          subtitle: subtitle,
          contentPadding: contentPadding,
          value: value,
          onChanged: onChanged);
    }
    return ListTile(
        title: title,
        subtitle: subtitle,
        contentPadding: contentPadding,
        enabled: onChanged != null,
        onTap: onChanged == null ? null : () => onChanged!(!value),
        trailing: Opacity(
            opacity: onChanged == null ? .45 : 1,
            child: DesignToggle(
                label: title is Text ? (title as Text).data ?? '' : '',
                value: value,
                onChanged: onChanged)));
  }
}
