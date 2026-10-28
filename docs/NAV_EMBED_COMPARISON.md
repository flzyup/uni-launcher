# 导航 App 窗口嵌入：君君桌面 vs UNI桌面，以及更优解

> 只讨论一件事：**把导航 App 的窗口嵌进桌面自己的界面（卡片/浮窗）里**。
> 与"投仪表"无关（那是另一条链路：君君桌面用 ecarx `DimInteraction.setPresentationToDimSwitch` 让高德自己投到仪表；UNI桌面目前没做。本文件不再涉及。）
>
> 样本
> - **君君桌面** `com.ecarx.qq.tool` 1.0.01280：原生 Java，`sharedUserId="android.uid.system"`，platform 签名，`minSdk 18 / compileSdk=targetSdk 29`（Android 10 一档）
> - **UNI桌面** `xyz.i4o.uni.launcher`：Flutter + 原生适配层，领克 05 IP753 / 领克 06 E02（Android 9）

---

## 0. 结论先行

| 项 | 君君桌面 | UNI桌面 |
|---|---|---|
| 嵌入用的原语 | **`android.app.ActivityView`**（框架自带的"应用嵌入容器"） | **自建 `VirtualDisplay` + Flutter `SurfaceTexture`** |
| 画面怎么回到桌面 | ActivityView 内部的 `SurfaceView`（独立图层） | 虚拟屏直接画进 Flutter 纹理，由 Flutter 合成 |
| 谁启动 App | `ActivityView.startActivity(PendingIntent, options)` | `startActivity(intent, setLaunchDisplayId(vdId))`，已在跑就 `moveStackToDisplay` |
| 谁转发触摸 | 自己铺 `touchView` + `InputManager.injectInputEvent` | `InputManager.createInputForwarder(vdId).forwardEvent()` |
| 名字陷阱 | 类叫 `PipManager` / `PIP_*`，但**不是系统画中画** | 无 |
| 谁更优 | 要嵌**任意 App 完整界面**（输入法/对话框/复杂层级）→ ActivityView 更省事 | 要嵌**一块实时地图**且要圆角/动画/换页 → 纹理方案更干净 |

**一句话**：君君桌面把窗口托管给系统，然后跟**图层和输入规则**搏斗；UNI桌面自己当宿主，把窗口变成一张**纹理**，跟窗口系统解耦。

---

## 1. 君君桌面：`ActivityView` 嵌入拆解

### 1.1 卡片长什么样

布局 `card_map`（ViewBinding `CardMapBinding`），桌面同时存在两张：`mapCard`、`mapCard2`（`ActivityMainBinding.java:33-34`）。

```
CardView（圆角由 CardView.setRadius + setClipToOutline 提供）
└─ FrameLayout  cardMap.getRoot()
   └─ FrameLayout  R.id.pipContainer   ← ActivityView 的宿主容器（运行时动态 addView）
      ├─ ActivityView（RoundMapActivityView / PipVdActivityView）
      ├─ touchView（透明手势层，盖在 ActivityView 上）
      ├─ loadOverlay / resizeCover（遮黑帧）
      └─ pipDotGroup / mapPlaceholder（指示点、占位提示）
```

另外 `FloatWindows`（51 KB）用同一套原语做**浮窗**（`new ActivityView(mainActivity, null, 0)`），所以"嵌入导航窗口"在君君桌面有两个宿主：桌面卡片 和 桌面浮窗。

### 1.2 `ActivityView` 是什么（从它反射的私有成员就能反推）

君君桌面反射的字段/方法：

| 反射目标 | 说明 |
|---|---|
| `ActivityView.mSurfaceView` | 内部是一块 **SurfaceView** —— 嵌入画面是独立图层，不跟普通 View 一起绘制 |
| `ActivityView.mVirtualDisplay` / `getVirtualDisplay()` | 内部创建了一块 **VirtualDisplay**，App 跑在这块虚拟屏上 |
| `ActivityView.getVirtualDisplayId()` | 用它给 `MotionEvent.setDisplayId(...)`，把触摸投进那块屏 |
| `ActivityView.cleanTapExcludeRegion()` 等 | 内部维护 **tap-exclude region**：这块区域内的触摸不转发给嵌入 App，留给宿主 |

结论（也是这套方案的全部约束来源）：
- 一个 `ActivityView` = 一块虚拟屏 = 一个 App，**不能一屏多 App**；
- 画面走 SurfaceView，**是独立图层**，所以圆角、层序、被自家 UI 遮挡都要单独处理；
- 输入走内部 forwarder，宿主可以"挖洞"排除自己的 UI 区域；
- API 29+ 才有这个类。

