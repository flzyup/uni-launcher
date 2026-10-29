package xyz.i4o.uni.launcher.integration;

import android.content.Context;
import android.content.Intent;
import android.net.Uri;
import android.net.wifi.WifiManager;
import android.os.Handler;
import android.os.Looper;
import android.provider.Settings;
import android.util.Log;
import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.InputStream;
import java.io.OutputStream;
import java.net.Inet4Address;
import java.net.InetAddress;
import java.net.NetworkInterface;
import java.net.ServerSocket;
import java.net.Socket;
import java.net.SocketException;
import java.net.URLDecoder;
import java.util.ArrayList;
import java.util.Enumeration;
import java.util.List;
import java.util.Locale;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.atomic.AtomicBoolean;
import java.util.concurrent.atomic.AtomicInteger;
import org.json.JSONArray;
import org.json.JSONObject;

/** 局域网传文件：一个极简 HTTP 服务器，手机扫码后在浏览器里把 APK 上传到
 *  files/transfers/，再由 {@link #install} 走包安装器安装。服务器、网络接口枚举
 *  与文件写入全部在后台线程，回调 {@code onChanged} 投递回主线程。 */
public final class LanTransfer {
    private static final String TAG = "UniTransfer";
    private static final int PREFERRED_PORT = 8787;
    private static final long MAX_UPLOAD_BYTES = 2L * 1024 * 1024 * 1024;
    /** 手机端粘贴的下载链接长度上限；再长基本是粘错了。 */
    private static final int MAX_LINK_LENGTH = 2048;
    private static final int MAX_LINKS = 50;

    private final Context context;
    private final Runnable changed;
    private final Handler main = new Handler(Looper.getMainLooper());
    private final File dir;
    private final AtomicBoolean running = new AtomicBoolean();
    private final Object socketLock = new Object();
    private ServerSocket server;
    private Thread acceptThread;
    private volatile ExecutorService workers;
    private volatile String ip = "", url = "", mode = "none";
    private volatile int port = -1;
    private volatile JSONArray filesJson = new JSONArray();
    private final AtomicBoolean restarting = new AtomicBoolean();
    /** 手机在网页里填的下载地址先入队，车机上点「下载」才真正拉取：
     *  车机流量与磁盘都不该被手机随意驱动。列表持久化，重启后仍在。 */
    private static final class Link {
        final String id, url, host;
        final long time;
        volatile String name = "", status = "queued", error = "";
        volatile long size;
        volatile boolean cancelled;
        Link(String id, String url, String host, long time) {
            this.id = id;
            this.url = url;
            this.host = host;
            this.time = time;
        }
    }
    private final List<Link> links = new ArrayList<>();
    private final Object linkLock = new Object();
    private final AtomicInteger linkSeq = new AtomicInteger();
    private final File linkStore;
    private final ExecutorService downloader = Executors.newFixedThreadPool(2, r -> {
        Thread t = new Thread(r, "uni-transfer-download");
        t.setDaemon(true);
        return t;
    });

    public LanTransfer(Context context, Runnable changed) {
        this.context = context.getApplicationContext();
        this.changed = changed;
        dir = new File(this.context.getFilesDir(), "transfers");
        if (!dir.exists()) dir.mkdirs();
        linkStore = new File(this.context.getFilesDir(), "transfer-links.json");
        refreshFiles();
        loadLinks();
    }

    /** 启动服务器；返回状态对象，失败时 running=false。 */
    public JSONObject start() {
        if (running.get()) return snapshot();
        String[] resolved = resolveAddress();
        int chosen = bind(PREFERRED_PORT);
        if (chosen < 0) chosen = bind(0);
        if (chosen < 0) {
            ip = ""; url = ""; mode = "none"; port = -1;
            return snapshot();
        }
        port = chosen;
        ip = resolved[0];
        mode = resolved[1];
        url = ip.isEmpty() ? "" : "http://" + ip + ":" + port + "/";
        workers = Executors.newCachedThreadPool(r -> {
            Thread t = new Thread(r, "uni-transfer-worker");
            t.setDaemon(true);
            return t;
        });
        running.set(true);
        acceptThread = new Thread(this::acceptLoop, "uni-transfer-accept");
        acceptThread.setDaemon(true);
        acceptThread.start();
        notifyChanged();
        return snapshot();
    }

