package xyz.i4o.uni.launcher.core;

import android.content.Context;
import android.media.Rating;
import android.media.session.MediaController;
import android.os.Bundle;
import java.lang.reflect.Method;
import xyz.i4o.uni.launcher.log.LogTags;
import xyz.i4o.uni.launcher.log.UniLog;

/**
 * <b>标准 MediaSession 通道</b>（移植自 CarDesk 的同名实现）。
 *
 * <h3>标准入口是什么</h3>
 *
 * Android 官方定义的两个标准入口：
 *
 * <table>
 *   <tr><th>动作</th><th>标准入口</th><th>谁来接</th></tr>
 *   <tr><td>收藏</td><td>{@code TransportControls.setRating(心形评分)} → {@code onSetRating}</td><td>播放器的会话回调</td></tr>
 *   <tr><td>播放模式</td><td>{@code TransportControls.sendCustomAction(动作名, 参数)} → {@code onCustomAction}</td><td>播放器的会话回调</td></tr>
 * </table>
 *
 * 任何播放器只要实现了这两个回调，<b>第三方就能驱动它</b>，
 * 不需要桌面为每家单独逆向一套私有协议。
 *
 * <h3>为什么主路走公开 API，反射只作兜底</h3>
 *
 * {@code MediaController.TransportControls.sendCustomAction} 与
 * {@code MediaController.TransportControls.setRating} 都是 <b>API 21 起就有的公开方法</b>
 * （设备实测 API 28 的 framework 里确实有）→ 直接用，不需要任何反射。
 *
 * <p>CarDesk 那版把 {@code ISessionController} 的<b>隐藏代理</b>当主路，
 * 靠反射拿 {@code MediaSession.Token.mBinder} —— 但<b>那个字段在 API 24/28 的
 * {@code MediaSession.Token} 上根本不存在</b>（它只有一个 {@code CREATOR}），
 * 所以隐藏代理这条路在 API 28 上是<b>走不通的</b>。
 *
 * <p>→ 这里改成：<b>公开 API 为主路</b>，反射代理只作最后兜底（个别 ROM 把公开方法改坏了时）。
 *
 * <h3>兜底的反射路径</h3>
 *
 * {@code ISessionController} 的方法签名<b>随 Android 版本变化</b>：
 *
 * <pre>
 * void sendCustomAction(String callingPackage, ISessionControllerCallback callback,
 *                        String action, Bundle extras);
 * void rate(String callingPackage, ISessionControllerCallback callback, Rating rating);
 * </pre>
 *
 * 前面多了一个「<b>调用方包名</b>」—— framework 拿它做<b>权限检查</b>，传错会被服务端拒。
 * 而 AOSP 9 的标准签名是 {@code sendCustomAction(String action, Bundle extras)}（没有前两个）。
 *
 * → 所以调用参数<b>按参数类型定位</b>业务参数的位置，
 * 其余：第一个 {@code String} 填真实的调用方包名，别的填 null。
 *
 * <h3>评分入口的名字随版本变</h3>
 *
 * 有的版本叫 {@code rate(...)}，有的叫 {@code setRating(...)} → 两个都找。
 */
public final class SessionProxy {
    /** framework 内部会话控制接口的全名。 */
    private static final String ISESSION_CONTROLLER = "android.media.session.ISessionController";

    /** 评分入口的候选方法名（不同版本叫法不一样）。 */
    private static final String[] RATING_METHOD_NAMES = {"rate", "setRating"};

    private SessionProxy() {}

    /**
     * 拿会话控制代理。
     *
     * <p>设备实测（API 28）里 {@code MediaController} 上<b>没有</b> {@code mImpl} 字段，
     * {@code MediaSession.Token} 上<b>没有</b> {@code getMediaController()} ——
     * 真正握着代理的是 {@code Token} 里的一个 {@code ISessionController} 字段
     * （运行时类型是 {@code ISessionController$Stub$Proxy}，已经是现成的代理对象）。
     *
     * <p><b>字段名各 ROM 不一样</b>（{@code mBinder} / {@code mController} 都出现过），
     * 所以先按已知名字找，找不到就<b>遍历所有字段</b>，认「值的类型实现了
     * {@code ISessionController}」这一个特征 —— 不依赖字段名。
     *
     * @return 代理对象；拿不到返回 null
     */
    public static Object of(MediaController controller) {
        if (controller == null) return null;
        // ① 按已知字段名找（最快）：Token 上的字段。
        for (String name : PROXY_FIELDS) {
            Object found = readField(controller.getSessionToken(), name);
            if (isSessionController(found)) return found;
        }
        // ② Token 里遍历所有字段（字段名各 ROM 不一样）。
        Object found = scanForProxy(controller.getSessionToken());
        if (found != null) return found;
        // ③ MediaController 自己身上（部分 ROM 是 mSessionBinder）。
        for (String name : PROXY_FIELDS) {
            Object value = readField(controller, name);
            if (isSessionController(value)) return value;
        }
        return scanForProxy(controller);
    }

