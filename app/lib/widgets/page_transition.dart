import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import '../theme/design_tokens.dart';

/// Changes only at motion boundaries, never on animation ticks.
class DesktopMotionScope extends InheritedWidget {
  final bool moving;
  const DesktopMotionScope(
      {super.key, required this.moving, required super.child});
  static bool movingOf(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<DesktopMotionScope>()
          ?.moving ??
      false;
  @override
  bool updateShouldNotify(DesktopMotionScope oldWidget) =>
      moving != oldWidget.moving;
}

/// A retained workspace with one shared fractional page position. Gesture,
/// settling animation and indicator all consume the same signal. Only the two
/// involved pages paint; transforms never change the cards' layout constraints.
class DesktopPageStack extends StatefulWidget {
  final int page;
  final String effect;
  final List<Widget> children;
  final ValueNotifier<double>? position;
  final ValueChanged<int>? onPageRequested;

  /// 首尾环回（用户 2026-11-14 要求）：在最后一页继续向左、或第一页继续向右时，
  /// 允许**越过边界跟手一小段**（阻尼，最多 [_overscrollLimit] 个页宽），松手后把
  /// 另一端那一页**原地淡入**——不做位移动画，避免"往回翻一屏"的错觉。
  /// 编辑态 / 铺满 / 设置页不传，保持线性翻页。
  final bool wrap;
  const DesktopPageStack(
      {super.key,
      required this.page,
      required this.effect,
      required this.children,
      this.position,
      this.onPageRequested,
      this.wrap = false});
  @override
  State<DesktopPageStack> createState() => DesktopPageStackState();
}

class DesktopPageStackState extends State<DesktopPageStack>
    with TickerProviderStateMixin {
  late final AnimationController _animation;
  late final ValueNotifier<double> _ownPosition;
  ValueNotifier<double> get _position => widget.position ?? _ownPosition;
  late int _fromPage, _toPage;
  Set<int> _painted = {};
  bool _moving = false, _dragging = false;
  double _width = 1, _dragStart = 0, _dragDistance = 0;
  int _anchor = 0;

  /// 环回目标页（**真实索引**：0 或最后一页）。不在环回时为 null。
  int? _wrapTo;

  /// 环回起点页（真实索引），决定"进来的那一页"挂在左边还是右边。
  int? _wrapFromReal;
  bool get _wrapping => _wrapTo != null;

  /// 环回时"进来的那一页"用哪个**虚拟序号**参与平移：
  /// 向前环回（最后一页 → 第一页）挂在 `children.length`，于是它从**右侧**
  /// 跟着手指滑进来；向后环回挂在 -1，从**左侧**滑进来。
  /// 这样位移方向和手指一致，就是设置里那个「平移」效果。
  /// 注意方向要按"从哪绕到哪"判，不能比大小：向前环回是 last → 0，索引更小。
  int get _wrapVirtual {
    if (_wrapTo == null || _wrapFromReal == null) return -1;
    final forward =
        _wrapTo == 0 && _wrapFromReal == widget.children.length - 1;
    return forward ? widget.children.length : -1;
  }
  int _bounded(int page) =>
      widget.children.isEmpty ? 0 : page.clamp(0, widget.children.length - 1);
  bool get _motionDisabled =>
      widget.effect == 'none' ||
      MediaQuery.disableAnimationsOf(context) ||
      widget.children.length < 2;

  @override
  void initState() {
    super.initState();
    _fromPage = _toPage = _bounded(widget.page);
    _painted = {_toPage};
    _ownPosition = ValueNotifier(_toPage.toDouble());
    _animation =
        AnimationController.unbounded(vsync: this, value: _toPage.toDouble())
          ..addListener(_tick)
          ..addStatusListener(_status);
  }

  bool _positionScheduled = false;
  void _tick() {
    // didUpdateWidget may start/jump an animation while the workspace builds.
    // Its sibling indicator must not be dirtied in that build traversal.
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      if (_positionScheduled) return;
      _positionScheduled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _positionScheduled = false;
        if (mounted) _position.value = _animation.value;
      });
    } else {
      _position.value = _animation.value;
    }
  }

  void _status(AnimationStatus status) {
    if (status != AnimationStatus.completed || _dragging || !mounted) return;
    // 环回动画的终点是"虚拟位置"（last+1 或 -1），落位要换算成真实页。
    if (_wrapping) {
      _finishWrap();
      return;
    }
    setState(() {
      _moving = false;
      _fromPage = _toPage;
      _painted = {_toPage};
    });
  }

  @override
  void didUpdateWidget(DesktopPageStack oldWidget) {
    super.didUpdateWidget(oldWidget);
    final target = _bounded(widget.page);
    if (oldWidget.effect != widget.effect || _motionDisabled) {
      _jump(target);
    } else if (oldWidget.page != widget.page && target != _toPage) {
      _settle(target);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_motionDisabled) _jump(_bounded(widget.page));
  }

  void _jump(int target) {
    _animation.stop();
    _dragging = _moving = false;
    _fromPage = _toPage = target;
    _painted = {target};
    _animation.value = target.toDouble();
  }

  void _settle(int target) {
    final current = _position.value;
    _dragging = false;
    _toPage = target;
    if (_motionDisabled || (target - current).abs() < .0001) {
      setState(() => _jump(target));
      return;
    }
    // Rapid reversal keeps the current fractional position instead of jumping
    // back to an old integer page. Distant indicator taps still paint two pages.
    if (!_moving || !_painted.contains(target))
      _fromPage = _bounded(current.round());
    if (_fromPage == target)
      _fromPage = _bounded(current < target ? current.floor() : current.ceil());
    setState(() {
      _moving = true;
      _painted = {_fromPage, target};
    });
    _animation.value = current;
    final distance =
        ((target - current).abs() / math.max(1, (_fromPage - target).abs()))
            .clamp(0.0, 1.0);
    _animation.animateTo(target.toDouble(),
        duration: Duration(milliseconds: (140 + distance * 120).round()),
        curve: Curves.easeOutCubic);
  }

  void dragStart() {
    if (widget.children.length < 2) return;
    _animation.stop();
    _anchor = _bounded(widget.page);
    _dragStart = _position.value;
    _dragDistance = 0;
    _dragging = true;
  }

  void dragUpdate(double delta) {
    if (!_dragging) return;
    _dragDistance += delta;
    if (_motionDisabled) return;
    final last = widget.children.length - 1;
    final low = math.max(0, _anchor - 1).toDouble();
    final high = math.min(last, _anchor + 1).toDouble();
    var next = _dragStart - _dragDistance / _width;
    // 环回：页尾继续向左 → 第一页从右边滑进来；页首继续向右 → 最后一页
    // 从左滑进来。两者都按**平移**处理，位移方向跟手指一致。
    final forwardWrap = widget.wrap && _anchor == last && next > high;
    final backwardWrap = widget.wrap && _anchor == 0 && next < low;
    int? wrapTarget;
    if (forwardWrap) {
      wrapTarget = 0;
      next = math.min(last + 1.0, next);
    } else if (backwardWrap) {
      wrapTarget = last;
      next = math.max(-1.0, next);
    } else {
      next = next.clamp(low, high);
    }
    final neighbour = _bounded(next > _anchor ? _anchor + 1 : _anchor - 1);
    final painted = wrapTarget != null
        ? {_anchor, wrapTarget}
        : {_anchor, neighbour};
    if (!_moving ||
        !setEquals(painted, _painted) ||
        wrapTarget != _wrapTo) {
      setState(() {
        _wrapTo = wrapTarget;
        _wrapFromReal = wrapTarget == null ? null : _anchor;
        _fromPage = _anchor;
        // 位移公式按 `|to - from|` 归一化：环回时目标页的真实索引可能离得很远
        // （最后一页 → 0，三页时差 2），直接拿它当 to 会把位移砍成一半，
        // 手指才动一点另一页就窜进来半屏。这里给一个**相邻的虚拟 to**。
        _toPage = wrapTarget == null
            ? neighbour
            : _anchor + (_anchor == widget.children.length - 1 ? 1 : -1);
        _painted = painted;
        _moving = true;
      });
    }
    _position.value = next;
  }

  void dragEnd(double velocity) {
    if (!_dragging) return;
    final travelled =
        _motionDisabled ? -_dragDistance / _width : _position.value - _anchor;
    final fling = velocity.abs() >= 450 && _dragDistance.abs() >= 18;
    final direction =
        fling ? (velocity < 0 ? 1 : -1) : (travelled >= 0 ? 1 : -1);
    final last = widget.children.length - 1;
    // 已经在环回状态（越界时挂着另一端那一页）：够远或带速度就滑完，否则回弹。
    if (_wrapping) {
      final from = _wrapFromReal ?? _anchor;
      final forward = _wrapTo == 0 && from == last;
      final beyond = forward
          ? _position.value - last
          : (from == 0 ? -_position.value : 0);
      final complete = beyond >= .28 ||
          (fling && (forward ? direction > 0 : direction < 0));
      _completeWrap(complete: complete);
      return;
    }
    final target =
        _bounded(_anchor + (fling || travelled.abs() >= .28 ? direction : 0));
    _settle(target);
    if (target != widget.page) widget.onPageRequested?.call(target);
  }

  void dragCancel() {
    if (!_dragging) return;
    if (_wrapping) {
      _completeWrap(complete: false);
      return;
    }
    _settle(_bounded(widget.page));
  }

  /// 环回收尾：`complete` 为真是"滑完换页"，否则回弹到当前页。
  ///
  /// 两者都是**平移**动画：滑完时把位置推到虚拟终点（last+1 或 -1），
  /// 动画结束后再换成真实页；回弹时把越界那段滑回 0。
  void _completeWrap({required bool complete}) {
    _dragging = false;
    final target = _wrapTo;
    final from = _wrapFromReal;
    if (target == null || from == null) {
      _settle(_bounded(widget.page));
      return;
    }
    if (!complete) {
      // 回弹：撤掉"另一端那一页"，只留当前页滑回原位。
      _wrapTo = null;
      _wrapFromReal = null;
      _painted = {from};
      _toPage = from;
      _settle(from);
      return;
    }
    if (_motionDisabled) {
      _finishWrap();
      return;
    }
    final end = target == 0 && from == widget.children.length - 1
        ? widget.children.length.toDouble()
        : -1.0;
    _moving = true;
    setState(() {});
    _animation.animateTo(end,
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOutCubic);
  }

  void _finishWrap() {
    final target = _wrapTo;
    if (target == null) return;
    _wrapTo = null;
    _wrapFromReal = null;
    if (!mounted) return;
    setState(() => _jump(target));
    if (target != widget.page) widget.onPageRequested?.call(target);
  }

  @override
  void dispose() {
    _animation.dispose();
    _ownPosition.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.children.isEmpty) return const SizedBox.shrink();
    final parentTicker = TickerMode.valuesOf(context).enabled;
    return LayoutBuilder(builder: (context, constraints) {
      _width = constraints.maxWidth;
      final order = [for (var i = 0; i < widget.children.length; i++) i];
      if (!_wrapping && widget.effect == 'depth') {
        // The incoming page covers the receding page in either direction.
        order.remove(_toPage);
        order.add(_toPage);
      }
      // 环回淡入：进来的那一页必须画在最上层，否则被当前页整个盖住，
      // 淡入看不出任何变化（测试里就是这么发现的第一版问题）。
      if (_wrapping) {
        order.remove(_wrapTo!);
        order.add(_wrapTo!);
      }
      return ClipRect(
          child: Stack(fit: StackFit.expand, children: [
        for (final i in order) _motionPage(i, parentTicker),
      ]));
    });
  }

  /// 一页的运动外壳。
  ///
  /// 环回期间两页都钉在原位（`position = i`，不做位移），只让「进来的那一页」
  /// 从 0 淡到 1 盖上来 —— 否则沿用位置动画会出现「往回翻一屏」的错觉。
  Widget _motionPage(int i, bool parentTicker) {
    // 环回时"进来的那一页"用虚拟序号参与平移（挂在当前页的右边或左边），
    // 效果就是设置里的「平移」：跟手滑动，方向与手指一致。
    final wrapping = _wrapping;
    final index = wrapping && i == _wrapTo ? _wrapVirtual : i;
    final page = _PageTransform(
        position: _painted.contains(i)
            ? _position
            : AlwaysStoppedAnimation(i.toDouble()),
        index: index,
        // 环回固定用平移，不跟 depth / zoom 那套（那两套是"翻页"语义，
        // 套在环回上会出现方向错乱）。
        effect: wrapping
            ? 'slide'
            : (_motionDisabled ? 'none' : widget.effect),
        clip: !wrapping,
        from: _fromPage,
        to: _toPage,
        child: RepaintBoundary(
            child: ClipRect(
                key: ValueKey('desktop-motion-frame-$i'),
                child: widget.children[i])));
    return Positioned.fill(
        key: ValueKey('desktop-motion-page-$i'),
        child: _RetainedPage(
            offstage: !_painted.contains(i),
            child: IgnorePointer(
                ignoring: _moving || i != _bounded(widget.page),
                child: ExcludeSemantics(
                    excluding: _moving || i != _bounded(widget.page),
                    child: TickerMode(
                        enabled: parentTicker &&
                            !_moving &&
                            i == _bounded(widget.page),
                        child: DesktopMotionScope(
                            moving: _moving && _painted.contains(i),
                            child: page))))));
  }
}

