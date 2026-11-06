package xyz.i4o.uni.launcher.integration.lyrics;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertTrue;

import org.junit.Test;

import java.io.File;
import java.io.FileOutputStream;
import java.nio.charset.StandardCharsets;
import java.util.List;

/** The lookup rules that do not need a network: ordering, query variants, upgrade, sources. */
public class LyricSourcesTest {

    @Test
    public void theOwningCatalogueIsAskedFirstAndIsNotAskedTwice() {
        String[] plan = LyricCatalog.plan("com.tencent.qqmusic");
        assertEquals(LyricCatalog.QQ, plan[0]);
        assertEquals(plan.length, LyricCatalog.order().length);
        int seen = 0;
        for (String provider : plan) if (LyricCatalog.QQ.equals(provider)) seen++;
        assertEquals(1, seen);
    }

    @Test
    public void anUnknownPlayerFallsBackToTheFixedOrder() {
        assertEquals(LyricCatalog.NETEASE, LyricCatalog.plan("com.example.player")[0]);
        assertEquals(LyricCatalog.order().length, LyricCatalog.plan(null).length);
    }

    @Test
    public void queryVariantsGoFromSpecificToForgiving() {
        List<String[]> variants = LyricCatalog.variants("飞 (Live)", "某某");
        assertTrue("the raw title is tried first",
                "飞 (Live)".equals(variants.get(0)[0]));
        boolean cutFound = false;
        for (String[] variant : variants) {
            if ("飞".equals(variant[0])) cutFound = true;
        }
        assertTrue("the subtitle is dropped at some point", cutFound);
        assertTrue("variants stay bounded", variants.size() <= 4);
    }

    @Test
    public void duplicateSpellingsAreNotTriedTwice() {
        List<String[]> variants = LyricCatalog.variants("飞", "某某");
        assertEquals(1, variants.size());
    }

    @Test
    public void aWordTimedDocumentUpgradesAPlainOne() {
        LyricTimeline plain = LyricTimeline.parse(
                "[00:01.00]第一行\n[00:05.00]第二行\n", "", "", "");
        LyricTimeline timed = LyricTimeline.parse(
                "[00:01.00]第一行\n[00:05.00]第二行\n", "", 
                "[1000,4000](1000,900,0)第一行(1900,2100,0)\n"
                        + "[5000,4000](5000,2000,0)第二行(7000,2000,0)\n", "");
        LyricCatalog.Result first = new LyricCatalog.Result(plain, "kuwo", "酷我音乐", false,
                plain.qualityScore());
        LyricCatalog.Result better = new LyricCatalog.Result(timed, "netease", "网易云音乐",
                false, timed.qualityScore());
        assertTrue("karaoke must win", better.betterThan(first));
        assertFalse("plain must not replace karaoke", first.betterThan(better));
        assertFalse("a miss never upgrades a hit", LyricCatalog.Result.EMPTY.betterThan(first));
        assertTrue("a hit always beats a miss", first.betterThan(LyricCatalog.Result.EMPTY));
    }

    @Test
    public void aCacheHitKeepsItsScore() {
        LyricTimeline timed = LyricTimeline.parse(
                "[00:01.00]一行\n[00:05.00]二行\n", "",
                "[1000,4000](1000,900,0)一行(1900,2100,0)\n"
                        + "[5000,4000](5000,2000,0)二行(7000,2000,0)\n", "");
        LyricCatalog.Result hit = new LyricCatalog.Result(timed, "", "本地缓存", true,
                timed.qualityScore());
        // One above the raw quality: any usable document outscores "no document".
        assertEquals(timed.qualityScore() + 1, hit.score);
        assertTrue(hit.score > 0);
    }

    @Test
    public void miguSignatureIsStableForAGivenTimestamp() throws Exception {
        String first = LyricCatalog.miguSign("每天每天", 1700000000000L);
        String second = LyricCatalog.miguSign("每天每天", 1700000000000L);
        assertEquals(first, second);
        assertEquals(32, first.length());
        assertFalse(first.equals(LyricCatalog.miguSign("每天每天", 1700000000001L)));
    }

