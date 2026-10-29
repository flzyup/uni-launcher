package xyz.i4o.uni.launcher.ambient;

import android.util.Log;

import java.lang.reflect.Method;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.Map;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.ThreadFactory;
import java.util.concurrent.TimeUnit;
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
 */
public final class AmbientLightWriter {
    private static final String TAG = "UniAmbient";

    /** Minimum time between two colour writes, in milliseconds. */
    public static final long MIN_INTERVAL_MS = 120L;

    /** Minimum colour distance that still counts as a change. */
    public static final int MIN_COLOR_DELTA = 8;

    private final AmbientLightResolver resolver = new AmbientLightResolver();
    private final Supplier<Object> handle;

    private final ExecutorService worker = Executors.newSingleThreadExecutor(
            new ThreadFactory() {
                @Override public Thread newThread(Runnable runnable) {
                    Thread thread = new Thread(runnable, "uni-ambient-light");
                    thread.setPriority(Thread.MIN_PRIORITY);
                    return thread;
                }
            });

    private volatile boolean enabled;
    private volatile boolean available;
    private volatile String reason = "";
    private volatile int lastRgb = -1;
    private volatile int lastBrightness = -1;
    private volatile long lastWriteAt;
    private volatile boolean experienceCustomWritten;

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
        worker.execute(new Runnable() {
            @Override public void run() {
                applyEnabled(value);
            }
        });
    }

    /**
     * Writes one colour.
     *
     * <p>The colour is packed as 0xRRGGBB, which is how the vendor splits it
     * back into red, green and blue.
     */
    public void applyColor(final int r, final int g, final int b) {
        final int rgb = ((r & 0xFF) << 16) | ((g & 0xFF) << 8) | (b & 0xFF);
        worker.execute(new Runnable() {
            @Override public void run() {
                applyRgb(rgb);
            }
        });
    }

    /**
     * Sets the brightness, 0 to 100.
     *
     * <p>The vendor only offers three steps, so the percentage is folded into
     * low or high. Zero means off on this SDK, which is also what a user
     * dragging the brightness to zero expects, so it is not mapped to low.
     *
     * <p>Both ladders are written: the driving one and the parked one. The
     * head unit picks the ladder that applies to the current state, so
     * writing the same value to both keeps the brightness the same whether
     * the car is moving or not.
     */
    public void setBrightness(final int brightness) {
        worker.execute(new Runnable() {
            @Override public void run() {
                applyBrightness(brightness);
            }
        });
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
            result.put("unresolved", new ArrayList<>(resolver.misses()));
        } catch (Exception ignored) {
            result.put("available", false);
            result.put("reason", "状态读取失败");
        }
        return result;
    }

    // ----------------------------------------------------------------- internals

    private void applyEnabled(boolean value) {
        enableWrites++;
        Object functions = functions();
        if (functions == null) {
            unavailable("车机车辆服务尚未就绪");
            return;
        }
        Integer effect = resolver.resolve(AmbientLightContract.FUNC_INTERACTIVE_EFFECT);
        if (effect == null) {
            unavailable("氛围灯互动效果功能号按名解析不到");
            return;
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
            Log.i(TAG, "氛围灯开关已下发 enabled=" + value);
        } else {
            reason = "氛围灯开关下发失败";
            Log.w(TAG, "氛围灯开关下发失败 enabled=" + value);
        }
    }

    private void applyRgb(int rgb) {
        colorWrites++;
        Object functions = functions();
        if (functions == null) {
            unavailable("车机车辆服务尚未就绪");
            return;
        }
        long now = System.currentTimeMillis();
        if (lastRgb >= 0) {
            if (now - lastWriteAt < MIN_INTERVAL_MS) return;
            if (distance(lastRgb, rgb) < MIN_COLOR_DELTA) return;
        }
        Integer colorSet = resolver.resolve(AmbientLightContract.FUNC_COLOR_SET);
        if (colorSet == null) {
            unavailable("氛围灯颜色功能号按名解析不到");
            return;
        }
        // The experience mode has to be custom before a custom colour is
        // written; the vendor treats the two switches independently.
        ensureExperienceCustom(functions);
        if (write(functions, colorSet, AmbientLightContract.ZONE, rgb)) {
            lastRgb = rgb;
            lastWriteAt = now;
            available = true;
            reason = "";
            Log.i(TAG, "氛围灯颜色已下发 rgb=" + rgb);
        } else {
            reason = "氛围灯颜色下发失败";
            Log.w(TAG, "氛围灯颜色下发失败 rgb=" + rgb);
        }
    }

    private void applyBrightness(int brightness) {
        brightnessWrites++;
        Object functions = functions();
        if (functions == null) {
            unavailable("车机车辆服务尚未就绪");
            return;
        }
        Integer driving = resolver.resolve(AmbientLightContract.FUNC_BRIGHTNESS_DRIVING);
        if (driving == null) {
            unavailable("氛围灯亮度功能号按名解析不到");
            return;
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
        if (lastBrightness == value) return;
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
            lastBrightness = value;
        } else {
            reason = "氛围灯亮度下发失败";
        }
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
        try {
            Method method = functions.getClass().getMethod(
                    "setFunctionValue", int.class, int.class, int.class);
            Object result = method.invoke(functions, function, zone, value);
            return Boolean.TRUE.equals(result);
        } catch (NoSuchMethodException missingZoneForm) {
            try {
                Method method = functions.getClass().getMethod(
                        "setFunctionValue", int.class, int.class);
                Object result = method.invoke(functions, function, value);
                return Boolean.TRUE.equals(result);
            } catch (Throwable failure) {
                Log.w(TAG, "氛围灯写入失败 function=" + function, failure);
                return false;
            }
        } catch (Throwable failure) {
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
}