    public void stop() {
        running.set(false);
        synchronized (socketLock) {
            try { if (server != null) server.close(); } catch (Exception ignored) {}
            server = null;
        }
        if (workers != null) { workers.shutdownNow(); workers = null; }
        ip = ""; url = ""; port = -1;
        notifyChanged();
    }

    private int bind(int port) {
        try {
            // setReuseAddress 必须在 bind 之前，否则 stop→start 时 TIME_WAIT 端口会绑定失败。
            ServerSocket s = new ServerSocket();
            s.setReuseAddress(true);
            s.bind(new java.net.InetSocketAddress(InetAddress.getByName("0.0.0.0"), port), 50);
            synchronized (socketLock) { server = s; }
            Log.i(TAG, "listening on 0.0.0.0:" + s.getLocalPort());
            return s.getLocalPort();
        } catch (Exception e) { Log.w(TAG, "bind " + port + " failed: " + e); return -1; }
    }

    private boolean listening() {
        synchronized (socketLock) {
            ServerSocket s = server;
            return s != null && !s.isClosed();
        }
    }

    private void acceptLoop() {
        while (running.get()) {
            Socket socket;
            try {
                ServerSocket s;
                synchronized (socketLock) { s = server; }
                if (s == null) return;
                socket = s.accept();
            } catch (SocketException closed) {
                if (running.get()) Log.i(TAG, "accept loop closed while running");
                return;
            } catch (Exception e) {
                if (!running.get()) return;
                Log.w(TAG, "accept error, keep listening", e);
                continue;
            }
            ExecutorService w = workers;
            if (w == null || w.isShutdown()) { try { socket.close(); } catch (Exception ignored) {} return; }
            w.execute(() -> { try { handle(socket); } catch (Throwable ignored) {} });
        }
    }

    private void handle(Socket socket) {
        try {
            socket.setSoTimeout(60000);
            InputStream in = socket.getInputStream();
            OutputStream out = socket.getOutputStream();
            String requestLine = readLine(in);
            if (requestLine == null) return;
            String[] parts = requestLine.split(" ");
            String method = parts.length > 0 ? parts[0] : "";
            String rawPath = parts.length > 1 ? parts[1] : "/";
            // 路径与查询串必须分开：POST 目标是 /upload?name=...，路由只比路径本身。
            int queryIdx = rawPath.indexOf('?');
            String path = queryIdx >= 0 ? rawPath.substring(0, queryIdx) : rawPath;
            String query = queryIdx >= 0 ? rawPath.substring(queryIdx + 1) : "";
            Log.d(TAG, method + " " + rawPath);
            int contentLength = -1;
            String line;
            while ((line = readLine(in)) != null && !line.isEmpty()) {
                int idx = line.indexOf(':');
                if (idx > 0 && "content-length".equalsIgnoreCase(line.substring(0, idx).trim())) {
                    try { contentLength = Integer.parseInt(line.substring(idx + 1).trim()); } catch (NumberFormatException ignored) {}
                }
            }
            if ("GET".equalsIgnoreCase(method)) {
                if ("/".equals(path) || "/index.html".equals(path) || "/upload".equals(path)) {
                    byte[] body = page().getBytes("UTF-8");
                    writeHead(out, "200 OK", "text/html; charset=utf-8", body.length);
                    out.write(body);
                } else {
                    writeHead(out, "404 Not Found", "text/plain; charset=utf-8", 0);
                }
                out.flush();
                return;
            }
            if ("POST".equalsIgnoreCase(method) && "/upload".equals(path)) {
                if (contentLength <= 0 || contentLength > MAX_UPLOAD_BYTES) {
                    writeHead(out, "400 Bad Request", "text/plain; charset=utf-8", 0);
                    out.flush();
                    return;
                }
                String name = queryParam(query, "name");
                name = sanitize(name);
                File target = unique(new File(dir, name));
                int total = 0;
                byte[] buf = new byte[64 * 1024];
                try (FileOutputStream fos = new FileOutputStream(target)) {
                    while (total < contentLength) {
                        int n = in.read(buf, 0, Math.min(buf.length, contentLength - total));
                        if (n < 0) break;
                        fos.write(buf, 0, n);
                        total += n;
                    }
                }
                if (total != contentLength) { target.delete(); writeHead(out, "400 Bad Request", "text/plain; charset=utf-8", 0); out.flush(); return; }
                Log.i(TAG, "received " + target.getName() + " (" + total + " bytes)");
                refreshFiles();
                notifyChanged();
                writeHead(out, "200 OK", "text/plain; charset=utf-8", 2);
                out.write("OK".getBytes("UTF-8"));
                out.flush();
                return;
            }
            if ("POST".equalsIgnoreCase(method) && "/link".equals(path)) {
                // 手机端只提交地址；真正的下载由车机上的点击触发。
                String url = queryParam(query, "url");
                if ((url == null || url.isEmpty()) && contentLength > 0 && contentLength <= 8192) {
                    byte[] body = new byte[contentLength];
                    int off = 0;
                    while (off < contentLength) {
                        int n = in.read(body, off, contentLength - off);
                        if (n < 0) break;
                        off += n;
                    }
                    String text = new String(body, 0, off, "UTF-8").trim();
                    url = queryParam(text, "url");
                    if (url == null) url = text; // 也接受裸 URL
                }
                String id = addLink(url);
                byte[] reply = (id == null ? "BAD" : "OK " + id).getBytes("UTF-8");
                writeHead(out, id == null ? "400 Bad Request" : "200 OK", "text/plain; charset=utf-8", reply.length);
                out.write(reply);
                out.flush();
                return;
            }
            writeHead(out, "405 Method Not Allowed", "text/plain; charset=utf-8", 0);
            out.flush();
        } catch (Throwable ignored) {
        } finally {
            try { socket.close(); } catch (Exception ignored) {}
        }
    }

