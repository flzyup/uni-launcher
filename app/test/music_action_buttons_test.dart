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
      {int w = 4, int h = 4, bool settle = true}) async {
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
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      // 歌名横滚是一条无限循环的动画，pumpAndSettle 会一直等下去。
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
    }
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

  // 小卡（4×1 / 4×2）的收藏键落在播放键左边那块留白里：曲目信息那一列本来就
  // 窄，键挂在歌名后面会把歌手挤成省略号；靠右反而正好填掉一颗圆键的空白。
  testWidgets('4×1 两颗键都给，贴在播放键左侧', (tester) async {
    await pumpMusicCard(tester, {
      'actionCaps': {'favorite': true, 'playMode': true},
      'favorited': true,
      'playMode': 'REPEAT_ONE',
    }, w: 4, h: 1);
    final heart = find.byKey(const ValueKey('music-favorite-button'));
    final mode = find.byKey(const ValueKey('music-play-mode-button'));
    final play = find.byKey(const ValueKey('music-card-compact-play'));
    // 跟 4×2 保持同一套键：两档只差「有没有卡片头」。
    expect(heart, findsOneWidget);
    expect(mode, findsOneWidget);
    expect(tester.getCenter(heart).dx, lessThan(tester.getCenter(play).dx));
    expect(tester.getCenter(mode).dx, lessThan(tester.getCenter(play).dx));
    // 落在播放键的中线上，看着是一组传输键
    expect((tester.getCenter(heart).dy - tester.getCenter(play).dy).abs(),
        lessThan(2.0));
    // 曲目名与歌手都还在，没被键挤掉
    expect(find.byKey(const ValueKey('music-card-title')), findsOneWidget);
    expect(find.byKey(const ValueKey('music-card-artist')), findsOneWidget);
  });

  testWidgets('4×2 两颗键都在播放键左侧，歌名行不再重复', (tester) async {
    await pumpMusicCard(tester, {
      'actionCaps': {'favorite': true, 'playMode': true},
      'favorited': true,
      'playMode': 'REPEAT_ONE',
    }, w: 4, h: 2);
    final heart = find.byKey(const ValueKey('music-favorite-button'));
    final mode = find.byKey(const ValueKey('music-play-mode-button'));
    final play = find.byKey(const ValueKey('music-card-compact-play'));
    // 各一颗，不能歌名行一颗、播放键边又一颗
    expect(heart, findsOneWidget);
    expect(mode, findsOneWidget);
    expect(
        find.descendant(
            of: find.byKey(const ValueKey('music-card-title-row')),
            matching: heart),
        findsNothing);
    expect(tester.getCenter(heart).dx, lessThan(tester.getCenter(play).dx));
    expect(tester.getCenter(mode).dx, lessThan(tester.getCenter(play).dx));
    expect((tester.getCenter(heart).dy - tester.getCenter(play).dy).abs(),
        lessThan(2.0));
  });

  testWidgets('3 格宽的一格档只画收藏，不画播放模式', (tester) async {
    // 3 格宽是 CardSpec.minW 允许的最小档，曲目列被封面和播放键吃到只剩几十
    // 画布，再挂一颗播放模式歌名就没了。两行档（3×2）走 4×2 那套版式，不在此列。
    await pumpMusicCard(tester, {
      'actionCaps': {'favorite': true, 'playMode': true},
      'favorited': true,
      'playMode': 'REPEAT_ONE',
    }, w: 3, h: 1);
    expect(find.byKey(const ValueKey('music-favorite-button')), findsOneWidget);
    expect(find.byKey(const ValueKey('music-play-mode-button')), findsNothing);
  });

  testWidgets('4×1 长歌名改成横向滚动，短歌名不滚', (tester) async {
    // MarqueeText 只在超出容器宽度时才起滚动。一格档文字宽度是先算出来的，
    // 键加进来之后余量变窄——长歌名靠横滚兜住，不靠缩字。
    await pumpMusicCard(tester, {
      'actionCaps': {'favorite': true, 'playMode': true},
      'favorited': true,
      'title': '沿着环线一直开到天亮再回家',
    }, w: 4, h: 1, settle: false);
    expect(find.byKey(const ValueKey('marquee-paint-music-card-title')),
        findsOneWidget,
        reason: '长歌名要横滚');

    await pumpMusicCard(tester, {'title': '午夜立交'}, w: 4, h: 1);
    expect(find.byKey(const ValueKey('marquee-paint-music-card-title')),
        findsNothing,
        reason: '短歌名不滚');
  });

  testWidgets('小卡的收藏键仍按音源能力决定画不画', (tester) async {
    await pumpMusicCard(tester, {
      'actionCaps': {'favorite': false, 'playMode': false},
    }, w: 4, h: 1);
    expect(find.byKey(const ValueKey('music-favorite-button')), findsNothing);
    // 键不画，播放键还在
    expect(find.byKey(const ValueKey('music-card-compact-play')), findsOneWidget);
  });
}
