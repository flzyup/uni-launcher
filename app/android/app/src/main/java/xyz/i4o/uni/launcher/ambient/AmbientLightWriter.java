package xyz.i4o.uni.launcher.ambient;

import android.util.Log;

import java.lang.reflect.Method;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.concurrent.CopyOnWriteArrayList;
import java.util.concurrent.Executors;
import java.util.concurrent.RejectedExecutionException;
import java.util.concurrent.ScheduledExecutorService;
import java.util.concurrent.ThreadFactory;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicBoolean;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.function.Supplier;

/**
 * Writes the computed ambient colour to the head unit.
 *
 * <p>The {@code ICarFunction} handle is borrowed from the vehicle transport
 * that already owns the SDK connection. This class never creates, binds,
 * subscribes or disconnects anything, and it only writes when the caller
 * explicitly asks for a colour, a switch or a brightness.
 *
 * <p>Writes run on a dedicated background thread: the vendor call is a Binder
 * round trip and must never sit on the Flutter platform thread.
 *
 * <h3>Throttling</h3>
 * A spectrum frame arrives every 100 ms while music plays. Writing every
 * frame would keep the head unit busy for no visible gain, so two gates apply:
 * a minimum interval between writes and a minimum colour distance. The first
 * write after a change always goes through.
 *
 * <h3>Only the latest frame is written</h3>
 * The spectrum arrives ten times a second. If the vehicle is slow, queuing
 * every frame makes the queue grow without bound: the writer falls further
 * behind, which makes it slower still. So only the newest colour is kept and
 * the frames in between are dropped. A colour describes what the strip should
 * show now, so a skipped frame has no value.
 *
 * <h3>Failures</h3>
 * A failed write is retried, but not at the frame rate: the head unit does
 * not accept a colour that never arrives, and a blind 10 Hz retry storm
 * floods the vehicle IO. Failed writes therefore wait for
 * {@link #FAIL_BACKOFF_MS} before the next attempt.
 *
 * <h3>The switch and the brightness are retried</h3>
 * Lighting the strip needs a sequence: main colour source, experience mode,
 * three zones, interactive effect. The vehicle service connects
 * asynchronously, so the first attempt very often fails. The switch and the
 * brightness are therefore kept as "desired" state and written again every
 * {@link #STATE_RETRY_MS} until the head unit accepts them.
 */
public final class AmbientLightWriter {
    private static final String TAG = "UniAmbient";

    /** Minimum time between two colour writes, in milliseconds. */
    public static final long MIN_INTERVAL_MS = 120L;

    /** Minimum colour distance that still counts as a change. */
    public static final int MIN_COLOR_DELTA = 8;

    /**
     * How long a failed write waits before the next attempt.
     *
     * <p>The spectrum arrives ten times a second. Retrying every frame would
     * flood the vehicle IO with writes the head unit rejects.
     */
    public static final long FAIL_BACKOFF_MS = 1000L;

    /** How often the switch and the brightness are written again. */
    public static final long STATE_RETRY_MS = 3000L;

    /** Notified when the capability state or the failure reason changes. */
    public interface StateListener {
        void onAmbientState(Map<String, Object> state);
    }

    private final AmbientLightResolver resolver = new AmbientLightResolver();
    private final Supplier<Object> handle;
    private final List<StateListener> listeners = new CopyOnWriteArrayList<>();

    private final ScheduledExecutorService worker =
            Executors.newSingleThreadScheduledExecutor(
                    new ThreadFactory() {
                        @Override public Thread newThread(Runnable runnable) {
                            Thread thread = new Thread(runnable, "uni-ambient-light");
                            thread.setPriority(Thread.MIN_PRIORITY);
                            return thread;
                        }
                    });

    /** The newest colour that still has to be written, or -1. */
    private final AtomicInteger pendingRgb = new AtomicInteger(-1);

    /** Whether a colour write is already queued. */
    private final AtomicBoolean colorScheduled = new AtomicBoolean(false);

