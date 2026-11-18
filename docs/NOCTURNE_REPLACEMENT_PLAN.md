# 「蚀·暗夜升级版」落地可行性方案书

> 输入：设计总览《蚀-暗夜升级版 完整设计方案》（PART01–PART06，共 28 屏）
> 代码基线：`feat/lynkco-05` @ `db60aee`（0.7.6），`app/lib` 94 文件 / 24,318 行，409 个测试
> 结论日期：2026-11-05

---

## 0. 结论

**这套方案不是"待替换的新界面"，它已经是源码里的第三套皮肤。**

`app/lib/model/appearance.dart:45` 定义了 `themeStyles = ['classic', 'blueGlass', 'nocturne']`，`nocturne` 就是暗夜。调色板（`theme/launcher_theme.dart:11` `Nocturne`）、玻璃面（`widgets/glass_surface.dart:127` `_nocturne`）、一卡一色光晕（17 种卡片类型，`launcher_theme.dart:29`）都已实现，`theme-styles/nocturne/preview/` 下的四张截图就是设计稿的画面本身。

所以"替换"不是重写 UI 层，而是三件事：

| # | 事项 | 性质 | 工作量 |
|---|---|---|---|
| A | 把 `nocturne` 设为默认皮肤（含老用户迁移） | 改 3 处 + 1 个迁移分支 | 0.5 天 |
| B | 按 28 屏设计稿逐屏校准 | 视觉校准，不动结构 | 5–8 天 |
| C | 决定是否退掉 classic / blueGlass 两套皮肤 | 删代码，可选 | 3–5 天 |

**不建议"重写 UI 层"**：那等于把 24,318 行已经跑通、409 个测试覆盖的界面推倒，收益为 0，风险极高。

---

## 1. 现状基线（可验证的证据）

| 事实 | 位置 |
|---|---|
| 主题枚举含 `nocturne`，默认值仍是 `blueGlass` | `model/appearance.dart:45,78` |
| 暗夜调色板：画布 `#050607`、底栏 `#0B0D0E`、正文 `#EFF4F6` | `theme/launcher_theme.dart:11-51` |
| 暗夜玻璃面：白 alpha 渐变 + 底部压暗 + 1.4px 顶部高光 + 椭圆光晕 | `widgets/glass_surface.dart:127-255` |
| 一卡一色光晕表（nav/trafficLight/music/shortcuts/weather/air/cleanup/battery/fuel/tpms/body/clock/clockWeather/calendar/vehicle/ride/member） | `theme/launcher_theme.dart:29-47` |
| 卡片光晕注入点（每张卡都走这里） | `widgets/editable_card.dart:57` |
| 主题抽象覆盖率：`SurfaceStyle.of()` 132 处 / 48 个文件 | 全仓 |
| 硬编码颜色：152 处 / 15 个文件（集中在取色器色板、背景渐变、暗夜玻璃） | 全仓 |
| 设计稿对照图（已能复现） | `theme-styles/nocturne/preview/*.png` |

**推论：主题化已经是"令牌驱动"，不是"逐控件写死"。** 这意味着校准面很窄——绝大多数屏只需要改 `Nocturne` 里的常量或 `SurfaceStyle` 的派生值，不需要动布局代码。

---

## 2. 28 屏 → 源码映射与状态

图例：✅ 已实现可直接用　⚠️ 已实现但需按稿校准　❌ 源码中不存在（需新增）

### PART01 桌面首页（6 屏）

| 屏 | 设计内容 | 承载文件 | 状态 |
|---|---|---|---|
| 1.1 | 页1 驾驶版主（导航+音乐+红绿灯） | `widgets/desktop.dart`、`card_content_navigation.dart`、`embedded_navigation.dart`、`card_content_music.dart`、`traffic_light_card.dart`、`bottom_dock.dart` | ✅ 预览图可复现 |
| 1.2 | 页1 状态B 音乐·导航（卡片形态变化） | `card_content_music.dart`（4×4 / 4×2 变体）、`bottom_dock.dart` | ✅ |
| 1.3 | 页1 状态C 音乐播放器（全屏面板） | `card_content_panels.dart:19` `showMediaPanel` | ⚠️ 面板存在，暗夜样式无预览可对照 |
| 1.4 | 页1 状态D 全部应用 | `card_content_panels.dart:125` | ⚠️ 同上 |
| 1.5 | 页1 状态E 空调与座椅（底栏展开） | `climate_panel.dart`、`dock_climate_button.dart`、`seat_controls.dart` | ⚠️ 无暗夜对照图 |
| 1.6 | 页1 状态F2 座椅档位激活动画 | `seat_controls.dart` | ⚠️ 动效时长/曲线未按稿 |

