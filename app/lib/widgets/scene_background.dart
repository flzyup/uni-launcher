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
        _nocturneBackdrop(s, hasWallpaper, showOverlay)
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

  /// 暗夜画布：纯黑铺底 + 左上强调色、右下暖色的两处环境光，
  /// 与 design/desktop-lynk05.html 的画板底一致。有壁纸时只做压暗。
  ///
  /// 画板上那层 80px 的淡网格**不再画**：1920 宽下一屏 24 根线，把留白切成
  /// 一格一格，卡片压上去像贴在作业本上；而且它和「无边界黑」的设计意图
  /// 相反。暗角已经够给出距离感。
  Widget _nocturneBackdrop(SurfaceStyle s, bool hasWallpaper, bool overlay) {
    if (hasWallpaper) {
      // 暗夜 + 壁纸：
      //  · 压暗从 60% 黑收到 40% —— 原来那层把照片吃得只剩一点灰影，选壁纸等于
      //    选了个黑底（用户 2026-11-13 实车截图就是这个观感）；
      //  · 「叠加主题渐变」这个开关以前在暗夜完全没读，拨了没反应。现在打开时在
      //    照片上再叠一层主题色渐变（左上亮、右下暗，跟 blueGlass 那条同一套做法），
      //    让照片跟主题同调；关掉就是纯照片 + 压暗。
      return Stack(fit: StackFit.expand, children: [
        const DecoratedBox(decoration: BoxDecoration(color: Color(0x66050506))),
        if (overlay)
          DecoratedBox(
              key: const ValueKey('nocturne-wallpaper-overlay'),
              decoration: BoxDecoration(
                  gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      stops: const [
                    0,
                    .58,
                    1
                  ],
                      colors: [
                    s.accent.withValues(alpha: .22),
                    s.accent.withValues(alpha: .04),
                    const Color(0x8C050506)
                  ]))),
      ]);
    }
    return Stack(fit: StackFit.expand, children: [
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
              stops: const [
            0,
            .63,
            1
          ],
              colors: [
            Color.lerp(s.background, s.seed, s.dark ? .42 : .32)!
                .withValues(alpha: s.dark ? .52 : .38),
            s.background.withValues(alpha: s.dark ? .25 : .18),
            Color.lerp(s.background, s.seed, s.dark ? .28 : .22)!
                .withValues(alpha: s.dark ? .42 : .30),
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
