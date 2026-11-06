package xyz.i4o.uni.launcher.integration.lyrics;

import org.json.JSONArray;
import org.json.JSONObject;

import java.util.ArrayList;
import java.util.Collections;
import java.util.Iterator;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.TreeMap;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

/**
 * A lyric document with optional per-word timing.
 *
 * <p>Three shapes arrive from the catalogues and this class folds all of them into one
 * timeline:
 *
 * <ul>
 *   <li>plain LRC ({@code [01:02.34]text}) — line timing only;</li>
 *   <li>enhanced LRC / YRC ({@code [start,duration](wordStart,wordDuration,0)text}) —
 *       per-word timing, which is what the karaoke fill needs;</li>
 *   <li>a separate translation or romanisation document, aligned back onto the main
 *       line by text first and by timestamp second.</li>
 * </ul>
 *
 * <p>Nothing here touches the network, the clock, or a Context, so the whole pipeline is
 * reachable from a JVM unit test. The Flutter side receives {@link #toJson()} once per
 * track; {@link Cursor} is only needed where lyrics are painted from Java (the dock
 * overlay) or compared in tests.
 */
public final class LyricTimeline {
    /** A pause with no line before the next one is announced as an interlude. */
    static final long MIN_INTERLUDE_MS = 5000;
    /** A line without a duration holds the screen this long. */
    static final long PLAIN_LINE_HOLD_MS = 5000;
    /** Translation documents sometimes carry a slightly shifted copy of the same lines. */
    private static final long TEXT_MATCH_SLACK_MS = 5000;
    private static final long NEAR_TIME_TRANSLATION_MS = 2500;
    private static final long NEAR_TIME_ROMAJI_MS = 500;

    private static final Pattern TIME_TAG =
            Pattern.compile("\\[(\\d{1,3}):(\\d{2})(?:[.:](\\d{1,3}))?]");
    private static final Pattern YRC_LINE = Pattern.compile("^\\[(\\d+),(\\d+)](.*)$");
    private static final Pattern YRC_WORD = Pattern.compile("\\((\\d+),(\\d+),\\d+\\)");
    private static final Pattern OFFSET_TAG =
            Pattern.compile("(?im)^\\s*\\[offset:\\s*([+-]?\\d+)\\s*]\\s*$");

    public static final LyricTimeline EMPTY = new LyricTimeline(Collections.<Line>emptyList());

    private final List<Line> lines;

    private LyricTimeline(List<Line> lines) {
        this.lines = lines;
    }

    // ---- model ----

    public static final class Word {
        public final long startMs;
        public final long durationMs;
        public final String text;

        public Word(long startMs, long durationMs, String text) {
            this.startMs = Math.max(0, startMs);
            this.durationMs = Math.max(0, durationMs);
            this.text = text == null ? "" : text;
        }
    }

    public static final class Line {
        public final long timeMs;
        public final long durationMs;
        public final String text;
        public final String translation;
        public final String romaji;
        public final List<Word> words;

        public Line(long timeMs, long durationMs, String text, String translation, String romaji,
                    List<Word> words) {
            this.timeMs = Math.max(0, timeMs);
            this.durationMs = Math.max(0, durationMs);
            this.text = text == null ? "" : text;
            this.translation = translation == null ? "" : translation;
            this.romaji = romaji == null ? "" : romaji;
            this.words = words == null || words.isEmpty()
                    ? Collections.<Word>emptyList()
                    : Collections.unmodifiableList(new ArrayList<>(words));
        }

        boolean wordTimed() {
            return !words.isEmpty();
        }

        /** End of this line, used to detect an interlude before the next one. */
        long endMs() {
            if (durationMs > 0) return timeMs + durationMs;
            return timeMs + PLAIN_LINE_HOLD_MS;
        }
    }

    /** The frame the renderer needs: everything is derived, nothing is scheduled. */
    public static final class Cursor {
        public static final Cursor EMPTY = new Cursor("", "", "", "", false, false, "", "", false,
                -1, 0, -1, 0, 0, Collections.<Nearby>emptyList());

        public final String previous;
        public final String text;
        public final String translation;
        public final String next;
        public final boolean interlude;
        public final boolean wordTimed;
        /** Words already sung in this line, in order. */
        public final String completed;
        /** The word being sung right now, or "" between words. */
        public final String currentWord;
        /** The current word runs to the end of the line; a karaoke sweep must not stall. */
        public final boolean trailingWord;
        public final long lineStartMs;
        public final long lineDurationMs;
        public final long wordStartMs;
        public final long wordDurationMs;
        /** 0..1000 fill of the current word. */
        public final int wordProgressPermille;
        public final List<Nearby> nearby;

