package xyz.i4o.uni.launcher.integration;

import android.appwidget.AppWidgetProviderInfo;
import android.content.ComponentName;
import java.util.List;

/** Exact package + class identity only. Availability never implies data-field parity. */
public final class OfficialEntryAdapter {
    private OfficialEntryAdapter() {}

    public static AppWidgetProviderInfo select(List<ComponentName> candidates,
            List<AppWidgetProviderInfo> installed, ComponentName preferred) {
        if (installed == null) return null;
        if (preferred != null && candidates.contains(preferred)) {
            for (AppWidgetProviderInfo info : installed) {
                if (info != null && preferred.equals(info.provider)) return info;
            }
        }
        // Catalog order retains the DCY11 default ahead of other model variants.
        for (ComponentName candidate : candidates) {
            for (AppWidgetProviderInfo info : installed) {
                if (info != null && candidate.equals(info.provider)) return info;
            }
        }
        return null;
    }
}
