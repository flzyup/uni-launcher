# 歌词伴侣 → UNI 桌面功能移植方案

对象样本：`歌词伴侣.lyrics_companion.apk`（9,458,528 B，sha256 `f325fd9f…`，包名
`com.zuoqirun.lyricscompanion`，版本 `20261021-7902e14`，minSdk 19 / targetSdk 36，双 dex，
无 native 库，AGPL-3.0，上游仓库 `github.com/zuo-qirun/Lyrics-Companion`）。
反编译产物在 `_apk/jadx/sources/com/zuoqirun/lyricscompanion/`。

本方案已落地：4 个 Java 文件、2 个 Dart 文件、1 个 JUnit 测试、1 个 Dart 测试（全部离线可跑，
无设备依赖）。接线到现有播放链路只需改 `MediaAdapter` 一个地方。

---

## 1. 结论先行

这个 App 值得移植的不是 UI，而是**歌词时间轴**这一层。UNI 现在的歌词是「一行一个时间戳」，
它的歌词是「一个词一个时间戳」，并且为拿到这个词级时间轴铺了六家曲库、五种私有编码、三套
播放时钟兜底。差距集中在下面这张表，`LyricsResolver.java`（455 行）只覆盖了第 1 行：

| 能力 | UNI 现状 | 歌词伴侣 | 移植后 |
|---|---|---|---|
| 行级 LRC | ✅ `LyricsResolver` | ✅ | 保留为兜底 |
| 词级时间轴（卡拉 OK 填充） | ❌ | ✅ yrc/krc/qrc/mrc | ✅ `LyricTimeline` |
| 翻译 / 罗马音对齐 | ❌ | ✅ 文本优先、时间兜底 | ✅ |
| 曲库数量 | 3（网易/QQ/酷狗） | 6（+酷我/汽水/咪咕） | 4 家（+酷我词级） |
| 曲库优先级 | 固定顺序 | 按播放器包名优先 + 并行升级 | ✅ |
| 占位歌词过滤 | 无 | ✅ 质量闸门 | ✅ |
| 卡死行检测 | 无 | ✅ `StuckLineDetector` 规则 | 规则已随文档给出 |
| 间奏 / ±3 行窗口 | 无 | ✅ | ✅ |
| 六种编码解码 | 仅 LRC | ✅ | ✅ 4 种（KRC/QRC/MRC/AWLRC） |
| 私有渲染器 16 种特效 | 无 | ✅ 276 KB Canvas | 只取「填充」一种 |

---

## 2. 参考实现的功能地图

| 层 | 关键类（反编译路径） | 说明 |
|---|---|---|
| 取词编排 | `MultiSourceLyricClient` (599 行) | 6 家并行，先按播放器优先取命中缓存，再全量兜底，只允许质量分更高的结果覆盖 |
| 质量闸门 | `CatalogLyricQuality` | 行数 > 1 且至少一行不是 `纯音乐请欣赏/暂无歌词/instrumental` |
| 路由表 | `LyricSourceRules` | 远程 `lyric-rules.json`（6 h 刷新，64 KB 上限），域名钉死后重写 |
| 网易 | `NetEaseEapi` / `NetEaseLyricClient` | EAPI 签名 + AES/ECB，只有它能一次拿到 lrc/tlyric/**yrc**/romalrc |
| QQ | `QrcLyricCodec` | hex → 3DES(24 字节 key) → zlib，词标记 `text(start,dur)` |
| 酷狗 | `KrcLyricCodec` | 跳过 4 字节头 → XOR → zlib，词标记 `<start,dur,0>` |
| 酷我 | `KuwoWordLyricCodec` | `tp=content` 头 + zlib + base64 + XOR `yeelion`，词标记 `<start,end>` |
| 咪咕 | `MiguMrcCodec` | 9×64 bit key 的分组密码，UTF-16LE |
| 时间轴 | `LrcTimeline` (841 行) | 行/词模型、平移 `[offset:]`、翻译最近邻匹配、间奏判定、±3 行窗口、12 MB 缓存 |
| 时钟 | `PlaybackClockRules` / `StuckLineDetector` / `SessionChannelArbiter` | 30 s 宽限、卡死 25 s 判定、蓝牙与 MediaSession 权重仲裁 |
| 渲染 | `LyricsPanelView` (276 KB) + `LyricEffectCatalog` | 16 种特效，Choreographer 逐帧 |
| 悬浮 | `LyricsDisplayService` / `OverlayStartupReceiver` | SYSTEM_ALERT_WINDOW 副屏歌词，与桌面窗口是同一种东西 |

