import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../theme/launcher_theme.dart';
import '../theme/skin_material.dart';
import '../theme/design_tokens.dart';
import '../theme/technical_frame.dart';
import 'choice_button.dart';
import 'uni_icon.dart';

/// 把浮层面板的底色抬到至少 98% 不透明。
///
/// 面板底下压着卡片和壁纸，不是纯画布；底色太透时同一行文字在不同位置
/// 会呈现不同对比度（浅色 classic 只有 55% 白），看起来像字重变了。
/// `.98` 与暗夜分支的 `0xFA131619` 同一档；留 2% 只为让壁纸在边缘有一点点
/// 呼吸感，不会让底下的内容重新透出来。
Color _opaque(Color base) => base.a >= .98 ? base : base.withValues(alpha: .98);

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
  final bool dockFramed;

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

  /// 桌面卡片（主页那几页的卡）才为 true。
  ///
  /// 卡底压暗带**只属于桌面卡片**：设计稿里它是 `.card` 的装饰，设置面板、
  /// 弹窗、列表块（`.blk`）上都没有。默认 false，所以所有面板/弹窗/设置块
  /// 自动干净，只有卡片渲染处显式打开。
  final bool card;
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
      this.dockFramed = false,
      this.flat = false,
      this.sheet = false,
      this.card = false});

  @override
  Widget build(BuildContext context) {
    final s = SurfaceStyle.of(context),
        shape = BorderRadius.circular(radius ?? s.radius),
        m = s.material;
    final effectiveRadius = radius ?? s.radius;
    final body = Material(
        key: const ValueKey('glass-surface-body'),
        type: MaterialType.transparency,
        child: Padding(padding: padding, child: child));

    if (s.nocturne) return _nocturne(s, shape, body);
    final color = dock && s.technicalFrame
        ? s.dock
        : (sheet
            // 浮层面板背后是**内容**而不是桌面画布，必须给足实底：classic
            // 浅色的 `surface` 只有 55% 白，底下的卡片、大数字会透上来，
            // 同一套文字在上半截和下半截对比度不一样，看起来像字重变了
            // （用户就是这么报的）。暗夜分支早已单独给 0xFA 实底，这里补上
            // 同一件事，三套皮肤对齐到 98%。
            ? _opaque(switch (tone) {
                SurfaceTone.normal => s.surface,
                SurfaceTone.strong => s.strong,
                SurfaceTone.soft => s.soft,
              })
            : switch (tone) {
                SurfaceTone.normal => s.surface,
                SurfaceTone.strong => s.strong,
                SurfaceTone.soft => s.soft,
              });
    final bgBox = DecoratedBox(
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
                ? (dock && !dockFramed
                    ? Border(top: BorderSide(color: s.edge))
                    : null)
                : Border.all(color: borderColor ?? s.edge)));
    // 卡底压暗带：锁在材质表里，三套皮肤各取各的值。
    // classic 浅底给 0（压暗会变脏），所以这里不能写死颜色。
    final decorated = !card
        ? bgBox
        : ClipRRect(
            borderRadius: shape,
            child: Stack(fit: StackFit.passthrough, children: [
              bgBox,
              if (kCardBottomShade && m.cardShade > 0)
                Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    height: Design.dz(66),
                    child: IgnorePointer(
                        child: DecoratedBox(
                            decoration: BoxDecoration(
                                gradient: LinearGradient(
                                    begin: Alignment.topCenter,
                                    end: Alignment.bottomCenter,
                                    colors: [
                          const Color(0x00000000),
                          Colors.black.withValues(alpha: m.cardShade)
                        ]))))),
            ]));
    final framedBg = s.technicalFrame && (!dock || dockFramed)
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
            child: decorated)
        : decorated;
    final stack = Stack(fit: StackFit.passthrough, children: [
      Positioned.fill(
          child: s.liveBlur
              ? BackdropFilter.grouped(
                  key: const ValueKey('glass-filter'),
                  filter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                  child: framedBg)
              : framedBg),
      body,
    ]);
    final clipped = effectiveRadius > 0
        ? ClipRRect(borderRadius: shape, child: stack)
        : stack;
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
        child: clipped);
  }

  /// Nocturne surface: a hairline white-alpha gradient over the near-black
  /// canvas, an optional bottom glow, and no blur at all (the design is built
  /// for the 820A GPU — no backdrop-filter, no floating lights).
  Widget _nocturne(SurfaceStyle s, BorderRadius shape, Widget body) {
    if (flat) {
      // 底栏音乐块：只给一层平整的淡底和细边，不叠玻璃高光与底部压暗
      // （那两样铺在 72 高的胶囊里会糊成一块黑）。底色是必须的——没有它，
      // 播放进度染在近黑画布上就只剩一根孤立的色块，四角也不随圆角走。
      return ClipRRect(
          borderRadius: shape,
          child: Stack(fit: StackFit.passthrough, children: [
            Positioned.fill(
                child: DecoratedBox(
                    decoration: BoxDecoration(
                        // 和经典主题底栏音乐块的 soft 底色同一个值：暗夜要的是
                        // 「显示方式跟经典一样」，不是另立一套。
                        // 有壁纸时这块必须给实底，否则胶囊、播放键、进度全浮在照片上。
                        color: s.wallpaperBacked
                            ? const Color(0xCC0B0D0E)
                            : const Color(0x1AB3D9D9),
                        borderRadius: shape,
                        border: Border.all(
                            color: s.wallpaperBacked
                                ? const Color(0x26FFFFFF)
                                : const Color(0x2BFFFFFF))))),
            body,
          ]));
    }
    final isCard = !dock && !sheet;
    // 卡片和浮层面板共用同一套玻璃，区别只有两处：面板背后是内容而不是
    // 纯黑画布，所以必须给一个实底，否则会透出底下的卡片；光晕也要收敛，
    // 同样强度的椭圆铺在整块面板上会糊成一片色雾。
    final glass = isCard || sheet;
    final fill = glass
        ? (s.wallpaperBacked
            // 有壁纸：5% 白的玻璃会把照片透上来，卡片和按钮就「全透明」了。
            // 换成一层近黑半透底（约 72%），照片隐约透出来、内容仍然读得清；
            // 顶端留一点高光保住玻璃感。这里**不加实时模糊**：820A 上每页要多
            // 5~7ms，而降级开关又要跟着动一轮（用户 2026-11-13 定的）。
            ? const LinearGradient(
                begin: Alignment(-.2, -.98),
                end: Alignment(.2, .98),
                stops: [
                    0,
                    .42,
                    .74,
                    1
                  ],
                colors: [
                    Color(0xB414181A),
                    Color(0xBC0D1012),
                    Color(0xC00A0C0E),
                    Color(0xB80E1113)
                  ])
            : const LinearGradient(
                begin: Alignment(-.2, -.98),
                end: Alignment(.2, .98),
                stops: [
                    0,
                    .42,
                    .74,
                    1
                  ],
                colors: [
                    Color(0x16FFFFFF),
                    Color(0x08FFFFFF),
                    Color(0x04FFFFFF),
                    Color(0x0AFFFFFF)
                  ]))
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
                    //
                    // 降级（AdaptiveQuality 判出来帧预算不够）时收一半：宽高斯是
                    // raster 里最贵的一笔（Adreno 530 上 5-7ms/页），而阴影只是
                    // 让卡片“浮起来”，砍半几乎看不出来，帧却省得出来。
                    BoxShadow(
                        // 有壁纸时：90% 黑 + 54 模糊会变成卡片底下一坨黑（近黑画布上
                        // 本来看不见）。改成更紧、更淡的一圈，只用来「托一下」。
                        color: s.wallpaperBacked
                            ? const Color(0x8C000000)
                            : const Color(0xE6000000),
                        offset: Offset(0, s.wallpaperBacked ? 18 : 26),
                        blurRadius: s.wallpaperBacked
                            ? (s.lowPower ? 20 : 34)
                            : (s.lowPower ? 26 : 54),
                        spreadRadius: s.wallpaperBacked
                            ? (s.lowPower ? -8 : -16)
                            : (s.lowPower ? -13 : -26)),
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
                            // 稿子每个 `.dlg` 的底：
                            // `linear-gradient(168deg,#2C3136,#181B1E)`。
                            // 纯色渐变，不叠模糊也不叠光晕，三个皮肤同一块底。
                            gradient: const LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                transform:
                                    GradientRotation(-12 * math.pi / 180),
                                colors: [Color(0xFA2C3136), Color(0xFA181B1E)]),
                            borderRadius: shape))),
              Positioned.fill(
                  child: DecoratedBox(
                      decoration: BoxDecoration(
                          gradient: fill,
                          borderRadius: shape,
                          border: Border.all(color: borderColor ?? s.edge)))),
              if (glow != null && glass)
                sheet
                    // 弹层只让光从底部三分之一升起：整块面板做椭圆会糊满。
                    ? Positioned.fill(
                        child: Align(
                            alignment: Alignment.bottomCenter,
                            child: FractionallySizedBox(
                                heightFactor: .34,
                                widthFactor: 1,
                                child: _glowLayer(glow!, .75, ryScale: 1.15))))
                    : Positioned.fill(child: _glowLayer(glow!, 1)),
              if (card && kCardBottomShade)
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
                          // 设计稿 .card::after：底部 66px 压到黑 34%。
                          Colors.black.withValues(alpha: s.material.cardShade)
                        ])))),
              if (card && kCardBottomShade)
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
                          // 设计稿 .card::after：底部 66px 压到黑 34%。
                          Colors.black.withValues(alpha: s.material.cardShade)
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
              body,
            ])));
  }

  /// Bottom glow drawn as a true ellipse: same geometry as the design's
  /// `.card::before` (light centre 28 % below the card, rx 82 % / ry 94 % of
  /// the card, bright plateau to 22 %, fully faded at 76 %).
  ///
  /// [ryScale] 收窄垂直半径：弹层比卡片高得多，同一比例铺开会糊满整个面板。
  Widget _glowLayer(Color glow, double alphaScale, {double ryScale = 1}) =>
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
    // 设计稿 `.glow` 是
    // `radial-gradient(ellipse at center, rgba(acc,.30) 0%, rgba(acc,.11) 22%,
    //  transparent 76%)`：22% 处只剩**峰值的 37%**，不是平顶。
    // 之前这里写成 `[glow, glow, 0]`，把峰值一路铺到 22% 才开始衰减，
    // 卡片下半部就变成一片实色雾——比设计稿重得多。
    final halo = Paint()
      ..shader = ui.Gradient.radial(
          Offset.zero,
          1,
          [
            glow,
            glow.withValues(alpha: glow.a * .37),
            glow.withValues(alpha: 0)
          ],
          [0.0, 0.22, 0.76],
          ui.TileMode.clamp);
    canvas.drawCircle(Offset.zero, 1, halo);
    // 设计稿的卡片是 overflow:hidden，光晕不出边；外扩那层「溢光」
    // （1.35 倍再叠 38%）在稿子里根本不存在，只会把颜色加深，已删。
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
    final fg = !enabled
        ? s.disabled
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
    final s = SurfaceStyle.of(context);
    // ListTile 把背景/水波纹画在最近的 Material 上；调用方常把它包在带底色的
    // DecoratedBox 里，debug 下会刷满 "ListTile background color or ink
    // splashes may be invisible"。自带一层透明 Material 即可，视觉零变化。
    Widget tiled(Widget child) =>
        Material(type: MaterialType.transparency, child: child);
    // 经典主题还是 Material 的 SwitchListTile；暗夜用设计稿的 46×26 开关，
    // 否则同一页里「外观与壁纸」的两个开关是自绘的青绿胶囊，
    // 而这几十个 DesignSwitchTile 是 Flutter 原生的灰胶囊，一眼就不成套。
    if (!s.technicalFrame && !s.nocturne) {
      return tiled(SwitchListTile(
          title: title,
          subtitle: subtitle,
          contentPadding: contentPadding,
          value: value,
          onChanged: onChanged));
    }
    return tiled(ListTile(
        title: title,
        subtitle: subtitle,
        contentPadding: contentPadding,
        enabled: onChanged != null,
        onTap: onChanged == null ? null : () => onChanged!(!value),
        trailing: Opacity(
            opacity: onChanged == null ? .45 : 1,
            child: s.technicalFrame
                ? DesignToggle(
                    label: title is Text ? (title as Text).data ?? '' : '',
                    value: value,
                    onChanged: onChanged)
                : DesignSwitch(
                    semanticLabel: title is Text ? (title as Text).data : null,
                    value: value,
                    onChanged: onChanged))));
  }
}
