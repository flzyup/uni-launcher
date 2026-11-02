part of 'desktop.dart';

class _CardGesture {
  final LauncherCard card;
  final bool resize;
  final int pointer;
  final Offset start, gridOrigin;
  final Size gridSize;
  final double unitX, unitY;
  const _CardGesture(this.card, this.resize, this.pointer, this.start,
      this.gridOrigin, this.gridSize, this.unitX, this.unitY);
}

/// Workspace-owned pointer tracking survives a card being displaced, resized or
/// moved to another page. Pointer frames update only the small drag layer.
mixin _DesktopDrag on State<Desktop> {
  final _workspaceKey = GlobalKey();
  final _cardBoundaries = <String, GlobalKey>{};
  final _pointers = <int, Offset>{};
  final _pointerStarts = <int, Offset>{};
  final _feedbackBounds = ValueNotifier<Rect?>(null);
  _CardGesture? _gesture;
  LauncherCard? _pendingTarget;
  Timer? _hoverTimer, _edgeTimer, _settleTimer;
  String? _feedbackId;
  ui.Image? _feedbackImage;
  int _imageGeneration = 0, _edgeDirection = 0;
  bool _settling = false;
  LauncherController get _controller => widget.controller;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_placementChanged);
  }

  void _placementChanged() {
    if (_gesture != null && (!_controller.placing || !_controller.editing)) {
      _releaseGesture(cancel: true);
    }
  }

  Offset _local(Offset global) =>
      (_workspaceKey.currentContext!.findRenderObject()! as RenderBox)
          .globalToLocal(global);

  Rect _cardRect(_CardGesture g, LauncherCard card) =>
      (_local(g.gridOrigin) + Offset(card.x * g.unitX, card.y * g.unitY)) &
      Size(card.w * g.unitX - 20, card.h * g.unitY - 20);

  void _pointerDown(PointerDownEvent e) {
    _pointers[e.pointer] = e.position;
    _pointerStarts[e.pointer] = e.position;
  }

  void _pointerMove(PointerMoveEvent e) {
    _pointers[e.pointer] = e.position;
    if (_gesture?.pointer == e.pointer) _moveGesture(e.position);
  }

  void _pointerUp(PointerUpEvent e) {
    if (_gesture?.pointer == e.pointer) _releaseGesture();
    _pointers.remove(e.pointer);
    _pointerStarts.remove(e.pointer);
  }

  void _pointerCancel(PointerCancelEvent e) {
    if (_gesture?.pointer == e.pointer) _releaseGesture(cancel: true);
    _pointers.remove(e.pointer);
    _pointerStarts.remove(e.pointer);
  }

  void _beginGesture(LauncherCard card, bool resize, Offset global,
      RenderBox grid, double unitX, double unitY) {
    if (_gesture != null || _pointers.isEmpty) return;
    _clearFeedback();
    final pointer = _pointers.entries
        .reduce((a, b) => (a.value - global).distanceSquared <
                (b.value - global).distanceSquared
            ? a
            : b)
        .key;
    final g = _CardGesture(
        card,
        resize,
        pointer,
        _pointerStarts[pointer] ?? global,
        grid.localToGlobal(Offset.zero),
        grid.size,
        unitX,
        unitY);
    _gesture = g;
    _pendingTarget = card;
    if (!resize) {
      _feedbackId = card.id;
      _feedbackBounds.value = _cardRect(g, card);
      unawaited(_captureCard(card.id, ++_imageGeneration));
    }
    if (!_controller.beginPlacement(card.id, resizing: resize)) {
      _gesture = null;
      _clearFeedback();
      return;
    }
    _moveGesture(_pointers[pointer]!);
  }

  Future<void> _captureCard(String id, int generation) async {
    final render = _cardBoundaries[id]?.currentContext?.findRenderObject();
    if (render is! RenderRepaintBoundary || render.debugNeedsPaint) return;
    try {
      final area = render.size.width * render.size.height;
      final image = await render.toImage(
          pixelRatio: math.min(1, math.sqrt(1500000 / math.max(1, area))));
      if (!mounted || generation != _imageGeneration || _feedbackId != id) {
        image.dispose();
        return;
      }
      setState(() => _feedbackImage = image);
    } catch (_) {/* A lightweight title preview remains available. */}
  }

  void _moveGesture(Offset position) {
    final g = _gesture;
    if (g == null) return;
    final origin = g.card, offset = _local(position) - _local(g.start);
    final target = g.resize
        ? origin.copyWith(
            w: (origin.w + offset.dx / g.unitX)
                .round()
                .clamp(specFor(origin.type).minW, 12 - origin.x),
            h: (origin.h + offset.dy / g.unitY)
                .round()
                .clamp(specFor(origin.type).minH, 6 - origin.y))
        : origin.copyWith(
            page: _controller.page,
            x: (origin.x + offset.dx / g.unitX).round().clamp(0, 12 - origin.w),
            y: (origin.y + offset.dy / g.unitY).round().clamp(0, 6 - origin.h));
    if (!g.resize) {
      _feedbackBounds.value = _cardRect(g, origin).shift(offset);
      _edgeHover(position, g);
    }
    final previous = _pendingTarget;
    if (previous != null &&
        (previous.page, previous.x, previous.y, previous.w, previous.h) ==
            (target.page, target.x, target.y, target.w, target.h)) return;
    _pendingTarget = target;
    _hoverTimer?.cancel();
    if (g.resize) {
      _controller.previewPlacement(target);
    } else {
      final occupied =
          _controller.cards.any((c) => c.id != target.id && c.overlaps(target));
      _hoverTimer = Timer(Duration(milliseconds: occupied ? 150 : 0), () {
        if (_gesture == g) _controller.previewPlacement(target);
      });
    }
  }

  void _edgeHover(Offset position, _CardGesture g) {
    final local = _local(position), origin = _local(g.gridOrigin);
    final insideY =
        local.dy >= origin.dy && local.dy <= origin.dy + g.gridSize.height;
    final direction = !insideY
        ? 0
        : local.dx < origin.dx + Design.px(48)
            ? -1
            : local.dx > origin.dx + g.gridSize.width - Design.px(48)
                ? 1
                : 0;
    if (_edgeDirection == direction) return;
    _edgeTimer?.cancel();
    _edgeDirection = direction;
    final target = _controller.page + direction;
    if (direction == 0 || target < 0 || target >= _controller.pageCount) return;
    _edgeTimer = Timer(const Duration(milliseconds: 450), () async {
      if (_gesture != g) return;
      await _controller.switchPage(target);
      if (!mounted || _gesture != g) return;
      _edgeDirection = 0;
      _moveGesture(_pointers[g.pointer] ?? position);
    });
  }

  void _releaseGesture({bool cancel = false}) {
    final g = _gesture;
    if (g == null) return;
    _gesture = null;
    _hoverTimer?.cancel();
    _edgeTimer?.cancel();
    _edgeDirection = 0;
    _controller.cancelPendingPageSwitch();
    if (!cancel && _pendingTarget != null)
      _controller.previewPlacement(_pendingTarget!);
    final placed = _controller.finishPlacement(cancel: cancel);
    _pendingTarget = null;
    if (g.resize) {
      _clearFeedback();
      return;
    }
    final destination = placed ?? g.card;
    if (destination.page != _controller.page)
      unawaited(_controller.switchPage(destination.page));
    if (MediaQuery.disableAnimationsOf(context)) {
      _clearFeedback();
      return;
    }
    setState(() => _settling = true);
    _feedbackBounds.value = _cardRect(g, destination);
    _settleTimer = Timer(const Duration(milliseconds: 190), _clearFeedback);
  }

  void _clearFeedback() {
    _settleTimer?.cancel();
    _imageGeneration++;
    final image = _feedbackImage;
    _feedbackImage = null;
    _feedbackId = null;
    _settling = false;
    _feedbackBounds.value = null;
    if (image != null)
      WidgetsBinding.instance.addPostFrameCallback((_) => image.dispose());
    if (mounted) setState(() {});
  }

  Widget _dragFeedback() => ValueListenableBuilder<Rect?>(
      valueListenable: _feedbackBounds,
      builder: (context, rect, _) {
        if (rect == null) return const IgnorePointer(child: SizedBox.shrink());
        final s = SurfaceStyle.of(context), card = _gesture?.card;
        return AnimatedPositioned(
            key: const ValueKey('card-drag-feedback'),
            left: rect.left,
            top: rect.top,
            width: rect.width,
            height: rect.height,
            duration:
                _settling ? const Duration(milliseconds: 180) : Duration.zero,
            curve: Curves.easeOutCubic,
            child: IgnorePointer(
                child: AnimatedScale(
                    scale: _settling ? 1 : 1.025,
                    duration: const Duration(milliseconds: 120),
                    child: DecoratedBox(
                        decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(s.radius),
                            boxShadow: [
                              // 暗夜画布近黑，黑投影几乎看不出来；补一圈极淡
                              // 的强调色外晕，卡片才是「抬起来」而不是「变糊了」。
                              if (s.nocturne)
                                BoxShadow(
                                    color: s.accent.withValues(alpha: .20),
                                    blurRadius: 30,
                                    spreadRadius: -4),
                              BoxShadow(
                                  color: s.shadow.withValues(alpha: .35),
                                  blurRadius: 26,
                                  offset: const Offset(0, 12))
                            ]),
                        child: ClipRRect(
                            borderRadius: BorderRadius.circular(s.radius),
                            child: _feedbackImage != null
                                ? ColoredBox(
                                    // 快照是半透明的，必须垫一层不透明底，
                                    // 否则浮起来的卡片会透出下面的卡片。
                                    color: s.snapshotBase,
                                    child: RawImage(
                                        image: _feedbackImage,
                                        // 浮层放大了 2.5%，默认低质量采样会把
                                        // 文字拖出一圈灰边。
                                        filterQuality: FilterQuality.medium,
                                        fit: BoxFit.fill))
                                : GlassSurface(
                                    padding: const EdgeInsets.all(20),
                                    child: Center(
                                        child: Column(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                          UniIcon(
                                              cardSymbol(card?.type ?? 'apps'),
                                              size: 42,
                                              color: s.accent),
                                          const SizedBox(height: 12),
                                          Text(card?.title ?? '移动卡片',
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis),
                                        ]))))))));
      });

  @override
  void dispose() {
    _controller.removeListener(_placementChanged);
    _hoverTimer?.cancel();
    _edgeTimer?.cancel();
    _settleTimer?.cancel();
    _imageGeneration++;
    _feedbackImage?.dispose();
    _feedbackBounds.dispose();
    super.dispose();
  }
}
