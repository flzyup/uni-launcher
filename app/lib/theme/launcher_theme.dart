import 'dart:math' as math;

import 'package:flutter/material.dart';
import '../model/appearance.dart';
import 'design_tokens.dart';
import 'contrast.dart';
import 'liquid_backdrop.dart';
import 'launcher_type.dart';
import 'skin_material.dart';
import 'technical_frame.dart';

/// Nocturne (暗夜) palette, copied 1:1 from `design/desktop-lynk05.html`.
///
/// The skin's identity is "one colour per card": every card owns a single hue
/// that lives only in its bottom glow, so six hues can coexist on one desktop
/// without fighting the selected accent colour.
abstract final class Nocturne {
  static const mint = Color(0xFF3BE2C0);
  static const blue = Color(0xFF4E8CF8);
  static const violet = Color(0xFF8E6CFF);
  static const pink = Color(0xFFFF5FA8);
  static const amber = Color(0xFFFFB057);
  static const cyan = Color(0xFF6FD3FF);

  /// Canvas behind everything: near-black, never pure #000, so the card
  /// shadows and the two ambient glows still read. (The 80 px grid that used
  /// to sit on top of it was removed — it cut the empty space into cells and
  /// made every card look pasted onto graph paper.)
  static const background = Color(0xFF050607);

  /// 切到暗夜时写进「圆角」的初始值。设计稿是 34，按实机观感收到 25：
  /// 34 在 1600 画布上是 1:1 单位，比经典主题的换算值大一圈。
  static const defaultRadius = 25.0;

  /// Alpha is tuned per card type, not shared: a 4x2 card needs more glow than
  /// an 8x6 one to read as the same intensity (measured on the design canvas).
  static const _glow = <String, Color>{
    'nav': Color(0x4D3BE2C0),
    'trafficLight': Color(0x473BE2C0),
    'music': Color(0x4DFF5FA8),
    'shortcuts': Color(0x428E6CFF),
    'weather': Color(0x526FD3FF),
    'air': Color(0x576FD3FF),
    'cleanup': Color(0x476FD3FF),
    // 垃圾清理面板沿用清理类卡片的青色，不新开色系。
    'broom': Color(0x473BE2C0),
    'battery': Color(0x573BE2C0),
    'fuel': Color(0x573BE2C0),
    'tpms': Color(0x574E8CF8),
    'body': Color(0x574E8CF8),
    'clock': Color(0x578E6CFF),
    'clockWeather': Color(0x4D8E6CFF),
    'calendar': Color(0x478E6CFF),
    'vehicle': Color(0x52FFB057),
    'ride': Color(0x4DFFB057),
    'member': Color(0x42FF5FA8),
  };

  static Color glowOf(String type) => _glow[type] ?? const Color(0x4D3BE2C0);
}

class SurfaceStyle extends ThemeExtension<SurfaceStyle> {
  final bool dark, glass, technicalFrame, nocturne, liquidGlass;

  /// 皮肤标识。用 getter 从既有布尔位推出来，不新增构造参数——
  /// 三处工厂都已分别置位（technicalFrame 只有 blueGlass 为真、
  /// nocturne 只有 eclipse 为真），所以推出来的值与 themeStyle 一一对应，
  /// 而 `==` / hashCode 一个都不用改。
  LauncherSkin get skin => liquidGlass || technicalFrame
      ? LauncherSkin.blueGlass
      : (nocturne ? LauncherSkin.eclipse : LauncherSkin.classic);

  /// 这套皮肤在这个明暗态下的「新元素配色表」。布局是全局共用的，
  /// 只有颜色按皮肤分发，缺一项就会出现某皮肤下元素不可见。
  SkinMaterial get material => SkinMaterial.resolve(skin, dark);

  /// 画质降级：帧预算不够时由 [AdaptiveQuality] 打开，只关掉实时模糊，
  /// 配色与尺寸一个都不动，所以画面看起来是同一套皮肤。
  final bool lowPower;