    /** Whether a state retry is already queued. */
    private final AtomicBoolean stateRetryScheduled = new AtomicBoolean(false);

    private volatile boolean enabled;
    private volatile boolean available;
    private volatile String reason = "";
    private volatile int lastRgb = -1;
    private volatile int lastBrightness = -1;
    private volatile long lastWriteAt;
    private volatile boolean experienceCustomWritten;

    /** Whether {@link #lastRgb} holds a colour the head unit accepted. */
    private volatile boolean lastColorAccepted;

    /** Whether the most recent write failed. */
    private volatile boolean lastWriteFailed;

    /** The folded brightness step the head unit accepted last. */
    private volatile int lastBrightnessStep = -1;

    /** What the user wants the strip to do. */
    private volatile Boolean desiredEnabled;

    /** What the head unit has accepted. */
    private volatile Boolean writtenEnabled;

    /** The absolute brightness that still has to be written. */
    private volatile Integer pendingBrightness;

    /** The last write, for the diagnostics dump. */
    private volatile String lastOp = "";
    private volatile int lastFunction;
    private volatile int lastZone = -1;
    private volatile int lastValue;
    private volatile boolean lastWriteOk;
    private volatile String lastError = "";

    /** Signature of the last state that was pushed to the listeners. */
    private volatile String pushedSignature = "";

    /**
     * How many writes of each kind reached this writer.
     *
     * <p>The counters count <em>attempts</em>, not successes: they show that
     * the app is really driving the strip, even on a device where the vendor
     * framework is missing and every write is refused.
     */
    private volatile int colorWrites;
    private volatile int brightnessWrites;
    private volatile int enableWrites;

    /**
     * @param handle supplies the borrowed {@code ICarFunction} instance, or
     *               null while the vehicle transport is not ready
     */
    public AmbientLightWriter(Supplier<Object> handle) {
        this.handle = handle;
    }

    /** The resolver used for vendor ids, exposed for diagnostics. */
    public AmbientLightResolver resolver() {
        return resolver;
    }

    /** Registers a listener that is told about capability changes. */
    public void addStateListener(StateListener listener) {
        if (listener != null) listeners.add(listener);
    }

    /** Removes a previously registered listener. */
    public void removeStateListener(StateListener listener) {
        if (listener != null) listeners.remove(listener);
    }

    /**
     * The borrowed function handle, with its class registered as the most
     * accurate lookup root.
     *
     * <p>The constants live in the same jar as the handle, so resolving them
     * from the handle's own class is more reliable than guessing the host
     * interface name.
     */
    private Object functions() {
        Object functions = handle.get();
        if (functions != null) resolver.registerRoot(functions.getClass());
        return functions;
    }

    /** Whether the strip is switched on. */
    public boolean enabled() {
        return enabled;
    }

    /**
     * Switches the strip on or off.
     *
     * <p>Switching on sets the main colour source to the custom colour, sets
     * the experience mode to custom, lights all three zones and turns the
     * interactive effect (the vendor's music reaction) on. Switching off only
     * turns the interactive effect off and leaves the main colour in place,
     * so the next switch-on lights up immediately.
     */
    public void setEnabled(final boolean value) {
        desiredEnabled = value;
        // The head unit may have lost the state, so the sequence is written
        // again even when the desired value did not change.
        writtenEnabled = null;
        worker.execute(new Runnable() {
            @Override public void run() {
                writeState();
            }
        });
        scheduleStateRetry();
    }

    /**
     * Writes one colour.
     *
     * <p>The colour is packed as 0xRRGGBB, which is how the vendor splits it
     * back into red, green and blue.
     */
    public void applyColor(final int r, final int g, final int b) {
        pendingRgb.set(((r & 0xFF) << 16) | ((g & 0xFF) << 8) | (b & 0xFF));
        if (colorScheduled.compareAndSet(false, true)) {
            worker.execute(new Runnable() {
                @Override public void run() {
                    drainColors();
                }
            });
        }
    }