/// Only these inexpensive wrappers build per frame. The expensive child is the
/// same Widget instance and has its own display list / raster cache boundary.
class _PageTransform extends AnimatedWidget {
  final int index, from, to;
  final String effect;
  final Widget child;

  /// 普通相邻翻页才用「未覆盖裁剪」省绘制；环回时两页都可能是满宽可见，
  /// 裁掉会看着像页面被切了一块。
  final bool clip;
  const _PageTransform(
      {required ValueListenable<double> position,
      this.clip = true,
      required this.index,
      required this.effect,
      required this.from,
      required this.to,
      required this.child})
      : super(listenable: position);
  @override
  Widget build(BuildContext context) {
    final position = (listenable as ValueListenable<double>).value;
    final relative = (index - position) / math.max(1, (to - from).abs());
    final amount = relative.abs().clamp(0.0, 1.0);
    final entering = index == to;
    final offset = switch (effect) {
      'none' || 'fade' => 0.0,
      'depth' when !entering => relative * .22,
      _ => relative,
    };
    final scale = switch (effect) {
      'zoom' => 1 - amount * .08,
      'depth' when !entering => 1 - amount * .08,
      _ => 1.0,
    };
    final opacity = switch (effect) {
      'fade' => 1 - amount,
      _ => 1.0,
    };
    // All wrappers stay mounted when an effect changes or motion ends. Native
    // map textures and card State must never be detached by an animation.
    return ClipRect(
        // Avoid a full-screen alpha buffer and overdraw in layered motion. Slide
        // and depth only differ in how far the outgoing page travels, so the same
        // uncovered-region clip removes the invisible half of its raster work.
        clipper: clip &&
                from != to &&
                index == from &&
                (effect == 'depth' || effect == 'slide')
            ? _UncoveredPageClipper(
                (to - position) / (to - from).abs(), to > from)
            : null,
        child: Transform.translate(
            offset: Offset(offset * Design.px(24), 0),
            child: FractionalTranslation(
                translation: Offset(offset, 0),
                child: Transform.scale(
                    scale: scale,
                    child: Opacity(opacity: opacity, child: child)))));
  }
}

