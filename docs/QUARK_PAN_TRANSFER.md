# 传文件 · 夸克网盘接入规划

面向"传文件"面板新增第三来源：**夸克网盘**。车机上扫一次码登录，之后长期免登录，可浏览网盘目录、勾选文件、下载到与手机上传同一个目录，再走现有的安装/删除流程。

本文只做规划与包体估算，不含实现代码。接口细节标注了「实测」的条目是在本机直接发请求验证过的；标「待实测」的需要在车机上用真实账号走一遍。

---

## 1. 目标与不做的部分

| 项目 | 结论 |
| --- | --- |
| 扫码登录（夸克手机 App） | 做 |
| 登录态长期有效（免反复扫码） | 做：cookie 落盘 + `__puus` 周期刷新 |
| 目录浏览（面包屑、分页、文件夹进入） | 做 |
| 选文件下载到 `files/transfers/`，可安装/删除 | 做 |
| 上传车机文件到网盘 | 不做（先只做下行；上行要分片验签，是另一套工作量） |
| 分享链接解析/转存 | 不做（与现有「手机发链接」重叠，二期再议） |
| 在线播放/缩略图预览 | 不做（会带进视频插件与图片缓存，包体和内存代价大，见 §9） |

---

## 2. 现状：现有传文件是怎么跑的

| 环节 | 落点 | 现状 |
| --- | --- | --- |
| 手机上传 | `integration/LanTransfer.java`（772 行） | 8787 端口的微型 HTTP 服务器，`POST /upload` 写入 `filesDir/transfers/` |
| 手机发链接 | 同上 `POST /link` | 只入队，**车机上点「下载」才真正拉流**（车机流量/磁盘不被外部驱动） |
| 队列与持久化 | `LanTransfer.Link` + `transfer-links.json` | `id/url/host/name/status/size/time/error`，进程被杀后 `downloading` 回落 `queued` |
| 安装 | `LanTransfer.install()` + `TransferFileProvider` | `ACTION_INSTALL_PACKAGE`，非未知来源授权时跳系统设置 |
| 命令面 | `LauncherRuntime.handleAction()` | `transfer-start/stop/install/delete/link-download/link-remove` |
| 状态面 | `LauncherRuntime.publish()` → snapshot `transfer` 段 | `running/ip/port/url/mode/files/links` |
| 界面 | `widgets/file_transfer_popup.dart`（面板）、`widgets/file_transfer_settings.dart`（设置页） | `controller.native` 值监听驱动刷新；`qr_flutter` 已在依赖里 |

两个必须先认清的约束：

1. **面板跑在自己的 FlutterEngine 上，关面板就 `engine.destroy()`**（`GlobalDockService.java:340`），而 `LauncherRuntime` 是进程级单例（`LauncherRuntime.java:82`，application context）。所以：**下载与会话刷新必须在原生侧**，否则用户一关面板任务就断。
2. **不要让 Dart 侧持有 cookie**。snapshot 会经 EventChannel 进 Dart，日志/崩溃上报里也更容易漏，cookie 只在 Java 侧进出，snapshot 只出昵称与容量。

结论：**Java 做内核（登录、cookie、列表、下载取链），Dart 只做 UI + 命令**，与现有 `official-catalog`、`weather` 的模式一致。

---

## 3. 夸克接口（实测结论：走 TV / 设备授权通道）

### 3.1 为什么不是网页扫码

最早接的是 PC 网页那套（`uop.quark.cn/cas/...` + `client_id=532` + `su.quark.cn/4_eMHBJ?token=`）。
**实测失败**：手机夸克 App 扫进去之后一直回「登录请求已过期」。原因是那条 token 是网页会话的，
换票端点（`getServiceTicketByQrcodeToken`）和 App 侧的授权不是同一套，扫码确认也对不上。

改用 OpenList 的 **夸克 TV 驱动**（`drivers/quark_uc_tv`）那条通道后一次就通了：
服务端直接给二维码图片，登录产出 **`refresh_token`**，这本来就是为「电视盒子长期登录」设计的。

### 3.2 三步登录（已实机跑通）

