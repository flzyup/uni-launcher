import 'package:flutter/material.dart';
import '../theme/design_tokens.dart';
import '../theme/launcher_theme.dart';
import 'glass_surface.dart';

class SettingBlock extends StatelessWidget {
  final String title;
  final String? note;
  final Widget? trailing;
  final Widget child;
  final bool compact;
  const SettingBlock(
      {super.key,
      required this.title,
      this.note,
      this.trailing,
      required this.child,
      this.compact = false});
  @override
  Widget build(BuildContext context) {
    final s = SurfaceStyle.of(context);
    return GlassSurface(
        padding: EdgeInsets.symmetric(
            horizontal: Design.px(30), vertical: Design.px(compact ? 16 : 22)),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Text(title,
                style: TextStyle(
                    fontSize: Design.px(26), fontWeight: FontWeight.w500)),
            if (note != null || trailing != null) const Spacer(),
            if (note != null)
              Text(note!,
                  style: TextStyle(color: s.muted, fontSize: Design.px(18))),
            if (trailing != null) trailing!
          ]),
          SizedBox(height: Design.px(18)),
          child
        ]));
  }
}
