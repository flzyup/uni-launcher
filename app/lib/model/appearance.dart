import 'package:flutter/material.dart';
import 'page_motion.dart';

class AccentPreset {
  final String id, name;
  final Color seed, dark, light;
  const AccentPreset(this.id, this.name, this.seed, this.dark, this.light);
}

const accentPresets = [
  AccentPreset(
      'mint', '青屿', Color(0xFF31B9A2), Color(0xFF71E4CE), Color(0xFF087568)),
  AccentPreset(
      'blue', '冰川', Color(0xFF4B92DE), Color(0xFF8FC8FF), Color(0xFF245F9E)),
  AccentPreset(
      'violet', '鸢尾', Color(0xFF9570D5), Color(0xFFCEB5FF), Color(0xFF7550A4)),
  AccentPreset(
      'amber', '琥珀', Color(0xFFD49A47), Color(0xFFF4CF8A), Color(0xFF8B5E1E)),
  AccentPreset(
      'rose', '玫瑰', Color(0xFFCB748A), Color(0xFFF4B1C4), Color(0xFF98465F)),
];

class WallpaperPreset {
  final String id, name;
  final String? asset;
  final bool? dark;
  const WallpaperPreset(this.id, this.name, [this.asset, this.dark]);
}

const wallpaperPresets = <WallpaperPreset>[
  WallpaperPreset('gradient', '主题渐变'),
  WallpaperPreset(
      'coastal', '海岸晨雾', 'assets/wallpapers/coastal-mist.jpg', false),
  WallpaperPreset(
      'graphite', '石墨夜色', 'assets/wallpapers/graphite-night.jpg', true),
  WallpaperPreset('dawn', '暖曦沙丘', 'assets/wallpapers/warm-dawn.jpg', false),
  WallpaperPreset('neon', '霓光地平', 'assets/wallpapers/neon-horizon.jpg', true),
  WallpaperPreset(
      'precision', '精密曲面', 'assets/wallpapers/precision-grid.jpg', false),
  WallpaperPreset(
      'terrain', '数字地形', 'assets/wallpapers/digital-terrain.jpg', true),
];

class Appearance {
  static const themeStyles = ['classic', 'blueGlass'];
  static const spectrumStyles = ['bars', 'segments', 'mirror', 'outline'];
  static const defaultDesktopName = 'LYNK & CO / 05';
  static String normalizeDesktopName(Object? value) {
    final name =
        value is String ? value.replaceAll(RegExp(r'[\r\n]'), ' ').trim() : '';
    return name.isEmpty
        ? defaultDesktopName
        : String.fromCharCodes(name.runes.take(24));
  }

  final String mode,
      themeStyle,
      palette,
      custom,
      pageTransition,
      spectrumStyle,
      desktopName,
      wallpaper,
      wallpaperPath;
  final double radius;
  final double? wallpaperLuminance;
  final bool glass;
  const Appearance(
      {this.desktopName = defaultDesktopName,
      this.mode = 'system',
      this.themeStyle = 'blueGlass',
      this.palette = 'mint',
      this.custom = '#38A4A0',
      this.radius = 0,
      this.glass = false,
      this.pageTransition = 'slide',
      this.spectrumStyle = 'segments',
      this.wallpaper = 'gradient',
      this.wallpaperPath = '',
      this.wallpaperLuminance});
  factory Appearance.fromJson(Map<String, dynamic> json) => Appearance(
        desktopName: normalizeDesktopName(json['desktopName']),
        themeStyle: themeStyles.contains(json['themeStyle'])
            ? json['themeStyle']
            : 'classic',
        mode: ['smart', 'system', 'light', 'dark'].contains(json['mode'])
            ? json['mode']
            : 'system',
        palette: [...accentPresets.map((p) => p.id), 'custom']
                .contains(json['palette'])
            ? json['palette']
            : 'mint',
        custom: RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch('${json['custom']}')
            ? json['custom']
            : '#38A4A0',
        radius: json['radius'] is num
            ? (json['radius'] as num).toDouble().clamp(0, 40)
            : 28,
        glass: json['glass'] == true,
        pageTransition: normalizePageEffect(json['pageTransition']),
        spectrumStyle: spectrumStyles.contains(json['spectrumStyle'])
            ? json['spectrumStyle']
            : 'bars',
        wallpaper: [...wallpaperPresets.map((item) => item.id), 'custom']
                .contains(json['wallpaper'])
            ? json['wallpaper']
            : 'gradient',
        wallpaperPath: json['wallpaperPath'] is String &&
                (json['wallpaperPath'] as String).length <= 1024
            ? json['wallpaperPath']
            : '',
        wallpaperLuminance: json['wallpaperLuminance'] is num
            ? (json['wallpaperLuminance'] as num).toDouble().clamp(0, 1)
            : null,
      );
  Appearance copyWith(
          {String? desktopName,
          String? themeStyle,
          String? mode,
          String? palette,
          String? custom,
          double? radius,
          bool? glass,
          String? pageTransition,
          String? spectrumStyle,
          String? wallpaper,
          String? wallpaperPath,
          double? wallpaperLuminance}) =>
      Appearance(
          desktopName: normalizeDesktopName(desktopName ?? this.desktopName),
          themeStyle: themeStyle ?? this.themeStyle,
          mode: mode ?? this.mode,
          palette: palette ?? this.palette,
          custom: custom ?? this.custom,
          radius: (radius ?? this.radius).clamp(0, 40),
          glass: glass ?? this.glass,
          pageTransition: pageTransition ?? this.pageTransition,
          spectrumStyle: spectrumStyles.contains(spectrumStyle)
              ? spectrumStyle!
              : this.spectrumStyle,
          wallpaper: wallpaper ?? this.wallpaper,
          wallpaperPath: wallpaperPath ?? this.wallpaperPath,
          wallpaperLuminance: wallpaperLuminance ?? this.wallpaperLuminance);
  Map<String, dynamic> toJson() => {
        'desktopName': desktopName,
        'themeStyle': themeStyle,
        'mode': mode,
        'palette': palette,
        'custom': custom,
        'radius': radius.round(),
        'glass': glass,
        'pageTransition': pageTransition,
        'spectrumStyle': spectrumStyle,
        'wallpaper': wallpaper,
        if (wallpaperPath.isNotEmpty) 'wallpaperPath': wallpaperPath,
        if (wallpaperLuminance != null)
          'wallpaperLuminance': wallpaperLuminance,
      };

  WallpaperPreset? get wallpaperPreset {
    for (final preset in wallpaperPresets) {
      if (preset.id == wallpaper) return preset;
    }
    return null;
  }

  bool get usesBackdropBlur => glass && themeStyle != 'blueGlass';

  bool isDark(bool systemDark) =>
      mode == 'dark' || ({'smart', 'system'}.contains(mode) && systemDark);
  bool backgroundIsDark(bool systemDark) {
    if (wallpaper == 'gradient') return isDark(systemDark);
    if (wallpaper == 'custom') {
      return wallpaperLuminance == null
          ? isDark(systemDark)
          : wallpaperLuminance! < .48;
    }
    return wallpaperPreset?.dark ?? isDark(systemDark);
  }

  Color seed() => palette == 'custom'
      ? Color(0xFF000000 | int.parse(custom.substring(1), radix: 16))
      : accentPresets.firstWhere((p) => p.id == palette).seed;
  Color accent(bool dark) {
    if (palette == 'custom')
      return Color.lerp(seed(), dark ? Colors.white : Colors.black, .42)!;
    final p = accentPresets.firstWhere((p) => p.id == palette);
    return dark ? p.dark : p.light;
  }
}
