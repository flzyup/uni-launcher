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
import 'file_transfer_popup.dart';
import '../model/card_layout.dart';
import 'card_content.dart';
import 'uni_icon.dart';
import 'native_slice_builder.dart';
import 'scene_background.dart';

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
  Widget build(BuildContext context) => WallpaperInk(
      appearance: widget.controller.appearance,
      child: Builder(builder: _content));

  Widget _content(BuildContext context) {
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
                    select: (native) {
                      final status = mapOf(native['systemStatus']);
                      return [
                        native['demo'],
                        native['simulationMode'],
                        native['weather'],
                        status['bluetooth'],
                        status['network'],
                        status['usb'],
                        status['charging'],
                        status['dvr'],
                        native['transfer'] is Map &&
                            (native['transfer'] as Map)['running'] == true
                      ];
                    },
                    builder: (context, native) =>
                        Row(mainAxisSize: MainAxisSize.min, children: [
                          if (native['demo'] == true) ...[
                            Text(
                                native['simulationMode'] == 'highFidelity'
                                    ? '高保真'
                                    : '演示',
                                style: TextStyle(
                                    color: s.muted, fontSize: Design.px(17))),
                            SizedBox(width: Design.px(20)),
                          ],
                          _HeaderWeather(native: native),
                          SizedBox(width: Design.px(28)),
                          if (native['transfer'] is Map &&
                              (native['transfer'] as Map)['running'] ==
                                  true) ...[
                            Tooltip(
                                message: '文件服务运行中，打开传文件',
                                child: Semantics(
                                    button: true,
                                    label: '文件服务运行中，打开传文件',
                                    child: InkWell(
                                        key: const ValueKey(
                                            'status-file-transfer'),
                                        onTap: () => showFileTransferPopup(
                                            context, widget.controller),
                                        borderRadius: BorderRadius.circular(
                                            s.controlRadius),
                                        child: Padding(
                                            padding:
                                                EdgeInsets.all(Design.px(6)),
                                            child: Icon(
                                                Icons.upload_file_outlined,
                                                size: Design.px(24),
                                                color: s.accent))))),
                            SizedBox(width: Design.px(12)),
                          ],
                          SystemStatusRow(
                              status: native['systemStatus'] is Map
                                  ? Map<String, dynamic>.from(
                                      native['systemStatus'])
                                  : const {}),
                        ])),
              ])),
          if (widget.position != null && !widget.controller.settings)
            _DesktopPageIndicator(
                controller: widget.controller,
                position: widget.position!,
                // 页点数 = 可见页数：临时尾页只有编辑态才挂着（2026-11-14 起
                // 普通浏览不再有那张空白页），所以这里也只在编辑时 +1。
                pageCount: widget.controller.pageCount +
                    (widget.controller.editing ? 1 : 0)),
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

  /// 上一次建好的卡片树，和它的「布局签名」（见 _gridsFor）。
  List<Widget>? _cachedGrids;
  int _gridsSignature = 0;

  /// 正在铺满的那张卡（收起动画期间还留着，播完由 [_CardFocus.onClosed] 清掉）。
  LauncherCard? _focus;

  @override
  void initState() {
    super.initState();
    controller.focusedCard.addListener(_syncFocus);
  }

  /// 只在「开始铺满」时记下卡片；收起由 [_CardFocus] 自己播反向动画后回调。
  void _syncFocus() {
    final id = controller.focusedCard.value;
    if (id == null) {
      if (mounted) setState(() {});
      return;
    }
    final card = controller.cards.where((card) => card.id == id).firstOrNull;
    if (card != null && mounted) setState(() => _focus = card);
  }

  @override
  void didUpdateWidget(Desktop oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) {
      oldWidget.controller.focusedCard.removeListener(_syncFocus);
      widget.controller.focusedCard.addListener(_syncFocus);
    }
  }

  @override
  void dispose() {
    controller.focusedCard.removeListener(_syncFocus);
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
              const AssetImage('assets/art/lynk-05-top-line.webp'), context));
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = controller;
    // Keep pages and live map textures mounted while the workspace animates.
    final grids = _gridsFor(context);
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
                      displayPageCount: grids.length,
                      grids: [
                        for (int i = 0; i < grids.length; i++)
                          EmbeddedContentPolicy(
                              key: ValueKey('desktop-page-$i'),
                              enabled: EmbeddedContentPolicy.allowed(context),
                              visible: i == page &&
                                  !c.settings &&
                                  c.focusedCard.value == null,
                              child: Padding(
                                  padding: EdgeInsets.symmetric(
                                      horizontal: Design.px(32)),
                                  child: grids[i]))
                      ])),
          _dragFeedback(),
        ]));
  }

  /// 卡片树只在「布局真的变了」时重建。
  ///
  /// 以前每来一条遥测就把所有页的 AnimatedPositioned / RepaintBoundary /
  /// EditableCard 重新 new 一遍（三页 × 十几张卡），可绝大多数通知（车辆、
  /// 媒体、天气、时钟）跟布局毫无关系。签名只取真正会改变卡片树的输入，没变
  /// 就直接复用上一次的 widget 列表——连 diff 都不用走。
  List<Widget> _gridsFor(BuildContext context) {
    final c = controller;
    final target = c.placementTarget;
    final style = SurfaceStyle.of(context);
    final signature = Object.hash(
        identityHashCode(c.cards),
        c.pageCount,
        c.page,
        c.editing,
        identityHashCode(c.placementPreview),
        c.placementOrigin?.id,
        target?.page,
        target?.x,
        target?.y,
        target?.w,
        target?.h,
        c.placementResizing,
        c.placementValid,
        _feedbackId,
        // 铺满哪张卡会整块换掉这一页的 children，必须进签名，否则命中缓存后
        // 只 setState 而不重建网格，铺满层根本不会出现。
        c.focusedCard.value,
        _focus?.id,
        // 网格点阵、拖放预览用的都是主题色与圆角，换了皮肤必须重建。
        style.edge.toARGB32(),
        style.accent.toARGB32(),
        style.radius,
        MediaQuery.disableAnimationsOf(context));
    final cached = _cachedGrids;
    if (cached != null && signature == _gridsSignature) return cached;
    _gridsSignature = signature;
    return _cachedGrids = <Widget>[
      for (int page = 0; page < c.pageCount; page++) _grid(context, page),
      // 临时尾页只在编辑态挂着：普通浏览时它会变成一张永远滑得到的空白页
      // （中间一颗「添加一张卡片」按钮），用户 2026-11-14 要求不要这一页。
      // 编辑态仍需它：beginEditAtEnd / 拖卡到新页都靠它承载。
      if (c.editing && c.pageCount < 20)
        _grid(context, c.pageCount, scratch: true),
    ];
  }

  Widget _grid(BuildContext context, int page, {bool scratch = false}) {
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
      // 铺满时这一页只渲染那一张卡（其余卡片不建 widget，省一次整页重建）。
      final focusing = c.focusedCard.value;
      final focusCard = _focus;
      final focusHere =
          focusCard != null && focusCard.page == page && focusing != null;
      final focusClosing = focusCard != null && focusCard.page == page;
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
                            if (!c.editing) {
                              c.beginEditAtEnd();
                            } else if (scratch) {
                              unawaited(c.switchPage(page));
                            }
                            if (context.mounted) showCardLibrary(context, c);
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
            // 铺满时其余卡片**照常挂着**（内嵌地图这类要保住 texture 与实例），
            // 只是整层透明 + 不吃触摸；被铺满的那张改由下面的 _CardFocus 渲染。
            for (final card in items)
              if (!focusHere || card.id != focusCard.id)
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
                    child: IgnorePointer(
                        ignoring: focusHere,
                        child: Opacity(
                            opacity:
                                focusHere || card.id == _feedbackId ? 0 : 1,
                            child: RepaintBoundary(
                                key: _cardBoundaries.putIfAbsent(
                                    card.id,
                                    () => GlobalKey(
                                        debugLabel:
                                            'card-boundary-${card.id}')),
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
                                            unitY)))))), // EditableCard/RepaintBoundary/Opacity/IgnorePointer/AnimatedPositioned
            if (focusClosing)
              Positioned.fill(
                  child: _CardFocus(
                      key: ValueKey('card-focus-${focusCard.id}'),
                      controller: c,
                      card: focusHere ? focusCard : null,
                      origin: Rect.fromLTWH(
                          focusCard.x * unitX,
                          focusCard.y * unitY,
                          focusCard.w * unitX - gap,
                          focusCard.h * unitY - gap),
                      onClosed: () {
                        if (mounted) setState(() => _focus = null);
                      })),
          ]);
    });
  }
}

