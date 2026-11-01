package xyz.i4o.uni.launcher.integration;

/** Reject results from an earlier request or an earlier adapter lifecycle. */
public final class ForecastRequestGate {
    private long generation;
    private boolean active;

    public void start() { active = true; generation++; }
    public void stop() { active = false; generation++; }
    public long next() { return ++generation; }
    public boolean accepts(long request) { return active && generation == request; }
}
