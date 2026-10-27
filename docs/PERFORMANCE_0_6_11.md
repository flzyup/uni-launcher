# 0.6.11：820A 性能与翻屏修复

版本 `0.6.11+22`，包名 `xyz.i4o.uni.launcher`。本轮在本地与 Android 9 / 1920×1080 模拟器验证；没有连接或安装车机。模拟器 Profile 数据不等于高通 820A / Adreno 530 实测帧率。

## 翻屏为何不明显

旧实现只接收松手速度，低于阈值的慢拖不换屏；手指按住移动时桌面不跟随。切页后立即隐藏旧页，只让新页平移 8% 宽度、150 ms，淡入也仅从 0.85 开始，因而难以观察到完整翻屏。

新版使用唯一的连续页进度：手指拖动、松手吸附、点击页码和底部指示条共用它。慢拖超过页面宽度约 28%，或有足够距离的快速甩动，均可换页；短拖或取消回到原页。边界不显示空白页。快速反向切换从当前浮点位置继续，不跳回旧页再开始。

设置 → 桌面翻屏提供：

| 效果 | 实现 | 选择建议 |
| --- | --- | --- |
| 平移 | 两页完整横向移动；不使用整页透明混合 | 默认与 820A 首选 |
| 淡入淡出 | 两页透明交替 | 可选，整页混合有 GPU 成本 |
| 缩放 | 横向平移并轻微缩小 | 可选，缩放缓存有成本 |
| 层叠 | 新页滑入，旧页轻微收拢；裁掉已被覆盖部分，不用整页透明缓冲 | 可选 |
| 无动画 | 松手或点击后直接切页 | 最少动效 |

新安装或缺失/非法配置默认使用平移；已明确保存的“无动画”保留，可在设置中改选平移。编辑桌面与系统减少动态效果时使用无动画。

行为参考 [AOSP Launcher3 PagedView](https://android.googlesource.com/platform/packages/apps/Launcher3/+/master/src/com/android/launcher3/PagedView.java) 的拖动、速度/距离判定和吸附思路。Flutter 实现保留现有车机接入，不引入 Android Widget 宿主。

## 降低持续开销

- 翻屏不逐帧重建桌面、卡片或主题，也不逐帧布局。动画只更新变换、裁剪和必要的透明层，最多绘制参与切换的两页；隐藏页不订阅逐帧进度。
- 所有页面和地图纹理保留在树中。翻屏不生成整屏位图、不销毁或重建地图，不对地图逐帧 resize。标题栏和底栏不参与变换。
- 隐藏页、设置背后的桌面及运动中的卡片暂停 ticker。歌词的 250 ms Timer 与进度条的 1 s Timer 也实际取消，恢复显示后直接同步最新位置；可见的全局底栏仍正常更新。
- `NativeSliceBuilder` 通过 TickerMode notifier 控制更新，不因单纯暂停而重建卡片；恢复时仅有数据变化的卡片重建。原始新鲜度时间戳保留，超时判断保持有效。
- 卡片内容增加独立绘制边界，歌词、进度和仪表更新不连带重画外层圆角、边框及大阴影。顶部状态区域只比较天气/系统状态输入。
- 导航应用的 PackageManager 查询按 Application 缓存，共享给短生命周期 helper；安装、卸载、启停、替换、语言变化使结果失效。导航偏好和嵌入权限仍实时读取，返回的 Intent 为副本。
- 播放状态回调不再重复同步一次媒体镜像和 OEM 桥接；保留原有注册、选源、QQ/网易云控制与仪表元数据路径。

本轮不增加实时毛玻璃、3D 立方体或整屏截图翻屏。现有毛玻璃开关仍默认关闭。没有将尚未实测的音乐退出归因于已确认的内存泄漏。

## 验证与边界

- Flutter analyze 无问题，全套 133 项测试通过。包括慢拖、取消、边缘、快速反向、多页跳转、各种效果中间态、层叠遮挡裁剪、隐藏/运动中的遥测合并、歌词/进度定时器暂停与恢复。
- 既有地图生命周期回归通过：texture id / Element 不变，无动画引起的 create、dispose 或 resize。
- 原生缓存/媒体优化：30 + 24 项 JVM contract checks 通过；1000 次热态导航 snapshot/helper 没有额外 PackageManager 查询；100 次播放回调由原先 200 次同步变为 100 次。脚本对前一提交代码执行反例，确认两项回归均能检出；另通过 Android API 28 编译与 D8。QQ/网易云专用路径和 OEM 媒体桥接既有 34 + 31 项检查通过。
- Android 9 Profile 集成验证覆盖真实 Flutter 桌面、触摸跟手、指示条、固定底栏、切页保留组件、五种设置和反复切换。详细检查与帧耗时在 [profile-report.json](../app/verification/page-motion/profile-report.json)。使用明确的演示数据，不冒充实车数据。
- 帧耗时采样在正常 SurfaceView、页面预热后进行，放在截图转换之前；每种效果反复切换 12 次，并加入模拟事件。截图单独在其后采集。报告包含无动画基线、UI build/raster/total span 的 P50/P90/P99/max 和超 16.67 ms 数量，不过滤慢帧。不能据此声称 820A 保证 60 FPS。

本次模拟器正常 SurfaceView 的 Profile 采样（毛玻璃关闭）：

|效果|采样帧|UI build P90 / ms|raster P90 / ms|
|---|---:|---:|---:|
|无动画（基线）|240|1.844|35.632|
|平移|240|1.786|35.821|
|淡入淡出|240|1.352|33.417|
|缩放|240|1.402|45.809|
|层叠|240|1.810|41.884|

平移的 raster P90 与无动画接近，但本模拟器连无动画基线也超过 16.67 ms；不能宣称已达到 60 FPS。此表用于确认效果确实运行及相对开销，不能换算为 820A 的绝对性能。截图库转换会额外改变渲染路径，故不纳入此表。

真车仍需核对：高德实时纹理换页、地图触控与页面手势边界、四种效果帧耗时、音乐持续播放时的内存与系统进程行为。优先选择平移进行实车对比；淡入/缩放等可选效果不能承诺与平移相同 GPU 开销。

## 复现

```sh
python3 app/tools/flutter_task.py analyze --no-pub
python3 app/tools/flutter_task.py test --no-pub
python3 app/native-tests/tools/test-navigation-media-performance.py --prove-regressions
python3 app/native-tests/tools/test-netease-adapter.py
python3 app/native-tests/tools/test-official-media-bridge.py
python3 app/tools/flutter_task.py drive --driver=test_driver/page_motion_driver.dart --target=integration_test/page_motion_test.dart --profile --no-dds -d emulator-5580
python3 app/tools/flutter_task.py build apk --release --target-platform android-arm64,android-x64 --split-per-abi
```

车机包：`app/build/app/outputs/flutter-apk/UNI-Launcher-0.6.11-IP753.apk`。最终构建、签名摘要与模拟器结果见 [release-report.json](../app/verification/page-motion/release-report.json)。
