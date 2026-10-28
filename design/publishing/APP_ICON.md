# UNI 桌面应用图标

当前采用 `uni-logo-concepts-v2.png` 中方案 01 的连笔 UNI 标志，以矢量重建：直角方形、纯色深蓝背景（`#0D203B`），保留银白到冰蓝的连笔 U/N 和独立 I。背景无渐变、曲面装饰或内缩留白。

- 矢量源：`uni-app-icon-connected.svg`
- 高分辨率 PNG：`uni-app-icon-connected-2048.png`、`uni-app-icon-connected-1024.png`
- 预览：`uni-app-icon-connected-512.png`
- Android 主图标：`app/android/app/src/main/res/drawable/uni_icon.xml`（项目根目录相对路径）
- Android 通知图标：`app/android/app/src/main/res/drawable/uni_notification.xml`，仅保留白色字形及透明背景。

主应用和“UNI桌面设置”共用主图标；`mipmap-*` 中的五档历史启动图标已同步。PNG 使用铺满画布的纯色背景，四角不透明，所有尺寸均从同一组路径直接渲染。其他桌面或系统可能另外对应用图标施加形状遮罩。

在项目根目录运行 `python3 tools/export_app_icon.py` 可重新生成上述资源，需要 Python 3 和 Pycairo。路径及渐变统一定义在该脚本中，修改后应重新导出以保持 SVG、Android Vector Drawable 与 PNG 一致。

`uni-app-icon-2048.png` 为此前旧 U 字标的历史导出，不是当前应用图标。
