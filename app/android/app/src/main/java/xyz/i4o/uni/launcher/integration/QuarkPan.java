package xyz.i4o.uni.launcher.integration;

import android.content.Context;
import android.os.Handler;
import android.os.Looper;
import android.util.Log;
import java.io.ByteArrayOutputStream;
import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.InputStream;
import java.io.OutputStream;
import java.net.HttpURLConnection;
import java.net.URL;
import java.net.URLEncoder;
import java.security.MessageDigest;
import java.util.ArrayDeque;
import java.util.Deque;
import java.util.UUID;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.ScheduledExecutorService;
import java.util.concurrent.ScheduledFuture;
import java.util.concurrent.TimeUnit;
import org.json.JSONArray;
import org.json.JSONObject;

/**
 * 夸克网盘（TV / 设备授权通道）。
 *
 * 为什么不用网页那条：PC 网页的二维码 token 属于 {@code client_id=532} 那套会话，
 * 手机夸克 App 扫进去换票会对不上，实测只会得到「登录请求已过期」。
 * 这里换成 TV 授权：
 * <ol>
 *   <li>{@code GET /oauth/authorize?auth_type=code&qrcode=1} 直接返回 base64 二维码图与 query_token；</li>
 *   <li>轮询 {@code GET /oauth/code}：未确认是 {@code errno=11003 用户未确认授权}，扫码确认后给 code；</li>
 *   <li>{@code POST /token} 用 code 换 access_token + refresh_token —— refresh_token 才是「长期有效」的本体，
 *       access_token 到期就用它续，不需要用户再扫码。</li>
 * </ol>
 * 每个请求都要签名：{@code x-pan-token = sha256(method + "&" + path + "&" + ts + "&" + signKey)}，
 * {@code req_id = md5(deviceId + ts)}。deviceId 必须**长期稳定**，否则换来的 token 会被判设备不一致，
 * 所以首次生成后落盘。
 *
 * 下载地址由 {@code /file?method=download} 现取现用，不落盘（签名会过期）。
 * cookie / token 只在原生侧流转，{@link #snapshot()} 只吐昵称、容量和二维码图。
 */
public final class QuarkPan {
    private static final String TAG = "UniQuarkTV";

    // ---- TV 通道参数（接口变动只需改这一段；来源 OpenList quark_uc_tv 驱动） ----
    static final String API = "https://open-api-drive.quark.cn";
    /** 官方 token 端点要求 App 侧签名，社区用这个转发端点代换 access/refresh token。 */
    static final String CODE_API = "http://api.extscreen.com/quarkdrive/token";
    static final String CLIENT_ID = "d3194e61504e493eb6222857bccfed94";
    static final String SIGN_KEY = "kw2dvtd7p4t3pjl2d9ed9yc8yej8kw2d";
    static final String APP_VER = "1.8.2.2";
    static final String CHANNEL = "GENERAL";
    static final String UA = "Mozilla/5.0 (Linux; U; Android 13; zh-cn; M2004J7AC"
            + " Build/UKQ1.231108.001) AppleWebKit/533.1 (KHTML, like Gecko) Mobile Safari/533.1";
    static final String DEVICE_BRAND = "Xiaomi";
    static final String DEVICE_MODEL = "M2004J7AC";
    static final String DEVICE_GPU = "Adreno (TM) 550";
    static final String PLATFORM = "tv";

    static final long POLL_MS = 2000;
    static final long QR_TTL_MS = 5L * 60 * 1000;
    static final int PAGE_SIZE = 100;
    /** 用户未确认授权：继续等。 */
    static final int ERR_NOT_CONFIRMED = 11003;
    /** access_token 失效：刷新后重试一次。 */
    static final int ERR_TOKEN = 11001;