    /** 已知的候选字段名（按可能性排序）。 */
    private static final String[] PROXY_FIELDS = {
        "mBinder", "mController", "mSessionBinder", "mImpl", "mSessionController"};

    /**
     * 这个值是不是会话控制代理。
     *
     * <p>认的是<b>类型</b>：实现了 {@code android.media.session.ISessionController}
     * 的对象 —— 不认字段名，也不认具体实现类。
     */
    private static boolean isSessionController(Object value) {
        if (value == null) return false;
        for (Class<?> type = value.getClass(); type != null; type = type.getSuperclass()) {
            if (ISESSION_CONTROLLER.equals(type.getName())) return true;
            for (Class<?> face : type.getInterfaces()) {
                if (ISESSION_CONTROLLER.equals(face.getName())) return true;
            }
        }
        return false;
    }

    /** 读一个字段（含父类），读不到返回 null。 */
    private static Object readField(Object target, String name) {
        if (target == null) return null;
        for (Class<?> type = target.getClass(); type != null; type = type.getSuperclass()) {
            try {
                java.lang.reflect.Field field = type.getDeclaredField(name);
                field.setAccessible(true);
                return field.get(target);
            } catch (Throwable ignored) {
                // Not this class: keep walking up the hierarchy.
            }
        }
        return null;
    }

    /**
     * 遍历对象（含父类）的所有字段，找出会话控制代理。
     *
     * <p>这是「字段名随 ROM 变」的兜底：只认类型特征。
     */
    private static Object scanForProxy(Object target) {
        if (target == null) return null;
        for (Class<?> type = target.getClass(); type != null; type = type.getSuperclass()) {
            for (java.lang.reflect.Field field : type.getDeclaredFields()) {
                if (java.lang.reflect.Modifier.isStatic(field.getModifiers())) continue;
                try {
                    field.setAccessible(true);
                    Object value = field.get(target);
                    if (isSessionController(value)) return value;
                } catch (Throwable ignored) {
                    // Inaccessible field: skip it and keep looking.
                }
            }
        }
        return null;
    }

    /**
     * 拿不到代理时，把候选字段名记下来（排障用）。
     *
     * @param controller 当前会话控制器
     * @return 字段名清单
     */
    public static String describeProxySearch(MediaController controller) {
        StringBuilder names = new StringBuilder();
        if (controller == null) return "no-controller";
        for (Class<?> type = controller.getSessionToken().getClass(); type != null; type = type.getSuperclass()) {
            for (java.lang.reflect.Field field : type.getDeclaredFields()) {
                if (names.length() > 0) names.append(',');
                names.append(field.getName()).append(':').append(field.getType().getSimpleName());
            }
        }
        return names.toString();
    }

    /**
     * 在代理上找同名方法，<b>优先参数少的那个</b>。
     *
     * <p>接口上声明的签名（AOSP 9 那种 2 参）比代理类上的（AIDL 加了隐藏参数）更稳。
     */
    static Method find(Object proxy, String name) {
        Method best = null;
        for (Method method : candidates(proxy, name)) {
            if (best == null || method.getParameterTypes().length < best.getParameterTypes().length) {
                best = method;
            }
        }
        return best;
    }

    private static Method[] candidates(Object proxy, String name) {
        int size = 0;
        Method[] fromInterface = new Method[0];
        try {
            fromInterface = Class.forName(ISESSION_CONTROLLER).getMethods();
        } catch (Throwable ignored) {
            // The interface is hidden; the proxy class still exposes the methods.
        }
        Method[] fromProxy = proxy.getClass().getMethods();
        for (Method method : fromInterface) {
            if (method.getName().equals(name)) size++;
        }
        for (Method method : fromProxy) {
            if (method.getName().equals(name)) size++;
        }
        Method[] all = new Method[size];
        int index = 0;
        for (Method method : fromInterface) {
            if (method.getName().equals(name)) all[index++] = method;
        }
        for (Method method : fromProxy) {
            if (method.getName().equals(name)) all[index++] = method;
        }
        return all;
    }

