package xyz.i4o.uni.launcher.integration;

import android.appwidget.AppWidgetProviderInfo;
import android.content.ComponentName;
import java.util.List;
import xyz.i4o.uni.launcher.log.LogTags;
import xyz.i4o.uni.launcher.log.UniLog;

/** Exact package + class identity only. Availability never implies data-field parity. */
public final class OfficialEntryAdapter {
    private OfficialEntryAdapter() {}

    public static AppWidgetProviderInfo select(List<ComponentName> candidates,
            List<AppWidgetProviderInfo> installed, ComponentName preferred) {
        UniLog.enter(LogTags.APP, "widget/select",
                "preferred", preferred == null ? null : preferred.flattenToString(),
                "candidates", candidates == null ? 0 : candidates.size(),
                "installed", installed == null ? 0 : installed.size());
        if (installed == null) {
            UniLog.done(LogTags.APP, "widget/select", "result", "NO_INSTALLED_LIST");
            return null;
        }
        if (preferred != null && candidates.contains(preferred)) {
            for (AppWidgetProviderInfo info : installed) {
                if (info != null && preferred.equals(info.provider)) {
                    UniLog.done(LogTags.APP, "widget/select", "result", "PREFERRED",
                            "provider", info.provider.flattenToString());
                    return info;
                }
            }
        }
        // Catalog order retains the DCY11 default ahead of other model variants.
        for (ComponentName candidate : candidates) {
            for (AppWidgetProviderInfo info : installed) {
                if (info != null && candidate.equals(info.provider)) {
                    UniLog.done(LogTags.APP, "widget/select", "result", "CATALOG_MATCH",
                            "provider", info.provider.flattenToString());
                    return info;
                }
            }
        }
        UniLog.done(LogTags.APP, "widget/select", "result", "NO_MATCH",
                "candidates", candidates == null ? 0 : candidates.size());
        return null;
    }
}