**不移植**：Folia 3D 场景（约 8 MB 资源 + 自建 GPU/Canvas 管线）、频谱音源、社区/更新器/FAQ
客户端、悬浮窗权限流程（UNI 有自己的窗口与 `GlobalDockService`）。

---

## 3. 交付文件

### Java（`app/android/app/src/main/java/xyz/i4o/uni/launcher/integration/lyrics/`）

| 文件 | 职责 | 关键 API |
|---|---|---|
| `LyricTimeline.java` | 时间轴模型与解析：LRC / YRC / 增强 LRC 折叠成一份；翻译按文本优先、时间兜底对齐；间奏；±3 行窗口；质量分；JSON 桥 | `parse(lrc,tr,yrc,romaji)`、`at(positionMs)`、`toJson()`、`qualityScore()`、`usable()` |
| `LyricCodecs.java` | 五种容器解码，全部输出增强 LRC 正文 | `kugou(base64)`、`qq(xml/hex)`、`migu(hex)`、`kuwoWord(bytes)`、`awlrc(text)`、`enhancedToPlain()` |
| `LyricCatalog.java` | 四家曲库检索 + 评分 + 优先级 + 磁盘缓存 + 有界 HTTP | `load(title,artist,durationMs,ownerPackage)`、`cached(...)`、`eapiBody(songId)` |
| `LyricTimelineProvider.java` | 非阻塞门面：内存/磁盘命中即返回，未命中单线程后台取一次，失败记 30 min 未命中 | `resolve(title,artist,durationMs,ownerPackage,embeddedLrc)` |

这 4 个文件只依赖 JDK + `org.json`（平台自带），没有 Context、没有 Android 类，因此
`app/android/app/src/test/` 可以直接跑，不需要模拟器。

### Dart

| 文件 | 职责 |
|---|---|
| `app/lib/model/lyric_timeline.dart` | 解析 `media['lyricTimeline']`，本地推进游标：活动行、已唱前缀、当前词进度、间奏、±3 行窗口；`sungPrefix` 只在有词级时间轴时给值，`estimatedSungPrefix` 是显式可选的估算 |
| `app/lib/widgets/lyric_karaoke.dart` | `KaraokeText`（两层文本 + 像素级裁剪，填充边沿落在字形边界）与 `LyricKaraokePanel`（三行面板，stateless，时钟由父级传入） |

### 测试

| 文件 | 覆盖 |
|---|---|
| `app/android/app/src/test/java/.../lyrics/LyricTimelineTest.java` | 8 个用例：行级/词级/卡拉 OK 游标/间奏/质量闸门/KRC 解码/词标记方向/JSON 往返 |
| `app/test/lyric_timeline_test.dart` | 7 个用例：解析、已唱前缀、多字词比例填充、无词级时不自作聪明、间奏、垃圾输入、两个 widget 冒烟 |

已实测：`javac`（Java 17）零错误；JUnit 4.13.2 `OK (8 tests)`。

---

## 4. 接线：`MediaAdapter` 唯一改动点

现状（`MediaAdapter.java:393–409`）：先读 media 元数据里的歌词文本，再查
`LyricsResolver` 缓存，未命中就异步请求，最终写 `lyrics` / `lyricsSource`。

新增两处，不动原有四行（原逻辑继续做行级兜底，Dart 侧两条通道各取所需）：

**(1) 字段与初始化**，紧挨 `MediaAdapter.java:37` / `:131`：

```java
private final LyricTimelineProvider timeline;                       // 字段
// :131 附近，与 LyricsResolver 并列
timeline = new LyricTimelineProvider(new File(context.getFilesDir(), "lyric-timeline"));
```

**(2) 快照里多写一个键**，插在 `MediaAdapter.java:403–409` 之间：

```java
// 词级时间轴与行级歌词是两条通道：老路径不动，新路径按播放器包名优先取词级文档。
LyricTimelineProvider.Result timed = timeline.resolve(
        title, artist, duration, controller.getPackageName(), text);
if (!timed.isEmpty()) {
    j.put("lyricTimeline", timed.json)
     .put("lyricTimelineLabel", timed.label)
     .put("lyricTimelineWords", timed.wordTimed);
}
```

`text` 就是上面 `readLyrics(m, controller.getExtras())` 的结果，所以播放器自己发布的歌词
（包括带 `<offset,dur>` 词标记的那种）会走本地解析，一次网络请求都不发。

**为什么放这里**：`MediaAdapter` 已经是快照聚合点，`lyricTimeline` 与 `positionMs`、
`sampledAtMs` 同批下发，Dart 侧拿到的词级时间轴和时间基准是同一次采样，不需要额外对时。

---

## 5. Dart 侧接线

`LyricsView` 继续服务行级歌词；词级渲染是并行选项，用设置项切换：

