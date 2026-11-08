package xyz.i4o.uni.launcher.integration.lyrics;

import java.io.File;
import java.util.ArrayList;
import java.util.Iterator;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.ThreadFactory;

/**
 * Per-track lyric resolution with a non-blocking contract.
 *
 * <p>{@code MediaAdapter} builds a snapshot on a binder thread every few hundred
 * milliseconds. It must never wait for an HTTP round trip, and it must not repeat a failed
 * lookup for a track that simply has no lyrics. So:
 *
 * <ul>
 *   <li>a hit in memory or on disk returns the JSON immediately;</li>
 *   <li>a miss starts one background lookup for that recording identity and returns
 *       {@link Result#EMPTY}, which the card already renders as "no lyrics yet";</li>
 *   <li>the lookup finishes on a single worker thread and the next snapshot picks it up,
 *       typically one frame or two later;</li>
 *   <li>a recording that no catalogue knows is remembered as a miss for
 *       {@link #missTtlMs} so stalls in playback do not turn into request storms.</li>
 * </ul>
 *
 * <p>Everything is keyed by {@link LyricCatalog#key} — title, artist and whole seconds —
 * so a track change is simply a different key, and nothing has to be invalidated by hand.
 */
public final class LyricTimelineProvider {
    private static final int MEMORY_ENTRIES = 16;
    /** A word-timed document whose first line is this late is missing its credit block. */
    private static final long LEAD_GAP_MS = 4000;
    private static final int LEAD_MAX_LINES = 40;
    static final long MISS_TTL_MS = 30 * 60 * 1000;
    private static final long MIN_DURATION_MS = 20000;

    private final LyricCatalog catalog;
    private final ExecutorService worker;
    private final Map<String, CacheEntry> memory =
            new LinkedHashMap<String, CacheEntry>(MEMORY_ENTRIES, 0.75f, true) {
                @Override
                protected boolean removeEldestEntry(Map.Entry<String, CacheEntry> eldest) {
                    return size() > MEMORY_ENTRIES;
                }
            };
    private final Map<String, Long> misses = new ConcurrentHashMap<>();
    private final Set<String> inFlight = ConcurrentHashMap.newKeySet();
    /** Told once per background answer so the UI can repaint without waiting for a media event. */
    private final Runnable arrived;

    public LyricTimelineProvider(File cacheDir) {
        this(cacheDir, null);
    }

    /**
     * @param arrived run after a background lookup has just put a document (or a known miss) into
     *                the in-memory cache. Without it the caller has no reason to take a new
     *                snapshot: the card kept the empty state it painted while the request was in
     *                flight until the *next* playback event — a paused track, a skip, a toggle —
     *                which is exactly the "歌在放，歌词一直不出来" report. Runs on the worker
     *                thread; the caller hops to its own thread.
     */
    public LyricTimelineProvider(File cacheDir, Runnable arrived) {
        this.catalog = new LyricCatalog(cacheDir);
        this.arrived = arrived;
        this.worker = Executors.newSingleThreadExecutor(new ThreadFactory() {
            @Override
            public Thread newThread(Runnable runnable) {
                Thread thread = new Thread(runnable, "uni-lyric-timeline");
                thread.setDaemon(true);
                return thread;
            }
        });
    }

    private void notifyArrived() {
        Runnable callback = arrived;
        if (callback == null) return;
        try {
            callback.run();
        } catch (RuntimeException ignored) {
            // The surface is being torn down; the next track asks again.
        }
    }

    public static final class Result {
        public static final Result EMPTY = new Result("", "", false, false, LyricTimeline.EMPTY, "");

        /** Serialised timeline, or "" while the lookup is still running. */
        public final String json;
        /** Catalogue name for the attribution line, e.g. "网易云音乐". */
        public final String label;
        public final boolean wordTimed;
        /** True when the document came from this track's own metadata rather than a catalogue. */
        public final boolean embedded;
        /**
         * The same document as a live object, for surfaces that paint from Java — the cast
         * window on another display — so they never re-parse the JSON string.
         */
        public final LyricTimeline timeline;
        /**
         * The recording this document was resolved for ({@link LyricCatalog#key}). Callers compare
         * it against the track they are painting: a document that belongs to another track must
         * never reach the screen, whatever a cache or a late answer did.
         */
        public final String key;

