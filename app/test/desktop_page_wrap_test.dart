import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uni_launcher/controller/launcher_controller.dart';
import 'package:uni_launcher/launcher_app.dart';
import 'package:uni_launcher/widgets/page_transition.dart';
import 'fake_gateway.dart';

/// 桌面翻页两件事（用户 2026-11-14）：
/// ① 普通浏览时不显示那张「空白尾页」（只有编辑态才挂，编辑态仍能加卡）；
/// ② 在最后一页继续向左（或第一页继续向右）时**环回**到另一端 —— 越界跟手一小段、
///    松手后原地淡入，不做位移动画。
void main() {
  testWidgets('普通态不显示空白尾页，进编辑态才出现', (t) async {
    t.view.physicalSize = const Size(1920, 1080);
    t.view.devicePixelRatio = 1;
    final g = FakeGateway(), c = LauncherController(g);
    await c.initialize();
    await t.pumpWidget(LauncherApp(controller: c));
    await t.pumpAndSettle();
    addTearDown(() async {
      await t.pumpWidget(const SizedBox.shrink());
      c.dispose();
      await g.dispose();
      t.view.resetPhysicalSize();
      t.view.resetDevicePixelRatio();
    });

    // 未激活的页是 offstage（保留挂载、不绘制），所以查找要跳过 offstage 过滤。
    Finder grid(int page) =>
        find.byKey(ValueKey('desktop-grid-$page'), skipOffstage: false);
    expect(c.pageCount, 2, reason: '默认两页');
    expect(grid(0), findsOneWidget);
    expect(grid(1), findsOneWidget);
    // 第三页是编辑态的临时尾页，普通浏览下不该存在（也就滑不到）。
    expect(grid(2), findsNothing);

    c.beginEdit();
    await t.pumpAndSettle();
    expect(grid(2), findsOneWidget, reason: '编辑态要留着它承载"新页放卡"');

    c.cancelEdit();
    await t.pumpAndSettle();
    expect(grid(2), findsNothing);
    expect(t.takeException(), isNull);
  });

  testWidgets('最后一页继续向左滑 → 环回第一页（越界有阻尼，不做位移跳转）',
      (t) async {
    t.view.physicalSize = const Size(1000, 600);
    t.view.devicePixelRatio = 1;
    final position = ValueNotifier<double>(1);
    final requests = <int>[];
    final key = GlobalKey<DesktopPageStackState>();
    addTearDown(position.dispose);
    await t.pumpWidget(MaterialApp(
        home: DesktopPageStack(
            key: key,
            page: 1,
            effect: 'slide',
            position: position,
            wrap: true,
            onPageRequested: requests.add,
            children: const [
          ColoredBox(color: Color(0xFF101010)),
          ColoredBox(color: Color(0xFF202020)),
        ])));
    await t.pumpAndSettle();

    key.currentState!.dragStart();
    // 在最后一页继续往左拖 600px（一屏宽 1000）：第一页从右侧跟手滑进来。
    key.currentState!.dragUpdate(-600);
    await t.pump();
    expect(position.value, closeTo(1.6, .01), reason: '越界部分按平移跟着手指走');
    expect(requests, isEmpty, reason: '还没松手，不该换页');

    key.currentState!.dragEnd(-900);
    // 收尾是 150ms 的平移，不是"一帧跳过去"。
    await t.pump(const Duration(milliseconds: 60));
    expect(requests, isEmpty);
    await t.pumpAndSettle();
    expect(requests, [0], reason: '环回到第一页');
    expect(position.value, 0);
    expect(t.takeException(), isNull);
  });

  testWidgets('第一页继续向右滑 → 环回最后一页', (t) async {
    t.view.physicalSize = const Size(1000, 600);
    t.view.devicePixelRatio = 1;
    final position = ValueNotifier<double>(0);
    final requests = <int>[];
    final key = GlobalKey<DesktopPageStackState>();
    addTearDown(position.dispose);
    await t.pumpWidget(MaterialApp(
        home: DesktopPageStack(
            key: key,
            page: 0,
            effect: 'slide',
            position: position,
            wrap: true,
            onPageRequested: requests.add,
            children: const [
          ColoredBox(color: Color(0xFF101010)),
          ColoredBox(color: Color(0xFF202020)),
          ColoredBox(color: Color(0xFF303030)),
        ])));
    await t.pumpAndSettle();

    key.currentState!.dragStart();
    key.currentState!.dragUpdate(600); // 往右拖：最后一页从左侧滑进来
    await t.pump();
    expect(position.value, closeTo(-.6, .01));
    key.currentState!.dragEnd(900);
    await t.pumpAndSettle();
    expect(requests, [2]);
    expect(position.value, 2);
    expect(t.takeException(), isNull);
  });

  testWidgets('环回是"原地淡入"，不是把下一屏整体推过来', (t) async {
    t.view.physicalSize = const Size(800, 400);
    t.view.devicePixelRatio = 1;
    final position = ValueNotifier<double>(1);
    final boundaryKey = GlobalKey();
    final key = GlobalKey<DesktopPageStackState>();
    var page = 1;
    addTearDown(position.dispose);
    await t.pumpWidget(MaterialApp(
        home: StatefulBuilder(builder: (ctx, setState) {
      return RepaintBoundary(
          key: boundaryKey,
          child: SizedBox(
              width: 800,
              height: 400,
              child: DesktopPageStack(
                  key: key,
                  page: page,
                  effect: 'slide',
                  position: position,
                  wrap: true,
                  onPageRequested: (p) => setState(() => page = p),
                  children: const [
                    ColoredBox(color: Color(0xFF008000)), // 第一页：绿
                    ColoredBox(color: Color(0xFF800080)), // 当前页：紫
                  ])));
    })));
    await t.pumpAndSettle();

    // 屏幕上左右两点：平移期间左半还是当前页（紫）、右半已经是第一页（绿）。
    Future<(int, int, int)> at(int x) async {
      var rgb = (0, 0, 0);
      final b =
          boundaryKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
      await t.runAsync(() async {
        final image = await b.toImage();
        final bytes =
            await image.toByteData(format: ui.ImageByteFormat.rawRgba);
        final px = bytes!.buffer.asUint8List();
        final i = (200 * 800 + x) * 4;
        rgb = (px[i].toInt(), px[i + 1].toInt(), px[i + 2].toInt());
      });
      return rgb;
    }

    key.currentState!.dragStart();
    key.currentState!.dragUpdate(-400); // 越过边界半个页宽
    await t.pump();
    final (rL, gL, _) = await at(100);
    expect((rL, gL), (128, 0), reason: '左半还是当前页');
    final (rR, gR, _) = await at(700);
    expect((rR, gR), (0, 128), reason: '右半已经滑进来第一页（平移，不是叠影）');

    key.currentState!.dragEnd(-900);
    await t.pump();
    await t.pump(const Duration(milliseconds: 60));
    // 还在平移中：两侧内容都在，但已经往第一页的方向走。
    expect(await at(700), (0, 128, 0));

    await t.pumpAndSettle();
    expect(await at(100), (0, 128, 0), reason: '落定在第一页');
    expect(await at(700), (0, 128, 0));
    expect(t.takeException(), isNull);
  });

  testWidgets('三页桌面：环回位移仍是 1:1 跟手（不会一动就半屏）', (t) async {
    t.view.physicalSize = const Size(1600, 800);
    t.view.devicePixelRatio = 1;
    final position = ValueNotifier<double>(2);
    final key = GlobalKey<DesktopPageStackState>();
    final boundaryKey = GlobalKey();
    addTearDown(position.dispose);
    await t.pumpWidget(MaterialApp(
        home: RepaintBoundary(
            key: boundaryKey,
            child: SizedBox(
                width: 1600,
                height: 800,
                child: DesktopPageStack(
                    key: key,
                    page: 2,
                    effect: 'slide',
                    position: position,
                    wrap: true,
                    children: const [
                      ColoredBox(color: Color(0xFFC00000)), // 第一页：红
                      ColoredBox(color: Color(0xFF00C000)), // 第二页：绿
                      ColoredBox(color: Color(0xFF0000C0)), // 第三页：蓝（当前）
                    ])))));
    await t.pumpAndSettle();

    Future<(int, int, int)> at(int x) async {
      var rgb = (0, 0, 0);
      final b =
          boundaryKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
      await t.runAsync(() async {
        final image = await b.toImage();
        final bytes =
            await image.toByteData(format: ui.ImageByteFormat.rawRgba);
        final px = bytes!.buffer.asUint8List();
        final i = (400 * 1600 + x) * 4;
        rgb = (px[i].toInt(), px[i + 1].toInt(), px[i + 2].toInt());
      });
      return rgb;
    }

    // 拖 10% 页宽：第一页只该从右边露出 10%，而不是半屏。
    // （之前按真实页距 2 归一化，位移被砍一半，手指一动就窜进来 47%。）
    key.currentState!.dragStart();
    key.currentState!.dragUpdate(-160);
    await t.pump();
    expect(position.value, closeTo(2.1, .001));
    expect(await at(1200), (0, 0, 192), reason: '左边仍是当前页');
    expect(await at(1430), (0, 0, 192), reason: '到 1440 之前都还是当前页');
    expect(await at(1590), (192, 0, 0), reason: '右边 10% 才是第一页');
    expect(t.takeException(), isNull);
  });

  testWidgets('没开环回时（编辑态）到头只会回弹，不跳页', (t) async {
    t.view.physicalSize = const Size(1000, 600);
    t.view.devicePixelRatio = 1;
    final position = ValueNotifier<double>(1);
    final requests = <int>[];
    final key = GlobalKey<DesktopPageStackState>();
    addTearDown(position.dispose);
    await t.pumpWidget(MaterialApp(
        home: DesktopPageStack(
            key: key,
            page: 1,
            effect: 'slide',
            position: position,
            onPageRequested: requests.add,
            children: const [
          ColoredBox(color: Color(0xFF101010)),
          ColoredBox(color: Color(0xFF202020)),
        ])));
    await t.pumpAndSettle();

    key.currentState!.dragStart();
    key.currentState!.dragUpdate(-600);
    await t.pump();
    expect(position.value, 1, reason: '没开环回就不会越界');
    key.currentState!.dragEnd(-900);
    await t.pumpAndSettle();
    expect(requests, isEmpty);
    expect(position.value, 1);
    expect(t.takeException(), isNull);
  });
}