    private void writeHead(OutputStream out, String status, String contentType, int length) throws Exception {
        out.write(("HTTP/1.1 " + status + "\r\nContent-Type: " + contentType
                + "\r\nContent-Length: " + length + "\r\nCache-Control: no-store\r\nConnection: close\r\n\r\n").getBytes("UTF-8"));
    }

    private static String readLine(InputStream in) throws Exception {
        StringBuilder sb = new StringBuilder();
        int c;
        while ((c = in.read()) >= 0) {
            if (c == '\n') break;
            if (c != '\r') sb.append((char) c);
        }
        return c < 0 && sb.length() == 0 ? null : sb.toString();
    }

    private static String queryParam(String query, String key) {
        if (query == null || query.isEmpty()) return null;
        for (String pair : query.split("&")) {
            int eq = pair.indexOf('=');
            if (eq > 0 && key.equals(pair.substring(0, eq))) {
                try { return URLDecoder.decode(pair.substring(eq + 1), "UTF-8"); }
                catch (Exception ignored) { return pair.substring(eq + 1); }
            }
        }
        return null;
    }

    private static String sanitize(String raw) {
        if (raw == null) raw = "";
        raw = raw.replace('\\', '/');
        int slash = raw.lastIndexOf('/');
        if (slash >= 0) raw = raw.substring(slash + 1);
        raw = raw.replaceAll("[\\r\\n\\t\\x00-\\x1f]", "").trim();
        if (raw.isEmpty() || ".".equals(raw) || "..".equals(raw)) raw = "upload.apk";
        // QQ 等下载器会把 APK 存成 xxx.apk.1，落盘前摘掉这层后缀，车机才能直接安装。
        raw = raw.replaceFirst("(?i)(\\.apk)\\.\\d{1,2}$", "$1");
        if (raw.length() > 200) raw = raw.substring(raw.length() - 200);
        return raw;
    }

    private static File unique(File f) {
        if (!f.exists()) return f;
        String name = f.getName();
        int dot = name.lastIndexOf('.');
        String base = dot > 0 ? name.substring(0, dot) : name;
        String ext = dot > 0 ? name.substring(dot) : "";
        for (int i = 1; i < 10000; i++) {
            File candidate = new File(f.getParentFile(), base + "-" + i + ext);
            if (!candidate.exists()) return candidate;
        }
        return new File(f.getParentFile(), base + "-" + System.currentTimeMillis() + ext);
    }

