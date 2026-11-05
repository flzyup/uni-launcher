package xyz.i4o.uni.launcher.integration.display;

/**
 * Choose which attached display a cast window belongs on.
 *
 * <p>Display ids are not stable across reboots or reconnects on car head units, so the saved
 * identity is a pair: the physical name ({"仪表", "cluster", "HDMI Screen 1"}) plus the last
 * known id. Resolution order is deliberately conservative — a wrong guess paints lyrics over
 * the passenger screen or the rear camera, so a name that matches more than one display is
 * only resolved when the id still agrees.
 *
 * <p>Android-free on purpose: the arrays in, index out shape is what makes this testable
 * without a device, and it is the only part of the cast path that has opinions.
 */
public final class DisplayPicker {
    /** Nothing to paint on. */
    public static final int NONE = -1;

    private DisplayPicker() {
    }

    /**
     * @param ids          display ids, {@link android.view.Display#getDisplayId()}
     * @param names        display names, {@link android.view.Display#getName()}
     * @param presentation whether the display was listed under
     *                     {@link android.hardware.display.DisplayManager#DISPLAY_CATEGORY_PRESENTATION}
     * @param wantName     last known name, "" when the user never picked one
     * @param wantId       last known id, -1 when unknown
     * @return index into the arrays, or {@link #NONE}
     */
    public static int pick(int[] ids, String[] names, boolean[] presentation, String wantName,
                           int wantId) {
        if (ids == null || names == null) return NONE;
        int length = Math.min(ids.length, names.length);
        if (length == 0) return NONE;

        // 1. The exact display we used last time, when it still exists.
        if (wantId > 0) {
            for (int i = 0; i < length; i++) {
                if (ids[i] == wantId) return i;
            }
        }

        // 2. The same physical panel under a new id. Only when the name is unambiguous:
        //    two displays sharing a name and neither matching the saved id is exactly the
        //    case where a guess would paint over the wrong screen.
        //
        //    主屏永远不是投射目标。单屏设备（模拟器、平板、没接仪表的车机）里唯一那块屏
        //    的名字一旦被存下来，按名字匹配就会把它当成仪表，于是歌词窗口盖在桌面自己
        //    身上：整个中间一条半透明底被压暗，桌面和设置页的字看起来全糊掉了。
        if (wantName != null && !wantName.trim().isEmpty()) {
            String wanted = wantName.trim();
            int match = NONE;
            int matches = 0;
            for (int i = 0; i < length; i++) {
                if (ids[i] <= 0) continue;
                String name = names[i] == null ? "" : names[i].trim();
                if (!wanted.equalsIgnoreCase(name)) continue;
                matches++;
                if (match == NONE) match = i;
            }
            if (matches == 1) return match;
        }
        return NONE;
    }

    /** First presentation-capable secondary display, for the "pick for me" button. */
    public static int firstPresentation(int[] ids, boolean[] presentation) {
        if (ids == null || presentation == null) return NONE;
        int length = Math.min(ids.length, presentation.length);
        for (int i = 0; i < length; i++) {
            if (presentation[i] && ids[i] > 0) return i;
        }
        return NONE;
    }

    /** First secondary display of any kind; the fallback when nothing advertises itself. */
    public static int firstSecondary(int[] ids) {
        if (ids == null) return NONE;
        for (int i = 0; i < ids.length; i++) {
            if (ids[i] > 0) return i;
        }
        return NONE;
    }

    /** Human label for a display row: {@code 仪表 · ID 1 · 1920×720 · 240 dpi}. */
    public static String label(String name, int id, int width, int height, int densityDpi) {
        StringBuilder out = new StringBuilder();
        String trimmed = name == null ? "" : name.trim();
        out.append(trimmed.isEmpty() ? "屏幕 " + id : trimmed);
        out.append("  ·  ID ").append(id);
        if (width > 0 && height > 0) out.append("  ·  ").append(width).append('×').append(height);
        if (densityDpi > 0) out.append("  ·  ").append(densityDpi).append(" dpi");
        return out.toString();
    }
}
