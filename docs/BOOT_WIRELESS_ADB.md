# 开机自动启动无线 adb

记忆配置里的开关。打开后，每次开机把 adbd 拉到 **5555** 端口，PC 直接
`adb connect <车机IP>:5555`，不用再插 USB 敲一次 `adb tcpip 5555`。

## 为什么需要一个「桥」

真正干活的两步只有 system 域做得动：

| 动作 | 为什么普通应用做不了 |
| --- | --- |
| `service.adb.tcp.port=5555` | 属性 SELinux 标签是 `adb_prop`，`untrusted_app` 域写会被属性服务拒绝（`setprop` 直接返回失败） |
| `ctl.restart=adbd` | init 控制属性，只有 init/root 类域能写；adbd 不重启就只会继续在原来的端口上听 |

参考机器上已有的 `Lynk05-IP753-DebugTool-2.2.apk`（`local.linkco.wirelessadb`）正是这么干的：
清单里 `android:sharedUserId="android.uid.system"` + 平台签名 → 装到 `/data/app` 后
`userId=1000`，跑在 `system_app` 域，于是 `SystemProperties.set("service.adb.tcp.port", …)`
和 `setProperty("ctl.restart", "adbd")` 都能成功；再用 `UsbManager` 拔插 USB gadget 做兜底，
最后用 `Socket` 连 `127.0.0.1:5555` 判断到底起没起来。

本项目照这个思路做了一个**无界面**的小桥，而不是把桌面本身改成 uid 1000
（桌面换 uid 会丢掉自己的 SharedPreferences 与所有既有配置）。

## 组成

| 组件 | 位置 | 作用 |
| --- | --- | --- |
| 桥 | `android-helper/adb-bridge/`（`xyz.i4o.uni.adbbridge`，uid 1000） | 写调试开关、写端口属性、`ctl.restart adbd`、USB 兜底、探测端口、把结果写进 `Settings.Global` |
| 桌面 | `WirelessAdb.java` + 记忆配置里的开关 | 开机/点按发 SET 广播，自己探测 `127.0.0.1:5555`，把状态显示出来 |

桥的权限面：

- 定义 `xyz.i4o.uni.adb.BRIDGE`（`protectionLevel=signature`），`SetReceiver` 挂这个权限，
  只有同平台签名的包（也就是 UNI 桌面）能发 SET；
- `BootReceiver` 只接 `BOOT_COMPLETED`，不加权限（系统广播）；
- 桥自己声明 `RECEIVE_BOOT_COMPLETED`、`WRITE_SECURE_SETTINGS`、`MANAGE_USB`。

## 一次开机发生了什么

1. 系统发 `BOOT_COMPLETED` → 桥的 `BootReceiver`（异步线程）按自己存的开关值决定做不做；
2. 桥把 `adb_enabled`、`development_settings_enabled` 置 1；
3. `service.adb.tcp.port=5555`、`persist.adb.tcp.port=5555`（后者能在部分机型上直接保住下次开机）；
4. `ctl.restart=adbd` → init 重启 adbd → adbd 读到 5555 开始在 TCP 上监听；
5. 桥用 `Socket` 探 5 秒，没起来就 `UsbManager.setCurrentFunctions(0)` 再切回来，逼 init 再启一次 adbd；
6. 结果写进 `Settings.Global`：`uni_adb_state`（`ready`/`pending`/`blocked`/`failed`/`off`）、
   `uni_adb_detail`（人话原因）、`uni_adb_at`（时间戳）。
7. 桌面侧：自己的 `LauncherRuntime` 在 `MainActivity.onCreate` / `GlobalDockService.onCreate`
   里调 `scheduleWirelessAdb()`，3 秒后发 SET 广播（带 `FLAG_INCLUDE_STOPPED_PACKAGES`，
   保证桥刚装好、还处于 stopped 状态也能收到），然后探测端口；没监听就 20 秒后再来，最多 6 次。

## 设置页显示

| 状态 | 文案 |
| --- | --- |
| `ready` | 已就绪 · `adbd 已在 5555 端口监听 · adb connect 192.168.x.x:5555` |
| `pending` | 等待中 · 已通知桥组件，等 adbd 监听（附原因） |
| `blocked` / `failed` | 被系统拦下 / 执行失败 · 附桥写回来的原因 |
| `missing` | 缺少桥组件 · 还没装 `UNI-AdbBridge` |
| `off` | 不生效 · 开关关着 |

## 安装与交付

两个包都在 `dist/`：

```
dist/UNI-Launcher-0.7.6-IP753.apk     # 桌面
dist/UNI-AdbBridge-1.0-IP753.apk      # 桥，12.7 KB，无界面，装一次即可
```

装机：

```
adb push dist/UNI-AdbBridge-1.0-IP753.apk /data/local/tmp/b.apk
adb shell pm install -r /data/local/tmp/b.apk
adb shell dumpsys package xyz.i4o.uni.adbbridge | grep userId   # 应该是 1000
```

构建桥（平台证书签名）：

```
python tools/build_adb_bridge.py --toolchain D:\PO\signing\ip753
```

## 万一没有无线 adb 了

- 插 USB，`adb tcpip 5555`，或者
- 打开车机上已装的「领克05调试工具」（`local.linkco.wirelessadb`，同样是 uid 1000）点一下无线调试，
  或者
- 断网重启车机：桥的开机广播会把端口重新拉起来（前提是桥已安装）。

## 实测记录

- 桥已装到车机 `/data/app`，`userId=1000`（`sharedUser=android.uid.system`），与参考工具一致。
- 端到端（改端口 → adbd 重启 → 5555 监听）还差一次上电验证：写这份文档时车机已离线
  （`ping 192.168.22.18` 不通），下一次上电就是第一次真机跑完整链路。
- 已验证的部分：桌面编译、桥编译、桥签名、桥安装后 uid 正确、Dart 侧 13 个记忆配置测试全过。