    @Test
    public void aSodaSharePageYieldsLinesWordsAndTranslation() {
        String html = "<html><script>window._ROUTER_DATA = {\"loaderData\":{\"track_page\":"
                + "{\"audioWithLyricsOption\":{\"lyrics\":{\"sentences\":["
                + "{\"startMs\":1000,\"endMs\":5000,\"text\":\"第一行\",\"translation\":\"line one\","
                + "\"words\":[{\"startMs\":1000,\"endMs\":3000,\"text\":\"第一\"},"
                + "{\"startMs\":3000,\"endMs\":5000,\"text\":\"行\"}]},"
                + "{\"startMs\":6000,\"endMs\":9000,\"words\":[{\"startMs\":6000,\"endMs\":9000,"
                + "\"text\":\"第二行\"}]}]}}}}};</script></html>";
        LyricTimeline timeline = LyricCatalog.sodaPage(html);
        assertEquals(2, timeline.lines().size());
        assertEquals("第一行", timeline.lines().get(0).text);
        assertEquals("line one", timeline.lines().get(0).translation);
        assertTrue("word timing must survive", timeline.lines().get(0).words.size() >= 2);
        assertEquals("a sentence without text borrows its words",
                "第二行", timeline.lines().get(1).text);
        assertTrue(timeline.hasWordTiming());
    }

    @Test
    public void aSharePageWithoutLyricsIsAMiss() {
        assertTrue(LyricCatalog.sodaPage("<html>no router data</html>").isEmpty());
        assertTrue(LyricCatalog.sodaPage("").isEmpty());
        assertTrue(LyricCatalog.sodaPage("window._ROUTER_DATA = {\"loaderData\":{}}").isEmpty());
    }

    @Test
    public void sodaAndMiguAreKnownCatalogueOwners() {
        assertEquals(LyricCatalog.SODA, LyricCatalog.providerForPackage("com.luna.music"));
        assertEquals(LyricCatalog.MIGU, LyricCatalog.providerForPackage("cn.migu.music"));
        assertEquals("汽水音乐", LyricCatalog.label(LyricCatalog.SODA));
        assertEquals("咪咕音乐", LyricCatalog.label(LyricCatalog.MIGU));
    }

    @Test
    public void offsetIsClampedAndPerTrackIsAdditive() {
        assertEquals(LyricOffset.LIMIT_MS, LyricOffset.clamp(99999));
        assertEquals(-LyricOffset.LIMIT_MS, LyricOffset.clamp(-99999));
        LyricOffset.configure(200, "某某", "某人", 150);
        assertEquals(350, LyricOffset.forTrack("某某", "某人"));
        assertEquals(200, LyricOffset.forTrack("别的歌", "某人"));
        LyricOffset.configure(0, "", "", 0);
        assertEquals(0, LyricOffset.forTrack("某某", "某人"));
    }

    @Test
    public void capacityPolicyTrimsTheOldestFilesFirst() throws Exception {
        File dir = File.createTempFile("lyric-cache", "dir");
        assertTrue(dir.delete());
        assertTrue(dir.mkdirs());
        try {
            long[] sizes = {400, 400, 400};
            for (int i = 0; i < sizes.length; i++) {
                File file = new File(dir, "doc" + i);
                try (FileOutputStream out = new FileOutputStream(file)) {
                    out.write(new byte[(int) sizes[i]]);
                }
                assertTrue(file.setLastModified(1000L * (i + 1)));
            }
            // 1200 bytes on disk, a 700-byte ceiling: the two oldest go, the newest stays.
            int removed = LyricCachePolicy.trimToBytes(dir.listFiles(), 700);
            assertEquals(2, removed);
            assertEquals(1, dir.listFiles().length);
            assertTrue(new File(dir, "doc2").isFile());
        } finally {
            File[] left = dir.listFiles();
            if (left != null) for (File file : left) file.delete();
            dir.delete();
        }
    }