    public JSONObject snapshot() {
        // 自愈：界面还显示“运行中”但监听 socket 已消失（进程活着、服务器线程却
        // 意外退出）时，在后台重建一次，避免手机端看到二维码却 ERR_CONNECTION_REFUSED。
        if (running.get() && !listening() && restarting.compareAndSet(false, true)) {
            new Thread(() -> {
                try { recover(); } catch (Throwable t) { Log.w(TAG, "recover failed", t); }
                finally { restarting.set(false); }
            }, "uni-transfer-recover").start();
        }
        JSONObject j = new JSONObject();
        try {
            j.put("running", running.get()).put("ip", ip).put("port", port)
             .put("url", url).put("mode", mode).put("files", filesJson)
             .put("links", linksJson());
        } catch (Exception ignored) {}
        return j;
    }

    /** 后台重建监听：保留原 IP 与“开启”意图，重新绑定端口并重启 accept 线程。 */
    private void recover() {
        if (!running.get()) return;
        synchronized (socketLock) {
            try { if (server != null) server.close(); } catch (Exception ignored) {}
            server = null;
        }
        if (workers != null) { workers.shutdownNow(); workers = null; }
        if (!running.get()) return; // 重建期间用户已手动关闭，尊重关闭意图
        String savedIp = ip, savedMode = mode;
        int chosen = bind(PREFERRED_PORT);
        if (chosen < 0) chosen = bind(0);
        if (chosen < 0) { running.set(false); ip = ""; url = ""; port = -1; notifyChanged(); return; }
        port = chosen;
        ip = savedIp;
        mode = savedMode;
        url = ip.isEmpty() ? "" : "http://" + ip + ":" + port + "/";
        workers = Executors.newCachedThreadPool(r -> {
            Thread t = new Thread(r, "uni-transfer-worker");
            t.setDaemon(true);
            return t;
        });
        running.set(true);
        acceptThread = new Thread(this::acceptLoop, "uni-transfer-accept");
        acceptThread.setDaemon(true);
        acceptThread.start();
        notifyChanged();
    }

    /** 把手机填的地址入队。只收 http/https，同址未完成的只留一条；非法返回 null。 */
    public String addLink(String raw) {
        if (raw == null) return null;
        String url = raw.trim();
        if (url.isEmpty() || url.length() > MAX_LINK_LENGTH) return null;
        java.net.URL parsed;
        try { parsed = new java.net.URL(url); } catch (Exception e) { return null; }
        String scheme = parsed.getProtocol() == null ? "" : parsed.getProtocol().toLowerCase(Locale.ROOT);
        if (!"http".equals(scheme) && !"https".equals(scheme)) return null;
        String host = parsed.getHost();
        if (host == null || host.isEmpty()) return null;
        Link created;
        synchronized (linkLock) {
            for (Link existing : links) {
                if (existing.url.equals(url) && !"done".equals(existing.status)) return existing.id;
            }
            if (links.size() >= MAX_LINKS) {
                for (int i = links.size() - 1; i >= 0; i--) {
                    if ("done".equals(links.get(i).status)) { links.remove(i); break; }
                }
            }
            created = new Link(newId(), url, host, System.currentTimeMillis());
            created.name = sanitize(filenameOf(url));
            links.add(created);
            Log.i(TAG, "queued link " + url);
        }
        persistAsync();
        notifyChanged();
        return created.id;
    }

    /** 车机上点「下载」时才真正拉取文件，落到与上传同一个目录。 */
    public boolean downloadLink(String id) {
        Link link = find(id);
        if (link == null) return false;
        if ("downloading".equals(link.status)) return true;
        link.cancelled = false;
        link.error = "";
        link.status = "downloading";
        persistAsync();
        notifyChanged();
        try { downloader.execute(() -> runDownload(link)); } catch (Throwable t) {
            link.status = "failed";
            link.error = String.valueOf(t);
            notifyChanged();
            return false;
        }
        return true;
    }

    public boolean removeLink(String id) {
        Link link = find(id);
        if (link == null) return false;
        link.cancelled = true;
        synchronized (linkLock) { links.remove(link); }
        persistAsync();
        notifyChanged();
        return true;
    }