  /// 背后是**一张照片**（选了壁纸）而不是主题自己的渐变画布。
  ///
  /// 暗夜这套皮肤是围着「近黑底」设计的：卡片只有 5% 白、阴影是 90% 黑 + 54 模糊。
  /// 近黑画布上那层阴影看不见；一旦换成照片，阴影就成了卡片底下一坨黑、卡片本体
  /// 又把照片透上来（用户 2026-11-13 实车反馈「按钮全透明、卡片糊成一团黑」）。
  /// 这个标记只在暗夜 + 壁纸时为真，`glass_surface` 据此换一套实底色与收敛的阴影。
  final bool wallpaperBacked;
  final double radius;
  final String spectrumStyle;
  final Color accent,
      accentText,
      seed,
      text,
      muted,
      disabled,
      surface,
      strong,
      soft,
      edge,
      shadow;
  SurfaceStyle(
      {required this.dark,
      this.technicalFrame = false,
      this.liquidGlass = false,
      this.nocturne = false,
      this.lowPower = false,
      this.wallpaperBacked = false,
      this.spectrumStyle = 'bars',
      required this.glass,
      required this.radius,
      required this.accent,
      required this.accentText,
      required this.seed,
      required this.text,
      required this.muted,
      required this.disabled,
      required this.surface,
      required this.strong,
      required this.soft,
      required this.edge,
      required this.shadow});
  factory SurfaceStyle.from(Appearance a, bool systemDark,
      {bool adaptToWallpaper = false, bool lowPower = false}) {
    // 只有暗夜需要这个标记：另两套皮肤本来就靠玻璃底色吃照片。
    final backed = a.wallpaper != 'gradient';
    if (a.themeStyle == 'nocturne') {
      return SurfaceStyle._nocturne(a, lowPower, backed);
    }
    final dark = adaptToWallpaper && a.mode == 'smart'
        ? a.backgroundIsDark(systemDark)
        : a.isDark(systemDark);
    if (a.themeStyle == 'blueGlass') {
      final accent = readableColor(
          _readableAccent(
              a.palette == 'blue'
                  ? (dark ? const Color(0xFF83B6FF) : const Color(0xFF245BC1))
                  : a.accent(dark),
              dark),
          [_liquidContrastBase(dark, a.glass)],
          minimum: 4.7);
      return SurfaceStyle(
          lowPower: lowPower,
          dark: dark,
          glass: a.glass,
          liquidGlass: true,
          spectrumStyle: a.spectrumStyle,
          radius: Design.px(a.radius),
          accent: accent,
          accentText: foregroundOn(accent),
          seed: a.seed(),
          text: dark ? const Color(0xFFF2F6FC) : const Color(0xFF08131E),
          muted: dark ? const Color(0xFFB5C3D2) : const Color(0xFF0B1927),
          disabled: dark ? const Color(0xFF8394A6) : const Color(0xFF6D7D90),
          surface: dark ? const Color(0xC51A283A) : const Color(0xD9EDF4FA),
          strong: dark ? const Color(0xF0223041) : const Color(0xF5F2F7FC),
          soft: dark ? const Color(0x123C546A) : const Color(0x0AFFFFFF),
          edge: dark ? const Color(0x40D6EDFF) : const Color(0x40283B49),
          shadow: dark ? const Color(0x50000000) : const Color(0x26364D67));
    }
    final accent = _readableAccent(a.accent(dark), dark);
    return SurfaceStyle(
        lowPower: lowPower,
        dark: dark,
        spectrumStyle: a.spectrumStyle,
        glass: a.glass,
        radius: Design.px(a.radius),
        accent: accent,
        accentText: foregroundOn(accent),
        seed: a.seed(),
        text: dark ? const Color(0xFFF2F6F5) : const Color(0xFF182D29),
        muted: dark ? const Color(0xFFB5C3D2) : const Color(0xFF42556B),
        disabled: dark ? const Color(0xFF8394A6) : const Color(0xFF6D7D90),
        surface: dark ? const Color(0xF016232B) : const Color(0xF0FFFFFF),
        strong: dark ? const Color(0xF5192730) : const Color(0xF5FAFFFD),
        soft: dark ? const Color(0x14B3D9D9) : const Color(0x5CFFFFFF),
        edge: dark ? const Color(0x2BE0FFFC) : const Color(0xC2FFFFFF),
        shadow: dark ? const Color(0x2E000D16) : const Color(0x1A365457));
  }
  static SurfaceStyle of(BuildContext c) =>
      Theme.of(c).extension<SurfaceStyle>()!;

