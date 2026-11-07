# 歌词链路增补 2026-11：并发、变体、直连、新源、缓存策略、内嵌、偏移、探针、字形缓存

> **用途**：记录本轮对歌词获取链路的 9 项改造（对应参考 App `歌词伴侣` 经验清单的第 2–10 项，
> 第 1 项「远程规则表」按用户要求未做）。
> **对象**：`app/android/app/src/main/java/xyz/i4o/uni/launcher/integration/lyrics/*`、
> `integration/MediaAdapter.java`、`integration/display/*`、`app/lib/platform/lyric_tuning.dart`、
> `app/lib/widgets/lyric_tuning_panel.dart`。
> **约定**：行号为当前文件真实行号；未在设备上验证的结论标 `待确认`。
> **不含**：副屏窗口挂载细节（见 [05-副屏投射](interface/05-副屏投射.md)）、逐字编码格式（见
> [06-媒体与歌词](interface/06-媒体与歌词.md) §4）。

---

## 0. 一眼看全

| # | 能力 | 落地位置 | 一句话效果 |
|---|---|---|---|
| 2 | 多源并发 + 先给快的、再升级 | `LyricCatalog.load` `:281`、`POOL` `:63`、`UPGRADE` `:72`、`Upgrade` 回调 `:261`、`LyricTimelineProvider.request` `:152` | 六个源同时问，先到先显；慢的若更优（词级）再悄悄换掉 |
| 3 | 每曲偏移微调（设置里「关联的音乐播放器」下） | `LyricOffset.java`、`MediaAdapter.java:459-464`、`MainActivity` `lyricTuning`/`lyricTuningStatus`、`lib/widgets/lyric_tuning_panel.dart` | 全局 ±3 s + 单曲 ±3 s，卡片与投屏同时平移 |
| 4 | 查询变体（不只清洗一次） | `LyricCatalog.variants` `:394`、`fetch` `:431` | 原名→去括号→去副标题→去 feat/Live，最多 4 种拼法依次试 |
| 5 | 缓存三档策略 | `LyricCachePolicy.java`（`:53`/`:85`/`:118`）、启动清扫 `MainActivity.onCreate` | 永久 / 30 天未用 / 按容量，目录仍是 `files/media-lyrics` 与 `files/lyric-timeline` |
| 6 | 媒体 ID 直连，跳过搜索 | `LyricCatalog.direct` `:453`、`neteaseById` `:522`、`qqByMid` `:619`、`kuwoById` `:705`；`MediaAdapter.mediaId` `:516` | 同一曲库的 `MEDIA_ID` 直接换歌词，省一次搜索往返 |
| 7 | 补两个源：汽水音乐、咪咕音乐 | `LyricCatalog.soda` `:754` / `sodaPage` `:801`；`migu` `:906` / `miguSign` `:982` | provider 顺序变成 6 个；两者都是最后兜底 |
| 8 | 音频文件内嵌歌词 | `EmbeddedLyricReader.java:37`、`MediaAdapter.localLyrics` `:527` / `audioPath` `:538` | 本地文件自带歌词优先于任何在线曲库，离线可用 |
| 9 | 投射窗口健康探针 | `ClusterLyricsService.pump` `:381`、`healthy` `:410`、心跳重绘 `:397` | 窗口被系统摘掉或变成孤儿时自动重挂，不再「状态显示已开启、屏上什么都没有」 |
| 10 | 字形缓存 + 复杂脚本 shaping | `ClusterLyricsView.width` `:277`、`simple` `:301`、`fit` `:323`、`ADVANCE_LIMIT` `:274` | 常用字宽按「字号+码位」缓存；阿拉伯/印度/泰/希伯来等仍走系统整形 |

---

## 1. 多源并发 + 先给快的、再升级（第 2 项）

### 1.1 并发怎么排

```java
// LyricCatalog.java:281
public Result load(String title, String artist, long durationMs, String owner,
                   String mediaId, Upgrade upgrade)
```

1. 磁盘缓存命中 → 直接返回（带 `score`，见 §1.3），不再发任何请求（`:284-289`）。
2. 否则把 `plan(owner)` 里的**每个** provider 提交到 `POOL`（6 个 daemon 线程，线程名
   `lyric-fetch`，`:63-71`）。每个任务内部先试直连（§5），再试变体搜索（§2）。
