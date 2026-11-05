package xyz.i4o.uni.launcher.log;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertTrue;

import org.junit.Before;
import org.junit.Test;

/**
 * The anchor ledger answers "which step did this chain stop at" and "which
 * node never fired at all". Both answers are worthless if the counters drift,
 * so they are pinned here.
 */
public class AnchorLedgerTest {
    @Before public void reset() {
        AnchorLedger.reset();
    }

    @Test public void stagesAreCountedPerNodeAndTag() {
        AnchorLedger.record(LogTags.VEHICLE, "vehicle/read", LogFormat.STAGE_ENTER, "x");
        AnchorLedger.record(LogTags.VEHICLE, "vehicle/read", LogFormat.STAGE_ENTER, "x");
        AnchorLedger.record(LogTags.VEHICLE, "vehicle/read", LogFormat.STAGE_DONE, "x");
        AnchorLedger.record(LogTags.VEHICLE, "vehicle/command", LogFormat.STAGE_ENTER, "x");

        assertEquals(2, AnchorLedger.nodeCount());
        String described = AnchorLedger.describe();
        assertTrue(described.contains("UNI/Vehicle vehicle/read"));
        assertTrue(described.contains("enter=2"));
        assertTrue(described.contains("done=1"));
    }

    @Test public void recentKeepsTheNewestFirst() {
        AnchorLedger.record(LogTags.APP, "a", LogFormat.STAGE_ENTER,
                LogFormat.anchor("a", LogFormat.STAGE_ENTER, null));
        AnchorLedger.record(LogTags.APP, "b", LogFormat.STAGE_ENTER,
                LogFormat.anchor("b", LogFormat.STAGE_ENTER, null));
        String recent = AnchorLedger.recent(10);
        assertTrue(recent.indexOf("b") >= 0);
        assertTrue(recent.indexOf("a") >= 0);
        assertTrue(recent.indexOf("b") < recent.indexOf("a"));
    }

    @Test public void emptyLedgerSaysSoInsteadOfPrintingNothing() {
        assertTrue(AnchorLedger.describe().contains("没有记录锚点"));
        assertTrue(AnchorLedger.recent(5).contains("没有记录锚点"));
    }

    @Test public void resetClearsCountsAndHistory() {
        AnchorLedger.record(LogTags.APP, "a", LogFormat.STAGE_ENTER, "");
        AnchorLedger.reset();
        assertEquals(0, AnchorLedger.nodeCount());
        assertTrue(AnchorLedger.recentLines().isEmpty());
    }
}