        Result(String json, String label, boolean wordTimed, boolean embedded,
               LyricTimeline timeline, String key) {
            this.json = json;
            this.label = label;
            this.wordTimed = wordTimed;
            this.embedded = embedded;
            this.timeline = timeline == null ? LyricTimeline.EMPTY : timeline;
            this.key = key == null ? "" : key;
        }

        public boolean isEmpty() {
            return json.isEmpty();
        }
    }

    /**
     * Resolve the timeline for one recording. Never blocks on the network.
     *
     * @param embeddedLrc lyric text the player itself published in its media metadata,
     *                    already handed to us by {@code MediaAdapter.readLyrics}; word tags
     *                    are accepted and used when present
     */
    public Result resolve(String title, String artist, long durationMs, String ownerPackage,
                          String embeddedLrc) {
        return resolve(title, artist, durationMs, ownerPackage, embeddedLrc, "");
    }

    /**
     * @param mediaId the playing app's own id for this recording, when its session publishes
     *                one. Same-catalogue ids skip the search round trip entirely.
     */
    public Result resolve(String title, String artist, long durationMs, String ownerPackage,
                          String embeddedLrc, String mediaId) {
        if (title == null || title.trim().isEmpty()) return Result.EMPTY;
        String key = LyricCatalog.key(title, artist, durationMs);
        if (key.isEmpty()) return Result.EMPTY;

        CacheEntry cachedEntry = memoryGet(key);
        if (cachedEntry != null) {
            if (cachedEntry.leadMerged) return cachedEntry.toResult(key);
            CacheEntry merged = CacheEntry.of(withLead(cachedEntry.timeline, embeddedLrc),
                    cachedEntry.label, cachedEntry.embedded, true);
            memoryPut(key, merged);
            return merged.toResult(key);
        }

        CacheEntry embedded = fromEmbedded(embeddedLrc);
        if (embedded != null) {
            memoryPut(key, embedded);
            return embedded.toResult(key);
        }
        if (durationMs > 0 && durationMs < MIN_DURATION_MS) return Result.EMPTY;

        Long missedAt = misses.get(key);
        if (missedAt != null) {
            if (System.currentTimeMillis() - missedAt < MISS_TTL_MS) return Result.EMPTY;
            misses.remove(key);
        }

        LyricTimeline onDisk = catalog.cached(title, artist, durationMs, "");
        if (!onDisk.isEmpty()) {
            CacheEntry entry = CacheEntry.of(withLead(onDisk, embeddedLrc), "", false, true);
            memoryPut(key, entry);
            return entry.toResult(key);
        }

        request(title, artist, durationMs, ownerPackage, key, mediaId);
        return Result.EMPTY;
    }

    private void request(final String title, final String artist, final long durationMs,
                         final String ownerPackage, final String key, final String mediaId) {
        if (!inFlight.add(key)) return;
        try {
            worker.execute(new Runnable() {
                @Override
                public void run() {
                    try {
                        LyricCatalog.Result result = catalog.load(title, artist, durationMs,
                                ownerPackage, mediaId, new LyricCatalog.Upgrade() {
                                    @Override
                                    public void onBetter(LyricCatalog.Result better) {
                                        // A richer document (word timing) landed after the
                                        // first answer: swap it in so the next snapshot paints
                                        // karaoke without the caller asking again.
                                        memoryPut(key, CacheEntry.of(better.timeline,
                                                better.sourceLabel, false, true));
                                        notifyArrived();
                                    }
                                });
                        if (result.isEmpty()) {
                            misses.put(key, System.currentTimeMillis());
                        } else {
                            memoryPut(key, CacheEntry.of(result.timeline, result.sourceLabel,
                                    false, true));
                        }
                        notifyArrived();
                    } catch (RuntimeException unexpected) {
                        misses.put(key, System.currentTimeMillis());
                    } finally {
                        inFlight.remove(key);
                    }
                }
            });
        } catch (RuntimeException rejected) {
            // The executor is shutting down; the next track starts a fresh one.
            inFlight.remove(key);
        }
    }

