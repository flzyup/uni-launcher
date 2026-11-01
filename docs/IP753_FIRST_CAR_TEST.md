# IP753 首轮实车测试与 0.4.1 修复

2026-10-24，实车 `dcy11` / MSM8996 arm64 / Android 9。连接车机自带热点后的 ADB 为 `192.168.5.1:5555`。共享手机热点的车机地址可 ping，但 TCP 5555 超时；USB 没有枚举到车机。原始日志、APK、地图与账号相关截图留在 Git 忽略的 `car-reports/`，本文件只记录脱敏结论。

## 调试工具与启动崩溃

合并调试工具已从 2.0 覆盖升级至 2.1，保留恢复记录，确认 ADB 正常。没有触发关闭端口或恢复设置。

0.4.0 普通开发签名 APK 在实车崩溃，原因是 `CAR_VENDOR_EXTENSION` 未授予。原车 SDK 的创建会异步连接服务，主线程回调中的 `SecurityException` 不在同步反射调用的 catch 范围内。0.4.1 在调用原车 SDK 前检查权限，未授权时返回不可用状态；保留状态心跳，不创建 SDK 客户端。修复版已在未获车辆权限时实车启动并保持进程稳定。

## 实车签名包

本车定义的车辆扩展权限为 `signature|privileged`，地图输入权限为 `signature`。核对原车 CarService 与已有调试工具的证书后，使用仓库外已有的签名文件生成单独的 `UNI-Launcher-<版本>-IP753.apk`。应用使用独立 UID，不声明系统共享 UID。开发/模拟器包保留原开发证书，两种证书的包不能相互直接覆盖。

构建完成后，在仓库根目录生成实车包：

```sh
python3 tools/sign_car_apk.py \
  --input app/build/app/outputs/flutter-apk/app-release.apk
```

`--out` 可以省略，默认写到 **`dist/UNI-Launcher-<版本>-IP753.apk`**（版本号从刚构建出来的 APK 里读，改了版本号不会对不上）。两个 app 的实车包都放在各自的 `dist/` 下，和 `app/build/...` 里的中间产物分开 —— 那个目录里曾经躺着几个 V2 移植前的旧 APK，体积和正式包几乎一样，很容易装错车机。

脚本只签名、校验证书和输出 APK，不连接或安装车辆。密钥不入 Git。

### 平台密钥从哪来

`sign_car_apk.py` 按下面的顺序找平台密钥（`platform.pk8` + `platform.x509.pem`）：

| 顺序 | 来源 | 说明 |
| --- | --- | --- |
| 1 | `--toolchain` | 显式指定 |
| 2 | `$IP753_SIGNING_DIR` | 环境变量 |
| 3 | `/data/tools/linkco-android/ip753-signing` | 原来那台构建机的路径 |
| 4 | `<repo>/../cardesk/platform-key` | **兄弟工程 cardesk 用的同一张密钥** |

第 4 项是关键：cardesk 的实车包也是用这张证书签的，所以两个 app 签出来是**同一张平台证书**，车控权限两边都拿得到。Java 与 apksigner 也一样自动找（`$JAVA_HOME` → `PATH` → 仓库自带工具链；apksigner 从 SDK 的 `build-tools` 里取最新的）。

### 证书是强校验的

脚本签完会 `apksigner verify --print-certs` 并比对指纹：

```
c8a2e9bccf597c2fb6dc66bee293fc13f2fc47ec77bc6b2b0d52c11f51192ab8
```

对不上就把产物**删掉**并报错 —— 签名不符的包装到车机上，现象是「句柄永远拿不到、氛围灯不亮」，跟「没接氛围灯」一模一样，很容易误判成通道问题。

### 两个 app 的产物命名

| app | 实车包（平台签名） | 包名 | 开发包（开发证书） |
| --- | --- | --- | --- |
| **UNI-Launcher**（本工程） | `dist/UNI-Launcher-<版本>-IP753.apk` | `xyz.i4o.uni.launcher` | `app/build/app/outputs/flutter-apk/app-debug.apk` |
| **CarDesk**（兄弟工程 cardesk） | `dist/CarDesk-platform-<包名>-<versionCode>.apk` | `com.ecarx.cardesk`（并存）或 `com.ecarx.qq.tool`（替换原桌面） | `app-debug.apk` |

两条规则：

1. **包名不同 ⇒ 两个 app 可以同时装在车上**（即使证书相同）；桌面上的名字也不同（`UNI 桌面` / `CarDesk 车控桌面`）。
2. **实车包的名字里带签名标记**（`IP753` / `platform`），和开发包一眼能分开 —— 开发证书的包装到车上会因签名不符拿不到车控权限。
3. **实车包只在 `dist/` 下**。`app/build/.../flutter-apk/` 里是构建中间产物，不是给车上装的；那里曾经同时躺着几个改版前的旧 APK，肉眼很难和正式包区分开。`dist/README.md` 每次出包时自动生成，写明**唯一该装的那个文件**和它的 SHA-256（和 cardesk 的做法一致）。

## 接入测试发现

- 地图容器需要检查 `INJECT_EVENTS`、`ACTIVITY_EMBEDDING`、`MANAGE_ACTIVITY_STACKS`，迁移已有任务还需要 `INTERNAL_SYSTEM_WINDOW`。补齐所需声明及预检查，失败时释放容器并显示回退入口。
- 高德已有任务可停留在其他桌面的虚拟显示器；仅发启动 Intent 不能保证进入新卡片。实车先验证定向迁移可显示地图，再加入自动检查/迁移并观察到卡片内实际地图。只允许移动关联应用自己的单任务栈，不移动包含其他应用的栈。
- 普通应用入口与 HOME 入口可产生不同任务，旧实例保留地图容器。参照官方 Launcher 使用 singleInstance，并增加旧实例清理。未通过脚本设置永久默认 HOME。
- Android 9 的 SurfaceView 不会随 Flutter Offstage 自动隐藏，曾浮到设置页上。增加逐卡片显隐通道，进入设置或弹窗时隐藏原生地图，回桌面后恢复；设置缩略预览不再启动另一个地图实例。
- 原车底栏占 136 像素，部分窗口已经在原生层缩小内容区域。重复应用 Flutter SafeArea 会多留一条空白；增加实际窗口检测与状态变更重布局，组件回归验证不重复扣除。
- 匹配签名包已获得车辆与地图所需权限。增加 `MEDIA_CONTENT_CONTROL`，使用媒体会话访问能力；实车网易云车机版的歌名、歌手、封面与播放进度已显示。本车当前版本未提供歌词，且 `canToggle/canNext/canPrevious` 均为 false，控制按钮保持禁用；仍需播放器专用适配。
- 官方适配框架存在，摄像头配置与 PM2.5 支持探测可以访问。本车未提供候选兼容层使用的 `ecarxcar_service`，因此空调、座椅、胎压没有获得有效值。需要改用本车实际框架接入；当前保持未知值与禁用写操作。
- 天气 Provider 的统一数据接口仍未接通；不使用地图界面上的温度代替天气卡片来源。

## 只读诊断

```sh
adb -s 192.168.5.1:5555 shell dumpsys activity \
  xyz.i4o.uni.launcher/.MainActivity --uni-state
```

输出来自缓存状态，不会调用车控。包含版本、权限、导航容器与显示 ID、车辆适配状态、媒体来源及能力；排除歌词正文、歌曲元数据、封面和应用图标。`tools/collect_car_readiness.py` 已加入此项。
