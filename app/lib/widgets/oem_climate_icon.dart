import 'package:flutter/material.dart';

/// 原车 SystemUI 空调图标。资源仅裁去透明留白，保留原始线条和档位明暗。
/// 统一使用白色夜间资源乘以主题色，避免黑色日间资源着色后不可见。
class OemClimateIcon extends StatelessWidget {
  final String asset;
  final Color color;
  final double size;
  final double? width;

  const OemClimateIcon(this.asset,
      {super.key, required this.color, required this.size, this.width});

  @override
  Widget build(BuildContext context) =>
      Image.asset('assets/icons/oem_climate/$asset.png',
          width: width ?? size,
          height: size,
          fit: BoxFit.contain,
          color: color,
          colorBlendMode: BlendMode.modulate,
          gaplessPlayback: true,
          excludeFromSemantics: true);
}

/// 座椅图标按主副驾方向和实际档位选择；关闭/未知只降低可见度，不伪造档位。
class OemSeatIcon extends StatelessWidget {
  final bool ventilation;
  final bool passenger;
  final int? level;
  final Color color;
  final double size;

  const OemSeatIcon(
      {super.key,
      this.ventilation = false,
      this.passenger = false,
      required this.level,
      required this.color,
      required this.size});

  @override
  Widget build(BuildContext context) {
    final active = level != null && level! > 0;
    return OemClimateIcon(
        'seat_${ventilation ? 'fan' : 'heat'}_${active ? level!.clamp(1, 3) : 3}_${passenger ? 'right' : 'left'}',
        color: active ? color : color.withValues(alpha: color.a * .35),
        size: size);
  }
}
