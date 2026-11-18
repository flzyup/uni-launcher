import 'package:flutter/material.dart';
import 'page_motion.dart';

class AccentPreset {
  final String id, name;
  final Color seed, dark, light;

  /// 设置页「主题配色」那颗色球的三段渐变（sim board 09 的
  /// `linear-gradient(180deg, top, seed 55%, bottom)`）。
  ///
  /// 三段值在设计稿里是**逐色标定**的，不是从 seed 插值出来的：
  /// 往白/黑插值会连带把饱和度稀释掉，青屿就成了一颗发灰的薄荷球。
  /// 这里直接抄 board 09 的字面值，`seed` 正好是它的中间段。
  final Color dotTop, dotBottom;
  const AccentPreset(this.id, this.name, this.seed, this.dark, this.light,
      {required this.dotTop, required this.dotBottom});
}

const accentPresets = [
  AccentPreset('mint', '青屿', Color(0xFF31B9A2), Color(0xFF71E4CE),
      Color(0xFF087568),
      dotTop: Color(0xFF6FF0D4), dotBottom: Color(0xFF1F937D)),
  AccentPreset('blue', '冰川', Color(0xFF4B92DE), Color(0xFF8FC8FF),
      Color(0xFF245F9E),
      dotTop: Color(0xFF8CC6F8), dotBottom: Color(0xFF346FB4)),
  AccentPreset('violet', '鸢尾', Color(0xFF9570D5), Color(0xFFCEB5FF),
      Color(0xFF7550A4),
      dotTop: Color(0xFFB99AEB), dotBottom: Color(0xFF7352B0)),
  AccentPreset('amber', '琥珀', Color(0xFFD49A47), Color(0xFFF4CF8A),
      Color(0xFF8B5E1E),
      dotTop: Color(0xFFF2C877), dotBottom: Color(0xFFAE7A2E)),
  AccentPreset('rose', '玫瑰', Color(0xFFCB748A), Color(0xFFF4B1C4),
      Color(0xFF98465F),
      dotTop: Color(0xFFEC9DB2), dotBottom: Color(0xFFA8566E)),
];