    private Link find(String id) {
        if (id == null) return null;
        synchronized (linkLock) {
            for (Link l : links) if (l.id.equals(id)) return l;
        }
        return null;
    }

    private void runDownload(Link link) {
        File part = null;
        try {
            java.net.HttpURLConnection conn = (java.net.HttpURLConnection) new java.net.URL(link.url).openConnection();
            conn.setInstanceFollowRedirects(true);
            conn.setConnectTimeout(15000);
            conn.setReadTimeout(20000);
            conn.setRequestProperty("User-Agent", "UNI-Launcher/1.0 (uni-transfer)");
            int code = conn.getResponseCode();
            if (code < 200 || code >= 300) throw new java.io.IOException("HTTP " + code);
            if (conn.getContentLengthLong() > MAX_UPLOAD_BYTES) throw new java.io.IOException("文件超过 2GB");
            File target = unique(new File(dir, sanitize(filenameFrom(conn, link.url, link.name))));
            part = new File(dir, target.getName() + ".part");
            long total = 0;
            byte[] buf = new byte[64 * 1024];
            try (InputStream in = conn.getInputStream(); FileOutputStream fos = new FileOutputStream(part)) {
                int n;
                while ((n = in.read(buf)) >= 0) {
                    if (link.cancelled) throw new java.io.IOException("cancelled");
                    total += n;
                    if (total > MAX_UPLOAD_BYTES) throw new java.io.IOException("文件超过 2GB");
                    fos.write(buf, 0, n);
                }
            }
            if (part.length() == 0) throw new java.io.IOException("空文件");
            if (!part.renameTo(target)) throw new java.io.IOException("写入失败");
            part = null;
            link.name = target.getName();
            link.size = total;
            link.error = "";
            link.status = "done";
            Log.i(TAG, "downloaded " + target.getName() + " (" + total + " bytes)");
            refreshFiles();
        } catch (Throwable t) {
            if (part != null) part.delete();
            link.status = link.cancelled ? "queued" : "failed";
            link.error = link.cancelled ? "" : String.valueOf(t.getMessage() == null ? t.getClass().getSimpleName() : t.getMessage());
            if (!link.cancelled) Log.w(TAG, "download failed: " + link.url, t);
        } finally {
            persistAsync();
            notifyChanged();
        }
    }

    private String newId() {
        return Long.toHexString(System.currentTimeMillis()) + Integer.toHexString(linkSeq.incrementAndGet());
    }

    /** 仅从 URL 猜文件名（入队时给界面用），真正落盘时以响应头为准。 */
    private static String filenameOf(String url) {
        String path = "";
        try { path = new java.net.URL(url).getPath(); } catch (Exception ignored) {}
        if (path == null) path = "";
        String name = path.substring(path.lastIndexOf('/') + 1);
        try { name = URLDecoder.decode(name, "UTF-8"); } catch (Exception ignored) {}
        name = name.trim();
        return name.isEmpty() ? "download.bin" : name;
    }

    private static String filenameFrom(java.net.HttpURLConnection conn, String url, String hint) {
        try {
            String disp = conn == null ? null : conn.getHeaderField("Content-Disposition");
            if (disp != null && !disp.isEmpty()) {
                String lower = disp.toLowerCase(Locale.ROOT);
                int star = lower.indexOf("filename*=");
                if (star >= 0) {
                    String v = disp.substring(star + 10).trim();
                    int semi = v.indexOf(';');
                    if (semi >= 0) v = v.substring(0, semi);
                    v = v.replace("\"", "").trim();
                    int enc = v.indexOf("''");
                    if (enc >= 0) v = v.substring(enc + 2);
                    try { v = URLDecoder.decode(v, "UTF-8"); } catch (Exception ignored) {}
                    if (!v.isEmpty()) return v;
                }
                int plain = lower.indexOf("filename=");
                if (plain >= 0) {
                    String v = disp.substring(plain + 9).trim();
                    int semi = v.indexOf(';');
                    if (semi >= 0) v = v.substring(0, semi);
                    v = v.replace("\"", "").trim();
                    if (!v.isEmpty()) return v;
                }
            }
        } catch (Throwable ignored) {}
        String fromUrl = filenameOf(url == null ? "" : url);
        if (!"download.bin".equals(fromUrl)) return fromUrl;
        return hint == null || hint.isEmpty() ? fromUrl : hint;
    }

