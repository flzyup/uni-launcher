package xyz.i4o.uni.launcher.integration.lyrics;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertTrue;

import org.junit.Test;

import java.io.ByteArrayOutputStream;
import java.nio.charset.StandardCharsets;
import java.util.Base64;
import java.util.zip.Deflater;
import java.util.zip.DeflaterOutputStream;

/** Offline coverage for the word-timed lyric pipeline; no device and no network. */
public final class LyricTimelineTest {
    private static final String LRC =
            "[offset:0]\n[00:01.00]line one\n[00:05.50]line two\n[00:10.00]line three";
    private static final String TRANSLATION =
            "[00:01.00]第一行\n[00:05.50]第二行\n[00:10.00]第三行";
    private static final String YRC = "[1000,2000](1000,500,0)你(1500,500,0)好(2000,1000,0)世界\n"
            + "[5000,3000](5000,1000,0)第(6000,2000,0)二行";

    @Test
    public void plainLrcKeepsLineTimingOnly() {
        LyricTimeline timeline = LyricTimeline.parse(LRC, TRANSLATION, "", "");
        assertEquals(3, timeline.lineCount());
        assertFalse(timeline.hasWordTiming());
        assertEquals("第二行", timeline.at(5500).translation);
    }

    @Test
    public void wordTimedDocumentWinsAndCarriesTranslation() {
        LyricTimeline timeline = LyricTimeline.parse(LRC, TRANSLATION, YRC, "");
        assertTrue(timeline.hasWordTiming());
        assertEquals("你好世界", timeline.at(1600).text);
        assertEquals("第一行", timeline.at(1600).translation);
    }

    @Test
    public void karaokeCursorSplitsSungAndCurrentWord() {
        LyricTimeline timeline = LyricTimeline.parse(LRC, TRANSLATION, YRC, "");
        LyricTimeline.Cursor cursor = timeline.at(1750);
        assertEquals("你", cursor.completed);
        assertEquals("好", cursor.currentWord);
        assertEquals(1500, cursor.wordStartMs);
        assertEquals(500, cursor.wordProgressPermille);
    }

    @Test
    public void aLongBreakBecomesAnInterlude() {
        LyricTimeline timeline = LyricTimeline.parse("[00:01.00]a\n[00:20.00]b", "", "", "");
        LyricTimeline.Cursor cursor = timeline.at(8000);
        assertTrue(cursor.interlude);
        assertEquals("", cursor.text);
        assertEquals("b", cursor.next);
        assertTrue(cursor.nearby.size() >= 2);
    }

    @Test
    public void unusableDocumentsAreRejected() {
        assertFalse(LyricTimeline.parse("[00:01.00]纯音乐请欣赏", "", "", "").usable());
        assertFalse(LyricTimeline.parse("[00:01.00]only one line", "", "", "").usable());
        assertTrue(LyricTimeline.parse(LRC, "", "", "").usable());
    }

    @Test
    public void krcDecodesToWordTiming() throws Exception {
        byte[] key = {0x40, 0x47, 0x61, 0x77, 0x5E, 0x32, 0x74, 0x47, 0x51, 0x36, 0x31, 0x2D,
                (byte) 0xCE, (byte) 0xD2, 0x6E, 0x69};
        String body = "[1000,2000]<0,500,0>你<500,500,0>好\n[3000,1000]<0,1000,0>再见";
        ByteArrayOutputStream packed = new ByteArrayOutputStream();
        try (DeflaterOutputStream deflater =
                     new DeflaterOutputStream(packed, new Deflater(Deflater.BEST_COMPRESSION, false))) {
            deflater.write(body.getBytes(StandardCharsets.UTF_8));
        }
        byte[] deflated = packed.toByteArray();
        byte[] raw = new byte[deflated.length + 4];
        raw[0] = 'k';
        raw[1] = 'r';
        raw[2] = 'c';
        raw[3] = '1';
        for (int i = 0; i < deflated.length; i++) raw[i + 4] = (byte) (deflated[i] ^ key[i % 16]);
        String enhanced = LyricCodecs.kugou(Base64.getEncoder().encodeToString(raw));
        assertTrue(enhanced.contains("(1000,500,0)你"));
        LyricTimeline timeline = LyricTimeline.parseEnhanced(enhanced);
        assertTrue(timeline.hasWordTiming());
        assertEquals(1000, timeline.at(1200).lineStartMs);
        assertEquals("再见", timeline.at(3200).text);
    }

    @Test
    public void markersThatFollowTheirWordAreSlicedForward() {
        String enhanced = LyricCodecs.awlrc("[00:01.50]你<0,500>好<500,1000>");
        assertEquals("[1500,1000](1500,500,0)你(2000,500,0)好\n", enhanced);
        String kuwo = LyricCodecs.kuwoToEnhanced("[00:01.00]你<0,500>好<500,1000>");
        assertEquals("[1000,1000](1000,500,0)你(1500,500,0)好\n", kuwo);
    }

    @Test
    public void jsonBridgeRoundTripsWordTiming() {
        LyricTimeline timeline = LyricTimeline.parse(LRC, TRANSLATION, YRC, "");
        String json = timeline.toJson().toString();
        assertTrue(json.contains("\"w\""));
        LyricTimeline restored = LyricCatalog.fromJson(timeline.toJson());
        assertTrue(restored.hasWordTiming());
        assertEquals("好", restored.at(1750).currentWord);
        assertEquals("第二行", restored.at(5500).translation);
    }
    @Test
    public void aWordTimedDocumentBorrowsTheCreditBlockItDropped() {
        // Shape of the real pair on the test unit: the LRC carries the credits at 0 s and the
        // first sung line at 17.99 s, while the netease KRC starts at 17.56 s with word timing.
        String lrc = "[00:00.00] 作词 : 娃娃\n[00:01.00] 作曲 : 方大同\n"
                + "[00:02.00] 编曲 : 方大同\n[00:17.99]每天每天\n[00:19.37]站在忙乱又无聊的路旁";
        String krc = "[17560,1420](17560,370,0)每(17930,310,0)天(18240,300,0)每(18540,440,0)天\n"
                + "[18980,4150](18980,350,0)站(19330,280,0)在";
        LyricTimeline timed = LyricTimeline.parseEnhanced(krc);
        assertEquals(2, timed.lineCount());
        assertTrue(timed.hasWordTiming());

        LyricTimeline merged = LyricTimelineProvider.withLead(timed, lrc);
        assertEquals(5, merged.lineCount());
        // 2.5 s: the credit line is now the current line, exactly what the card highlights.
        assertEquals("编曲 : 方大同", merged.at(2_500).text);
        // 11 s sits in the gap the KRC left behind; the panel keeps the last line and shows the
        // next one instead of three bare dots.
        LyricTimeline.Cursor gap = merged.at(11_000);
        assertTrue(gap.interlude);
        assertEquals("编曲 : 方大同", gap.previous);
        assertEquals("每天每天", gap.next);
        assertEquals("每天每天", merged.at(17_600).text);
        // Word timing of the sung lines survives the splice.
        assertTrue(merged.hasWordTiming());
        assertEquals("每", merged.at(17_600).sungPrefix());

        // An LRC that only has lines after the timed document's first line adds nothing.
        assertEquals(timed.lineCount(), LyricTimelineProvider.withLead(timed,
                "[00:20.00]第一句\n[00:25.00]第二句").lineCount());
    }}
