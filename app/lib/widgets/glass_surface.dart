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
  final bool shadow;
  final bool dock;
  const GlassSurface(
      {super.key,
      required this.child,
      this.padding = const EdgeInsets.all(22),
      this.radius,
      this.tone = SurfaceTone.normal,
      this.borderColor,
      this.shadow = true,
      this.dock = false});
  @override
  Widget build(BuildContext context) {
    final s = SurfaceStyle.of(context),
        shape = BorderRadius.circular(radius ?? s.radius);
    final color = dock && s.technicalFrame
        ? s.dock
        : switch (tone) {
            SurfaceTone.normal => s.surface,
            SurfaceTone.strong => s.strong,
            SurfaceTone.soft => s.soft,
          };
    final content = DecoratedBox(
        decoration: BoxDecoration(
            color: color,
            gradient: s.technicalFrame && s.glass
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
                : Border.all(color: borderColor ?? s.edge)),
        child: Material(
            type: MaterialType.transparency,
            child: Padding(padding: padding, child: child)));
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
                        blurRadius: Design.px(s.technicalFrame ? 12 : 20))
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
    final fg = !enabled
        ? s.muted.withValues(alpha: .35)
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
                    shape:
                        s.technicalFrame && framed && (active || solid || soft)
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
                        highlightColor: s.accent.withValues(alpha: .20),
                        splashColor: s.accent.withValues(alpha: .12),
                        splashFactory: NoSplash.splashFactory,
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
