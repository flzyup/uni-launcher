import 'dart:async';
import 'package:flutter/material.dart';
import '../model/lyrics.dart';
import '../theme/design_tokens.dart';
import '../theme/launcher_theme.dart';

/// Reused by the card and detail panel; scrolls only on a timestamp change.
class LyricsView extends StatefulWidget {
  final Map<String, dynamic> media;
  final bool compact;
  final int? currentLineMaxLines;
  final int? visibleLines;
  final double? lineHeight, fontSize;
  final TextAlign textAlign;
  const LyricsView(
      {super.key,
      required this.media,
      this.compact = false,
      this.currentLineMaxLines,
      this.visibleLines,
      this.lineHeight,
      this.fontSize,
      this.textAlign = TextAlign.center});
  @override
  State<LyricsView> createState() => _LyricsViewState();
}

class _LyricsViewState extends State<LyricsView> {
  final scroll = ScrollController();
  Timer? timer;
  Lyrics lyrics = const Lyrics([]);
  int active = -1;
  String payload = '';
  bool _tickersEnabled = false;
  String _layoutSignature = '';
  List<double> _lineHeights = const [];
  List<double> _lineOffsets = const [0];
  double get rowHeight => Design.px(widget.lineHeight ?? 36);
  int get visibleLines => widget.visibleLines ?? (widget.compact ? 1 : 3);
  @override
  void initState() {
    super.initState();
    refresh();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final enabled = TickerMode.valuesOf(context).enabled;
    if (enabled == _tickersEnabled) return;
    _tickersEnabled = enabled;
    // A hidden page may have missed native samples. Catch up immediately,
    // without animating through the lyrics that elapsed while it was hidden.
    refresh(reset: enabled);
  }

  @override
  void didUpdateWidget(LyricsView old) {
    super.didUpdateWidget(old);
    refresh();
  }

  void refresh({bool reset = false}) {
    final next = widget.media['lyrics'] is String
        ? widget.media['lyrics'] as String
        : '';
    final changed = payload != next;
    if (changed) {
      payload = next;
      lyrics = Lyrics.parse(next);
      active = -1;
    }
    timer?.cancel();
    timer = null;
    if (!_tickersEnabled) return;
    updateLine(reset: changed || reset);
    if (lyrics.timed &&
        widget.media['playing'] == true &&
        widget.media['positionKnown'] == true)
      timer = Timer.periodic(
          const Duration(milliseconds: 250), (_) => updateLine());
  }