    /**
     * 拼「动作 + 参数」的调用参数。
     *
     * <ul>
     *   <li>{@code action} 放在<b>最后一个 Bundle 之前最近的 String</b> 上；</li>
     *   <li>{@code extras} 放在最后一个 {@code Bundle} 上；</li>
     *   <li>其余参数：第一个 {@code String} 填调用方包名，别的填 null。</li>
     * </ul>
     */
    static Object[] actionArgs(Method method, String callingPackage, String action, Bundle extras) {
        Class<?>[] types = method.getParameterTypes();
        Object[] args = new Object[types.length];
        int extrasIndex = -1;
        for (int i = types.length - 1; i >= 0; i--) {
            if (types[i] == Bundle.class) { extrasIndex = i; break; }
        }
        if (extrasIndex < 0) extrasIndex = types.length - 1;
        int actionIndex = -1;
        for (int i = extrasIndex - 1; i >= 0; i--) {
            if (types[i] == String.class) { actionIndex = i; break; }
        }
        if (actionIndex < 0) actionIndex = extrasIndex > 0 ? extrasIndex - 1 : 0;
        args[actionIndex] = action;
        args[extrasIndex] = extras;
        for (int i = 0; i < types.length; i++) {
            if (i == actionIndex || i == extrasIndex) continue;
            args[i] = types[i] == String.class ? callingPackage : null;
        }
        return args;
    }

    /**
     * 在代理上找<b>评分</b>方法（{@code rate} / {@code setRating}）。
     *
     * <p>设备实测（API 28）这台是 {@code rate} —— 但不同 ROM / 不同版本可能不一样 →
     * 两个都找，取「<b>参数里能塞进一个评分</b>」的那个里参数最少的。
     *
     * @param proxy 会话控制代理
     * @return 找到的方法；找不到返回 null
     */
    static Method findRatingMethod(Object proxy) {
        Method best = null;
        for (String name : RATING_METHOD_NAMES) {
            for (Method method : candidates(proxy, name)) {
                if (ratingIndex(method) < 0) continue;
                if (best == null || method.getParameterTypes().length < best.getParameterTypes().length) {
                    best = method;
                }
            }
        }
        return best;
    }

    /**
     * 评分参数在方法签名里的<b>位置</b>（-1 = 找不到）。
     *
     * <p>评分参数的类型在不同版本上可能是 {@code Rating} 也可能是 {@code Object}，
     * 而 {@code callingPackage} 是 {@code String}、回调是<b>接口</b> →
     * 按「不是 String、不是接口」的位置定位。
     */
    private static int ratingIndex(Method method) {
        Class<?>[] types = method.getParameterTypes();
        for (int i = 0; i < types.length; i++) {
            Class<?> type = types[i];
            if (type != String.class && !type.isInterface() && type != Object.class) return i;
        }
        return -1;
    }

    /**
     * 拼「评分」的调用参数（{@code rate(callingPackage, callback, Rating)}）。
     */
    static Object[] ratingArgs(Method method, String callingPackage, Rating rating) {
        Class<?>[] types = method.getParameterTypes();
        Object[] args = new Object[types.length];
        int ratingIndex = ratingIndex(method);
        if (ratingIndex < 0) ratingIndex = types.length - 1;
        args[ratingIndex] = rating;
        for (int i = 0; i < types.length; i++) {
            if (i == ratingIndex) continue;
            args[i] = types[i] == String.class ? callingPackage : null;
        }
        return args;
    }