    private final Context context;
    private final Runnable changed;
    private final Handler main = new Handler(Looper.getMainLooper());
    private final File dir;
    private final File store;
    private final ExecutorService worker = Executors.newFixedThreadPool(2, r -> {
        Thread t = new Thread(r, "uni-quark");
        t.setDaemon(true);
        return t;
    });
    private final Object netLock = new Object();

    private volatile ScheduledExecutorService sched;
    private ScheduledFuture<?> pollTask;

    // ---- 凭证（只在原生侧） ----
    private volatile String deviceId = "";
    private volatile String accessToken = "";
    private volatile String refreshToken = "";
    private volatile String queryToken = "";
    private volatile long loginAt;

    // ---- 界面状态 ----
    private volatile String state = "idle";   // idle|waiting|scanned|authorized|expired|error
    private volatile String error = "";
    private volatile String qrImage = "";     // base64 PNG，服务端直接给
    private volatile long qrAt;
    private volatile String nickname = "";
    private volatile String memberType = "";
    private volatile long totalCapacity;
    private volatile long useCapacity;
    private volatile String pdir = "0";
    private volatile JSONArray entries = new JSONArray();
    private volatile int page = 1;
    private volatile int total;
    private final Deque<String[]> crumbs = new ArrayDeque<>();   // {fid, name}

    public QuarkPan(Context context, Runnable changed) {
        this.context = context.getApplicationContext();
        this.changed = changed;
        dir = new File(this.context.getFilesDir(), "quark");
        if (!dir.exists()) dir.mkdirs();
        store = new File(dir, "session.json");
    }

    // =====================================================================
    // 纯函数区（单测直接打这里，不碰网络）
    // =====================================================================

    static String hex(byte[] raw) {
        StringBuilder sb = new StringBuilder(raw.length * 2);
        for (byte b : raw) sb.append(Character.forDigit((b >> 4) & 0xF, 16))
                .append(Character.forDigit(b & 0xF, 16));
        return sb.toString();
    }

    /** {@code req_id = md5(deviceId + ts)}。 */
    static String reqId(String deviceId, String ts) {
        try {
            MessageDigest md = MessageDigest.getInstance("MD5");
            return hex(md.digest((deviceId + ts).getBytes("UTF-8")));
        } catch (Exception e) {
            return "";
        }
    }

    /** {@code x-pan-token = sha256(method + "&" + path + "&" + ts + "&" + signKey)}。 */
    static String sign(String method, String path, String ts, String key) {
        try {
            MessageDigest md = MessageDigest.getInstance("SHA-256");
            return hex(md.digest((method + "&" + path + "&" + ts + "&" + key).getBytes("UTF-8")));
        } catch (Exception e) {
            return "";
        }
    }

    /** 首次运行生成设备号；必须是稳定值，换设备号等于换设备。 */
    static String newDeviceId() {
        return UUID.randomUUID().toString().replace("-", "");
    }

    /** 夸克列表里的文件名是 HTML 转义过的，显示前还原。 */
    static String htmlUnescape(String s) {
        if (s == null) return "";
        return s.replace("&amp;", "&").replace("&lt;", "<").replace("&gt;", ">")
                .replace("&quot;", "\"").replace("&#39;", "'").replace("&nbsp;", " ");
    }

    /**
     * {@code /file?method=list} 的 data.files → 界面结构。
     * TV 通道字段名与网页侧不同（filename / isdir / updated_at），缺字段一律降级。
     */
    static JSONArray normalizeEntries(JSONArray raw) {
        JSONArray out = new JSONArray();
        if (raw == null) return out;
        for (int i = 0; i < raw.length(); i++) {
            JSONObject o = raw.optJSONObject(i);
            if (o == null) continue;
            String fid = o.optString("fid", "");
            if (fid.isEmpty()) continue;
            String name = htmlUnescape(o.optString("filename", o.optString("file_name", "")));
            if (name.isEmpty()) name = "(未命名)";
            try {
                out.put(new JSONObject()
                        .put("fid", fid)
                        .put("name", name)
                        .put("size", o.optLong("size", 0))
                        .put("dir", o.optInt("isdir", o.optBoolean("dir", false) ? 1 : 0) == 1)
                        .put("updatedAt", o.optLong("updated_at", 0))
                        .put("category", o.optInt("category", 0)));
            } catch (Exception ignored) {}
        }
        return out;
    }