  void updateLine({bool reset = false}) {
    final timeline = MediaTimeline.fromJson(widget.media);
    final next = timeline.known
        ? lyrics.activeAt(timeline.at(DateTime.now().millisecondsSinceEpoch))
        : -1;
    if (next == active && !reset) return;
    if (mounted) setState(() => active = next);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_tickersEnabled || !scroll.hasClients) return;
      final rawTarget = next < 0
          ? 0.0
          : next < _lineOffsets.length
              ? _lineOffsets[next]
              : next * rowHeight;
      final target = rawTarget.clamp(0.0, scroll.position.maxScrollExtent);
      if (reset || MediaQuery.disableAnimationsOf(context)) {
        scroll.jumpTo(target);
      } else {
        scroll.animateTo(target,
            duration: const Duration(milliseconds: 320),
            curve: Curves.easeOutCubic);
      }
    });
  }

  @override
  void dispose() {
    timer?.cancel();
    scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = SurfaceStyle.of(context);
    final count = visibleLines;
    final liveLine = widget.media['lyricLine']?.toString().trim() ?? '';
    if (widget.currentLineMaxLines != null) {
      final maxLines = widget.currentLineMaxLines!.clamp(1, 2);
      final current = liveLine.isNotEmpty
          ? liveLine
          : lyrics.lines.isNotEmpty
              ? lyrics.lines[active < 0 ? 0 : active].text
              : widget.media['lyricsReason']?.toString() ?? '当前音源未提供歌词';
      return Semantics(
          label: '当前歌词',
          child: SizedBox(
              height: rowHeight * maxLines,
              width: double.infinity,
              child: Center(
                  child: Text(current,
                      key: const ValueKey('current-lyric-wrapped'),
                      textAlign: TextAlign.center,
                      softWrap: true,
                      maxLines: maxLines,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: Design.px(widget.fontSize ?? 26),
                          height: 1.2,
                          color: liveLine.isNotEmpty || lyrics.lines.isNotEmpty
                              ? s.accent
                              : s.muted)))));
    }
    if (lyrics.lines.isEmpty && liveLine.isNotEmpty) {
      final lines = count == 1
          ? [liveLine]
          : [
              widget.media['lyricPrevious']?.toString() ?? '',
              liveLine,
              widget.media['lyricNext']?.toString() ?? '',
            ];
      return SizedBox(
          height: rowHeight * count,
          child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              child: Column(
                  key: ValueKey(liveLine),
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    for (var i = 0; i < lines.length; i++)
                      SizedBox(
                          height: rowHeight,
                          width: double.infinity,
                          child: Align(
                              alignment: widget.textAlign == TextAlign.start
                                  ? Alignment.centerLeft
                                  : Alignment.center,
                              child: Text(lines[i],
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  textAlign: widget.textAlign,
                                  style: TextStyle(
                                      fontSize:
                                          Design.px(widget.fontSize ?? 20),
                                      color: (lines.length == 1 || i == 1)
                                          ? s.accent
                                          : s.muted))))
                  ])));
    }
    if (lyrics.lines.isEmpty)
      return SizedBox(
          height: rowHeight * count,
          child: Center(
              child: Text(
                  widget.media['lyricsReason']?.toString() ?? '当前音源未提供歌词',
                  key: const ValueKey('lyrics-empty'),
                  maxLines: count == 1 ? 1 : null,
                  overflow: TextOverflow.ellipsis,
                  textAlign: widget.textAlign,
                  style: TextStyle(
                      fontSize: Design.px(widget.fontSize ?? 19),
                      color: s.muted))));
    return Semantics(
        label: '歌词',
        child: LayoutBuilder(builder: (context, constraints) {
          final fontSize =
              Design.px(widget.fontSize ?? (widget.compact ? 20 : 22));
          final signature =
              '$payload|${constraints.maxWidth}|$fontSize|$rowHeight';
          if (_layoutSignature != signature) {
            final heights = <double>[];
            final offsets = <double>[0.0];
            for (final item in lyrics.lines) {
              final painter = TextPainter(
                  text: TextSpan(
                      text: item.text,
                      style: TextStyle(fontSize: fontSize, height: 1.18)),
                  textDirection: TextDirection.ltr)
                ..layout(maxWidth: constraints.maxWidth);
              final renderedLines = painter
                  .computeLineMetrics()
                  .length
                  .clamp(1, widget.visibleLines ?? 3);
              heights.add(rowHeight * renderedLines);
              offsets.add(offsets.last + heights.last);
            }
            _layoutSignature = signature;
            _lineHeights = heights;
            _lineOffsets = offsets;
          }
          return SizedBox(
              height: rowHeight * count,
              child: ListView.builder(
                key: const ValueKey('lyrics-scroll'),
                controller: scroll,
                padding:
                    EdgeInsets.symmetric(vertical: rowHeight * (count - 1) / 2),
                itemCount: lyrics.lines.length,
                itemBuilder: (context, i) => SizedBox(
                    height: _lineHeights.isEmpty ? rowHeight : _lineHeights[i],
                    child: Align(
                        alignment: widget.textAlign == TextAlign.start
                            ? Alignment.centerLeft
                            : Alignment.center,
                        child: Text(lyrics.lines[i].text,
                            key: ValueKey(
                                'lyric-line-$i-${active == i ? "active" : "idle"}'),
                            softWrap: true,
                            textAlign: widget.textAlign,
                            style: TextStyle(
                                fontSize: fontSize,
                                height: 1.18,
                                color: i == active ? s.accent : s.muted,
                                fontWeight: i == active
                                    ? FontWeight.w500
                                    : FontWeight.w400)))),
              ));
        }));
  }
}