```dart
// 卡片里，原来的 LyricsView 位置
final timeline = LyricTimeline.parse(media['lyricTimeline']);
final positionMs = MediaTimeline.fromJson(media).at(nowMs);   // 复用现有时间基准
if (timeline.hasWordTiming) {
  LyricKaraokePanel(timeline: timeline, positionMs: positionMs,
      estimatedKaraoke: settings.estimatedKaraoke);
} else {
  LyricsView(media: media);                                   // 原路径
}
```

三条纪律，与仓库现有约定一致：

1. **不伪造时间轴**。没有词级文档时 `cursor.sungPrefix` 返回空串，整行高亮；估算填充必须由
   `estimatedKaraoke` 显式打开，和上游的「估算词级」一样是选项而不是默认。
2. **不编歌词**。`LyricTimeline.usable()` 不通过就是空，卡片显示「当前音源未提供歌词」。
3. **标注来源**。`lyricTimelineLabel`（网易云音乐 / QQ 音乐 / 酷狗音乐 / 酷我音乐 / 本地歌词）
   直接给归属行用；行级通道原有的 `lyricsSource`（`media-session` / `lyrics-resolver` / `demo`）保持不变。

---

## 6. 编码格式速查（移植时核对用）

| 来源 | 线上形态 | 变换 | 词标记 |
|---|---|---|---|
| 酷狗 KRC | base64 文本 | 去 4 字节头 → `key[i%16]` XOR → zlib | `<start,dur,0>text` |
| QQ QRC | XML CDATA 里的 hex | hex → DESede/ECB（`!@#)(*$%123ZXC!@!@#)(NHL`）→ zlib → 取 `LyricContent=""` | `text(start,dur)` |
| 酷我 词级 | `tp=content\r\n\r\n` + 二进制 | zlib → base64 → `yeelion` XOR | `text<start,end>` |
| 咪咕 MRC | hex | 16 hex 一块 → 分组解密（DELTA 2654435769，9 个 64 bit key）→ UTF-16LE | `text(start,dur)` |
| 本地 AWLRC | 文本 | 无 | `text<offset,dur>` |

两种方向必须分清，移植时最容易错：**KRC/QRC/MRC 的标记在前**（标记描述它后面的文本），
**酷我/AWLRC 的标记在后**（标记描述它前面的文本）。`LyricCodecs` 里用
`wordsToEnhanced(...)` 与 `textBeforeMarkers(...)` 分别处理，`LyricTimelineTest` 各锁一条用例。

`[offset:±ms]` 平移、`[mm:ss.xxx]` 小数位换算（1/2/3 位分别 ×100/×10/×1）、
`(?:[.:](\d{1,3}))?` 两种分隔符都按上游 `LrcTimeline.TIME_TAG` 行为实现。

---

## 7. 端点清单（移植后实际会打到的地址）

```
网易  POST music.163.com/api/search/get/web                （检索）
      POST interface3.music.163.com/eapi/song/lyric/v1     （EAPI，唯一给 yrc）
QQ    GET  c.y.qq.com/soso/fcgi-bin/client_search_cp
      GET  c.y.qq.com/qqmusic/fcgi-bin/lyric_download.fcg  （QRC）
      GET  c.y.qq.com/lyric/fcgi-bin/fcg_query_lyric_new.fcg（纯 LRC 兜底）
酷狗  GET  songsearch.kugou.com/song_search_v2
      GET  lyrics.kugou.com/search  →  /download?fmt=krc
酷我  GET  search.kuwo.cn/r.s
      GET  mlyric.kuwo.cn/mobi.s?...&lrcx=1&rid=MUSIC_<id> （词级）
      GET  m.kuwo.cn/newh5/singles/songinfoandlrc          （行级/翻译）
```

网络纪律：连接 3 s、读 4 s、单响应 256 KB 上限、失败静默降级到下一家；沿用仓库「有界载荷 +
主线程零 I/O」的既有约定。缓存落在 `filesDir/lyric-timeline/<sha1>.lyric.json`，带
`cv` 版本号与 `quality` 分，命中后再遇到更高分文档会覆盖。

---

## 8. 验证

**离线**（本机已跑通）：

```powershell
# Java：解析、词标记方向、KRC 解码、JSON 往返
javac -encoding UTF-8 -d $env:TEMP\lt -cp <json.jar> `
  app\android\app\src\main\java\xyz\i4o\uni\launcher\integration\lyrics\*.java `
  app\android\app\src\test\java\xyz\i4o\uni\launcher\integration\lyrics\*.java
java -cp "<json.jar>;<junit.jar>;<hamcrest.jar>;$env:TEMP\lt" `
  org.junit.runner.JUnitCore xyz.i4o.uni.launcher.integration.lyrics.LyricTimelineTest
