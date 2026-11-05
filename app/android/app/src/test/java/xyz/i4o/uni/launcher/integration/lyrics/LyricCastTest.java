package xyz.i4o.uni.launcher.integration.lyrics;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertNotSame;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertTrue;

import org.junit.Test;

/** The clock every cast surface samples; time is injected, so nothing here sleeps. */
public final class LyricCastTest {
    private static final String YRC =
            "[1000,2000](1000,500,0)你(1500,500,0)好\n[5000,2000](5000,2000,0)再见";

    private static LyricTimeline timeline() {
        return LyricTimeline.parseEnhanced(YRC);
    }

    @Test
    public void aPlayingStateAdvancesWithTheClocksSpeed() {
        LyricCast.State state = new LyricCast.State("歌", "人", "网易云音乐", timeline(), true,
                1000, 1600, 1.5f);
        assertEquals(1000, state.positionAt(1600));
        assertEquals(1150, state.positionAt(1700));
        assertEquals("你好", state.cursorAt(1700).text);
        assertTrue(state.hasTimeline());
    }

    @Test
    public void aPausedStateHoldsItsPosition() {
        LyricCast.State state =
                new LyricCast.State("歌", "人", "", timeline(), false, 1000, 1600, 1f);
        assertEquals(1000, state.positionAt(60000));
        assertEquals("你好", state.cursorAt(60000).text);
        // And further into the track the document still answers for the held position only.
        assertEquals("你好", state.cursorAt(600000).text);
    }

    @Test
    public void publishedStateIsWhatReadersSee() {
        LyricCast.clear();
        assertFalse(LyricCast.state().hasTimeline());
        LyricCast.publish("起风了", "买辣椒也用券", "QQ 音乐", timeline(), true, 1600, 1600, 1f);
        assertEquals("起风了", LyricCast.state().title);
        assertEquals("QQ 音乐", LyricCast.state().sourceLabel);
        assertEquals("你好", LyricCast.cursorAt(1700).text);
        // A track without lyrics must clear the previous document, not leave it on screen.
        LyricCast.publish("无词", "", "", LyricTimeline.EMPTY, true, 0, 1700, 1f);
        assertFalse(LyricCast.state().hasTimeline());
        LyricCast.clear();
        assertFalse(LyricCast.state().hasTimeline());
    }

    @Test
    public void everyPublishHandsOutANewIdentity() {
        LyricCast.clear();
        LyricCast.publish("每天每天", "方大同", "网易云音乐", LyricTimeline.EMPTY, true, 73_000, 1000, 1f);
        LyricCast.State before = LyricCast.state();
        // Same track, same position, only the timeline landed (the catalog answered). The panel
        // finds out about it by reference comparison in the feed watchdog, so a publish that
        // reused the old instance would leave the window frozen on "正在获取歌词".
        LyricCast.publish("每天每天", "方大同", "网易云音乐", timeline(), true, 73_000, 1400, 1f);
        LyricCast.State after = LyricCast.state();
        assertNotSame(before, after);
        assertFalse(before.hasTimeline());
        assertTrue(after.hasTimeline());
    }

    @Test
    public void theSungPrefixIsSharedWithTheFlutterSide() {
        LyricTimeline timeline = timeline();
        // Halfway through the single-glyph word "好": the fill leads by less than one glyph.
        assertEquals("你好", timeline.at(1750).sungPrefix());
        assertEquals("你", timeline.at(1250).sungPrefix());
        // A plain document never claims a syllable fill it cannot know.
        assertEquals("",
                LyricTimeline.parse("[00:01.00]a\n[00:05.00]b", "", "", "").at(5500)
                        .sungPrefix());
    }
}