### PART02 其余三页（6 屏）

| 屏 | 设计内容 | 承载文件 | 状态 |
|---|---|---|---|
| 2.1 | 页2 车辆状态（车况与胎压） | `vehicle_cards.dart`、`vehicle_visuals.dart` | ✅ 预览图可复现 |
| 2.2 | 页2 燃油液体·剩余油量 | `vehicle_cards.dart` `FuelLevelBar` | ✅（预览图中为"动力电池"卡，同构） |
| 2.3 | 页3 时间天气（大时钟+天气+日历整页） | `clock_weather_card.dart`、`clock_card.dart` | ⚠️ 实现是单张组合卡，设计稿是三块并置，**布局口径需确认** |
| 2.4 | 页3 状态B 天气预警 | —— | ❌ 源码无"预警"相关实现（全仓 grep 为空） |
| 2.5 | 页4 服务与账号 | `card_content_oem.dart`（`member` / 出行服务） | ✅ |
| 2.6 | 页4 账号详情弹层 | `account_details_sheet.dart` | ⚠️ 无暗夜对照图 |

### PART03 卡片系统（3 屏）

| 屏 | 设计内容 | 承载文件 | 状态 |
|---|---|---|---|
| 3.1 | 卡片库·添加卡片 | `desktop.dart` `showCardLibrary` | ✅ |
| 3.2 | 卡片库·编排卡片（缩放网格） | `card_editor_sheet.dart`、`desktop_drag.dart`、`editable_card.dart` | ✅ |
| 3.3 | 卡片库·桌面扩展（末页添加） | `desktop.dart`（`scratch` 页） | ✅ |

### PART04 核心组件规范（3 屏）

| 屏 | 设计内容 | 承载文件 | 状态 |
|---|---|---|---|
| 4.1 | 红绿灯·灯态全览盘（12 种组合） | 规范稿 `design/traffic-lights.html` | ⚠️ **这是规范图，不是运行界面**，不应做成产品屏 |
| 4.2 | 红绿灯·单灯亮度 | `traffic_light_card.dart`、原生 `AmapTrafficLightProtocol.java` | ✅ |
| 4.3 | 顶栏图例 | `desktop.dart:25` `Header`、`system_status_row.dart` | ✅ |

### PART05 设置（8 屏）

设置页左侧固定 7 个分类，与设计稿 5.1/5.3–5.8 一一对应；5.2 是 5.1 的子块。

| 屏 | 设计内容 | 承载文件 | 状态 |
|---|---|---|---|
| 5.1 | 外观与壁纸（主题样式/配色/壁纸） | `screens/settings_screen.dart` + `widgets/*` | ✅ 预览图可复现 |
| 5.2 | 壁纸库（独立网格屏） | `model/appearance.dart:30` `wallpaperPresets` | ⚠️ 实现是 5.1 内的横向列表，**无独立壁纸库屏** |
| 5.3 | 应用与底栏 | `settings_screen.dart`（`dock`） | ✅ |
| 5.4 | 导航与媒体 | 同上（`connections`） | ✅ |
| 5.5 | 动画与频谱 | 同上（`motion`） | ✅ 预览图可复现 |
| 5.6 | 氛围灯 | 同上（`ambient`）+ `ambient_light_settings.dart` | ✅ |
| 5.7 | 系统与调试 | 同上（`system`）+ `diagnostics_settings.dart` | ✅ |
| 5.8 | 关于与更新 | 同上（`about`）+ `ota/update_ui.dart` | ✅ |

分类清单证据：`screens/settings_screen.dart:88-117`（外观与壁纸 / 应用与底栏 / 导航与媒体 / 动画与频谱 / 氛围灯 / 系统与调试 / 关于与更新）。

### PART06 全局交互（2 屏）

| 屏 | 设计内容 | 承载文件 | 状态 |
|---|---|---|---|
| 6.1 | 最近任务 | `recent_tasks_panel.dart` | ✅ |
| 6.2 | 桌面命名 | `desktop_name_dialog.dart` | ✅ |

**统计：✅ 17 屏 / ⚠️ 10 屏 / ❌ 1 屏。**

---

