package xyz.i4o.uni.launcher.integration.display;

import android.content.Context;
import android.graphics.Canvas;
import android.graphics.LinearGradient;
import android.graphics.Paint;
import android.graphics.RectF;
import android.graphics.Shader;
import android.graphics.Typeface;
import android.text.TextPaint;
import android.text.TextUtils;
import android.view.View;

import xyz.i4o.uni.launcher.integration.lyrics.LyricCast;
import xyz.i4o.uni.launcher.integration.lyrics.LyricTimeline;

/**
 * The lyric rows painted onto a display that is not the launcher's own.
 *
 * <p>A plain {@link View} with a Canvas, not a Flutter surface: the cast window lives in another
 * display's window manager, and booting a second engine for three rows of text costs RAM and a
 * frame of latency for nothing. Everything drawn here is derived from the
 * {@link LyricTimeline.Cursor} at the sampled position, so the fill edge is the same one the
 * desktop card shows.
 *
 * <p>Typographic contract, all of it configurable from the settings page:
 *
 * <ul>
 *   <li>the active line is the largest row and carries the sweep; the row above and the row
 *       below are dimmed and set smaller, which is what makes the panel read as a lyric pane
 *       instead of three equal lines of text;</li>
 *   <li>the swept edge is a gradient, not a hard cut: a hard edge looks like a rendering bug on
 *       a matte cluster panel, a feathered edge looks intentional;</li>
 *   <li>a document without word timing fills the whole line in the accent colour — a plain LRC
 *       knows nothing about syllables and faking a sweep makes the text crawl;</li>
 *   <li>the panel can be a translucent pill or bare text, and either way it sits on top of the
 *       factory cluster UI without hiding it;</li>
 *   <li>with no timeline the panel explains itself instead of drawing an empty box.</li>
 * </ul>
 */
public final class ClusterLyricsView extends View {
    /** Style: bare text, a translucent pill, or text with a stronger glow. */
    public static final int STYLE_PLAIN = 0;
    public static final int STYLE_PILL = 1;
    public static final int STYLE_GLOW = 2;

    private static final float EDGE_FEATHER = 0.55f;

    private final TextPaint basePaint = new TextPaint(Paint.ANTI_ALIAS_FLAG);
    private final TextPaint accentPaint = new TextPaint(Paint.ANTI_ALIAS_FLAG);
    private final Paint backgroundPaint = new Paint(Paint.ANTI_ALIAS_FLAG);
    private final Paint dotPaint = new Paint(Paint.ANTI_ALIAS_FLAG);
    private final RectF backgroundRect = new RectF();

    private LyricCast.State state = LyricCast.State.EMPTY;
    private long nowMs;
    private float textSizePx = 40f;
    private int rows = ClusterPanelGeometry.DEFAULT_ROWS;
    private int accent = 0xFF7FE3D4;
    private int muted = 0xFF9FB4BB;
    private int background = 0xB3000000;
    private int style = STYLE_PILL;
    private Shader sweep;

    public ClusterLyricsView(Context context) {
        super(context);
        Typeface typeface = Typeface.create("sans-serif-medium", Typeface.NORMAL);
        basePaint.setTypeface(typeface);
        accentPaint.setTypeface(typeface);
        basePaint.setTextAlign(Paint.Align.LEFT);
        accentPaint.setTextAlign(Paint.Align.LEFT);
        setWillNotDraw(false);
    }

    /**
     * @param textSizePx active-row text size, already converted to the target display's pixels
     * @param rows       1..3 visible rows
     * @param accent     已唱与当前行颜色
     * @param muted      上一行、下一行、翻译颜色
     * @param background 面板底色，alpha 为 0 时不画底
     * @param style      {@link #STYLE_PLAIN} / {@link #STYLE_PILL} / {@link #STYLE_GLOW}
     */
    public void configure(float textSizePx, int rows, int accent, int muted, int background,
                          int style) {
        this.textSizePx = Math.max(10f, textSizePx);
        this.rows = ClusterPanelGeometry.rows(rows);
        this.accent = accent;
        this.muted = muted;
        this.background = background;
        this.style = style;
        sweep = null;
        requestLayout();
        invalidate();
    }

