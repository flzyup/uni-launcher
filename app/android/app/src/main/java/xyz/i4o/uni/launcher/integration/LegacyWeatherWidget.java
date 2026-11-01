package xyz.i4o.uni.launcher.integration;

import android.appwidget.AppWidgetHost;
import android.appwidget.AppWidgetHostView;
import android.appwidget.AppWidgetManager;
import android.appwidget.AppWidgetProviderInfo;
import android.content.ComponentName;
import android.content.Context;
import android.content.SharedPreferences;
import android.os.Handler;
import android.os.Looper;
import android.view.View;
import android.widget.RemoteViews;
import android.widget.TextView;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

/** Reads the public RemoteViews of the 2021 XCHome weather widget; no private data access. */
final class LegacyWeatherWidget {
    interface Listener {
        void onWeather(String city, String condition, double temperature);
        void onUnavailable(String reason);
    }
    private static final String PACKAGE = "com.ecarx.smartcloud";
    private static final ComponentName PROVIDER = new ComponentName(
        PACKAGE, "ecarx.home.module.widget.WeatherWidgetProvider1X2");
    private static final int HOST_ID = 74402;
    private final Context context;
    private final Listener listener;
    private final Handler main = new Handler(Looper.getMainLooper());
    private final SharedPreferences prefs;
    private AppWidgetManager manager;
    private AppWidgetHost host;
    private AppWidgetHostView view;
    private int id = -1;
    private boolean active;

    LegacyWeatherWidget(Context context, Listener listener) {
        this.context = context.getApplicationContext();
        this.listener = listener;
        prefs = this.context.getSharedPreferences("legacy_weather_widget", 0);
    }
    void start() {
        if (active) return;
        active = true;
        try {
            manager = AppWidgetManager.getInstance(context);
            host = new AppWidgetHost(context, HOST_ID) {
                @Override protected AppWidgetHostView onCreateView(Context c, int widgetId, AppWidgetProviderInfo info) {
                    return new AppWidgetHostView(c) {
                        @Override public void updateAppWidget(RemoteViews views) {
                            super.updateAppWidget(views);
                            if (views != null) main.post(() -> read(this));
                        }
                    };
                }
            };
            int saved = prefs.getInt("id", -1);
            boolean owned = false;
            for (int item : host.getAppWidgetIds()) if (item == saved) owned = true;
            AppWidgetProviderInfo info = owned ? manager.getAppWidgetInfo(saved) : null;
            if (info != null && PROVIDER.equals(info.provider)) id = saved;
            else {
                if (owned) host.deleteAppWidgetId(saved);
                prefs.edit().remove("id").apply();
                id = host.allocateAppWidgetId();
                if (!manager.bindAppWidgetIdIfAllowed(id, PROVIDER)) {
                    host.deleteAppWidgetId(id); id = -1;
                    listener.onUnavailable("原车天气组件绑定未获授权"); return;
                }
                prefs.edit().putInt("id", id).apply();
                info = manager.getAppWidgetInfo(id);
            }
            if (info == null) { listener.onUnavailable("原车天气组件不可用"); return; }
            view = host.createView(context, id, info);
            view.setAppWidget(id, info);
            host.startListening();
            main.post(() -> read(view));
        } catch (RuntimeException e) {
            listener.onUnavailable("原车天气组件暂不可用");
            android.util.Log.w("UniWeather", "Legacy weather widget unavailable", e);
        }
    }
    private String text(View root, String name) {
        if (root == null) return "";
        int resource = context.getResources().getIdentifier(name, "id", PACKAGE);
        if (resource == 0) try {
            resource = context.getPackageManager().getResourcesForApplication(PACKAGE).getIdentifier(name, "id", PACKAGE);
        } catch (Exception ignored) { }
        View child = resource == 0 ? null : root.findViewById(resource);
        return child instanceof TextView ? String.valueOf(((TextView) child).getText()).trim() : "";
    }
    private void read(View root) {
        if (!active || root == null) return;
        String city = text(root, "tv_resident_city");
        if (city.isEmpty()) city = text(root, "tv_area");
        String condition = text(root, "tv_trend");
        String raw = text(root, "tv_temperature").replace('−', '-');
        if (raw.isEmpty()) raw = text(root, "tv_today_temp").replace('−', '-');
        Matcher match = Pattern.compile("^[+-]?[0-9]+(?:\\.[0-9]+)?").matcher(raw);
        if (!match.find() || city.isEmpty() || city.length() > 80 || condition.length() > 80) {
            android.util.Log.i("UniWeather", "Legacy widget fields: temp=" + (raw.isEmpty() ? "empty" : raw)
                + ", cityLength=" + city.length() + ", conditionLength=" + condition.length()
                + ", children=" + (root instanceof android.view.ViewGroup ? ((android.view.ViewGroup) root).getChildCount() : 0));
            listener.onUnavailable("等待原车天气组件返回城市和温度（温度 " + raw
                + "，城市长度 " + city.length() + "，天气长度 " + condition.length()
                + "，视图数 " + (root instanceof android.view.ViewGroup ? ((android.view.ViewGroup) root).getChildCount() : 0) + "）");
            return;
        }
        try {
            double value = Double.parseDouble(match.group());
            if (value < -90 || value > 70) return;
            listener.onWeather(city, condition, value);
        } catch (NumberFormatException ignored) { }
    }
    void stop() {
        active = false;
        if (host != null) try { host.stopListening(); } catch (RuntimeException ignored) { }
        view = null; host = null; manager = null;
    }
}
