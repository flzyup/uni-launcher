package xyz.i4o.uni.launcher.integration.display;

import android.app.Service;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.graphics.PixelFormat;
import android.hardware.display.DisplayManager;
import android.os.Build;
import android.os.Handler;
import android.os.IBinder;
import android.os.Looper;
import android.util.DisplayMetrics;
import android.view.Choreographer;
import android.view.Display;
import android.view.Gravity;
import android.view.WindowManager;

import java.lang.ref.WeakReference;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

import xyz.i4o.uni.launcher.LauncherRuntime;
import xyz.i4o.uni.launcher.integration.lyrics.LyricCast;

/**
 * Paints lyrics on a display that is not the launcher's own — the instrument cluster on units
 * that expose one, a passenger or rear screen otherwise.
 *
 * <p>How it attaches is the whole trick, and it is what the reference app does too: the window
 * is added to <em>the target display's own window manager</em>, not to the launcher's.
 * {@code createDisplayContext(display)} gives a Context whose {@code WINDOW_SERVICE} belongs
 * to that display, and {@link WindowManager.LayoutParams#TYPE_APPLICATION_OVERLAY} keeps the
 * panel clear of whatever the cluster process itself draws. Nothing is launched, focus is not
 * taken ({@code FLAG_NOT_FOCUSABLE}), touches pass through ({@code FLAG_NOT_TOUCH_MODAL}), and
 * the window is translucent so the factory cluster UI stays readable underneath.
 *
 * <p>Placement is absolute, from {@link ClusterPanelGeometry}: the panel's centre is stored as
 * two fractions of the display, which is exactly what the draggable preview in the settings page
 * writes. Moving or restyling therefore never re-attaches the window; {@link #refresh(Context)}
 * updates the layout params and redraws.
 *
 * <p>Frames come from a {@link Choreographer} loop that only runs while something is playing,
 * so a paused car with the cast switched on costs no wakeups.
 *
 * <p>The lyric state itself is fed by {@link #startFeed()}: the launcher only publishes a
 * snapshot while its Flutter engine has a listener, so a cast that relied on that would freeze
 * the moment the user opened the music app full screen. The feed asks the runtime for the media
 * block directly on a fixed cadence instead, whether or not any UI is attached.
 *
 * <p>Failure is expected and handled: a cluster display may be owned by another process
 * ({@code FLAG_PRIVATE}), may vanish when the screen sleeps, or may return with a new id.
 * Attach failures back off, and display add/remove/change re-resolves from the saved identity
 * instead of trusting the old id. The last outcome is kept in {@link #report()} so the settings
 * page can say why nothing appeared.
 */
public final class ClusterLyricsService extends Service {
    public static final String PREFS = "cluster-lyrics";
    public static final String KEY_ENABLED = "enabled";
    public static final String KEY_DISPLAY_ID = "displayId";
    public static final String KEY_DISPLAY_NAME = "displayName";
    public static final String KEY_FONT_SP = "fontSp";
    public static final String KEY_BACKGROUND = "background";
    public static final String KEY_X = "xRatio";
    public static final String KEY_Y = "yRatio";
    public static final String KEY_WIDTH = "widthRatio";
    public static final String KEY_ROWS = "rows";
    public static final String KEY_ACCENT = "accent";
    public static final String KEY_STYLE = "style";

    private static final float DEFAULT_FONT_SP = 34f;
    private static final long RETRY_MIN_MS = 1000;
    private static final long RETRY_MAX_MS = 30000;
    private static final long FRAME_MS = 40; // 25 fps is plenty for text and halves the draw cost
    private static final long FEED_MS = 700;
    /** Accent choices the settings page offers; any int works, this is only the default. */
    public static final int DEFAULT_ACCENT = 0xFF7FE3D4;

    /** Last attach/detach outcome, readable from the settings page after the fact. */
    private static volatile String lastReport = "未启用";
    /** The live instance, so a settings change can restyle without restarting the service. */
    private static WeakReference<ClusterLyricsService> live = new WeakReference<>(null);

    private DisplayManager displays;
    private final Handler handler = new Handler(Looper.getMainLooper());

