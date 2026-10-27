import 'dart:io';
import 'package:flutter/material.dart';
import '../model/appearance.dart';
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
    final showOverlay = !hasWallpaper || forceOverlay;
    return Stack(fit: StackFit.expand, children: [
      if (s.technicalFrame)
        ColoredBox(color: s.background)
      else
        const SizedBox.expand(),
      if (hasWallpaper)
        WallpaperImage(appearance: wallpaper, cacheWidth: wallpaperCacheWidth)
      else
        const SizedBox.expand(),
      if (s.technicalFrame && !hasWallpaper)
        _technicalGradient(s)
      else if (s.technicalFrame)
        ColoredBox(
            color: forceOverlay
                ? s.background.withValues(alpha: .9)
                : Colors.transparent)
      else if (showOverlay)
        _classicBackdrop(s, hasWallpaper)
      else
        const SizedBox.expand(),
      KeyedSubtree(key: const ValueKey('scene-content'), child: child),
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
      return Image.asset(preset!.asset!,
          fit: fit,
          cacheWidth: cacheWidth,
          filterQuality: FilterQuality.medium);
    }
    if (appearance.wallpaper == 'custom' &&
        appearance.wallpaperPath.isNotEmpty) {
      return Image.file(File(appearance.wallpaperPath),
          key: ValueKey(appearance.wallpaperPath),
          fit: fit,
          cacheWidth: cacheWidth,
          filterQuality: FilterQuality.medium,
          gaplessPlayback: true,
          errorBuilder: (_, __, ___) => const SizedBox.expand());
    }
    return const SizedBox.expand();
  }
}
