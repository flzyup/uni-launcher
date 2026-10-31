package xyz.i4o.uni.launcher.platform;

import java.lang.reflect.Method;

/**
 * Lifts the hidden API restriction for this process.
 *
 * <p>Some of the car interfaces are only reachable through a hidden method.
 * The audio session id behind the spectrum fallback is one of them:
 * {@code AudioPlaybackConfiguration.getAudioSessionId()} is {@code @hide}, the
 * public SDK only offers {@code getAudioAttributes()}.
 *
 * <p>The exemption only affects **our own process**. It changes no system
 * state, and every call site is guarded, so a failure is a failure and not a
 * crash.
 */
public final class HiddenApiCompat {
    /**
     * The exemption prefix.
     *
     * <p>{@code "L"} releases every class (the {@code Lxxx/} prefix match).
     */
    private static final String EXEMPT_PREFIX = "L";

    /** The result is cached: the exemption is applied once per process. */
    private static volatile String result;

    private HiddenApiCompat() {}

    /**
     * The conclusion of the last {@link #tryExempt()}, or an empty string
     * when the exemption was never applied.
     */
    public static String status() {
        return result == null ? "" : result;
    }

    /**
     * Applies the exemption once and returns a one line conclusion.
     *
     * @return a short status, for the diagnostics
     */
    public static synchronized String tryExempt() {
        if (result != null) return result;
        try {
            Class<?> vmRuntimeClass = Class.forName("dalvik.system.VMRuntime");
            Method getRuntime = vmRuntimeClass.getDeclaredMethod("getRuntime");
            Object vmRuntime = getRuntime.invoke(null);
            Method setExemptions = findSetHiddenApiExemptions(vmRuntimeClass);
            if (setExemptions == null) throw new NoSuchMethodException("setHiddenApiExemptions [class java.lang.String[]]");
            // The signature is String[], and the invocation has to be expanded:
            // passing the array as one argument would hit the wrong overload.
            setExemptions.invoke(vmRuntime, new Object[]{new String[]{EXEMPT_PREFIX}});
            result = "已放开";
        } catch (Throwable error) {
            result = "未放开(" + error.getClass().getSimpleName() + ": " + text(error) + ")";
        }
        return result;
    }

    /**
     * Finds {@code setHiddenApiExemptions}.
     *
     * <p>The parameter type has to be {@code String[]}: Android 10 added a
     * single argument overload, so the method must not be picked by name
     * alone.
     */
    private static Method findSetHiddenApiExemptions(Class<?> cls) {
        try {
            return cls.getDeclaredMethod("setHiddenApiExemptions", String[].class);
        } catch (Throwable ignored) {
            // Fall back to a scan, in case a ROM moved the method or changed
            // its visibility.
        }
        for (Method method : cls.getDeclaredMethods()) {
            if ("setHiddenApiExemptions".equals(method.getName())
                    && method.getParameterTypes().length == 1
                    && method.getParameterTypes()[0] == String[].class) {
                return method;
            }
        }
        return null;
    }

    private static String text(Throwable error) {
        String message = error.getMessage();
        if (message == null || message.isEmpty()) return "-";
        return message.length() > 80 ? message.substring(0, 80) : message;
    }
}
