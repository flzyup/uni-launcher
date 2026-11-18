import 'package:flutter/material.dart';
import '../controller/launcher_controller.dart';
import '../model/appearance.dart';
import '../theme/design_tokens.dart';
import '../theme/launcher_theme.dart';
import 'launcher_dialog.dart';
import 'choice_button.dart';

/// 设计稿 `#f20`（`theme-styles/eclipse/simulator.html`）：
/// `.nm-dlg` 566.7 宽、内边距 34·38、整体居中；标题 21/500；输入框 56 高、
/// 圆角 14、6% 墨底 + 12% 描边；计数 11.5 右对齐；底部两颗等宽按钮
/// （取消 = 6% 墨底 + 9% 描边，保存 = 强调色渐变实底）。
///
/// 稿子里没有「关闭」键，也没有「恢复默认」——前者由取消按钮承担，
/// 后者保留成一个静默文字链（放计数行左侧），不破坏原有能力。
Future<void> showDesktopNameDialog(
    BuildContext context, LauncherController c) async {
  final name = await showLauncherSheet<String>(context,
      title: '桌面名称',
      closeLabel: '关闭名称编辑',
      width: Design.dz(566.7),
      showHeader: false,
      padding: EdgeInsets.symmetric(
          horizontal: Design.dz(38), vertical: Design.dz(34)),
      builder: (_) => _DesktopNameEditor(initial: c.appearance.desktopName));
  if (name != null) c.setAppearance(c.appearance.copyWith(desktopName: name));
}

class _DesktopNameEditor extends StatefulWidget {
  final String initial;
  const _DesktopNameEditor({required this.initial});
  @override
  State<_DesktopNameEditor> createState() => _DesktopNameEditorState();
}

class _DesktopNameEditorState extends State<_DesktopNameEditor> {
  static const _max = 24;
  late final input = TextEditingController(text: widget.initial);

  @override
  void initState() {
    super.initState();
    // 计数（`14 / 24`）要跟着每次输入走。
    input.addListener(_onChanged);
  }

  void _onChanged() => setState(() {});

  @override
  void dispose() {
    input.removeListener(_onChanged);
    input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = SurfaceStyle.of(context), ink = s.text;
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Text('桌面名称',
          textAlign: TextAlign.center,
          style: TextStyle(
              fontSize: Design.dz(21),
              fontWeight: FontWeight.w500,
              height: 1.1,
              color: ink.withValues(alpha: .94))),
      SizedBox(height: Design.dz(24)),
      Container(
          height: Design.dz(56),
          padding: EdgeInsets.symmetric(horizontal: Design.dz(18)),
          alignment: Alignment.centerLeft,
          decoration: BoxDecoration(
              color: ink.withValues(alpha: .06),
              border: Border.all(color: ink.withValues(alpha: .12)),
              borderRadius: BorderRadius.circular(Design.dz(14))),
          child: TextField(
              key: const ValueKey('desktop-name-input'),
              controller: input,
              maxLength: _max,
              maxLines: 1,
              textInputAction: TextInputAction.done,
              cursorColor: s.accent,
              cursorWidth: Design.dz(1.5),
              style: TextStyle(
                  fontSize: Design.dz(17),
                  letterSpacing: Design.dz(1.02),
                  color: ink.withValues(alpha: .9)),
              decoration: InputDecoration(
                  counterText: '',
                  isDense: true,
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.zero,
                  hintText: '给桌面起个名字',
                  hintStyle: TextStyle(
                      fontSize: Design.dz(17),
                      letterSpacing: Design.dz(1.02),
                      color: ink.withValues(alpha: .26))),
              onSubmitted: (v) => Navigator.pop(context, v))),
      SizedBox(height: Design.dz(10)),
      Row(children: [
        GestureDetector(
            key: const ValueKey('desktop-name-reset'),
            behavior: HitTestBehavior.opaque,
            onTap: () => setState(() {
                  input.text = Appearance.defaultDesktopName;
                  input.selection = TextSelection.collapsed(
                      offset: input.text.length);
                }),
            child: Padding(
                padding: EdgeInsets.symmetric(vertical: Design.dz(2)),
                child: Text('恢复默认',
                    style: TextStyle(
                        fontSize: Design.dz(11.5),
                        color: ink.withValues(alpha: .38))))),
        const Spacer(),
        Text('${input.text.characters.length} / $_max',
            key: const ValueKey('desktop-name-count'),
            style: TextStyle(
                fontSize: Design.dz(11.5),
                fontFeatures: const [FontFeature.tabularFigures()],
                color: ink.withValues(alpha: .34)))
      ]),
      SizedBox(height: Design.dz(26)),
      Row(children: [
        Expanded(
            child: _NameButton(
                label: '取消',
                onTap: () => Navigator.pop(context),
                soft: true)),
        SizedBox(width: Design.dz(12)),
        Expanded(
            child: _NameButton(
                key: const ValueKey('desktop-name-save'),
                label: '保存',
                onTap: () => Navigator.pop(context, input.text.trim())))
      ])
    ]);
  }
}

/// `.nm-btns .b`：48 高、圆角 14、15px；主按钮是 `170deg` 强调色渐变，
/// 文字用 `accentText`（深色皮肤下是近黑墨绿）。
class _NameButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  final bool soft;
  const _NameButton(
      {super.key, required this.label, required this.onTap, this.soft = false});
  @override
  Widget build(BuildContext context) {
    return ChoiceButton(
        height: Design.controlHeight,
        selected: !soft,
        onPressed: onTap,
        child: Text(label, style: TextStyle(fontSize: Design.dz(15))));
  }
}
