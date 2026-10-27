package xyz.i4o.uni.launcher.integration;

import android.app.Activity;
import android.appwidget.AppWidgetHost;
import android.appwidget.AppWidgetHostView;
import android.appwidget.AppWidgetManager;
import android.appwidget.AppWidgetProviderInfo;
import android.content.ComponentName;
import android.content.Intent;
import android.content.SharedPreferences;
import android.os.Bundle;
import android.view.View;
import android.widget.Button;
import android.widget.LinearLayout;
import android.widget.TextView;
import java.util.List;

/** Own host IDs only; RemoteViews stay inside the OEM application data boundary. */
public final class OfficialWidgetActivity extends Activity {
    private static final int HOST_ID = 75301, BIND = 10, CONFIGURE = 11;
    private AppWidgetHost host;
    private AppWidgetManager manager;
    private OfficialCatalog catalog;
    private AppRepository apps;
    private AppWidgetProviderInfo info;
    private int widgetId = -1, pendingRequest;
    private String type;
    private boolean committed;
    private SharedPreferences prefs;
    private LinearLayout content;
    private TextView status, appStatus;
    private Button openApp, retry;

    @Override protected void onCreate(Bundle saved) {
        super.onCreate(saved);
        host = new AppWidgetHost(this, HOST_ID);
        manager = AppWidgetManager.getInstance(this);
        prefs = getSharedPreferences("widgets", 0);
        catalog = new OfficialCatalog(this);
        apps = new AppRepository(this);
        String requestedType = getIntent().getStringExtra("type");
        type = OfficialCatalog.normalize(requestedType);
        // Older hosts persisted Flutter's music/nav aliases as their preference keys.
        if (requestedType != null && !type.equals(requestedType) && !prefs.contains(type) && prefs.contains(requestedType)) {
            prefs.edit().putInt(type, prefs.getInt(requestedType, -1)).remove(requestedType).apply();
        }
        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        int padding = (int) (16 * getResources().getDisplayMetrics().density);
        root.setPadding(padding, padding, padding, padding);
        setContentView(root);
        Button back = new Button(this);
        back.setText("‹ 返回桌面");
        back.setOnClickListener(new View.OnClickListener() {
            public void onClick(View v) { finish(); }
        });
        root.addView(back);
        TextView boundary = new TextView(this);
        boundary.setText("原车" + catalog.label(type) + "兼容视图 · 内容由原车应用提供");
        root.addView(boundary);
        openApp = new Button(this);
        openApp.setText("打开原车" + catalog.label(type) + "应用");
        openApp.setOnClickListener(new View.OnClickListener() {
          public void onClick(View v) {
            if (!apps.launchOfficial(type)) {
                updateAppEntry();
                appStatus.setText("原车应用当前无法启动，请检查安装、启用状态和权限。");
            }
          }
        });
        root.addView(openApp);
        appStatus = new TextView(this);
        root.addView(appStatus);
        status = new TextView(this);
        status.setTextSize(20);
        root.addView(status);
        retry = new Button(this);
        retry.setText("重试原厂卡片");
        retry.setOnClickListener(new View.OnClickListener() {
            public void onClick(View v) { if (pendingRequest == 0) { updateAppEntry(); prepare(null); } }
        });
        root.addView(retry);
        content = new LinearLayout(this);
        content.setOrientation(LinearLayout.VERTICAL);
        root.addView(content, new LinearLayout.LayoutParams(-1, 0, 1));
        updateAppEntry();
        prepare(saved);
    }

    private void updateAppEntry() {
        boolean available = false, installed = false, failed = false;
        for (String pkg : catalog.applicationPackages(type)) {
            String state = apps.packageStatus(pkg);
            available |= "available".equals(state);
            installed |= !"not-installed".equals(state);
            failed |= "unavailable".equals(state);
        }
        openApp.setEnabled(available);
        appStatus.setText(available ? "可直接打开原车应用，独立于卡片授权。"
            : failed ? "无法检查原车应用，请稍后重试。"
            : installed ? "原车应用已安装，但没有可访问的启动入口或已被停用。"
            : "未安装对应原车应用；此处不使用演示数据。");
    }