  /// Nocturne keeps a fixed dark canvas: the skin is built around #050607 and
  /// has no light variant, so `mode` is intentionally ignored here.
  ///
  /// The radius is taken from the settings slider verbatim — one unit on the
  /// slider is one design unit on screen, so 0 really means square corners.
  /// [Nocturne.defaultRadius] is only a starting value, written by the theme
  /// picker and the preview entry point when they switch a profile to
  /// Nocturne; mapping 0 → 25 here would make the left end of the slider a
  /// dead zone.
  factory SurfaceStyle._nocturne(Appearance a,
      [bool lowPower = false, bool wallpaperBacked = false]) {
    final accent = _readableAccent(a.accent(true), true);
    return SurfaceStyle(
        nocturne: true,
        lowPower: lowPower,
        wallpaperBacked: wallpaperBacked,
        dark: true,
        glass: a.glass,
        spectrumStyle: a.spectrumStyle,
        radius: Design.dz(a.radius),
        accent: accent,
        // `--acc-d`：实心渐变上的字色，hsl(h,60%,9%) 的近黑同色系。
        accentText: foregroundOn(accent),
        seed: a.seed(),
        text: const Color(0xFFEFF4F6),
        muted: const Color(0xFFB5C3D2),
        disabled: const Color(0xFF8394A6),
        // 有壁纸时：几个表层色改成「压得住照片」的近黑实底，否则按钮、底栏胶囊、
        // 面板全都半透明地浮在照片上（实车反馈）。没壁纸时保持原值。
        surface:
            wallpaperBacked ? const Color(0xE60E1113) : const Color(0x14FFFFFF),
        strong:
            wallpaperBacked ? const Color(0xFA131619) : const Color(0xFF131619),
        soft:
            wallpaperBacked ? const Color(0xB30B0D0E) : const Color(0x0FFFFFFF),
        edge:
            wallpaperBacked ? const Color(0x24FFFFFF) : const Color(0x16FFFFFF),
        shadow: const Color(0xE6000000));
  }

  /// 820A 上逐帧离屏高斯会直接吃掉帧预算，暗夜按设计稿只用静态色阶，
  /// 不开实时模糊（设计稿 820A Budget 一节）。[lowPower] 是运行时降级：
  /// 帧预算真的不够时，同一套配色优先保住帧率。
  bool get liveBlur => glass && !technicalFrame && !nocturne && !lowPower;
  double get controlRadius =>
      technicalFrame ? (radius * .5).clamp(0, Design.px(16)) : radius * .64;
  Color get corner => dark ? const Color(0xFF829AB2) : const Color(0xFF738DA8);
  Color get dock => nocturne
      ? const Color(0xFF0B0D0E)
      : (dark ? const Color(0xFF0C1929) : const Color(0xFFF5F8FC));
  Color get background => nocturne
      ? Nocturne.background
      : technicalFrame || liquidGlass
          ? (dark ? const Color(0xFF07111F) : const Color(0xFFE8EEF5))
          : (dark ? const Color(0xFF0E1920) : const Color(0xFFE1ECE7));

  /// Bottom glow tint for a card type. Only meaningful when [nocturne] is on;
  /// other styles keep one accent for the whole desktop.
  Color? cardGlow(String type) => nocturne ? Nocturne.glowOf(type) : null;

  /// 不透明底板，只为「把卡片快照重新合成一次」而存在（拖动浮层把卡片
  /// `RepaintBoundary.toImage()` 后画在画布之上）。
  ///
  /// 快照本身几乎是透明的：卡面就是一层 8% 白叠在画布上，离屏渲染时不带
  /// 画布。经典主题的 `surface` 本身够实，直接抬到 alpha 1 就行；暗夜的
  /// `0x14FFFFFF` 一旦抬到 alpha 1 就是**纯白**，于是整张浮起来的卡片变成
  /// 一块白门板，内容全被冲淡。暗夜必须用画布色兜底。
  Color get snapshotBase =>
      nocturne ? background : surface.withValues(alpha: 1);