/// 把某张卡从它自己的格位放大到整块桌面区域，退出时反向收回。
///
/// 动画只做 **Transform + Opacity**：卡片按整页尺寸**只布局一次**，逐帧只改合成层
/// 的位移与等比缩放，不触发 relayout、不重建子树——开销和一次 220ms 的页面转场同级，
/// 车机上不会比翻页更卡。系统关掉动画（无障碍/降级）时直接跳到终态。
class _CardFocus extends StatefulWidget {
  /// null = 正在收起（播放反向动画）。
  final LauncherCard? card;
  final LauncherController controller;
  final Rect origin;
  final VoidCallback onClosed;
  const _CardFocus(
      {super.key,
      required this.card,
      required this.controller,
      required this.origin,
      required this.onClosed});
  @override
  State<_CardFocus> createState() => _CardFocusState();
}

class _CardFocusState extends State<_CardFocus>
    with SingleTickerProviderStateMixin {
  late final AnimationController _anim = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 220));
  late final Animation<double> _curve = CurvedAnimation(
      parent: _anim,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic);
  bool _started = false, _closed = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (MediaQuery.disableAnimationsOf(context)) {
      _anim.value = 1;
      return;
    }
    _anim.forward();
  }

  @override
  void didUpdateWidget(_CardFocus old) {
    super.didUpdateWidget(old);
    if (widget.card == null && old.card != null) _close();
  }

  void _close() {
    if (_closed) return;
    _closed = true;
    if (MediaQuery.disableAnimationsOf(context)) {
      widget.onClosed();
      return;
    }
    _anim.reverse().whenComplete(() {
      if (mounted) widget.onClosed();
    });
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, box) {
        final card = widget.card;
        final target = Rect.fromLTWH(0, 0, box.maxWidth, box.maxHeight);
        if (card == null) return const SizedBox.shrink();
        // 归一化的卡片：把尺寸换成整页，卡片自己的版式按「铺满档」排。
        final full = card.copyWith(w: 12, h: 6);
        final scale = math.min(widget.origin.width / math.max(target.width, 1),
            widget.origin.height / math.max(target.height, 1));
        return AnimatedBuilder(
            animation: _curve,
            builder: (context, child) {
              final t = _curve.value;
              final center =
                  Offset.lerp(widget.origin.center, target.center, t)!;
              return Opacity(
                  opacity: (t * 2).clamp(0.0, 1.0),
                  child: Transform.translate(
                      offset: center - target.center,
                      child: Transform.scale(
                          scale: ui.lerpDouble(scale, 1, t)!, child: child)));
            },
            child: GestureDetector(
                // 铺满时这层是 opaque 的：点空白直接收起（用户 2026-11-15 要求
                // 「点空白也能返回，点到功能键就不用返回」）。按键、进度条这些
                // 内层手势会先赢得竞技场，所以点它们不会冒泡到这里。
                behavior: HitTestBehavior.opaque,
                onTap: widget.controller.unfocusCard,
                child: Stack(children: [
                  Positioned.fill(
                      child: GlassSurface(
                          padding: EdgeInsets.zero,
                          card: true,
                          glow: SurfaceStyle.of(context).cardGlow(card.type),
                          child: ClipRect(
                              child: CardContent(
                                  card: full, controller: widget.controller)))),
                  Positioned(
                      right: Design.px(16),
                      top: Design.px(14),
                      child: IconAction(
                          key: const ValueKey('card-focus-close'),
                          icon: Icons.keyboard_arrow_down,
                          label: '收起',
                          size: Design.px(48),
                          iconSize: Design.px(26),
                          soft: true,
                          onTap: widget.controller.unfocusCard)),
                ])));
      });
}

