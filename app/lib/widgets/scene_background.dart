import 'dart:io';
import 'package:flutter/material.dart';
import '../model/appearance.dart';
import '../theme/design_tokens.dart';
import '../theme/launcher_theme.dart';

class SceneBackground extends StatelessWidget {
  final Widget child;
  final Appearance? appearance;
  final int wallpaperCacheWidth;
  final bool forceOverlay;
  const SceneBackground(
      {super.key,
      required this.child,
      this.appearance,
      this.wallpaperCacheWidth = 1920,
      this.forceOverlay = false});
  @override
  Widget build(BuildContext context) {
    final s = SurfaceStyle.of(context);
    final wallpaper = appearance;
    final hasWallpaper = wallpaper != null && wallpaper.wallpaper != 'gradient';
    // Keep the content at one stable parent/slot. Wrapping it in a new
    // decoration for settings (or switching wallpaper/theme) would dispose
    // the live map and release its display, bringing AMap onto the main screen.
    final showOverlay =
        !hasWallpaper || wallpaper.wallpaperOverlay || forceOverlay;
    return Stack(fit: StackFit.expand, children: [
      if (s.technicalFrame || s.nocturne)
        ColoredBox(color: s.background)
      else
        const SizedBox.expand(),
      if (hasWallpaper)
        WallpaperImage(appearance: wallpaper, cacheWidth: wallpaperCacheWidth)
      else
        const SizedBox.expand(),
      if (s.nocturne)
        _nocturneBackdrop(s, hasWallpaper)
      else if (s.technicalFrame && !hasWallpaper)
        _technicalGradient(s)
      else if (s.technicalFrame && showOverlay)
        _technicalWallpaperOverlay(s)
      else if (s.technicalFrame)
        const SizedBox.expand()
      else if (showOverlay)
        _classicBackdrop(s, hasWallpaper)
      else
        const SizedBox.expand(),
      KeyedSubtree(key: const ValueKey('scene-content'), child: child),
    ]);
  }

  /// 暗夜画布：纯黑铺底 + 80px 网格 + 左上强调色、右下暖色的两处环境光，
  /// 与 design/desktop-lynk05.html 的画板底一致。有壁纸时只做压暗。
  Widget _nocturneBackdrop(SurfaceStyle s, bool hasWallpaper) {
    if (hasWallpaper) {
      return const DecoratedBox(
          decoration: BoxDecoration(color: Color(0x99050506)));
    }
    return Stack(fit: StackFit.expand, children: [
      const RepaintBoundary(child: CustomPaint(painter: _NightGridPainter())),
      DecoratedBox(
          decoration: BoxDecoration(
              gradient: RadialGradient(
                  center: const Alignment(-.72, -.92),
                  radius: 1.1,
                  colors: [
            s.accent.withValues(alpha: .09),
            s.accent.withValues(alpha: 0)
          ]))),
      const DecoratedBox(
          decoration: BoxDecoration(
              gradient: RadialGradient(
                  center: Alignment(.9, 1),
                  radius: 1,
                  colors: [Color(0x17FFB057), Color(0x00FFB057)]))),
      const DecoratedBox(
          decoration: BoxDecoration(
              gradient: RadialGradient(
                  center: Alignment.center,
                  radius: .85,
                  stops: [.52, 1],
                  colors: [Color(0x00000000), Color(0x4D000000)]))),
    ]);
  }

  Widget _technicalGradient(SurfaceStyle s) => DecoratedBox(
      key: const ValueKey('technical-theme-gradient'),
      decoration: BoxDecoration(
          gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
            Color.lerp(s.background, s.seed, s.dark ? .22 : .12)!,
            s.background,
            Color.lerp(s.background, s.seed, s.dark ? .12 : .08)!,
          ])));

  Widget _technicalWallpaperOverlay(SurfaceStyle s) => DecoratedBox(
      key: const ValueKey('technical-wallpaper-overlay'),
      decoration: BoxDecoration(
          gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              stops: const [0, .63, 1],
              colors: s.dark
                  ? const [
                      Color(0x590A151C),
                      Color(0x331D3038),
                      Color(0x420E2029)
                    ]
                  : const [
                      Color(0x29E1ECE7),
                      Color(0x24D4E1E0),
                      Color(0x2DE9EEF0)
                    ])));

  Widget _classicBackdrop(SurfaceStyle s, bool hasWallpaper) => DecoratedBox(
      decoration: BoxDecoration(
          gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              stops: const [0, .63, 1],
              colors: !hasWallpaper
                  ? (s.dark
                      ? const [
                          Color(0xFF0E1920),
                          Color(0xFF273E46),
                          Color(0xFF172A34)
                        ]
                      : const [
                          Color(0xFFE1ECE7),
                          Color(0xFFD4E1E0),
                          Color(0xFFE9EEF0)
                        ])
                  : (s.dark
                      ? const [
                          Color(0xB30A151C),
                          Color(0x7A1D3038),
                          Color(0xA30E2029)
                        ]
                      : const [
                          Color(0x70E1ECE7),
                          Color(0x66D4E1E0),
                          Color(0x78E9EEF0)
                        ]))),
      child: DecoratedBox(
          decoration: BoxDecoration(
              gradient: RadialGradient(
                  center: s.dark
                      ? const Alignment(-.76, -.92)
                      : const Alignment(-.84, -.64),
                  radius: .9,
                  colors: [
                s.seed.withValues(alpha: s.dark ? .20 : .16),
                s.seed.withValues(alpha: 0)
              ])),
          child: DecoratedBox(
              decoration: BoxDecoration(
                  gradient: RadialGradient(
                      center: const Alignment(.7, .36),
                      radius: .8,
                      colors: [
                    (s.dark ? const Color(0xFF79A2B7) : const Color(0xFF9FC0D5))
                        .withValues(alpha: s.dark ? .24 : .42),
                    const Color(0x0079A2B7)
                  ])),
              child: const SizedBox.expand())));
}

/// 80 设计像素的极淡网格：只是让纯黑有一点点距离感，不参与交互也不重绘。
class _NightGridPainter extends CustomPainter {
  const _NightGridPainter();
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0x0DFFFFFF)
      ..strokeWidth = 1;
    final step = Design.px(80);
    if (step <= 0) return;
    for (var x = 0.0; x <= size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (var y = 0.0; y <= size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _NightGridPainter oldDelegate) => false;
}

class WallpaperImage extends StatelessWidget {
  final Appearance appearance;
  final BoxFit fit;
  final int cacheWidth;
  const WallpaperImage(
      {super.key,
      required this.appearance,
      this.fit = BoxFit.cover,
      this.cacheWidth = 1920});

  @override
  Widget build(BuildContext context) {
    final preset = appearance.wallpaperPreset;
    if (preset?.asset != null) {
      // cacheWidth already matches the panel width, so this is a 1:1 blit: mipmaps
      // cost VRAM and upload time without changing a single pixel.
      return Image.asset(preset!.asset!,
          fit: fit, cacheWidth: cacheWidth, filterQuality: FilterQuality.low);
    }
    if (appearance.wallpaper == 'custom' &&
        appearance.wallpaperPath.isNotEmpty) {
      return Image.file(File(appearance.wallpaperPath),
          key: ValueKey(appearance.wallpaperPath),
          fit: fit,
          cacheWidth: cacheWidth,
          filterQuality: FilterQuality.low,
          gaplessPlayback: true,
          errorBuilder: (_, __, ___) => const SizedBox.expand());
    }
    return const SizedBox.expand();
  }
}