## 3. 需要更改的地方（按落地顺序）

### 3.1 设默认皮肤（P0，必做）

| 文件 | 改什么 |
|---|---|
| `app/lib/model/appearance.dart:78` | `this.themeStyle = 'blueGlass'` → `'nocturne'` |
| `app/lib/model/appearance.dart:95-97` | 读取已持久化 json 时，老值 `classic`/`blueGlass` 是否迁移到 `nocturne`。**这一步必须显式决策**：不迁移 = 只有新装用户看到暗夜；迁移 = 所有老用户外观突变 |
| `app/lib/screens/settings_screen.dart`（外观页主题样式选择器） | 若"替换"是排他的，需要把 `深蓝玻璃 / 清夏 / 经典` 从选择器移除；`themeStyles` 常量（`appearance.dart:45`）同时是读取校验白名单，删项会让老配置回落到默认值 |

**风险点**：`appearance.dart:212` 有一串基于 `themeStyle` 的门控（如 `usesBackdropBlur`），主题默认值一改，模糊、圆角、字体对比度、壁纸叠加的默认行为全部换一套。必须在实机确认一遍默认外观下的可读性。

### 3.2 逐屏校准（P0–P2）

校准只在三个层面动手，**不要逐控件改代码**：

1. **常量层**：`theme/launcher_theme.dart` 的 `Nocturne`（背景、半径、光晕 alpha 表）。
2. **派生层**：`SurfaceStyle` 的 getter（`edge` / `muted` / `accent` / `cardGlow`）。
3. **单屏特例**：仅当设计稿与实现的**结构**不同才改布局（已识别 3 处，见 §4）。

### 3.3 需要新增的实现（P2，唯一硬缺口）

- **2.4 天气预警**：源码完全没有。要么按稿新增一张 `weatherAlert` 卡片类型（`card_content.dart` 类型表 + `Nocturne._glow` 补色 + 数据源要确认原车是否提供预警字段），要么从方案里删掉这一屏。**建议先确认数据源，没有数据就不做这屏。**

### 3.4 可选：退掉另两套皮肤（P3）

`classic` 与 `blueGlass` 两套分支散在 `SurfaceStyle`、`glass_surface.dart`、`technical_frame.dart`、`scene_background.dart`。全部清掉可减约 800–1200 行，并且让"设计稿 = 唯一真相"。

代价：老用户无法回退；`blue_glass_theme_test.dart`、`scene_gradient_test.dart` 等测试要连带删改；`technical_frame`（技术框线）是 blueGlass 独有装饰，删了不影响暗夜。

---

## 4. 与设计稿的差异说明（重要）

### 4.1 有意偏离：毛玻璃

设计稿有 `backdrop-filter`，暗夜实现**主动不做**。原因写在 `glass_surface.dart:125`：目标机是 Adreno 530（2016 年 Vulkan 1.0 驱动），每卡一次 sigma 10 背景模糊是最贵的单类操作，一屏 8–10 张卡直接超帧预算。暗夜改用"8% 白玻璃 + 9% 描边 + 椭圆光晕"达到同样的浮起感。

**这一条不要按稿改回去**，改了会把翻页帧率打回去。

### 4.2 有意偏离：圆角

设计稿 34，实机收到 25。理由在 `launcher_theme.dart:26`：设计稿是 1600 宽 1:1 逻辑单位，实机 1920 实宽要乘 1.2，34 会显得大一圈。**需产品确认以哪个为准**。

### 4.3 结构性差异（3 处，需产品决策）

| 差异 | 设计稿 | 现状 | 建议 |
|---|---|---|---|
| 页3 时间天气 | 大时钟 / 天气 / 日历三块并置 | 单张 `clockWeather` 组合卡 | 按稿改布局 = 动 `clock_weather_card.dart` 结构 + 改 `design_contract_test` 锚点 |
| 壁纸库 | 独立网格屏（5.2） | 5.1 内的横向列表 | 按稿新增独立子页，改动小、收益明确 |
| 红绿灯灯态全览（4.1） | 12 种组合的规范盘 | 只有运行态单卡 | 不进产品，作为设计规范文档保留 |

### 4.4 全局放大 1.2× 带来的系统性偏差

实现用 `FittedBox(BoxFit.fill)` 把 1600×900 逻辑画布铺到 1920×1080（`screens/launcher_shell.dart:109-113`），所有 1px 描边、字距、圆角都会被整体放大 1.2 倍后再栅格化。**逐屏 pixel diff 时，边框类和细线类的偏差属正常，不要为它去改代码。**

