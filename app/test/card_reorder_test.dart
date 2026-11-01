import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uni_launcher/model/card_layout.dart';
import 'package:uni_launcher/model/card_reorder.dart';
import 'package:uni_launcher/controller/launcher_controller.dart';
import 'package:uni_launcher/launcher_app.dart';
import 'fake_gateway.dart';

List<LauncherCard> fullPage([int page = 0]) => [
      for (var y = 0; y < 2; y++)
        for (var x = 0; x < 3; x++)
          LauncherCard('$page-$x-$y', 'clock', '时钟$x', x * 4, y * 3, 4, 3, page,
              layout: 'kept'),
    ];
String layout(List<LauncherCard> cards) =>
    jsonEncode(cards.map((c) => c.toJson()).toList());

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('occupied full-page slot swaps without deleting or resizing widgets',
      () {
    final original = fullPage(), before = layout(fullPage());
    final next = reorderCards(original, original.first.copyWith(x: 4))!;
    expect(validLayout(next), isTrue);
    expect(next.first.x, 4);
    expect(next[1].x, 0);
    expect(next.map((c) => c.id), original.map((c) => c.id));
    expect(next.map((c) => (c.w, c.h, c.title, c.layout)),
        original.map((c) => (c.w, c.h, c.title, c.layout)));
    expect(layout(original), before);
    expect(layout(next.skip(2).toList()), layout(original.skip(2).toList()));
  });

  test('large widget displaces several smaller widgets into its vacated area',
      () {
    final original = [
      const LauncherCard('a', 'clock', '大卡片', 0, 0, 8, 3, 0),
      const LauncherCard('b', 'clock', 'B', 0, 3, 4, 3, 0),
      const LauncherCard('c', 'clock', 'C', 4, 3, 4, 3, 0),
      const LauncherCard('d', 'clock', 'D', 8, 0, 4, 6, 0),
    ];
    final next = reorderCards(original, original.first.copyWith(y: 3))!;
    expect(validLayout(next), isTrue);
    expect(next[1].y, 0);
    expect(next[2].y, 0);
    expect(next[3], same(original[3]));
  });

  test(
      'cross-page full-grid drop exchanges a displaced card back to source page',
      () {
    final original = [...fullPage(), ...fullPage(1)];
    final next =
        reorderCards(original, original.first.copyWith(page: 1, x: 4, y: 3))!;
    expect(validLayout(next), isTrue);
    expect(next.first.page, 1);
    expect(next.where((c) => c.page == 0).length, 6);
    expect(next.where((c) => c.page == 1).length, 6);
    expect(next.singleWhere((c) => c.id == '1-1-1').page, 0);
  });

  test('resize makes space while impossible expansion is atomic', () {
    final original = [
      for (var y = 0; y < 3; y++)
        LauncherCard('$y', 'clock', '$y', 0, y * 2, 4, 2, 0),
    ];
    final grown = reorderCards(original, original.first.copyWith(h: 3))!;
    expect(validLayout(grown), isTrue);
    expect(grown.first.h, 3);
    expect(grown.skip(1).map((c) => (c.w, c.h)), everyElement((4, 2)));
    final full = fullPage(), before = layout(full);
    expect(reorderCards(full, full.first.copyWith(h: 4)), isNull);
    expect(reorderCards(full, full.first.copyWith(x: 11)), isNull);
    expect(
        reorderCards(full, full.first.copyWith(x: 4), searchBudget: 0), isNull);
    expect(layout(full), before);
  });

  test(
      'preview is temporary; drop commits once and editor cancellation restores all',
      () async {
    final g = FakeGateway();
    final controller = LauncherController(g);
    await controller.initialize();
    controller.cards = fullPage();
    controller.pageCount = 1;
    final before = controller.serialize();
    controller.beginEdit();
    expect(controller.beginPlacement('0-0-0'), isTrue);
    expect(controller.previewPlacement(controller.cards.first.copyWith(x: 4)),
        isTrue);
    expect(controller.serialize(), before);
    expect(controller.placementPreview!.first.x, 4);
    controller.finishPlacement();
    expect(controller.cards.first.x, 4);
    controller.cancelEdit();
    expect(controller.serialize(), before);
    controller.beginEdit();
    controller.beginPlacement('0-0-0', resizing: true);
    expect(controller.previewPlacement(controller.cards.first.copyWith(h: 4)),
        isFalse);
    expect(controller.finishPlacement(), isNull);
    expect(controller.serialize(), before);
    controller.dispose();
    await g.dispose();
  });

  test('card added on the trailing scratch page can be placed and resized',
      () async {
    final g = FakeGateway();
    final controller = LauncherController(g);
    await controller.initialize();
    // 空桌面点「添加卡片」：编辑态直落尾部草稿页，卡片也落在 page == pageCount
    // 这一页（草稿页要等 finishEdit 才转正）。此前 previewPlacement 用
    // `>= pageCount` 判断，把这唯一一条路径整个拦掉，表现就是刚添加的卡片
    // 按右下角手柄拖不动；退出编辑再长按进来就正常了。
    controller.cards = [];
    controller.pageCount = 1;
    controller.beginEditAtEnd();
    expect((controller.page, controller.pageCount), (1, 1));
    expect(controller.add('music'), isTrue);
    final added = controller.cards.single;
    expect((added.page, added.w, added.h), (1, 4, 3));

    expect(controller.beginPlacement(added.id, resizing: true), isTrue);
    expect(controller.previewPlacement(added.copyWith(h: added.h + 1)), isTrue);
    expect(controller.placementPreview!.single.h, added.h + 1);
    // 越界页仍然要拦：草稿页之外没有可落的网格。
    expect(controller.previewPlacement(added.copyWith(page: 2)), isFalse);
    controller.finishPlacement();
    expect(controller.cards.single.h, added.h + 1);

    controller.finishEdit();
    expect(controller.pageCount, 2);
    expect(controller.cards.single.page, 1);
    controller.dispose();
    await g.dispose();
  });

  test('bounded reorder stays valid across repeated full-grid moves', () {
    var cards = fullPage();
    final timer = Stopwatch()..start();
    for (var i = 0; i < 120; i++) {
      final card = cards[i % cards.length];
      final next = reorderCards(
          cards, card.copyWith(x: ((i + 1) % 3) * 4, y: ((i ~/ 3) % 2) * 3));
      expect(next, isNotNull);
      expect(validLayout(next!), isTrue);
      cards = next;
    }
    debugPrint('120 grid swaps: ${timer.elapsedMilliseconds}ms');
  });

  testWidgets(
      'real pointer drag previews displacement, animates and drops atomically',
      (t) async {
    t.view.physicalSize = const Size(1920, 1080);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    final g = FakeGateway(), c = LauncherController(g);
    await c.initialize();
    c.cards = fullPage();
    c.pageCount = 1;
    c.beginEdit();
    await t.pumpWidget(LauncherApp(controller: c));
    await t.pumpAndSettle();
    final grid = t.getRect(find.byKey(const ValueKey('grid-bounds'))).size;
    final gesture = await t
        .startGesture(t.getCenter(find.byKey(const ValueKey('move-0-0-0'))));
    await gesture.moveBy(Offset((grid.width + 20) / 3, 0));
    await t.pump();
    await t.pump(const Duration(milliseconds: 170));
    expect(c.placementPreview?.first.x, 4);
    expect(c.cards.first.x, 0);
    expect(find.byKey(const ValueKey('card-drag-feedback')), findsOneWidget);
    final animation = t.widget<AnimatedPositioned>(
        find.byKey(const ValueKey('position-0-1-0')));
    expect(animation.duration, const Duration(milliseconds: 150));
    final initialLeft =
        t.getRect(find.byKey(const ValueKey('position-0-1-0'))).left;
    await t.pump(const Duration(milliseconds: 75));
    final middleLeft =
        t.getRect(find.byKey(const ValueKey('position-0-1-0'))).left;
    expect(middleLeft, lessThan(initialLeft));
    expect(middleLeft,
        greaterThan(t.getRect(find.byKey(const ValueKey('grid-bounds'))).left));
    await t.pump(const Duration(milliseconds: 100));
    await gesture.up();
    await t.pumpAndSettle();
    expect(c.cards.first.x, 4);
    expect(c.cards[1].x, 0);
    expect(validLayout(c.cards), isTrue);
    expect(find.byKey(const ValueKey('card-drag-feedback')), findsNothing);
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox());
    c.dispose();
    await g.dispose();
  });

  testWidgets(
      'corner resize keeps tracking the same pointer and reflows content',
      (t) async {
    t.view.physicalSize = const Size(1920, 1080);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    final g = FakeGateway(), c = LauncherController(g);
    await c.initialize();
    c.cards = [
      const LauncherCard('signal', 'trafficLight', '红绿灯', 0, 0, 4, 2, 0)
    ];
    c.pageCount = 1;
    c.beginEdit();
    await t.pumpWidget(LauncherApp(controller: c));
    await t.pumpAndSettle();
    final grid = t.getRect(find.byKey(const ValueKey('grid-bounds'))).size;
    final gesture = await t
        .startGesture(t.getCenter(find.byKey(const ValueKey('resize-signal'))));
    await gesture
        .moveBy(Offset((grid.width + 20) / 12 * 4, (grid.height + 20) / 6));
    await t.pump();
    expect((c.placementTarget?.w, c.placementTarget?.h), (8, 3));
    await gesture.up();
    await t.pumpAndSettle();
    expect((c.cards.single.w, c.cards.single.h), (8, 3));
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox());
    c.dispose();
    await g.dispose();
  });

  testWidgets('edge dwell continues across pages and preserves widget state',
      (t) async {
    t.view.physicalSize = const Size(1920, 1080);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    final g = FakeGateway(), c = LauncherController(g);
    await c.initialize();
    c.cards = [...fullPage(), ...fullPage(1)];
    c.pageCount = 2;
    c.beginEdit();
    await t.pumpWidget(LauncherApp(controller: c));
    await t.pumpAndSettle();
    final sourceElement = t.element(find.byKey(const ValueKey('0-0-0')));
    final grid = t.getRect(find.byKey(const ValueKey('grid-bounds')));
    final start = t.getCenter(find.byKey(const ValueKey('move-0-0-0')));
    final gesture = await t.startGesture(start);
    await gesture.moveTo(Offset(grid.right - 8, start.dy));
    await t.pump();
    await t.pump(const Duration(milliseconds: 460));
    await t.pump();
    expect(c.page, 1);
    expect(c.placing, isTrue);
    await t.pump(const Duration(milliseconds: 170));
    expect(c.placementTarget?.page, 1);
    await gesture.up();
    await t.pumpAndSettle();
    expect(c.cards.first.page, 1);
    expect(validLayout(c.cards), isTrue);
    expect(t.element(find.byKey(const ValueKey('0-0-0'))), same(sourceElement));
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox());
    c.dispose();
    await g.dispose();
  });

  testWidgets(
      'pointer cancellation and impossible resizing restore the whole layout',
      (t) async {
    t.view.physicalSize = const Size(1920, 1080);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    final g = FakeGateway(), c = LauncherController(g);
    await c.initialize();
    c.cards = fullPage();
    c.pageCount = 1;
    c.beginEdit();
    final before = layout(c.cards);
    await t.pumpWidget(LauncherApp(controller: c));
    await t.pumpAndSettle();
    final grid = t.getRect(find.byKey(const ValueKey('grid-bounds'))).size;
    final gesture = await t
        .startGesture(t.getCenter(find.byKey(const ValueKey('move-0-0-0'))));
    await gesture.moveBy(Offset((grid.width + 20) / 3, 0));
    await t.pump();
    await t.pump(const Duration(milliseconds: 170));
    await gesture.cancel();
    await t.pumpAndSettle();
    expect(layout(c.cards), before);
    expect(c.placing, isFalse);
    final resize = await t
        .startGesture(t.getCenter(find.byKey(const ValueKey('resize-0-0-0'))));
    await resize.moveBy(Offset(0, (grid.height + 20) / 6));
    await t.pump();
    expect(c.placementValid, isFalse);
    await resize.up();
    await t.pumpAndSettle();
    expect(layout(c.cards), before);
    expect(find.byKey(const ValueKey('card-drop-preview')), findsNothing);
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox());
    c.dispose();
    await g.dispose();
  });
}
