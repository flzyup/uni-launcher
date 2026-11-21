import 'package:flutter/material.dart';

/// 全局总开关：卡底 66px 压暗带。一处生效。
///
/// 设计稿 `.card` 右上角还画过一道 45° 弧线 + 端点小圆（`.tick`），实车上去掉了：
/// 它纯装饰，摆在卡片角落却像一个可点的「关闭」控件。要找回来看
/// `git show 68e2dcc:app/lib/widgets/glass_surface.dart` 里的 `_CornerTickPainter`。
const bool kCardBottomShade = true;

/// 皮肤标识。`nocturne` 这个字符串 ID 保留不动（老配置无损），
/// 但它代表的外观现在是 eclipse（日蚀）这一套。
enum LauncherSkin { classic, blueGlass, eclipse }

LauncherSkin launcherSkinOf(String themeStyle) => switch (themeStyle) {
      'nocturne' => LauncherSkin.eclipse,
      'blueGlass' => LauncherSkin.blueGlass,
      _ => LauncherSkin.classic,
    };

/// 三套皮肤各自的那一小撮「新元素配色」。
///
/// 为什么要有这张表：布局是全局共用的（顶栏、页点、卡片基座、底栏胶囊三套皮肤
/// 结构完全一样），但每个新元素都得在每套皮肤、每个明暗态下有一个色值。
/// 缺一个就会出现「某皮肤下元素消失」。所以这里**所有字段 required、不给默认值**，
/// 漏填直接编译不过，而不是运行时变成一块灰。
///
/// 口径：classic 与 blueGlass 有明暗两态，eclipse 只有暗态（设计稿就没有浅色）。
class SkinMaterial {
  /// 卡底压暗带的高度占比，0 表示不要。
  ///
  /// 设计稿是 66px 渐变到黑 34%，用来把「底部光晕」压住、让大字读数更清楚。
  /// classic 是浅底，压暗会变脏，所以给 0；blueGlass 深色给一点点。
  final double cardShade;

  /// 顶栏页点：未选中 / 选中（选中是拉长的胶囊）。
  final Color pageDot, pageDotActive;

  /// 底栏胶囊（空调与媒体两块）的面与描边。
  final Color capsule, capsuleEdge;

  const SkinMaterial({
    required this.cardShade,
    required this.pageDot,
    required this.pageDotActive,
    required this.capsule,
    required this.capsuleEdge,
  });

  /// 取某套皮肤在某个明暗态下的材质。eclipse 的浅色是「透明玻璃」形态：
  /// 造型不变，但不能再压黑，所以 cardShade 归零。
  static SkinMaterial resolve(LauncherSkin skin, bool dark) => switch (skin) {
        LauncherSkin.eclipse => dark ? _eclipse : _eclipseLight,
        LauncherSkin.blueGlass => dark ? _glassDark : _glassLight,
        LauncherSkin.classic => dark ? _classicDark : _classicLight,
      };

  static const _eclipse = SkinMaterial(
    cardShade: .34,
    pageDot: Color(0x38FFFFFF),
    pageDotActive: Color(0xD9FFFFFF),
    // 和底栏音乐块同一档：音乐块那块 GlassSurface(flat) 已经是完全透明，
    // 胶囊再叠 4% 白就会在底栏里显出第二条亮度线（2026-11-19 用户要求
    // 「空调胶囊的底色和音乐块一样」）。留描边勾边界，底交给外壳。
    capsule: Color(0x00000000),
    capsuleEdge: Color(0x16FFFFFF),
  );

  /// 浅色暗夜：卡片是白玻璃，压黑会把底变脏；页点反过来用深色。
  static const _eclipseLight = SkinMaterial(
    cardShade: 0,
    pageDot: Color(0x59000000),
    pageDotActive: Color(0xCC000000),
    capsule: Color(0x3DFFFFFF),
    capsuleEdge: Color(0x1F000000),
  );

  static const _classicDark = SkinMaterial(
    // 浅底主题不压暗：一层黑渐变铺在透明白卡上会直接变灰。
    cardShade: 0,
    pageDot: Color(0x59FFFFFF),
    pageDotActive: Color(0xE0FFFFFF),
    capsule: Color(0x14B3D9D9),
    capsuleEdge: Color(0x2BE0FFFC),
  );

  static const _classicLight = SkinMaterial(
    cardShade: 0,
    pageDot: Color(0x59000000),
    pageDotActive: Color(0xE0000000),
    capsule: Color(0x5CFFFFFF),
    capsuleEdge: Color(0xC2FFFFFF),
  );

  static const _glassDark = SkinMaterial(
    cardShade: 0,
    pageDot: Color(0x5583B6FF),
    pageDotActive: Color(0xE0F2F6FC),
    capsule: Color(0x633C546A),
    capsuleEdge: Color(0x55E4F2FF),
  );

  static const _glassLight = SkinMaterial(
    cardShade: 0,
    pageDot: Color(0x55245BC1),
    pageDotActive: Color(0xE0172B42),
    capsule: Color(0xCCFFFFFF),
    capsuleEdge: Color(0xCCFFFFFF),
  );
}
