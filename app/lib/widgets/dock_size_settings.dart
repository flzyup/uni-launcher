import 'package:flutter/material.dart';
import '../controller/launcher_controller.dart';
import '../theme/design_tokens.dart';
import '../theme/launcher_theme.dart';
import 'setting_block.dart';

class DockSizeSettings extends StatelessWidget {
  final LauncherController controller;
  const DockSizeSettings({super.key, required this.controller});
  @override
  Widget build(BuildContext context) {
    final s = SurfaceStyle.of(context), c = controller;
    return SettingBlock(
        title: '底部栏大小',
        child: Row(children: [
          for (final (value, label) in [
            ('small', '小'),
            ('medium', '中'),
            ('large', '大'),
          ])
            Expanded(
                child: Padding(
                    padding: EdgeInsets.only(
                        right: value == 'large' ? 0 : Design.px(14)),
                    child: OutlinedButton(
                        key: ValueKey('dock-size-$value'),
                        style: s.selectionStyle(c.appearance.dockSize == value),
                        onPressed: () => c.setAppearance(
                            c.appearance.copyWith(dockSize: value)),
                        child: Padding(
                            padding:
                                EdgeInsets.symmetric(vertical: Design.px(14)),
                            child: Text(label))))),
        ]));
  }
}