```text
固定参数（TV）：client_id=d3194e61504e493eb6222857bccfed94
                sign_key=kw2dvtd7p4t3pjl2d9ed9yc8yej8kw2d
                app_ver=1.8.2.2  channel=GENERAL  platform=tv
                api=https://open-api-drive.quark.cn
                token 交换=https://api.extscreen.com/quarkdrive/token

每个请求都要签名（路径不含域名）：
  x-pan-tm    = 13 位时间戳
  req_id      = md5(deviceId + 时间戳)
  x-pan-token = sha256(method + "&" + path + "&" + 时间戳 + "&" + sign_key)
  另带 x-pan-client-id 与一串公参（device_id/brand/model/gpu/activity_rect/channel…）

1) GET /oauth/authorize?auth_type=code&client_id=…&scope=netdisk&qrcode=1&qr_width=460&qr_height=460
   实测：{"status":0,"qr_data":"iVBORw0KGgo…（PNG 的 base64，4.8KB）","query_token":"sta336…"}
   → 二维码不用本地画，直接 Image.memory 显示；手机夸克 App 一定能认。

2) GET /oauth/code?client_id=…&scope=netdisk&query_token=<query_token>&req_id=…
   未扫码/未确认：HTTP 400 {"status":-1,"errno":11003,"error_info":"用户未确认授权"} → 继续轮询
   扫码确认后：HTTP 200 {"code":"<一次性 code>"}
   过期/失效另有 errno，按文案分类（见 3.4）

3) POST https://api.extscreen.com/quarkdrive/token
   body {req_id, app_ver, device_id, device_brand, platform, device_name, device_model,
         build_device, build_product, device_gpu, activity_rect, channel, code}
   → {"code":200,"data":{"status":0,"access_token":"<JWT>","refresh_token":"<JWT>","expires_in":…}}
   refresh_token 轮转：每次刷新都返回新的，必须立刻落盘。

4) GET /user?method=user_info  验证登录态（拿昵称/容量，拿不到不影响用）
```

### 3.3 目录与下载

```text
列目录 GET /file?method=list&parent_fid=<fid>&order_by=3&desc=1&category=&source=&ex_source=
        &list_all=0&page_size=100&page_index=<0 起>
        → data.total_count、data.files[{fid, filename, size, isdir, updated_at, category}]
        字段名与网页侧不同：filename / isdir / updated_at，归一时要兼容
        文件名要过一遍 HTML 反转义（&amp; 之类）

取下载 GET /file?method=download&group_by=source&fid=<fid>
        &resolution=low,normal,high,super,2k,4k&support=dolby_vision
        → data.download_url（现取现用，签名会过期，绝不落盘）
        拉流带同一份 User-Agent（TV UA），不需要 cookie / Referer

转码播放（未接）method=streaming，同一路径，返回 video_info[].url
```

### 3.4 错误码映射（UI 文案直接照这张表）

| 条件 | 含义 | UI |
| --- | --- | --- |
| `errno=11003` | 用户未确认授权 | 不报错，继续等（这是扫码前的常态） |
| `errno=11002` / 文案含「过期」「失效」 | 二维码过期 | 「二维码已过期，请刷新」+ 刷新按钮 |
| `errno=11004` | 授权码无效 | 「授权码无效，请重新扫码」 |
| `errno=11001` / 文案含 token | access_token 失效 | 静默刷新一次；仍失败 → 「夸克登录已失效，请重新扫码」 |
| `errno=10001` | 公参缺失（我们拼错参数时才会出现） | 原样透出上游文案，便于定位 |
| 其他 | 上游异常 | 透出 `error_info`；空则给 HTTP 状态码 |

> 踩过的坑：`/oauth/*` 的字段在响应**顶层**，`/file` 与 token 端点包在 `data` 里。
> 只按 `data.xxx` 取会让二维码静默变空、界面显示「取二维码失败」——`QuarkPan.field()` 两级都认。

---

## 4. 「长期有效」靠什么

TV 通道给的 `refresh_token` 就是长期凭证（这也是选它的主要原因）：

