import 'dart:async';
import 'package:flutter/material.dart';
import '../model/lyrics.dart';
import '../theme/design_tokens.dart';
import '../theme/launcher_theme.dart';

class MediaProgress extends StatefulWidget {
  final Map<String, dynamic> media;
  final ValueChanged<int>? onSeek;
  const MediaProgress({super.key, required this.media, this.onSeek});
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
    return Column(children: [
      SizedBox(
        height: Design.px(28),
        child: SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: Design.px(4),
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
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
      SizedBox(height: Design.px(11)),
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        for (final label in [
          t.known ? time(shown) : '--:--',
          t.durationMs > 0 ? time(t.durationMs) : '--:--'
        ])
          Text(label,
              style: TextStyle(
                  fontSize: Design.px(17), height: 1.2, color: s.muted))
      ])
    ]);
  }
}
