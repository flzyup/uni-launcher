import 'package:flutter/material.dart';

import '../theme/launcher_theme.dart';
import '../theme/design_tokens.dart';
import 'liquid_press.dart';
import 'liquid_material.dart';

/// 设计稿里 `.vh-g` / 温度卡 / 座椅卡共用的「平面描边块」：
/// 3.5% 墨色底 + 7% 描边 + 16 圆角，不带玻璃高光、不带投影。
///
/// 空调与座椅面板、车辆信息页里所有分组都用它——稿子里这些块是纯色平面，
/// 用 [GlassSurface] 会多出渐变高光和边缘亮线，一行四五个块排下来很花。
class SpecPanel extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double? radius;
  const SpecPanel(
      {super.key,
      required this.child,
      this.padding = EdgeInsets.zero,
      this.radius});
  @override
  Widget build(BuildContext context) {
    final s = SurfaceStyle.of(context), ink = s.text;
    if (s.liquidGlass) {
      return LiquidMaterial(
          sheet: true,
          shadow: false,
          radius: BorderRadius.circular(radius ?? s.controlRadius),
          child: Padding(padding: padding, child: child));
    }
    return Container(
        padding: padding,
        decoration: BoxDecoration(
            color: ink.withValues(alpha: .035),
            border: Border.all(color: ink.withValues(alpha: .07)),
            borderRadius: BorderRadius.circular(radius ?? s.controlRadius)),
        child: child);
  }
}

/// `.step-b`：42 见方、圆角 12、5% 墨底 + 10% 描边的加减键。
class SpecStepButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  const SpecStepButton(
      {super.key, required this.icon, required this.label, this.onTap});
  @override
  Widget build(BuildContext context) {
    final s = SurfaceStyle.of(context), ink = s.text;
    final enabled = onTap != null;
    final button = Semantics(
        button: true,
        enabled: enabled,
        label: label,
        child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onTap,
            child: Container(
                width: Design.compactControlHeight,
                height: Design.compactControlHeight,
                decoration: BoxDecoration(
                    color: ink.withValues(alpha: .05),
                    border: Border.all(color: ink.withValues(alpha: .10)),
                    borderRadius: BorderRadius.circular(s.controlRadius)),
                child: Icon(icon,
                    size: 19, color: enabled ? s.text : s.disabled))));
    return LiquidPress(enabled: enabled, child: button);
  }
}
