import 'dart:io';
import 'package:flutter/material.dart';
import '../model/appearance.dart';
import '../theme/launcher_theme.dart';

class SceneBackground extends StatelessWidget {
  final Widget child;
  final Appearance? appearance;
  final int wallpaperCacheWidth;
  final bool forceOverlay;
  final bool protectText;
  const SceneBackground(
      {super.key,
      required this.child,
      this.appearance,
      this.wallpaperCacheWidth = 1920,
      this.forceOverlay = false,
      this.protectText = false});
  @override
  Widget build(BuildContext context) {
    final s = SurfaceStyle.of(context);
    final wallpaper = appearance;
    final hasWallpaper = wallpaper != null && wallpaper.wallpaper != 'gradient';
    // Keep the content at one stable parent/slot. Wrapping it in a new
    // decoration for settings (or switching wallpaper/theme) would dispose
    // the live map and release its display, bringing AMap onto the main screen.
    final showOverlay = !hasWallpaper ||
        wallpaper.wallpaperOverlay ||
        (forceOverlay && !s.liquidGlass);
    return Stack(fit: StackFit.expand, children: [
      if (s.technicalFrame || s.liquidGlass || s.nocturne)
        ColoredBox(color: s.background)
      else
        const SizedBox.expand(),
      if (hasWallpaper)
        WallpaperImage(appearance: wallpaper, cacheWidth: wallpaperCacheWidth)
      else
        const SizedBox.expand(),
      if (s.nocturne)
        _nocturneBackdrop(s, hasWallpaper, showOverlay)
      else if ((s.technicalFrame || s.liquidGlass) && !hasWallpaper)
        _technicalGradient(s)
      else if ((s.technicalFrame || s.liquidGlass) && showOverlay)
        _technicalWallpaperOverlay(s)
      else if (s.technicalFrame || s.liquidGlass)
        const SizedBox.expand()
      else if (showOverlay)
        _classicBackdrop(s, hasWallpaper)
      else
        const SizedBox.expand(),
      // Text outside cards (clock/status and settings heading) must remain
      // readable when a fixed light/dark mode is paired with the opposite photo.
      //
      // 暗夜不画这条（2026-11-18，用户要求）：它已经把整屏压过一层 40% 黑
      // （见 _nocturneBackdrop），再叠一条 96% 不透明的顶部黑带，壁纸基本就
      // 看不见了。暗夜要的是「看到后面的桌面」，不是一条黑边。
      // 液态玻璃本来就不画（走 WallpaperInk 的光晕）。
      //
      // 经典**深色**现在同样不画（2026-11-19，用户报「经典深色顶栏被一块黑
      // 遮挡」）：它压在照片上时也整屏铺了一层 70% 深蓝（见 _classicBackdrop
      // 的 0xB30A151C），白字本来就压得住，那条 96% 黑带只剩副作用——顶栏
      // 一整块发黑，跟暗夜当初一模一样。浅色保留：深色照片 + 深色字时那张
      // 浅色带仍然负担可读性，而它本身不刺眼。
      if (hasWallpaper &&
          !s.liquidGlass &&
          !s.nocturne &&
          !s.dark &&
          (protectText || forceOverlay))
        Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: MediaQuery.sizeOf(context).width /
                1920 *
                (forceOverlay ? 220 : 96),
            child: IgnorePointer(
                child: DecoratedBox(
                    key: const ValueKey('scene-text-contrast-scrim'),
                    decoration: BoxDecoration(
                        gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            stops: const [
                          0,
                          .75,
                          1
                        ],
                            colors: [
                          s.background.withValues(alpha: .96),
                          s.background.withValues(alpha: .94),
                          s.background.withValues(alpha: 0)
                        ])))))
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
    // 浅色形态：一层压暗都不画。照片原样当底，任何黑色都会把「透明玻璃」
    // 变成「灰玻璃」，也违背「我要看到后面的桌面」这个诉求。
    if (!s.dark) return const SizedBox.shrink();
    if (hasWallpaper) {
      // 暗夜 + 壁纸：
      //  · 压暗从 60% 黑收到 40% —— 原来那层把照片吃得只剩一点灰影，选壁纸等于
      //    选了个黑底（用户 2026-11-13 实车截图就是这个观感）；
      //  · 「叠加主题渐变」这个开关以前在暗夜完全没读，拨了没反应。现在打开时在
      //    照片上再叠一层主题色渐变（左上亮、右下暗，跟 blueGlass 那条同一套做法），
      //    让照片跟主题同调；关掉就是纯照片 + 压暗。
      return Stack(fit: StackFit.expand, children: [
        const DecoratedBox(decoration: BoxDecoration(color: Nocturne.scrim)),
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
                    Nocturne.scrimDeep
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

/// Bare header text adapts to the wallpaper, independently of card light/dark
/// mode. A small glyph halo handles photo detail without painting a full-width
/// white/dark band over the wallpaper.
class WallpaperInk extends StatelessWidget {
  final Appearance appearance;
  final Widget child;
  const WallpaperInk(
      {super.key, required this.appearance, required this.child});
  @override
  Widget build(BuildContext context) {
    final s = SurfaceStyle.of(context);
    if (!s.liquidGlass || appearance.wallpaper == 'gradient') return child;
    final dark = appearance.backgroundIsDark(s.dark);
    final ink = SurfaceStyle.from(
        appearance.copyWith(mode: dark ? 'dark' : 'light'), dark,
        lowPower: s.lowPower);
    return Theme(
        data: launcherTheme(ink),
        child: DefaultTextStyle.merge(
            style: TextStyle(color: ink.text, shadows: [
              Shadow(
                  color: (dark ? Colors.black : Colors.white)
                      .withValues(alpha: .65),
                  blurRadius: 3)
            ]),
            child: IconTheme.merge(
                data: IconThemeData(color: ink.text), child: child)));
  }
}
