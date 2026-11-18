import 'package:flutter/material.dart';

import '../controller/launcher_controller.dart';
import '../theme/design_tokens.dart';
import '../theme/launcher_theme.dart';
import 'glass_surface.dart';

/// 「收藏 / 播放模式」两个按钮（移植自 CarDesk 音乐卡的同名实现）。
///
/// ## 为什么按钮会「自己消失」
///
/// 这两个能力**不是每个播放器都有**：
///
/// | 播放器 | 收藏 | 播放模式 |
/// |---|---|---|
/// | QQ 音乐车机版 | URI 协议 `m0=5/6` | URI 协议 `m0=101/103/105` |
/// | 网易云车机版 | 标准会话 `star_action` | 标准会话 `play_mode_action` |
/// | 汽水音乐车机版 | 标准评分（心形） | 无对外通道 |
/// | 其它播放器 | 运行时探测 | 运行时探测 |
///
/// → 原生侧用 `actionCaps` 报告当前音源**到底支持什么**，
/// 不支持的按钮**直接不画** —— 亮一个「点了没反应」的按钮比没有更糟。
///
/// ## 收藏态是三态，不是两态
///
/// 「已收藏 / 未收藏 / **不知道**」三态要分开：
/// 不知道 → 空心心形且颜色更弱（别让用户以为「确定没收藏」）。
///
/// 只用 `update_state`（只有播放态）那类广播的播放器不会带收藏字段，
/// 若把它当成「未收藏」，界面会在每次播放态更新时闪一下 —— 看着像收藏状态丢了。
class MusicActionButtons extends StatelessWidget {
  final Map<String, dynamic> media;
  final LauncherController controller;
  final double iconSize;

  /// 整体缩放。稿子 f1 的 4×4 版式整块按比例缩，两个按钮跟着走。
  final double scale;

  /// 相对设计稿基准尺寸的**放大倍数**。
  ///
  /// 车机是 1920×1080 实屏、观看距离又远，19~22 画布的心形/播放模式图标
  /// 在真机上偏小：点不准，状态（已收藏 / 单曲循环）也不够醒目。
  /// 图标、可点区域、两个按钮之间的间距**同步**放大 1.5 倍，保持它们还是一组。
  static const double sizeFactor = 1.5;

  const MusicActionButtons(
      {super.key,
      required this.media,
      required this.controller,
      this.iconSize = 22,
      this.scale = 1});

  /// 当前音源支不支持收藏。
  bool get _supportsFavorite => _caps['favorite'] == true;

  /// 当前音源支不支持切播放模式。
  bool get _supportsPlayMode => _caps['playMode'] == true;

  Map<String, dynamic> get _caps =>
      media['actionCaps'] is Map
          ? Map<String, dynamic>.from(media['actionCaps'] as Map)
          : const {};

  /// 收藏态：true = 已收藏，false = 未收藏，null = 不知道。
  bool? get _favorited {
    final value = media['favorited'];
    if (value is bool) return value;
    return null;
  }

  /// 播放模式：REPEAT_ALL / REPEAT_ONE / SHUFFLE，null = 不知道。
  String? get _playMode {
    final value = media['playMode'];
    if (value is String && value.isNotEmpty) return value;
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final s = SurfaceStyle.of(context);
    final widgets = <Widget>[];
    if (_supportsFavorite) {
      final known = _favorited != null;
      final filled = _favorited == true;
      // 已收藏 → 强调色实心；未收藏 → 常规弱色空心；不知道 → 更弱的空心。
      final color = filled
          ? s.accent
          : known
              ? s.muted
              : s.disabled;
      widgets.add(IconAction(
          key: const ValueKey('music-favorite-button'),
          icon: filled ? Icons.favorite : Icons.favorite_border,
          label: filled ? '取消收藏' : '收藏',
          size: Design.px(38) * scale * sizeFactor,
          iconSize: Design.px(iconSize) * scale * sizeFactor,
          framed: false,
          foregroundColor: color,
          onTap: () => controller.command('favorite-toggle')));
    }
    if (_supportsPlayMode) {
      final mode = _playMode;
      widgets.add(IconAction(
          key: const ValueKey('music-play-mode-button'),
          icon: switch (mode) {
            'REPEAT_ONE' => Icons.repeat_one,
            'SHUFFLE' => Icons.shuffle,
            // 顺序播放与「不知道」都画顺序箭头：
            // 不知道时点一下就是切到顺序播放（见原生侧的 nextPlayMode）。
            _ => Icons.repeat,
          },
          label: switch (mode) {
            'REPEAT_ONE' => '播放模式：单曲',
            'SHUFFLE' => '播放模式：随机',
            'REPEAT_ALL' => '播放模式：顺序',
            _ => '播放模式：顺序',
          },
          size: Design.px(38) * scale * sizeFactor,
          iconSize: Design.px(iconSize) * scale * sizeFactor,
          framed: false,
          // 模式未知时用更弱的色：此时显示的是「点完会切到的模式」，不是当前模式。
          foregroundColor: mode == null ? s.disabled : s.muted,
          onTap: () => controller.command('play-mode-toggle')));
    }
    if (widgets.isEmpty) return const SizedBox.shrink();
    return Row(mainAxisSize: MainAxisSize.min, children: [
      for (final widget in widgets) ...[
        SizedBox(width: Design.px(4) * sizeFactor),
        widget,
      ],
    ]);
  }
}