    private WindowManager displayWindows;
    private ClusterLyricsView panel;
    private int attachedDisplayId = -1;
    private int attachedWidth;
    private int attachedHeight;
    private int failures;
    private boolean frameScheduled;
    /** Last state the panel actually painted, so the feed can notice a state it never drew. */
    private LyricCast.State lastDrawn = LyricCast.State.EMPTY;
    private boolean feedRunning;

    private final Choreographer.FrameCallback frameCallback = new Choreographer.FrameCallback() {
        @Override
        public void doFrame(long frameTimeNanos) {
            frameScheduled = false;
            tick();
        }
    };

    private final Runnable feed = new Runnable() {
        @Override
        public void run() {
            if (!feedRunning) return;
            pump();
            handler.postDelayed(this, FEED_MS);
        }
    };

    private final DisplayManager.DisplayListener displayListener =
            new DisplayManager.DisplayListener() {
                @Override
                public void onDisplayAdded(int displayId) {
                    reconcile("display-added");
                }

                @Override
                public void onDisplayRemoved(int displayId) {
                    if (displayId == attachedDisplayId) detach("display-removed");
                    reconcile("display-removed");
                }

                @Override
                public void onDisplayChanged(int displayId) {
                    if (displayId == attachedDisplayId) reattach("display-changed");
                }
            };

    @Override
    public void onCreate() {
        super.onCreate();
        live = new WeakReference<>(this);
        displays = (DisplayManager) getSystemService(Context.DISPLAY_SERVICE);
        if (displays != null) displays.registerDisplayListener(displayListener, handler);
        reconcile("service-created");
    }

    @Override
    public int onStartCommand(Intent intent, int flags, int startId) {
        reconcile("start-command");
        return START_STICKY;
    }

    @Override
    public IBinder onBind(Intent intent) {
        return null;
    }

    @Override
    public void onDestroy() {
        if (displays != null) displays.unregisterDisplayListener(displayListener);
        stopFeed();
        handler.removeCallbacksAndMessages(null);
        detach("service-destroyed");
        live = new WeakReference<>(null);
        super.onDestroy();
    }

    // ---- control surface (same process, called from the launcher) ----

    /**
     * Persist the whole configuration and apply it. Safe to call repeatedly; an attached window
     * is restyled in place, never torn down, so dragging the preview does not flicker.
     */
    public static void apply(Context context, Map<String, Object> values) {
        SharedPreferences prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE);
        SharedPreferences.Editor edit = prefs.edit();
        Object enabledValue = values.get("enabled");
        boolean enabled = enabledValue instanceof Boolean
                ? (Boolean) enabledValue
                : prefs.getBoolean(KEY_ENABLED, false);
        edit.putBoolean(KEY_ENABLED, enabled);
        if (values.containsKey("displayId")) {
            edit.putInt(KEY_DISPLAY_ID, asInt(values.get("displayId"), prefs.getInt(KEY_DISPLAY_ID, -1)));
        }
        if (values.containsKey("displayName")) {
            Object name = values.get("displayName");
            edit.putString(KEY_DISPLAY_NAME, name == null ? "" : String.valueOf(name));
        }
        if (values.containsKey("fontSp")) {
            float fontSp = (float) asDouble(values.get("fontSp"), DEFAULT_FONT_SP);
            edit.putFloat(KEY_FONT_SP, fontSp > 0 ? fontSp : DEFAULT_FONT_SP);
        }
        if (values.containsKey("solidBackground")) {
            edit.putBoolean(KEY_BACKGROUND, asBool(values.get("solidBackground"), true));
        }
        if (values.containsKey("xRatio")) {
            edit.putFloat(KEY_X, ClusterPanelGeometry.clampRatio(
                    (float) asDouble(values.get("xRatio"), ClusterPanelGeometry.DEFAULT_X_RATIO),
                    ClusterPanelGeometry.DEFAULT_X_RATIO));
        }
        if (values.containsKey("yRatio")) {
            edit.putFloat(KEY_Y, ClusterPanelGeometry.clampRatio(
                    (float) asDouble(values.get("yRatio"), ClusterPanelGeometry.DEFAULT_Y_RATIO),
                    ClusterPanelGeometry.DEFAULT_Y_RATIO));
        }
        if (values.containsKey("widthRatio")) {
            edit.putFloat(KEY_WIDTH, ClusterPanelGeometry.widthRatio(
                    (float) asDouble(values.get("widthRatio"),
                            ClusterPanelGeometry.DEFAULT_WIDTH_RATIO)));
        }
        if (values.containsKey("rows")) {
            edit.putInt(KEY_ROWS, ClusterPanelGeometry.rows(
                    asInt(values.get("rows"), ClusterPanelGeometry.DEFAULT_ROWS)));
        }
        if (values.containsKey("accent")) {
            edit.putInt(KEY_ACCENT, asInt(values.get("accent"), DEFAULT_ACCENT));
        }
        if (values.containsKey("style")) {
            edit.putString(KEY_STYLE, styleName(values.get("style")));
        }
        edit.apply();