### 1.3 君君桌面的完整驱动流程（11 步）

| # | 动作 | 位置 |
|---|---|---|
| 1 | 从 `pipContainer` 取容器，`releaseActivityView(pkg)` 先清旧实例 | `PipManager.smali:4855` |
| 2 | 按设备分支造实例：mdpi → `PipVdActivityView`；否则 → `RoundMapActivityView`（都 `extends ActivityView`） | `PipManager.smali:4882-4898` |
| 3 | 反射拿 `mSurfaceView`，给它挂 `OnLayoutChangeListener` + `SurfaceHolder.Callback`（surface 尺寸/创建销毁是几何同步的触发点） | `PipManager.smali:4902-4922` |
| 4 | `activityView.setCallback(StateCallback)`：`onActivityViewReady` 之后才允许启动；`onActivityViewDestroyed` 清状态 | `PipManager.java:166-244` |
| 5 | 解析启动 Intent（`getLaunchIntent(pkg)`，无则 `showPlaceholder("未安装: pkg")`） | `PipManager.smali:4834-4848` |
| 6 | 启动：`PendingIntent.getActivity(..., FLAG_UPDATE_CURRENT\|FLAG_IMMUTABLE)` + `activityView.startActivity(pi, ActivityOptions.makeCustomAnimation(ctx,0,0))`；失败回退 `activityView.startActivity(intent)`。Intent 加 `270532608 = NEW_TASK\|RESET_TASK_IF_NEEDED` | `PipManager.java:1012-1030` |
| 7 | `ensureTouchView()`：在 ActivityView 上面铺一层透明 `touchView` 接管手势 | `PipManager.smali:4939` |
| 8 | 触摸注入：复制 `MotionEvent` → 反射 `setDisplayId(activityView.getVirtualDisplayId())` → `InputManager.getInstance().injectInputEvent(e, 1)` | `PipManager.java:734-768` |
| 9 | 几何同步：`virtualDisplay.resize(w,h,dpi)`（mdpi 分支自己抓 `mVirtualDisplay`；默认分支走 ActivityView 自身 onLayout → 但 resize 后要 `resizeCover` 遮一下黑帧） | `PipVdActivityView.java:155-235`、`PipManager.java:1288` |
| 10 | 图层与裁剪：`setZOrderOnTop(false)` + `setZOrderMediaOverlay(false)`；圆角 `applyRoundClip`；把被自家 UI 遮住的矩形从点击区减掉 | `PipManager.java:504-519`、`PipVdActivityView.java:90-235` |
| 11 | 容错：看门狗 1 s、`resizeReloadView`、几何重试 ≤11 次×160 ms、`PIP_BOOT_WINDOW_MS=120000`、`embeddedTaskId` + `resizeTask` 修陈旧 bounds | `PipManager.java:56-66, 353-423, 1698+` |

### 1.4 它在框架之上又打了 6 个补丁（这就是 ActivityView 裸用的代价）

| 补丁 | 为什么需要 | 位置 |
|---|---|---|
| 自铺 `touchView` | 要在嵌入窗之上接管手势（长按进入编辑、拖动卡片、双指缩放不与地图冲突） | `PipManager.java:734` |
| tap-exclude 挖洞 | 浮窗/弹窗/加载遮罩盖在地图上时，点击不能漏进地图 | `PipVdActivityView.java:90-235` |
| SurfaceView 层序 | SurfaceView 默认敢盖住普通 View，需要压回底层；浮窗那条路要反射 `SurfaceControl.Transaction#setRelativeLayer/setLayer` | `PipManager.java:504`、`FloatWindows.java:263-305` |
| resize 遮罩 + 重建 | resize 会触发 App 重排，中间有黑帧；mdpi 设备还要 `resizeReloadView` 整个重建 | `PipManager.java:522-660` |
| 几何修复 | 嵌入任务在虚拟屏上的 bounds 会"陈旧"（App 自己 resizeTask 或系统配置变更），要 `resizeTask(id, null, 0)` 重置 | `PipManager.java:1698+` |
| 看门狗 + 启动时限 | ActivityView 没有"首帧到了"的确定性回调，只能靠遮罩 + 1 s 轮询 + 120 s 启动窗口猜 | `PipManager.java:56-66` |

### 1.5 代价清单