    /** 轮询结果的判定：扫码确认前一律继续等，过期与失效要分开。 */
    static String pollVerdict(int http, int errno, String code, String info) {
        if (code != null && !code.trim().isEmpty()) return "code";
        if (errno == ERR_NOT_CONFIRMED) return "wait";
        if (errno == 11002) return "expired";
        // 上游也会用 HTTP 400 + 文案表达「请求过期」（网页通道的实测表现），文案优先于兜底
        String text = info == null ? "" : info;
        if (text.contains("过期") || text.contains("失效")) return "expired";
        if (http >= 400 && errno == 0 && text.trim().isEmpty()) return "wait";
        return "error";
    }

    /** 错误文案（直接给用户看）。 */
    static String errorText(int http, int errno, String info) {
        if (errno == ERR_TOKEN || (info != null && (info.contains("token") || info.contains("登录"))))
            return "夸克登录已失效，请重新扫码";
        if (errno == ERR_NOT_CONFIRMED) return "等待手机确认授权";
        if (errno == 11002) return "二维码已过期，请刷新";
        if (errno == 11004) return "授权码无效，请重新扫码";
        if (info != null && !info.trim().isEmpty()) return info.trim();
        if (http >= 500) return "夸克服务暂时不可用（HTTP " + http + "）";
        if (http >= 400) return "夸克拒绝了请求（HTTP " + http + "）";
        return "";
    }

    static boolean tokenBroken(int errno, String info) {
        if (errno == ERR_TOKEN) return true;
        String text = info == null ? "" : info.toLowerCase();
        return text.contains("access token") || text.contains("access_token")
                || text.contains("token无效") || text.contains("token 无效");
    }

    // =====================================================================
    // 网络
    // =====================================================================

    private static final class Resp {
        int http;
        String body = "";
        int status;
        int errno;
        String info = "";
        JSONObject json;

        JSONObject data() {
            return json == null ? new JSONObject() : json.optJSONObject("data");
        }
    }

    private static String enc(String s) {
        try {
            return URLEncoder.encode(s == null ? "" : s, "UTF-8");
        } catch (Exception e) {
            return "";
        }
    }

    /** 每个请求都要带的那串公参。 */
    private String commonQuery() {
        return "app_ver=" + APP_VER + "&device_id=" + enc(deviceId)
                + "&device_brand=" + enc(DEVICE_BRAND) + "&platform=" + PLATFORM
                + "&device_name=" + enc(DEVICE_MODEL) + "&device_model=" + enc(DEVICE_MODEL)
                + "&build_device=" + enc(DEVICE_MODEL) + "&build_product=" + enc(DEVICE_MODEL)
                + "&device_gpu=" + enc(DEVICE_GPU) + "&activity_rect=" + enc("{}")
                + "&channel=" + CHANNEL;
    }

    /** 走 TV 通道的请求：自动签名、带 access_token、token 失效时刷新并重试一次。 */
    private Resp request(String path, String extraQuery, boolean retryOnToken) {
        return request(path, extraQuery, retryOnToken, false);
    }

    private Resp request(String path, String extraQuery, boolean retryOnToken, boolean refreshing) {
        String ts = String.valueOf(System.currentTimeMillis());
        String url = API + path + "?req_id=" + reqId(deviceId, ts)
                + "&access_token=" + enc(accessToken) + "&" + commonQuery()
                + (extraQuery == null || extraQuery.isEmpty() ? "" : "&" + extraQuery);
        Resp r = http("GET", url, null, ts, sign("GET", path, ts, SIGN_KEY));
        if (retryOnToken && !refreshing && tokenBroken(r.errno, r.info)) {
            if (refreshSync()) return request(path, extraQuery, false, true);
        }
        return r;
    }