3. 主线程侧用一个 `LinkedBlockingQueue<Result>` 收结果，最多等 `FIRST_WAIT_MS = 2600 ms`
   （`:59`）：期间只要有任一 `score > 0` 就立刻返回；全部落空或超时才返回空。
4. 若还有任务没回来（`answered < total`），把「继续等」交给 `UPGRADE` 单线程执行器
   （`:72-80`），窗口 `UPGRADE_WINDOW_MS = 6000 ms`（`:61`）；期间只要有更高分的文档，
   就通过 `Upgrade.onBetter`（`:261`）回调出去。

调用方（`LyricTimelineProvider.request` `:152-176`）拿到的回调做一件事：`memoryPut` 把更优
文档写进内存缓存，并标 `leadMerged=true`（`:167-168`），于是**下一次快照自然就是卡拉 OK**，
调用方不需要再问一次。

### 1.2 为什么不是「最短超时 + 串行降级」

串行链路里第一个源超时就是 3 s 连接 + 4 s 读取（`CONNECT_MS`/`READ_MS`，`:55-56`），四个源
最坏 28 s；而列表页只等 2.6 s 就给结论。并发把「最坏情况」换成「最快一个源的时间」，代价是
冷曲目多打 3–5 个请求 —— 命中缓存后一次都不打。

### 1.3 分数与替换规则

| 项 | 规则 | 行号 |
|---|---|---|
| `Result.score` | `timeline.usable() ? max(1, qualityScore + 1) : 0` | `:1120-1125` |
| 为什么 +1 | `qualityScore()` 只数词级/翻译/罗马音，纯行级文档得 0，会被误判成「没拿到」 | `LyricTimeline.java:446-454` |
| 升级条件 | `betterThan(other)`：`score > other.score`，或同分但对方为空 | `:1127-1131` |
| 缓存命中分数 | 用的是同一个 `qualityScore + 1`（`cached` 路径 `:284-289`） | — |

> 旧文档 [06-媒体与歌词](interface/06-媒体与歌词.md) §5.3 里写的「`quality` 只写不读、没有
> 高分替换低分」在本轮之后**已过时**：替换逻辑就是 §1.1 的升级回调。

---

## 2. 查询变体（第 4 项）

```java
// LyricCatalog.java:394
static List<String[]> variants(String title, String artist)
```

| 变体 | 例子 | 出处 |
|---|---|---|
| 原始 | `飞 (Live)` / `某某` | `:396` |
| `strip()` 之后 | `飞` / `某某` | `:397-398`（`strip` 见 `:149` 附近） |
| 截到副标题之前 | `飞`、`某某 - 电视剧《…》主题曲` → `某某` | `:399-400`、`subtitleCut` `:409-421` |
| 去掉 feat/Live/伴奏 尾巴 | `某某 feat. 谁` → `某某` | `:401-404` |

- 去重按 `normalize(名)|normalize(歌手)`（`:423-429`），所以 `飞 (Live)` 与 `飞` 同时存在时
  第二个不会重复请求；最多 4 条。
- `fetch(provider, …)`（`:431-451`）按顺序试变体，**拿到词级文档立刻返回**；只拿到行级则记住
  最高分继续试下一种拼法。

---

## 3. 缓存三档策略（第 5 项）

`LyricCachePolicy`（`app/android/.../integration/lyrics/LyricCachePolicy.java`）：

| 档位 | 常量 | 行为 | 行号 |
|---|---|---|---|
| 30 天未用即清理（默认） | `Days30 = "30d"` | `lastModified < now - 30 d` 的文件删除 | `:97-116` |
| 永久保留 | `FOREVER = "forever"` | 直接返回 0，不碰目录 | `:99` |
| 按容量 | `CAPACITY = "capacity"` | 按 `lastModified` 从旧到新删到 ≤ `limitMb` | `:100-102`、`:118-146` |

- 「已被使用」的判定用文件的 `lastModified`：缓存命中时 `LyricCatalog.cached()` 会
  `file.setLastModified(now)`（`:200-206`），所以天天听的歌永远不会被 30 天档清掉。
