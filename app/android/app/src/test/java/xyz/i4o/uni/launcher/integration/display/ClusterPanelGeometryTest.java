package xyz.i4o.uni.launcher.integration.display;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertTrue;

import org.junit.Test;

/**
 * Placement maths for the cast panel.
 *
 * <p>These numbers are duplicated in the Flutter twin {@code ClusterLayout} and pinned by
 * {@code cluster_layout_test.dart}. The preview in settings and the WindowManager window must
 * compute the same pixels from the same ratios; a change on one side that is not mirrored shows
 * up as a failing test here rather than as lyrics landing 200 px off in a car.
 */
public final class ClusterPanelGeometryTest {
    private static final int W = 1920;
    private static final int H = 720;

    @Test
    public void widthIsClampedToTheFloorAndToTheDisplay() {
        assertEquals(0.2f, ClusterPanelGeometry.widthRatio(0.01f), 1e-6);
        assertEquals(1f, ClusterPanelGeometry.widthRatio(9f), 1e-6);
        assertEquals(1805, ClusterPanelGeometry.width(1920, 0.94f));
        assertEquals(960, ClusterPanelGeometry.width(1920, 0.5f));
        assertEquals(1920, ClusterPanelGeometry.width(1920, 5f));
    }

    @Test
    public void heightGrowsWithRowsAndTextSize() {
        assertEquals(130, ClusterPanelGeometry.height(80f, 1));
        assertEquals(389, ClusterPanelGeometry.height(80f, 3));
        assertEquals(3, ClusterPanelGeometry.rows(9));
        assertEquals(1, ClusterPanelGeometry.rows(0));
    }

    @Test
    public void ratioIsTheCentreOfThePanelNotItsCorner() {
        int[] origin = ClusterPanelGeometry.origin(W, H, 960, 260, 0.5f, 0.5f);
        assertEquals(480, origin[0]);
        assertEquals(230, origin[1]);
    }

    @Test
    public void thePanelIsNeverPushedOffTheDisplay() {
        int[] left = ClusterPanelGeometry.origin(W, H, 960, 260, 0f, 0f);
        assertEquals(0, left[0]);
        assertEquals(0, left[1]);
        int[] right = ClusterPanelGeometry.origin(W, H, 960, 260, 1f, 1f);
        assertEquals(960, right[0]);
        assertEquals(460, right[1]);
    }

    @Test
    public void aFullWidthPanelSitsOnTheDisplayItWasGiven() {
        int width = ClusterPanelGeometry.width(W, ClusterPanelGeometry.DEFAULT_WIDTH_RATIO);
        int height = ClusterPanelGeometry.height(51f, 3);
        int[] origin = ClusterPanelGeometry.origin(W, H, width, height, 0.5f,
                ClusterPanelGeometry.DEFAULT_Y_RATIO);
        // Nothing may hang outside, in any of the four directions.
        assertTrue(origin[0] >= 0);
        assertTrue(origin[1] >= 0);
        assertTrue(origin[0] + width <= W);
        assertTrue(origin[1] + height <= H);
        // And the default placement is where the old hardcoded 62% used to be.
        assertEquals(Math.round(H * 0.62f), origin[1] + height / 2);
    }

    @Test
    public void aBrokenRatioFallsBackInsteadOfCorruptingTheLayout() {
        float fallback = ClusterPanelGeometry.DEFAULT_X_RATIO;
        assertEquals(0f, ClusterPanelGeometry.clampRatio(-4f, fallback), 1e-6);
        assertEquals(1f, ClusterPanelGeometry.clampRatio(4f, fallback), 1e-6);
        assertEquals(0.5f, ClusterPanelGeometry.clampRatio(0.5f, fallback), 1e-6);
        assertEquals(fallback, ClusterPanelGeometry.clampRatio(Float.NaN, fallback), 1e-6);
        assertEquals(ClusterPanelGeometry.DEFAULT_WIDTH_RATIO,
                ClusterPanelGeometry.widthRatio(Float.NaN), 1e-6);
    }

    @Test
    public void theFontSliderRangeIsClampedNotTrusted() {
        // The two range ends are what the Flutter slider offers; anything outside it is either a
        // stale preference from an older build or a corrupt one.
        assertEquals(ClusterPanelGeometry.MIN_FONT_SP, ClusterPanelGeometry.fontSp(4f), 1e-6);
        assertEquals(ClusterPanelGeometry.MAX_FONT_SP, ClusterPanelGeometry.fontSp(400f), 1e-6);
        assertEquals(26f, ClusterPanelGeometry.fontSp(26f), 1e-6);
        assertEquals(ClusterPanelGeometry.DEFAULT_FONT_SP,
                ClusterPanelGeometry.fontSp(0f), 1e-6);
        assertEquals(ClusterPanelGeometry.DEFAULT_FONT_SP,
                ClusterPanelGeometry.fontSp(Float.NaN), 1e-6);
    }

    @Test
    public void effectsAreOffUnlessTheStoredNameSaysWords() {
        // Default off is the whole point: an unknown or missing value must not start a frame
        // loop on a head unit that is already drawing a map.
        assertEquals(ClusterPanelGeometry.MOTION_NONE, ClusterPanelGeometry.motionOf(null));
        assertEquals(ClusterPanelGeometry.MOTION_NONE, ClusterPanelGeometry.motionOf(""));
        assertEquals(ClusterPanelGeometry.MOTION_NONE,
                ClusterPanelGeometry.motionOf("words+fx"));
        assertEquals(ClusterPanelGeometry.MOTION_NONE, ClusterPanelGeometry.motionOf("true"));
        assertEquals(ClusterPanelGeometry.MOTION_FLOW, ClusterPanelGeometry.motionOf("words"));
        assertEquals(ClusterPanelGeometry.MOTION_NAME_NONE, ClusterPanelGeometry.motionName("nope"));
        assertEquals(ClusterPanelGeometry.MOTION_NAME_FLOW, ClusterPanelGeometry.motionName("words"));
    }

    @Test
    public void aBiggerFontGrowsThePanelProportionally() {
        int small = ClusterPanelGeometry.height(24f, 3);
        int large = ClusterPanelGeometry.height(48f, 3);
        assertEquals(small * 2, large);
        // The row pitch is the number the view reserves, so both sides must agree on it.
        assertEquals(Math.round(24f * ClusterPanelGeometry.ROW_SPACING * 3), small);
    }
}