    private void prepare(Bundle saved) {
        content.removeAllViews();
        retry.setEnabled(true);
        try {
            List<ComponentName> candidates = catalog.providers(type);
            if (candidates.isEmpty()) { message("没有此类型的官方卡片记录。"); return; }
            List<AppWidgetProviderInfo> installed = manager.getInstalledProviders();
            if (saved != null && type.equals(saved.getString("type"))) {
                widgetId = saved.getInt("pendingId", -1);
                pendingRequest = saved.getInt("pendingRequest", 0);
                ComponentName expected = ComponentName.unflattenFromString(saved.getString("provider", ""));
                info = OfficialEntryAdapter.select(candidates, installed, expected);
                if (pendingRequest != 0 && widgetId != -1 && owns(widgetId) && info != null
                        && info.provider.equals(expected)) {
                    retry.setEnabled(false);
                    message("等待系统授权或原车卡片配置完成。");
                    return;
                }
                pendingRequest = 0;
            }
            // Recover an allocation abandoned by process death before its activity result.
            int abandoned = prefs.getInt(type + ".pending", -1);
            if (abandoned != -1) deleteOwned(abandoned);
            prefs.edit().remove(type + ".pending").apply();
            widgetId = prefs.getInt(type, -1);
            committed = false;
            if (widgetId != -1) {
                AppWidgetProviderInfo previous = manager.getAppWidgetInfo(widgetId);
                info = OfficialEntryAdapter.select(candidates, installed, previous == null ? null : previous.provider);
                if (owns(widgetId) && previous != null && info != null && info.provider.equals(previous.provider)) {
                    committed = true;
                    showWidget();
                    return;
                }
                deleteOwned(widgetId);
                prefs.edit().remove(type).apply();
                widgetId = -1;
            }
            info = OfficialEntryAdapter.select(candidates, installed, null);
            if (info == null) { message("未发现对应原厂卡片，可尝试上方原车应用入口。"); return; }
            widgetId = host.allocateAppWidgetId();
            prefs.edit().putInt(type + ".pending", widgetId).apply();
            Bundle options = new Bundle();
            options.putInt(AppWidgetManager.OPTION_APPWIDGET_HOST_CATEGORY, AppWidgetProviderInfo.WIDGET_CATEGORY_HOME_SCREEN);
            if (manager.bindAppWidgetIdIfAllowed(widgetId, info.provider, options)) configureOrShow();
            else {
                pendingRequest = BIND;
                retry.setEnabled(false);
                startActivityForResult(new Intent(AppWidgetManager.ACTION_APPWIDGET_BIND)
                    .putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, widgetId)
                    .putExtra(AppWidgetManager.EXTRA_APPWIDGET_PROVIDER, info.provider)
                    .putExtra(AppWidgetManager.EXTRA_APPWIDGET_OPTIONS, options), BIND);
            }
        } catch (Exception e) { fail("系统暂不允许绑定此原厂卡片，可使用上方原车应用入口。", e); }
    }

    private boolean owns(int id) {
        for (int owned : host.getAppWidgetIds()) if (id == owned) return true;
        return false;
    }

    private void deleteOwned(int id) {
        if (id != -1 && owns(id)) host.deleteAppWidgetId(id);
    }

    private boolean matchingBinding() {
        AppWidgetProviderInfo bound = manager.getAppWidgetInfo(widgetId);
        AppWidgetProviderInfo installed = bound == null ? null : OfficialEntryAdapter.select(
            catalog.providers(type), manager.getInstalledProviders(), bound.provider);
        return owns(widgetId) && bound != null && info != null && info.provider.equals(bound.provider)
            && installed != null && installed.provider.equals(bound.provider);
    }

    private void configureOrShow() {
        if (!matchingBinding()) { fail("绑定的卡片与官方组件不一致，请重试。", null); return; }
        if (info.configure == null) showWidget();
        else {
            pendingRequest = CONFIGURE;
            retry.setEnabled(false);
            message("请完成原车卡片配置。");
            host.startAppWidgetConfigureActivityForResult(this, widgetId, 0, CONFIGURE, null);
        }
    }

    private void showWidget() {
        AppWidgetHostView view = host.createView(this, widgetId, info);
        view.setAppWidget(widgetId, info);
        content.removeAllViews();
        content.addView(view, new LinearLayout.LayoutParams(-1, -1));
        view.addOnLayoutChangeListener(new View.OnLayoutChangeListener() {
            public void onLayoutChange(View v, int l, int t, int r, int b, int ol, int ot, int or, int ob) {
                if (r <= l || b <= t || (r - l == or - ol && b - t == ob - ot)) return;
                float density = getResources().getDisplayMetrics().density;
                int width = Math.max(1, Math.round((r - l) / density));
                int height = Math.max(1, Math.round((b - t) / density));
                try { view.updateAppWidgetSize(null, width, height, width, height); }
                catch (Exception e) { android.util.Log.w("UniWidget", "Unable to update widget size", e); }
            }
        });
        prefs.edit().putInt(type, widgetId).remove(type + ".pending").apply();
        committed = true;
        pendingRequest = 0;
        retry.setEnabled(true);
        message("原车卡片独立显示，桌面摘要尚未同步。");
    }

    private void message(String text) { status.setText(text); }

    @Override protected void onActivityResult(int request, int result, Intent data) {
        super.onActivityResult(request, result, data);
        if (request != pendingRequest || (request != BIND && request != CONFIGURE)) return;
        pendingRequest = 0;
        try {
            int returned = data == null ? widgetId : data.getIntExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, widgetId);
            if (result != RESULT_OK || returned != widgetId || !matchingBinding()) {
                fail(result == RESULT_OK ? "原厂卡片绑定失效，请重试。"
                    : request == BIND ? "未授权原厂卡片，可使用上方原车应用入口。"
                    : "已取消原车卡片配置，可重试或打开原车应用。", null);
            } else if (request == BIND) configureOrShow();
            else showWidget();
        } catch (Exception e) { fail("原车卡片服务暂不可用，可使用上方原车应用入口。", e); }
    }

    private void cleanup() {
        if (committed || widgetId == -1) return;
        try { deleteOwned(widgetId); }
        catch (Exception e) { android.util.Log.w("UniWidget", "Unable to release pending widget", e); }
        // Keep the journal if deletion failed so the next attempt can recover it.
        try { if (!owns(widgetId)) prefs.edit().remove(type + ".pending").apply(); }
        catch (Exception ignored) { }
        widgetId = -1;
    }

    private void fail(String text, Exception error) {
        if (error != null) android.util.Log.w("UniWidget", text, error);
        pendingRequest = 0;
        cleanup();
        retry.setEnabled(true);
        message(text);
    }

    @Override protected void onSaveInstanceState(Bundle out) {
        super.onSaveInstanceState(out);
        out.putString("type", type);
        out.putString("provider", info == null ? "" : info.provider.flattenToString());
        out.putInt("pendingId", widgetId);
        out.putInt("pendingRequest", pendingRequest);
    }
    @Override protected void onResume() { super.onResume(); updateAppEntry(); }
    @Override protected void onStart() {
        super.onStart();
        try { host.startListening(); }
        catch (Exception e) { message("卡片服务暂不可用，可重试或打开原车应用。"); }
    }
    @Override protected void onStop() {
        try { host.stopListening(); }
        catch (Exception e) { android.util.Log.w("UniWidget", "Unable to stop listening", e); }
        super.onStop();
    }
    @Override protected void onDestroy() { if (isFinishing()) cleanup(); super.onDestroy(); }
}