- 清扫目录固定为 `files/media-lyrics`（行级文本通道）与 `files/lyric-timeline`（时间轴通道），
  见 `directories()` `:75-82`。
- 触发点：`MainActivity.onCreate` 起一个 `lyric-cache-sweep` 线程调 `sweep(this, now)`，主线程
  零成本。
- 容量档上限默认 24 MB、范围 1–512（`:53-59`）。

---

## 4. 媒体 ID 直连（第 6 项）

`MediaAdapter.mediaId(metadata)`（`:516-525`）读
`MediaMetadata.METADATA_KEY_MEDIA_ID`，上限 64 字符，经
`LyricTimelineProvider.resolve(..., mediaId)`（`:113-114`）传给 `LyricCatalog.load`，再由
`direct()`（`:453-478`）分发：

| provider | 接受形态 | 走的接口 |
|---|---|---|
| `netease` | 纯数字 songId | `eapi/song/lyric/v1`（`neteaseById` `:522`） |
| `qqmusic` | 10–16 位字母数字 songmid | `fcg_query_lyric_new.fcg`（`qqByMid` `:619`） |
| `kuwo` | `MUSIC_<rid>` 或纯数字 rid | 词级 `mlyric.kuwo.cn` + 行级 `songinfoandlrc`（`kuwoById` `:705`） |
| 其它 | — | 走搜索（`kugou` 的 hash 无法从 session 推出） |

直连只在**同一曲库**下有意义（NetEase 的 id 对 QQ 毫无意义），所以 `plan()` 仍把播放来源的
曲库排第一（`:368-392`），直连失败即退回搜索。

---

## 5. 补两个源（第 7 项）

`ORDER = {NETEASE, QQ, KUGOU, KUWO, SODA, MIGU}`（`:53`），两者都排在最后，只在四大源全落空
时才花时间。

### 5.1 汽水音乐（`soda`）

| 步骤 | 地址 / 解析 | 行号 |
|---|---|---|
| 搜索 | `GET https://api.qishui.com/luna/pc/search/track?q=…&cursor=0&search_method=input&aid=386088&device_platform=web&channel=pc_web`，Referer `https://www.qishui.com/` | `:762-766` |
| 取 id | `result_groups[].data[].entity.track{id,name,artists[],duration}`，用 `score()` 挑 | `:767-789` |
| 歌词 | `GET https://www.qishui.com/share/track?track_id=<id>`，从 HTML 里截 `window._ROUTER_DATA` 的花括号块 | `:791-793`、`matchingBrace` `:872-892` |
| 句级解析 | `loaderData.track_page.audioWithLyricsOption.lyrics.sentences[]` 的 `startMs/endMs/text/translation/words[]` | `sodaPage` `:801-860` |
| 编码 | 行级 LRC + 增强 LRC 双份，交给 `LyricTimeline.parse` | `:851-854` |

### 5.2 咪咕音乐（`migu`）

| 步骤 | 地址 / 解析 | 行号 |
|---|---|---|
| 请求头 | `uiVersion: A_music_3.6.1`、`deviceId: 963B7AA0D21511ED807EE5846EC87D20`、`timestamp`、`sign`、`channel: 0146921` | `signed` `:1013-1036`、`MIGU_DEVICE` `:1041` |
| 签名 | `md5(text + SALT + timestamp)` 小写 hex；`SALT` 是参考实现的公开常量（102 字符，含 device id） | `miguSign` `:1010-1012`、`MIGU_SALT` `:1038-1040` |
| 搜索 | `GET https://jadeite.migu.cn/music_search/v3/search/searchAll?…&sid=USS`，`code` 必须 `000000` | `miguSearch` `:913-958` |
| 时长归一 | 搜索结果的 `duration` 是**秒**（如 256），`< 20000` 时 ×1000 再进 `score()` | `miguDuration` `:960-962` |
| 取 id | `resultList[][]{contentId,copyrightId,name,singerList[],duration}` | `:930-956` |
| 歌词元数据 | `POST https://c.musicapp.migu.cn/MIGUM2.0/v1.0/content/resourceinfo.do?resourceType=2`，body `resourceId=<contentId>`（失败再试 `copyrightId`）→ `resource[0].{mrcUrl,lrcUrl,trcUrl}` | `miguLyric` `:980-998`、`miguResource` `:1000-1008` |
| 词级文档 | `mrcUrl` → `LyricCodecs.mrcText`（XXTEA 解密）→ `LyricCodecs.miguToEnhanced` → 增强 LRC | `LyricCodecs.java:261-325`、`:328-365` |
| 兜底 | `mrcUrl` 缺失或容器里一个词标记都没有 → 行级 `lrcUrl`；`trcUrl` 作翻译 | `:990-997` |

