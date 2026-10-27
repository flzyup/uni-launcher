import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import '../controller/launcher_controller.dart';
import '../theme/launcher_theme.dart';
import '../theme/design_tokens.dart';
import 'glass_surface.dart';
import 'editable_card.dart';
import 'page_transition.dart';
import 'embedded_navigation.dart';
import '../model/weather_condition.dart';
import 'weather_icon.dart';
import 'desktop_name_dialog.dart';
import 'system_status_row.dart';
import '../model/card_layout.dart';
import 'card_content.dart';
import 'uni_icon.dart';
import 'native_slice_builder.dart';

part 'desktop_drag.dart';

class Header extends StatefulWidget {
  final LauncherController controller;
  final ValueNotifier<double>? position;
  const Header({super.key, required this.controller, this.position});
  @override
  State<Header> createState() => _HeaderState();
}

class _HeaderState extends State<Header> {
  Timer? timer;
  @override
  void initState() {
    super.initState();
    timer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = SurfaceStyle.of(context), d = DateTime.now();
    return SizedBox(
        height: Design.px(64),
        child: Stack(alignment: Alignment.center, children: [
          Padding(
              padding: EdgeInsets.symmetric(horizontal: Design.px(40)),
              child: Row(children: [
                Text(
                    '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}',
                    style: TextStyle(
                        fontSize: Design.px(23), fontWeight: FontWeight.w500)),
                const SizedBox(width: 28),
                GestureDetector(
                    key: const ValueKey('desktop-name'),
                    onLongPress: () =>
                        showDesktopNameDialog(context, widget.controller),
                    child: ConstrainedBox(
                        constraints: BoxConstraints(maxWidth: Design.px(480)),
                        child: Text(widget.controller.appearance.desktopName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                color: s.muted,
                                fontSize: 15,
                                letterSpacing: 2)))),
                const Spacer(),
                NativeSliceBuilder(
                    valueListenable: widget.controller.native,
                    select: (native) => [
                          native['demo'],
                          native['weather'],
                          native['systemStatus']
                        ],
                    builder: (context, native) =>
                        Row(mainAxisSize: MainAxisSize.min, children: [
                          if (native['demo'] == true) ...[
                            Text('演示',
                                style: TextStyle(
                                    color: s.muted, fontSize: Design.px(17))),
                            SizedBox(width: Design.px(20)),
                          ],
                          _HeaderWeather(native: native),
                          SizedBox(width: Design.px(28)),
                          SystemStatusRow(
                              status: native['systemStatus'] is Map
                                  ? Map<String, dynamic>.from(
                                      native['systemStatus'])
                                  : const {}),
                        ])),
              ])),
          if (widget.position != null && !widget.controller.settings)
            _DesktopPageIndicator(
                controller: widget.controller, position: widget.position!),
        ]));
  }
}

class _HeaderWeather extends StatelessWidget {
  final Map<String, dynamic> native;
  const _HeaderWeather({required this.native});
  @override
  Widget build(BuildContext context) {
    final weather = WeatherSnapshot.fromNative(native),
        s = SurfaceStyle.of(context);
    if (!weather.available)
      return Text('天气暂未更新',
          style: TextStyle(color: s.muted, fontSize: Design.px(19)));
    return Row(mainAxisSize: MainAxisSize.min, children: [
      WeatherIcon(
          condition: weather.condition,
          night: weather.night,
          size: Design.px(26),
          color: s.muted),
      SizedBox(width: Design.px(12)),
      Text('${weather.city}  ${weather.temperature}° ${weather.description}',
          style: TextStyle(color: s.muted, fontSize: Design.px(20))),
    ]);
  }
}

class Desktop extends StatefulWidget {
  final LauncherController controller;
  final ValueNotifier<double>? position;
  const Desktop({super.key, required this.controller, this.position});
  @override
  State<Desktop> createState() => _DesktopState();
}

class _DesktopState extends State<Desktop> with _DesktopDrag {
  LauncherController get controller => widget.controller;
  final _pagerKey = GlobalKey<DesktopPageStackState>();
  late final _pagePosition =
      widget.position ?? ValueNotifier(controller.page.toDouble());
  bool warmed = false;
  @override
  void dispose() {
    if (widget.position == null) _pagePosition.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!warmed) {
      warmed = true;
      // Decode the detailed vehicle trace while the first workspace is idle,
      // rather than on the first frame of the vehicle-page transition.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted)
          unawaited(precacheImage(
              const AssetImage('assets/art/lynk-05-top-line.png'), context));
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = controller;
    // Keep pages and live map textures mounted while the workspace animates.
    final grids = <Widget>[
      for (int page = 0; page < c.pageCount; page++) _grid(context, page)
    ];
    // Page changes use a dedicated signal. Header, dock, theme, inactive cards
    // and the MaterialApp no longer rebuild for every swipe.
    _cardBoundaries
        .removeWhere((id, _) => !c.cards.any((card) => card.id == id));
    return Listener(
        onPointerDown: _pointerDown,
        onPointerMove: _pointerMove,
        onPointerUp: _pointerUp,
        onPointerCancel: _pointerCancel,
        child: Stack(key: _workspaceKey, fit: StackFit.expand, children: [
          ValueListenableBuilder<int>(
              valueListenable: c.pageChanged,
              builder: (context, page, __) => _DesktopStaticLayers(
                      controller: c,
                      pagerKey: _pagerKey,
                      position: _pagePosition,
                      grids: [
                        for (int i = 0; i < grids.length; i++)
                          EmbeddedContentPolicy(
                              key: ValueKey('desktop-page-$i'),
                              enabled: EmbeddedContentPolicy.allowed(context),
                              visible: i == page && !c.settings,
                              child: Padding(
                                  padding: EdgeInsets.symmetric(
                                      horizontal: Design.px(32)),
                                  child: grids[i]))
                      ])),
          _dragFeedback(),
        ]));
  }

