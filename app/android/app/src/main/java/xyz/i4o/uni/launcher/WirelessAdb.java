package xyz.i4o.uni.launcher;

import android.content.ComponentName;
import android.content.ContentResolver;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.content.pm.PackageManager;
import android.net.wifi.WifiManager;
import android.os.Handler;
import android.os.SystemClock;
import android.provider.Settings;

import org.json.JSONObject;

import java.net.Inet4Address;
import java.net.InetAddress;
import java.net.InetSocketAddress;
import java.net.NetworkInterface;
import java.net.Socket;
import java.util.Collections;
import java.util.Enumeration;

/**
 * 开机自动启动无线 adb。
 *
 * 真正改端口的事不在这个进程里做——那需要 system 域（写 {@code service.adb.tcp.port}
 * 和 {@code ctl.restart}）。这里只负责：开机时按开关把请求发给同签名的小桥
 * {@code xyz.i4o.uni.adbbridge}（sharedUserId=android.uid.system），然后自己探测
 * 127.0.0.1:5555 并把桥写回的状态（Settings.Global 的 uni_adb_*）如实显示出来。
 *
 * 只在开关打开时动手；探测不到监听就 20 秒后重试，最多 6 次。
 */
public final class WirelessAdb {
    public static final int PORT = 5555;
    public static final String BRIDGE_PACKAGE = "xyz.i4o.uni.adbbridge";
    public static final String BRIDGE_RECEIVER = BRIDGE_PACKAGE + ".SetReceiver";
    private static final String ACTION_SET = "xyz.i4o.uni.adb.SET";
    private static final String KEY_ENABLED = "bootWirelessAdb";
    private static final int MAX_ATTEMPTS = 6;
    private static final long RETRY_MS = 20000L;

    private final Context context;
    private final SharedPreferences prefs;
    private final Handler main;
    private final Runnable publish;
    private final JSONObject state = new JSONObject();
    private boolean scheduled;
    private boolean running;

    public WirelessAdb(Context context, SharedPreferences prefs, Handler main, Runnable publish) {
        this.context = context.getApplicationContext();
        this.prefs = prefs;
        this.main = main;
        this.publish = publish;
    }

    public boolean enabled() { return prefs.getBoolean(KEY_ENABLED, false); }

    public void setEnabled(boolean value) {
        prefs.edit().putBoolean(KEY_ENABLED, value).apply();
        put("enabled", value);
        if (value) {
            schedule();
        } else {
            request(false);
            put("state", "off");
            put("reason", "");
            put("listening", false);
            put("attempt", 0);
        }
        emit();
    }

    /** 桥装没装（同签名的小 APK，uid 1000）。 */
    public boolean bridgeInstalled() {
        try {
            context.getPackageManager().getPackageInfo(BRIDGE_PACKAGE, 0);
            return true;
        } catch (Exception | LinkageError e) {
            return false;
        }
    }

    /** 开机只排一次；开关打开、改完设置也会走这里。 */
    public void schedule() {
        if (scheduled) { ensureOnce(); return; }
        scheduled = true;
        main.postDelayed(new Runnable() { public void run() { ensureOnce(); } }, 3000);
    }

    /** 设置页的「立即开启」。 */
    public void ensureNow() {
        running = false;
        main.post(new Runnable() { public void run() { ensureOnce(); } });
    }

    private void ensureOnce() {
        if (running) return;
        if (!enabled()) {
            put("enabled", false); put("state", "off"); put("reason", "");
            emit();
            return;
        }
        running = true;
        new Thread(new Runnable() {
            public void run() {
                JSONObject result;
                try {
                    result = attempt();
                } catch (Throwable error) {
                    result = new JSONObject();
                    try {
                        result.put("state", "failed")
                                .put("reason", "执行异常：" + error.getClass().getSimpleName());
                    } catch (Exception ignored) {}
                }
                final JSONObject done = result;
                main.post(new Runnable() {
                    public void run() {
                        merge(done);
                        running = false;
                        emit();
                        int attempt = state.optInt("attempt", 0);
                        boolean settled = "ready".equals(state.optString("state"))
                                || "off".equals(state.optString("state"))
                                || "missing".equals(state.optString("state"));
                        if (!settled && attempt < MAX_ATTEMPTS && enabled())
                            main.postDelayed(new Runnable() { public void run() { ensureOnce(); } }, RETRY_MS);
                    }
                });
            }
        }, "wireless-adb").start();
    }

    /** 一轮：问桥 → 探测端口 → 汇总状态。工作线程。 */
    private JSONObject attempt() {
        JSONObject out = new JSONObject();
        int attempt = state.optInt("attempt", 0) + 1;
        long started = System.currentTimeMillis();

        if (!bridgeInstalled()) {
            return fill(out, "missing",
                    "还没有安装无线 adb 桥（dist/UNI-AdbBridge-1.0-IP753.apk），装好后这里会自动生效",
                    attempt, false, false);
        }

        boolean sent = request(true);
        boolean listening = waitForPort(12000);
        String bridgeState = globalString("uni_adb_state");
        String bridgeDetail = globalString("uni_adb_detail");

        String stateValue;
        String reason;
        if (listening) {
            stateValue = "ready";
            reason = "";
        } else if ("blocked".equals(bridgeState) || "failed".equals(bridgeState)) {
            stateValue = bridgeState;
            reason = bridgeDetail;
        } else if (!sent) {
            stateValue = "failed";
            reason = "桥组件没有响应（可能被系统限制后台广播）";
        } else if (bridgeDetail != null && !bridgeDetail.isEmpty()) {
            stateValue = "pending";
            reason = bridgeDetail;
        } else {
            stateValue = "pending";
            reason = "已通知桥组件，但 " + PORT + " 端口还没有监听";
        }
        return fill(out, stateValue, reason, attempt, true, listening);
    }