class _UncoveredPageClipper extends CustomClipper<Rect> {
  final double incoming;
  final bool forward;
  const _UncoveredPageClipper(this.incoming, this.forward);
  @override
  Rect getClip(Size size) => forward
      ? Rect.fromLTWH(0, 0, incoming.clamp(0.0, 1.0) * size.width, size.height)
      : Rect.fromLTRB((incoming + 1).clamp(0.0, 1.0) * size.width, 0,
          size.width, size.height);
  @override
  bool shouldReclip(_UncoveredPageClipper old) =>
      incoming != old.incoming || forward != old.forward;
}

/// Warm each page once, then defer parent-driven hidden layout until reveal.
/// Unlike removing a child, this preserves Elements and platform view identity.
/// RenderOffstage still supplies paint, hit-test and semantics isolation.
class _RetainedPage extends Offstage {
  const _RetainedPage({required super.offstage, required super.child});

  @override
  RenderOffstage createRenderObject(BuildContext context) =>
      _RenderRetainedPage(offstage: offstage);
}

class _RenderRetainedPage extends RenderOffstage {
  _RenderRetainedPage({required super.offstage});
  bool _laidOut = false;

  @override
  void performLayout() {
    if (!offstage || !_laidOut) {
      super.performLayout();
      _laidOut = true;
    }
  }
}