    private Resp http(String method, String url, JSONObject body, String ts, String sign) {
        Resp r = new Resp();
        HttpURLConnection conn = null;
        try {
            conn = (HttpURLConnection) new URL(url).openConnection();
            conn.setRequestMethod(method);
            conn.setConnectTimeout(15000);
            conn.setReadTimeout(20000);
            conn.setInstanceFollowRedirects(false);
            conn.setRequestProperty("User-Agent", UA);
            conn.setRequestProperty("Accept", "application/json, text/plain, */*");
            conn.setRequestProperty("Accept-Language", "zh-CN,zh;q=0.9");
            if (ts != null) conn.setRequestProperty("x-pan-tm", ts);
            if (sign != null) conn.setRequestProperty("x-pan-token", sign);
            conn.setRequestProperty("x-pan-client-id", CLIENT_ID);
            if (body != null) {
                conn.setDoOutput(true);
                conn.setRequestProperty("Content-Type", "application/json");
                byte[] raw = body.toString().getBytes("UTF-8");
                conn.setFixedLengthStreamingMode(raw.length);
                try (OutputStream os = conn.getOutputStream()) {
                    os.write(raw);
                }
            }
            r.http = conn.getResponseCode();
            InputStream in = r.http >= 400 ? conn.getErrorStream() : conn.getInputStream();
            if (in != null) r.body = readAll(in);
            if (!r.body.isEmpty() && r.body.trim().startsWith("{")) {
                r.json = new JSONObject(r.body.trim());
                r.status = r.json.optInt("status", 0);
                String info = r.json.optString("error_info", r.json.optString("message", ""));
                // token 端点把业务状态包在 data 里
                JSONObject data = r.json.optJSONObject("data");
                if (data != null && (r.status == 0 && r.json.has("code"))) {
                    r.errno = data.optInt("errno", 0);
                    String nested = data.optString("error_info", "");
                    r.info = nested.isEmpty() ? info : nested;
                    if (data.has("status")) r.status = data.optInt("status", r.status);
                } else {
                    r.errno = r.json.optInt("errno", 0);
                    r.info = info;
                }
            }
        } catch (Throwable t) {
            r.http = -1;
            r.info = t.getMessage() == null ? t.getClass().getSimpleName() : t.getMessage();
            Log.w(TAG, method + " " + url + " failed: " + r.info);
        } finally {
            if (conn != null) conn.disconnect();
        }
        return r;
    }

    private static String readAll(InputStream in) {
        try (InputStream stream = in) {
            ByteArrayOutputStream bos = new ByteArrayOutputStream();
            byte[] buf = new byte[16 * 1024];
            int n;
            while ((n = stream.read(buf)) >= 0) bos.write(buf, 0, n);
            return new String(bos.toByteArray(), "UTF-8");
        } catch (Throwable t) {
            return "";
        }
    }

    /**
     * 取值：{@code /oauth/*} 的字段在响应顶层，{@code /file}、token 端点包在 data 里，两种都认。
     * （这一层是踩过的坑：只读 data 会让二维码静默变空。）
     */
    static String field(JSONObject json, String key) {
        if (json == null) return "";
        String top = json.optString(key, "");
        if (!top.isEmpty()) return top;
        JSONObject data = json.optJSONObject("data");
        return data == null ? "" : data.optString(key, "");
    }

    // =====================================================================
    // 登录
    // =====================================================================

    public boolean loggedIn() {
        return "authorized".equals(state) && !accessToken.isEmpty();
    }

