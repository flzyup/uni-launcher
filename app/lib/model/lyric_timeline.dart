import 'dart:convert';

/// A lyric document with optional per-word timing.
///
/// The native side resolves one document per track and ships it across the platform
/// channel as a single JSON string (`media['lyricTimeline']`). Everything that has to
/// happen sixty times a second — finding the active line, splitting sung text from the
/// word being sung, deciding where the fill edge sits — happens here, in Dart, from the
/// playback clock the card already models. No per-frame channel traffic.
///
/// Shape of the payload, produced by `LyricTimeline.toJson()` on the Android side:
///
/// ```json
/// {"v":1,"lines":[{"t":1000,"d":2000,"x":"你好世界","tr":"第一行",
///                  "w":[[1000,500,"你"],[1500,500,"好"]]}]}
/// ```
class LyricWord {
  final int startMs;
  final int durationMs;
  final String text;
  const LyricWord(this.startMs, this.durationMs, this.text);
}

class LyricLine {
  final int timeMs;
  final int durationMs;
  final String text;
  final String translation;
  final String romaji;
  final List<LyricWord> words;
  const LyricLine({
    required this.timeMs,
    this.durationMs = 0,
    this.text = '',
    this.translation = '',
    this.romaji = '',
    this.words = const [],
  });

  bool get wordTimed => words.isNotEmpty;

  /// End of this line; a line without a duration holds the screen for five seconds.
  int get endMs => durationMs > 0 ? timeMs + durationMs : timeMs + LyricTimeline.holdMs;
}

/// One row of the scrolling window; [offset] is relative to the active line.
class LyricNearby {
  final int offset;
  final String text;
  final String translation;
  final String romaji;
  final int timeMs;
  final int durationMs;
  final bool interlude;
  const LyricNearby(
    this.offset,
    this.text,
    this.translation,
    this.romaji,
    this.timeMs,
    this.durationMs, {
    this.interlude = false,
  });
}

/// The frame the renderer needs. Mirrors `LyricTimeline.Cursor` on the Java side.
class LyricCursor {
  final String previous;
  final String text;
  final String translation;
  final String next;

  /// A break long enough to be intentional: hold no line, the display shows a marker.
  final bool interlude;
  final bool wordTimed;

  /// Words already sung in this line, in order.
  final String completed;

  /// The word being sung right now, or `''` between words.
  final String currentWord;

  /// The current word runs to the end of the line, so the fill must not stall on it.
  final bool trailingWord;
  final int lineStartMs;
  final int lineDurationMs;
  final int wordStartMs;
  final int wordDurationMs;

  /// 0..1000 fill of the current word.
  final int wordProgressPermille;

  /// Milliseconds into the current line, -1 when there is no line.
  final int elapsedMs;
  final List<LyricNearby> nearby;

  const LyricCursor({
    this.previous = '',
    this.text = '',
    this.translation = '',
    this.next = '',
    this.interlude = false,
    this.wordTimed = false,
    this.completed = '',
    this.currentWord = '',
    this.trailingWord = false,
    this.lineStartMs = -1,
    this.lineDurationMs = 0,
    this.wordStartMs = -1,
    this.wordDurationMs = 0,
    this.wordProgressPermille = 0,
    this.elapsedMs = -1,
    this.nearby = const [],
  });

  static const empty = LyricCursor();

  /// The part of [text] that should be painted in the highlight colour.
  ///
  /// Only word timing earns a fill. A plain-LRC document has no idea which syllable is
  /// being sung, so it highlights the whole line and lets [estimatedSungPrefix] opt into
  /// the guess instead of pretending the guess is data.
  String get sungPrefix => wordTimed ? _songPrefix : '';

  /// Even split across the line duration, for the opt-in "estimated karaoke" setting.
  String get estimatedSungPrefix {
    if (wordTimed) return _songPrefix;
    if (text.isEmpty || lineDurationMs <= 0 || elapsedMs <= 0) return '';
    final count = _codePoints(text);
    final ratio = _clamp01(elapsedMs / lineDurationMs);
    return _takeCodePoints(text, (ratio * count).floor());
  }

  /// Position inside the line, 0..1, or -1 when unknown.
  double get lineProgress01 {
    if (!wordTimed || lineStartMs < 0 || lineDurationMs <= 0 || elapsedMs <= 0) return -1;
    return _clamp01(elapsedMs / lineDurationMs);
  }