    public void setState(LyricCast.State next, long nowMs) {
        this.state = next == null ? LyricCast.State.EMPTY : next;
        this.nowMs = nowMs;
    }

    /** Text size the layout should reserve for one row, in pixels. */
    public float rowHeightPx() {
        return textSizePx * ClusterPanelGeometry.ROW_SPACING;
    }

    @Override
    protected void onMeasure(int widthMeasureSpec, int heightMeasureSpec) {
        int width = MeasureSpec.getSize(widthMeasureSpec);
        int height = Math.round(rowHeightPx() * rows);
        if (MeasureSpec.getMode(heightMeasureSpec) == MeasureSpec.EXACTLY) {
            height = MeasureSpec.getSize(heightMeasureSpec);
        }
        setMeasuredDimension(Math.max(1, width), Math.max(1, height));
    }

    @Override
    protected void onDraw(Canvas canvas) {
        int width = getWidth();
        int height = getHeight();
        if (width <= 0 || height <= 0) return;
        float rowHeight = height / (float) rows;

        if (style != STYLE_PLAIN && (background >>> 24) != 0) drawPanelBackground(canvas, width, height);

        LyricCast.State snapshot = state;
        if (!snapshot.hasTimeline()) {
            // Telling the driver "this source has no lyrics" while the catalog request is still
            // in flight is a lie that lasts a frame. Say what is actually happening instead.
            String reason;
            if (snapshot.title.isEmpty()) reason = "等待播放";
            else if (snapshot.playing) reason = "正在获取歌词";
            else reason = "当前音源未提供歌词";
            drawText(canvas, reason, 0, width, height, rowHeight, muted, 0.82f, 0.62f, "");
            return;
        }

        LyricTimeline.Cursor cursor = snapshot.cursorAt(nowMs);
        if (cursor.interlude) {
            // During an interlude the cursor carries the line that just ended in previous
            // (its own 	ext is empty by design), so this used to draw nothing at all.
            String ended = !cursor.text.isEmpty() ? cursor.text : cursor.previous;
            if (rows >= 3 && !ended.isEmpty()) {
                // Keep the line that just ended visible above the dots instead of blanking it.
                drawText(canvas, ended, rowFor(0), width, height, rowHeight, muted, 0.74f,
                        0.42f, "");
            }
            // Above the dots sits what is coming. A silent intro (netease KRC starts at the first
            // sung line, so 18 s of a 4-minute song can be empty) used to render as three dots
            // and nothing else, which reads as "no lyrics" rather than "not yet".
            if (rows >= 2 && !cursor.next.isEmpty()) {
                drawText(canvas, cursor.next, rowFor(1), width, height, rowHeight, muted, 0.7f,
                        0.5f, "");
            }
            drawInterludeDots(canvas, width, height);
            return;
        }

        String sung = cursor.sungPrefix();
        if (rows >= 3 && !cursor.previous.isEmpty()) {
            drawText(canvas, cursor.previous, rowFor(-1), width, height, rowHeight, muted, 0.72f,
                    0.5f, "");
        }
        drawText(canvas, cursor.text, rowFor(0), width, height, rowHeight, accent, 1f, 1f, sung);

        String third = !cursor.translation.isEmpty() ? cursor.translation : cursor.next;
        if (rows >= 2 && !third.isEmpty()) {
            drawText(canvas, third, rowFor(1), width, height, rowHeight, muted,
                    cursor.translation.isEmpty() ? 0.7f : 0.64f, 0.72f, "");
        }
    }

    /**
     * Row index for a line offset, given how many rows are visible. Two rows means the active
     * line is on top and the secondary line below it; three rows centres the active line.
     */
    private int rowFor(int offset) {
        if (rows >= 3) return offset + 1;
        if (rows == 2) return offset <= 0 ? 0 : 1;
        return 0;
    }