        Cursor(String previous, String text, String translation, String next, boolean interlude,
               boolean wordTimed, String completed, String currentWord, boolean trailingWord,
               long lineStartMs, long lineDurationMs, long wordStartMs, long wordDurationMs,
               int wordProgressPermille, List<Nearby> nearby) {            this.previous = previous;
            this.text = text;
            this.translation = translation;
            this.next = next;
            this.interlude = interlude;
            this.wordTimed = wordTimed;
            this.completed = completed;
            this.currentWord = currentWord;
            this.trailingWord = trailingWord;
            this.lineStartMs = lineStartMs;
            this.lineDurationMs = lineDurationMs;
            this.wordStartMs = wordStartMs;
            this.wordDurationMs = wordDurationMs;
            this.wordProgressPermille = wordProgressPermille;
            this.nearby = nearby;
        }

        /**
         * The part of {@link #text} that must be painted in the highlight colour.
         *
         * <p>Empty when the document has no word timing: a plain LRC knows nothing about
         * which syllable is being sung, so the whole line is highlighted instead of faking a
         * fill. This is the single definition both the Java cast window and the Flutter card
         * use, which is why it lives on the model rather than in a renderer.
         */
        public String sungPrefix() {
            if (!wordTimed) return "";
            if (currentWord.isEmpty()) return completed;
            if (trailingWord) return completed + currentWord;
            int count = currentWord.codePointCount(0, currentWord.length());
            if (count == 0) return completed;
            int permille = Math.max(0, Math.min(1000, wordProgressPermille));
            int taken = (permille * count + 999) / 1000;
            return completed + takeCodePoints(currentWord, taken);
        }

        private static String takeCodePoints(String value, int count) {
            if (count <= 0) return "";
            int available = value.codePointCount(0, value.length());
            if (count >= available) return value;
            return value.substring(0, value.offsetByCodePoints(0, count));
        }
    }

    /** One row of the scrolling window; {@code offset} is relative to the active line. */
    public static final class Nearby {
        public final int offset;
        public final String text;
        public final String translation;
        public final String romaji;
        public final long timeMs;
        public final long durationMs;
        public final boolean interlude;

        public Nearby(int offset, String text, String translation, String romaji, long timeMs,
                      long durationMs, boolean interlude) {
            this.offset = offset;
            this.text = text == null ? "" : text;
            this.translation = translation == null ? "" : translation;
            this.romaji = romaji == null ? "" : romaji;
            this.timeMs = timeMs;
            this.durationMs = durationMs;
            this.interlude = interlude;
        }
    }

    // ---- construction ----

    public static LyricTimeline fromLines(List<Line> lines) {
        if (lines == null || lines.isEmpty()) return EMPTY;
        TreeMap<Long, Line> byTime = new TreeMap<>();
        for (Line line : lines) byTime.put(line.timeMs, line);
        return new LyricTimeline(
                Collections.unmodifiableList(new ArrayList<>(byTime.values())));
    }

    /**
     * Fold the documents a catalogue returned into one timeline.
     *
     * @param lrc         plain LRC, the fallback when there is no word timing
     * @param translation translated LRC, timestamps aligned with {@code lrc}
     * @param yrc         word-timed lyrics; when present it wins over {@code lrc}
     * @param romaji      romanised LRC (kana/romaja), aligned like the translation
     */
    public static LyricTimeline parse(String lrc, String translation, String yrc, String romaji) {
        long offset = offsetOf(yrc, lrc, translation, romaji);
        TreeMap<Long, String> plain = timedLines(lrc, offset);
        TreeMap<Long, String> translated = timedLines(translation, offset);
        TreeMap<Long, String> romanised = timedLines(romaji, offset);
        List<Line> words = wordTimedLines(yrc, plain, translated, romanised, offset);
        if (!words.isEmpty()) {
            return new LyricTimeline(Collections.unmodifiableList(words));
        }
        if (plain.isEmpty()) return EMPTY;
        List<Line> out = new ArrayList<>(plain.size());
        for (Map.Entry<Long, String> entry : plain.entrySet()) {
            long at = entry.getKey();
            out.add(new Line(at, 0, entry.getValue(), nearest(translated, at, 500),
                    nearest(romanised, at, 500), Collections.<Word>emptyList()));
        }
        return new LyricTimeline(Collections.unmodifiableList(out));
    }