MRC 解码细节（复用仓库里早先写过但一直没接线的 `LyricCodecs.migu`，本轮修好并接上）：

| 环节 | 规则 | 行号 |
|---|---|---|
| 密钥 | 9 个 64 位常量，来自参考实现 dex 的 `array-data` 原文（已逐字节核对） | `:285-293` |
| 混合函数 | 标准 XXTEA `MX(y, z, sum, key) = ((sum^y)+(key^z)) ^ (((z>>5)^(y<<2)) + ((y>>3)^(z<<4)))` | `mix` `:315-317` |
| 轮数 | `(52 / n + 6)`，`sum` 从 `轮数 × DELTA` 递减 | `:294-311` |
| 读入 | 每 16 个十六进制字符 = 一个 `long`（`BigInteger(…,16).longValue()`） | `:285-293` |
| 输出 | 小端 `UTF-16LE`，去掉 `\u0000` 与 BOM | `mrcText` `:269-325` |
| 行/词格式 | `[start,dur]` 切行、`(start,dur)` 切词 → `(start,dur,0)` | `miguToEnhanced` `:328-365` |

> **时间戳是毫秒**：真实载荷 `[2045,649](2045,499,0)作(2544,50,0)词(2594,50,0)：唐(2644,50,0)恬`，
> 每个音节 50 ms 级 —— 词级高亮在咪咕这条线上是真实数据，不是插值。

> **三处与参考实现不同，都是修 bug**：
> 1. `miguToEnhanced` 不按 `\n` 切行。真实 MRC 的字段分隔符是 `\r\n` 混 `\u2028`，前面还挂着
>    `[ti:]`/`[ar:]`；按行切 + `^…$` 正则会把整个文档判成「没有词标记」，直接退化成行级。
> 2. 词标记是**跟在音节后面**的（`起(0,0)风(0,0)`）。参考实现按「标记在前」解析，每行第一个字
>    被整段丢掉（`起风了` → `风了`）；这里按载荷实际形态解析。
> 3. `resourceinfo.do` 只认 `contentId`；用 `copyrightId` 会拿到 `code=000000` 但 `resource=[]`
>    （看着像「这歌没歌词」）。所以两个都试，`contentId` 优先。

### 5.3 酷狗（`kugou`）与参考实现的差异

| 环节 | 参考实现（dex 反汇编） | UNI | 判定 |
|---|---|---|---|
| 搜索 | `song_search_v2?keyword=<title+空格+artist>&page=1&pagesize=10&userid=-1&clientver=&platform=WebFilter` | 同 `keyword`，多带 `filter=2&iscorrection=1&privilege_filter=0` | 等价，多给的参数被忽略 |
| 取 hash | `data.lists[].{SongName,SingerName,Duration,FileHash}`，`matchScore≥100` 取第一条 | `score() ≥ ACCEPT` 取最高，`FileHash` | UNI 阈值是另一套量纲，不照抄 |
| 候选 | `GET https://lyrics.kugou.com/search?ver=1&man=yes&client=pc&hash=<hash>` → `candidates[0].{id,accesskey}` | 同（本轮去掉了多带的 `keyword=`/`duration=`） | 已对齐 |
| 下载 | `GET https://lyrics.kugou.com/download?ver=1&client=pc&id=&accesskey=&fmt=krc&charset=utf8` → `content` | 同，`LyricCodecs.kugou` 解 KRC；空则退 `fmt=lrc` | 已对齐 |
| 直连 | 允许 `netease/soda/kuwo/migu` 用 mediaId，**kugou 不在列**（session 里拿不到 `FileHash`） | 同 | 一致 |

