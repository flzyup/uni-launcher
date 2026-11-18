import 'dart:async';
import 'package:flutter/material.dart';
import '../model/traffic_light.dart';
import '../theme/design_tokens.dart';
import '../theme/launcher_theme.dart';
import 'embedded_navigation.dart';
import 'signal_arrow.dart';
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
      // 一格高（4×1 档）放不下卡头：卡高只有 ~100 逻辑像素，卡头那一行就要
      // 吃掉三分之一。这一档直接不画 `_heading`，读数撑满整卡——灯色和倒计时
      // 本身就是这张卡的全部信息，标题只在库里和编辑弹层里出现。
      // 用高度判定而不是 card.h：红绿灯卡拿不到卡片尺寸，而且 4×2 卡被压扁时
      // 同样该退回这一档。
      final bare = box.maxHeight < Design.px(170);
      final short = box.maxHeight < Design.px(220);
      // 稿子：`.tl-hd` 左 26 / 上 20，`.tlg` 左 26 / 下 16。
      final pad = bare
          ? const EdgeInsets.symmetric(horizontal: 14, vertical: 6)
          : short
              ? const EdgeInsets.fromLTRB(20, 12, 20, 12)
              : const EdgeInsets.fromLTRB(26, 18, 26, 16);
      final body = live
          ? _content(s, short, box.maxWidth - pad.horizontal)
          : _waiting(s, data.reason == 'expired' || data.available);
      final content = Padding(
          padding: pad,
          child: bare
              ? body
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                      _heading(s, small: short),
                      Expanded(child: body),
                    ]));
      return Semantics(
          label: '${widget.title}，${data.demo ? '示例数据' : widget.sourceLabel}',
          child: content);
    });
  }

  /// 稿子 `.tl-hd`：21px 竖三灯（当前灯态那颗亮）+ 12px 字距标题 + 右侧 34% 来源。
  ///
  /// 原来是「主题色 25px 大标题 + 16px 来源」，那是正文标题的量级；稿子这行是
  /// 卡片内的小标签，字号只有正文的一半。
  Widget _heading(SurfaceStyle s, {bool small = false}) {
    final data = widget.snapshot;
    final color = _lampColor(s, _primaryLampAt(data.demo ? 0 : elapsed));
    return Material(
        type: MaterialType.transparency,
        child: InkWell(
            key: const ValueKey('traffic-light-open-map'),
            onTap: widget.editing ? null : widget.onOpenMap,
            borderRadius: BorderRadius.circular(s.controlRadius),
            child: Padding(
                padding: EdgeInsets.symmetric(vertical: Design.dz(2)),
                child: Row(children: [
                  _TrafficLightGlyph(size: Design.dz(small ? 19 : 21), lit: color),
                  SizedBox(width: Design.dz(10)),
                  Flexible(
                      child: Text(widget.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: Design.dz(small ? 14 : 15.5),
                              fontWeight: FontWeight.w500,
                              letterSpacing: Design.dz(2.6),
                              color: s.text.withValues(alpha: .62)))),
                  // 右侧不再写来源（原来的「高德地图」）：卡片只有这一处竖向信号，
                  // 来源对开车的人没有信息量，稿子的这一行也只有灯 + 标题
                  // （用户 2026-11-13 实车反馈去掉）。来源仍保留在语义标签里。
                ]))));
  }

  /// 头部那颗小灯亮哪一色：取排好序的第一路（固定顺序下就是左转）。
  String _primaryLampAt(int elapsedMs) {
    final lights = _ordered(widget.snapshot.lights);
    return lights.isEmpty ? 'red' : lights.first.lampAt(elapsedMs);
  }

  /// 路口信号的列顺序：左转 → 直行 → 右转 → 掉头 → 未知，同方向只留第一路。
  ///
  /// 高德的巡航批量包不保证顺序（不同路口解出来的先后会变），而三列并排是给人
  /// 扫一眼的，位置必须固定，否则同一辆车前后两次显示的列会互换。同一方向收到
  /// 多条（同向多车道）时按到达先后留第一条，免得三列全是「左转」。
  static const _directionRank = {
    'left': 0,
    'straight': 1,
    'right': 2,
    'uturn': 3
  };

  static List<TrafficSignal> _ordered(List<TrafficSignal> input) {
    final unique = <String, TrafficSignal>{};
    for (final signal in input) {
      unique.putIfAbsent(signal.direction, () => signal);
    }
    return unique.values.toList(growable: false)
      ..sort((a, b) => (_directionRank[a.direction] ?? 9)
          .compareTo(_directionRank[b.direction] ?? 9));
  }

  Widget _content(SurfaceStyle s, bool short, double width) {
    final data = widget.snapshot;
    final elapsed = data.demo ? 0 : this.elapsed;
    final lights = _ordered(data.lights).take(3).toList(growable: false);
    return Row(
        key: const ValueKey('traffic-light-directions'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < lights.length; i++) ...[
            // 稿子 `.tlg-c+.tlg-c::before`：1px 竖线，上下各留 24%
            if (i > 0)
              Center(
                  child: FractionallySizedBox(
                      heightFactor: .52,
                      child: Container(
                          width: 1,
                          color: s.text.withValues(alpha: .12)))),
            Expanded(
                // 每列留一点内边距：三路信号时两块读数才不至于顶着分隔线
                // （稿子只给了两列，三列是压缩档，需要额外呼吸位）。
                child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: Design.dz(6)),
                    child: Center(
                        child: _SignalReading(
                            signal: lights[i],
                            elapsedMs: elapsed,
                            large: !short,
                            compact: lights.length == 3)))),
          ],
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

