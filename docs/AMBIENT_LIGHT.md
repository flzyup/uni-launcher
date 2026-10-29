# 音乐律动氛围灯

把正在播放的音乐频谱换算成颜色与亮度，下发到车机氛围灯通道。

## 功能

- 桌面设置新增「氛围灯」标签页：开关、颜色模式、灵敏度、亮度上下限、固定色。
- 实时预览：当前颜色、亮度条、频谱条，与下发给车机的颜色同源。
- 三种颜色模式：
  - **跟随低频**：取低频段（24 段对数频谱里的前 4 段，约 60–150 Hz）里最响的那一段决定色相，鼓点一响灯就跳。
  - **跟随频谱**：全部频段按能量做**圆周加权平均**决定色相，像一条彩虹随音乐流动。
  - **固定色**：色相固定，颜色仍随电平明暗变化。
- 亮度由整体电平换算：`亮度 = 下限 + (上限 − 下限) × 电平^(1/灵敏度)`。灵敏度越高，微弱的声音也越能点亮氛围灯。
- 静音时保留上一次的色相，避免灯在没有声音时乱跳。

## 色相为什么用圆周平均

色相是**环形**的：359° 和 1° 只差 2°，算术平均却会得到 180°（青绿）——正好是最离谱的结果。所以频谱模式的色相按 `cos/sin` 做圆周平均，而不是直接求平均。

## 车机通道

氛围灯在车机端 `ecarx.adapterapi.jar` 里是一组**设置类功能号**，写法和空调属性一样：`setFunctionValue(功能号, 区域, 值)`。

| 我们要做的事 | 功能号 | 写入的值 |
| --- | --- | --- |
| 开关氛围灯 | `SETTING_FUNC_AMBIENCE_LIGHT_INTERACTIVE_EFFECT` | `1` 开 / `0` 关 |
| 主色来源 = 自定义色 | `SETTING_FUNC_AMBIENCE_LIGHT_MAINCOLOR` | `AMBIENCE_LIGHT_MAINCOLOR_SETCOLOR` |
| 颜色 | `SETTING_FUNC_AMBIENCE_LIGHT_COLOR_SET` | `0xRRGGBB` 打包 |
| 行车亮度 | `SETTING_FUNC_AMBIENCE_LIGHT_BRIGHTNESS_DRIVING` | `HIGH` / `LOW` / `OFF` |
| 静止亮度 | `SETTING_FUNC_AMBIENCE_LIGHT_BRIGHTNESS_STATIONARY` | `HIGH` / `LOW` / `OFF` |
| 点亮主区 | `SETTING_FUNC_AMBIENCE_LIGHT_MAINZONES` | `1` |
| 点亮上区 | `SETTING_FUNC_AMBIENCE_LIGHT_TOPZONES` | `1` |
| 点亮下区 | `SETTING_FUNC_AMBIENCE_LIGHT_BOTZONES` | `1` |
| 体验模式 = 自定义 | `SETTING_FUNC_AMBIENCE_LIGHT_EXPERIENCE` | `AMBIENCE_LIGHT_EXPERIENCE_CUSTOM` |

「互动效果」就是厂商那边的**音乐律动**；主色设成「自定义色」，颜色由我们按频谱算好写进去。

### 三个陷阱

1. **分区是三个独立功能号**。写主区**不会**带上区与下区，只写主区的话上/下分区（门板那圈 / 脚部）点不亮，所以开灯时三个分区都写。某个分区解析不到就跳过那一个，不拿别的分区的号顶替。
2. **亮度 `0` 是 `OFF`（把灯关掉），不是「最低档」**。厂商把 `0` 映射成 `OFF`，`LOW` 必须传 `BRIGHTNESS_*_LOW` 常量。亮度 0 按「关灯」处理，这是故意的。
3. **亮度有两套**：行车（`0x200A0700`）与静止（`0x200A0600`）是不同功能号，档位常量也各有一套。代码**两套都写同样的值**，这样车在动和车停着亮度一致。

### 数值一律按名字解析

厂商常量放在 `com.ecarx.xui.adaptapi.car.vehicle.IAmbienceLight` 与 `IVehicle` 里。本工程**不链接**车机 jar，所有常量都用反射**按名字**解析（`AmbientLightResolver`），解析不到就**不写**——猜一个数值去写别的功能，比不写更糟。解析结果带缓存，功能号句柄的类会作为最准的根类登记。