1. 首次扫码拿 `access_token + refresh_token`，两个都落盘（`filesDir/quark/session.json`，仅本人可读）；
2. `access_token` 是短周期 JWT，任何请求遇到 11001 / 文案含 token → 用 `refresh_token` 换一对新的，
   **新 refresh_token 立即覆盖落盘**（轮转，旧的会作废），然后原请求重试一次；
3. 冷启动（进程起来 2.5s 后）读盘恢复并静默续期一次，用户不用重新扫码；
4. `deviceId` 首次生成后永久固定：它参与每个请求的签名，换掉等于换设备，会被判设备不一致。

不做无限重试：`refresh_token` 也失效时只提示「请重新扫码」，不打扰用户、不刷屏。
单飞锁：续期与取链互斥，避免一次刷新把正在取链的请求弄成 401。

---
## 5. 结构设计

### 5.1 新增/改动的文件（写范围）

| 文件 | 动作 | 估算行数 |
| --- | --- | --- |
| `app/android/.../integration/QuarkPan.java` | 新增 | ~600 |
| `app/android/.../integration/LanTransfer.java` | 改：队列支持 `quark` 来源、`rescan()`、目录访问器 | ~110 |
| `app/android/.../LauncherRuntime.java` | 改：7 条命令 + snapshot `quark` 段 | ~45 |
| `app/android/app/src/test/java/.../QuarkPanTest.java` | 新增（JUnit 4 + org.json，已在依赖里） | ~180（不进包） |
| `app/lib/widgets/quark_panel.dart` | 新增：二维码态、列表态、面包屑、多选 | ~380 |
| `app/lib/widgets/file_transfer_popup.dart` | 改：顶部分段「手机上传 / 夸克网盘」 | ~60 |
| `app/lib/widgets/file_transfer_settings.dart` | 改：登录状态、容量条、退出登录 | ~40 |
| `docs/QUARK_PAN_TRANSFER.md`、`CHANGELOG.md` | 文档 | — |

### 5.2 类骨架

```java
public final class QuarkPan {
    // 纯函数区（单测直接打这里，不碰网络）
    static String reqId(String deviceId, String ts);                        // md5(deviceId+ts)
    static String sign(String method, String path, String ts, String key);  // sha256
    static String field(JSONObject json, String key);                       // 顶层与 data 两级都认
    static String pollVerdict(int http, int errno, String code, String info);// code|wait|expired|error
    static JSONArray normalizeEntries(JSONArray raw);                       // TV 字段名 → 界面字段

    // 会话
    void    startLogin();                   // /oauth/authorize → qrImage(base64) + query_token
    void    restore();                      // 冷启动读 session.json + 静默续期
    void    logout();
    boolean loggedIn();

    // 文件
    void    list(String fid, int page);      // method=list，归一化后进 snapshot
    void    open(String fid, String name);   // 目录栈（".." 回上级）
    Fetch   resolve(String fid) throws Exception;      // method=download，现取现用
    int     enqueue(String fids, LanTransfer transfer); // 入队不下载
    void    shutdown();
}
```

```java
// LanTransfer 侧：复用现有队列，不新造一套
private static final class Link { ... String kind = "http"; String fid = ""; }

public String addQuarkLink(String fid, String name, long sizeHint); // 入队，status=queued
// runDownload() 分支：
//   kind=http  → 现状逻辑
//   kind=quark → 先 quark.downloadUrl(fid)，再带 cookieSnapshot/UA/Referer 拉流
//                失败且是鉴权类 → status=failed, error="登录已失效"
```

### 5.3 命令面（`LauncherRuntime.handleAction`）

| action | value | 行为 |
| --- | --- | --- |
| `quark-login` | — | 取 TV 二维码（base64 图），进入 waiting，启动 2s 轮询 |
| `quark-login-refresh` | — | 二维码过期后重取（旧 query_token 作废） |
| `quark-logout` | — | 清 session.json，回到未登录 |
| `quark-list` | fid | 列目录，写回 snapshot |
| `quark-open` | `fid|name` / `..` | 进入子目录或回上级（维护面包屑栈） |
| `quark-more` | — | 加载下一页（每页 100） |
| `quark-enqueue` | `fid1,fid2` | 加入 links，**入队不下载**（沿用"车机点一下才开始"的规矩） |
| `transfer-text-remove` | id | 删掉一条手机发来的文本 |
| `transfer-text-clear` | — | 清空全部文本 |