/// 稿子 `.tlg-c`：左边一颗「灯珠圆环」（66 圆、5.5 描边、12% 同色底、外发光、
/// 内部 40px 方向箭头取正文色），右边 64px 倒计时取灯色。
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
    final seconds = signal.remaining(elapsedMs);
    // 绿灯最后 3 秒按黄灯画（红灯/未知不动，没倒计时也不切），见 TrafficSignal.lampAt。
    final color = _lampColor(s, signal.lampAt(elapsedMs));
    final arrow = Design.dz(compact ? 34 : 40);
    final ring = compact ? 56.0 : (large ? 66.0 : 60.0);
    return Semantics(
        label:
            '${signal.directionLabel}，${signal.lampLabelAt(elapsedMs)}，${seconds == null ? '倒计时未知' : '$seconds 秒'}',
        excludeSemantics: true,
        child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.center,
            child: Row(
                key: ValueKey('traffic-reading-${signal.direction}'),
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 稿子 `.rw .ring`：5.5 描边 + 同色底，`.rw::before` 是环外一圈
                  // 柔光。用一个圆形盒子一次画完：圈内是**均匀**的同色底（以前叠
                  // 了一层 radial 热点，中间亮、靠环边淡，实机像一圈脏印）。
                  //
                  // 两套皮肤的取法不一样，因为「白箭头」只在一侧说得通：
                  // - 暗夜：淡底 + 亮环 + 白箭头（稿子原样）。灯珠太扎眼，环色压到
                  //   88%、外发光只留一点点（用户 2026-11-13 反馈「有点亮」）。
                  // - 浅色：白箭头需要一点底子才看得清，圈内取 45% 同色底——
                  //   比实心灯珠淡，又不至于让白箭头浮在空白上（72% 太深、18% 太浅，
                  //   2026-11-13 用户对着三版选了 45%）。
                  Container(
                      key: ValueKey('traffic-ring-${signal.direction}'),
                      width: Design.dz(ring),
                      height: Design.dz(ring),
                      decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: color.withValues(alpha: s.dark ? .10 : .45),
                          border: Border.all(
                              color: s.dark
                                  ? color.withValues(alpha: .88)
                                  : color,
                              width: Design.dz(compact ? 4.6 : 5.5)),
                          boxShadow: [
                            BoxShadow(
                                color: color.withValues(alpha: s.dark ? .12 : .16),
                                blurRadius: Design.dz(s.dark ? 10 : 12))
                          ]),
                      child: Center(
                          child: SignalArrowPaths.of(signal.direction) == null
                              ? UniIcon('traffic-light',
                                  size: arrow, color: Colors.white)
                              : SignalArrow(
                                  direction: signal.direction,
                                  size: arrow,
                                  color: Colors.white))),
                  SizedBox(width: Design.dz(compact ? 10 : 16)),
                  Text(seconds?.toString() ?? '—',
                      key: const ValueKey('traffic-light-seconds'),
                      style: TextStyle(
                          fontSize: Design.dz(
                              seconds == null ? (compact ? 26 : 28) : (compact ? 46 : 64)),
                          height: 1,
                          fontWeight: FontWeight.w400,
                          letterSpacing: Design.dz(-.6),
                          color: seconds == null
                              ? s.text.withValues(alpha: .35)
                              : color,
                          fontFeatures: const [FontFeature.tabularFigures()])),
                ])));
  }
}

/// 头部那颗竖三灯：22×22 视口，灯壳描边 28% 墨色，中间那颗按当前灯态点亮。
class _TrafficLightGlyph extends StatelessWidget {
  final double size;
  final Color lit;
  const _TrafficLightGlyph({required this.size, required this.lit});
  @override
  Widget build(BuildContext context) {
    final s = SurfaceStyle.of(context);
    return SizedBox.square(
        dimension: size,
        child: CustomPaint(painter: _TrafficLightGlyphPainter(s, lit)));
  }
}

class _TrafficLightGlyphPainter extends CustomPainter {
  final SurfaceStyle s;
  final Color lit;
  _TrafficLightGlyphPainter(this.s, this.lit);
  @override
  void paint(Canvas canvas, Size size) {
    final k = size.width / 22;
    canvas.scale(k);
    final shell = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = s.text.withValues(alpha: .38);
    canvas.drawRRect(
        RRect.fromRectAndRadius(
            const Rect.fromLTWH(7.6, 2.4, 8.8, 17.2), const Radius.circular(4.4)),
        shell);
    final dim = Paint()..color = s.text.withValues(alpha: .20);
    final bright = Paint()..color = lit;
    canvas.drawCircle(const Offset(12, 6.6), 1.85, bright);
    canvas.drawCircle(const Offset(12, 11), 1.85, dim);
    canvas.drawCircle(const Offset(12, 15.4), 1.85, dim);
  }

  @override
  bool shouldRepaint(covariant _TrafficLightGlyphPainter old) =>
      old.lit != lit || old.s.text != s.text;
}

/// 灯态 → 颜色。深色皮肤用亮一档（暗底上 100% 描边才够跳），浅色用稿子的深一档。
Color _lampColor(SurfaceStyle s, String lamp) => switch (lamp) {
      'red' => Color(s.dark ? 0xFFFF8C7F : 0xFFC8453E),
      'green' => Color(s.dark ? 0xFF71E4B4 : 0xFF2A8F62),
      'amber' => Color(s.dark ? 0xFFFFD17D : 0xFFC09122),
      _ => s.text.withValues(alpha: .5),
    };