# => OK (8 tests)

cd app; flutter test test/lyric_timeline_test.dart
```

**真机**（每家用一首已知有词级歌词的歌，看 `lyricTimelineWords` 与填充是否跟得上）：

1. 网易云音乐 → 应出 `wordTimed=true`（yrc 通道）；把 `eapiBody` 的 `id` 换成一首只有 LRC 的
   歌，应退化为 `wordTimed=false` 但行仍显示。
2. QQ 音乐 → `lyric_download.fcg` 的 QRC 必须解出词级；若只有 `fgc_query_lyric_new` 命中，
   说明 QRC 分支解密失败，先查 3DES 是否走了 `NoPadding` 兜底。
3. 酷狗 → KRC 首 4 字节头与 XOR key 对齐；歌词错位一个字通常是 `trimWordEdges` 把空白词裁掉了。
4. 酷我 → 词级优先，`m.kuwo.cn` 只作行级与翻译来源。
5. 暂停 30 s 再播放、拖进度条、切歌三次：填充不能残留上一首的位置（`elapsedMs` 由
   `MediaTimeline.at()` 给出，切歌后 `lineStartMs` 变，自然归零）。

---

## 9. 风险与取舍

| 项 | 事实 | 处理 |
|---|---|---|
| 曲库可用性 | 六个端点全是公开但非承诺的接口，随时可能改签名/换域名 | 每家独立 try/catch，单家失败只是少一家；`LyricCatalog` 的评分与缓存让结果稳定，不追新签名逻辑 |
| 远程路由表 | 上游靠 `lyric-rules.json` 热修域名 | v1 不做远程配置，域名写死在 `LyricCatalog`；要跟就加一个 64 KB 上限的 JSON 拉取，6 h 刷新 |
| AGPL-3.0 | 上游与其 Folia 资源是 AGPL，衍生作品要开源 | 这里的 4 个 Java 文件是按线上格式**重写**的独立实现（相同协议、相同常量，代码自有），不含上游代码与资源；若将来整体公开分发，仍需评估这一条 |
| TLS | 上游对 API 19 才装 TLS 1.2 socket factory；本项目 minSdk 24 | 未移植 `HttpCompat`，无需 |
| 版权 | 歌词属于词曲权利人，缓存是本地派生数据 | 缓存只存解析后的时间轴，随曲目键失效，不导出、不聚合 |
| 反爬 | 酷我/咪咕对无 UA、无 Referer 的请求返回空 | 已带 UA/Referer/Origin/Cookie（网易 `os=pc; appver=2.9.7`） |

---

## 10. 分阶段落地

**P0（本次已交付，可编译可测）**：`LyricTimeline` + `LyricCodecs` + `LyricCatalog`（4 家）+
`LyricTimelineProvider` + Dart 模型与面板 + `MediaAdapter` 8 行接线。产出：词级歌词在卡片与
停靠栏可用，六种编码可解，占位与卡死有闸门。

**P1（建议下一步，约 1 天）**：
- 把上游 `StuckLineDetector` 的三条规则搬到 Dart：单行文档、时长 3 倍偏差、播放器自身在推进
  而我们的行卡住 25 s → 退回播放器给的行级文本。规则常量已在 `LyricTimeline` 的同名文档里注出。
- 汽水/咪咕接入（咪咕解码器已在 `LyricCodecs.migu`，缺检索与路由）。
- 设置项：`estimatedKaraoke`、翻译开关、罗马音开关。

**P2（可选）**：从 `LyricEffectCatalog` 的 16 种里挑 3–5 种（karaoke/neon/sweep 这类只改颜色与
裁剪的），用 `CustomPainter` 复刻；3D/粒子类（orbit/flame/glitch）需要上游那套 276 KB 渲染器，
性价比低。

---

## 附录：不移植的部分与原因

| 上游能力 | 原因 |
|---|---|
| Folia 3D 场景 | 约 8 MB 资源 + 自建 GPU 管线，与 UNI 现有皮肤体系（`launcher_theme.dart` / `SurfaceStyle`）冲突 |
| 频谱音源 | UNI 已有 `docs/MUSIC_SPECTRUM_0_6_13.md` 的独立实现 |
| 更新器 / 社区 / FAQ 客户端 | UNI 有 `ota.i4o.xyz` 与自己的 OTA 流程 |
| 悬浮窗权限流程 | UNI 用 `GlobalDockService`，窗口模型不同 |
| `SessionChannelArbiter` | UNI 的 `MediaAdapter` 已按 `isOnlinePlayer(...)` 与蓝牙槽位做了等价仲裁 |
