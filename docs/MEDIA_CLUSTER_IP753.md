# 领克 05（IP753，192.168.22.198）媒体 / 仪表链路排查记录

> 车机：MSM8996 for arm64，user build，无 root。桌面：`xyz.i4o.uni.launcher`。
> 现象起点：仪表盘没有媒体卡片 / 没有歌名 / 没有封面，方控换歌无效。

## 1. 根因一：原车媒体中心被停用

`ecarx.xsf.mediacenter` 在禁用列表里（`pm list packages -d`），于是：

```
W ActivityManager: Unable to start service Intent { act=ecarx.xsf.MEDIA_CENTER_SERVICE
  cmp=ecarx.xsf.mediacenter/.MediaCenterService }: not found
I UNI/Media: [ANCHOR] media/oem-session fail reason=bind-refused component=ecarx.xsf.mediacenter
```

恢复：`adb shell pm enable ecarx.xsf.mediacenter`，之后立刻 `media/oem-session done action=bind bound=true`。

该服务的声明（`aapt2 dump xmltree`）：

```
E: service
  A: android:name="ecarx.xsf.mediacenter.MediaCenterService"
  A: android:permission="ecarx.oem.permission.OPENAPI_MEDIACENTER_PERMISSION"
  E: intent-filter  action = ecarx.xsf.MEDIA_CENTER_SERVICE
```

所以调用方必须持有 `ecarx.oem.permission.OPENAPI_MEDIACENTER_PERMISSION`（UNI 已放行，`granted=true`）。

## 2. 根因二：`OfficialMediaBridge` 的白名单挡掉了第三方播放器

`Sample.from()` 原来只放行蓝牙 / 网易云车机版 / QQ 音乐，别的播放器一律 `EMPTY`：

```java
if(!"com.android.bluetooth".equals(pkg)&&!"com.netease.cloudmusic.iot".equals(pkg)
   &&!"com.tencent.qqmusiccar".equals(pkg)&&!"com.tencent.qqmusic".equals(pkg))return EMPTY;
```

结果洛雪（`cn.toside.music.mobilegcx`）永远不注册，日志里只有：

```
I UNI/Media: 原车媒体跳过注册 running=true enabled=true available=false registered=false api=true apiReady=true
```

去掉白名单（非蓝牙一律按 `sourceType=6` 自定义源注册，和 HY 仪表方控助手同一套做法）之后：

```
I UNI/Media: 原车媒体取样 available=true playing=true source=cn.toside.music.mobilegcx title=草莓冰淇淋
I UNI/Media: 原车媒体注册结果 tag=UniOemMedia registered=true token=true sourceType=6
I UNI/Media: [ANCHOR] media/oem-playback done source=cn.toside.music.mobilegcx claimed=true
```

仪表随即出现歌名。

## 3. 根因三：仪表媒体通道缺签名权限

`DimInteraction.getMediaInteraction()` 抛 `SecurityException`，因为
`se.cevt.dimsupportservice` 的 `android.cevt.dimsupportservice.permission.DIM_MESSAGING`
是 `signature|privileged`。UNI 在本机被放行系统签名权限（`INJECT_EVENTS`、
`MEDIA_CONTENT_CONTROL` 都是 `granted=true`），所以声明 + 安装即放行：

```xml
<uses-permission android:name="android.cevt.dimsupportservice.permission.DIM_MESSAGING"/>
```

```
I UNI/Media: [ANCHOR] media/dim done mode=diminteraction callback=true
```

## 4. 仪表封面（已解决）

### 4.1 死路：会话路线

先把封面塞进 UNI 自己的 `MediaSession("UNI steering media bridge")` 的
`METADATA_KEY_ALBUM_ART`，并把会话标题临时改成 `…·UNI` 做探针 —— 仪表上标题
**完全没反映**，说明仪表不读我们这条会话，它读播放器自己的会话（洛雪的
`TrackPlayer`）。洛雪给的封面在系统里是 Bitmap，仪表那边不认。

结论：封面必须走**原车媒体中心**，不是 MediaSession。

### 4.2 真正的契约：`getArtwork()` 返回 `Uri`

编译期没有 ECARX SDK，方法名只能在运行时摸。注册成功后把 `IMusicPlaybackInfo`
的方法全打出来：

```
getTitle:String  getArtist:String  getAlbum:String
getArtwork:Uri   getNextArtwork:Uri  getPreviousArtwork:Uri
getLyric:Uri     getLyricContent:String  getCurrentLyricSentence:String
getMediaPath:Uri getDuration:long  getPlaybackStatus:int  getSourceType:int
getLoopMode:int  getLaunchIntent:PendingIntent getPlayingItemPositionInQueue:int
getRadioFrequency:String getRadioMode:int getRadioStationName:String
```

