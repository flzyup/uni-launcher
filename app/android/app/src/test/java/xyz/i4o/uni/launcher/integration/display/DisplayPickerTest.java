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
    public void aSingleScreenUnitCastsNowhere() {
        // 只存了主屏的名字（模拟器/平板上唯一那块屏），以前按名字会匹配上主屏，
        // 于是歌词窗口盖在桌面自己身上，中间一条半透明底把界面压得只剩个影。
        int[] ids = {0};
        String[] names = {"内置屏幕"};
        boolean[] presentation = {false};
        assertEquals(DisplayPicker.NONE,
                DisplayPicker.pick(ids, names, presentation, "内置屏幕", 0));
        assertEquals(DisplayPicker.NONE,
                DisplayPicker.pick(ids, names, presentation, "内置屏幕", -1));
        // 真的接了仪表时，名字匹配照旧。
        assertEquals(0, DisplayPicker.pick(new int[]{2}, new String[]{"内置屏幕"},
                presentation, "内置屏幕", -1));
    }

    @Test
    public void rowsExplainThemselves() {
        assertEquals("仪表  ·  ID 2  ·  1920×720  ·  240 dpi",
                DisplayPicker.label("仪表", 2, 1920, 720, 240));
        assertEquals("屏幕 4  ·  ID 4", DisplayPicker.label("", 4, 0, 0, 0));
    }
}