    /**
     * Sets the brightness, 0 to 100.
     *
     * <p>The value is the user's absolute brightness, not the spectrum
     * derived one: the head unit only offers three steps, and the music
     * reaction shows in the colour instead.
     *
     * <p>Both ladders are written: the driving one and the parked one. The
     * head unit picks the ladder that applies to the current state, so
     * writing the same value to both keeps the brightness the same whether
     * the car is moving or not.
     */
    public void setBrightness(final int brightness) {
        pendingBrightness = brightness;
        worker.execute(new Runnable() {
            @Override public void run() {
                writeState();
            }
        });
        scheduleStateRetry();
    }

    /** Releases the background thread. */
    public void close() {
        worker.shutdownNow();
        try {
            worker.awaitTermination(500, TimeUnit.MILLISECONDS);
        } catch (InterruptedException interrupted) {
            Thread.currentThread().interrupt();
        }
    }

    /**
     * Capability and last write state, for the settings page and dumpsys.
     *
     * <p>A plain map is returned rather than a {@code JSONObject}: the
     * platform channel encodes maps directly, while the rest of this project
     * passes JSON as text.
     */
    public Map<String, Object> status() {
        Map<String, Object> result = new LinkedHashMap<>();
        try {
            Object functions = functions();
            boolean ready = functions != null;
            result.put("available", ready);
            result.put("enabled", enabled);
            result.put("backend", ready ? "ECARX AdaptAPI" : "未接入");
            result.put("reason", reason);
            result.put("lastRgb", lastRgb);
            result.put("lastBrightness", lastBrightness);
            result.put("colorWrites", colorWrites);
            result.put("brightnessWrites", brightnessWrites);
            result.put("enableWrites", enableWrites);
            result.put("resolved",
                    resolver.resolve(AmbientLightContract.FUNC_COLOR_SET) != null);
            result.put("unresolved", unresolvedNames());
            // The detail that tells "no vehicle handle" and "the ids do not
            // resolve" apart. Both look identical in the reason string alone.
            result.put("handlePresent", ready);
            result.put("switchApplied", Boolean.TRUE.equals(writtenEnabled));
            result.put("desiredEnabled", desiredEnabled);
            result.put("pendingBrightness", pendingBrightness);
            result.put("lastBrightnessStep", lastBrightnessStep);
            result.put("resolvedIds", resolvedIds());
            Map<String, Object> write = new LinkedHashMap<>();
            write.put("op", lastOp);
            write.put("function", lastFunction);
            write.put("zone", lastZone);
            write.put("value", lastValue);
            write.put("ok", lastWriteOk);
            write.put("error", lastError);
            result.put("lastWrite", write);
        } catch (Exception ignored) {
            result.put("available", false);
            result.put("reason", "状态读取失败");
        }
        return result;
    }

    // ----------------------------------------------------------------- internals

    /**
     * Writes the desired state: the switch first, then the brightness.
     *
     * <p>Called on the writer thread only.
     */
    private void writeState() {
        Boolean want = desiredEnabled;
        if (want != null && !want.equals(writtenEnabled)) {
            if (applyEnabled(want)) writtenEnabled = want;
        }
        Integer brightness = pendingBrightness;
        if (brightness != null) {
            if (applyBrightness(brightness)) pendingBrightness = null;
        }
    }

    /**
     * Queues the next state attempt.
     *
     * <p>The vehicle service connects asynchronously, so the switch and the
     * brightness are written again until the head unit accepts them.
     */
    private void scheduleStateRetry() {
        if (!stateRetryScheduled.compareAndSet(false, true)) return;
        try {
            worker.schedule(new Runnable() {
                @Override public void run() {
                    stateRetryScheduled.set(false);
                    if (!statePending()) return;
                    writeState();
                    if (statePending()) scheduleStateRetry();
                }
            }, STATE_RETRY_MS, TimeUnit.MILLISECONDS);
        } catch (RejectedExecutionException stopped) {
            stateRetryScheduled.set(false);
        }
    }