> **本机实测（2026-11）**：
> - 咪咕：`deviceId` 用对之后搜索返回 `code=000000`（87 条），整条链路 `孤勇者/陈奕迅` →
>   68 行 / 词级 / `quality=272`，`起风了/买辣椒也用券` → 72 行 / 词级 / `quality=288`；
>   不存在的歌名 → 0 行（正确拒绝）。
> - 汽水：`GET api.qishui.com/luna/pc/search/track` 仍然 `HTTP 200`、`Content-Length: 0`。
>   ⚠未验证：需要国内出口或带 `aid`/cookie 的浏览器上下文，本轮没有拿到可解析的响应，
>   所以 `soda` 保持「失败即让位」。

---

## 6. 音频文件内嵌歌词（第 8 项）

`EmbeddedLyricReader.read(File)`（`:37-52`）读文件头 ≤ 2 MB（`MAX_SCAN` `:30`），按魔数分派：

| 容器 | 读取内容 | 行号 |
|---|---|---|
| ID3v2（MP3） | `USLT`、`SYLT`，其余帧里 `TXXX`/`COMM` 作兜底；支持 v2.3 大端长度与 v2.4 syncsafe 长度 | `id3` `:78-116` |
| FLAC | `VORBIS_COMMENT` 块（type 4）里的 `LYRICS=` / `UNSYNCEDLYRICS=` | `flac` `:130-146` |
| Ogg Vorbis | 在 comment 包里顺序找 `LYRICS=` | `ogg` `:148-150`、`vorbisComment` `:152-166` |
| MP4 / M4A | `©lyr` atom 里的 `data` 载荷 | `mp4` `:170-182` |

- 文本判定 `looksLikeLyrics`（`:191-207`）：有时间戳，或 ≥3 行且 ≥12 字符 —— 避免把
  `COMM` 里的评论当歌词。
- ID3 v2.3 的编码字节 0 常被唱片抓轨写成 GBK，`charsetFor` 对 `0` 回退 GBK（`:118-128`）。
- 接线：`MediaAdapter.snapshot()` 先 `readLyrics`（会话给的文本），空则 `localLyrics(...)`
  （`:439-446`、`:527-537`），命中时 `lyricsSource = "embedded"`；同一路径结果按
  `LinkedHashMap` 缓存 8 条（`:515`）。

---

## 7. 每曲偏移微调（第 3 项）

### 7.1 语义

| 项 | 规则 | 行号 |
|---|---|---|
| 范围 | ±`LIMIT_MS = 3000` ms，超出即夹紧 | `LyricOffset.java:20`、`:31-33` |
| 全局 | `globalMs`，作用于所有曲目 | `:57-72` |
| 单曲 | 键 `title|artist`（小写去空格）→ 增量 | `:37-45`、`:110-117` |
| 生效值 | `clamp(global + track)` | `:37-45` |
| 正负含义 | 正数让歌词**更晚**出现，负数更早 | UI 文案 `lyric_tuning_panel.dart:74-79` |
| 存储 | `shared_prefs/lyric-offset.xml`：`globalMs`、`track:<key>` | `:22-25`、`:79-108` |

应用点在**播放时钟**而不是文档：`MediaAdapter.snapshot()` 里

```java
// MediaAdapter.java:459
long castPosition = Math.max(0, position(p) + LyricOffset.forTrack(title, artist));
```

这一份 `castPosition` 同时喂给 `LyricCast.publish`（`:460-461`）和快照的
`positionMs`（`:464`）。卡片与投屏读的都是它，所以改一次偏移，两边一起平移 —— 不会出现
「桌面准、副屏差 200 ms」这种最难查的偏差。

### 7.2 设置界面

位置：桌面设置 → **导航与媒体** → 右列「关联的音乐播放器」下方（用户明确要求放在这里），
组件 `LyricTuningPanel`（`app/lib/widgets/lyric_tuning_panel.dart`），插在
`integration_settings.dart:119`。

| 控件 | 行为 | 通道 |
|---|---|---|
| 全局偏移 `−/+`（每 100 ms） | `LyricOffset.save(global)` 后立即回显 | `lyricTuning` → `LyricOffset.save` |
| 当前曲目微调 `−/+` | 只写当前 `LyricCast.state()` 的 title/artist | 同上 |
| 刷新按钮 | 换曲后重新取「当前曲目」 | `lyricTuningStatus` |
| 歌词缓存 | 三档下拉；选「按容量」再出现 8/16/24/48/96 MB | `lyricCache` |
| 生效提示 | `当前生效 X.XXs（正数让歌词更晚…）微调只作用于当前曲目「…」` | 读 `effectiveMs` |

