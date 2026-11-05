package xyz.i4o.uni.launcher.integration.lyrics;

/**
 * The lyric state every surface in the process can read: the card and dock already receive
 * it as a snapshot, but the cast window lives on another display and has no snapshot of its
 * own. Rather than teaching a second consumer to subscribe to {@code MediaSession}, the media
 * adapter publishes here and the cast window samples it at frame time.
 *
 * <p>The clock is kept, not advanced: a state holds the position and the wall time it was
 * sampled at plus the playback speed, so any reader can ask "where are we now" without
 * owning a timer. Paused state simply does not advance.
 *
 * <p>Android-free; {@code nowMs} is always injected.
 */
public final class LyricCast {
    private static volatile State current = State.EMPTY;

    private LyricCast() {
    }

    /** Immutable snapshot of what is playing, published by the media adapter. */
    public static final class State {
        public static final State EMPTY = new State("", "", "", LyricTimeline.EMPTY, false, 0, 0, 1f);

        public final String title;
        public final String artist;
        public final String sourceLabel;
        public final LyricTimeline timeline;
        public final boolean playing;
        public final long positionMs;
        public final long sampledAtMs;
        public final float speed;

        State(String title, String artist, String sourceLabel, LyricTimeline timeline,
              boolean playing, long positionMs, long sampledAtMs, float speed) {
            this.title = title == null ? "" : title;
            this.artist = artist == null ? "" : artist;
            this.sourceLabel = sourceLabel == null ? "" : sourceLabel;
            this.timeline = timeline == null ? LyricTimeline.EMPTY : timeline;
            this.playing = playing;
            this.positionMs = Math.max(0, positionMs);
            this.sampledAtMs = Math.max(0, sampledAtMs);
            this.speed = speed > 0 ? speed : 1f;
        }

        /** Playback position at {@code nowMs}, advanced only while playing. */
        public long positionAt(long nowMs) {
            if (!playing || sampledAtMs <= 0 || nowMs <= sampledAtMs) return positionMs;
            long advanced = (long) ((nowMs - sampledAtMs) * (double) speed);
            return positionMs + Math.max(0, advanced);
        }

        public LyricTimeline.Cursor cursorAt(long nowMs) {
            return timeline.at(positionAt(nowMs));
        }

        public boolean hasTimeline() {
            return !timeline.isEmpty();
        }
    }

    /**
     * Publish one sampled state. Called from the media adapter on the same cadence as the
     * snapshot, so the cast window trails the card by at most one snapshot.
     */
    public static void publish(String title, String artist, String sourceLabel,
                               LyricTimeline timeline, boolean playing, long positionMs,
                               long sampledAtMs, float speed) {
        current = new State(title, artist, sourceLabel, timeline, playing, positionMs,
                sampledAtMs, speed);
    }

    public static void clear() {
        current = State.EMPTY;
    }

    public static State state() {
        return current;
    }

    public static LyricTimeline.Cursor cursorAt(long nowMs) {
        return current.cursorAt(nowMs);
    }
}
