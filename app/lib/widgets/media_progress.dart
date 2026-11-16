import 'dart:async';
import 'package:flutter/material.dart';
import '../model/lyrics.dart';
import '../theme/design_tokens.dart';
import '../theme/launcher_theme.dart';

class MediaProgress extends StatefulWidget {
  final Map<String, dynamic> media;
  final ValueChanged<int>? onSeek;

  /// 音乐卡稿子版式（f1 `.mu-prog`）：3px 细轨、11px 时间、右侧显示剩余时间。
  /// 弹层里的播放器仍用默认那一档（4px 轨 + 可拖的拇指 + 17px 时间）。
  final bool dense;

  /// 覆盖轨道厚度 / 拇指半径 / 时间字号；null 走 [dense] 那一档的默认值。
  /// 播放器整屏（稿子 f5 `.pl-pr`）是 4px 轨 + 10px 拇指 + 12.5 字号。
  final double? trackHeight, thumbRadius, labelSize;
  const MediaProgress(
      {super.key,
      required this.media,
      this.onSeek,
      this.dense = false,
      this.trackHeight,
      this.thumbRadius,
      this.labelSize});
  @override
  State<MediaProgress> createState() => _MediaProgressState();
}

class _MediaProgressState extends State<MediaProgress> {
  Timer? timer;
  double? dragging;
  bool _tickersEnabled = false;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final enabled = TickerMode.valuesOf(context).enabled;
    if (enabled == _tickersEnabled) return;
    _tickersEnabled = enabled;
    // Dependency changes already rebuild the timeline at the current time.
    refresh();
  }

  @override
  void didUpdateWidget(MediaProgress old) {
    super.didUpdateWidget(old);
    refresh();
  }

  void refresh() {
    timer?.cancel();
    timer = null;
    if (_tickersEnabled &&
        widget.media['playing'] == true &&
        widget.media['positionKnown'] == true)
      timer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  String time(int ms) =>
      '${(ms ~/ 60000).toString().padLeft(2, '0')}:${(ms ~/ 1000 % 60).toString().padLeft(2, '0')}';
  @override
  Widget build(BuildContext context) {
    final s = SurfaceStyle.of(context),
        t = MediaTimeline.fromJson(widget.media);
    final p = t.at(DateTime.now().millisecondsSinceEpoch);
    final canSeek = widget.onSeek != null &&
        widget.media['canSeek'] == true &&
        t.known &&
        t.durationMs > 0;
    final shown = dragging?.round() ?? p;
    // 稿子右侧是「-00:49」这样的剩余时间；时长未知时退回总时长占位。
    final remaining = t.durationMs > 0
        ? (t.durationMs - shown).clamp(0, t.durationMs)
        : -1;
    return Column(children: [
      SizedBox(
        height: widget.dense ? Design.dz(18) : Design.px(28),
        child: SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: widget.trackHeight ??
                (widget.dense ? Design.dz(3) : Design.px(4)),
            thumbShape: RoundSliderThumbShape(
                enabledThumbRadius:
                    widget.thumbRadius ?? (widget.dense ? 3.5 : 5)),
            overlayShape: RoundSliderOverlayShape(
                overlayRadius: widget.dense ? 10 : 14),
            activeTrackColor: s.accent,
            inactiveTrackColor: s.edge,
            thumbColor: s.accent,
            disabledActiveTrackColor: s.accent,
            disabledInactiveTrackColor: s.edge,
            disabledThumbColor: s.accent,
          ),
          child: Slider(
            key: const ValueKey('media-seek'),
            min: 0,
            max: t.durationMs > 0 ? t.durationMs.toDouble() : 1,
            value: t.known && t.durationMs > 0
                ? shown.toDouble().clamp(0, t.durationMs.toDouble())
                : 0,
            semanticFormatterCallback: (v) => time(v.round()),
            onChanged: canSeek ? (v) => setState(() => dragging = v) : null,
            onChangeEnd: canSeek
                ? (v) {
                    widget.onSeek!(v.round());
                    setState(() => dragging = null);
                  }
                : null,
          ),
        ),
      ),
      SizedBox(height: widget.dense ? Design.dz(6) : Design.px(11)),
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        for (final label in [
          t.known ? time(shown) : '--:--',
          remaining >= 0
              ? '-${time(remaining)}'
              : t.durationMs > 0
                  ? time(t.durationMs)
                  : '--:--'
        ])
          Text(label,
              style: TextStyle(
                  fontSize: widget.labelSize ??
                      (widget.dense ? Design.dz(11) : Design.px(17)),
                  height: 1.2,
                  letterSpacing: widget.dense ? Design.dz(.2) : null,
                  fontFeatures: const [FontFeature.tabularFigures()],
                  color: s.muted))
      ])
    ]);
  }
}