  Widget _grid(BuildContext context, int page) {
    final c = controller;
    return LayoutBuilder(builder: (context, box) {
      const gap = 20.0;
      final unitX = (box.maxWidth + gap) / 12,
          unitY = (box.maxHeight + gap) / 6,
          preview = {
            for (final card in c.placementPreview ?? <LauncherCard>[])
              card.id: card
          },
          items = c.cards
              .map((card) =>
                  card.id == c.placementOrigin?.id && !c.placementResizing
                      ? card
                      : preview[card.id] ?? card)
              .where((card) => card.page == page)
              .toList();
      final target = c.placementTarget;
      return Stack(
          key: ValueKey('desktop-grid-$page'),
          clipBehavior: Clip.none,
          children: [
            if (page == c.page)
              const Positioned.fill(
                  child: IgnorePointer(
                      child: SizedBox.expand(key: ValueKey('grid-bounds')))),
            if (c.editing)
              Positioned.fill(
                  child: IgnorePointer(
                      child: CustomPaint(
                          painter: _GridDots(
                              unitX, unitY, SurfaceStyle.of(context).edge)))),
            if (items.isEmpty)
              Positioned.fill(
                  child: Center(
                      child: OutlinedButton.icon(
                          onPressed: () {
                            if (!c.editing) c.beginEdit();
                            showCardLibrary(context, c);
                          },
                          icon: const Icon(Icons.add),
                          label: const Text('添加一张卡片')))),
            if (target != null && target.page == page)
              Positioned(
                  left: target.x * unitX,
                  top: target.y * unitY,
                  width: target.w * unitX - gap,
                  height: target.h * unitY - gap,
                  child: IgnorePointer(
                      child: Container(
                          key: const ValueKey('card-drop-preview'),
                          decoration: BoxDecoration(
                              color: (c.placementValid
                                      ? SurfaceStyle.of(context).accent
                                      : Theme.of(context).colorScheme.error)
                                  .withValues(alpha: .08),
                              borderRadius: BorderRadius.circular(
                                  SurfaceStyle.of(context).radius),
                              border: Border.all(
                                  width: 2,
                                  color: c.placementValid
                                      ? SurfaceStyle.of(context).accent
                                      : Theme.of(context)
                                          .colorScheme
                                          .error))))),
            for (final card in items)
              AnimatedPositioned(
                  key: ValueKey('position-${card.id}'),
                  duration: !c.editing ||
                          MediaQuery.disableAnimationsOf(context) ||
                          (c.placementResizing &&
                              card.id == c.placementOrigin?.id)
                      ? Duration.zero
                      : const Duration(milliseconds: 150),
                  curve: Curves.easeOutCubic,
                  left: card.x * unitX,
                  top: card.y * unitY,
                  width: card.w * unitX - gap,
                  height: card.h * unitY - gap,
                  child: Opacity(
                      opacity: card.id == _feedbackId ? 0 : 1,
                      child: RepaintBoundary(
                          key: _cardBoundaries.putIfAbsent(
                              card.id,
                              () => GlobalKey(
                                  debugLabel: 'card-boundary-${card.id}')),
                          child: EditableCard(
                              key: ValueKey(card.id),
                              card: card,
                              controller: c,
                              unitX: unitX,
                              unitY: unitY,
                              onPlacementStart: (card, resize, position) =>
                                  _beginGesture(
                                      card,
                                      resize,
                                      position,
                                      context.findRenderObject()! as RenderBox,
                                      unitX,
                                      unitY))))),
          ]);
    });
  }
}