  BorderSide controlSide(bool selected) => BorderSide(
      color: selected
          ? (technicalFrame ? Color.lerp(edge, accent, .24)! : accent)
          : edge);

  /// 选中控件上的文字色。
  ///
  /// 经典主题的选中态是**实心 accent 底**，这时候再用 `accent` 当字色就是同色
  /// 压同色——侧边栏选中的那一项只剩图标，字整个消失。所以选中态一律走
  /// 已经为实心底算好的 [accentText]；科技框和暗夜是低透明度描边，没有实底，
  /// 用 `accent` 反而更清楚。
  late final Color selectedText =
      technicalFrame || liquidGlass || nocturne ? tintedText : accentText;

  // Light glass reveals the wallpaper instead of painting a white panel.
  // Ink is calibrated against the darkest composited stop, so transparency
  // does not depend on the selected wallpaper or per-frame pixel sampling.
  static Color _liquidTint(bool dark) =>
      dark ? const Color(0xFF172332) : const Color(0xFFDDEAF4);
  static double _liquidOpacity(bool dark, bool glass,
      {bool nested = false, bool sheet = false, bool content = false}) {
    // 嵌套面板仍有可辨识的玻璃层次；按钮只保留极薄填充。
    if (nested) return sheet ? .035 : .012;
    if (!glass) return .96;
    return sheet ? .10 : (content ? .025 : .035);
  }

  LiquidBackdrop get liquidBackdrop => LiquidBackdrop.of(dark);
  Color liquidBackground(Color background) =>
      glass ? liquidBackdrop.apply(background) : background;
  Color get liquidTint => _liquidTint(dark);
  double liquidOpacity(
          {bool nested = false, bool sheet = false, bool content = false}) =>
      _liquidOpacity(dark, glass,
          nested: nested, sheet: sheet, content: content);
  static List<Color> _liquidFill(bool dark, Color base) => [
        Color.alphaBlend(
            Colors.white.withValues(alpha: dark ? .035 : .018), base),
        Color.alphaBlend(Colors.white.withValues(alpha: .004), base),
        Color.alphaBlend(
            (dark ? Colors.black : const Color(0xFF86A7BD))
                .withValues(alpha: dark ? .035 : .018),
            base)
      ];
  List<Color> liquidFill(
          {bool nested = false, bool sheet = false, bool content = false}) =>
      _liquidFill(
          dark,
          liquidTint.withValues(
              alpha: liquidOpacity(
                  nested: nested, sheet: sheet, content: content)));
  static Color _liquidContrastBase(bool dark, bool glass) {
    final stops = [
      for (final opacity in [
        _liquidOpacity(dark, glass),
        _liquidOpacity(dark, glass, content: true),
        _liquidOpacity(dark, glass, sheet: true),
      ])
        ..._liquidFill(dark, _liquidTint(dark).withValues(alpha: opacity))
    ];
    final bases = stops
        .map((c) => Color.alphaBlend(
            c,
            glass
                ? LiquidBackdrop.of(dark)
                    .apply(dark ? Colors.white : Colors.black)
                : (dark ? Colors.white : Colors.black)))
        .toList()
      ..sort((a, b) => a.computeLuminance().compareTo(b.computeLuminance()));
    return dark ? bases.last : bases.first;
  }

  Color get contrastBase => liquidGlass
      ? _liquidContrastBase(dark, glass)
      : Color.alphaBlend(strong, background);
  Color get selectionBase {
    var base = contrastBase;
    if (liquidGlass) {
      // Top highlight plus a nested lens, both behind the label.
      base = Color.alphaBlend(
          Colors.white.withValues(alpha: dark ? .035 : .018), base);
      base = Color.alphaBlend(liquidTint.withValues(alpha: .012), base);
      base = Color.alphaBlend(
          Colors.white.withValues(alpha: dark ? .035 : .018), base);
    }
    return Color.alphaBlend(accent.withValues(alpha: .14), base);
  }

