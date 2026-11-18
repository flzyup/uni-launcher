# 构建签名：全项目只有一张证书（AOSP 测试签名）

> 结论先说：`debug` / `profile` / `release` / 实车包（`tools/sign_car_apk.py`）**全部**签 AOSP 测试签名（testkey）。仓库里不再有第二张证书，也不再有任何「签名回落」。

## 1. 为什么只能有一张

车机的 `android.car.permission.CAR_VENDOR_EXTENSION`、原车媒体中心传输回调、车控与氛围灯通道都是 `signature|privileged`，**按证书授予**。证书对不上时车控 SDK 不会被创建，句柄永远拿不到，界面只会显示「此设备没有原车氛围灯接口 / 车辆厂商读取权限未授权」，看不出真正原因（`OfficialCarReader.java:399`、`:421`）。

因此「开发包用开发证书、实车包用实车证书」这套在本项目里是错的：车机只认 AOSP 测试签名，开发包也得用同一张，否则每换一次包就要重装。

## 2. 证书

| 项 | 值 |
| --- | --- |
| 主题 | `EMAILADDRESS=android@android.com, CN=Android, OU=Android, O=Android, L=Mountain View, ST=California, C=US` |
| SHA-256 | `C8:A2:E9:BC:CF:59:7C:2F:B6:DC:66:BE:E2:93:FC:13:F2:FC:47:EC:77:BC:6B:2B:0D:52:C1:1F:51:19:2A:B8`（无冒号小写：`c8a2e9bccf597c2fb6dc66bee293fc13f2fc47ec77bc6b2b0d52c11f51192ab8`） |
| SHA-1 | `27:19:6E:38:6B:87:5E:76:AD:F7:00:E7:EA:84:E4:C6:EE:E3:3D:FA` |
| keystore | `app/android/signing/uni-debug.keystore`（JKS，私钥不入库） |
| alias / 口令 | `uni-debug` / `android`（store 与 key 同口令） |
| 签名方案 | v2 + v3，v1 关闭；单一签名者 |

> 这是 AOSP 的 **testkey**（测试签名），不是平台的 release key，也不是商店发布证书。口令是公开的 `android`，因此**只能用于本项目的测试分发**，不要拿它签任何对外产品。

## 3. Gradle 侧

`app/android/app/build.gradle.kts:45-96` 只有一个 `signingConfigs.create("aospTest")`：

- keystore 查找顺序：`UNI_SIGNING_STORE` → `app/android/signing/uni-debug.keystore` → `/data/tools/linkco-android/uni-debug.keystore`（原构建机绝对路径）。
- **三个都不存在 → 构建失败**（`GradleException`，打印试过的绝对路径）。
- 三个构建类型都指向它：`debug`、`release`、`maybeCreate("profile")`（只换证书，不继承 release 的 R8，否则 profile 会因 `integration_test` 插件缺类而失败）。

历史教训：旧配置的 `storeFile` 里有 `?: ${user.home}/.android/...` 的回落。同一台机器两天内产出两个签名的包，设备上覆盖安装报 `INSTALL_FAILED_UPDATE_INCOMPATIBLE`，而构建日志一句提示都没有。现在宁可构建失败，也不猜。

## 4. 实车包

`tools/sign_car_apk.py` 不再要求 PEM 素材，优先用**同一份 keystore**：

1. `--ks` → `UNI_SIGNING_STORE` → `app/android/signing/uni-debug.keystore` → `/data/tools/linkco-android/uni-debug.keystore`；
2. 都没有时才退回 `platform.pk8` + `platform.x509.pem`（`--toolchain` → `IP753_SIGNING_DIR` → `/data/tools/linkco-android/ip753-signing` → `<workspace>/cardesk/platform-key`）；
3. 重签（v1+v2+v3）后 `apksigner verify --print-certs`，与常量 `EXPECTED_SHA256` 逐字比对，不符就删包并退出。

```sh
python3 tools/sign_car_apk.py \
  --input app/build/app/outputs/flutter-apk/app-arm64-v8a-release.apk \
  --out app/build/app/outputs/flutter-apk/UNI-Launcher-<版本>-IP753.apk
```

它额外做一件事：往 `assets/uni-nav-insets.apk` 注入导航栏 inset 资源（`build_nav_insets`），产出包与原始构建产物分开存放，避免装错。

## 5. 怎么核对（任何一台机器、任何一个包）

```sh
apksigner verify --print-certs <apk>    # 看 certificate SHA-256 digest
apksigner verify -v <apk>               # 看 v2/v3 方案
aapt2 dump badging <apk> | head -1      # 看包名 / versionCode
```

期望：`certificate SHA-256 digest: c8a2e9bccf597c2fb6dc66bee293fc13f2fc47ec77bc6b2b0d52c11f51192ab8`，`v2=true`、`v3=true`。

设备上已安装包的签名：

```powershell
adb -s <serial> shell dumpsys package xyz.i4o.uni.launcher | Select-String 'signatures'
```

## 6. 迁移注意

- **0.7.6 之前装过的设备**（包括模拟器、之前分发出去的测试包）用的是 `~/.android/debug.keystore`（SHA-256 `1A:ED:6E:29:…`）。那批设备必须**卸载重装一次**，同签名升级从这一版开始才成立。想保住设置：先 `su -c 'tar -czf /sdcard/uni-data.tgz -C /data/data/xyz.i4o.uni.launcher shared_prefs files'`，重装后解回并 `chown` 成应用 uid。
- OTA 装包会核对「包名 + versionCode + 签名数组」（`MainActivity.java:125`），签名不一致直接 `SecurityException("package identity")`；所以迁移期要先把设备刷到同签名版本，再谈 OTA。

## 本文依据

- `app/android/app/build.gradle.kts:45-96`（签名配置、三种构建类型、keystore 查找与失败策略）
- `tools/sign_car_apk.py:27-33`、`:78-124`（`--ks` 参数与素材查找）、`:209-224`（重签与指纹校验）
- `app/README.md:76-104`（README 侧同一份结论）
- `docs/interface/10-原生组件.md` §5.1–5.4（权限与签名落点、`otaInstall` 的签名核对）
- 实测：`apksigner verify --print-certs` 对本机 6 个产物（release / 三个 ABI split / profile / debug）与 `tools/sign_car_apk.py` 产出的实车包，证书 SHA-256 全部为 `c8a2e9bc…`，v2+v3 一致。
