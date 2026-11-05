package xyz.i4o.uni.launcher.integration.display;

/**
 * Pure layout math for the lyric panel that is painted on another display.
 *
 * <p>Two consumers must agree on exactly where the panel lands: the service that adds the
 * window, and the position editor in the settings page that previews it. Keeping the maths
 * here, with no Android types, is what makes that agreement testable — the editor maps a drag
 * to the same ratio the service maps to pixels, so what the user drops in the preview is what
 * appears on the cluster.
 *
 * <p>Coordinates are the panel's own top-left corner in display pixels. The service used to
 * place the window with {@code Gravity.TOP|CENTER_HORIZONTAL} and a fixed {@code 62%} offset,
 * which cannot express "a bit to the left, a bit higher"; absolute origin plus a clamp does.
 */
public final class ClusterPanelGeometry {
    /** Narrower than a fifth of the screen is not a lyric panel any more. */
    public static final float MIN_WIDTH_RATIO = 0.2f;
    public static final float MAX_WIDTH_RATIO = 1f;
    /** Row pitch in multiples of the text size; the view draws with the same number. */
    public static final float ROW_SPACING = 1.62f;
    public static final int MIN_ROWS = 1;
    public static final int MAX_ROWS = 3;

    public static final float DEFAULT_X_RATIO = 0.5f;
    public static final float DEFAULT_Y_RATIO = 0.62f;
    public static final float DEFAULT_WIDTH_RATIO = 0.94f;
    public static final int DEFAULT_ROWS = 3;

    private ClusterPanelGeometry() {
    }

    public static float clampRatio(float value, float fallback) {
        if (Float.isNaN(value) || Float.isInfinite(value)) return fallback;
        return Math.max(0f, Math.min(1f, value));
    }

    public static float widthRatio(float value) {
        float ratio = clampRatio(value, DEFAULT_WIDTH_RATIO);
        if (Float.isNaN(value) || Float.isInfinite(value)) return DEFAULT_WIDTH_RATIO;
        return Math.max(MIN_WIDTH_RATIO, Math.min(MAX_WIDTH_RATIO, ratio));
    }

    public static int rows(int value) {
        return Math.max(MIN_ROWS, Math.min(MAX_ROWS, value));
    }

    public static int clamp(int value, int min, int max) {
        if (max < min) return min;
        return Math.max(min, Math.min(max, value));
    }

    /** Panel width in pixels for a display of {@code displayWidth}. */
    public static int width(int displayWidth, float widthRatio) {
        int available = Math.max(1, displayWidth);
        int width = Math.round(available * widthRatio(widthRatio));
        return clamp(width, 1, available);
    }

    /** Panel height in pixels: {@code rows} rows of {@code ROW_SPACING × textSizePx}. */
    public static int height(float textSizePx, int rows) {
        float size = Math.max(8f, textSizePx);
        return Math.max(1, Math.round(size * ROW_SPACING * rows(rows)));
    }

    /**
     * Top-left origin of the panel.
     *
     * <p>{@code xRatio}/{@code yRatio} are the <em>centre</em> of the panel expressed as a
     * fraction of the display, which is the intuitive thing to drag: drop the block in the
     * middle and it stays centred whatever its width. The result is clamped so a panel can
     * never be pushed off the display.
     *
     * @return {@code {x, y}} in display pixels
     */
    public static int[] origin(int displayWidth, int displayHeight, int panelWidth, int panelHeight,
                               float xRatio, float yRatio) {
        int screenW = Math.max(1, displayWidth);
        int screenH = Math.max(1, displayHeight);
        int w = clamp(panelWidth, 1, screenW);
        int h = clamp(panelHeight, 1, screenH);
        int centreX = Math.round(screenW * clampRatio(xRatio, DEFAULT_X_RATIO));
        int centreY = Math.round(screenH * clampRatio(yRatio, DEFAULT_Y_RATIO));
        int x = clamp(centreX - w / 2, 0, screenW - w);
        int y = clamp(centreY - h / 2, 0, screenH - h);
        return new int[]{x, y};
    }
}