1. **必须 system 权限**：`injectInputEvent` 要 `INJECT_EVENTS`（signature 级）→ 只能 platform 签名 + `android.uid.system`。
2. **反射 AOSP 私有成员**：`mSurfaceView`、`mVirtualDisplay`、`cleanTapExcludeRegion`——框架一改就炸。
3. **一个实例一个 App**：切 App 要 release + 重建，于是有 `pipReady / geometryView / resizeReloadView / embeddedTaskId / repairedGeometryTaskId / geometryAttempts` 一整排状态机。
4. **API 29+**：Android 9 上没有 `android.app.ActivityView`（嘟嘟 `Pip28View` 用的是 ROM backport 的隐藏类，普通应用拿不到）。
5. **代码体量**：`PipManager` 90 KB + `PipVdActivityView` 16.7 KB + `FloatWindows` 51 KB。

---

## 2. UNI桌面：自建 VirtualDisplay + Flutter 纹理

`app/android/app/src/main/java/xyz/i4o/uni/launcher/platform/LiveNavigationHost.java`（269 行，无 ActivityView / 无 SurfaceView / 无 PlatformView）。

### 2.1 六个动作

```java
// :149-160  ① 一张 Flutter 纹理当虚拟屏的输出面
texture = textures.createSurfaceTexture();
texture.surfaceTexture().setDefaultBufferSize(width, height);
surface = new Surface(texture.surfaceTexture());
display = manager.createVirtualDisplay("UNI Live Navigation "+id, width, height,
        textureDensity(), surface,
        VIRTUAL_DISPLAY_FLAG_PUBLIC | VIRTUAL_DISPLAY_FLAG_OWN_CONTENT_ONLY);

// :163-165  ② 关掉系统对显示信息的覆盖（这就是 ActivityView 帮你做的那件事）
WindowManagerGlobal.getWindowManagerService()
        .dontOverrideDisplayInfo(display.getDisplay().getDisplayId());

// :166-169  ③ 输入转发器（框架给 ActivityView 用的同一个内部通道）
inputForwarder = InputManager.getInstance().createInputForwarder(vdId);
forwardEvent   = inputForwarder.getClass().getMethod("forwardEvent", InputEvent.class);

// :199-200  ④ 启动；已有任务则 :208-221 归位
options.setLaunchDisplayId(vdId);
startActivity(intent.addFlags(NEW_TASK), options.toBundle());
// 已有任务 → ActivityManager.getAllStackInfos() + moveStackToDisplay(stackId, vdId)

// :151-156  ⑤ 首帧确定性
texture.setOnFrameConsumedListener(() -> ready = true);   // 一帧即 ready，10 s 超时明确报错

// :229-255  ⑥ 触摸：归一化坐标 → 多点 MotionEvent → forwardEvent
```

尺寸策略：`:171-177` `pixels = logical * scale` 且 `density = base * scale` → 分辨率降、**dp 不变**，导航 App 不重排。
隐藏策略：`:78-84` `setVisible(false)` 只停输入，VD/Surface 不销毁；`preparePageChange()` 空实现——纹理跟着 Flutter 走，没有"Surface 重建栅栏"。

实车数据（`docs/IP753_0_6_8.md`）：displayId 11、1229×782、首次检查已消费 347 帧、四轮换屏 resize 0、纹理与显示 ID 不变。

---

## 3. 逐项对比

| 维度 | 君君桌面（ActivityView） | UNI桌面（VD + Texture） |
|---|---|---|
| 宿主 | 原生 View 树里的一个 View | Flutter 纹理（`Texture` widget） |
| 画面路径 | App → VD → **SurfaceView（独立 layer）** → SF 合成 | App → VD → SurfaceTexture → **Flutter GL 合成**（一层） |
| 圆角/裁剪 | 需要 Surface 侧 crop 或 `Region` 挖洞 + CardView `clipToOutline` | `ClipRRect`/`ClipPath` 直接给 |
| 换页/缩放动画 | SurfaceView 不跟随 View 变换，动画期要额外处理；resize 触发重排 | 纹理随 Flutter 一起动，动画期**不 resize** |
| 输入 | 透明 touchView + `injectInputEvent`（全局注入，需签名权限） | `createInputForwarder(vdId).forwardEvent()`（框架内部通道） |
| 输入法 | 弱（Android 无 per-display IME，嵌入式搜索框基本不可用） | 同样弱（同等短板） |
| 首帧确定性 | 无回调，靠遮罩 + 看门狗 | `setOnFrameConsumedListener` 一帧确认 |
| 任务归属 | ActivityView 托管，但几何要自己修（`resizeTask`） | 自己搬栈 + 200/250 ms 归位校验（≤20 次） |
| 多实例 | 一实例一 App，切换要 release + 重建 | 一 `LiveMap` 一 VD，可扩多实例（现策略一次一个） |
| 平台依赖 | **API 29+** | Android 9 可用（`dontOverrideDisplayInfo`、`createInputForwarder` 隐藏 API） |
| 权限要求 | system uid + platform 签名（`INJECT_EVENTS`） | 同样需要特权（隐藏 API + 注入/转发） |
| 崩溃面 | 反射 AOSP 私有字段，框架升级易炸 | 反射隐藏 API，反射面更窄；`ActivityManager` 栈 API 在新系统需换 `ActivityTaskManager` |
| 代码量 | 90 KB + 16.7 KB + 51 KB，状态标志十几个 | 269 行，phase/ready/publish 三个状态位 |