  static double _clamp01(double value) => value < 0 ? 0 : (value > 1 ? 1 : value);

  String get _songPrefix {
    if (currentWord.isEmpty) return completed;
    if (trailingWord) return completed + currentWord;
    final count = _codePoints(currentWord);
    if (count == 0) return completed;
    // Proportional inside one word: a CJK word is one glyph (exact), a Latin word divides
    // its letters, the same approximation every karaoke renderer uses.
    final permille = wordProgressPermille <= 0
        ? 0
        : (wordProgressPermille >= 1000 ? 1000 : wordProgressPermille);
    final taken = (permille * count + 999) ~/ 1000;
    return completed + _takeCodePoints(currentWord, taken);
  }

  static int _codePoints(String value) => value.runes.length;

  static String _takeCodePoints(String value, int count) {
    if (count <= 0) return '';
    final runes = value.runes;
    if (count >= runes.length) return value;
    return String.fromCharCodes(runes.take(count));
  }
}

class LyricTimeline {
  static const int holdMs = 5000;
  static const int minInterludeMs = 5000;
  static const int maxLines = 4000;
  static const int maxTextLength = 4096;

  final List<LyricLine> lines;
  const LyricTimeline(this.lines);

  static const empty = LyricTimeline(<LyricLine>[]);

  bool get isEmpty => lines.isEmpty;
  int get lineCount => lines.length;
  bool get hasWordTiming => lines.any((line) => line.wordTimed);
  bool get hasTranslation => lines.any((line) => line.translation.isNotEmpty);

  /// Parses the payload the native timeline produces. Unrecognised input is empty.
  factory LyricTimeline.parse(Object? payload) {
    if (payload is! String || payload.isEmpty || payload.length > 2000000) {
      return empty;
    }
    Object? decoded;
    try {
      decoded = jsonDecode(payload);
    } catch (_) {
      return empty;
    }
    if (decoded is! Map) return empty;
    final raw = decoded['lines'];
    if (raw is! List) return empty;
    final out = <LyricLine>[];
    for (final item in raw.take(maxLines)) {
      if (item is! Map) continue;
      final text = _text(item['x']);
      final words = <LyricWord>[];
      final rawWords = item['w'];
      if (rawWords is List) {
        for (final entry in rawWords) {
          if (entry is! List || entry.length < 3) continue;
          words.add(LyricWord(
            _int(entry[0]),
            _int(entry[1]),
            _text(entry[2]),
          ));
        }
      }
      if (text.isEmpty && words.isEmpty) continue;
      out.add(LyricLine(
        timeMs: _int(item['t']),
        durationMs: _int(item['d']),
        text: text,
        translation: _text(item['tr']),
        romaji: _text(item['ro']),
        words: words,
      ));
    }
    if (out.isEmpty) return empty;
    out.sort((a, b) => a.timeMs.compareTo(b.timeMs));
    return LyricTimeline(List<LyricLine>.unmodifiable(out));
  }

  /// Index of the line active at [positionMs], or -1 before the first line.
  int indexAt(int positionMs) {
    var low = 0;
    var high = lines.length;
    while (low < high) {
      final mid = (low + high) >> 1;
      if (lines[mid].timeMs <= positionMs) {
        low = mid + 1;
      } else {
        high = mid;
      }
    }
    return low - 1;
  }

