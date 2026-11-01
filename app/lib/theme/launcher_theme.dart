import 'package:flutter/material.dart';
import '../model/appearance.dart';
import 'design_tokens.dart';
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

  /// Canvas behind everything: near-black, never pure #000, so the 80 px grid
  /// and the card shadows still read.
  static const background = Color(0xFF050607);

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
    'battery': Color(0x573BE2C0),
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
  final bool dark, glass, technicalFrame, nocturne;
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
  const SurfaceStyle(
      {required this.dark,
      this.technicalFrame = false,
      this.nocturne = false,
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
      {bool adaptToWallpaper = false}) {
    if (a.themeStyle == 'nocturne') return SurfaceStyle._nocturne(a);
    final dark = adaptToWallpaper && a.mode == 'smart'
        ? a.backgroundIsDark(systemDark)
        : a.isDark(systemDark);
    if (a.themeStyle == 'blueGlass') {
      final accent = a.palette == 'blue'
          ? (dark ? const Color(0xFF83B6FF) : const Color(0xFF245BC1))
          : a.accent(dark);
      return SurfaceStyle(
          dark: dark,
          glass: a.glass,
          technicalFrame: true,
          spectrumStyle: a.spectrumStyle,
          radius: Design.px(a.radius),
          accent: accent,
          accentText: dark ? const Color(0xFF07111F) : Colors.white,
          seed: a.seed(),
          text: dark ? const Color(0xFFF2F6FC) : const Color(0xFF172B42),
          muted: dark ? const Color(0xFFA2B3C7) : const Color(0xFF52687F),
          disabled: dark ? const Color(0xFF68808F) : const Color(0xFF93A5BA),
          surface: dark ? const Color(0xF0102034) : const Color(0xF0F6F9FD),
          strong: dark ? const Color(0xFA172B43) : const Color(0xFAFFFFFF),
          soft: dark ? const Color(0xFF1B3048) : const Color(0xFFE9EFF7),
          edge: dark ? const Color(0xFF31475E) : const Color(0xFFCAD6E4),
          shadow: dark ? const Color(0x18000000) : const Color(0x0C263E58));
    }
    if (a.themeStyle == 'nocturne') return SurfaceStyle._nocturne(a);
    return SurfaceStyle(
        dark: dark,
        spectrumStyle: a.spectrumStyle,
        glass: a.glass,
        radius: Design.px(a.radius),
        accent: a.accent(dark),
        accentText:
            dark ? Color.lerp(a.seed(), Colors.black, .80)! : Colors.white,
        seed: a.seed(),
        text: dark ? const Color(0xFFF2F6F5) : const Color(0xFF182D29),
        muted: dark ? const Color(0xFFADBDC4) : const Color(0xFF546C65),
        disabled: dark ? const Color(0xFF668081) : const Color(0xFF93A8A2),
        surface: dark ? const Color(0xA116232B) : const Color(0x8CFFFFFF),
        strong: dark ? const Color(0xCC192730) : const Color(0xCCFAFFFD),
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
  /// The design's 34 is only a starting value, written by the theme picker and
  /// the preview entry point when they switch a profile to Nocturne; mapping
  /// 0 → 34 here would make the left end of the slider a dead zone.
  factory SurfaceStyle._nocturne(Appearance a) {
    final accent = a.accent(true);
    return SurfaceStyle(
        nocturne: true,
        dark: true,
        glass: a.glass,
        spectrumStyle: a.spectrumStyle,
        radius: Design.dz(a.radius),
        accent: accent,
        accentText: Color.lerp(accent, Colors.black, .84)!,
        seed: a.seed(),
        text: const Color(0xFFEFF4F6),
        muted: const Color(0x8CE9F1F5),
        disabled: const Color(0x5E676B70),
        surface: const Color(0x14FFFFFF),
        strong: const Color(0xFF131619),
        soft: const Color(0x0FFFFFFF),
        edge: const Color(0x16FFFFFF),
        shadow: const Color(0xE6000000));
  }

  /// 820A 上逐帧离屏高斯会直接吃掉帧预算，暗夜按设计稿只用静态色阶，
  /// 不开实时模糊（设计稿 820A Budget 一节）。
  bool get liveBlur => glass && !technicalFrame && !nocturne;
  double get controlRadius =>
      technicalFrame ? (radius * .5).clamp(0, Design.px(16)) : radius * .64;
  Color get corner => dark ? const Color(0xFF829AB2) : const Color(0xFF738DA8);
  Color get dock => nocturne
      ? const Color(0xFF0B0D0E)
      : (dark ? const Color(0xFF0C1929) : const Color(0xFFF5F8FC));
  Color get background => nocturne
      ? Nocturne.background
      : technicalFrame
          ? (dark ? const Color(0xFF07111F) : const Color(0xFFE8EEF5))
          : (dark ? const Color(0xFF0E1920) : const Color(0xFFE1ECE7));

  /// Bottom glow tint for a card type. Only meaningful when [nocturne] is on;
  /// other styles keep one accent for the whole desktop.
  Color? cardGlow(String type) => nocturne ? Nocturne.glowOf(type) : null;

  BorderSide controlSide(bool selected) => BorderSide(
      color: selected
          ? (technicalFrame ? Color.lerp(edge, accent, .24)! : accent)
          : edge);
  OutlinedBorder controlShape({bool selected = false}) => technicalFrame
      ? TechnicalFrameBorder(
          radius: controlRadius,
          cornerLength: Design.px(10),
          cornerColor: selected ? accent : corner,
          side: controlSide(selected))
      : RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(controlRadius));
  ButtonStyle selectionStyle(bool selected) => OutlinedButton.styleFrom(
      shape: controlShape(selected: selected),
      backgroundColor: selected
          ? (technicalFrame ? accent.withValues(alpha: .11) : accent)
          : soft,
      foregroundColor: selected ? (technicalFrame ? accent : accentText) : text,
      side: technicalFrame
          ? controlSide(selected)
          : BorderSide(color: selected ? Colors.transparent : edge));

  /// Weak control-level border for dense rows such as climate mode and seat
  /// steps: a simple rounded outline so secondary cards keep the hierarchy.
  ButtonStyle weakSelectionStyle(bool selected) => OutlinedButton.styleFrom(
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(controlRadius)),
      backgroundColor:
          selected ? accent.withValues(alpha: .10) : Colors.transparent,
      foregroundColor: selected ? accent : text,
      side: BorderSide(
          color: selected
              ? accent.withValues(alpha: .55)
              : edge.withValues(alpha: .55)));
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
      other.nocturne == nocturne &&
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
  int get hashCode => Object.hash(dark, glass, technicalFrame, nocturne, radius,
      spectrumStyle, accent, accentText, seed, text, muted, disabled, surface,
      strong, soft, edge, shadow);
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
  final shape = s.controlShape();
  final button = ButtonStyle(
    shape: WidgetStatePropertyAll(shape),
    textStyle: WidgetStatePropertyAll(TextStyle(
        fontSize: Design.px(21),
        fontWeight: FontWeight.w400,
        height: 1.2,
        letterSpacing: 0)),
    minimumSize: WidgetStatePropertyAll(Size(0, Design.px(60))),
    padding:
        WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: Design.px(24))),
    visualDensity: VisualDensity.standard,
  );
  final colors = ColorScheme.fromSeed(
          seedColor: s.seed,
          brightness: s.dark ? Brightness.dark : Brightness.light)
      .copyWith(
          primary: s.accent,
          onPrimary: s.accentText,
          primaryContainer: s.soft,
          onPrimaryContainer: s.accent,
          surface: s.strong,
          onSurface: s.text,
          outline: s.edge);
  return ThemeData(
      useMaterial3: true,
      brightness: colors.brightness,
      colorScheme: colors,
      scaffoldBackgroundColor: s.background,
      textTheme: Typography.material2021()
          .black
          .apply(bodyColor: s.text, displayColor: s.text)
          .copyWith(
              bodyMedium: TextStyle(
                  fontSize: Design.px(20),
                  height: 1.2,
                  color: s.text,
                  letterSpacing: 0)),
      textButtonTheme: TextButtonThemeData(
          style: button.copyWith(
              foregroundColor: WidgetStatePropertyAll(s.muted))),
      outlinedButtonTheme: OutlinedButtonThemeData(
          style: button.copyWith(
              foregroundColor: WidgetStatePropertyAll(s.text),
              backgroundColor: WidgetStatePropertyAll(s.soft),
              side: WidgetStatePropertyAll(BorderSide(color: s.edge)))),
      filledButtonTheme: FilledButtonThemeData(
          style: button.copyWith(
              backgroundColor:
                  WidgetStatePropertyAll(s.technicalFrame ? s.soft : s.accent),
              foregroundColor: WidgetStatePropertyAll(
                  s.technicalFrame ? s.text : s.accentText))),
      inputDecorationTheme: InputDecorationTheme(
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
