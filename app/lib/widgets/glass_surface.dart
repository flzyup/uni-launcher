import 'dart:ui' as ui;
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

  /// Nocturne only: bottom glow tint owned by the card type. Leave null for
  /// dialogs and settings blocks — the design gives the glow to desktop cards
  /// alone, everything else stays plain glass.
  final Color? glow;
  final bool shadow;
  final bool dock;

  /// Nocturne only: the dock's media block. It gets a single flat tint instead
  /// of the card glass (the white gradient plus the 66 px bottom shade would
  /// read as a smudge inside a 72 px capsule), but it must still carry *some*
  /// surface — without it the playback tint floats on pure black and reads as
  /// a loose rectangle, and the block's corners no longer answer the radius
  /// setting the way the classic theme's do.
  final bool flat;

  /// Nocturne only: floating panel (dialog sheet) rather than a desktop card.
  /// Panels need an opaque base — desktop cards sit on the near-black canvas,
  /// panels sit on other cards and would otherwise show them through.
  final bool sheet;
  const GlassSurface(
      {super.key,
      required this.child,
      this.padding = const EdgeInsets.all(22),
      this.radius,
      this.tone = SurfaceTone.normal,
      this.borderColor,
      this.glow,
      this.shadow = true,
      this.dock = false,
      this.flat = false,
      this.sheet = false});

  @override
  Widget build(BuildContext context) {
    final s = SurfaceStyle.of(context),
        shape = BorderRadius.circular(radius ?? s.radius);
    if (s.nocturne) return _nocturne(s, shape);
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
                    filter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                    child: framed)
                : framed));
  }

  /// Nocturne surface: a hairline white-alpha gradient over the near-black
  /// canvas, an optional bottom glow, and no blur at all (the design is built
  /// for the 820A GPU — no backdrop-filter, no floating lights).
  Widget _nocturne(SurfaceStyle s, BorderRadius shape) {
    if (flat) {
      // 底栏音乐块：只给一层平整的淡底和细边，不叠玻璃高光与底部压暗
      // （那两样铺在 72 高的胶囊里会糊成一块黑）。底色是必须的——没有它，
      // 播放进度染在近黑画布上就只剩一根孤立的色块，四角也不随圆角走。
      return ClipRRect(
          borderRadius: shape,
          child: DecoratedBox(
              decoration: BoxDecoration(
                  // 和经典主题底栏音乐块的 soft 底色同一个值：暗夜要的是
                  // 「显示方式跟经典一样」，不是另立一套。
                  color: const Color(0x1AB3D9D9),
                  borderRadius: shape,
                  border: Border.all(color: const Color(0x2BFFFFFF))),
              child: Material(
                  type: MaterialType.transparency,
                  child: Padding(padding: padding, child: child))));
    }
    final isCard = !dock && !sheet;
    // 卡片和浮层面板共用同一套玻璃，区别只有两处：面板背后是内容而不是
    // 纯黑画布，所以必须给一个实底，否则会透出底下的卡片；光晕也要收敛，
    // 同样强度的椭圆铺在整块面板上会糊成一片色雾。
    final glass = isCard || sheet;
    final fill = glass
        ? const LinearGradient(
            begin: Alignment(-.2, -.98),
            end: Alignment(.2, .98),
            stops: [0, .42, .74, 1],
            colors: [
              Color(0x16FFFFFF),
              Color(0x08FFFFFF),
              Color(0x04FFFFFF),
              Color(0x0AFFFFFF)
            ])
        : const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF1A1E20), Color(0xFF0B0D0E)]);
    return DecoratedBox(
        decoration: BoxDecoration(
            borderRadius: shape,
            boxShadow: shadow
                ? [
                    // 0 26px 54px -26px rgba(0,0,0,.9) on the design board.
                    const BoxShadow(
                        color: Color(0xE6000000),
                        offset: Offset(0, 26),
                        blurRadius: 54,
                        spreadRadius: -26),
                  ]
                : null),
        child: ClipRRect(
            borderRadius: shape,
            child: Stack(fit: StackFit.passthrough, children: [
              // 底色和渐变必须分两层：BoxDecoration 里 gradient 一旦存在，
              // color 会被整段忽略，写在一起等于没给底色。
              if (sheet)
                Positioned.fill(
                    child: DecoratedBox(
                        decoration: BoxDecoration(
                            color: const Color(0xFA131619),
                            borderRadius: shape))),
              Positioned.fill(
                  child: DecoratedBox(
                      decoration: BoxDecoration(
                          gradient: fill,
                          borderRadius: shape,
                          border: Border.all(
                              color: borderColor ?? s.edge)))),
              if (glow != null && glass)
                sheet
                    // 弹层只让光从底部三分之一升起：整块面板做椭圆会糊满。
                    ? Positioned.fill(
                        child: Align(
                            alignment: Alignment.bottomCenter,
                            child: FractionallySizedBox(
                                heightFactor: .34,
                                widthFactor: 1,
                                child: _glowLayer(glow!, .75,
                                    ryScale: 1.15))))
                    : Positioned.fill(child: _glowLayer(glow!, 1)),
              if (glass)
                Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    height: Design.dz(66),
                    child: DecoratedBox(
                        decoration: BoxDecoration(
                            gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                          const Color(0x00000000),
                          Colors.black.withValues(alpha: .68)
                        ])))),
              if (glass)
                Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    height: 1.4,
                    child: DecoratedBox(
                        decoration: BoxDecoration(
                            gradient: LinearGradient(colors: [
                          const Color(0x00FFFFFF),
                          Colors.white.withValues(alpha: .16),
                          const Color(0x00FFFFFF)
                        ])))),
              Material(
                  type: MaterialType.transparency,
                  child: Padding(padding: padding, child: child)),
            ])));
  }

  /// Bottom glow drawn as a true ellipse: same geometry as the design's
  /// `.card::before` (light centre 28 % below the card, rx 82 % / ry 94 % of
  /// the card, bright plateau to 22 %, fully faded at 76 %).
  ///
  /// [ryScale] 收窄垂直半径：弹层比卡片高得多，同一比例铺开会糊满整个面板。
  Widget _glowLayer(Color glow, double alphaScale,
          {double ryScale = 1}) =>
      CustomPaint(
          painter: _NocturneGlowPainter(
              alphaScale == 1
                  ? glow
                  : glow.withValues(alpha: glow.a * alphaScale),
              ryScale));
}

class _NocturneGlowPainter extends CustomPainter {
  final Color glow;
  final double ryScale;
  const _NocturneGlowPainter(this.glow, this.ryScale);
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height * 1.28);
    final rx = size.width * .82, ry = size.height * .94 * ryScale;
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.scale(rx, ry);
    final halo = Paint()
      ..shader = ui.Gradient.radial(Offset.zero, 1, [
        glow,
        glow,
        glow.withValues(alpha: 0)
      ], [
        0.0,
        0.22,
        0.76
      ], ui.TileMode.clamp);
    canvas.drawCircle(Offset.zero, 1, halo);
    // Spill light beyond the card edge: the CSS design relies on an outer
    // box-shadow for this, but Flutter's BoxShadow floods the whole
    // semi-transparent surface, so the spill is drawn here instead.
    canvas.scale(1.35, 1.35);
    canvas.drawCircle(
        Offset.zero,
        1,
        Paint()
          ..shader = ui.Gradient.radial(Offset.zero, 1, [
            glow.withValues(alpha: .38),
            glow.withValues(alpha: 0)
          ], [
            0.0,
            1.0
          ], ui.TileMode.clamp));
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _NocturneGlowPainter oldDelegate) =>
      oldDelegate.glow != glow;
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
