package xyz.i4o.uni.launcher.integration;

import android.content.ComponentName;
import android.content.Context;
import org.json.JSONArray;
import org.json.JSONObject;
import java.io.ByteArrayOutputStream;
import java.io.InputStream;
import java.util.ArrayList;
import java.util.List;

/** Generated catalog is the same versioned evidence used by the design, not a second list. */
public final class OfficialCatalog {
    private final JSONObject catalog;
    private final Context context;
    public OfficialCatalog(Context context) {
        this.context = context;
        JSONObject loaded = new JSONObject();
        try {
            InputStream in = context.getAssets().open("official-widgets.json");
            ByteArrayOutputStream out = new ByteArrayOutputStream(); byte[] b = new byte[4096]; int n;
            while ((n = in.read(b)) != -1) out.write(b, 0, n);
            in.close(); loaded = new JSONObject(out.toString("UTF-8"));
        } catch (Exception e) { android.util.Log.e("UniCatalog", "Catalog unavailable", e); }
        catalog = loaded;
    }
    public static String normalize(String type) {
        return type == null ? "" : "music".equals(type) ? "media" : "nav".equals(type) ? "navigation" : type;
    }
    public String label(String type) {
        JSONObject row = type(normalize(type));
        return row == null ? "原厂卡片" : row.optString("label", "原厂卡片");
    }
    private JSONObject type(String normalized) {
        JSONArray types = catalog.optJSONArray("types");
        if (types != null) for (int i = 0; i < types.length(); i++) {
            JSONObject row = types.optJSONObject(i);
            if (row != null && normalized.equals(row.optString("id"))) return row;
        }
        return null;
    }
    public List<ComponentName> providers(String type) {
        List<ComponentName> result = new ArrayList<ComponentName>();
        JSONObject row = type(normalize(type));
        JSONArray components = row == null ? null : row.optJSONArray("providerComponents");
        if (components != null) for (int j = 0; j < components.length(); j++) {
            ComponentName c = ComponentName.unflattenFromString(components.optString(j));
            if (c != null && !result.contains(c)) result.add(c);
        }
        return result;
    }
    public String packageFor(String type) {
        List<String> packages = applicationPackages(type);
        AppRepository apps = new AppRepository(context);
        for (String pkg : packages) if ("available".equals(apps.packageStatus(pkg))) return pkg;
        return packages.isEmpty() ? "" : packages.get(0);
    }
    /** DCY11 workspace + official Utilities variants; class namespaces are not package IDs. */
    public List<String> applicationPackages(String type) {
        List<String> result = new ArrayList<String>();
        String normalized = normalize(type);
        if ("climate".equals(type)) result.add("com.ecarx.hvac");
        else if ("vehicle".equals(type)) result.add("com.ecarx.xcvehicle");
        else if ("settings".equals(type)) {
            result.add("com.ecarx.settings");
            result.add("ecarx.settings");
        }
        else if ("phone".equals(type)) result.add("com.ecarx.btphone");
        else if ("navigation".equals(normalized)) result.add("com.autonavi.amapauto");
        for (ComponentName provider : providers(normalized)) {
            if (!result.contains(provider.getPackageName())) result.add(provider.getPackageName());
        }
        if ("weather".equals(normalized)) result.add("ecarx.weather");
        return result;
    }
}