  late final Color tintedText = readableColor(accent, [
    selectionBase,
    Color.alphaBlend(accent.withValues(alpha: .14), contrastBase)
  ]);
  static Color _readableAccent(Color color, bool dark) => readableColor(
      color, [dark ? const Color(0xFF414D5A) : const Color(0xFFD0D8E0)]);

  /// 同一色相下的一个色调，只换饱和度和明度。
  static Color _tone(Color base, double saturation, double lightness) =>
      HSLColor.fromAHSL(1, HSLColor.fromColor(base).hue, saturation, lightness)
          .toColor();

  /// 设计稿的强调色是三元组而不是单色：`--acc`（本体）、`--acc-hi`（实心
  /// 控件的渐变亮端）、`--acc-lo`（暗端）。`.opt.on` / `.chip.on` / `.seg.on`
  /// 都是 `linear-gradient(170deg, acc-hi, acc-lo)` 的实心底，文字再压一层
  /// `--acc-d`（近黑的同色系），所以这三个值缺一不可。
  ///
  /// 稿子的算法是**同色相换明度**：
  /// ```
  /// --acc     hsl(h,62%,56%)   --acc-hi  hsl(h,72%,72%)
  /// --acc-lo  hsl(h,55%,40%)   --acc-d   hsl(h,60%,9%)
  /// ```
  /// 不能写成 `Color.lerp(accent, white, .32)`——往白里插值会连着**饱和度一起
  /// 稀释**，青屿的实心按钮就变成一层发白的灰绿，跟稿子上那种饱和的青绿差一
  /// 整档。这里照稿子的公式算，换任意自定义色都不会跑偏。
  late final Color accentHi = readableColor(
      nocturne
          ? _tone(accent, .72, .72)
          : Color.lerp(accent, Colors.white, .24)!,
      [accentText]);
  late final Color accentLo = readableColor(
      nocturne
          ? _tone(accent, .55, .40)
          : Color.lerp(accent, Colors.black, .30)!,
      [accentText]);