    private void drawPanelBackground(Canvas canvas, int width, int height) {
        // A stadium radius on a wide bar reads as a pill sitting on top of the cluster; a
        // softer 30% corner reads as a plate that belongs to the screen.
        float radius = Math.min(height * 0.30f, width * 0.02f);
        backgroundPaint.setShader(null);
        backgroundPaint.setColor(background);
        backgroundRect.set(0, 0, width, height);
        canvas.drawRoundRect(backgroundRect, radius, radius, backgroundPaint);
        // A single soft highlight along the top edge keeps the pill from reading as a black bar.
        backgroundPaint.setShader(new LinearGradient(0, 0, 0, height,
                new int[]{(background & 0x00FFFFFF) | 0x14FFFFFF, 0x00000000},
                new float[]{0f, 1f}, Shader.TileMode.CLAMP));
        canvas.drawRoundRect(backgroundRect, radius, radius, backgroundPaint);
        backgroundPaint.setShader(null);
    }

    /** Three dots for an instrumental section, half-period pulse so they never look frozen. */
    private void drawInterludeDots(Canvas canvas, int width, int height) {
        float radius = Math.max(2.5f, textSizePx * 0.07f);
        float gap = radius * 3.4f;
        // With a third row in use the dots sit on the middle row, not the vertical centre.
        float centreY = rows >= 3 ? height * 0.5f : height * 0.34f;
        float startX = width / 2f - gap;
        double phase = (nowMs % 1400L) / 1400.0;
        dotPaint.setColor(muted);
        for (int i = 0; i < 3; i++) {
            double offset = (phase + i * 0.18) % 1.0;
            float pulse = (float) (0.45 + 0.55 * Math.abs(Math.sin(offset * Math.PI)));
            dotPaint.setAlpha((int) (70 + 130 * pulse));
            canvas.drawCircle(startX + gap * i, centreY, radius * (0.8f + 0.35f * pulse), dotPaint);
        }
    }

    /**
     * Draw one row: dimmed base text, then the sung prefix in the accent colour with a feathered
     * leading edge. The prefix is a real string prefix, so {@link Paint#measureText} lands on the
     * same glyph boundary the desktop card uses.
     */
    private void drawText(Canvas canvas, String text, int row, int width, int height,
                          float rowHeight, int color, float scale, float alpha, String sung) {
        if (text == null || text.isEmpty()) return;
        float size = textSizePx * scale;
        float maxWidth = width * 0.94f;
        basePaint.setTextSize(size);
        basePaint.setColor(color);
        basePaint.setAlpha(clampAlpha(alpha));
        applyShadow(basePaint, size, 0x99000000, 0.14f);

        String shown = fit(basePaint, text, maxWidth);
        float textWidth = width(basePaint, shown, size);
        float left = Math.max(width * 0.03f, (width - textWidth) / 2f);
        float baseline = rowHeight * row + rowHeight * 0.72f;

        canvas.drawText(shown, left, baseline, basePaint);

        if (sung == null || sung.isEmpty() || !shown.startsWith(sung)) return;

        float sungWidth = width(basePaint, sung, size);
        if (sungWidth <= 0f) return;
        float feather = Math.max(2f, size * EDGE_FEATHER);
        accentPaint.setTextSize(size);
        accentPaint.setAlpha(255);
        applyShadow(accentPaint, size, style == STYLE_GLOW ? 0xAA000000 : 0x55000000, 0.2f);

        int solid = accent;
        int edge = (accent & 0x00FFFFFF);
        sweep = new LinearGradient(left, 0, left + sungWidth + feather, 0,
                new int[]{solid, solid, edge, edge},
                new float[]{0f, Math.max(0.01f, sungWidth / (sungWidth + feather)) * 0.82f, 1f, 1f},
                Shader.TileMode.CLAMP);
        accentPaint.setShader(sweep);
        canvas.save();
        canvas.clipRect(left - 2f, rowHeight * row - 2f, left + sungWidth + feather,
                rowHeight * (row + 1) + 2f);
        canvas.drawText(shown, left, baseline, accentPaint);
        canvas.restore();
        accentPaint.setShader(null);
    }

    // ---- glyph cache ----