下载复用现有 `transfer-link-download` / `transfer-link-remove` —— 不需要新命令。

### 5.4 snapshot 新段

```json
"quark": {
  "state": "idle|waiting|scanned|authorized|expired|error",
  "qrImage": "iVBORw0KGgo…（PNG base64，只在 waiting/scanned/expired 时下发）",
  "expiresIn": 0,
  "nickname": "", "memberType": "NORMAL",
  "totalCapacity": 0, "useCapacity": 0,
  "pdir": "0",
  "crumbs": [{"fid":"0","name":"根目录"}],
  "entries": [{"fid":"","name":"","size":0,"dir":false,"updatedAt":0,"category":0}],
  "total": 0, "page": 1, "error": ""
}
```

`transfer.links[]` 增加 `"kind":"quark"`，UI 的来源标显示「夸克」。

### 5.5 持久化

| 文件 | 内容 | 说明 |
| --- | --- | --- |
| `filesDir/quark/session.json` | `deviceId`、`accessToken`、`refreshToken`、昵称、容量、loginAt | 应用私有目录，`setReadable(false,false)`；token 不进 logcat |
| `filesDir/transfer-links.json` | 现有队列 + `kind/fid` | 老数据无 `kind` 视为 `http`；`quark` 任务恢复时按 fid 重新取链（旧 URL 会过期） |
| `filesDir/transfer-texts.json` | 手机发来的文本（最多 30 条，单条 20000 字） | 正文原样保存，只在提交时统一换行、清控制字符 |

不引 `flutter_secure_storage`：车机是单用户私有设备，Android 私有目录已经够了，多一层 encryption 只会带进 androidx.security 依赖（见 §9）。

---

## 6. 界面规划

面板（现在 640×860 单列）改成「顶部分段 + 内容区」，分段控件放标题行下方：

```text
[传文件]                                    [×]
( 手机扫码 | 夸克网盘 )
--------------------------------------------------
手机扫码页：
   [开启传文件 开关]  手机与车机连接同一网络
   [二维码 300px] + 访问地址
   手机发来的文本（N）                       [清空]
   ┌ 手机文本 · 点击复制 / 已复制 ✓     [复制] [删除]
   │ 正文最多三行，超出省略
   └ …（整块也可点，直接进剪贴板）
   下载队列：链接行/夸克行，来源标 + [下载][删除]
   已接收文件：名称 + 大小 + [安装][删除]
--------------------------------------------------
夸克页：
未登录：[二维码]  手机夸克 App › 扫一扫 › 确认授权
        [刷新二维码] [从手机上传]
已登录：昵称 · 会员类型 · 已用/总量            [退出]
        根目录 › 电影 › 2024                (面包屑可点)
        文件夹行 → 点进下一层；文件行 → 勾选后 [下载选中 N 个]
        [更多] 仅在有下一页时出现
```

交互细节：

- 轮询 1.5s，二维码 5 分钟过期自动换新，页面不可见时暂停轮询；
- 面包屑只在登录态显示，`..` 与返回键语义一致；
- 下载中显示"已下载/总量 + 速度"，非会员限速是正常现象，UI 显示真实速率，别让用户以为是 Bug；
- 断网/401 用统一的错误条，不弹对话框（车机触屏弹窗体验差）。

---

## 7. 下载管线（复用现有那条）

```text
选文件 → quark-enqueue(fid) → links 里多一条 status=queued（来源=夸克，不下载）
车机点「下载」 → transfer-link-download → runDownload()
   kind=quark: POST /file/download 取链（快照 cookie）
               GET download_url（同一 cookie + UA + Referer，Range 分段 2 并发 × 8MB 可选）
               写 filesDir/transfers/<name>.part → rename → refreshFiles() → 列表里可安装
失败分支:   401/403 → 「登录已失效」；2GB 上限沿用；磁盘不足 → 「空间不足」
进程被杀:   现有 loadLinks() 把 downloading 回落 queued；quark 任务按 fid 重新取链
```

上限与现状保持一致：单文件 **2GB**（`LanTransfer.MAX_UPLOAD_BYTES`）。超过就明确提示，不做静默截断。