    /** Player-published lyric text, including the word-tagged variety. */
    private static CacheEntry fromEmbedded(String text) {
        if (text == null) return null;
        String body = text.trim();
        if (body.isEmpty()) return null;
        boolean tagged = body.indexOf('<') >= 0 && body.indexOf('>') > body.indexOf('<');
        String enhanced = tagged ? LyricCodecs.awlrc(body) : "";
        LyricTimeline timeline = enhanced.isEmpty()
                ? LyricTimeline.parse(body, "", "", "")
                : LyricTimeline.parse(body, "", enhanced, "");
        if (timeline.isEmpty()) return null;
        return CacheEntry.of(timeline, "本地歌词", true);
    }

    /**
     * Splice the plain-LRC lines that come before a word-timed document's first line.
     *
     * <p>netease's KRC starts at the first sung line, so a track whose credits sit at 0–3 s and
     * whose vocal starts at 18 s has a twenty-second hole at the top. The desktop card renders
     * the LRC and shows those credits; the cast panel reads the KRC and showed nothing. Both now
     * read the same content, and the karaoke timing of the real lines is untouched.
     */
    static LyricTimeline withLead(LyricTimeline timeline, String lrcText) {
        if (timeline == null || timeline.isEmpty() || timeline.lines().isEmpty()) return timeline;
        if (lrcText == null || lrcText.trim().isEmpty()) return timeline;
        long first = timeline.lines().get(0).timeMs;
        if (first < LEAD_GAP_MS) return timeline;
        LyricTimeline plain = LyricTimeline.parse(lrcText, "", "", "");
        if (plain.isEmpty()) return timeline;
        List<LyricTimeline.Line> head = new ArrayList<>();
        for (LyricTimeline.Line line : plain.lines()) {
            if (line.timeMs >= first) break;
            if (line.text.trim().isEmpty()) continue;
            // The tail of the plain document may hold a translated duplicate of the same line;
            // its content is already in the timed document, and here it would land as a gap.
            head.add(line);
            if (head.size() >= LEAD_MAX_LINES) break;
        }
        if (head.isEmpty()) return timeline;
        return timeline.withLeadLines(head);
    }

    private CacheEntry memoryGet(String key) {
        synchronized (memory) {
            return memory.get(key);
        }
    }

    private void memoryPut(String key, CacheEntry entry) {
        synchronized (memory) {
            memory.put(key, entry);
        }
    }

    /** Drops learned misses, e.g. after the user changed the lyric source setting. */
    public void forgetMisses() {
        misses.clear();
    }

    public void shutdown() {
        worker.shutdownNow();
        synchronized (memory) {
            memory.clear();
        }
        misses.clear();
    }

    /** Serialised snapshot kept in memory so a steady track costs no re-serialisation. */
    private static final class CacheEntry {
        final String json;
        final String label;
        final boolean wordTimed;
        final boolean embedded;
        final boolean leadMerged;
        final LyricTimeline timeline;

        private CacheEntry(String json, String label, boolean wordTimed, boolean embedded,
                      LyricTimeline timeline, boolean leadMerged) {
            this.json = json;
            this.label = label;
            this.wordTimed = wordTimed;
            this.embedded = embedded;
            this.timeline = timeline;
            this.leadMerged = leadMerged;
        }

        static CacheEntry of(LyricTimeline timeline, String label, boolean embedded) {
            return of(timeline, label, embedded, false);
        }

        static CacheEntry of(LyricTimeline timeline, String label, boolean embedded,
                             boolean leadMerged) {
            return new CacheEntry(timeline.toJson().toString(), label, timeline.hasWordTiming(),
                    embedded, timeline, leadMerged);
        }

        Result toResult(String key) {
            return new Result(json, label, wordTimed, embedded, timeline, key);
        }
    }

    /** Diagnostics: how many recordings are being looked up right now. */
    public int pendingCount() {
        return inFlight.size();
    }

    /** Diagnostics: known misses, oldest first. */
    public String describeMisses() {
        StringBuilder out = new StringBuilder();
        for (Iterator<Map.Entry<String, Long>> it = misses.entrySet().iterator(); it.hasNext(); ) {
            out.append(it.next().getKey());
            if (it.hasNext()) out.append(", ");
        }
        return out.toString();
    }
}