    @Test
    public void foreverPolicyNeverDeletesAnything() throws Exception {
        File dir = File.createTempFile("lyric-cache", "keep");
        assertTrue(dir.delete());
        assertTrue(dir.mkdirs());
        try {
            File file = new File(dir, "old");
            try (FileOutputStream out = new FileOutputStream(file)) {
                out.write(new byte[10]);
            }
            assertTrue(file.setLastModified(0L));
            assertEquals(0, LyricCachePolicy.sweep(dir, LyricCachePolicy.FOREVER, 1,
                    System.currentTimeMillis()));
            assertTrue(file.isFile());
        } finally {
            File[] left = dir.listFiles();
            if (left != null) for (File f : left) f.delete();
            dir.delete();
        }
    }

    @Test
    public void aFlacCommentCarriesItsLyrics() throws Exception {
        String lyrics = "[00:01.00]第一行\n[00:05.00]第二行\n[00:09.00]第三行\n";
        byte[] comment = ("LYRICS=" + lyrics).getBytes(StandardCharsets.UTF_8);
        byte[] data = new byte[4 + 4 + comment.length];
        data[0] = 'f';
        data[1] = 'L';
        data[2] = 'a';
        data[3] = 'C';
        data[4] = (byte) (0x80 | 4);            // last block, VORBIS_COMMENT
        data[5] = (byte) ((comment.length >> 16) & 0xFF);
        data[6] = (byte) ((comment.length >> 8) & 0xFF);
        data[7] = (byte) (comment.length & 0xFF);
        System.arraycopy(comment, 0, data, 8, comment.length);
        File file = File.createTempFile("lyric", ".flac");
        try {
            try (FileOutputStream out = new FileOutputStream(file)) {
                out.write(data);
            }
            String text = EmbeddedLyricReader.read(file);
            assertTrue(text.contains("第一行"));
            assertTrue(text.startsWith("[00:01.00]"));
        } finally {
            assertTrue(file.delete());
        }
    }

    @Test
    public void aFileWithoutLyricsReadsAsEmpty() throws Exception {
        File file = File.createTempFile("no-lyric", ".mp3");
        try {
            try (FileOutputStream out = new FileOutputStream(file)) {
                out.write(new byte[4096]);
            }
            assertEquals("", EmbeddedLyricReader.read(file));
        } finally {
            assertTrue(file.delete());
        }
        assertEquals("", EmbeddedLyricReader.read(null));
    }

    // ---- Migu MRC ----

    @Test
    public void miguMrcDecryptsWhatXxteaEncrypts() {
        String plain = "[1000,500]听见冬天的离开\n[2000,400](2000,300)我在某年某月醒过来\n";
        String cipher = miguEncrypt(plain);
        assertTrue("cipher must be pure hex of whole 16-char words",
                cipher.matches("([0-9a-f]{16})+"));
        assertEquals(plain, LyricCodecs.mrcText(cipher));
    }

    @Test
    public void miguMrcPassesPlainLrcThroughUntouched() {
        String lrc = "[00:01.00]第一行\n[00:03.00]第二行";
        assertEquals(lrc, LyricCodecs.mrcText(lrc));
    }

    @Test
    public void miguMrcRejectsWhatIsNotAContainer() {
        assertEquals("", LyricCodecs.mrcText(null));
        assertEquals("", LyricCodecs.mrcText(""));
        assertTrue("too short to be a container, so it comes back as text",
                LyricCodecs.mrcText("00112233").equals("00112233"));
        assertEquals("", LyricCodecs.mrcText("zzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz"));
        // 词级入口对“不是词级文档”的回答是空串，调用方据此退回 lrcUrl。
        assertEquals("", LyricCodecs.migu("00112233"));
        assertEquals("", LyricCodecs.migu("[00:01.00]没有词标记的行级歌词"));
    }