    public void startLogin() {
        stopPolling();
        state = "waiting";
        error = "";
        qrImage = "";
        nickname = "";
        notifyChanged();
        worker.execute(() -> {
            if (deviceId.isEmpty()) {
                deviceId = newDeviceId();
                persist();
            }
            String ts = String.valueOf(System.currentTimeMillis());
            String query = "auth_type=code&client_id=" + CLIENT_ID + "&scope=netdisk"
                    + "&qrcode=1&qr_width=460&qr_height=460&req_id=" + reqId(deviceId, ts)
                    + "&access_token=&" + commonQuery();
            Resp r = http("GET", API + "/oauth/authorize?" + query, null,
                    ts, sign("GET", "/oauth/authorize", ts, SIGN_KEY));
            String qr = field(r.json, "qr_data");
            String token = field(r.json, "query_token");
            if (r.http != 200 || qr.isEmpty() || token.isEmpty()) {
                Log.w(TAG, "authorize failed http=" + r.http + " body=" + r.body);
                state = "error";
                error = errorText(r.http, r.errno, r.info);
                if (error.isEmpty()) error = "取二维码失败";
                notifyChanged();
                return;
            }
            qrImage = qr;
            queryToken = token;
            qrAt = System.currentTimeMillis();
            state = "waiting";
            error = "";
            notifyChanged();
            startPolling();
        });
    }

    private synchronized void startPolling() {
        stopPolling();
        pollTask = scheduler().scheduleWithFixedDelay(this::pollOnce, POLL_MS, POLL_MS,
                TimeUnit.MILLISECONDS);
    }

    private void stopPolling() {
        ScheduledFuture<?> task = pollTask;
        pollTask = null;
        if (task != null) task.cancel(false);
    }

    private synchronized ScheduledExecutorService scheduler() {
        if (sched == null || sched.isShutdown()) {
            sched = Executors.newSingleThreadScheduledExecutor(r -> {
                Thread t = new Thread(r, "uni-quark-poll");
                t.setDaemon(true);
                return t;
            });
        }
        return sched;
    }

    /** 轮询一次：未确认就等，确认了就换 token，过期就停。 */
    private void pollOnce() {
        String token = queryToken;
        if (token.isEmpty() || (!"waiting".equals(state) && !"scanned".equals(state))) {
            stopPolling();
            return;
        }
        if (System.currentTimeMillis() - qrAt > QR_TTL_MS) {
            state = "expired";
            error = "二维码已过期，请刷新";
            stopPolling();
            notifyChanged();
            return;
        }
        String ts = String.valueOf(System.currentTimeMillis());
        String query = "client_id=" + CLIENT_ID + "&scope=netdisk&query_token=" + enc(token)
                + "&req_id=" + reqId(deviceId, ts) + "&access_token=&" + commonQuery();
        Resp r = http("GET", API + "/oauth/code?" + query, null,
                ts, sign("GET", "/oauth/code", ts, SIGN_KEY));
        String code = field(r.json, "code");
        String verdict = pollVerdict(r.http, r.errno, code, r.info);
        if ("code".equals(verdict)) {
            stopPolling();
            exchangeCode(code);
            return;
        }
        if ("expired".equals(verdict)) {
            state = "expired";
            error = "二维码已过期，请刷新";
            stopPolling();
            notifyChanged();
            return;
        }
        if ("error".equals(verdict)) {
            state = "error";
            error = errorText(r.http, r.errno, r.info);
            stopPolling();
            notifyChanged();
            return;
        }
        // wait：扫码确认前上游一直是 11003，这里只在状态真的变了时推一次
        if (!"waiting".equals(state) && !error.isEmpty()) {
            error = "";
            notifyChanged();
        }
    }

    /** code → access_token + refresh_token。 */
    private void exchangeCode(String code) {
        worker.execute(() -> {
            if (!tokenRequest("code", code)) return;
            state = "authorized";
            error = "";
            loginAt = System.currentTimeMillis();
            persist();
            notifyChanged();
            refreshProfile();
            list("0", 1);
        });
    }