---

## 8. 落地状态

### 8.1 夸克网盘

| 环节 | 文件 | 状态 |
| --- | --- | --- |
| 协议内核：TV 签名、二维码、轮询换票、`refresh_token` 续期、目录、取链、入队 | `integration/QuarkPan.java`（819 行） | 已完成 |
| 下载管线：`kind`/`fid` 字段、夸克分支（TV 直链 + UA）、持久化兼容 | `integration/LanTransfer.java` | 已完成 |
| 命令面与快照：7 条命令 + `quark` 段 + 冷启动静默恢复 | `LauncherRuntime.java` | 已完成 |
| 界面：扫码/等待/失效/已登录四态、面包屑、勾选、翻页 | `widgets/quark_panel.dart`（322 行） | 已完成 |
| 入口：面板加「手机扫码／夸克网盘」页签，手机扫码仍是默认 | `widgets/file_transfer_popup.dart` | 已完成 |
| Java 单测 9 例 / Dart 组件测试 5 例 | `QuarkPanTest.java`、`test/quark_panel_test.dart` | 全绿 |

**真机（雷电模拟器，Android 9）已跑通**：扫码登录 → 根目录列出真实文件夹 → 进子目录 → 选文件入队 → 点下载落地。
实测记录：`session.json` 里 `access_token`/`refresh_token` 均为真实 JWT，`deviceId` 稳定不变。

### 8.2 手机发文本到车机

| 环节 | 文件 | 状态 |
| --- | --- | --- |
| 服务端 `POST /text`、`GET /texts`、清洗/去重/上限、持久化 | `integration/LanTransfer.java` | 已完成 |
| 网页第三块「发一段文本到车机」（textarea + 发送） | 同上 `page()` | 已完成 |
| 车机侧文本卡片：整块点击复制、复制/删除/清空、`已复制 ✓` 1.6s 反馈 | `widgets/file_transfer_popup.dart` | 已完成 |
| 命令面 `transfer-text-remove` / `transfer-text-clear` | `LauncherRuntime.java` | 已完成 |
| Java 单测 4 例（清洗、截断、三种请求体解码） / Dart 组件测试 2 例 | `LanTransferTextTest.java`、`test/file_transfer_popup_test.dart` | 全绿 |

**真机已跑通**：`POST /text` 中文+换行原样落库、`GET /texts` 回读一致、车机面板出现文本行并复制成功。

> 本机 Gradle 备注：`app/android/settings.gradle.kts` 在 Gradle 9.3.1 下报 Kotlin DSL 符号解析失败（`Unresolved reference 'run'/'file'`），与本功能无关，是环境版本组合问题，wrapper 已改钉 9.7.1。早期验证走的是「`javac` 对 `android.jar` 真编译 + `d8` 真出 dex + Flutter 侧 `analyze`/`test`」；现在 `flutter build apk --debug` 也能整包构建。

---
## 9. 包体实测（`d8` 真量的边际，不是模型）

### 9.1 基线（本机实测，`app/build/app/outputs/`）

| 项 | 压缩后 | 解压后 |
| --- | --- | --- |
| `app-arm64-v8a-release.apk` | **13.39 MB** | — |
| `lib/arm64-v8a/libapp.so`（Dart AOT） | 2883.9 KB | 7168.9 KB |
| `classes.dex`（Java/Kotlin） | 2256.8 KB | 6355.0 KB |
| `libflutter.so`（引擎，固定） | 5356.9 KB | 11487.7 KB |

关键压缩比：`libapp.so` 压缩后/原始 = **0.402**，`classes.dex` = **0.355**。

### 9.2 每行代码的边际体积（实测，不是估算模型）

各做一次「加 1 组代码前后」的对照，量**增量**而不是总量。用同一套数据模型代码（字段 + `fromJson/toJson` + 字符串处理），避免风格差异污染结论。