    /** Accepts a bare enhanced-LRC body ({@code [start,dur](wordStart,dur,0)text}). */
    public static LyricTimeline parseEnhanced(String enhanced) {
        return parse("", "", enhanced, "");
    }

    private static long offsetOf(String... documents) {
        for (String document : documents) {
            if (document == null) continue;
            Matcher matcher = OFFSET_TAG.matcher(document);
            if (!matcher.find()) continue;
            try {
                return Long.parseLong(matcher.group(1));
            } catch (NumberFormatException ignored) {
                return 0;
            }
        }
        return 0;
    }

    private static TreeMap<Long, String> timedLines(String document, long offset) {
        TreeMap<Long, String> out = new TreeMap<>();
        if (document == null || document.isEmpty()) return out;
        for (String raw : document.split("\\r?\\n")) {
            Matcher matcher = TIME_TAG.matcher(raw);
            List<Long> stamps = new ArrayList<>(2);
            int textStart = -1;
            while (matcher.find()) {
                stamps.add(Math.max(0, toMillis(matcher.group(1), matcher.group(2),
                        matcher.group(3)) + offset));
                textStart = matcher.end();
            }
            if (stamps.isEmpty() || textStart < 0) continue;
            // A metadata line such as "[ar:someone]" leaves no text behind.
            String text = raw.substring(textStart).trim();
            if (text.isEmpty()) continue;
            for (Long stamp : stamps) out.put(stamp, text);
        }
        return out;
    }

    private static List<Line> wordTimedLines(String yrc, TreeMap<Long, String> plain,
                                            TreeMap<Long, String> translated,
                                            TreeMap<Long, String> romanised, long offset) {
        List<Line> out = new ArrayList<>();
        if (yrc == null || yrc.isEmpty()) return out;
        for (String raw : yrc.split("\\r?\\n")) {
            Matcher line = YRC_LINE.matcher(raw.trim());
            if (!line.matches()) continue;
            long start = Math.max(0, parseLong(line.group(1)) + offset);
            long duration = Math.max(0, parseLong(line.group(2)));
            String body = line.group(3);
            Matcher word = YRC_WORD.matcher(body);
            List<Word> words = new ArrayList<>();
            int previousEnd = -1;
            long wordStart = -1;
            long wordDuration = 0;
            while (word.find()) {
                if (previousEnd >= 0) {
                    words.add(new Word(wordStart, wordDuration,
                            body.substring(previousEnd, word.start())));
                }
                wordStart = Math.max(0, parseLong(word.group(1)) + offset);
                wordDuration = Math.max(0, parseLong(word.group(2)));
                previousEnd = word.end();
            }
            if (previousEnd < 0) continue;
            words.add(new Word(wordStart, wordDuration, body.substring(previousEnd)));
            trimWordEdges(words);
            StringBuilder joined = new StringBuilder();
            for (Word item : words) joined.append(item.text);
            String text = joined.toString();
            if (text.isEmpty()) continue;
            String translation = alignedTranslation(plain, translated, start, text);
            String romaji = nearest(romanised, start, NEAR_TIME_ROMAJI_MS);
            out.add(new Line(start, duration, text, translation, romaji, words));
        }
        return out;
    }

    /** Drop the leading/trailing padding words so the fill starts and ends on a glyph. */
    private static void trimWordEdges(List<Word> words) {
        if (words.isEmpty()) return;
        int first = 0;
        while (first < words.size() && words.get(first).text.trim().isEmpty()) first++;
        if (first >= words.size()) {
            words.clear();
            return;
        }
        int last = words.size() - 1;
        while (last >= first && words.get(last).text.trim().isEmpty()) last--;
        if (last + 1 < words.size()) words.subList(last + 1, words.size()).clear();
        if (first > 0) words.subList(0, first).clear();
        Word head = words.get(0);
        String trimmed = head.text.trim();
        if (!trimmed.equals(head.text)) {
            words.set(0, new Word(head.startMs, head.durationMs, leadingTrim(head.text)));
        }
        int tailIndex = words.size() - 1;
        Word tail = words.get(tailIndex);
        words.set(tailIndex,
                new Word(tail.startMs, tail.durationMs, trailingTrim(tail.text)));
    }

