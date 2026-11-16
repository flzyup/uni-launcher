import 'package:flutter/material.dart';
import '../controller/launcher_controller.dart';
import '../theme/design_tokens.dart';
import 'choice_button.dart';
import 'setting_block.dart';

/// sim f10 · 底栏图标大小：四个等分 `.opt`，选中态是主题色渐变实心。
class DockSizeSettings extends StatelessWidget {
  final LauncherController controller;
  const DockSizeSettings({super.key, required this.controller});
  @override
  Widget build(BuildContext context) {
    final c = controller;
    return SettingBlock(
        title: '底栏图标大小',
        dense: true,
        child: Row(children: [
          for (final (index, item) in [
            ('small', '小'),
            ('medium', '中'),
            ('large', '大'),
            ('extraLarge', '超大'),
          ].indexed) ...[
            if (index > 0) SizedBox(width: Design.dz(11.67)),
            Expanded(
                child: ChoiceButton(
                    key: ValueKey('dock-size-${item.$1}'),
                    height: 47,
                    selected: c.appearance.dockSize == item.$1,
                    onPressed: () => c.setAppearance(
                        c.appearance.copyWith(dockSize: item.$1)),
                    child: Text(item.$2,
                        style: TextStyle(fontSize: Design.dz(16)))))
          ],
        ]));
  }
}
