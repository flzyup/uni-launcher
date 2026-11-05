package xyz.i4o.uni.launcher.integration.display;

import static org.junit.Assert.assertEquals;

import org.junit.Test;

/** Which display a cast window lands on; no device, no DisplayManager. */
public final class DisplayPickerTest {
    private static final int[] IDS = {-1, 0, 2, 5};
    private static final String[] NAMES = {
            "internal", "内置屏幕", "仪表", "HDMI Screen 1"
    };
    private static final boolean[] PRESENTATION = {false, false, true, false};

    @Test
    public void theSameDisplayIdWinsOverEverything() {
        assertEquals(2, DisplayPicker.pick(IDS, NAMES, PRESENTATION, "HDMI Screen 1", 2));
    }

    @Test
    public void aVanishedDisplayIsFoundAgainByItsName() {
        assertEquals(3, DisplayPicker.pick(IDS, NAMES, PRESENTATION, "HDMI Screen 1", 9));
    }

    @Test
    public void anAmbiguousNameIsNotGuessed() {
        String[] names = {"HDMI Screen 1", "HDMI Screen 1", "仪表"};
        int[] ids = {-1, 0, 7, 8};
        // Two displays share the name and neither id matches: refuse instead of picking one.
        assertEquals(DisplayPicker.NONE,
                DisplayPicker.pick(ids, names, PRESENTATION, "HDMI Screen 1", 3));
        // With the id still known, the pair resolves again.
        assertEquals(2, DisplayPicker.pick(ids, names, PRESENTATION, "HDMI Screen 1", 7));
    }

    @Test
    public void anUnknownIdentityPaintsNowhere() {
        assertEquals(DisplayPicker.NONE,
                DisplayPicker.pick(IDS, NAMES, PRESENTATION, "", -1));
        // A name that still resolves uniquely is enough; the id only ever adds precision.
        assertEquals(2, DisplayPicker.pick(IDS, NAMES, PRESENTATION, "仪表", 0));
        assertEquals(DisplayPicker.NONE,
                DisplayPicker.pick(IDS, NAMES, PRESENTATION, "已拔掉的屏", 0));
    }

    @Test
    public void theMainDisplayIsNeverACastTarget() {
        int[] ids = {0, 3};
        assertEquals(1, DisplayPicker.firstPresentation(ids, new boolean[]{false, true}));
        assertEquals(1, DisplayPicker.firstSecondary(ids));
        // Nothing but the launcher's own display: there is nowhere to cast.
        assertEquals(DisplayPicker.NONE, DisplayPicker.firstSecondary(new int[]{0}));
        assertEquals(DisplayPicker.NONE,
                DisplayPicker.firstPresentation(new int[]{0}, new boolean[]{true}));
    }

    @Test
    public void rowsExplainThemselves() {
        assertEquals("仪表  ·  ID 2  ·  1920×720  ·  240 dpi",
                DisplayPicker.label("仪表", 2, 1920, 720, 240));
        assertEquals("屏幕 4  ·  ID 4", DisplayPicker.label("", 4, 0, 0, 0));
    }
}