    @Test
    public void miguWordMarkersBecomeEnhancedLrc() {
        // 真实载荷里标记跟在音节后面：起(0,0)风(0,0)了 —— 每个标记关掉它前面那段文字。
        assertEquals("[1000,500](1100,200,0)你好(1350,150,0)世界回家\n",
                LyricCodecs.miguToEnhanced("[1000,500]你好(1100,200)世界(1350,150)回家"));
        assertEquals("", LyricCodecs.miguToEnhanced("[1000,500]没有词标记"));
        assertEquals("", LyricCodecs.miguToEnhanced(null));
    }

    @Test
    public void miguMetadataAndSeparatorsDoNotEatTheFirstSyllable() {
        // 真实载荷：前置 [ti:]/[ar:]，行与行之间没有 \n（是 U+000A 混 U+2028 之类的分隔）。
        String raw = "[ti:起风了]\n[ar:某某]\u2028[0,0]起(0,0)风(0,0)了(0,0)"
                + "\u2028[9000,300]我(9000,120)曾(9120,180)";
        assertEquals("[0,0](0,0,0)起(0,0,0)风(0,0,0)了\n[9000,300](9000,120,0)我(9120,180,0)曾\n",
                LyricCodecs.miguToEnhanced(raw));
    }

    @Test
    public void miguSearchDurationsComeBackInSeconds() {
        // 咪咕搜索给了 256，按毫秒比对会把 4 分钟的曲子判成完全不同的录音（score 直接 0）。
        assertEquals(256000L, LyricCatalog.miguDuration(256));
        assertEquals(256000L, LyricCatalog.miguDuration(256000));
        assertEquals(0L, LyricCatalog.miguDuration(0));
    }

    @Test
    public void miguSearchDurationsComeBackInSecondsAndScore() {
        double seconds = LyricCatalog.score("孤勇者", "陈奕迅", "孤勇者", "陈奕迅",
                255000, LyricCatalog.miguDuration(256));
        assertTrue("a 256-second hit must clear the gate, not read as a mismatch", seconds >= 3);
        assertEquals(0, LyricCatalog.miguDuration(0));
    }

    /** XXTEA encrypt, mirroring {@code LyricCodecs#mix}; only the test uses it to prove the inverse. */
    private static String miguEncrypt(String plain) {
        byte[] utf16 = plain.getBytes(StandardCharsets.UTF_16LE);
        int words = (utf16.length + 7) / 8;
        long[] block = new long[words];
        for (int i = 0; i < words; i++) {
            long word = 0;
            for (int b = 7; b >= 0; b--) {
                int index = i * 8 + b;
                word = (word << 8) | (index < utf16.length ? utf16[index] & 0xFF : 0);
            }
            block[i] = word;
        }
        long sum = 0;
        long delta = 2654435769L;
        int rounds = 6 + 52 / words;
        long last = block[words - 1];
        while (rounds-- > 0) {
            sum += delta;
            int shift = (int) ((sum >>> 2) & 3);
            for (int i = 0; i < words - 1; i++) {
                last = block[i] + miguMix(block[i + 1], last, sum,
                        miguKey((i & 3) ^ shift));
                block[i] = last;
            }
            last = block[words - 1] + miguMix(block[0], last, sum,
                    miguKey(((words - 1) & 3) ^ shift));
            block[words - 1] = last;
        }
        StringBuilder out = new StringBuilder(words * 16);
        for (long word : block) {
            String hex = Long.toHexString(word);
            for (int pad = hex.length(); pad < 16; pad++) out.append('0');
            out.append(hex);
        }
        return out.toString();
    }

    private static long miguMix(long y, long z, long sum, long key) {
        return ((sum ^ y) + (key ^ z)) ^ (((z >> 5) ^ (y << 2)) + ((y >> 3) ^ (z << 4)));
    }

    private static long miguKey(int index) {
        long[] key = {
            27303562373562475L, 18014862372307051L, 22799692160172081L, 34058940340699235L,
            30962724186095721L, 27303523720101991L, 27303523720101998L, 31244139033526382L,
            28992395054481524L
        };
        return key[index & 7];
    }
}
