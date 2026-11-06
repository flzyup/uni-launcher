import 'package:flutter/material.dart';

import '../model/lyric_timeline.dart';
import '../theme/design_tokens.dart';
import '../theme/launcher_theme.dart';

/// One line whose sung part is painted in the highlight colour.
///
/// Two identical text layers are stacked and the top one is clipped to the measured width
/// of [sung]. The clip is a pixel width, not a glyph count, so the edge lands exactly where
/// the last sung glyph ends, at any font size or [MediaQuery.textScalerOf].
///
/// Single line only: a wrapped paragraph cannot be filled left-to-right across its rows, and
/// on the card and the dock a lyric line is one row by design.
class KaraokeText extends StatelessWidget {
  final String text;
  final String sung;
  final TextStyle style;
  final TextStyle sungStyle;
  final TextAlign textAlign;

  const KaraokeText({
    super.key,
    required this.text,
    required this.sung,
    required this.style,
    required this.sungStyle,
    this.textAlign = TextAlign.center,
  });

  @override
  Widget build(BuildContext context) {
    if (text.isEmpty) return const SizedBox.shrink();
    if (sung.isEmpty || !text.startsWith(sung)) return _layer(text, style);
    if (sung == text) return _layer(text, sungStyle);
    return LayoutBuilder(builder: (context, constraints) {
      if (!constraints.hasBoundedWidth) return _layer(text, style);
      final painter = TextPainter(
        text: TextSpan(text: sung, style: style),
        textDirection: Directionality.of(context),
        textAlign: textAlign,
        maxLines: 1,
        textScaler: MediaQuery.textScalerOf(context),
        textWidthBasis: TextWidthBasis.longestLine,
      )..layout(maxWidth: constraints.maxWidth);
      final edge = painter.width;
      painter.dispose();
      return Stack(
        clipBehavior: Clip.hardEdge,
        alignment: Alignment.center,
        children: [
          _layer(text, style),
          ClipRect(
            clipper: _EdgeClipper(edge),
            child: _layer(text, sungStyle),
          ),
        ],
      );
    });
  }

  Widget _layer(String value, TextStyle textStyle) => SizedBox(
        width: double.infinity,
        child: Text(
          value,
          maxLines: 1,
          softWrap: false,
          overflow: TextOverflow.ellipsis,
          textAlign: textAlign,
          style: textStyle,
        ),
      );
}

class _EdgeClipper extends CustomClipper<Rect> {
  final double edge;
  const _EdgeClipper(this.edge);

  @override
  Rect getClip(Size size) {
    final limit = edge < 0 ? 0.0 : (edge > size.width ? size.width : edge);
    return Rect.fromLTWH(0, 0, limit, size.height);
  }

  @override
  bool shouldReclip(_EdgeClipper old) => old.edge != edge;
}

/// Three-row lyric panel driven by a [LyricTimeline] and a playback position.
///
/// The parent owns the clock: it passes the position it already derives from the media
/// snapshot (corrected for pause, speed and seek), so this widget stays stateless and
/// testable. [estimatedKaraoke] is the opt-in guess for plain-LRC documents, where no
/// document knows which syllable is being sung.
class LyricKaraokePanel extends StatelessWidget {
  final LyricTimeline timeline;
  final int positionMs;
  final String emptyReason;
  final double fontSize;
  final double rowHeight;
  final bool estimatedKaraoke;

  const LyricKaraokePanel({
    super.key,
    required this.timeline,
    required this.positionMs,
    this.emptyReason = '当前音源未提供歌词',
    this.fontSize = 26,
    this.rowHeight = 36,
    this.estimatedKaraoke = false,
  });

  @override
  Widget build(BuildContext context) {
    final surface = SurfaceStyle.of(context);
    final size = Design.px(fontSize);
    final row = Design.px(rowHeight);
    final secondary = Design.px(fontSize * 0.78);
    if (timeline.isEmpty) {
      return SizedBox(
        height: row * 3,
        child: Center(
          child: Text(
            emptyReason,
            key: const ValueKey('lyric-karaoke-empty'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: Design.px(fontSize * 0.72), color: surface.muted),
          ),
        ),
      );
    }
    final cursor = timeline.at(positionMs);
    final muted = TextStyle(fontSize: secondary, height: 1.18, color: surface.muted);
    final accent = TextStyle(
      fontSize: size,
      height: 1.18,
      color: surface.accent,
      fontWeight: FontWeight.w600,
    );
    final glow = TextStyle(
      fontSize: size,
      height: 1.18,
      color: surface.accent,
      fontWeight: FontWeight.w600,
      shadows: [Shadow(color: surface.accent.withValues(alpha: 0.45), blurRadius: 12)],
    );

    final rows = <Widget>[];
    void addLine(
      String value,
      TextStyle base, {
      String sung = '',
    }) {
      rows.add(SizedBox(
        height: row,
        child: Align(
          alignment: Alignment.center,
          child: value.isEmpty
              ? const SizedBox.shrink()
              : KaraokeText(
                  text: value,
                  sung: sung,
                  style: base,
                  // Only the active row is ever given a prefix, so the glow layer is
                  // reserved for it; muted rows fall through the empty-prefix path.
                  sungStyle: glow,
                ),
        ),
      ));
    }

    if (cursor.interlude) {
      if (cursor.previous.isNotEmpty) addLine(cursor.previous, muted);
      addLine(cursor.next, accent);
    } else {
      if (cursor.previous.isNotEmpty) addLine(cursor.previous, muted);
      addLine(
        cursor.text,
        accent,
        sung: estimatedKaraoke ? cursor.estimatedSungPrefix : cursor.sungPrefix,
      );
      addLine(cursor.translation.isNotEmpty ? cursor.translation : cursor.next, muted);
    }
    return Semantics(
      label: '歌词',
      child: SizedBox(
        height: row * 3,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: rows,
        ),
      ),
    );
  }
}
