import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uni_launcher/controller/launcher_controller.dart';
import 'package:uni_launcher/launcher_app.dart';
import 'package:uni_launcher/model/card_layout.dart';
import 'package:uni_launcher/theme/design_tokens.dart';
import 'package:uni_launcher/widgets/music_action_buttons.dart';

import 'fake_gateway.dart';

/// 音乐卡的「收藏 / 播放模式」两个按钮（移植自 CarDesk 音乐卡）。
///
/// 关键约束有三条：
/// 1. 播放器**不支持**的能力 → 按钮根本不画（亮一个点了没反应的按钮比没有更糟）；
/// 2. 收藏态是**三态**：已收藏 / 未收藏 / 不知道，图标与颜色都不同；
/// 3. 播放模式显示的是**当前模式**，点一下切到下一个（顺序 → 单曲 → 随机）。
void main() {
  Future<LauncherController> pumpMusicCard(
      WidgetTester tester, Map<String, dynamic> media,
      {int w = 4, int h = 4}) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1;
    final g = FakeGateway();
    g.state = {
      ...g.state,
      'demo': false,
      'media': {...g.state['media'] as Map<String, dynamic>, ...media},
    };
    final c = LauncherController(g);
    await c.initialize();
    c.cards = [LauncherCard('music-1', 'music', '正在播放', 0, 0, w, h, 0)];
    await tester.pumpWidget(LauncherApp(controller: c));
    await tester.pumpAndSettle();
    return c;
  }

  testWidgets('unsupported player gets no action buttons',
      (tester) async {
    await pumpMusicCard(tester, {
      'actionCaps': {'favorite': false, 'playMode': false},
    });
    expect(find.byKey(const ValueKey('music-favorite-button')), findsNothing);
    expect(find.byKey(const ValueKey('music-play-mode-button')), findsNothing);
    // 歌名本身还在
    expect(find.byKey(const ValueKey('music-card-title')), findsOneWidget);
  });

  testWidgets('missing actionCaps hides both buttons', (tester) async {
    await pumpMusicCard(tester, {'title': '向海而行'});
    expect(find.byKey(const ValueKey('music-favorite-button')), findsNothing);
    expect(find.byKey(const ValueKey('music-play-mode-button')), findsNothing);
  });

  testWidgets('favorite button shows outline heart when not favorited',
      (tester) async {
    await pumpMusicCard(tester, {
      'actionCaps': {'favorite': true, 'playMode': false},
      'favorited': false,
    });
    final button = find.byKey(const ValueKey('music-favorite-button'));
    expect(button, findsOneWidget);
    expect(
        find.descendant(of: button, matching: find.byIcon(Icons.favorite_border)),
        findsOneWidget);
    expect(find.byIcon(Icons.favorite), findsNothing);
    // 播放模式不支持 → 不画
    expect(find.byKey(const ValueKey('music-play-mode-button')), findsNothing);
  });

  testWidgets('favorite button shows filled heart when favorited',
      (tester) async {
    await pumpMusicCard(tester, {
      'actionCaps': {'favorite': true, 'playMode': false},
      'favorited': true,
    });
    final button = find.byKey(const ValueKey('music-favorite-button'));
    expect(
        find.descendant(of: button, matching: find.byIcon(Icons.favorite)),
        findsOneWidget);
    expect(find.byIcon(Icons.favorite_border), findsNothing);
  });

  testWidgets('unknown favorite state still shows an outline heart',
      (tester) async {
    // 「不知道」与「未收藏」在界面上要分得开：都是空心心形，但不知道时颜色更弱。
    await pumpMusicCard(tester, {
      'actionCaps': {'favorite': true, 'playMode': false},
      'favorited': null,
    });
    final button = find.byKey(const ValueKey('music-favorite-button'));
    expect(
        find.descendant(of: button, matching: find.byIcon(Icons.favorite_border)),
        findsOneWidget);
    expect(find.byIcon(Icons.favorite), findsNothing);
  });

  testWidgets('favorite button sends the favorite-toggle command',
      (tester) async {
    final g = FakeGateway();
    g.state = {
      ...g.state,
      'demo': false,
      'media': {
        ...g.state['media'] as Map<String, dynamic>,
        'actionCaps': {'favorite': true, 'playMode': false},
        'favorited': false,
      },
    };
    final c = LauncherController(g);
    await c.initialize();
    c.cards = [const LauncherCard('music-1', 'music', '正在播放', 0, 0, 4, 4, 0)];
    await tester.pumpWidget(LauncherApp(controller: c));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('music-favorite-button')));
    await tester.pumpAndSettle();
    expect(g.commands.any((c) => c['action'] == 'favorite-toggle'), isTrue);
  });

  testWidgets('play mode button reflects the current mode', (tester) async {
    await pumpMusicCard(tester, {
      'actionCaps': {'favorite': false, 'playMode': true},
      'playMode': 'SHUFFLE',
    });
    final button = find.byKey(const ValueKey('music-play-mode-button'));
    expect(button, findsOneWidget);
    expect(find.descendant(of: button, matching: find.byIcon(Icons.shuffle)),
        findsOneWidget);
    expect(find.byIcon(Icons.repeat), findsNothing);
  });

  testWidgets('play mode button falls back to repeat when unknown',
      (tester) async {
    // 模式未知时画「顺序」：此时点一下就是切到顺序播放。
    await pumpMusicCard(tester, {
      'actionCaps': {'favorite': false, 'playMode': true},
      'playMode': null,
    });
    final button = find.byKey(const ValueKey('music-play-mode-button'));
    expect(find.descendant(of: button, matching: find.byIcon(Icons.repeat)),
        findsOneWidget);
  });

  testWidgets('play mode button sends the play-mode-toggle command',
      (tester) async {
    final g = FakeGateway();
    g.state = {
      ...g.state,
      'demo': false,
      'media': {
        ...g.state['media'] as Map<String, dynamic>,
        'actionCaps': {'favorite': false, 'playMode': true},
        'playMode': 'REPEAT_ALL',
      },
    };
    final c = LauncherController(g);
    await c.initialize();
    c.cards = [const LauncherCard('music-1', 'music', '正在播放', 0, 0, 4, 4, 0)];
    await tester.pumpWidget(LauncherApp(controller: c));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('music-play-mode-button')));
    await tester.pumpAndSettle();
    expect(g.commands.any((c) => c['action'] == 'play-mode-toggle'), isTrue);
  });

  testWidgets('both buttons render next to the song title', (tester) async {
    await pumpMusicCard(tester, {
      'actionCaps': {'favorite': true, 'playMode': true},
      'favorited': true,
      'playMode': 'REPEAT_ONE',
    });
    expect(find.byKey(const ValueKey('music-card-title')), findsOneWidget);
    expect(find.byKey(const ValueKey('music-card-title-row')), findsOneWidget);
    expect(find.byKey(const ValueKey('music-favorite-button')), findsOneWidget);
    expect(find.byKey(const ValueKey('music-play-mode-button')), findsOneWidget);
    // 单曲循环 → repeat_one 图标
    expect(
        find.descendant(
            of: find.byKey(const ValueKey('music-play-mode-button')),
            matching: find.byIcon(Icons.repeat_one)),
        findsOneWidget);
  });

  testWidgets('两个按钮按 1.5 倍基准尺寸绘制', (tester) async {
    // 4×3 走「普通」版式：scale 固定 1，按钮尺寸就是基准 × 放大倍数。
    await pumpMusicCard(tester, {
      'actionCaps': {'favorite': true, 'playMode': true},
      'favorited': true,
      'playMode': 'REPEAT_ONE',
    }, w: 4, h: 3);
    // 这里量到的是**画布单位**（桌面画布 1600 宽），不是 1920 视口的物理像素：
    // 47.5 = Design.px(38) × 1.5。放到 1920 的真机上再乘 1.2 倍。
    final expected = Design.px(38) * MusicActionButtons.sizeFactor;
    expect(expected, 47.5, reason: '基准 38 画布单位放大 1.5 倍');
    for (final key in const [
      ValueKey('music-favorite-button'),
      ValueKey('music-play-mode-button')
    ]) {
      final size = tester.getSize(find.byKey(key));
      expect(size.width, closeTo(expected, .5), reason: '$key 宽度');
      expect(size.height, closeTo(expected, .5), reason: '$key 高度');
    }
  });

  testWidgets('放大后各版式都不溢出', (tester) async {
    // RenderFlex 溢出在 flutter_test 里会直接判失败，这里逐个版式过一遍：
    // 4×1（一格档，自己画歌名没有按钮）/ 4×2 两行档 / 4×3 / 4×4 稿子 f1 / 8×6 大卡。
    for (final size in const [(4, 1), (4, 2), (4, 3), (4, 4), (8, 6)]) {
      await pumpMusicCard(tester, {
        'actionCaps': {'favorite': true, 'playMode': true},
        'favorited': true,
        'playMode': 'REPEAT_ONE',
      }, w: size.$1, h: size.$2);
      expect(tester.takeException(), isNull, reason: '${size.$1}×${size.$2} 版式');
    }
  });
}
