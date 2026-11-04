package xyz.i4o.uni.launcher.log;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertTrue;

import org.junit.Test;

import java.util.Arrays;
import java.util.List;

/**
 * Log formatting is pure logic on purpose: the diagnostic package is the only
 * evidence available from a head unit, so its line format and its retention
 * rules must be pinned down by a test rather than by reading a log file.
 */
public class LogFormatTest {
    @Test public void fieldsBecomeGreppableKeyValuePairs() {
        String message = LogFormat.message("写入空调", new Object[]{"func", 0x10010300, "zone", 1});
        assertEquals("写入空调 func=268501760 zone=1", message);
    }

    @Test public void nullFieldIsWrittenOutInsteadOfSkipped() {
        assertEquals("msg value=null", LogFormat.message("msg", new Object[]{"value", null}));
    }

    @Test public void oddFieldCountStillShowsTheDanglingKey() {
        // A dropped value is a bug in the caller; hiding it makes the log lie.
        assertEquals("msg key=(missing)", LogFormat.message("msg", new Object[]{"key"}));
    }

    @Test public void emptyFieldsLeaveTheMessageUntouched() {
        assertEquals("msg", LogFormat.message("msg", new Object[0]));
        assertEquals("msg", LogFormat.message("msg", null));
    }

    @Test public void lineCarriesTimestampLevelTagAndMessage() {
        String line = LogFormat.line("11-03 20:04:12.345", LogLevel.INFO, LogTags.VEHICLE, "通道已连接");
        assertEquals("11-03 20:04:12.345 I UNI/Vehicle : 通道已连接", line);
    }

    @Test public void lineAppendsTheErrorClassAndMessage() {
        String line = LogFormat.line("11-03 20:04:12.345", LogLevel.ERROR, LogTags.LOG,
                "导出异常", new IllegalStateException("磁盘满了"));
        assertTrue(line.endsWith("| IllegalStateException: 磁盘满了"));
    }

    @Test public void recordAlwaysEndsWithALineBreak() {
        // Without the separator the whole file collapses into one line and
        // `grep -n` / `tail -n` become useless.
        assertEquals("line\n", LogFormat.record("line"));
    }

    @Test public void fileNameCarriesDayAndIndex() {
        assertEquals("uni-20261103-0.txt", LogFormat.fileName("20261103", 0));
        assertEquals("uni-20261103-12.txt", LogFormat.fileName("20261103", 12));
    }

    @Test public void sameDayOnlyMatchesItsOwnDay() {
        assertTrue(LogFormat.isSameDay("uni-20261103-0.txt", "20261103"));
        assertFalse(LogFormat.isSameDay("uni-20261102-0.txt", "20261103"));
        assertFalse(LogFormat.isSameDay("other-20261103-0.txt", "20261103"));
    }

    @Test public void retentionKeepsTheNewestFiles() {
        List<String> ordered = Arrays.asList("a", "b", "c", "d");
        assertEquals(Arrays.asList("a", "b"), LogFormat.toRemove(ordered, 2));
        assertTrue(LogFormat.toRemove(ordered, 4).isEmpty());
    }

    @Test public void byteBudgetDropsTheOldestFirst() {
        // Eight files of the same size would exceed the budget even though the
        // file count is still allowed; the byte cap has to win.
        List<LogFormat.FileSize> files = Arrays.asList(
                new LogFormat.FileSize("a", 100),
                new LogFormat.FileSize("b", 100),
                new LogFormat.FileSize("c", 100));
        assertEquals(Arrays.asList("a"), LogFormat.toRemoveByBytes(files, 250));
        assertTrue(LogFormat.toRemoveByBytes(files, 300).isEmpty());
        assertTrue(LogFormat.toRemoveByBytes(files, 0).isEmpty());
    }

    @Test public void anchorRendersWithTheGreppablePrefix() {
        String anchor = LogFormat.anchor("vehicle/read", LogFormat.STAGE_ENTER,
                new Object[]{"source", "official"});
        assertEquals("[ANCHOR] vehicle/read enter source=official", anchor);
    }

    @Test public void anchorSurvivesMissingNameAndStage() {
        assertEquals("[ANCHOR] (unnamed) enter", LogFormat.anchor(null, null, null));
    }

    @Test public void levelThresholdDecidesWhatIsPersisted() {
        assertFalse(LogLevel.DEBUG.reached(LogLevel.INFO));
        assertTrue(LogLevel.INFO.reached(LogLevel.INFO));
        assertTrue(LogLevel.ERROR.reached(LogLevel.WARN));
    }

    @Test public void persistedLevelFallsBackWhenUnrecognised() {
        // A hand-edited or stale value must not break the logger.
        assertEquals(null, LogLevel.byNameOrNull("VERBOSE"));
        assertEquals(null, LogLevel.byNameOrNull(""));
        assertEquals(null, LogLevel.byNameOrNull(null));
        assertEquals(LogLevel.DEBUG, LogLevel.byNameOrNull("DEBUG"));
    }
}
