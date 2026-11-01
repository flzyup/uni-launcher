package xyz.i4o.uni.launcher.ambient;

import android.content.Context;
import android.os.Handler;
import android.os.Looper;

import java.util.List;
import java.util.Map;

import io.flutter.embedding.engine.FlutterEngine;
import io.flutter.plugin.common.MethodChannel;

import xyz.i4o.uni.launcher.integration.OfficialCarReader;

/**
 * Flutter bridge for the ambient light.
 *
 * <p>The channel is thin on purpose: the spectrum to colour mapping runs in
 * Dart where it can be unit tested, and this side only executes the writes
 * against the vendor SDK. Every write is explicit, so nothing reaches the
 * head unit unless the user enabled the music ambience.
 *
 * <p>Methods:
 * <ul>
 *   <li>{@code status} - capability and last write state;</li>
 *   <li>{@code enable} - switches the strip on or off;</li>
 *   <li>{@code color} - writes one packed colour;</li>
 *   <li>{@code brightness} - sets the brightness, 0 to 100;</li>
 *   <li>{@code zone} - switches one zone (main / top / bottom) on or off.</li>
 * </ul>
 *
 * <p>The native side also pushes a {@code state} call when the capability or
 * the failure reason changes. Without it the settings page would keep showing
 * whatever the channel said when the app started, which hides the real
 * reason when a write fails.
 */
public final class AmbientLightBridge {
    /**
     * One writer per process. The launcher, the global dock and the global
     * panel are separate engines, and each of them would otherwise hold its
     * own writer and write the strip twice.
     */
    private static AmbientLightWriter sharedWriter;

    private final AmbientLightWriter writer;
    private final MethodChannel channel;
    private final Handler main = new Handler(Looper.getMainLooper());
    private final AmbientLightWriter.StateListener listener;

    private AmbientLightBridge(Context context, FlutterEngine engine) {
        synchronized (AmbientLightBridge.class) {
            if (sharedWriter == null) {
                sharedWriter = new AmbientLightWriter(new java.util.function.Supplier<Object>() {
                    @Override public Object get() {
                        return OfficialCarReader.borrowedFunctions();
                    }
                });
            }
            writer = sharedWriter;
        }
        channel = new MethodChannel(engine.getDartExecutor().getBinaryMessenger(),
                "xyz.i4o.uni.launcher/ambient-light");
        listener = new AmbientLightWriter.StateListener() {
            @Override public void onAmbientState(final Map<String, Object> state) {
                // The channel call has to leave the platform thread.
                main.post(new Runnable() {
                    @Override public void run() {
                        try {
                            channel.invokeMethod("state", state);
                        } catch (Throwable ignored) {
                            // The engine may be gone already.
                        }
                    }
                });
            }
        };
        writer.addStateListener(listener);
        channel.setMethodCallHandler((call, result) -> {
            try {
                switch (call.method) {
                    case "status":
                        result.success(writer.status());
                        break;
                    case "enable":
                        writer.setEnabled(Boolean.TRUE.equals(call.arguments));
                        result.success(null);
                        break;
                    case "color":
                        applyColor(call.arguments);
                        result.success(null);
                        break;
                    case "brightness":
                        writer.setBrightness(call.arguments instanceof Number
                                ? ((Number) call.arguments).intValue() : 0);
                        result.success(null);
                        break;
                    case "zone":
                        result.success(applyZone(call.arguments));
                        break;
                    default:
                        result.notImplemented();
                        break;
                }
            } catch (Exception failure) {
                result.error("unavailable", "氛围灯通道暂不可用", null);
            }
        });
    }

    /** Creates the bridge and attaches it to the engine. */
    public static AmbientLightBridge attach(Context context, FlutterEngine engine) {
        return new AmbientLightBridge(context.getApplicationContext(), engine);
    }

    private void applyColor(Object arguments) {
        int r = 0, g = 0, b = 0;
        if (arguments instanceof Map) {
            Map<?, ?> color = (Map<?, ?>) arguments;
            r = number(color.get("r"));
            g = number(color.get("g"));
            b = number(color.get("b"));
        } else if (arguments instanceof List) {
            List<?> values = (List<?>) arguments;
            if (values.size() >= 3) {
                r = number(values.get(0));
                g = number(values.get(1));
                b = number(values.get(2));
            }
        }
        writer.applyColor(r, g, b);
    }

    private static int number(Object value) {
        return value instanceof Number ? ((Number) value).intValue() : 0;
    }

    /**
     * Switches one zone on or off.
     *
     * <p>The arguments are a map with {@code zone} (0 main, 1 top, 2 bottom)
     * and {@code enabled}. Only the zone switches exist on this head unit, so
     * the zone choreography can only be a hard edge; see
     * {@link AmbientLightWriter#setZoneEnabled(int, boolean)}.
     */
    private boolean applyZone(Object arguments) {
        if (!(arguments instanceof Map)) return false;
        Map<?, ?> zone = (Map<?, ?>) arguments;
        final int index = number(zone.get("zone"));
        final boolean enabled = Boolean.TRUE.equals(zone.get("enabled"));
        return writer.setZoneEnabled(index, enabled);
    }

    /** Capability and last write state, for the read-only diagnostics dump. */
    public Map<String, Object> status() {
        return writer.status();
    }

    /** Detaches the channel. The shared writer lives as long as the process. */
    public void close() {
        writer.removeStateListener(listener);
        channel.setMethodCallHandler(null);
    }
}