原生侧返回结构（`MainActivity` → `lyricTuningStatus`）：
`{globalMs, trackMs, title, artist, policy, limitMb}`，`title/artist` 取自 `LyricCast.state()`。

---

## 8. 投射窗口健康探针（第 9 项）

`ClusterLyricsService.pump()`（`:381-404`）每 700 ms（`FEED_MS` `:77`）做三件事：

| 动作 | 条件 | 行号 |
|---|---|---|
| 拉一次媒体快照 | 始终 | `:382-385` |
| 状态看门狗 | `LyricCast.state() != lastDrawn` → `startFrames()` | `:396` |
| 心跳重绘 | 每 2 次 pump（≈1.4 s）→ `startFrames()` | `:397` |
| 附着探针（节流 5 s） | `!healthy(panel)` → `reattach("health:<原因>")`，`healthRetries++` | `:398-402` |

`healthy(view)` = `view.isAttachedToWindow() && view.getParent() != null`（`:410-416`），异常也
算不健康（`:413-415`）。

- 为什么需要：车机重连、副屏热插、系统静默收回悬浮窗之后，对象里仍握着一个「活着但画在死
  WindowManager 上」的 view —— 状态页写着已开启，屏上什么都没有，日志里也什么都没有。
- 为什么节流 5 s：窗口若确实无法附着（无副屏、无悬浮权限），每帧重挂会把 WMS 打满。
- 心跳重绘解决的是另一件事：换曲瞬间新状态**没有** timeline，帧循环按设计停在此处，于是上一
  首的歌词会一直留在玻璃上，直到新文档到达（实测冷启动首曲可停留数秒）。1.4 s 一次重绘让
  面板立刻改成「正在获取歌词」，代价可忽略。

---

## 9. 字形缓存 + 复杂脚本 shaping（第 10 项）

`ClusterLyricsView`（`app/android/.../integration/display/ClusterLyricsView.java`）：

| 项 | 规则 | 行号 |
|---|---|---|
| 缓存键 | `(round(size*4) << 32) \| codePoint` | `:289-291` |
| 缓存内容 | 单码位 `paint.measureText(char)` 的宽度 | `:292-297` |
| 上限 | `ADVANCE_LIMIT = 4096`，超了整体清空（不是逐条淘汰，避免复杂度） | `:274`、`:295-296` |
| 简单文本 | 逐码位累加缓存宽度 | `width` `:277-287` |
| 复杂文本 | 直接 `paint.measureText(整串)`，走系统整形 | `:279`、`simple` `:301-321` |
| 省略号 | 简单文本用缓存宽度自己截断 + `…`；复杂文本仍用 `TextUtils.ellipsize` | `fit` `:323-346` |

`simple()` 排斥的区间：希伯来 `0590-05FF`、阿拉伯/叙利亚 `0600-08FF`、
天城文…僧伽罗 `0900-0DFF`、泰/老挝 `0E00-0EFF`、缅甸 `1000-109F`、高棉 `1780-17FF`、
组合附加符 `1AB0-1AFF`、表现形式 `FB1D-FEFF`，以及 `NON_SPACING_MARK` /
`COMBINING_SPACING_MARK` 两类字符（`:305-320`）。中文/日文/韩文/拉丁都落在「简单」一侧，
是绝大多数场景。

一帧里同一行最多被量三次（截断判断、居中、卡拉 OK 填充前缀），30 fps × 3 行 × 3 次 = 270 次
整串测量/秒；缓存后每个新字号只量每字一次。

---

## 10. 验证

### 10.1 单元测试（离线，`_apk\junit-srcs.txt` 编译 + JUnitCore 运行）

`app/android/app/src/test/java/.../lyrics/LyricSourcesTest.java` 新增 15 条，覆盖：