        Intent intent = new Intent(context, ClusterLyricsService.class);
        if (!enabled) {
            context.stopService(intent);
            lastReport = "已关闭";
            return;
        }
        try {
            context.startService(intent);
        } catch (IllegalStateException background) {
            lastReport = "后台启动被系统拒绝，回到桌面再试";
            return;
        }
        refresh(context);
    }

    /** Convenience shape kept for callers that only flip the switch. */
    public static void apply(Context context, boolean enabled, int displayId, String displayName,
                             float fontSp, boolean solidBackground) {
        Map<String, Object> values = new LinkedHashMap<>();
        values.put("enabled", enabled);
        values.put("displayId", displayId);
        values.put("displayName", displayName == null ? "" : displayName);
        values.put("fontSp", fontSp);
        values.put("solidBackground", solidBackground);
        apply(context, values);
    }

    /** Re-read the persisted configuration into an attached window. */
    public static void refresh(Context context) {
        ClusterLyricsService service = live.get();
        if (service != null) {
            final ClusterLyricsService target = service;
            service.handler.post(new Runnable() {
                @Override
                public void run() {
                    target.reconcile("refresh");
                }
            });
            return;
        }
        context.startService(new Intent(context, ClusterLyricsService.class));
    }

    public static boolean enabled(Context context) {
        return context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
                .getBoolean(KEY_ENABLED, false);
    }

    public static String report() {
        return lastReport;
    }

    /**
     * Plain maps, not JSON: this goes straight back over the method channel, and Dart cannot
     * receive {@code org.json} types.
     */
    public static Map<String, Object> status(Context context) {
        SharedPreferences prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE);
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("enabled", prefs.getBoolean(KEY_ENABLED, false));
        out.put("displayId", prefs.getInt(KEY_DISPLAY_ID, -1));
        out.put("displayName", prefs.getString(KEY_DISPLAY_NAME, ""));
        out.put("fontSp", prefs.getFloat(KEY_FONT_SP, DEFAULT_FONT_SP));
        out.put("solidBackground", prefs.getBoolean(KEY_BACKGROUND, true));
        out.put("xRatio", prefs.getFloat(KEY_X, ClusterPanelGeometry.DEFAULT_X_RATIO));
        out.put("yRatio", prefs.getFloat(KEY_Y, ClusterPanelGeometry.DEFAULT_Y_RATIO));
        out.put("widthRatio", prefs.getFloat(KEY_WIDTH, ClusterPanelGeometry.DEFAULT_WIDTH_RATIO));
        out.put("rows", prefs.getInt(KEY_ROWS, ClusterPanelGeometry.DEFAULT_ROWS));
        out.put("accent", prefs.getInt(KEY_ACCENT, DEFAULT_ACCENT));
        out.put("style", prefs.getString(KEY_STYLE, "pill"));
        out.put("report", reportForDisplay(prefs.getInt(KEY_DISPLAY_ID, -1)));
        LyricCast.State cast = LyricCast.state();
        out.put("track", cast.title);
        out.put("artist", cast.artist);
        out.put("lyricLines", cast.timeline.lineCount());
        out.put("lyricLabel", cast.sourceLabel);
        out.put("playing", cast.playing);
        return out;
    }

    /**
     * The report with the lyric part refreshed.
     *
     * <p>{@link #lastReport} is written once, when the window is added — at that moment the
     * timeline is often still being fetched, so the text froze at "尚未拿到曲目" while the panel
     * went on to show real lyrics. The window half of the sentence is historical, the lyric half
     * is current, so it is recomputed here instead of being baked in at attach time.
     */
    private static String reportForDisplay(int displayId) {
        String report = lastReport;
        if (!report.startsWith("已投射") || displayId < 0) return report;
        int marker = report.lastIndexOf(" · ");
        String head = marker > 0 ? report.substring(0, marker) : report;
        return head + " · " + describeLyrics();
    }

    /**
     * Every attached display, so the settings page can show what the unit actually exposes.
     * This is the first thing to look at in a car: if the cluster is not in this list, it is
     * driven by another system and no third-party window can reach it.
     */
    public static List<Object> displays(Context context) {
        List<Object> out = new ArrayList<>();
        DisplayManager manager = (DisplayManager) context.getSystemService(Context.DISPLAY_SERVICE);
        if (manager == null) return out;
        int[] presentationIds =
                ids(manager.getDisplays(DisplayManager.DISPLAY_CATEGORY_PRESENTATION));
        for (Display display : manager.getDisplays()) {
            if (display == null || !display.isValid()) continue;
            try {
                DisplayMetrics metrics = new DisplayMetrics();
                display.getRealMetrics(metrics);
                Map<String, Object> row = new LinkedHashMap<>();
                row.put("id", display.getDisplayId());
                row.put("name", display.getName());
                row.put("presentation", contains(presentationIds, display.getDisplayId()));
                row.put("width", metrics.widthPixels);
                row.put("height", metrics.heightPixels);
                row.put("densityDpi", metrics.densityDpi);
                row.put("label", DisplayPicker.label(display.getName(), display.getDisplayId(),
                        metrics.widthPixels, metrics.heightPixels, metrics.densityDpi));
                out.add(row);
            } catch (Exception skipped) {
                // A display that disappears mid-enumeration simply does not get a row.
            }
        }
        return out;
    }

    // ---- lyric feed ----

    /**
     * Sample the media block on a fixed cadence, with or without a Flutter listener.
     *
     * <p>This is the piece that makes the cast show real lyrics: {@code MainActivity.publish()}
     * skips snapshot construction when no sink is attached, so before this feed existed the cast
     * kept whatever it saw while the launcher was on screen — which, in a car, is almost never.
     */
    private void startFeed() {
        if (feedRunning) return;
        feedRunning = true;
        handler.post(feed);
    }

    private void stopFeed() {
        if (!feedRunning) return;
        feedRunning = false;
        handler.removeCallbacks(feed);
        try {
            LauncherRuntime.get(this).releaseMediaCast();
        } catch (RuntimeException | LinkageError ignored) {
            // Runtime already gone; nothing to release.
        }
    }

    /** Throttle for the attachment probe, so a panel that cannot attach is not re-added per frame. */
    private long lastHealthRetry;
    private int healthRetries;
    private int pumpTicks;

    private void pump() {
        try {
            LauncherRuntime.get(this).pumpMediaCast();
        } catch (RuntimeException | LinkageError ignored) {
            // The runtime is being torn down; the next tick retries.
        }
        // Watchdog. A track change publishes a state with the new title but no timeline yet
        // (the catalog lookup is asynchronous), and the frame loop stops as soon as there is
        // nothing to animate. Without this line the panel froze on "正在获取歌词" /
        // "当前音源未提供歌词" until the user toggled the switch: the timeline had arrived, the
        // reporter counted 64 lines, and the window never redrew.
        if (panel != null && LyricCast.state() != lastDrawn) startFrames();
        // Slow heartbeat. The frame loop stops when there is nothing to animate, which also
        // means a state change that does *not* carry a timeline (track switch while the lookup
        // is in flight) can leave the previous song's lines on the glass for as long as the
        // lookup takes. One repaint a second keeps the panel honest and costs nothing.
        if (panel != null && ++pumpTicks % 2 == 0) startFrames();
        // Health probe. A car head unit that reconnects, a display that hot-plugs, and an
        // overlay that the system silently removed all leave this object holding a view that
        // still draws into a dead WindowManager. The window is then alive in our hands and
        // invisible on the panel, with no error anywhere. One attachment check per tick costs
        // nothing and turns that silent failure into a re-attach.
        if (panel != null && !healthy(panel) && System.currentTimeMillis() - lastHealthRetry > 5000) {
            lastHealthRetry = System.currentTimeMillis();
            healthRetries++;
            reattach("health:" + describe(panel));
        }
    }

    private static boolean healthy(ClusterLyricsView view) {
        try {
            return view.isAttachedToWindow() && view.getParent() != null;
        } catch (RuntimeException gone) {
            return false;
        }
    }

    private static String describe(ClusterLyricsView view) {
        try {
            return view.isAttachedToWindow() ? "detached-from-parent" : "detached-from-window";
        } catch (RuntimeException gone) {
            return "unreadable";
        }
    }

    // ---- attach / detach ----

    private void reconcile(String reason) {
        if (!enabled(this)) {
            stopFeed();
            detach(reason + ":disabled");
            return;
        }
        // Same gate the dock uses: on Android 6+ the manifest entry alone does not let a
        // window be added, the user must have granted "display over other apps".
        if (!android.provider.Settings.canDrawOverlays(this)) {
            detach(reason + ":no-overlay-permission");
            lastReport = "缺少「显示在其他应用上层」权限";
            return;
        }
        if (displays == null) displays = (DisplayManager) getSystemService(Context.DISPLAY_SERVICE);
        if (displays == null) return;

        Display[] all = displays.getDisplays();
        int[] ids = ids(all);
        int[] presentationIds =
                ids(displays.getDisplays(DisplayManager.DISPLAY_CATEGORY_PRESENTATION));
        String[] names = new String[all.length];
        boolean[] presentation = new boolean[all.length];
        for (int i = 0; i < all.length; i++) {
            names[i] = all[i] == null ? "" : all[i].getName();
            presentation[i] = all[i] != null && contains(presentationIds, all[i].getDisplayId());
        }
        SharedPreferences prefs = getSharedPreferences(PREFS, Context.MODE_PRIVATE);
        int picked = DisplayPicker.pick(ids, names, presentation,
                prefs.getString(KEY_DISPLAY_NAME, ""), prefs.getInt(KEY_DISPLAY_ID, -1));
        if (picked < 0) {
            detach(reason + ":no-target");
            return;
        }
        Display target = all[picked];
        if (target.getDisplayId() == attachedDisplayId && panel != null) {
            restyle();
            return;
        }
        attach(target, reason);
    }

    /** Re-apply size, position and style to the window that is already attached. */
    private void restyle() {
        ClusterLyricsView view = panel;
        WindowManager windows = displayWindows;
        if (view == null || windows == null) return;
        Display display = displays == null ? null : displays.getDisplay(attachedDisplayId);
        if (display == null || !display.isValid()) return;
        try {
            SharedPreferences prefs = getSharedPreferences(PREFS, Context.MODE_PRIVATE);
            DisplayMetrics metrics = new DisplayMetrics();
            display.getRealMetrics(metrics);
            float density = metrics.density <= 0 ? 1f : metrics.density;
            float fontPx = prefs.getFloat(KEY_FONT_SP, DEFAULT_FONT_SP) * density;
            int rows = ClusterPanelGeometry.rows(
                    prefs.getInt(KEY_ROWS, ClusterPanelGeometry.DEFAULT_ROWS));
            boolean solid = prefs.getBoolean(KEY_BACKGROUND, true);
            int accent = prefs.getInt(KEY_ACCENT, DEFAULT_ACCENT);
            int style = styleOf(prefs.getString(KEY_STYLE, "pill"));

            view.configure(fontPx, rows, accent, mutedOf(accent),
                    solid ? backgroundFor(style) : 0x00000000, style);

            WindowManager.LayoutParams params = (WindowManager.LayoutParams) view.getLayoutParams();
            if (params == null) {
                attach(display, "restyle");
                return;
            }
            int width = ClusterPanelGeometry.width(metrics.widthPixels,
                    prefs.getFloat(KEY_WIDTH, ClusterPanelGeometry.DEFAULT_WIDTH_RATIO));
            int height = ClusterPanelGeometry.height(fontPx, rows);
            int[] origin = ClusterPanelGeometry.origin(metrics.widthPixels, metrics.heightPixels,
                    width, height,
                    prefs.getFloat(KEY_X, ClusterPanelGeometry.DEFAULT_X_RATIO),
                    prefs.getFloat(KEY_Y, ClusterPanelGeometry.DEFAULT_Y_RATIO));
            params.width = width;
            params.height = height;
            params.x = origin[0];
            params.y = origin[1];
            attachedWidth = width;
            attachedHeight = height;
            windows.updateViewLayout(view, params);
            view.invalidate();
        } catch (Exception gone) {
            // The display or the window went away between the check and the update.
            detach("restyle-failed");
            scheduleRetry("restyle-failed");
        }
    }

    private void reattach(String reason) {
        if (displayWindows == null) {
            reconcile(reason);
            return;
        }
        Display display = displays == null ? null : displays.getDisplay(attachedDisplayId);
        if (display == null || !display.isValid()) {
            detach(reason + ":gone");
            reconcile(reason);
            return;
        }
        attach(display, reason);
    }

    private void attach(Display target, String reason) {
        detach(reason + ":reattach");
        try {
            Context displayContext = createDisplayContext(target);
            WindowManager windows =
                    (WindowManager) displayContext.getSystemService(Context.WINDOW_SERVICE);
            if (windows == null) {
                scheduleRetry(reason + ":no-window-manager");
                return;
            }
            DisplayMetrics metrics = new DisplayMetrics();
            target.getRealMetrics(metrics);
            float density = metrics.density <= 0 ? 1f : metrics.density;
            SharedPreferences prefs = getSharedPreferences(PREFS, Context.MODE_PRIVATE);
            float fontPx = prefs.getFloat(KEY_FONT_SP, DEFAULT_FONT_SP) * density;
            int rows = ClusterPanelGeometry.rows(
                    prefs.getInt(KEY_ROWS, ClusterPanelGeometry.DEFAULT_ROWS));
            boolean solid = prefs.getBoolean(KEY_BACKGROUND, true);
            int accent = prefs.getInt(KEY_ACCENT, DEFAULT_ACCENT);
            int style = styleOf(prefs.getString(KEY_STYLE, "pill"));

            ClusterLyricsView view = new ClusterLyricsView(displayContext);
            view.configure(fontPx, rows, accent, mutedOf(accent),
                    solid ? backgroundFor(style) : 0x00000000, style);

            int width = ClusterPanelGeometry.width(metrics.widthPixels,
                    prefs.getFloat(KEY_WIDTH, ClusterPanelGeometry.DEFAULT_WIDTH_RATIO));
            int height = ClusterPanelGeometry.height(fontPx, rows);
            int[] origin = ClusterPanelGeometry.origin(metrics.widthPixels, metrics.heightPixels,
                    width, height,
                    prefs.getFloat(KEY_X, ClusterPanelGeometry.DEFAULT_X_RATIO),
                    prefs.getFloat(KEY_Y, ClusterPanelGeometry.DEFAULT_Y_RATIO));

            WindowManager.LayoutParams params = new WindowManager.LayoutParams(
                    width,
                    height,
                    Build.VERSION.SDK_INT >= Build.VERSION_CODES.O
                            ? WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
                            : WindowManager.LayoutParams.TYPE_PHONE,
                    WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE
                            | WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE
                            | WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL
                            | WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN
                            | WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS
                            | WindowManager.LayoutParams.FLAG_HARDWARE_ACCELERATED,
                    PixelFormat.TRANSLUCENT);
            // Absolute placement: the stored ratios are the panel centre, and the geometry
            // helper has already clamped the result inside the display.
            params.gravity = Gravity.TOP | Gravity.START;
            params.x = origin[0];
            params.y = origin[1];
            params.setTitle("UNI 歌词投屏");
            windows.addView(view, params);

            panel = view;
            displayWindows = windows;
            attachedDisplayId = target.getDisplayId();
            attachedWidth = width;
            attachedHeight = height;
            failures = 0;
            lastReport = "已投射 · " + target.getName() + " · ID " + target.getDisplayId()
                    + " · " + describeLyrics();
            startFrames();
            startFeed();
        } catch (Exception | LinkageError failed) {
            // A private display, a revoked overlay permission, or a window manager that is
            // already gone. Keep state clean and back off instead of retrying in a tight loop.
            panel = null;
            displayWindows = null;
            attachedDisplayId = -1;
            scheduleRetry(reason + ":" + failed.getClass().getSimpleName());
        }
    }

    private static String describeLyrics() {
        LyricCast.State cast = LyricCast.state();
        int lines = cast.timeline.lineCount();
        if (lines > 0) {
            return (cast.sourceLabel.isEmpty() ? "歌词" : cast.sourceLabel) + " " + lines + " 行";
        }
        return cast.title.isEmpty() ? "尚未拿到曲目" : "正在匹配歌词";
    }

    private void detach(String reason) {
        stopFrames();
        if (displayWindows != null && panel != null) {
            try {
                displayWindows.removeViewImmediate(panel);
            } catch (Exception gone) {
                // The display went away first; nothing left to remove.
            }
        }
        panel = null;
        displayWindows = null;
        attachedDisplayId = -1;
        if (lastReport.startsWith("已投射")) lastReport = "已断开 · " + reason;
    }

    private void scheduleRetry(String reason) {
        failures++;
        if (failures <= 1 || reason.startsWith("retry")) {
            lastReport = "投射失败 · " + reason;
        }
        long delay = Math.min(RETRY_MAX_MS, RETRY_MIN_MS << Math.min(5, Math.max(0, failures - 1)));
        handler.postDelayed(() -> reconcile("retry"), delay);
    }

    // ---- frames ----

    private void startFrames() {
        if (frameScheduled) return;
        frameScheduled = true;
        Choreographer.getInstance().postFrameCallback(frameCallback);
    }

    private void stopFrames() {
        if (!frameScheduled) return;
        Choreographer.getInstance().removeFrameCallback(frameCallback);
        frameScheduled = false;
    }

    private void tick() {
        ClusterLyricsView view = panel;
        if (view == null) return;
        LyricCast.State state = LyricCast.state();
        lastDrawn = state;
        view.setState(state, System.currentTimeMillis());
        view.invalidate();
        // 25 fps only while there is something to animate: a paused track, or one whose
        // timeline has not landed yet, leaves the last frame on screen and costs nothing. The
        // feed watchdog re-arms this loop the moment a new state shows up, so stopping here
        // cannot strand the panel.
        if (state.playing && state.hasTimeline()) startFrames();
    }

    // ---- small helpers ----

    private static int styleOf(String name) {
        if ("plain".equals(name)) return ClusterLyricsView.STYLE_PLAIN;
        if ("glow".equals(name)) return ClusterLyricsView.STYLE_GLOW;
        return ClusterLyricsView.STYLE_PILL;
    }

    private static String styleName(Object value) {
        String name = value == null ? "" : String.valueOf(value);
        if ("plain".equals(name) || "glow".equals(name) || "pill".equals(name)) return name;
        return "pill";
    }

    /** Background alpha per style: bare text has none, the pill is a soft black, glow lighter. */
    private static int backgroundFor(int style) {
        if (style == ClusterLyricsView.STYLE_GLOW) return 0x66000000;
        return 0xB3000000;
    }

    /** Secondary rows keep a hint of the accent instead of a flat grey. */
    private static int mutedOf(int accent) {
        int r = (accent >> 16) & 0xFF, g = (accent >> 8) & 0xFF, b = accent & 0xFF;
        int grey = Math.round(r * 0.45f + g * 0.45f + b * 0.1f);
        int mixR = (grey + r) / 2, mixG = (grey + g) / 2, mixB = (grey + b) / 2;
        return 0xC0000000 | (mixR << 16) | (mixG << 8) | mixB;
    }

    private static int asInt(Object value, int fallback) {
        if (value instanceof Number) return ((Number) value).intValue();
        if (value instanceof String) {
            try {
                return Integer.parseInt(((String) value).trim());
            } catch (NumberFormatException ignored) {
                return fallback;
            }
        }
        return fallback;
    }

    private static double asDouble(Object value, double fallback) {
        if (value instanceof Number) return ((Number) value).doubleValue();
        if (value instanceof String) {
            try {
                return Double.parseDouble(((String) value).trim());
            } catch (NumberFormatException ignored) {
                return fallback;
            }
        }
        return fallback;
    }

    private static boolean asBool(Object value, boolean fallback) {
        if (value instanceof Boolean) return (Boolean) value;
        if (value instanceof Number) return ((Number) value).intValue() != 0;
        if (value instanceof String) return Boolean.parseBoolean((String) value);
        return fallback;
    }

    private static int[] ids(Display[] all) {
        int[] out = new int[all.length];
        for (int i = 0; i < all.length; i++) {
            out[i] = all[i] == null || !all[i].isValid() ? -1 : all[i].getDisplayId();
        }
        return out;
    }

    private static boolean contains(int[] values, int want) {
        for (int value : values) if (value == want) return true;
        return false;
    }
}
