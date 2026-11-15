import 'package:flutter/widgets.dart';

import '../theme/design_tokens.dart';

/// 把 Overlay 里的内容放回桌面那套「1600 宽的设计坐标系」。
///
/// 桌面主体在 `launcher_shell` 里套了 `FittedBox`（`scale = 屏宽 / 1600`），
/// 但 `showGeneralDialog` / `PopupRoute` 挂在 **root overlay** 上，不吃那层缩放。
/// 于是所有按 `Design.dz` / `Design.px` 写死的浮层尺寸会按 1:1 逻辑像素落地：
/// 模拟器 1080×612 上，716.67 高的传文件面板就有 196 单位跑到了屏幕外（顶部被切）。
///
/// 包一层 [CanvasScope] 之后，浮层与桌面同一比例；在 1600×900 的车机上
/// `scale == 1`，是恒等变换，观感零变化。
class CanvasScope extends StatelessWidget {
  final Widget child;
  const CanvasScope({super.key, required this.child});

  @override
  Widget build(BuildContext context) =>
      LayoutBuilder(builder: (context, box) {
        // 车机若把逻辑宽度报成别的值（模拟器、无边窗口），这里统一折算。
        final width = box.maxWidth > 0 ? box.maxWidth : Design.canvasWidth;
        final scale = width / Design.canvasWidth;
        final height = box.maxHeight > 0 ? box.maxHeight / scale : 900.0;
        final size = Size(Design.canvasWidth, height);
        return FittedBox(
            fit: BoxFit.fill,
            child: SizedBox.fromSize(
                size: size, child: CanvasScopeInfo(size: size, child: child)));
      });
}

/// 当前浮层所在的画布尺寸（设计单位）。浮层用它把「写死的高度」夹到画布内。
class CanvasScopeInfo extends InheritedWidget {
  final Size size;
  const CanvasScopeInfo({super.key, required this.size, required super.child});

  static Size of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<CanvasScopeInfo>()?.size ??
      const Size(Design.canvasWidth, 900);

  @override
  bool updateShouldNotify(CanvasScopeInfo old) => old.size != size;
}