class _DesktopStaticLayers extends StatelessWidget {
  final LauncherController controller;
  final List<Widget> grids;
  final GlobalKey<DesktopPageStackState> pagerKey;
  final ValueNotifier<double> position;
  final int displayPageCount;
  const _DesktopStaticLayers(
      {required this.controller,
      required this.grids,
      required this.pagerKey,
      required this.position,
      required this.displayPageCount});
  @override
  Widget build(BuildContext context) {
    final c = controller;
    return BackdropGroup(
        child: GestureDetector(
            key: const ValueKey('card-grid'),
            behavior: HitTestBehavior.translucent,
            onLongPress: c.editing ? null : c.beginEdit,
            // 铺满一张卡时，卡片左右各有 32 画布的网格边距，那一条缝不在
            // `_CardFocus` 的覆盖范围里，点下去原本没有任何反应。铺满期间把它也
            // 当作「点空白收起」；不铺满时这里是 null，不注册手势，不影响桌面。
            onTap: c.focusedCard.value == null ? null : c.unfocusCard,
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
                              SizedBox(width: Design.px(14)),
                              TextButton.icon(
                                  key: const ValueKey('add-card'),
                                  onPressed: () => showCardLibrary(context, c),
                                  icon: const Icon(Icons.add),
                                  label: const Text('添加卡片')),
                              SizedBox(width: Design.px(14)),
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
                          effect: c.appearance.pageTransition,
                          // 首尾环回只在普通浏览时开：编辑态要留给"边缘拖卡换页"，
                          // 铺满一张卡、设置页、拖拽落位时也不该绕圈。
                          wrap: !c.editing &&
                              !c.settings &&
                              !c.placing &&
                              c.focusedCard.value == null,
                          children: grids)),
                ]))));
  }
}

class _DesktopPageIndicator extends StatelessWidget {
  final LauncherController controller;
  final ValueNotifier<double> position;
  final int pageCount;
  const _DesktopPageIndicator(
      {required this.controller,
      required this.position,
      required this.pageCount});
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
                  width: slot * pageCount,
                  height: Design.px(16),
                  child: Stack(children: [
                    for (int i = 0; i < pageCount; i++)
                      Positioned(
                          left: slot * i + (slot - dot) / 2,
                          top: Design.px(4),
                          width: dot,
                          height: dot,
                          child: DecoratedBox(
                              decoration: BoxDecoration(
                                  // 页点色走材质表：设计稿是墨色系（深底用白、
                                  // 浅底用黑），不跟强调色，避免和卡片光晕抢。
                                  color: s.material.pageDot,
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
                                        color: s.material.pageDotActive,
                                        borderRadius:
                                            BorderRadius.circular(dot / 2)))))),
                    for (int i = 0; i < pageCount; i++)
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