    /**
     * 用 code 或 refresh_token 换 token。成功返回 true。
     * refresh_token 会轮转，所以每次都要落盘，否则下次续期就失效。
     */
    private boolean tokenRequest(String field, String value) {
        String ts = String.valueOf(System.currentTimeMillis());
        JSONObject body = new JSONObject();
        try {
            body.put("req_id", reqId(deviceId, ts))
                    .put("app_ver", APP_VER)
                    .put("device_id", deviceId)
                    .put("device_brand", DEVICE_BRAND)
                    .put("platform", PLATFORM)
                    .put("device_name", DEVICE_MODEL)
                    .put("device_model", DEVICE_MODEL)
                    .put("build_device", DEVICE_MODEL)
                    .put("build_product", DEVICE_MODEL)
                    .put("device_gpu", DEVICE_GPU)
                    .put("activity_rect", "{}")
                    .put("channel", CHANNEL)
                    .put(field, value);
        } catch (Exception e) {
            error = "构造请求失败";
            return false;
        }
        Resp r = http("POST", CODE_API, body, null, null);
        JSONObject data = r.data();
        String access = data == null ? "" : data.optString("access_token", "");
        String refresh = data == null ? "" : data.optString("refresh_token", "");
        if (r.http != 200 || access.isEmpty()) {
            error = errorText(r.http, r.errno, r.info);
            if (error.isEmpty()) error = "换取登录凭证失败";
            if (!"authorized".equals(state)) {
                state = "error";
                notifyChanged();
            }
            return false;
        }
        accessToken = access;
        if (!refresh.isEmpty()) refreshToken = refresh;
        return true;
    }

    /** 同步续期，供请求线程内部用。 */
    private boolean refreshSync() {
        if (refreshToken.isEmpty()) return false;
        synchronized (netLock) {
            if (!tokenRequest("refresh_token", refreshToken)) return false;
            persist();
            return true;
        }
    }

    public void logout() {
        stopPolling();
        accessToken = "";
        refreshToken = "";
        queryToken = "";
        qrImage = "";
        nickname = "";
        memberType = "";
        totalCapacity = 0;
        useCapacity = 0;
        entries = new JSONArray();
        synchronized (crumbs) {
            crumbs.clear();
        }
        pdir = "0";
        page = 1;
        total = 0;
        state = "idle";
        error = "";
        if (store.isFile()) store.delete();
        notifyChanged();
    }

    /** 冷启动：读盘恢复 deviceId 与 refresh_token，再静默续期一次。 */
    public void restore() {
        if (!store.isFile()) return;
        try {
            byte[] raw = new byte[(int) Math.min(Math.max(store.length(), 1), 1 << 16)];
            int off = 0;
            try (FileInputStream in = new FileInputStream(store)) {
                while (off < raw.length) {
                    int n = in.read(raw, off, raw.length - off);
                    if (n < 0) break;
                    off += n;
                }
            }
            if (off == 0) return;
            JSONObject saved = new JSONObject(new String(raw, 0, off, "UTF-8"));
            deviceId = saved.optString("deviceId", "");
            refreshToken = saved.optString("refreshToken", "");
            accessToken = saved.optString("accessToken", "");
            nickname = saved.optString("nickname", "");
            memberType = saved.optString("memberType", "");
            totalCapacity = saved.optLong("totalCapacity", 0);
            useCapacity = saved.optLong("useCapacity", 0);
            loginAt = saved.optLong("loginAt", 0);
            if (deviceId.isEmpty()) {
                deviceId = newDeviceId();
                persist();
                return;
            }
            if (refreshToken.isEmpty() && accessToken.isEmpty()) return;
            state = "authorized";
            notifyChanged();
        } catch (Throwable t) {
            Log.w(TAG, "restore session failed", t);
            return;
        }
        worker.execute(() -> {
            boolean ok = refreshToken.isEmpty() || refreshSync();
            if (ok) {
                state = "authorized";
                error = "";
                notifyChanged();
                refreshProfile();
            } else {
                state = "error";
                error = "夸克登录已失效，请重新扫码";
                notifyChanged();
            }
        });
    }