  /// 实心控件底（`.opt.on` / `.chip.on` / `.seg.on` / `.diag-btn.pri`）。
  ///
  /// 角度必须用 [GradientRotation] 锁死，不能写 `Alignment(-.34,-1)→(.34,1)`：
  /// Flutter 的 Alignment 是**相对元素宽高**的，同一个对齐在一颗 380×35 的
  /// 扁按钮上会被拉成横贯左右的渐变，而 CSS 的 `170deg` 是绝对角度。
  ///
  /// 符号：CSS 的角度是「渐变方向」，170deg = 向下偏右，所以亮端在左上；
  /// Flutter 的 rotationZ 是顺时针为正，要还原「向下偏右」得给负角。
  LinearGradient get accentFill => LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      transform: const GradientRotation(-10 * math.pi / 180),
      colors: [accentHi, accentLo]);

  OutlinedBorder controlShape({bool selected = false}) => technicalFrame
      ? TechnicalFrameBorder(
          radius: controlRadius,
          cornerLength: Design.px(10),
          cornerColor: selected ? accent : corner,
          side: controlSide(selected))
      : RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(controlRadius));
  ButtonStyle selectionStyle(bool selected) => controlStyle(
      foreground: selected ? selectedText : text,
      fill: selected
          ? (technicalFrame || liquidGlass || nocturne
              ? accent.withValues(alpha: .14)
              : accent)
          : soft,
      side: controlSide(selected),
      selected: selected);

  ButtonStyle weakSelectionStyle(bool selected) => controlStyle(
      foreground: selected ? tintedText : text,
      fill: selected ? accent.withValues(alpha: .10) : Colors.transparent,
      side: BorderSide(color: selected ? accent : edge));

  ButtonStyle controlStyle(
          {required Color foreground,
          required Color fill,
          BorderSide? side,
          bool selected = false}) =>
      ButtonStyle(
        shape: WidgetStatePropertyAll(controlShape(selected: selected)),
        minimumSize:
            const WidgetStatePropertyAll(Size(0, Design.controlHeight)),
        padding: WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: Design.px(24))),
        textStyle: WidgetStatePropertyAll(TextStyle(
            fontSize: Design.px(21),
            fontWeight: FontWeight.w400,
            height: LauncherType.lineTight,
            letterSpacing: 0)),
        visualDensity: VisualDensity.standard,
        foregroundColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.disabled) ? disabled : foreground),
        backgroundColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.disabled)
                ? Color.alphaBlend(disabled.withValues(alpha: .08), soft)
                : fill),
        side: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.disabled)
                ? BorderSide(color: disabled.withValues(alpha: .24))
                : side),
        overlayColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.disabled)
                ? Colors.transparent
                : foreground.withValues(
                    alpha: states.contains(WidgetState.pressed)
                        ? .12
                        : states.contains(WidgetState.focused)
                            ? .10
                            : .06)),
      );
  @override
  SurfaceStyle copyWith() => this;
  @override
  SurfaceStyle lerp(covariant SurfaceStyle? other, double t) => other ?? this;
  // ThemeData compares extensions with mapEquals, which falls back to identity for
  // types without value equality. Without these, every rebuild produced a "new"
  // theme and Theme re-inflated the whole subtree — repainting every card on each
  // controller notification.
  @override
  bool operator ==(Object other) =>
      other is SurfaceStyle &&
      other.dark == dark &&
      other.glass == glass &&
      other.technicalFrame == technicalFrame &&
      other.liquidGlass == liquidGlass &&
      other.nocturne == nocturne &&
      other.lowPower == lowPower &&
      other.wallpaperBacked == wallpaperBacked &&
      other.radius == radius &&
      other.spectrumStyle == spectrumStyle &&
      other.accent == accent &&
      other.accentText == accentText &&
      other.seed == seed &&
      other.text == text &&
      other.muted == muted &&
      other.disabled == disabled &&
      other.surface == surface &&
      other.strong == strong &&
      other.soft == soft &&
      other.edge == edge &&
      other.shadow == shadow;
  @override
  int get hashCode => Object.hash(
      dark,
      glass,
      technicalFrame,
      liquidGlass,
      nocturne,
      lowPower,
      wallpaperBacked,
      radius,
      spectrumStyle,
      accent,
      accentText,
      seed,
      text,
      muted,
      disabled,
      surface,
      strong,
      soft,
      edge,
      shadow);
}

SurfaceStyle? _cachedStyle;
ThemeData? _cachedTheme;

ThemeData launcherTheme(SurfaceStyle s) {
  final cached = _cachedTheme;
  if (cached != null && _cachedStyle == s) return cached;
  final data = _buildTheme(s);
  _cachedStyle = s;
  _cachedTheme = data;
  return data;
}

