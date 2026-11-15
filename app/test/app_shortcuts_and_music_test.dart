import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uni_launcher/controller/launcher_controller.dart';
import 'package:uni_launcher/launcher_app.dart';
import 'package:uni_launcher/model/card_layout.dart';
import 'package:uni_launcher/widgets/music_app_picker.dart';
import 'fake_gateway.dart';

void main() {
  test('music options only contain detected players and live sessions', () {
    final options = musicAppOptions({
      'apps': [
        {'id': 'qq/.Main', 'package': 'qq', 'label': 'QQ', 'isMusic': true},
        {'id': 'maps/.Main', 'package': 'maps', 'label': 'Map'},
        {'id': 'session/.Main', 'package': 'session', 'label': 'Session'},
        {'id': 'qq/.Alt', 'package': 'qq', 'label': 'QQ'},
      ],
      'media': {
        'sessions': [
          {'package': 'session'}
        ]
      },
    });
    expect(options.map((a) => a['package']), ['qq', 'session']);
  });

  testWidgets('播放器弹层右上角的换音源入口只列音乐应用并切换音源',
      (t) async {
    t.view.physicalSize = const Size(1920, 1080);
    t.view.devicePixelRatio = 1;
    final g = FakeGateway();
    g.state['apps'] = [
      {'id': 'qq/.Main', 'package': 'qq', 'label': 'QQ音乐', 'isMusic': true},
      {'id': 'map/.Main', 'package': 'map', 'label': '地图'},
    ];
    final c = LauncherController(g);
    await c.initialize();
    c.cards = [const LauncherCard('music-1', 'music', '音乐', 0, 0, 4, 3, 0)];
    await t.pumpWidget(LauncherApp(controller: c));
    await t.pumpAndSettle();
    // 稿子把换音源挪进播放器弹层：桌面卡片上不再有这颗键。
    expect(find.byKey(const ValueKey('music-app-picker')), findsNothing);
    await t.tap(find.byKey(const ValueKey('music-card-open-panel')).first);
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('media-app-picker')));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('music-option-qq')), findsOneWidget);
    expect(find.byKey(const ValueKey('music-option-map')), findsNothing);
    await t.tap(find.byKey(const ValueKey('music-option-qq')));
    await t.pumpAndSettle();
    expect(
        g.commands
            .any((v) => v['action'] == 'select-player' && v['value'] == 'qq'),
        isTrue);
    await t.pumpWidget(const SizedBox());
    c.dispose();
    await g.dispose();
    t.view.resetPhysicalSize();
    t.view.resetDevicePixelRatio();
  });

  testWidgets(
      'shortcut layouts render their supported capacities without overflow',
      (t) async {
    t.view.physicalSize = const Size(1920, 1080);
    t.view.devicePixelRatio = 1;
    final g = FakeGateway();
    g.state['apps'] = [
      for (var i = 0; i < 12; i++)
        {'id': 'p$i/.Main', 'package': 'p$i', 'label': '应用$i'}
    ];
    final c = LauncherController(g);
    await c.initialize();
    for (final height in [2, 3, 4]) {
      c.cards = [
        LauncherCard('short-1', 'shortcuts', '快捷应用', 0, 0, 4, height, 0,
            shortcutApps: [for (var i = 0; i < 12; i++) 'p$i/.Main'])
      ];
      await t.pumpWidget(LauncherApp(key: ValueKey(height), controller: c));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull, reason: '4x$height');
      expect(find.byKey(const ValueKey('shortcut-p0/.Main')), findsOneWidget);
    }
    await t.pumpWidget(const SizedBox());
    c.dispose();
    await g.dispose();
    t.view.resetPhysicalSize();
    t.view.resetDevicePixelRatio();
  });

  testWidgets('shortcut selection persists per card and launches selected app',
      (t) async {
    t.view.physicalSize = const Size(1920, 1080);
    t.view.devicePixelRatio = 1;
    final g = FakeGateway();
    g.state['apps'] = [
      {'id': 'one/.Main', 'package': 'one', 'label': '应用一'},
      {'id': 'two/.Main', 'package': 'two', 'label': '应用二'},
    ];
    final c = LauncherController(g);
    await c.initialize();
    c.cards = [
      const LauncherCard('short-1', 'shortcuts', '快捷应用', 0, 0, 4, 3, 0)
    ];
    await t.pumpWidget(LauncherApp(controller: c));
    await t.pumpAndSettle();
    // 卡头不再有铅笔按钮，入口是虚线「添加」格（未选满时）或长按整卡。
    await t.tap(find.byKey(const ValueKey('shortcuts-add-short-1')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('shortcut-option-one/.Main')));
    await t.tap(find.byKey(const ValueKey('shortcut-option-two/.Main')));
    await t.tap(find.byKey(const ValueKey('shortcut-picker-save')));
    await t.pumpAndSettle();
    expect(c.cards.first.shortcutApps, ['one/.Main', 'two/.Main']);
    expect((jsonDecode(g.saved!)['cards'] as List).first['shortcutApps'],
        ['one/.Main', 'two/.Main']);
    await t.tap(find.byKey(const ValueKey('shortcut-one/.Main')));
    await t.pumpAndSettle();
    expect(
        g.commands.any(
            (x) => x['action'] == 'launch-app' && x['value'] == 'one/.Main'),
        isTrue);
    await t.tap(find.byKey(const ValueKey('shortcuts-add-short-1')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('shortcut-option-one/.Main')));
    await t.tap(find.byKey(const ValueKey('shortcut-picker-save')));
    await t.pumpAndSettle();
    expect(c.cards.first.shortcutApps, ['two/.Main']);
    g.state['savedDesign'] = g.saved;
    final restored = LauncherController(g);
    await restored.initialize();
    expect(restored.cards.first.shortcutApps, ['two/.Main']);
    restored.dispose();
    await t.pumpWidget(const SizedBox());
    c.dispose();
    await g.dispose();
    t.view.resetPhysicalSize();
    t.view.resetDevicePixelRatio();
  });

  testWidgets('快捷应用不满一行时不画卡头，加号只补一颗', (t) async {
    t.view.physicalSize = const Size(1920, 1080);
    t.view.devicePixelRatio = 1;
    final g = FakeGateway();
    g.state['apps'] = [
      for (var i = 0; i < 12; i++)
        {'id': 'p$i/.Main', 'package': 'p$i', 'label': '应用$i'}
    ];
    final c = LauncherController(g);
    await c.initialize();

    Future<void> showCard(int w, int h, List<String> apps) async {
      c.cards = [
        LauncherCard('short-1', 'shortcuts', '快捷应用', 0, 0, w, h, 0,
            shortcutApps: apps)
      ];
      await t.pumpWidget(LauncherApp(controller: c));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
    }

    const add = ValueKey('shortcuts-add-short-1');
    const p0 = 'p0/.Main', p1 = 'p1/.Main', p2 = 'p2/.Main', p3 = 'p3/.Main';

    // 4×1 选 3 个：卡头让位，3 图标 + 1 颗加号。
    await showCard(4, 1, [p0, p1, p2]);
    expect(find.text('快捷应用'), findsNothing);
    expect(find.text('应用0'), findsNothing);
    expect(find.byKey(const ValueKey('shortcut-p2/.Main')), findsOneWidget);
    expect(find.byKey(add), findsOneWidget);
    // 图标不能吃满格子高度：一行的卡格子高就是卡内容高，吃满会顶住上下边框
    // （用户 2026-11-15 截图反馈）。留出 ~20% 的缝。
    // 用 getSize 而不是 getRect：桌面整体在缩放容器里，getRect 带父级变换，
    // 和 getSize 不是同一套坐标。
    final oneRowCell =
        t.getSize(find.byKey(const ValueKey('shortcut-p0/.Main')));
    final oneRowIcon = t.getSize(find
        .descendant(
            of: find.byKey(const ValueKey('shortcut-p0/.Main')),
            matching: find.byType(FittedBox))
        .first);
    expect(oneRowIcon.height, lessThan(oneRowCell.height * .85),
        reason: '4×1 图标要留上下间隙，不能顶住卡片边框');
    expect(oneRowIcon.height, greaterThan(oneRowCell.height * .7),
        reason: '别收得太小，一行档图标仍是这张卡的主体');

    // 4×2 的格子比图标高，图标是格宽限制的，不该跟着收（用户只让动顶边那一档）。
    await showCard(4, 2, [p0, p1, p2]);
    final twoRowCell =
        t.getSize(find.byKey(const ValueKey('shortcut-p0/.Main')));
    final twoRowIcon = t.getSize(find
        .descendant(
            of: find.byKey(const ValueKey('shortcut-p0/.Main')),
            matching: find.byType(FittedBox))
        .first);
    expect(twoRowIcon.width, greaterThan(twoRowCell.width * .95),
        reason: '4×2 那档图标原本就是格宽封顶，这一版不动它');

    // 4×1 选满 4 个：一行正好，加号收掉。
    await showCard(4, 1, [p0, p1, p2, p3]);
    expect(find.text('快捷应用'), findsNothing);
    expect(find.byKey(add), findsNothing);

    // 一个都没选的 2 格卡保留卡头：纯一颗加号认不出这张卡是干什么的。
    await showCard(4, 2, []);
    expect(find.text('快捷应用'), findsOneWidget);
    expect(find.byKey(add), findsOneWidget);

    // 4×2 选 3 个：同样不要卡头，加号也只补一颗（不把整行摊满）。
    await showCard(4, 2, [p0, p1, p2]);
    expect(find.text('快捷应用'), findsNothing);
    expect(find.byKey(add), findsOneWidget);

    // 4×2 选满 4 个：卡头回来。
    await showCard(4, 2, [p0, p1, p2, p3]);
    expect(find.text('快捷应用'), findsOneWidget);
    expect(find.byKey(add), findsNothing);

    // 4×3 起有两行，卡头 + 一行字都回来。
    await showCard(4, 3, [p0, p1, p2, p3]);
    expect(find.text('快捷应用'), findsOneWidget);
    expect(find.text('应用0'), findsOneWidget);
    expect(find.text('添加'), findsOneWidget);

    // 3 宽的卡容量是 3：选 1 个补一颗加号，选满 3 个就收掉。
    await showCard(3, 1, [p0]);
    expect(find.text('快捷应用'), findsNothing);
    expect(find.byKey(add), findsOneWidget);
    await showCard(3, 1, [p0, p1, p2]);
    expect(find.byKey(add), findsNothing);

    // 第 4 个应用在 3 宽的卡里没有格位，先不渲染；数据还在，拉宽会回来。
    await showCard(3, 2, [p0, p1, p2, p3]);
    expect(find.byKey(const ValueKey('shortcut-p3/.Main')), findsNothing);
    expect(find.byKey(const ValueKey('shortcut-p1/.Main')), findsOneWidget);

    await t.pumpWidget(const SizedBox());
    c.dispose();
    await g.dispose();
    t.view.resetPhysicalSize();
    t.view.resetDevicePixelRatio();
  });

  testWidgets('快捷应用按稿子铺 4 列方格，最后一格是虚线添加', (t) async {
    t.view.physicalSize = const Size(1920, 1080);
    t.view.devicePixelRatio = 1;
    final g = FakeGateway();
    g.state['apps'] = [
      for (var i = 0; i < 6; i++)
        {'id': 'p$i/.Main', 'package': 'p$i', 'label': '应用$i'}
    ];
    final c = LauncherController(g);
    await c.initialize();
    c.cards = [
      LauncherCard('short-1', 'shortcuts', '快捷应用', 0, 0, 4, 3, 0,
          shortcutApps: ['p0/.Main', 'p1/.Main', 'p2/.Main'])
    ];
    await t.pumpWidget(LauncherApp(controller: c));
    await t.pumpAndSettle();

    final tiles = [
      for (final id in ['p0', 'p1', 'p2'])
        t.getRect(find.byKey(ValueKey('shortcut-$id/.Main'))),
      t.getRect(find.byKey(const ValueKey('shortcuts-add-short-1'))),
    ];
    // 稿子 `.mini-apps` 是 4 等分格：四格同一行、同尺寸，添加格在最后一列
    // （原来是一颗 IconButton，尺寸与格子无关，所以这几个断言都会红）。
    for (final tile in tiles) {
      expect(tile.top, closeTo(tiles.first.top, .01), reason: '四格应在同一行');
      expect(tile.width, closeTo(tiles.first.width, .01));
      expect(tile.height, closeTo(tiles.first.height, .01));
    }
    expect(tiles.last.left, greaterThan(tiles[2].left));
    expect(t.takeException(), isNull);

    await t.pumpWidget(const SizedBox());
    c.dispose();
    await g.dispose();
    t.view.resetPhysicalSize();
    t.view.resetDevicePixelRatio();
  });
}
