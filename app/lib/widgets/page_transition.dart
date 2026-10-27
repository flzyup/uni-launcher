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
  const DesktopPageStack(
      {super.key,
      required this.page,
      required this.effect,
      required this.children,
      this.position,
      this.onPageRequested});
  @override
  State<DesktopPageStack> createState() => DesktopPageStackState();
}

class DesktopPageStackState extends State<DesktopPageStack>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animation;
  late final ValueNotifier<double> _ownPosition;
  ValueNotifier<double> get _position => widget.position ?? _ownPosition;
  late int _fromPage, _toPage;
  Set<int> _painted = {};
  bool _moving = false, _dragging = false;
  double _width = 1, _dragStart = 0, _dragDistance = 0;
  int _anchor = 0;
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
    if (status == AnimationStatus.completed && !_dragging && mounted) {
      setState(() {
        _moving = false;
        _fromPage = _toPage;
        _painted = {_toPage};
      });
    }
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
    final next = (_dragStart - _dragDistance / _width).clamp(
        math.max(0, _anchor - 1).toDouble(),
        math.min(widget.children.length - 1, _anchor + 1).toDouble());
    final neighbour = _bounded(next > _anchor ? _anchor + 1 : _anchor - 1);
    final painted = {_anchor, neighbour};
    if (!_moving || !setEquals(painted, _painted)) {
      setState(() {
        _fromPage = _anchor;
        _toPage = neighbour;
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
    final target =
        _bounded(_anchor + (fling || travelled.abs() >= .28 ? direction : 0));
    _settle(target);
    if (target != widget.page) widget.onPageRequested?.call(target);
  }

  void dragCancel() {
    if (_dragging) _settle(_bounded(widget.page));
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
    return LayoutBuilder(builder: (context, constraints) {
      _width = constraints.maxWidth;
      final order = [for (var i = 0; i < widget.children.length; i++) i];
      if (widget.effect == 'depth') {
        // The incoming page covers the receding page in either direction.
        order.remove(_toPage);
        order.add(_toPage);
      }
      return ClipRect(
          child: Stack(fit: StackFit.expand, children: [
        for (final i in order)
          Positioned.fill(
              key: ValueKey('desktop-motion-page-$i'),
              child: _RetainedPage(
                  offstage: !_painted.contains(i),
                  child: IgnorePointer(
                      ignoring: _moving || i != _bounded(widget.page),
                      child: ExcludeSemantics(
                          excluding: _moving || i != _bounded(widget.page),
                          child: TickerMode(
                              enabled: !_moving && i == _bounded(widget.page),
                              child: DesktopMotionScope(
                                  moving: _moving && _painted.contains(i),
                                  child: _PageTransform(
                                      position: _painted.contains(i)
                                          ? _position
                                          : AlwaysStoppedAnimation(
                                              i.toDouble()),
                                      index: i,
                                      effect: _motionDisabled
                                          ? 'none'
                                          : widget.effect,
                                      from: _fromPage,
                                      to: _toPage,
                                      child: RepaintBoundary(
                                          child: ClipRect(
                                              key: ValueKey(
                                                  'desktop-motion-frame-$i'),
                                              child:
                                                  widget.children[i]))))))))),
      ]));
    });
  }
}

/// Only these inexpensive wrappers build per frame. The expensive child is the
/// same Widget instance and has its own display list / raster cache boundary.
class _PageTransform extends AnimatedWidget {
  final int index, from, to;
  final String effect;
  final Widget child;
  const _PageTransform(
      {required ValueListenable<double> position,
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
        // Avoid a full-screen alpha buffer and overdraw in layered motion.
        clipper: effect == 'depth' && index == from && from != to
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