    /** 昵称/容量：TV 通道可能不给，拿不到就保持空，不影响用。 */
    private void refreshProfile() {
        worker.execute(() -> {
            Resp r = request("/user", "method=user_info", true);
            if (r.http == 200 && r.json != null) {
                String name = field(r.json, "nickname");
                if (name.isEmpty()) name = field(r.json, "nick_name");
                String type = field(r.json, "member_type");
                if (type.isEmpty()) type = field(r.json, "vip_type");
                long totalCap = r.json.optLong("total_capacity",
                        r.json.optLong("total_capacity_size", 0));
                long useCap = r.json.optLong("use_capacity",
                        r.json.optLong("use_capacity_size", 0));
                if (!name.isEmpty() || totalCap > 0) {
                    nickname = name;
                    memberType = type;
                    if (totalCap > 0) totalCapacity = totalCap;
                    if (useCap > 0) useCapacity = useCap;
                    persist();
                    notifyChanged();
                }
            }
        });
    }

    private void persist() {
        try {
            JSONObject out = new JSONObject()
                    .put("deviceId", deviceId)
                    .put("accessToken", accessToken)
                    .put("refreshToken", refreshToken)
                    .put("nickname", nickname)
                    .put("memberType", memberType)
                    .put("totalCapacity", totalCapacity)
                    .put("useCapacity", useCapacity)
                    .put("loginAt", loginAt);
            if (!dir.exists()) dir.mkdirs();
            try (FileOutputStream fos = new FileOutputStream(store)) {
                fos.write(out.toString().getBytes("UTF-8"));
            }
            store.setReadable(false, false);
            store.setReadable(true, true);
        } catch (Throwable t) {
            Log.w(TAG, "persist session failed", t);
        }
    }

    // =====================================================================
    // 目录
    // =====================================================================

    public void open(String fid, String name) {
        String target = fid == null || fid.isEmpty() ? "0" : fid.trim();
        synchronized (crumbs) {
            if ("..".equals(target)) {
                if (crumbs.size() > 1) crumbs.removeLast();
                String[] top = crumbs.peekLast();
                target = top == null ? "0" : top[0];
            } else if (!target.equals(pdir)) {
                if (crumbs.isEmpty()) crumbs.addLast(new String[] {"0", "根目录"});
                if ("0".equals(target)) {
                    while (crumbs.size() > 1) crumbs.removeLast();
                } else {
                    String label = name == null || name.isEmpty() ? "目录" : name;
                    crumbs.addLast(new String[] {target, label});
                }
            }
            if (crumbs.isEmpty()) crumbs.addLast(new String[] {"0", "根目录"});
        }
        pdir = target;
        list(target, 1);
    }

    public void more() {
        list(pdir, page + 1);
    }

    public void list(String fid, int pageNo) {
        final String target = fid == null || fid.isEmpty() ? "0" : fid;
        final int pageIndex = Math.max(1, pageNo);
        worker.execute(() -> {
            String query = "method=list&parent_fid=" + enc(target)
                    + "&order_by=3&desc=1&category=&source=&ex_source=&list_all=0"
                    + "&page_size=" + PAGE_SIZE + "&page_index=" + (pageIndex - 1);
            Resp r = request("/file", query, true);
            if (r.http != 200 || (r.errno != 0 && r.errno != 0) || r.status >= 400) {
                state = "authorized".equals(state) || "error".equals(state) ? state : "error";
                error = errorText(r.http, r.errno, r.info);
                if (error.isEmpty()) error = "列表获取失败";
                notifyChanged();
                return;
            }
            JSONObject data = r.data();
            JSONArray raw = data == null ? null : data.optJSONArray("files");
            JSONArray list = normalizeEntries(raw);
            int count = data == null ? 0 : data.optInt("total_count", list.length());
            if (pageIndex == 1) {
                entries = list;
                page = 1;
            } else {
                for (int i = 0; i < list.length(); i++) {
                    JSONObject item = list.optJSONObject(i);
                    if (item != null) entries.put(item);
                }
                page = pageIndex;
            }
            total = count > 0 ? count : entries.length();
            error = "";
            state = "authorized";
            notifyChanged();
        });
    }