    /** Whether the switch or the brightness still has to be written. */
    private boolean statePending() {
        Boolean want = desiredEnabled;
        if (want != null && !want.equals(writtenEnabled)) return true;
        return pendingBrightness != null;
    }

    /**
     * Writes the newest colour, dropping the frames in between.
     *
     * <p>Called on the writer thread only.
     */
    private void drainColors() {
        try {
            while (true) {
                int rgb = pendingRgb.getAndSet(-1);
                if (rgb < 0) break;
                applyRgb(rgb);
                if (pendingRgb.get() < 0) break;
            }
        } finally {
            colorScheduled.set(false);
            // A frame that arrived while the last one was written.
            if (pendingRgb.get() >= 0 && colorScheduled.compareAndSet(false, true)) {
                worker.execute(new Runnable() {
                    @Override public void run() {
                        drainColors();
                    }
                });
            }
        }
    }

    /**
     * The switch-on sequence.
     *
     * @return true when the head unit accepted it
     */
    private boolean applyEnabled(boolean value) {
        enableWrites++;
        Object functions = functions();
        if (functions == null) {
            unavailable("车机车辆服务尚未就绪");
            pushStateIfChanged();
            return false;
        }
        Integer effect = resolver.resolve(AmbientLightContract.FUNC_INTERACTIVE_EFFECT);
        if (effect == null) {
            unavailable("氛围灯互动效果功能号按名解析不到");
            pushStateIfChanged();
            return false;
        }
        boolean ok;
        if (value) {
            Integer mainColor = resolver.resolve(AmbientLightContract.FUNC_MAIN_COLOR);
            Integer setColor = resolver.resolve(AmbientLightContract.VALUE_MAIN_COLOR_SET_COLOR);
            if (mainColor != null && setColor != null) {
                write(functions, mainColor, AmbientLightContract.ZONE, setColor);
            }
            ensureExperienceCustom(functions);
            writeZones(functions);
            ok = write(functions, effect, AmbientLightContract.ZONE, AmbientLightContract.ON);
        } else {
            ok = write(functions, effect, AmbientLightContract.ZONE, AmbientLightContract.OFF);
            // The strip is off, so the experience mode has to be written again
            // on the next switch-on.
            experienceCustomWritten = false;
        }
        if (ok) {
            enabled = value;
            available = true;
            reason = "";
            // The colour written before is no longer meaningful.
            lastRgb = -1;
            lastColorAccepted = false;
            Log.i(TAG, "氛围灯开关已下发 enabled=" + value);
        } else {
            reason = "氛围灯开关下发失败";
            Log.w(TAG, "氛围灯开关下发失败 enabled=" + value);
        }
        pushStateIfChanged();
        return ok;
    }

    /**
     * Writes one colour.
     *
     * <p>The gates come first, so a head unit that rejects the colour does
     * not get a resolution attempt ten times a second.
     */
    private void applyRgb(int rgb) {
        colorWrites++;
        long now = System.currentTimeMillis();
        if (lastColorAccepted) {
            if (now - lastWriteAt < MIN_INTERVAL_MS) return;
            if (distance(lastRgb, rgb) < MIN_COLOR_DELTA) return;
        }
        if (lastWriteFailed && now - lastWriteAt < FAIL_BACKOFF_MS) return;
        Object functions = functions();
        if (functions == null) {
            // The vehicle service is not ready yet. Not a write failure: the
            // handle is looked up again on the next frame.
            unavailable("车机车辆服务尚未就绪");
            pushStateIfChanged();
            return;
        }
        lastWriteAt = now;
        Integer colorSet = resolver.resolve(AmbientLightContract.FUNC_COLOR_SET);
        if (colorSet == null) {
            lastWriteFailed = true;
            unavailable("氛围灯颜色功能号按名解析不到");
            pushStateIfChanged();
            return;
        }
        // The experience mode has to be custom before a custom colour is
        // written; the vendor treats the two switches independently.
        ensureExperienceCustom(functions);
        if (write(functions, colorSet, AmbientLightContract.ZONE, rgb)) {
            lastRgb = rgb;
            lastColorAccepted = true;
            lastWriteFailed = false;
            available = true;
            reason = "";
            Log.i(TAG, "氛围灯颜色已下发 rgb=" + rgb);
        } else {
            lastWriteFailed = true;
            reason = "氛围灯颜色下发失败";
            Log.w(TAG, "氛围灯颜色下发失败 rgb=" + rgb);
        }
        pushStateIfChanged();
    }