| 测试 | 断言要点 |
|---|---|
| `theOwningCatalogueIsAskedFirstAndIsNotAskedTwice` | `plan("com.tencent.qqmusic")[0] == qqmusic`，且列表不重复 |
| `queryVariantsGoFromSpecificToForgiving` | 原名在首位、`飞 (Live)` 能退到 `飞`、≤4 条 |
| `duplicateSpellingsAreNotTriedTwice` | 同名同歌手只 1 条 |
| `aWordTimedDocumentUpgradesAPlainOne` | 词级 > 行级；空结果不覆盖命中 |
| `aCacheHitKeepsItsScore` | 分数 = `qualityScore + 1` |
| `miguSignatureIsStableForAGivenTimestamp` | 同参同值、32 位、时间戳变化即变 |
| `aSodaSharePageYieldsLinesWordsAndTranslation` | 句级文本/翻译/词级都在；无 text 的句子借 words |
| `aSharePageWithoutLyricsIsAMiss` | 三种残缺页都返回空 |
| `sodaAndMiguAreKnownCatalogueOwners` | 包名映射 + 中文 label |
| `offsetIsClampedAndPerTrackIsAdditive` | 夹紧、全局+单曲叠加、清空后归零 |
| `capacityPolicyTrimsTheOldestFilesFirst` | 1200 B / 700 B 上限 → 删 2 留最新 |
| `foreverPolicyNeverDeletesAnything` | mtime=0 也不删 |
| `aFlacCommentCarriesItsLyrics` | 合成 FLAC 头 → 读出 `[00:01.00]` 开头文本 |
| `aFileWithoutLyricsReadsAsEmpty` | 全零 MP3、null 都返回空 |

运行结果：**`OK (78 tests)`**（原 63 + 新增 15）。

### 10.2 静态与 Flutter

| 检查 | 结果 |
|---|---|
| `javac`（`android.jar` 优先，JUnit 用 `json` 优先） | 0 错误 |
| `flutter analyze lib test` | `No issues found!` |
| `flutter test` | `446 tests, All tests passed!` |
| `flutter build apk --debug` / `--release` | 均成功（release 27.6 MB） |

### 10.3 设备（LDPlayer 9，Android 9，1920×1080，`emulator-5554`）

| 步骤 | 观察 | 证据 |
|---|---|---|
| 设置页「导航与媒体」 | 「歌词偏移与缓存」出现在「关联的音乐播放器」正下方，显示 `当前生效 0.00s`、当前曲目「一起」、缓存档位 | `_apk/it10-s3.png` |
| 点 2 次全局 `+` | 界面变 `+200` / `当前生效 0.20s`；`shared_prefs/lyric-offset.xml` 出现 `globalMs=200` | `_apk/it10-s9.png` |
| 缓存下拉选「按容量清理」 | 界面出现「容量上限 24 MB」；`shared_prefs/lyric-cache.xml` 出现 `policy=capacity, limitMb=24` | `_apk/it10-s12.png` |
| 恢复默认 | `globalMs=0`；删 `lyric-cache.xml` 后回落到 30 天档 | prefs dump |
| 清空两个缓存目录后重启 + 跳曲 | 第 1 张（0.8 s）卡片还是「当前音源未提供歌词」，第 2 张（≈2.4 s）卡片与投屏已是同一份歌词并同步高亮 | `_apk/cold-t1.png`、`_apk/cold-t2.png` |

`待确认`：升级回调（行级→词级替换）在设备上没有肉眼可辨的对照画面 —— 它只在两个源先后给出
不同质量文档时触发，播放列表里恰好没有这种曲目。该项由
`aWordTimedDocumentUpgradesAPlainOne` + `request()` 的回调接线（`LyricTimelineProvider.java:161-169`）
保障。

---

## 11. 已知边界

1. **汽水/咪咕在本机网络下取不到数据**（§5 实测）。它们不阻塞任何东西：并发竞速里超时就让位。
2. **咪咕没有词级**：只接了 `lrcUrl`（行级）。MRC 解码器未移植。
3. **直连只在同曲库生效**：`kugou` 需要 FileHash，session 的 `MEDIA_ID` 给不出来。
4. **偏移按 `title|artist` 记忆**：同名不同版本（Live/录音室）共用一个键，因为它们常共用
   `title|artist|seconds` 之外的同一文本。