    // =====================================================================
    // 下载：地址现取现用
    // =====================================================================

    public static final class Fetch {
        public final String url, cookie, referer, userAgent;

        Fetch(String url) {
            this.url = url;
            this.cookie = "";
            this.referer = "";
            this.userAgent = UA;
        }
    }

    /** {@code /file?method=download} 拿直链；签名会过期，所以下载前才取。 */
    public Fetch resolve(String fid) throws Exception {
        if (fid == null || fid.isEmpty()) throw new Exception("文件不存在");
        synchronized (netLock) {
            String query = "method=download&group_by=source&fid=" + enc(fid)
                    + "&resolution=low,normal,high,super,2k,4k&support=dolby_vision";
            Resp r = request("/file", query, true);
            if (r.http != 200 || r.errno != 0) {
                throw new Exception(errorText(r.http, r.errno, r.info));
            }
            JSONObject data = r.data();
            String url = data == null ? "" : data.optString("download_url", "");
            if (url.isEmpty()) throw new Exception("没有拿到下载地址");
            return new Fetch(url);
        }
    }

    /** 入队：按当前列表的 fid 找名字与大小，交给 {@link LanTransfer} 排队。 */
    public int enqueue(String fids, LanTransfer transfer) {
        if (!loggedIn() || transfer == null) return 0;
        int count = 0;
        JSONArray snapshot = entries;
        for (String part : (fids == null ? "" : fids).split(",")) {
            String fid = part.trim();
            if (fid.isEmpty()) continue;
            JSONObject hit = null;
            for (int i = 0; i < snapshot.length(); i++) {
                JSONObject item = snapshot.optJSONObject(i);
                if (item != null && fid.equals(item.optString("fid", ""))) {
                    hit = item;
                    break;
                }
            }
            if (hit == null || hit.optBoolean("dir", false)) continue;
            transfer.addQuarkLink(fid, hit.optString("name", ""), hit.optLong("size", 0));
            count++;
        }
        return count;
    }

    // =====================================================================
    // 状态
    // =====================================================================

    public JSONObject snapshot() {
        JSONObject out = new JSONObject();
        try {
            JSONArray crumbArr = new JSONArray();
            Deque<String[]> stack;
            synchronized (crumbs) {
                stack = new ArrayDeque<>(crumbs);
            }
            if (stack.isEmpty()) stack.addLast(new String[] {"0", "根目录"});
            for (String[] c : stack) {
                crumbArr.put(new JSONObject().put("fid", c[0]).put("name", c[1]));
            }
            boolean pending = "waiting".equals(state) || "scanned".equals(state)
                    || "expired".equals(state);
            long left = ("waiting".equals(state) || "scanned".equals(state))
                    ? Math.max(0, QR_TTL_MS - (System.currentTimeMillis() - qrAt)) / 1000 : 0;
            out.put("state", state)
                    .put("qrImage", pending ? qrImage : "")
                    .put("expiresIn", left)
                    .put("nickname", nickname)
                    .put("memberType", memberType)
                    .put("totalCapacity", totalCapacity)
                    .put("useCapacity", useCapacity)
                    .put("pdir", pdir)
                    .put("page", page)
                    .put("total", total)
                    .put("crumbs", crumbArr)
                    .put("entries", entries)
                    .put("error", error == null ? "" : error);
        } catch (Exception ignored) {}
        return out;
    }

    private void notifyChanged() {
        main.post(changed);
    }

    public void shutdown() {
        stopPolling();
        if (sched != null) sched.shutdownNow();
        worker.shutdownNow();
    }
}