### 4.5 字体（最大的观感差异，且是法务问题）

`pubspec.yaml` 没有声明任何自定义字体，实机走 Android 系统字体（Roboto / Noto Sans CJK）。设计稿用的是 MiSans。

后果：字形、字重、数字宽度、中文断行都与稿不同，大字号（86px 级别）的观感差异尤其明显。

**并且**：MiSans / HarmonyOS Sans 用于车机商业发布需要授权。**在上车前必须确认授权状态，否则不许把字体打进包。**

### 4.6 截图里的数值不是验收基准

设计稿里的 `78%` / `2.40bar` / `342km` / `22:47` 是演示数据（`app/preview/main_preview.dart` 的 `_demoVehicle()`）。验收只看版式、间距、层级、发光强度，不看具体数字。

---

## 5. 风险清单

| 风险 | 影响 | 处置 |
|---|---|---|
| `design_contract_test.dart` 锚定了几何（`closeTo(14.9333)`、`closeTo(138)`、`closeTo(1200)` 等） | 改布局/间距会直接测试失败 | 校准前先跑一遍该测试，确认哪些锚点是"设计契约"还是"历史快照" |
| 默认皮肤切换导致老用户外观突变 | 用户投诉 | 加设置项 + 首次切换引导；或只对新装生效 |
| 一卡一色光晕的绘制成本 | 一屏 6–10 层全卡尺寸 radial gradient | 已有实现已验证可用；**但如果校准把光晕调强，必须重新上车测翻页帧率**（历史上阴影 44→20 只换来 25% 帧时间，说明这类全卡绘制是敏感项） |
| 28 屏逐屏校准是纯人力活 | 容易越改越花 | 用现成工具链：`preview_shot.sh` 出图 + `pixel_diff.sh` 逐屏 diff，改一屏 diff 一屏 |
| 若顺手删 `classic`/`blueGlass` | 连带 5+ 个测试文件 | 单独一个提交，不与校准混在一起 |

---

## 6. 分期实施

| 期 | 内容 | 交付 | 验收 |
|---|---|---|---|
| P0 | 设默认 + 迁移策略 + 首页 6 屏校准 | 可安装包 | 首页 6 屏与设计稿 diff；车机帧率不退化 |
| P1 | 页2–4（6 屏）+ 设置 8 屏校准 | 可安装包 | 同上 |
| P2 | 卡片系统 3 屏 + 全局交互 2 屏 + 壁纸库独立屏 | 可安装包 | 同上 |
| P3（可选） | 退掉 classic / blueGlass | 分支合并 | 409 测试全绿 |

**验收工具（已存在，无需新建）**

```bash
# 出图（Windows 预览，F2 切主题 / F3 存图）
cd app && flutter run -d windows -t preview/main_preview.dart

# 或走脚本
bash .workbuddy/skills/uni-launcher-theme/scripts/preview_shot.sh nocturne <out.png>

# 与设计稿逐像素对照
bash .workbuddy/skills/uni-launcher-theme/scripts/pixel_diff.sh a.png b.png

# 车机性能（确认视觉改动没把帧率打回去）
pwsh tools/car_perf_probe.ps1 -Label after
```

---

## 7. 不建议做的事

1. **不要重写 UI 层。** 现有 24,318 行 + 409 测试就是这套设计稿的实现，重写等于把已完成的工作清零。
2. **不要按稿加 backdrop-filter。** 目标 GPU 已实测不支持，加了必然掉帧。
3. **不要把 4.1 灯态全览盘做成产品屏。** 它是规范说明，不是功能。
4. **不要为了 pixel diff 全绿去改 `FittedBox`。** 那会动到 409 个测试里锚定的几何，属于"为验收而改实现"。
5. **不要在校准提交里顺手删皮肤。** 混在一起出问题无法二分。

---

## 8. 需要你决策的 4 件事

1. **迁移策略**：只对新装生效，还是所有老用户强制切暗夜？
2. **另两套皮肤**：选择器里保留（用户可回退）还是移除（方案排他）？
3. **3 处结构性差异**（页3 时间天气 / 壁纸库 / 灯态图解）：以稿为准改布局，还是以现状为准改稿？
4. **MiSans 授权**：有没有，能不能进包？没有就明确"系统字体 + 按稿调字号行高"作为终态。