    private JSONObject fill(JSONObject out, String stateValue, String reason,
                            int attempt, boolean bridge, boolean listening) {
        try {
            out.put("enabled", true)
                    .put("attempt", attempt)
                    .put("port", PORT)
                    .put("portProperty", globalString("uni_adb_state") == null ? "" : property())
                    .put("bridge", bridge)
                    .put("listening", listening)
                    .put("address", address())
                    .put("state", stateValue)
                    .put("reason", reason == null ? "" : reason)
                    .put("updatedAtMs", System.currentTimeMillis());
        } catch (Exception ignored) {}
        return out;
    }

    /** 给桥发一条 SET 广播（同签名 signature 权限）。 */
    private boolean request(boolean on) {
        try {
            Intent intent = new Intent(ACTION_SET);
            intent.setComponent(new ComponentName(BRIDGE_PACKAGE, BRIDGE_RECEIVER));
            intent.putExtra("enabled", on);
            // 桥刚装好还处于 stopped 状态，不带这个标记的广播会被系统直接丢掉。
            intent.addFlags(Intent.FLAG_INCLUDE_STOPPED_PACKAGES);
            context.sendBroadcast(intent);
            return true;
        } catch (Exception | LinkageError e) {
            return false;
        }
    }

    private boolean waitForPort(long timeoutMs) {
        long deadline = SystemClock.elapsedRealtime() + timeoutMs;
        while (SystemClock.elapsedRealtime() < deadline) {
            if (listening()) return true;
            try { Thread.sleep(300); } catch (InterruptedException ignored) {}
        }
        return listening();
    }

    private boolean listening() {
        Socket socket = new Socket();
        try {
            socket.connect(new InetSocketAddress("127.0.0.1", PORT), 400);
            return true;
        } catch (Exception | LinkageError e) {
            return false;
        } finally {
            try { socket.close(); } catch (Exception ignored) {}
        }
    }

    /** 端口属性只读（写要靠桥）；getprop 不受 hidden API 限制。 */
    private String property() {
        Process process = null;
        try {
            process = new ProcessBuilder("getprop", "service.adb.tcp.port")
                    .redirectErrorStream(true).start();
            java.io.BufferedReader reader = new java.io.BufferedReader(
                    new java.io.InputStreamReader(process.getInputStream()));
            String line = reader.readLine();
            process.waitFor();
            return line == null ? "" : line.trim();
        } catch (Exception | LinkageError e) {
            return "";
        } finally {
            if (process != null) process.destroy();
        }
    }

    private String globalString(String key) {
        try {
            ContentResolver resolver = context.getContentResolver();
            return Settings.Global.getString(resolver, key);
        } catch (Exception | LinkageError e) {
            return null;
        }
    }

    /** 本机 wlan0 的 IPv4，给设置页显示「adb connect IP:5555」。 */
    private String address() {
        String ip = null;
        try {
            WifiManager wifi = (WifiManager) context.getApplicationContext()
                    .getSystemService(Context.WIFI_SERVICE);
            if (wifi != null) {
                int raw = wifi.getConnectionInfo().getIpAddress();
                if (raw != 0) {
                    ip = (raw & 0xFF) + "." + ((raw >> 8) & 0xFF) + "."
                            + ((raw >> 16) & 0xFF) + "." + ((raw >> 24) & 0xFF);
                }
            }
        } catch (Exception | LinkageError ignored) {}
        if (ip == null || ip.isEmpty() || "0.0.0.0".equals(ip)) {
            try {
                Enumeration<NetworkInterface> all = NetworkInterface.getNetworkInterfaces();
                for (NetworkInterface n : all == null
                        ? Collections.<NetworkInterface>emptyList() : Collections.list(all)) {
                    if (!n.isUp() || n.isLoopback()) continue;
                    for (InetAddress address : Collections.list(n.getInetAddresses())) {
                        if (address instanceof Inet4Address && !address.isLoopbackAddress()) {
                            ip = address.getHostAddress();
                            break;
                        }
                    }
                    if (ip != null) break;
                }
            } catch (Exception | LinkageError ignored) {}
        }
        return (ip == null || ip.isEmpty() ? "" : ip) + ":" + PORT;
    }

    private void merge(JSONObject patch) {
        try {
            for (java.util.Iterator<String> keys = patch.keys(); keys.hasNext(); ) {
                String key = keys.next();
                state.put(key, patch.opt(key));
            }
        } catch (Exception ignored) {}
    }

    private void put(String key, Object value) {
        try { state.put(key, value); } catch (Exception ignored) {}
    }

    private void emit() {
        put("enabled", enabled());
        if (publish != null) publish.run();
    }

    /** 给 Dart 的快照；字段固定，缺省也补齐。 */
    public JSONObject snapshot() {
        JSONObject out = new JSONObject();
        boolean bridge = bridgeInstalled();
        try {
            out.put("enabled", enabled())
                    .put("port", PORT)
                    .put("portProperty", state.optString("portProperty", ""))
                    .put("bridge", bridge)
                    .put("listening", state.optBoolean("listening", false))
                    .put("address", state.optString("address", ":" + PORT))
                    .put("state", state.optString("state",
                            bridge ? (enabled() ? "idle" : "off") : "missing"))
                    .put("reason", state.optString("reason", ""))
                    .put("attempt", state.optInt("attempt", 0))
                    .put("updatedAtMs", state.optLong("updatedAtMs", 0));
        } catch (Exception ignored) {}
        return out;
    }
}