---

## 4. 哪个更优（按用途，不给单一答案）

| 用途 | 更优 | 原因 |
|---|---|---|
| 卡片里放**一块实时地图**，要圆角、要跟桌面动画一起动、要频繁换页 | **UNI（纹理）** | 只有一层，动画零成本；隐藏不销毁生产面；首帧可判定；无 SurfaceView 层序问题 |
| 卡片/浮窗里放**任意 App 的完整界面**（含输入法、系统对话框、复杂层级、多窗口交互） | **君君桌面（ActivityView）** | 输入/焦点/任务归属由系统托管，不用自己实现嵌入契约 |
| 平台是 **Android 9** | **UNI（纹理）** | `ActivityView` 不在框架里；ROM backport 版需要系统签名 |
| 平台是 **Android 10+ 且自己是 system 应用** | 平手偏 ActivityView | 少写状态机，代价是层序/黑帧补丁 |
| 只要"浮窗里一个能动的 App" | ActivityView 更省事 | `FloatWindows` 已经证明这条路可行 |

**针对当前项目**（Flutter + Android 9 + 卡片式实时地图）：**现在的纹理方案在本场景更优**，而且它是平台约束下的正解，不是风格选择。

---

## 5. 比这两个都更优的方案（按可落地性排序）

### ① 官方嵌入能力（理论最优，优先争取）
导航厂商车机版的**官方嵌入式控件**（车厂合作版才下发的 MapView / 卡片宿主），或车机 OEM 提供的"卡片宿主 / Surface 投递 / RemoteViews"服务。
- 收益：不需要 VD、不需要输入注入、可交互、可裁剪、跟随升级。
- 成本：受商务与固件开放度限制，逆向拿不到。

### ② 现状增强（性价比最高，建议立刻做）
在 `LiveNavigationHost` 上补三件事，就能把纹理方案补到超出 ActivityView：
1. **输入法**：Android 没有 per-display IME。三选一：卡片内自绘键盘 / 拦文本入口改语音（高德百度车机版都有语音入口，最省事）/ `TYPE_INPUT_METHOD` 窗口投到虚拟屏（重度 hack，不建议）。
2. **任务 API 兼容**：`ActivityManager.getAllStackInfos/moveStackToDisplay` 在新系统被 `ActivityTaskManager` 取代（君君桌面已在用后者），加 fallback 即可跨 Android 10+ 复用。
3. **尺寸策略**：动画期不 resize（已做）；只在真实尺寸变化超阈值时 resize；保留 `scale` 降分辨率（已有 0.3~1）。

### ③ 双实现自适应（工程上最稳）
`SDK_INT >= 29 && ActivityView 可用` → 系统托管路径；否则 → 纹理路径。两条实现共用一个 `NavigationSurface` 接口（create/resize/touch/visible/dispose），Flutter 侧只认接口。多一套验收，换新车型吃系统红利。

### ④ `SurfaceControl.reparent` 零拷贝嵌入（不建议）
system uid 下把目标 Task 的 surface 用 `SurfaceControl.Transaction#reparent` + `setMatrix/setCrop/setAlpha` 挂到自己 ViewRoot 图层下。
省一次合成、延迟最低、裁剪动画都能做；但强绑 SurfaceFlinger 版本，App 内多 Surface（地图 GL + 控件层）要逐个处理，一次错误 reparent 能把系统 UI 干黑。ROM 团队才值得碰。