    private static String leadingTrim(String value) {
        int index = 0;
        while (index < value.length()) {
            int codePoint = value.codePointAt(index);
            if (!Character.isWhitespace(codePoint) && !Character.isSpaceChar(codePoint)) break;
            index += Character.charCount(codePoint);
        }
        return index == 0 ? value : value.substring(index);
    }

    private static String trailingTrim(String value) {
        int end = value.length();
        while (end > 0) {
            int codePoint = value.codePointBefore(end);
            if (!Character.isWhitespace(codePoint) && !Character.isSpaceChar(codePoint)) break;
            end -= Character.charCount(codePoint);
        }
        return end == value.length() ? value : value.substring(0, end);
    }

    private static long toMillis(String minutes, String seconds, String fraction) {
        long value = parseLong(minutes) * 60000L + parseLong(seconds) * 1000L;
        if (fraction == null || fraction.isEmpty()) return value;
        long digits = parseLong(fraction);
        if (fraction.length() == 1) return value + digits * 100L;
        if (fraction.length() == 2) return value + digits * 10L;
        if (fraction.length() > 3) return value + digits / (long) Math.pow(10, fraction.length() - 3);
        return value + digits;
    }

    private static long parseLong(String value) {
        try {
            return Long.parseLong(value);
        } catch (NumberFormatException ignored) {
            return 0;
        }
    }

    /**
     * Translation documents are usually a copy of the main document with the same line
     * count, but not always with the same timestamps. Match the line text first; only
     * fall back to the nearest timestamp when the text cannot be found.
     */
    private static String alignedTranslation(TreeMap<Long, String> plain,
                                             TreeMap<Long, String> translated, long at,
                                             String text) {
        String needle = normalize(text);
        Long bestKey = null;
        long bestDistance = Long.MAX_VALUE;
        if (!needle.isEmpty()) {
            for (Map.Entry<Long, String> entry : plain.entrySet()) {
                if (!needle.equals(normalize(entry.getValue()))) continue;
                long distance = Math.abs(entry.getKey() - at);
                if (distance < bestDistance) {
                    bestDistance = distance;
                    bestKey = entry.getKey();
                }
            }
        }
        if (bestKey != null && bestDistance <= TEXT_MATCH_SLACK_MS) {
            return nearest(translated, bestKey, 500);
        }
        return nearest(translated, at, NEAR_TIME_TRANSLATION_MS);
    }

    private static String nearest(TreeMap<Long, String> document, long at, long slackMs) {
        if (document.isEmpty()) return "";
        Map.Entry<Long, String> floor = document.floorEntry(at);
        Map.Entry<Long, String> ceiling = document.ceilingEntry(at);
        if (floor == null
                || (ceiling != null && Math.abs(ceiling.getKey() - at) < Math.abs(floor.getKey() - at))) {
            floor = ceiling;
        }
        if (floor == null || Math.abs(floor.getKey() - at) > slackMs) return "";
        return floor.getValue();
    }

    static String normalize(String value) {
        if (value == null) return "";
        return value.toLowerCase(Locale.ROOT).replaceAll("[\\p{P}\\s]+", "");
    }

    // ---- queries ----

    public boolean isEmpty() {
        return lines.isEmpty();
    }

    public int lineCount() {
        return lines.size();
    }

    public List<Line> lines() {
        return lines;
    }

    public boolean hasWordTiming() {
        for (Line line : lines) if (line.wordTimed()) return true;
        return false;
    }

    public boolean hasTranslation() {
        for (Line line : lines) if (!line.translation.isEmpty()) return true;
        return false;
    }

    /** Word timing counts for more than a translation, which counts for more than romaji. */
    public int qualityScore() {
        int score = 0;
        for (Line line : lines) {
            if (line.wordTimed()) score += 4;
            if (!line.translation.isEmpty()) score += 2;
            if (!line.romaji.isEmpty()) score += 2;
        }
        return score;
    }

    /**
     * This timeline with {@code head} glued in front of it.
     *
     * <p>Word-timed catalogues (netease KRC and friends) usually start at the first sung line and
     * drop the credit block the plain LRC carries ("作词 / 作曲 / 编曲" at 0–3 s). The desktop card
     * renders the LRC, so without this the card would show a highlighted credit line while the
     * cluster panel, reading the word-timed document, had nothing to draw for the first twenty
     * seconds of the song. Splicing keeps the karaoke timing and makes both agree on what is
     * playing right now.
     */
    public LyricTimeline withLeadLines(List<Line> head) {
        if (head == null || head.isEmpty()) return this;
        List<Line> merged = new ArrayList<>(head.size() + lines.size());
        merged.addAll(head);
        merged.addAll(lines);
        return new LyricTimeline(Collections.unmodifiableList(merged));
    }