**关键：`getArtwork()` 是 `Uri`，不是位图。** 之前这一路返回 `null`，原车不是
「拿不到图」，而是把整个对象当无效 —— 连 `getTitle` 都不来问（所以日志里
`原车媒体问字段` 一条都没有，歌名一直是从洛雪会话里来的）。

现在返回真实 `content://` 之后，原车立刻把字段全问了一遍，并且真的把图取走：

```
原车媒体问字段 name=getArtwork type=Uri
封面 URI 已就绪 name=cover_2061302377.png title=内隐记忆 bytes=139889
原车媒体问字段 name=getPlaybackStatus / getLoopMode / getRadioMode / getLaunchIntent …
封面被读取 caller=com.ecarx.diagnostic name=cover_2061302377.png
```

### 4.3 实现

- `integration/ArtworkFileProvider.java`：只读暴露 `cache/artwork/`，`grantUriPermissions`，
  每次被读取都记 `caller`（UID→包名）——「谁来看封面」从此有据可查。
  manifest：`<provider … authorities="xyz.i4o.uni.launcher.artwork" exported="false" grantUriPermissions="true"/>`
- `OfficialMediaBridge`：`getArtwork/getNextArtwork/getPreviousArtwork` → `artworkUri()`；
  PNG 落盘（按最长边缩到 512px），对 `ecarx.xsf.mediacenter`、`se.cevt.dimsupportservice`、
  `ecarx.launcher3` 分别 `grantUriPermission`；缓存按 `标题+歌手+版本号` 命中，超过 24 个旧图自动清。
- 歌词同路：`getLyricContent` 直接返回文本，`getLyric` 返回 `lyric_<hash>.lrc` 的 URI
  （`ArtworkFileProvider.getType` 按后缀给 `text/plain`）。

### 4.4 上一首歌的图（坑）

两个来源都会让仪表挂着上一首的封面：

1. **缓存位图跨曲目复用**。`lastCover` 只是「上次解出来那张」，换歌时如果新曲目
   还没给图，它会被当成当前封面。修法：`coverKey(metadata)=标题|歌手|mediaId`，
   缓存图只在 `key.equals(lastCoverKey)` 时可用，否则退回中性占位图。
2. **每次 metadata 回调都让原车重取**。`MediaMetadata.getBitmap()` **每次都新建
   Bitmap**，所以任何以位图 identity 作 key 的做法都会每次写新文件、原车跟着反复
   下载同一张图。修法：`artworkVersion` 只在「换曲目」或「这首的封面才到」时 +1，
   文件名 = `cover_<hash(标题|歌手|版本)>.png`。

修完之后日志变成「一首歌一条」：

```
封面 URI 已就绪 … title=生活倒影  →  封面被读取 … cover_1622907269.png
封面 URI 已就绪 … title=许愿 (Live) bytes=1773   ← 播放器这首没图，给的是占位图
```

占位图：深色渐变 + 青色音符（256px），中性、不像报错。

### 4.5 还没做的

- `getNextArtwork` / `getPreviousArtwork` 现在指向当前这张，原车若做「下一首预览」会看到同一张图。
- 播放器没给封面时不会去外部曲库补图（`lastCover` 只覆盖同一首）。


## 5. 方控（方向盘按键）

原车输入通道放行清单（`UniSteeringKeys: granted=`）在放宽申请范围后拿到 39 个键：

```
granted=200085,200087,200088,210005,85,3,300001,300002,200003,200004,200005,200006,
200024,200025,210001…210010,300001,300002,300003,300005,300010,110001…110010
```

- 实体 HOME = VHAL 注入 `KEYCODE_HOME(3)`，走这条通道后可以接管（见 `docs/HOME_KEY.md`）。
- 方控换歌在这台车上按下时**没有任何键上报**（`UniSteeringKeys` 无输出），
  推测被原车音频路由吃掉；原车媒体中心恢复后需要重新验证——注册成
  `sourceType=6` 并 `requestPlay()` 抢到焦点时，原车应通过 `IMusicClient` 的
  `onNext/onPrevious` 回调把按键交给我们（`dispatch("next")` 已有日志
  `原车媒体透传播放控制`）。截至本记录，该回调一次都没触发。

## 6. 复现/诊断命令

```bash
adb logcat -G 8M                              # 车机每秒刷 VHAL，默认缓冲区会把证据冲掉
adb logcat -s UniSteeringKeys:V               # 放行清单 + 每个键首个码值
adb shell dumpsys package ecarx.xsf.mediacenter | grep -A4 "Service Resolver"
adb shell pm list packages -d                 # 谁被停用了
adb shell logcat -d | grep -E "media/(dim|oem-playback|oem-session)"
```