5. **字形缓存不做 LRU**：超过 4096 条整体清空，代价是重建一轮（每字一次 measure）。

---

## 12. 修「歌词总是显示上一首的」

现场现象：切歌后卡片上的词还是上一首的，一直不换。根因不在取词，而在**卡片判定「文档有没有变」**。

`LyricsView.refresh()` 原来用一个「形状签名」判断要不要重建歌词对象：

```dart
final next = timeline.lines.isEmpty
    ? raw
    : 'T${timeline.lines.length}@${timeline.lines.first.timeMs}';
final changed = payload != next;   // 只有 changed 才重建 lyrics
```

签名只包含**行数**和**首行时间**，不含歌名。两首歌的 LRC 都以 `[00:00]作词：…` 开头、行数又恰好相同时
（中文流行歌极常见，40–60 行区间撞行数是常态），签名完全一致 → `changed=false` → `lyrics` 保持上一首，
`active` 也不重置，界面于是永久停在上一首的词上。这也解释了两件事：切歌瞬间标题/封面都是对的、
只有词不对；重新进页面能恢复（组件重建后签名重算）。

修法：签名带上曲目与文档身份，`title|artist|lyricsSource|lyricTimelineLabel|行数@首行-末行:首末行文本哈希`
（`app/lib/widgets/lyrics_view.dart:98`）。回归测试
`app/test/media_motion_test.dart` 的「a track change replaces the document even when the shapes match」
用两首同形状不同词的文档复现：改回旧签名时该测试失败，改后通过。

同一类问题在原生侧也补了一道闸：`LyricTimelineProvider.Result` 现在带上 `key`
（`LyricTimelineProvider.java:68`, `:287`），`MediaAdapter.snapshot()` 在发布前比对
`LyricCatalog.key(title,artist,duration)` 与文档的 `key`，不一致就丢弃文档并发
`LYRIC lyric/mismatch`（`MediaAdapter.java:561-566`）。缓存层本来是按 key 取值的，这道闸防的是
「迟到的一笔应答」或「被保留的旧曲目元数据」把别人的词送上屏。

> 若现场仍然出现，抓一条日志过滤 `LYRIC`：`lyric/mismatch` 说明是文档串曲（已拦截，会打 want/got），
> 没有这条而词仍不换，则是 `LyricsView` 之外的消费者（例如 `lyricLine` 直通路径）在画。

---

## 本文依据

- 源码：`LyricCatalog.java`（`:53` ORDER、`:281` load 并发、`:394` variants、`:453` direct、
  `:754` soda、`:906` migu、`:1127` betterThan）、`LyricTimelineProvider.java`（`:113` mediaId
  重载、`:161-169` 升级回调）、`MediaAdapter.java`（`:439-446` 内嵌、`:451` resolve 带 mediaId、
  `:459-464` 偏移入时钟、`:516-548` mediaId/localLyrics/audioPath）、`LyricOffset.java`、
  `LyricCachePolicy.java`、`EmbeddedLyricReader.java`、`ClusterLyricsService.java`
  （`:381-416` pump/healthy）、`ClusterLyricsView.java`（`:274-346` 字形缓存）。
- Dart：`app/lib/platform/lyric_tuning.dart`、`app/lib/widgets/lyric_tuning_panel.dart`、
  `app/lib/widgets/integration_settings.dart:119`。
- 测试：`LyricSourcesTest.java`（15 条）、`LyricTimelineTest.java`、`LyricCastTest.java`。
- 参考实现：`_apk/jadx/sources/com/zuoqirun/lyricscompanion/` 的 `MultiSourceLyricClient.java`
  （`:34-36` 6 线程池 + 单线程升级、`:559-572` 优先级、`:555-557` 直连）、`LyricSourceRules.java`、
  `SodaLyricClient.java`（`:53`/`:122-166`）、`MiguLyricClient.java`（`:46-53` 签名、`:133-155`
  resourceinfo）、`LyricCache.java`（三档策略）、`EmbeddedLyricReader.java`、`LyricGlyphCache.java`。
- 设备截图：`_apk/it10-s3.png`、`it10-s9.png`、`it10-s12.png`、`cold-t1.png`、`cold-t2.png`、
  `cold-t4.png`。
