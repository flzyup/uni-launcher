import 'package:flutter/material.dart';
import '../model/appearance.dart';
import 'design_tokens.dart';
import 'technical_frame.dart';

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
    if (a.themeStyle == 'nocturne') {
      // 暗夜：纯黑画布 + 一卡一色玻璃。色值取自 design/desktop-lynk05.html
      // 的 Nocturne 色板（--bg #050607、--ink #EFF4F6、--mint #3BE2C0、
      // --hair rgba(255,255,255,.08)），固定深色，不跟随明暗与壁纸亮度。
      final mint = a.palette == 'mint';
      return SurfaceStyle(
          dark: true,
          nocturne: true,
          glass: a.glass,
          technicalFrame: false,
          spectrumStyle: a.spectrumStyle,
          radius: Design.px(a.radius),
          accent: mint ? const Color(0xFF3BE2C0) : a.accent(true),
          accentText: const Color(0xFF04110E),
          seed: mint ? const Color(0xFF3BE2C0) : a.seed(),
          text: const Color(0xFFEFF4F6),
          muted: const Color(0xFF98A1A4),
          disabled: const Color(0xFF60686B),
          surface: const Color(0xE60F1112),
          strong: const Color(0xF5141617),
          soft: const Color(0x12FFFFFF),
          edge: const Color(0x17FFFFFF),
          shadow: const Color(0x66000000));
    }
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
  bool get liveBlur => glass && !technicalFrame;
  double get controlRadius =>
      technicalFrame ? (radius * .5).clamp(0, Design.px(16)) : radius * .64;
  Color get corner => dark ? const Color(0xFF829AB2) : const Color(0xFF738DA8);
  Color get dock => nocturne
      ? const Color(0xFF0A0B0C)
      : (dark ? const Color(0xFF0C1929) : const Color(0xFFF5F8FC));
  Color get background => nocturne
      ? const Color(0xFF050607)
      : technicalFrame
          ? (dark ? const Color(0xFF07111F) : const Color(0xFFE8EEF5))
          : (dark ? const Color(0xFF0E1920) : const Color(0xFFE1ECE7));
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
