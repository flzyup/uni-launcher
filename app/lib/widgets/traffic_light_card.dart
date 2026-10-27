import 'dart:async';
import 'package:flutter/material.dart';
import '../model/traffic_light.dart';
import '../theme/design_tokens.dart';
import '../theme/launcher_theme.dart';
import 'embedded_navigation.dart';
import 'uni_icon.dart';

/// Shares the outer GlassSurface with all desktop cards. Its second-level timer
/// repaints this card only; it is stopped off-page, in settings and in background.
class TrafficLightCard extends StatefulWidget {
  final TrafficLightSnapshot snapshot;
  final String title, sourceLabel;
  final VoidCallback? onOpenMap;
  final bool editing;
  const TrafficLightCard(
      {super.key,
      required this.snapshot,
      this.title = '红绿灯',
      this.sourceLabel = '高德地图',
      this.onOpenMap,
      this.editing = false});
  @override
  State<TrafficLightCard> createState() => _TrafficLightCardState();
}

class _TrafficLightCardState extends State<TrafficLightCard>
    with WidgetsBindingObserver {
  final clock = Stopwatch();
  Timer? timer;
  int ageAtAnchor = 0;
  int get elapsed => ageAtAnchor + clock.elapsedMilliseconds;
  bool get live =>
      widget.snapshot.available &&
      (widget.snapshot.demo || elapsed < widget.snapshot.ttlMs);
  bool visible = false, foreground = true;

  @override
  void initState() {
    super.initState();
    ageAtAnchor = widget.snapshot.ageMs;
    clock.start();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didUpdateWidget(TrafficLightCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(widget.snapshot, oldWidget.snapshot)) {
      final next = widget.snapshot, previous = oldWidget.snapshot;
      final sameSample = next.sequence == previous.sequence &&
          next.package == previous.package &&
          next.demo == previous.demo;
      ageAtAnchor = sameSample && elapsed > next.ageMs ? elapsed : next.ageMs;
      clock
        ..reset()
        ..start();
    }
    syncTimer();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    visible = TickerMode.valuesOf(context).enabled &&
        EmbeddedContentPolicy.visibleOf(context) &&
        EmbeddedContentPolicy.allowed(context);
    syncTimer();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    foreground = state == AppLifecycleState.resumed;
    syncTimer();
    if (foreground && mounted) setState(() {});
  }

  void syncTimer() {
    timer?.cancel();
    timer = null;
    final data = widget.snapshot;
    if (!visible || !foreground || widget.editing || data.demo || !live) return;
    final left = data.ttlMs - elapsed;
    final nextSecond = 1000 - elapsed % 1000;
    timer = Timer(Duration(milliseconds: left < nextSecond ? left : nextSecond),
        () {
      if (!mounted) return;
      setState(() {});
      syncTimer();
    });
  }

  @override
  void dispose() {
    timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    clock.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = SurfaceStyle.of(context), data = widget.snapshot;
    return LayoutBuilder(builder: (context, box) {
      final short = box.maxHeight < Design.px(220);
      final padding = Design.px(short ? 20 : 28);
      final content = Padding(
          padding: EdgeInsets.all(padding),
          child: !live
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                      _heading(s, small: short),
                      Expanded(
                          child: _waiting(
                              s, data.reason == 'expired' || data.available)),
                    ])
              : _content(s, short, box.maxWidth - padding * 2));
      return Semantics(
          label: '${widget.title}，${data.demo ? '示例数据' : widget.sourceLabel}',
          child: content);
    });
  }

  Widget _heading(SurfaceStyle s, {bool small = false, bool stacked = false}) =>
      Material(
          type: MaterialType.transparency,
          child: InkWell(
              key: const ValueKey('traffic-light-open-map'),
              onTap: widget.editing ? null : widget.onOpenMap,
              borderRadius: BorderRadius.circular(s.controlRadius),
              child: Padding(
                  padding: EdgeInsets.symmetric(vertical: Design.px(4)),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(children: [
                          UniIcon('traffic-light',
                              size: Design.px(small ? 23 : 27),
                              color: s.accent),
                          SizedBox(width: Design.px(10)),
                          Expanded(
                              child: Text(widget.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                      fontSize: Design.px(small ? 22 : 25),
                                      height: 1.2))),
                          if (!stacked) ...[
                            SizedBox(width: Design.px(10)),
                            Expanded(
                                child: Text(_source,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    textAlign: TextAlign.end,
                                    style: TextStyle(
                                        fontSize: Design.px(16),
                                        color: s.muted))),
                          ],
                        ]),
                        if (stacked) ...[
                          SizedBox(height: Design.px(10)),
                          Text(_source,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontSize: Design.px(16), color: s.muted)),
                        ],
                      ]))));

  String get _source => widget.snapshot.demo ? '示例数据' : widget.sourceLabel;

  Widget _content(SurfaceStyle s, bool short, double width) {
    final data = widget.snapshot;
    final elapsed = data.demo ? 0 : this.elapsed;
    if (data.lights.length == 1) {
      return Row(children: [
        Expanded(flex: 4, child: _heading(s, small: true, stacked: true)),
        SizedBox(width: Design.px(20)),
        Expanded(
            flex: 6,
            child: _SignalReading(
                signal: data.lights.single, elapsedMs: elapsed, large: !short)),
      ]);
    }
    final lights = data.lights.take(3).toList(growable: false);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _heading(s, small: true),
      Expanded(
          child:
              Row(key: const ValueKey('traffic-light-directions'), children: [
        for (var i = 0; i < lights.length; i++) ...[
          if (i > 0) SizedBox(width: Design.px(18)),
          Expanded(
              child: _SignalReading(
                  signal: lights[i],
                  elapsedMs: elapsed,
                  large: !short,
                  compact: lights.length == 3)),
        ],
      ])),
    ]);
  }

  Widget _waiting(SurfaceStyle s, bool expired) => FittedBox(
      fit: BoxFit.scaleDown,
      child: Padding(
          padding: EdgeInsets.symmetric(vertical: Design.px(16)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            UniIcon(expired ? 'clock' : 'nav',
                size: Design.px(32), color: s.muted),
            SizedBox(width: Design.px(18)),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(expired ? '信号暂未更新' : '等待路口信号',
                  style: TextStyle(fontSize: Design.px(22))),
              SizedBox(height: Design.px(10)),
              Text(expired ? '倒计时已隐藏' : '有可用信号时自动显示',
                  style: TextStyle(fontSize: Design.px(16), color: s.muted)),
            ]),
          ])));
}