    /**
     * 发一个<b>自定义动作</b>（标准 {@code onCustomAction} 入口）。
     *
     * <p>主路：<b>公开 API</b> {@code MediaController.TransportControls.sendCustomAction}
     * （API 21 起就有）→ 直接进播放器的 {@code onCustomAction} 回调。
     *
     * @param context 上下文（取真实的调用方包名，兜底反射路径要用）
     * @param controller 当前会话的控制器
     * @param action 动作名
     * @param extras 参数（可空）
     * @return 是否真的发出去了
     */
    public static boolean sendCustomAction(Context context, MediaController controller,
            String action, Bundle extras) {
        if (context == null || controller == null) return false;
        // 主路：公开的 TransportControls（API 21+，设备实测 API 28 可用）。
        try {
            controller.getTransportControls().sendCustomAction(action, extras);
            UniLog.done(LogTags.MEDIA, "media/custom-action", "action", action, "route", "transport-controls");
            return true;
        } catch (Throwable directFailed) {
            UniLog.fail(LogTags.MEDIA, "media/custom-action", "action", action, "route", "transport-controls",
                    "reason", "direct-failed", "error", directFailed.getClass().getSimpleName());
        }
        // 兜底：隐藏的会话控制代理（个别 ROM 把公开方法改坏了时）。
        return sendCustomActionViaProxy(context, controller, action, extras);
    }

    /** 兜底路径：反射 {@code ISessionController.sendCustomAction}。 */
    private static boolean sendCustomActionViaProxy(Context context, MediaController controller,
            String action, Bundle extras) {
        String pkg = context.getPackageName();
        Object proxy = of(controller);
        if (proxy == null) {
            UniLog.fail(LogTags.MEDIA, "media/custom-action", "action", action, "reason", "no-session-controller-proxy",
                    "tokenFields", describeProxySearch(controller));
            return false;
        }
        Method method = find(proxy, "sendCustomAction");
        if (method == null) {
            UniLog.fail(LogTags.MEDIA, "media/custom-action", "action", action, "reason", "method-missing");
            return false;
        }
        try {
            method.invoke(proxy, actionArgs(method, pkg, action, extras));
            UniLog.done(LogTags.MEDIA, "media/custom-action", "action", action, "route", "session-controller-proxy");
            return true;
        } catch (Throwable error) {
            UniLog.fail(LogTags.MEDIA, "media/custom-action", "action", action, "reason", "invoke-failed",
                    "error", error.getClass().getSimpleName());
            return false;
        }
    }

    /**
     * 发一个<b>评分</b>（标准 {@code onSetRating} 入口）。
     *
     * <p>这是<b>收藏</b>的标准通道：播放器实现 {@code onSetRating} 就能收。
     *
     * <p>主路：<b>公开 API</b> {@code MediaController.TransportControls.setRating}（API 21+）。
     *
     * @param context 上下文（取真实的调用方包名，兜底反射路径要用）
     * @param controller 当前会话的控制器
     * @param rating 评分（收藏用<b>心形评分</b>）
     * @return 是否真的发出去了
     */
    public static boolean sendRating(Context context, MediaController controller, Rating rating) {
        if (context == null || controller == null || rating == null) return false;
        // 主路：公开的 TransportControls（API 21+，设备实测 API 28 可用）。
        try {
            controller.getTransportControls().setRating(rating);
            UniLog.done(LogTags.MEDIA, "media/rating", "route", "transport-controls", "heart", rating.hasHeart());
            return true;
        } catch (Throwable directFailed) {
            UniLog.fail(LogTags.MEDIA, "media/rating", "route", "transport-controls", "reason", "direct-failed",
                    "error", directFailed.getClass().getSimpleName());
        }
        // 兜底：隐藏的会话控制代理上的评分入口。
        return sendRatingViaProxy(context, controller, rating);
    }

    /** 兜底路径：反射 {@code ISessionController.rate / setRating}。 */
    private static boolean sendRatingViaProxy(Context context, MediaController controller, Rating rating) {
        String pkg = context.getPackageName();
        Object proxy = of(controller);
        if (proxy == null) {
            UniLog.fail(LogTags.MEDIA, "media/rating", "reason", "no-session-controller-proxy",
                    "tokenFields", describeProxySearch(controller));
            return false;
        }
        Method method = findRatingMethod(proxy);
        if (method == null) {
            UniLog.fail(LogTags.MEDIA, "media/rating", "reason", "method-missing",
                    "candidates", String.join("/", RATING_METHOD_NAMES));
            return false;
        }
        try {
            method.invoke(proxy, ratingArgs(method, pkg, rating));
            UniLog.done(LogTags.MEDIA, "media/rating", "method", method.getName(), "heart", rating.hasHeart());
            return true;
        } catch (Throwable error) {
            UniLog.fail(LogTags.MEDIA, "media/rating", "method", method.getName(), "reason", "invoke-failed",
                    "error", error.getClass().getSimpleName());
            return false;
        }
    }
}