| 语言 | 方法 | 结果 |
| --- | --- | --- |
| Dart AOT（**真机口径**） | `flutter build apk --release --target-platform android-arm64`，同一工程 baseline（18 行 main）vs 加 2471 行 | libapp.so 2816.9 KB → 2880.9 KB，**+64.0 KB ⇒ 26.5 B/行** |
| DEX | `javac` + `d8 --release --min-api 24`，23 行 vs 849 行 | +85.5 KB / 826 行 ⇒ **106 B/行**（原始 dex） |
| （交叉校验）Dart AOT x64 | `dart compile aot-snapshot` 同款对照 | 55.8 B/行 —— 比 ARM64 高约 2×，说明**不能拿 x64 代 AOT 反推 Android 包** |

按 §9.1 的压缩比折成 APK 里的字节：**Dart ≈ 10.7 B/行**（26.5 × 0.402）、**Java ≈ 37.6 B/行**（106 × 0.355）。

### 9.3 本功能的实测增量（代码写完后的真数）

同一套 `javac` + `d8 --release --min-api 24`，对比 `HEAD` 版本的 `LanTransfer.java` / `TransferFileProvider.java` 与当前仓库（含 `QuarkPan.java`、文本通道）：

| 部分 | 行数（净增） | 原始体积 | 折成 APK 内（压缩比） |
| --- | --- | --- | --- |
| Java：`QuarkPan`（819）+ `LanTransfer`（+263/−12）+ `LauncherRuntime`（+23） | **+1093** | dex **30,320 B → 51,700 B**（**+21.4 KB**，19.6 B/行） | **+7.6 KB**（× 0.355） |
| Dart：`quark_panel.dart`（322）+ `file_transfer_popup.dart`（+167/−37） | **+452** | AOT ≈ **+12.0 KB**（26.5 B/行，实机 ARM64 口径） | **+4.8 KB**（× 0.402） |
| 资源 / 依赖 / 权限 / native 库 | **0** | — | **0** |
| **合计** | — | — | **≈ +12.4 KB** |

- arm64 单包：**13.39 MB → ≈ 13.40 MB，+0.09%**
- 安装后磁盘（`useLegacyPackaging` 解压 .so）：**+≈ 0.04 MB**
- 运行内存：峰值 **+2 – 3 MB**（一页 100 条列表 JSON + 二维码 base64 + 64 KB 下载缓冲），闲时约 0
- 测试代码（`QuarkPanTest` 9 例、`LanTransferTextTest` 4 例、两个 Dart 测试文件）**不进包**

> 「手机发文本」这部分几乎不占体积：服务端逻辑 80 行 + 页面里 3 个控件，dex 增量约 **+1.6 KB**，可忽略。
>
> 之前的 **+33–40 KB** 是偏保守的上界：那个 106 B/行 的 DEX 系数来自"每行都是新字符串、新方法、无共享"的玩具类；
> 真实增量里 19.6 B/行，因为新代码大量复用已有字符串池、`org.json`/`HttpURLConnection` 调用点与工具方法，
> `d8` 会把它们并进同一份常量表。
>
> 一个容易混进来的坑：`build.gradle.kts` 现在开着 `jniLibs.useLegacyPackaging = true`，libapp.so 是 **deflate 压缩**存的（0.402）。
> 哪天为了启动速度关掉它，包会直接涨 4 MB 级——那跟本功能无关，做对比时别把两件事搅在一起。
>### 9.4 会让包体明显变大的选项（明确避开）

| 选项 | 代价 | 结论 |
| --- | --- | --- |
| 内置 WebView 走网页登录 | **+2.5 – 4 MB**，常驻内存 +30–60 MB（还要 webview 引擎与 JS） | 不用，扫码已经够 |
| 引 okhttp / retrofit | okhttp ≈ **+0.7 – 1.1 MB** dex（+okio） | 不用，`HttpURLConnection` + `org.json` 够跑这些接口 |
| 引 gson / moshi | **+100 – 180 KB** | 不用，`org.json` 在框架里 |
| `flutter_secure_storage` | **+40 – 80 KB**（带 androidx.security） | 首版不用，私有目录 + 不落日志 |
| `path_provider` | **+20 – 40 KB** | 不需要，目录由 snapshot 从原生给 |
| 缩略图 / 海报（`cached_network_image` + 缓存管理） | **+150 – 350 KB**，还要新增磁盘缓存与清理策略 | 不做预览就不引 |
| 在线播放（视频插件 + 转码） | **+3 – 6 MB** | 不做 |