/// ColorScheme.fromSeed runs a full HCT derivation; the result depends only on the
/// resolved style, so the launcher builds it once per appearance instead of once
/// per frame.
ThemeData _buildTheme(SurfaceStyle s) {
  final colors = ColorScheme.fromSeed(
          seedColor: s.seed,
          brightness: s.dark ? Brightness.dark : Brightness.light)
      .copyWith(
          primary: s.accent,
          onPrimary: s.accentText,
          primaryContainer: s.soft,
          onPrimaryContainer: s.tintedText,
          secondary: s.accent,
          onSecondary: s.accentText,
          secondaryContainer: s.soft,
          onSecondaryContainer: s.tintedText,
          onSurfaceVariant: s.muted,
          surfaceContainerHighest: s.strong,
          surface: s.strong,
          onSurface: s.text,
          outline: s.edge);
  return ThemeData(
      useMaterial3: true,
      splashFactory:
          s.liquidGlass ? NoSplash.splashFactory : InkRipple.splashFactory,
      brightness: colors.brightness,
      colorScheme: colors,
      scaffoldBackgroundColor: s.background,
      // 字族留空 = 跟随车机系统字体（见 launcher_type.dart 的实测依据）。
      // 默认行高留 1.2：绝大多数 Text 是单行标签，行高只影响行盒高度；
      // 段落级的多行说明显式用 LauncherType.lineBody / lineLoose。
      textTheme: Typography.material2021()
          .black
          .apply(
              fontFamily: LauncherType.family,
              bodyColor: s.text,
              displayColor: s.text)
          .copyWith(
              bodyMedium: TextStyle(
                  fontSize: Design.px(20),
                  height: LauncherType.lineTight,
                  color: s.text,
                  letterSpacing: 0)),
      // 设计稿里 `.tbtn`（「打开导航应用」「立即应用驾驶模式」「立即开启无线
      // adb」都是这一类）是 `color: rgb(var(--acc))` 的纯文字链接，不是灰字。
      // 挂在 `s.muted`（白 40%）上的话，暗夜底下这些操作几乎看不见。
      disabledColor: s.disabled,
      iconTheme: IconThemeData(color: s.text),
      textButtonTheme: TextButtonThemeData(
          style:
              s.controlStyle(foreground: s.accent, fill: Colors.transparent)),
      outlinedButtonTheme:
          OutlinedButtonThemeData(style: s.selectionStyle(false)),
      filledButtonTheme: FilledButtonThemeData(
          style: s.controlStyle(foreground: s.accentText, fill: s.accent)),
      elevatedButtonTheme: ElevatedButtonThemeData(
          style: s
              .controlStyle(foreground: s.accentText, fill: s.accent)
              .copyWith(elevation: const WidgetStatePropertyAll(0))),
      iconButtonTheme: IconButtonThemeData(
          style: s
              .controlStyle(foreground: s.text, fill: Colors.transparent)
              .copyWith(
                  padding: const WidgetStatePropertyAll(EdgeInsets.zero))),
      switchTheme: SwitchThemeData(
          thumbColor: WidgetStateProperty.resolveWith(
              (states) => states.contains(WidgetState.disabled)
                  ? s.disabled
                  : states.contains(WidgetState.selected)
                      ? s.accentText
                      : (s.dark ? s.text : Colors.white)),
          trackColor: WidgetStateProperty.resolveWith(
              (states) => states.contains(WidgetState.disabled)
                  ? s.soft
                  : states.contains(WidgetState.selected)
                      ? s.accent
                      : s.muted),
          trackOutlineColor: WidgetStatePropertyAll(s.edge)),
      listTileTheme: ListTileThemeData(
          textColor: s.text,
          iconColor: s.muted,
          selectedColor: s.tintedText,
          selectedTileColor: s.accent.withValues(alpha: .10)),
      popupMenuTheme: PopupMenuThemeData(
          color: s.strong.withValues(alpha: .98),
          textStyle: TextStyle(color: s.text, fontSize: Design.px(21)),
          shape: s.controlShape()),
      dialogTheme: DialogThemeData(
          backgroundColor: s.strong.withValues(alpha: .98),
          shape: s.controlShape()),
      snackBarTheme: SnackBarThemeData(
          backgroundColor: s.strong.withValues(alpha: 1),
          contentTextStyle: TextStyle(color: s.text)),
      inputDecorationTheme: InputDecorationTheme(
          labelStyle: TextStyle(color: s.muted),
          hintStyle: TextStyle(color: s.muted),
          filled: true,
          fillColor: s.soft,
          contentPadding: EdgeInsets.symmetric(
              horizontal: Design.px(15), vertical: Design.px(14)),
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(s.radius * .5),
              borderSide: BorderSide(color: s.edge)),
          enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(s.radius * .5),
              borderSide: BorderSide(color: s.edge))),
      sliderTheme: SliderThemeData(
          trackHeight: Design.px(6),
          showValueIndicator: ShowValueIndicator.never,
          thumbShape: RoundSliderThumbShape(enabledThumbRadius: Design.px(7)),
          overlayShape: RoundSliderOverlayShape(overlayRadius: Design.px(18)),
          tickMarkShape: SliderTickMarkShape.noTickMark),
      tooltipTheme:
          const TooltipThemeData(waitDuration: Duration(milliseconds: 800)),
      extensions: [s]);
}
