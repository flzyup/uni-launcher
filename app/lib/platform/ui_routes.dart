import 'package:flutter/widgets.dart';

/// 桌面窗口自己的 Navigator。
///
/// HOME 是「回桌面」的明确指令：全部应用页、最近任务、媒体/空调这类压桌面上的
/// 路由必须一次性退掉，否则用户按 HOME 只关掉设置页、面板还留在最上面。控制层
/// 拿不到 BuildContext，所以这里留一个全局可达的 key。
final GlobalKey<NavigatorState> launcherNavigatorKey = GlobalKey<NavigatorState>();

/// 把桌面窗口的路由栈退到根（第一屏）。
///
/// 引导早期还没有 Navigator 时安静返回；退栈和按返回键等价，面板内部的
/// `await route` 会正常结束。
void popToLauncherRoot() {
  final navigator = launcherNavigatorKey.currentState;
  if (navigator == null) return;
  navigator.popUntil((route) => route.isFirst);
}