class _SignalReading extends StatelessWidget {
  final TrafficSignal signal;
  final int elapsedMs;
  final bool large, compact;
  const _SignalReading(
      {required this.signal,
      required this.elapsedMs,
      required this.large,
      this.compact = false});
  @override
  Widget build(BuildContext context) {
    final s = SurfaceStyle.of(context);
    final color = switch (signal.lamp) {
      'red' => Color(s.dark ? 0xFFFF8C7F : 0xFFBA392D),
      'green' => Color(s.dark ? 0xFF71E4B4 : 0xFF087550),
      'amber' => Color(s.dark ? 0xFFFFD17D : 0xFF8C6209),
      _ => s.muted,
    };
    final symbol = switch (signal.direction) {
      'left' => 'signal-left',
      'straight' => 'signal-straight',
      'right' => 'signal-left',
      'uturn' => 'signal-uturn',
      _ => 'traffic-light',
    };
    final seconds = signal.remaining(elapsedMs);
    return Semantics(
        label:
            '${signal.directionLabel}，${signal.lampLabel}，${seconds == null ? '倒计时未知' : '$seconds 秒'}',
        excludeSemantics: true,
        child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.center,
            child: Row(
                key: ValueKey('traffic-reading-${signal.direction}'),
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                      width: Design.px(compact ? 64 : (large ? 76 : 64)),
                      height: Design.px(compact ? 64 : (large ? 76 : 64)),
                      decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: color.withValues(alpha: .12),
                          border:
                              Border.all(color: color.withValues(alpha: .25))),
                      child: Center(
                          child: Transform.scale(
                              scaleX: signal.direction == 'right' ? -1 : 1,
                              child: UniIcon(symbol,
                                  size: Design.px(
                                      compact ? 38 : (large ? 42 : 36)),
                                  color: color)))),
                  SizedBox(width: Design.px(compact ? 8 : (large ? 12 : 9))),
                  Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Text(seconds?.toString() ?? '—',
                            key: const ValueKey('traffic-light-seconds'),
                            style: TextStyle(
                                fontSize:
                                    Design.px(compact ? 64 : (large ? 74 : 62)),
                                height: 1.05,
                                color: color,
                                fontFeatures: const [
                                  FontFeature.tabularFigures()
                                ])),
                      ]),
                ])));
  }
}