    /**
     * A catalogue hit is only worth showing when it carries more than one real line.
     * A single "纯音乐请欣赏" placeholder looks identical to a successful lookup.
     */
    public boolean usable() {
        if (lines.size() <= 1) return false;
        for (Line line : lines) {
            String text = line.text.trim();
            if (!text.isEmpty() && !placeholder(text)) return true;
        }
        return false;
    }

    private static boolean placeholder(String text) {
        String compact = text.replaceAll("[\\s\\p{Punct}，。！：、]+", "");
        return compact.contains("纯音乐请欣赏")
                || compact.equals("纯音乐")
                || compact.contains("暂无歌词")
                || compact.contains("暂时没有歌词")
                || compact.equalsIgnoreCase("instrumental");
    }

    /** The line index active at {@code positionMs}, or -1 before the first line. */
    public int indexAt(long positionMs) {
        int low = 0;
        int high = lines.size();
        while (low < high) {
            int mid = (low + high) >>> 1;
            if (lines.get(mid).timeMs <= positionMs) low = mid + 1;
            else high = mid;
        }
        return low - 1;
    }

    /**
     * Resolve everything the renderer needs for one frame.
     *
     * <p>An interlude is reported instead of the last line when the gap to the next line
     * is long enough to be intentional: holding the previous line through a 20 s break
     * makes the display look frozen, and the dock has room to show a break marker.
     */
    public Cursor at(long positionMs) {
        if (lines.isEmpty()) return Cursor.EMPTY;
        long at = Math.max(0, positionMs);
        int index = indexAt(at);
        Line line = index >= 0 ? lines.get(index) : null;
        Line before = index > 0 ? lines.get(index - 1) : null;
        Line after = index + 1 < lines.size() ? lines.get(index + 1) : null;

        if (line == null) {
            if (after == null) return Cursor.EMPTY;
            if (after.timeMs >= MIN_INTERLUDE_MS) {
                return new Cursor("", "", "", after.text, true, false, "", "", false, 0,
                        after.timeMs, -1, 0, 0,
                        window(-1, 0, after.timeMs));
            }
        } else if (after != null) {
            long gap = after.timeMs - line.endMs();
            if (gap >= MIN_INTERLUDE_MS && at >= line.endMs()) {
                return new Cursor(line.text, "", line.translation, after.text, true, false, "",
                        "", false, line.endMs(), gap, -1, 0, 0,
                        window(index, line.endMs(), gap));
            }
        }

        String completed = "";
        String currentWord = "";
        boolean trailingRow = false;
        long wordStart = -1;
        long wordDuration = 0;
        int progress = 0;
        if (line != null && line.wordTimed()) {
            StringBuilder sung = new StringBuilder();
            for (int i = 0; i < line.words.size(); i++) {
                Word word = line.words.get(i);
                if (at < word.startMs) break;
                if (word.durationMs > 0 && at < word.startMs + word.durationMs) {
                    currentWord = word.text;
                    wordStart = word.startMs;
                    wordDuration = word.durationMs;
                    progress = (int) Math.max(0,
                            Math.min(1000, (at - word.startMs) * 1000 / word.durationMs));
                    trailingRow = isTrailing(line.words, i);
                    break;
                }
                sung.append(word.text);
            }
            completed = sung.toString();
        }
        long lineDuration;
        if (line == null) {
            lineDuration = 0;
        } else if (line.durationMs > 0) {
            lineDuration = line.durationMs;
        } else if (after != null) {
            lineDuration = after.timeMs - line.timeMs;
        } else {
            lineDuration = PLAIN_LINE_HOLD_MS;
        }
        return new Cursor(before == null ? "" : before.text,
                line == null ? "" : line.text,
                line == null ? "" : line.translation,
                after == null ? "" : after.text,
                false,
                line != null && line.wordTimed(),
                completed,
                currentWord,
                trailingRow,
                line == null ? -1 : line.timeMs,
                Math.max(0, lineDuration),
                wordStart,
                wordDuration,
                progress,
                window(index, -1, 0));
    }

