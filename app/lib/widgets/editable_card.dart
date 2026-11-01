import 'package:flutter/material.dart';
import '../controller/launcher_controller.dart';
import '../model/card_layout.dart';
import '../theme/launcher_theme.dart';
import '../theme/design_tokens.dart';
import 'card_content.dart';
import 'clock_weather_card.dart';
import 'glass_surface.dart';
import 'launcher_dialog.dart';
import 'media_source_badge.dart';
import 'uni_icon.dart';

part 'card_editor_sheet.dart';

class EditableCard extends StatefulWidget {
  final LauncherCard card;
  final LauncherController controller;
  final double unitX, unitY;
  final void Function(LauncherCard card, bool resize, Offset globalPosition)?
      onPlacementStart;
  const EditableCard(
      {super.key,
      required this.card,
      required this.controller,
      required this.unitX,
      required this.unitY,
      this.onPlacementStart});
  @override
  State<EditableCard> createState() => _EditableCardState();
}

class _EditableCardState extends State<EditableCard> {
  void start(bool resize, Offset globalPosition) {
    final c = widget.controller;
    if (!c.editing) {
      c.beginEdit();
      // The edit strip changes the grid's origin and cell height. Measure only
      // after its first layout, retaining the same physical pointer position.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && c.editing)
          widget.onPlacementStart?.call(widget.card, resize, globalPosition);
      });
    } else {
      widget.onPlacementStart?.call(widget.card, resize, globalPosition);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller,
        s = SurfaceStyle.of(context),
        card = widget.card;
    return GestureDetector(
        onLongPressStart: (d) => start(false, d.globalPosition),
        child: GlassSurface(
            padding: EdgeInsets.zero,
            glow: s.cardGlow(card.type),
            borderColor: c.editing ? s.accent : null,
            child: Stack(children: [
              Positioned.fill(
                  top: c.editing ? Design.px(64) : 0,
                  // Lyrics, gauges and map textures update independently from
                  // the large rounded surface, border and blurred shadow.
                  child: RepaintBoundary(
                      child: CardContent(card: card, controller: c))),
              if (c.editing) ...[
                Positioned(
                    top: Design.px(8),
                    left: Design.px(14),
                    right: Design.px(12),
                    height: Design.px(46),
                    child: Row(children: [
                      Expanded(
                          child: GestureDetector(
                              key: ValueKey('move-${card.id}'),
                              behavior: HitTestBehavior.opaque,
                              onPanStart: (d) => start(false, d.globalPosition),
                              onPanUpdate: (_) {},
                              child: Row(children: [
                                UniIcon('move',
                                    color: s.accent, size: Design.px(23)),
                                SizedBox(width: Design.px(9)),
                                Expanded(
                                    child: card.type == 'music'
                                        ? MediaSourceBadge(
                                            controller: c,
                                            titleBar: true,
                                            compact: true,
                                            enabled: false)
                                        : Text(card.title,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                                fontSize: Design.px(21),
                                                color: s.accent))),
                                SizedBox(width: Design.px(9)),
                                Text('${card.w} × ${card.h}',
                                    style: TextStyle(
                                        color: s.muted,
                                        fontSize: Design.px(15)))
                              ]))),
                      IconAction(
                          icon: Icons.edit_outlined,
                          label: '编辑${card.title}',
                          size: Design.px(44),
                          iconSize: Design.px(22),
                          soft: true,
                          onTap: () => editCard(context, c, card)),
                      SizedBox(width: Design.px(9)),
                      _DeleteCardAction(card: card, controller: c),
                    ])),
                Positioned(
                    bottom: 0,
                    right: 0,
                    width: Design.px(48),
                    height: Design.px(48),
                    child: GestureDetector(
                        key: ValueKey('resize-${card.id}'),
                        onPanStart: (d) => start(true, d.globalPosition),
                        onPanUpdate: (_) {},
                        child: Container(
                            decoration: BoxDecoration(
                                // 暗夜卡面是近黑，原来的 s.strong(.70) 手柄
                                // 贴上去几乎看不见，用户会以为「没有大小手柄、
                                // 拖不动」。这里换成主题强调色的淡底＋描边。
                                color: s.nocturne
                                    ? s.accent.withValues(alpha: .18)
                                    : s.strong.withValues(alpha: .70),
                                border: s.nocturne
                                    ? Border.all(
                                        color: s.accent.withValues(alpha: .45))
                                    : null,
                                borderRadius: BorderRadius.only(
                                    topLeft: Radius.circular(s.controlRadius))),
                            child: Center(
                                child: UniIcon('resize',
                                    size: Design.px(24),
                                    color: s.nocturne ? s.accent : s.muted))))),
              ]
            ])));
  }
}

class _DeleteCardAction extends StatelessWidget {
  final LauncherCard card;
  final LauncherController controller;
  const _DeleteCardAction({required this.card, required this.controller});
  @override
  Widget build(BuildContext context) {
    final s = SurfaceStyle.of(context);
    return Tooltip(
        message: '删除${card.title}',
        child: Semantics(
            button: true,
            label: '删除${card.title}',
            child: SizedBox(
                width: Design.px(44),
                height: Design.px(44),
                child: Material(
                    color: s.soft,
                    borderRadius: BorderRadius.circular(s.controlRadius),
                    child: InkWell(
                        key: ValueKey('delete-${card.id}'),
                        borderRadius: BorderRadius.circular(s.controlRadius),
                        onTap: () {
                          controller.remove(card.id);
                          showLauncherToast(context, '卡片已移除');
                        },
                        child: Center(
                            child: UniIcon('trash',
                                size: Design.px(22), color: s.text)))))));
  }
}