  /// Everything the renderer needs for one frame at [positionMs].
  LyricCursor at(int positionMs) {
    if (lines.isEmpty) return LyricCursor.empty;
    final at = positionMs < 0 ? 0 : positionMs;
    final index = indexAt(at);
    final line = index >= 0 ? lines[index] : null;
    final before = index > 0 ? lines[index - 1] : null;
    final after = index + 1 < lines.length ? lines[index + 1] : null;

    if (line == null) {
      if (after == null) return LyricCursor.empty;
      if (after.timeMs >= minInterludeMs) {
        return LyricCursor(
          next: after.text,
          interlude: true,
          lineStartMs: 0,
          lineDurationMs: after.timeMs,
          nearby: _window(-1, 0, after.timeMs),
        );
      }
    } else if (after != null) {
      final gap = after.timeMs - line.endMs;
      if (gap >= minInterludeMs && at >= line.endMs) {
        return LyricCursor(
          previous: line.text,
          translation: line.translation,
          next: after.text,
          interlude: true,
          lineStartMs: line.endMs,
          lineDurationMs: gap,
          nearby: _window(index, line.endMs, gap),
        );
      }
    }

    var completed = '';
    var currentWord = '';
    var trailing = false;
    var wordStart = -1;
    var wordDuration = 0;
    var progress = 0;
    if (line != null && line.wordTimed) {
      final sung = StringBuffer();
      for (var i = 0; i < line.words.length; i++) {
        final word = line.words[i];
        if (at < word.startMs) break;
        if (word.durationMs > 0 && at < word.startMs + word.durationMs) {
          currentWord = word.text;
          wordStart = word.startMs;
          wordDuration = word.durationMs;
          final raw = (at - word.startMs) * 1000 ~/ word.durationMs;
          progress = raw < 0 ? 0 : (raw > 1000 ? 1000 : raw);
          trailing = _isTrailing(line.words, i);
          break;
        }
        sung.write(word.text);
      }
      completed = sung.toString();
    }

    final duration = line == null
        ? 0
        : line.durationMs > 0
            ? line.durationMs
            : after != null
                ? after.timeMs - line.timeMs
                : holdMs;
    return LyricCursor(
      previous: before?.text ?? '',
      text: line?.text ?? '',
      translation: line?.translation ?? '',
      next: after?.text ?? '',
      wordTimed: line?.wordTimed ?? false,
      completed: completed,
      currentWord: currentWord,
      trailingWord: trailing,
      lineStartMs: line?.timeMs ?? -1,
      lineDurationMs: duration < 0 ? 0 : duration,
      wordStartMs: wordStart,
      wordDurationMs: wordDuration,
      wordProgressPermille: progress,
      elapsedMs: line == null ? -1 : at - line.timeMs,
      nearby: _window(index, -1, 0),
    );
  }

  /// A long word that only runs into punctuation carries the rest of the line: filling it
  /// progressively would stall the sweep on a comma. A genuinely final word keeps its own
  /// timing, because its duration already covers the tail.
  static bool _isTrailing(List<LyricWord> words, int index) {
    final word = words[index];
    if (word.durationMs < 1000 || _onlyPunctuation(word.text)) return false;
    for (var i = index + 1; i < words.length; i++) {
      final next = words[i].text;
      if (next.trim().isNotEmpty) return _onlyPunctuation(next);
    }
    return false;
  }

  static bool _onlyPunctuation(String value) {
    if (value.trim().isEmpty) return true;
    for (final rune in value.runes) {
      final char = String.fromCharCode(rune);
      if (RegExp(r'[\s\p{P}\p{S}]', unicode: true).hasMatch(char)) continue;
      return false;
    }
    return true;
  }

  List<LyricNearby> _window(int index, int interludeStartMs, int interludeDurationMs) {
    if (index < 0) return const [];
    final out = <LyricNearby>[];
    final first = index - 3 < 0 ? 0 : index - 3;
    for (var i = first; i <= index; i++) {
      final line = lines[i];
      out.add(LyricNearby(i - index, line.text, line.translation, line.romaji, line.timeMs,
          line.durationMs));
    }
    if (interludeDurationMs > 0) {
      out.add(LyricNearby(0, '', '', '', interludeStartMs, interludeDurationMs,
          interlude: true));
    }
    final last = index + 3 > lines.length - 1 ? lines.length - 1 : index + 3;
    for (var i = index + 1; i <= last; i++) {
      final line = lines[i];
      out.add(LyricNearby(i - index, line.text, line.translation, line.romaji, line.timeMs,
          line.durationMs));
    }
    return List<LyricNearby>.unmodifiable(out);
  }

  static int _int(Object? value) => value is num ? value.toInt() : 0;

  static String _text(Object? value) {
    if (value is! String) return '';
    final trimmed = value.trimRight();
    return trimmed.length > maxTextLength
        ? trimmed.substring(0, maxTextLength)
        : trimmed;
  }

  int qualityScore() => lines.fold(
        0,
        (sum, line) =>
            sum +
            (line.wordTimed ? 4 : 0) +
            (line.translation.isNotEmpty ? 2 : 0) +
            (line.romaji.isNotEmpty ? 2 : 0),
      );
}