    /**
     * Advance width per (size, code point).
     *
     * <p>Every frame measured the same two strings of the same line up to three times — once to
     * decide the ellipsis, once for the centring, once for the karaoke fill — and each measure
     * walked the whole line. The panel redraws at 30 fps on a head unit whose CPU is already
     * busy, so the measurement was a real share of the frame. Advances are cached per code point
     * and summed for simple text; text that needs shaping (Arabic, Indic, Thai, Hebrew, any
     * combining mark) keeps the real engine call, because summing isolated advances would break
     * its joins.
     */
    private static final int ADVANCE_LIMIT = 4096;
    private final java.util.HashMap<Long, Float> advanceCache = new java.util.HashMap<>();

    private float width(TextPaint paint, String text, float size) {
        if (text == null || text.isEmpty()) return 0f;
        if (!simple(text)) return paint.measureText(text);
        float total = 0f;
        int index = 0;
        while (index < text.length()) {
            int codePoint = text.codePointAt(index);
            index += Character.charCount(codePoint);
            total += advance(paint, codePoint, size);
        }
        return total;
    }

    private float advance(TextPaint paint, int codePoint, float size) {
        long key = ((long) Math.round(size * 4f) << 32) | (codePoint & 0xFFFFFFFFL);
        Float cached = advanceCache.get(key);
        if (cached != null) return cached;
        float value = paint.measureText(new String(Character.toChars(codePoint)));
        if (advanceCache.size() > ADVANCE_LIMIT) advanceCache.clear();
        advanceCache.put(key, value);
        return value;
    }

    /** True when per-code-point advances add up to the shaped width of the whole string. */
    private static boolean simple(String text) {
        for (int i = 0; i < text.length(); ) {
            int cp = text.codePointAt(i);
            i += Character.charCount(cp);
            if (cp < 0x0590) continue;
            if (cp <= 0x05FF) return false;                        // Hebrew
            if (cp >= 0x0600 && cp <= 0x08FF) return false;         // Arabic, Syriac, Thaana
            if (cp >= 0x0900 && cp <= 0x0DFF) return false;         // Devanagari … Sinhala
            if (cp >= 0x0E00 && cp <= 0x0EFF) return false;         // Thai, Lao
            if (cp >= 0x1000 && cp <= 0x109F) return false;         // Myanmar
            if (cp >= 0x1780 && cp <= 0x17FF) return false;         // Khmer
            if (cp >= 0x1AB0 && cp <= 0x1AFF) return false;         // combining marks
            if (cp >= 0xFB1D && cp <= 0xFEFF) return false;         // presentation forms
            int type = Character.getType(cp);
            if (type == Character.NON_SPACING_MARK || type == Character.COMBINING_SPACING_MARK) {
                return false;
            }
        }
        return true;
    }

    /** Ellipsise with cached advances; falls back to the platform's shaped ellipsis. */
    private String fit(TextPaint paint, String text, float maxWidth) {
        if (width(paint, text, paint.getTextSize()) <= maxWidth) return text;
        if (!simple(text)) {
            return TextUtils.ellipsize(text, paint, maxWidth, TextUtils.TruncateAt.END).toString();
        }
        String mark = "…";
        float markWidth = width(paint, mark, paint.getTextSize());
        float budget = Math.max(0f, maxWidth - markWidth);
        StringBuilder out = new StringBuilder();
        float used = 0f;
        for (int i = 0; i < text.length(); ) {
            int cp = text.codePointAt(i);
            i += Character.charCount(cp);
            float advance = advance(paint, cp, paint.getTextSize());
            if (used + advance > budget) break;
            used += advance;
            out.appendCodePoint(cp);
        }
        return out.append(mark).toString();
    }

    private void applyShadow(TextPaint paint, float size, int color, float radiusRatio) {
        if (style == STYLE_PLAIN) {
            paint.clearShadowLayer();
            return;
        }
        paint.setShadowLayer(Math.max(1f, size * radiusRatio), 0, size * 0.05f, color);
    }

    private static int clampAlpha(float alpha) {
        int value = Math.round(255 * Math.max(0f, Math.min(1f, alpha)));
        return Math.max(0, Math.min(255, value));
    }

    /** Diagnostics for the settings panel: what this window is currently showing. */
    public String describe() {
        LyricCast.State snapshot = state;
        return "rows=" + rows + " px=" + Math.round(textSizePx)
                + " track=" + snapshot.title + " hasTimeline=" + snapshot.hasTimeline();
    }
}