### ⑤ MediaProjection 截屏裁剪（明确不选）
延迟 100 ms+、需授权、不能注入输入。只配当缩略图/预览。

---

## 6. 落地建议

| 优先级 | 动作 | 工作量 | 收益 |
|---|---|---|---|
| P0 | 保持 `LiveNavigationHost` 为 IP753 主路径，不回到 ActivityView | 0 | 现有稳定性不回退（实车 347 帧 / resize 0） |
| P0 | 补 `ActivityTaskManager` fallback（任务枚举/搬迁） | 0.5 天 | 未来 Android 10+ 车型直接复用 |
| P1 | 输入法方案定稿（自绘键盘 or 语音入口） | 2~3 天 | 补齐唯一硬短板 |
| P1 | 明确多地图卡策略（现为一次一个）：禁止或加实例池 | 1 天 | 避免二次进入 create/dispose 抖动 |
| P2 | ActivityView 双实现（仅确认要上 Android 10+ 车型时） | 3~5 天 | 新平台吃系统托管 |
| P2 | 争取官方嵌入式控件/卡片宿主 | 取决于商务 | 长期免维护 |

---

## 7. 代码索引

**君君桌面**（`D:\PO\lynkcotool\work\jj\jadx\sources\com\claunchercard\manager\`）

| 位置 | 内容 |
|---|---|
| `PipManager.smali:4882-4898` | `new PipVdActivityView` / `new RoundMapActivityView`（分支依据 `needsDuduPipPath()` = mdpi） |
| `PipManager.smali:4902-4937` | 反射 `mSurfaceView`、挂 layout/surface 回调、`setCallback` |
| `PipManager.java:1012` | `launchInActivityView`（PendingIntent + `ActivityOptions.makeCustomAnimation`，回退 `startActivity`） |
| `PipManager.java:734` | `injectTouchToVirtualDisplay`（`setDisplayId` + `injectInputEvent`） |
| `PipManager.java:504` | `applyActivitySurfaceZOrder`（`setZOrderOnTop/MediaOverlay`） |
| `PipManager.java:1288` | `scheduleDisplayGeometry`（几何重试 ≤11 次×160 ms） |
| `PipManager.java:1698+` | `syncEmbeddedTaskGeometry`（`resizeTask` 修陈旧 bounds） |
| `PipManager.java:56-66` | `PIP_BOOT_WINDOW_MS=120000`、`PIP_LAUNCH_FLAGS=270532608`、看门狗 1 s |
| `PipVdActivityView.java:270` | `captureVirtualDisplay`（反射 `mVirtualDisplay`） |
| `PipVdActivityView.java:155` | `resizeToSurface` / `syncSurfaceIfNeeded` |
| `PipVdActivityView.java:90-235` | `cutCoveringChrome/cutFloatingWindows/cutModalPanels/trimCornerHole`（tap-exclude 挖洞） |
| `FloatWindows.java:313-360` | 浮窗宿主：`new ActivityView(mainActivity, null, 0)` + 状态回调 |
| `FloatWindows.java:263-305` | `SurfaceControl` 反射 `setRelativeLayer/setLayer`（浮窗层级） |
| `MainActivity.java:867-889` | 两张地图卡 `mapCard`/`mapCard2` 的 `pipContainer` 圆角与容器 tag |

**UNI桌面**（`app/android/app/src/main/java/xyz/i4o/uni/launcher/`）

| 位置 | 内容 |
|---|---|
| `platform/LiveNavigationHost.java:147` | `createDisplay`（SurfaceTexture + VD + `dontOverrideDisplayInfo` + `createInputForwarder`） |
| `platform/LiveNavigationHost.java:179` | `resize`（buffer + `display.resize` + 重新等首帧） |
| `platform/LiveNavigationHost.java:188` | `activate`（启动 / 归位） |
| `platform/LiveNavigationHost.java:208` | `placeExistingTask`（`getAllStackInfos` + `moveStackToDisplay`） |
| `platform/LiveNavigationHost.java:229` | `touch`（归一化 → 多点 MotionEvent → `forwardEvent`） |
| `platform/LiveNavigationHost.java:261` | `close`（释放 display/surface/texture/forwarder） |
| `integration/NavigationApps.java` | `canEmbed` 判定、`displayIntent()` |
| `overlay/DisplayTasks.java`、`overlay/RecentTasksRepository.java` | 区分嵌入任务（在虚拟屏）与物理屏任务 |
| `docs/IP753_0_6_8.md` | 实车数据与验收口径 |