class _DesktopStaticLayers extends StatelessWidget {
  final LauncherController controller;
  final List<Widget> grids;
  final GlobalKey<DesktopPageStackState> pagerKey;
  final ValueNotifier<double> position;
  const _DesktopStaticLayers(
      {required this.controller,
      required this.grids,
      required this.pagerKey,
      required this.position});
  @override
  Widget build(BuildContext context) {
    final c = controller;
    return BackdropGroup(
        child: GestureDetector(
            key: const ValueKey('card-grid'),
            behavior: HitTestBehavior.translucent,
            onLongPress: c.editing ? null : c.beginEdit,
            onHorizontalDragStart: (_) {
              if (!c.placing) pagerKey.currentState?.dragStart();
            },
            onHorizontalDragUpdate: (d) {
              if (!c.placing)
                pagerKey.currentState?.dragUpdate(d.primaryDelta ?? 0);
            },
            onHorizontalDragEnd: (d) {
              if (!c.placing)
                pagerKey.currentState?.dragEnd(d.primaryVelocity ?? 0);
            },
            onHorizontalDragCancel: () => pagerKey.currentState?.dragCancel(),
            child: Padding(
                padding:
                    EdgeInsets.fromLTRB(0, Design.px(16), 0, Design.px(24)),
                child: Column(children: [
                  if (c.editing)
                    SizedBox(
                        height: Design.px(74),
                        child: Padding(
                            padding:
                                EdgeInsets.symmetric(horizontal: Design.px(32)),
                            child: Row(children: [
                              const Text('编辑桌面',
                                  style: TextStyle(fontSize: 28)),
                              const SizedBox(width: 24),
                              Text('拖动卡片让位 · 边缘停留换页 · 右下角调整尺寸',
                                  style: TextStyle(
                                      color: SurfaceStyle.of(context).muted,
                                      fontSize: 17)),
                              const Spacer(),
                              TextButton(
                                  key: const ValueKey('cancel-edit'),
                                  onPressed: c.cancelEdit,
                                  child: const Text('取消')),
                              TextButton.icon(
                                  key: const ValueKey('add-card'),
                                  onPressed: () => showCardLibrary(context, c),
                                  icon: const Icon(Icons.add),
                                  label: const Text('添加卡片')),
                              FilledButton(
                                  key: const ValueKey('finish-edit'),
                                  onPressed: c.finishEdit,
                                  child: const Text('完成'))
                            ]))),
                  Expanded(
                      child: DesktopPageStack(
                          key: pagerKey,
                          page: c.page,
                          position: position,
                          onPageRequested: (page) =>
                              unawaited(c.switchPage(page)),
                          effect:
                              c.editing ? 'none' : c.appearance.pageTransition,
                          children: grids)),
                ]))));
  }
}

class _DesktopPageIndicator extends StatelessWidget {
  final LauncherController controller;
  final ValueNotifier<double> position;
  const _DesktopPageIndicator(
      {required this.controller, required this.position});
  @override
  Widget build(BuildContext context) {
    final c = controller,
        s = SurfaceStyle.of(context),
        slot = Design.px(38),
        dot = Design.px(8),
        pill = Design.px(24);
    return SizedBox(
        height: Design.px(16),
        child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                  width: slot * c.pageCount,
                  height: Design.px(16),
                  child: Stack(children: [
                    for (int i = 0; i < c.pageCount; i++)
                      Positioned(
                          left: slot * i + (slot - dot) / 2,
                          top: Design.px(4),
                          width: dot,
                          height: dot,
                          child: DecoratedBox(
                              decoration: BoxDecoration(
                                  color: s.muted.withValues(alpha: .3),
                                  borderRadius:
                                      BorderRadius.circular(dot / 2)))),
                    Positioned(
                        left: (slot - pill) / 2,
                        top: Design.px(4),
                        width: pill,
                        height: dot,
                        child: RepaintBoundary(
                            child: ValueListenableBuilder<double>(
                                valueListenable: position,
                                builder: (context, value, child) =>
                                    Transform.translate(
                                        offset: Offset(slot * value, 0),
                                        child: KeyedSubtree(
                                            key: const ValueKey(
                                                'page-indicator-active'),
                                            child: child!)),
                                child: DecoratedBox(
                                    decoration: BoxDecoration(
                                        color: s.accent,
                                        borderRadius:
                                            BorderRadius.circular(dot / 2)))))),
                    for (int i = 0; i < c.pageCount; i++)
                      Positioned(
                          left: slot * i,
                          width: slot,
                          top: 0,
                          bottom: 0,
                          child: Semantics(
                              label: '桌面第${i + 1}页',
                              button: true,
                              child: GestureDetector(
                                  key: ValueKey('page-$i'),
                                  behavior: HitTestBehavior.opaque,
                                  onTap: () => c.switchPage(i))))
                  ])),
              if (c.editing)
                IconAction(
                    icon: Icons.add, label: '新建桌面页', size: 32, onTap: c.newPage)
            ]));
  }
}

class _GridDots extends CustomPainter {
  final double unitX, unitY;
  final Color color;
  _GridDots(this.unitX, this.unitY, this.color);
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()..color = color;
    for (double x = 0; x < size.width; x += unitX)
      for (double y = 0; y < size.height; y += unitY)
        canvas.drawCircle(Offset(x, y), Design.px(1.5), p);
  }

  @override
  bool shouldRepaint(_GridDots old) =>
      old.unitX != unitX || old.unitY != unitY || old.color != color;
}