一句话：**这个功能是"纯协议 + 纯列表 UI"，不加依赖就是 10 KB 量级（0.01 MB，+0.08%）；一旦想内置网页或做预览，就会从 0.01 MB 跳到 2–6 MB。**

---

## 10. 验证清单

### 10.1 已实测通过

协议层（curl 打过，App 抢在同一批端点上）：

1. `GET /oauth/authorize` 返回 `qr_data`（PNG base64，约 4.8 KB）与 `query_token`；
2. `GET /oauth/code` 未扫码回 `HTTP 400 + errno 11003 用户未确认授权`，扫确认后回 `code`；
3. `POST /extscreen/quarkdrive/token` 用 code 换到 `access_token` + `refresh_token`（均为 JWT）；
4. `GET /file?method=list` 带签名列出真实根目录（0 个 fid 也行）；
5. `GET /file?method=download` 拿 `download_url`，带 TV UA 能直接拉流落地。

设备上（雷电模拟器 · Android 9 · 1920×1080）：

- 扫码 → `session.json` 出现真实双 token，`deviceId` 稳定；
- 根目录列出 `0000temp / 来自：分享 / 课件 / 复仇者联盟 / 夸克上传文件 / 我的备份`；
- 进子目录、面包屑回上级、勾选入队、点下载落地到 `filesDir/transfers/`；
- 手机网页 `POST /text` 中文换行原样保存，面板出现文本卡片，点一下进剪贴板并显示 `已复制 ✓`。

单测（不进包）：

- Java 13 例：签名向量、轮询判定、错误文案、token 失效识别、列表归一化、文本清洗/截断/三种请求体解码；
- Dart 397 例全绿（含夸克面板 5 例、传文件面板 8 例）；`flutter analyze` No issues found。

### 10.2 还要在车上确认的（不是开发工作）

- IP753 / E02 上连续跑 24–72h，确认 `refresh_token` 续期后仍能列目录并下载（车机地库弱网也要试）；
- 关掉传文件面板后下载继续到 100%（验证"为什么把下载放原生"这条）；
- 500MB 以上 APK 下载后能直接安装；
- 手机与车机不在同一网段（热点/地库）时的错误提示是否符合预期。

---
## 11. 风险与待定

| 风险 | 处理 |
| --- | --- |
| 夸克这些是非公开接口，随时可能改 | 域名/路径/错误码集中成常量表；解析层全部做"缺字段降级"，不抛崩溃；出错只影响夸克页，不影响手机上传 |
| `refresh_token` 有效期是上游行为，没有官方文档 | 车机连续跑 24–72h 确认；续期做成"按需触发 + 单飞"，失效只提示重扫，不做无限重试 |
| 非会员下载限速、大文件慢 | UI 显示真实速率与剩余时间；不做"加速"承诺 |
| 车机流量 | 沿用"车机点下载才开始"；入队不自动跑；可选加"仅 WiFi 下载"开关（放在 M4，可作为增量） |
| cookie 泄漏 | 只在 Java 侧流转，snapshot 只出昵称/容量；日志打码；文件 0600 |
| 队列持久化格式变更 | `transfer-links.json` 加字段向后兼容（无 `kind` 视为 `http`），回滚旧版本不会崩 |
| 2GB 上限 | 沿用现状；超限明确提示，不静默截断 |
| targetSdk 28 / minSdk 24 | 无分区存储与 SAF 约束，写私有目录不涉及权限申请 |

---

## 12. 参考

- OpenList 夸克 TV 驱动（本实现的协议依据）：`drivers/quark_uc_tv/{meta,util,types}.go` <https://github.com/OpenListTeam/OpenList/tree/main/drivers/quark_uc_tv>
- 夸克接口手册（社区整理，含 sort/download/二维码登录）<https://github.com/zhaocongqi/clouddrive-auto-save/blob/main/docs/quark_apis.md>
- 现有实现：`app/android/app/src/main/java/xyz/i4o/uni/launcher/integration/LanTransfer.java`、`app/lib/widgets/file_transfer_popup.dart`