    /**
     * Writes the absolute brightness.
     *
     * @return true when the head unit accepted it
     */
    private boolean applyBrightness(int brightness) {
        brightnessWrites++;
        Object functions = functions();
        if (functions == null) {
            unavailable("车机车辆服务尚未就绪");
            pushStateIfChanged();
            return false;
        }
        Integer driving = resolver.resolve(AmbientLightContract.FUNC_BRIGHTNESS_DRIVING);
        if (driving == null) {
            unavailable("氛围灯亮度功能号按名解析不到");
            pushStateIfChanged();
            return false;
        }
        int value;
        if (brightness <= 0) {
            value = AmbientLightContract.OFF;
        } else if (brightness <= 50) {
            value = resolver.resolve(AmbientLightContract.VALUE_BRIGHTNESS_LOW,
                    AmbientLightContract.FALLBACK_BRIGHTNESS_LOW);
        } else {
            value = resolver.resolve(AmbientLightContract.VALUE_BRIGHTNESS_HIGH,
                    AmbientLightContract.FALLBACK_BRIGHTNESS_HIGH);
        }
        // Compare the folded step, not the percentage: otherwise every
        // spectrum frame rewrites the same brightness.
        if (lastBrightnessStep == value) return true;
        boolean ok = write(functions, driving, AmbientLightContract.ZONE, value);
        // The parked ladder is a separate function with its own constants. It
        // is best effort: a car without it still has a usable brightness.
        Integer stationary = resolver.resolve(AmbientLightContract.FUNC_BRIGHTNESS_STATIONARY);
        if (stationary != null) {
            int parked = brightness <= 0
                    ? AmbientLightContract.OFF
                    : brightness <= 50
                        ? resolver.resolve(AmbientLightContract.VALUE_STATIONARY_LOW,
                                AmbientLightContract.FALLBACK_STATIONARY_LOW)
                        : resolver.resolve(AmbientLightContract.VALUE_STATIONARY_HIGH,
                                AmbientLightContract.FALLBACK_STATIONARY_HIGH);
            write(functions, stationary, AmbientLightContract.ZONE, parked);
        }
        if (ok) {
            lastBrightnessStep = value;
            lastBrightness = brightness;
            available = true;
            reason = "";
        } else {
            reason = "氛围灯亮度下发失败";
        }
        pushStateIfChanged();
        return ok;
    }

    /**
     * Lights the main, top and bottom zones.
     *
     * <p>They are three independent function ids and writing one does not
     * light the others. A zone whose id does not resolve is skipped; its
     * number is never taken from another zone.
     */
    private void writeZones(Object functions) {
        for (String name : AmbientLightContract.ZONE_FUNCTIONS) {
            Integer function = resolver.resolve(name);
            if (function == null) continue;
            write(functions, function, AmbientLightContract.ZONE, AmbientLightContract.ON);
        }
    }

    /**
     * Sets the experience mode to custom, once per switch-on cycle.
     *
     * <p>The vendor maps this to a "not pushed" experience value. Whether a
     * custom colour needs this switch set first is not documented, so it is
     * written because it costs one call and cannot make the colour wrong.
     */
    private void ensureExperienceCustom(Object functions) {
        if (experienceCustomWritten) return;
        Integer function = resolver.resolve(AmbientLightContract.FUNC_EXPERIENCE);
        if (function == null) return;
        Integer custom = resolver.resolve(AmbientLightContract.VALUE_EXPERIENCE_CUSTOM);
        if (custom == null) return;
        if (write(functions, function, AmbientLightContract.ZONE, custom)) {
            experienceCustomWritten = true;
        }
    }