### 体验模式与自定义色的先后

厂商有**两个**互不相干的开关：`MAINCOLOR`（主色来源）和 `EXPERIENCE`（体验模式）。写自定义色之前先把体验模式置成 `CUSTOM`。「不置 `CUSTOM` 则自定义色不生效」这条因果关系厂商文档与源码都没有明说，属于**未验证**项；先置 `CUSTOM` 成本极低（一次写），因此保留。

## 架构与性能

```
AudioSpectrumService（真实播放频谱，10 Hz / 24 段）
      ↓ 频段能量 + 整体电平
AmbientPalette（纯函数：频段 → 颜色 + 亮度）
      ↓ AmbientColor
AmbientLightService（MethodChannel）
      ↓
AmbientLightWriter（原生：按名解析功能号 → 写入车机）
```

- **颜色计算放在 Dart**：映射是纯函数，能用 `flutter test` 覆盖，不需要设备和真实 FFT。
- **原生只负责执行**：写入在专用后台线程，绝不占用 Flutter 平台线程。
- **写频节流**：最小间隔 120 ms + 颜色变化幅度 8。折算后档位没变就不再重写亮度，否则每帧都会写一次车机 IO。
- **单写者**：桌面、底栏、面板是三个 Flutter 引擎，但只有桌面引擎驱动氛围灯，原生侧也只保留一个写者。三个引擎共用同一份持久化设置。
- **频谱按需采集**：氛围灯打开时才向频谱服务申请数据；关闭时释放。频谱本身需要 `RECORD_AUDIO` 与 `MODIFY_AUDIO_SETTINGS`，没有授权时只显示状态，不采样。
- **预览不重建设置页**：实时颜色走独立的 `ValueNotifier`，只有色块、亮度条和频谱条重绘。

## 验证

- `flutter analyze` 无问题；新增 18 项单元测试，覆盖色相圆周平均、静音保留色相、亮度曲线与上下限、设置序列化与越界裁剪、服务开关与写频调用序列。
- JVM 测试覆盖按名解析、未知名字不猜值、枚举取值、覆盖与缓存失效。
- Android 9 模拟器：桌面设置「氛围灯」页可见，开关可切换，实时色块/亮度条/频谱条正常渲染；无车机框架时明确显示「此设备没有原车氛围灯接口」，不假装成功。
- 端到端（`integration_test/ambient_light_test.dart`）：走真实平台通道与真实原生写者，用原生写计数器断言「一帧频谱 = 一次颜色写入」——频谱帧注入后 `colorWrites`/`brightnessWrites` 增长；静音帧回落到最低亮度并保留上一次色相；关闭氛围灯后释放频谱采集。
- **模拟器验证不了真实 FFT**：该 arm64 AOSP 镜像的 AudioFlinger 输出线程恒为 standby（`dumpsys media.audio_flinger` 显示 `Standby: yes`、`Total writes: 0`），仓库**既有**的频谱功能同样抓不到声音（诊断里 `signalFrames: 0`、`peakLevel: 0`）。这是模拟器声卡的限制，不是本次移植引入的问题；真实频谱→颜色链路必须在实车上确认。

## 车机待验证

1. **功能号能否按名解析**：装机后看 `dumpsys activity xyz.i4o.uni.launcher/.MainActivity --uni-state` 里 `ambientLight.unresolved`，列出解析不到的名字。
2. **写值是否被车机接受**：观察日志 `UniAmbient`（`氛围灯开关已下发` / `氛围灯颜色已下发`）与车机是否有实际灯光变化。写成功但灯不动，说明写入通道与灯光不是同一条路径。
3. **三个分区是否都亮**：只写主区时上/下分区不亮，是厂商设计；确认实车三个分区是否都有灯珠。
4. **亮度 0 是否等于关灯**：确认与仪表/原车设置一致。
5. **静止亮度是否需要单独写**：当前两套都写；若实车表现异常，先回退成只写行车那一套。
6. **音乐律动模式是否由车机自己做**：厂商的「互动效果」本身可能有内置灯效；确认我们写自定义色后，灯效来源到底是自定义色还是车机自带。