    private JSONArray linksJson() {
        JSONArray arr = new JSONArray();
        synchronized (linkLock) {
            for (Link l : links) {
                try {
                    arr.put(new JSONObject().put("id", l.id).put("url", l.url).put("host", l.host)
                            .put("name", l.name == null ? "" : l.name).put("status", l.status)
                            .put("size", l.size).put("time", l.time)
                            .put("error", l.error == null ? "" : l.error));
                } catch (Exception ignored) {}
            }
        }
        return arr;
    }

    private void persistAsync() {
        try { downloader.execute(this::persistLinks); } catch (Throwable ignored) {}
    }

    private void persistLinks() {
        JSONArray arr = new JSONArray();
        synchronized (linkLock) {
            for (Link l : links) {
                try {
                    arr.put(new JSONObject().put("id", l.id).put("url", l.url).put("host", l.host)
                            .put("name", l.name == null ? "" : l.name)
                            // 进程被杀时正在下载的任务回到队列，屏幕上仍是「待下载」。
                            .put("status", "downloading".equals(l.status) ? "queued" : l.status)
                            .put("size", l.size).put("time", l.time));
                } catch (Exception ignored) {}
            }
        }
        try (FileOutputStream fos = new FileOutputStream(linkStore)) {
            fos.write(arr.toString().getBytes("UTF-8"));
        } catch (Exception e) { Log.w(TAG, "persist links failed", e); }
    }

    private void loadLinks() {
        if (!linkStore.isFile()) return;
        try {
            byte[] raw = readAll(linkStore);
            JSONArray arr = new JSONArray(new String(raw, "UTF-8"));
            long now = System.currentTimeMillis();
            synchronized (linkLock) {
                links.clear();
                for (int i = 0; i < arr.length() && i < MAX_LINKS; i++) {
                    JSONObject o = arr.optJSONObject(i);
                    if (o == null) continue;
                    String url = o.optString("url", "");
                    if (url.isEmpty()) continue;
                    Link l = new Link(o.optString("id", newId()), url, o.optString("host", ""), o.optLong("time", now));
                    l.name = o.optString("name", "");
                    l.size = o.optLong("size", 0);
                    l.status = "done".equals(o.optString("status", "queued")) ? "done" : "queued";
                    links.add(l);
                }
            }
        } catch (Exception e) { Log.w(TAG, "load links failed", e); }
    }

    private static byte[] readAll(File f) throws Exception {
        byte[] buf = new byte[(int) Math.min(f.length(), 1 << 20)];
        try (FileInputStream in = new FileInputStream(f)) {
            int off = 0;
            while (off < buf.length) {
                int n = in.read(buf, off, buf.length - off);
                if (n < 0) break;
                off += n;
            }
            return off == buf.length ? buf : java.util.Arrays.copyOf(buf, off);
        }
    }