    /**
     * A long word that only runs into punctuation carries the rest of the line: filling it
     * progressively would stall the sweep on a comma. A genuinely final word keeps its own
     * timing, because its duration already covers the tail.
     */
    private static boolean isTrailing(List<Word> words, int index) {
        Word word = words.get(index);
        if (word.durationMs < 1000 || onlyPunctuation(word.text)) return false;
        for (int i = index + 1; i < words.size(); i++) {
            String next = words.get(i).text;
            if (next != null && !next.trim().isEmpty()) return onlyPunctuation(next);
        }
        return false;
    }

    private static boolean onlyPunctuation(String text) {
        if (text == null || text.trim().isEmpty()) return true;
        int index = 0;
        while (index < text.length()) {
            int codePoint = text.codePointAt(index);
            index += Character.charCount(codePoint);
            if (Character.isWhitespace(codePoint)) continue;
            int type = Character.getType(codePoint);
            // Dash, opening/closing quote, brackets, separators, connectors and symbols.
            boolean punctuating = type == Character.DASH_PUNCTUATION
                    || type == Character.START_PUNCTUATION
                    || type == Character.END_PUNCTUATION
                    || type == Character.INITIAL_QUOTE_PUNCTUATION
                    || type == Character.FINAL_QUOTE_PUNCTUATION
                    || type == Character.OTHER_PUNCTUATION
                    || type == Character.CONNECTOR_PUNCTUATION
                    || type == Character.MATH_SYMBOL
                    || type == Character.CURRENCY_SYMBOL
                    || type == Character.MODIFIER_SYMBOL
                    || type == Character.OTHER_SYMBOL;
            if (!punctuating) return false;
        }
        return true;
    }

    private List<Nearby> window(int index, long interludeStartMs, long interludeDurationMs) {
        if (index < 0) return Collections.emptyList();
        List<Nearby> out = new ArrayList<>(7);
        int first = Math.max(0, index - 3);
        for (int i = first; i <= index; i++) {
            Line line = lines.get(i);
            out.add(new Nearby(i - index, line.text, line.translation, line.romaji, line.timeMs,
                    line.durationMs, false));
        }
        if (interludeDurationMs > 0) {
            out.add(new Nearby(0, "", "", "", interludeStartMs, interludeDurationMs, true));
        }
        int last = Math.min(lines.size() - 1, index + 3);
        for (int i = index + 1; i <= last; i++) {
            Line line = lines.get(i);
            out.add(new Nearby(i - index, line.text, line.translation, line.romaji, line.timeMs,
                    line.durationMs, false));
        }
        return Collections.unmodifiableList(out);
    }

    // ---- bridge ----

    /**
     * The whole timeline as one JSON object. Serialising the document once per track keeps
     * the Java → Flutter hop free of per-frame traffic: Flutter advances the cursor itself
     * from the playback clock it already models.
     */
    public JSONObject toJson() {
        JSONObject out = new JSONObject();
        JSONArray rows = new JSONArray();
        for (Line line : lines) {
            JSONObject row = new JSONObject();
            try {
                row.put("t", line.timeMs);
                row.put("d", line.durationMs);
                row.put("x", line.text);
                if (!line.translation.isEmpty()) row.put("tr", line.translation);
                if (!line.romaji.isEmpty()) row.put("ro", line.romaji);
                if (line.wordTimed()) {
                    JSONArray words = new JSONArray();
                    for (Word word : line.words) {
                        JSONArray item = new JSONArray();
                        item.put(word.startMs);
                        item.put(word.durationMs);
                        item.put(word.text);
                        words.put(item);
                    }
                    row.put("w", words);
                }
            } catch (Exception ignored) {
                // org.json only fails on doubles and cycles; neither occurs here.
            }
            rows.put(row);
        }
        try {
            out.put("v", 1).put("lines", rows);
        } catch (Exception ignored) {
        }
        return out;
    }

    @Override
    public String toString() {
        return "LyricTimeline{" + lines.size() + " lines, words=" + hasWordTiming()
                + ", translation=" + hasTranslation() + '}';
    }

    /** Exposed for diagnostics: the plain text of every line, newline separated. */
    public String plainText() {
        StringBuilder out = new StringBuilder();
        for (Iterator<Line> it = lines.iterator(); it.hasNext(); ) {
            out.append(it.next().text);
            if (it.hasNext()) out.append('\n');
        }
        return out.toString();
    }
}