/// 「自定义」色球的顺时针彩虹，起点对齐 sim 的 `conic-gradient(from 210deg)`：
/// 粉 → 琥珀 → 当前强调色 → 青 → 紫 → 回到粉。第三段是**活的**，
/// 换什么色相都能在球上看见自己选的那一档。
List<Color> customDotColors(Color accent) => [
      const Color(0xFFFF5FA8),
      const Color(0xFFFFB057),
      accent,
      const Color(0xFF6FD3FF),
      const Color(0xFF8E6CFF),
      const Color(0xFFFF5FA8),
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
  static const themeStyles = ['classic', 'blueGlass', 'nocturne'];
  static const spectrumStyles = ['bars', 'segments', 'mirror', 'outline'];
  static const dockSizes = ['small', 'medium', 'large', 'extraLarge'];
  static const dockLayouts = ['full', 'floating'];
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
  final String dockSize;
  final String dockLayout;
  final double radius;
  final double? wallpaperLuminance;
  final bool glass;
  final bool wallpaperOverlay;
  final bool dockMusicProgressBackground;

  /// 底栏音乐的「烟雾流体」进度：shader 画的三层刀口 + 拖影。
  ///
  /// 以前它跟着皮肤走（只有暗夜用），没有开关。现在单独一颗：想关掉省那点帧
  /// 或者嫌它花，直接关；关掉后回落到原来那条细渐变进度。
  final bool dockMusicFluid;
  final bool dockMusicVisual;

  /// 开机落在第几页：`-1` 表示「上次停留的那一页」，其余是 0 起的页索引。
  ///
  /// 这条设置同时决定了一件事：导航卡在别的页上时，桌面一打开就不会去
  /// 碰那张卡，也就不会把导航应用拉起来（`EmbeddedNavigationCard` 只在
  /// 所在页可见时才向原生发 `create`）。所以「不自动启动高德」是靠
  /// 「开机停在没导航卡的那页」实现的，见 docs/AMAP_TRAFFIC_LIGHT_CARD.md 附近。
  final int bootPage;
  const Appearance(
      {this.desktopName = defaultDesktopName,
      this.mode = 'system',
      this.themeStyle = 'blueGlass',
      this.palette = 'mint',
      this.custom = '#38A4A0',
      this.radius = 0,
      this.glass = false,
      this.wallpaperOverlay = false,
      this.dockMusicProgressBackground = true,
      this.dockMusicFluid = true,
      this.dockMusicVisual = true,
      this.bootPage = -1,
      this.pageTransition = 'slide',
      this.spectrumStyle = 'segments',
      this.wallpaper = 'gradient',
      this.wallpaperPath = '',
      this.dockSize = 'large',
      this.dockLayout = 'floating',
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
        wallpaperOverlay: json['wallpaperOverlay'] == true,
        dockMusicProgressBackground: json['dockMusicProgressBackground'] is bool
            ? json['dockMusicProgressBackground'] as bool
            : true,
        dockMusicFluid: json['dockMusicFluid'] is bool
            ? json['dockMusicFluid'] as bool
            : true,
        dockMusicVisual: json['dockMusicVisual'] is bool
            ? json['dockMusicVisual'] as bool
            : true,
        // 非法值一律回落到「上次停留」，而不是第 1 页：宁可保持默认语义，
        // 也不要把一个读不懂的数字当成用户的明确选择。
        bootPage: json['bootPage'] is num
            ? (json['bootPage'] as num).toInt().clamp(-1, 19)
            : -1,
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
        dockSize:
            dockSizes.contains(json['dockSize']) ? json['dockSize'] : 'large',
        dockLayout: dockLayouts.contains(json['dockLayout'])
            ? json['dockLayout'] as String
            : 'floating',
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
          bool? wallpaperOverlay,
          bool? dockMusicProgressBackground,
          bool? dockMusicFluid,
          bool? dockMusicVisual,
          String? pageTransition,
          String? spectrumStyle,
          String? wallpaper,
          String? wallpaperPath,
          String? dockSize,
          String? dockLayout,
          int? bootPage,
          double? wallpaperLuminance}) =>
      Appearance(
          desktopName: normalizeDesktopName(desktopName ?? this.desktopName),
          themeStyle: themeStyle ?? this.themeStyle,
          mode: mode ?? this.mode,
          palette: palette ?? this.palette,
          custom: custom ?? this.custom,
          radius: (radius ?? this.radius).clamp(0, 40),
          glass: glass ?? this.glass,
          wallpaperOverlay: wallpaperOverlay ?? this.wallpaperOverlay,
          dockMusicProgressBackground:
              dockMusicProgressBackground ?? this.dockMusicProgressBackground,
          dockMusicFluid: dockMusicFluid ?? this.dockMusicFluid,
          dockMusicVisual: dockMusicVisual ?? this.dockMusicVisual,
          bootPage: (bootPage ?? this.bootPage).clamp(-1, 19),
          pageTransition: pageTransition ?? this.pageTransition,
          spectrumStyle: spectrumStyles.contains(spectrumStyle)
              ? spectrumStyle!
              : this.spectrumStyle,
          wallpaper: wallpaper ?? this.wallpaper,
          wallpaperPath: wallpaperPath ?? this.wallpaperPath,
          dockSize: dockSizes.contains(dockSize) ? dockSize! : this.dockSize,
          dockLayout:
              dockLayouts.contains(dockLayout) ? dockLayout! : this.dockLayout,
          wallpaperLuminance: wallpaperLuminance ?? this.wallpaperLuminance);
  Map<String, dynamic> toJson() => {
        'desktopName': desktopName,
        'themeStyle': themeStyle,
        'mode': mode,
        'palette': palette,
        'custom': custom,
        'radius': radius.round(),
        'glass': glass,
        'wallpaperOverlay': wallpaperOverlay,
        'dockMusicProgressBackground': dockMusicProgressBackground,
        'dockMusicFluid': dockMusicFluid,
        'dockMusicVisual': dockMusicVisual,
        'bootPage': bootPage,
        'pageTransition': pageTransition,
        'spectrumStyle': spectrumStyle,
        'wallpaper': wallpaper,
        'dockSize': dockSize,
        'dockLayout': dockLayout,
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

  /// 暗夜是纯深色体系，不跟随明暗与壁纸亮度；否则浅色壁纸会把卡片拉成亮面。
  bool isDark(bool systemDark) =>
      themeStyle == 'nocturne' ||
      mode == 'dark' ||
      ({'smart', 'system'}.contains(mode) && systemDark);
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

  /// 墨色强调色的本体。
  ///
  /// 预设直接读表（board 09 逐色标定）。**自定义必须按 HSL 算**，不能再用
  /// `Color.lerp(seed, white, .42)`：以正红 `#D42A2A` 为例，往白里插 42% 会
  /// 得到 `#E68383`——明度从 .50 顶到 .71、HSV 彩度从 .80 掉到 .43，屏幕上
  /// 就是一块浅粉，跟稿子里那一档饱和的红完全不是一回事（HSL 的 s 看着只差
  /// .01，所以不能拿它当判据）。
  ///
  /// sim 的自定义色相是 `hslTriple(h,62,56)` 一套四件套（见 simulator.html
  /// `:7156`），这里取同一套色相与饱和度，只按明暗态调明度——暗底对齐预设
  /// `dark`（#71E4CE 量级，l≈.66），浅底对齐 `light`（l≈.26）。
  Color accent(bool dark) {
    if (palette == 'custom') {
      final h = HSLColor.fromColor(seed()).hue;
      return HSLColor.fromAHSL(1, h, dark ? .68 : .78, dark ? .66 : .26)
          .toColor();
    }
    final p = accentPresets.firstWhere((p) => p.id == palette);
    return dark ? p.dark : p.light;
  }
}