    public boolean install(String name) {
        File f = file(name);
        if (f == null) return false;
        try {
            if (!context.getPackageManager().canRequestPackageInstalls()) {
                Intent settings = new Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                        Uri.parse("package:" + context.getPackageName()));
                settings.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
                context.startActivity(settings);
                return true;
            }
            Uri uri = Uri.parse("content://" + TransferFileProvider.AUTHORITY + "/" + Uri.encode(f.getName()));
            Intent intent = new Intent(Intent.ACTION_INSTALL_PACKAGE);
            intent.setData(uri);
            intent.putExtra(Intent.EXTRA_NOT_UNKNOWN_SOURCE, true);
            intent.putExtra(Intent.EXTRA_INSTALLER_PACKAGE_NAME, context.getPackageName());
            intent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION | Intent.FLAG_ACTIVITY_NEW_TASK);
            context.startActivity(intent);
            return true;
        } catch (Exception e) {
            return false;
        }
    }

    public boolean delete(String name) {
        File f = file(name);
        if (f == null) return false;
        boolean ok = f.delete();
        refreshFiles();
        notifyChanged();
        return ok;
    }

    private File file(String name) {
        if (name == null) return null;
        File f = new File(dir, sanitize(name));
        return f.isFile() ? f : null;
    }

    private void refreshFiles() {
        File[] all = dir.listFiles();
        List<File> list = new ArrayList<>();
        if (all != null) for (File f : all) if (f.isFile()) list.add(f);
        list.sort((a, b) -> Long.compare(b.lastModified(), a.lastModified()));
        JSONArray arr = new JSONArray();
        try {
            for (int i = 0; i < list.size() && i < 200; i++) {
                File f = list.get(i);
                arr.put(new JSONObject().put("name", f.getName())
                        .put("size", f.length())
                        .put("time", f.lastModified()));
            }
        } catch (Exception ignored) {}
        filesJson = arr;
    }

    private void notifyChanged() { main.post(changed); }

    /** 返回 {ip, mode}；优先热点网关地址，其次 WiFi 网卡地址。 */
    private String[] resolveAddress() {
        try {
            List<String[]> ifs = interfaces();
            if (tetheringActive()) {
                String gw = hotspotGateway(ifs);
                if (gw != null) return new String[]{gw, "hotspot"};
            }
            String wifi = wifiIp(ifs);
            if (wifi != null) return new String[]{wifi, "wifi"};
            if (!ifs.isEmpty()) return new String[]{ifs.get(0)[1], "other"};
        } catch (Throwable ignored) {}
        return new String[]{"", "none"};
    }

    private List<String[]> interfaces() throws Exception {
        List<String[]> out = new ArrayList<>();
        Enumeration<NetworkInterface> e = NetworkInterface.getNetworkInterfaces();
        while (e != null && e.hasMoreElements()) {
            NetworkInterface ni = e.nextElement();
            try { if (!ni.isUp() || ni.isLoopback()) continue; } catch (Throwable ignored) { continue; }
            Enumeration<InetAddress> addrs = ni.getInetAddresses();
            while (addrs.hasMoreElements()) {
                InetAddress ia = addrs.nextElement();
                if (ia instanceof Inet4Address && !ia.isLoopbackAddress() && !ia.isLinkLocalAddress()) {
                    out.add(new String[]{ni.getName(), ia.getHostAddress()});
                }
            }
        }
        return out;
    }

    private boolean tetheringActive() {
        try {
            WifiManager wm = (WifiManager) context.getSystemService(Context.WIFI_SERVICE);
            java.lang.reflect.Method m = wm.getClass().getMethod("getWifiApState");
            return ((Integer) m.invoke(wm)) == 13; // WIFI_AP_STATE_ENABLED
        } catch (Throwable ignored) {
            try {
                List<String[]> ifs = interfaces();
                for (String[] it : ifs) if (it[1].startsWith("192.168.43.")) return true;
            } catch (Throwable ignored2) {}
            return false;
        }
    }

    private String hotspotGateway(List<String[]> ifs) {
        String fallback = null;
        for (String[] it : ifs) {
            String ip = it[1];
            if ("192.168.43.1".equals(ip)) return ip;
            if (ip.endsWith(".1") && fallback == null) fallback = ip;
        }
        for (String[] it : ifs) if (it[1].startsWith("192.168.43.")) return it[1];
        return fallback;
    }

    private String wifiIp(List<String[]> ifs) {
        String fallback = null;
        for (String[] it : ifs) {
            String name = it[0].toLowerCase(Locale.ROOT), ip = it[1];
            if (name.startsWith("wlan")) return ip;
            if (isPrivate(ip) && fallback == null) fallback = ip;
        }
        return fallback;
    }

    private static boolean isPrivate(String ip) {
        return ip.startsWith("10.") || ip.startsWith("192.168.") || ip.startsWith("172.");
    }

    private static String page() {
        return "<!doctype html><html lang=\"zh\"><head><meta charset=\"utf-8\">"
            + "<meta name=\"viewport\" content=\"width=device-width,initial-scale=1,maximum-scale=1\">"
            + "<title>向车机传文件</title><style>"
            + "*{box-sizing:border-box}body{margin:0;font-family:-apple-system,'PingFang SC','Microsoft YaHei',sans-serif;"
            + "background:#0d1117;color:#e6edf3;display:flex;align-items:center;justify-content:center;min-height:100vh;padding:20px}"
            + ".card{width:100%;max-width:420px;background:#161b22;border:1px solid #30363d;border-radius:16px;padding:28px 22px;text-align:center}"
            + "h1{font-size:20px;margin:0 0 6px}p{color:#8b949e;font-size:13px;margin:0 0 22px}"
            + "label{display:block;padding:14px;border:1px dashed #30363d;border-radius:12px;font-size:14px;color:#79c0ff;"
            + "word-break:break-all;margin-bottom:16px;cursor:pointer}"
            + "button{width:100%;padding:14px;border:0;border-radius:12px;background:#238636;color:#fff;font-size:16px;cursor:pointer}"
            + "button:active{opacity:.85}#s{margin-top:16px;font-size:13px;color:#8b949e;min-height:18px}"
            + "#f{display:none}"
            + ".sep{height:1px;background:#30363d;margin:26px 0 22px}"
            + "h2{font-size:16px;margin:0 0 6px}"
            + "#u{width:100%;padding:13px 14px;border-radius:12px;border:1px solid #30363d;background:#0d1117;color:#e6edf3;"
            + "font-size:14px;margin-bottom:14px}#u::placeholder{color:#6e7681}"
            + "#dl{background:#1f6feb}#s2{margin-top:14px;font-size:13px;color:#8b949e;min-height:18px}"
            + "</style></head><body><div class=\"card\">"
            + "<h1>向车机传文件</h1><p>选择 APK，点击上传，车机端可选择安装</p>"
            + "<label for=\"f\" id=\"pick\">点击选择 APK 文件（QQ 下载的 .apk.1 也可以）</label>"
            + "<input type=\"file\" id=\"f\" accept=\".apk,.apk.1,application/vnd.android.package-archive,application/octet-stream\">"
            + "<button id=\"go\" disabled>上传</button><div id=\"s\"></div>"
            + "<div class=\"sep\"></div>"
            + "<h2>让车机下载链接</h2><p>粘贴文件地址，车机会收到一条待下载任务，点一下才开始下载</p>"
            + "<input id=\"u\" type=\"url\" inputmode=\"url\" autocomplete=\"off\" "
            + "placeholder=\"https://example.com/app.apk\">"
            + "<button id=\"dl\">发送到车机</button><div id=\"s2\"></div></div><script>"
            + "var f=document.getElementById('f'),go=document.getElementById('go'),s=document.getElementById('s'),p=document.getElementById('pick');"
            + "f.onchange=function(){if(f.files.length){p.textContent=f.files[0].name;go.disabled=false;}};"
            + "go.onclick=function(){var file=f.files[0];if(!file)return;go.disabled=true;s.textContent='上传中…';"
            + "var x=new XMLHttpRequest();x.open('POST','/upload?name='+encodeURIComponent(file.name));"
            + "x.upload.onprogress=function(e){if(e.lengthComputable)s.textContent='上传 '+Math.round(e.loaded/e.total*100)+'%';};"
            + "x.onload=function(){if(x.status===200){"
            + "s.textContent=/\\.apk\\.\\d{1,2}$/i.test(file.name)?'完成 ✓ 已按 .apk 保存，可在车机安装':'完成 ✓ 可在车机选择安装';}"
            + "else{s.textContent='失败 ('+x.status+')';go.disabled=false;}};"
            + "x.onerror=function(){s.textContent='网络错误，请重试';go.disabled=false;};x.send(file);};"
            + "var u=document.getElementById('u'),dl=document.getElementById('dl'),s2=document.getElementById('s2');"
            + "dl.onclick=function(){var v=u.value.trim();"
            + "if(!/^https?:\\/\\//i.test(v)){s2.textContent='请填写 http:// 或 https:// 开头的地址';return;}"
            + "dl.disabled=true;s2.textContent='发送中…';"
            + "var x=new XMLHttpRequest();x.open('POST','/link?url='+encodeURIComponent(v));"
            + "x.onload=function(){if(x.status===200){s2.textContent='已发送 ✓ 请在车机上点「下载」';u.value='';}"
            + "else{s2.textContent='地址无效或发送失败 ('+x.status+')';}dl.disabled=false;};"
            + "x.onerror=function(){s2.textContent='网络错误，请重试';dl.disabled=false;};x.send();};"
            + "</script></body></html>";
    }
}