    /**
     * Writes one vendor function value.
     *
     * <p>The three argument form is preferred because the zone is explicit.
     * When only the two argument form exists the zone is dropped, which is
     * correct for the ambience light: it does not use zones.
     */
    private boolean write(Object functions, int function, int zone, int value) {
        lastOp = "write";
        lastFunction = function;
        lastZone = zone;
        lastValue = value;
        try {
            Method method = functions.getClass().getMethod(
                    "setFunctionValue", int.class, int.class, int.class);
            Object result = method.invoke(functions, function, zone, value);
            lastWriteOk = Boolean.TRUE.equals(result);
            lastError = lastWriteOk ? "" : "车机拒绝了这次写入";
            return lastWriteOk;
        } catch (NoSuchMethodException missingZoneForm) {
            try {
                Method method = functions.getClass().getMethod(
                        "setFunctionValue", int.class, int.class);
                Object result = method.invoke(functions, function, value);
                lastWriteOk = Boolean.TRUE.equals(result);
                lastError = lastWriteOk ? "" : "车机拒绝了这次写入";
                return lastWriteOk;
            } catch (Throwable failure) {
                lastWriteOk = false;
                lastError = describe(failure);
                Log.w(TAG, "氛围灯写入失败 function=" + function, failure);
                return false;
            }
        } catch (Throwable failure) {
            lastWriteOk = false;
            lastError = describe(failure);
            Log.w(TAG, "氛围灯写入失败 function=" + function, failure);
            return false;
        }
    }

    private void unavailable(String why) {
        available = false;
        reason = why;
    }

    /** Euclidean distance between two packed colours. */
    private static int distance(int a, int b) {
        int dr = ((a >> 16) & 0xFF) - ((b >> 16) & 0xFF);
        int dg = ((a >> 8) & 0xFF) - ((b >> 8) & 0xFF);
        int db = (a & 0xFF) - (b & 0xFF);
        return (int) Math.sqrt(dr * dr + dg * dg + db * db);
    }

    /** The resolved vendor ids, by name, for the diagnostics dump. */
    private Map<String, Object> resolvedIds() {
        Map<String, Object> out = new LinkedHashMap<>();
        for (String name : AmbientLightContract.ALL_NAMES) {
            Integer value = resolver.resolve(name);
            if (value != null) out.put(name, value);
        }
        return out;
    }

    /** Every ambience constant that does not resolve on this head unit. */
    private List<String> unresolvedNames() {
        List<String> out = new ArrayList<>();
        for (String name : AmbientLightContract.ALL_NAMES) {
            if (resolver.resolve(name) == null) out.add(name);
        }
        return out;
    }

    /** A short, readable description of a write failure. */
    private static String describe(Throwable failure) {
        Throwable cause = failure.getCause() != null ? failure.getCause() : failure;
        String message = cause.getMessage();
        String text = cause.getClass().getSimpleName()
                + (message == null ? "" : ": " + message);
        return text.length() > 160 ? text.substring(0, 160) : text;
    }

    /**
     * Pushes the state to the listeners when the capability or the failure
     * reason changed.
     *
     * <p>Only changes are pushed: a spectrum frame arrives ten times a
     * second, and the UI only cares about "is it usable and why not".
     */
    private void pushStateIfChanged() {
        if (listeners.isEmpty()) return;
        String signature = available + "|" + reason + "|" + writtenEnabled
                + "|" + lastWriteOk + "|" + lastError;
        if (signature.equals(pushedSignature)) return;
        pushedSignature = signature;
        Map<String, Object> state = status();
        for (StateListener listener : listeners) {
            try {
                listener.onAmbientState(state);
            } catch (Throwable ignored) {
                // A listener must never break the writer.
            }
        }
    }
}
