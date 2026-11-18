import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uni_launcher/controller/launcher_controller.dart';
import 'package:uni_launcher/launcher_app.dart';
import 'package:uni_launcher/model/appearance.dart';
import 'package:uni_launcher/model/card_layout.dart';
import 'package:uni_launcher/theme/launcher_theme.dart';
import 'package:uni_launcher/theme/design_tokens.dart';
import 'package:uni_launcher/widgets/audio_spectrum.dart';
import 'package:uni_launcher/widgets/card_content.dart';
import 'package:uni_launcher/widgets/desktop.dart';
import 'package:uni_launcher/widgets/launcher_dialog.dart';
import 'package:uni_launcher/widgets/lyrics_view.dart';
import 'package:uni_launcher/widgets/media_artwork.dart';
import 'fake_gateway.dart';

void main() {
  /// 铺满档的卡片：网格把它归一成 12×6 再交给卡片自己排。
  Widget host(LauncherController c,
      {Appearance look = const Appearance(mode: 'dark')}) {
    final s = SurfaceStyle.from(look, true);
    return MaterialApp(
        theme: launcherTheme(s),
        home: Scaffold(
            body: SizedBox(
                width: 1600,
                height: 760,
                child: CardContent(
                    card: const LauncherCard(
                        'm-full', 'music', '音乐', 0, 0, 12, 6, 0),
                    controller: c))));
  }

  Future<LauncherController> ready(WidgetTester t, FakeGateway g) async {
    t.view.physicalSize = const Size(1600, 900);
    t.view.devicePixelRatio = 1;
    final c = LauncherController(g);
    await c.initialize();
    await t.pumpWidget(host(c));
    await t.pumpAndSettle();
    return c;
  }

  testWidgets('铺满档：封面 / 三颗标签 / 歌词 / 频谱 / 控制键 / 换音源', (t) async {
    final g = FakeGateway();
    g.state['media'] = {
      ...(g.state['media'] as Map<String, dynamic>),
      'collection': '环线',
      'lyrics': '[00:00]第一句\n[00:04]第二句\n[00:08]第三句',
      'positionMs': 5000,
      'durationMs': 269000,
      'positionKnown': true,
      'canNext': true,
      'canPrevious': true,
      'canToggle': true,
      'canSeek': true,
    };
    final c = await ready(t, g);
    expect(find.byKey(const ValueKey('music-player-title')), findsOneWidget);
    expect(find.byKey(const ValueKey('music-player-subtitle')), findsOneWidget);
    for (final tag in ['VIP', 'SQ', 'Hi-Res']) {
      expect(find.byKey(ValueKey('music-quality-$tag')), findsOneWidget,
          reason: tag);
    }
    // 副标题是「歌手 · 专辑」，专辑不再单占一行。
    expect(find.text('昼夜电台 · 环线'), findsOneWidget);
    expect(find.byKey(const ValueKey('music-player-lyrics')), findsOneWidget);
    // 封面走同一个 MediaArtwork：真会话送来的 artwork 会替换掉占位。
    expect(find.byType(MediaArtwork), findsOneWidget);
    expect(find.byKey(const ValueKey('music-player-spectrum')), findsOneWidget);
    // 稿子左侧的音量滑条换成了频谱；画法跟设置走（不再写死成 bars）。
    expect(t.widget<AudioSpectrum>(find.byType(AudioSpectrum)).style, isNull);
    expect(find.byKey(const ValueKey('media-app-picker')), findsOneWidget);
    expect(find.byKey(const ValueKey('media-seek')), findsOneWidget);

    await t.tap(find.byKey(const ValueKey('music-player-next')));
    await t.pump();
    expect(g.commands.last['action'], 'next');
    await t.tap(find.byKey(const ValueKey('music-player-toggle')));
    await t.pump();
    expect(g.commands.last['action'], 'toggle-play');
    await t.pumpWidget(const SizedBox());
    c.dispose();
    await g.dispose();
  });

  testWidgets('没有可用会话时播放控制与进度条都是禁用的', (t) async {
    final g = FakeGateway();
    g.state['demo'] = false;
    g.state['media'] = {'available': false, 'playing': false};
    final c = await ready(t, g);
    final before = g.commands.length;
    await t.tap(find.byKey(const ValueKey('music-player-next')));
    await t.tap(find.byKey(const ValueKey('music-player-previous')));
    await t.tap(find.byKey(const ValueKey('music-player-toggle')));
    await t.pump();
    expect(g.commands.length, before,
        reason: '禁用态不该发命令：${g.commands.skip(before).toList()}');
    expect(t.widget<Slider>(find.byKey(const ValueKey('media-seek'))).onChanged,
        isNull);
    await t.pumpWidget(const SizedBox());
    c.dispose();
    await g.dispose();
  });

  testWidgets('频谱画法跟随设置；浅色空态刻度单独压深一档', (t) async {
    t.view.physicalSize = const Size(1600, 900);
    t.view.devicePixelRatio = 1;
    final g = FakeGateway();
    final c = LauncherController(g);
    await c.initialize();
    AudioSpectrumPainter painted() => t
        .widget<CustomPaint>(find.byKey(const ValueKey('audio-spectrum-paint')))
        .painter! as AudioSpectrumPainter;

    // 设置里换成「频带轮廓」，铺满档跟着换（以前这里写死成 bars）。
    const dark = Appearance(mode: 'dark', spectrumStyle: 'outline');
    await t.pumpWidget(host(c, look: dark));
    await t.pumpAndSettle();
    expect(t.widget<AudioSpectrum>(find.byType(AudioSpectrum)).style, isNull);
    expect(painted().style, 'outline');
    // 暗夜：空态刻度仍用皮肤自己的 edge。
    expect(painted().edge, SurfaceStyle.from(dark, true).edge);

    // 浅色：edge 是接近白的边线色，空态那一排刻度在白底上看不见，
    // 所以换成正文墨色的低透明度（压深一档）。
    const light = Appearance(mode: 'light', spectrumStyle: 'segments');
    await t.pumpWidget(host(c, look: light));
    await t.pumpAndSettle();
    final s = SurfaceStyle.from(light, true);
    expect(painted().style, 'segments');
    expect(painted().edge.a, closeTo(.44, .01));
    expect(painted().edge.computeLuminance(),
        lessThan(s.edge.computeLuminance() - .2));

    await t.pumpWidget(const SizedBox());
    c.dispose();
    await g.dispose();
  });

  testWidgets('桌面点音乐卡：底栏服务在跑也不弹旧的媒体面板', (t) async {
    t.view.physicalSize = const Size(1920, 1080);
    t.view.devicePixelRatio = 1;
    final g = FakeGateway();
    // 车上的常态：底栏服务在跑、可见、已授权。以前这里会 presentGlobalPanel('media')，
    // 于是弹出另一套 1040 宽的旧弹层（用户 2026-11-13 实车反馈）。
    g.state['globalDock'] = {
      'enabled': true,
      'allowed': true,
      'running': true,
      'visible': true,
    };
    final c = LauncherController(g);
    await c.initialize();
    c.cards = [const LauncherCard('m', 'music', '音乐', 0, 0, 4, 4, 0)];
    await t.pumpWidget(LauncherApp(controller: c));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('music-card-open-panel')));
    await t.pumpAndSettle();
    expect(c.focusedCard.value, 'm');
    expect(g.commands.map((e) => e['action']), isNot(contains('show-dock-panel')));
    // 铺满层在桌面自己这棵树里，不是另一个窗口里的旧弹层。
    expect(find.byKey(const ValueKey('card-focus-m')), findsOneWidget);
    expect(find.byType(LauncherSheet), findsNothing);
    await t.pumpWidget(const SizedBox());
    c.dispose();
    await g.dispose();
  });

  testWidgets('点卡片 → 整页只剩这张卡（头部与底栏仍在）→ 收起回原页', (t) async {
    t.view.physicalSize = const Size(1920, 1080);
    t.view.devicePixelRatio = 1;
    final g = FakeGateway();
    final c = LauncherController(g);
    await c.initialize();
    c.cards = [
      const LauncherCard('m', 'music', '音乐', 0, 0, 4, 4, 0),
      const LauncherCard('t', 'trafficLight', '红绿灯', 0, 8, 4, 2, 0),
    ];
    await t.pumpWidget(LauncherApp(controller: c));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('t')), findsOneWidget,
        reason: '先确认另一张卡在网格里');
    await t.tap(find.byKey(const ValueKey('music-card-open-panel')));
    await t.pumpAndSettle();
    expect(c.focusedCard.value, 'm');
    // 铺满后：页面上只剩这一张卡；另一张仍挂着（内嵌地图那类要保住实例）
    // 但整层透明、不吃触摸。
    expect(find.byKey(const ValueKey('music-player-title')), findsOneWidget);
    expect(find.byKey(const ValueKey('t')).hitTestable(), findsNothing);
    // 稿子 f5 的 inset 就是头部与底栏的高度：这两条必须还在。
    expect(find.byType(Header), findsOneWidget);
    expect(find.byKey(const ValueKey('bottom-dock')), findsOneWidget);
    final focused = t.getRect(find.byKey(const ValueKey('card-focus-m')));
    expect(
        focused.top, greaterThan(t.getRect(find.byType(Header)).bottom - .1));
    expect(
        focused.bottom,
        lessThan(t.getRect(find.byKey(const ValueKey('bottom-dock'))).top + .1));
    // 收起：回到原来的页面，两张卡都在原位。
    await t.tap(find.byKey(const ValueKey('card-focus-close')));
    await t.pumpAndSettle();
    expect(c.focusedCard.value, isNull);
    expect(find.byKey(const ValueKey('music-player-title')), findsNothing);
    expect(find.byKey(const ValueKey('t')), findsOneWidget);
    await t.pumpWidget(const SizedBox());
    c.dispose();
    await g.dispose();
  });

  testWidgets('铺满档歌词只占 5 行，中间高亮行明显大于普通行', (t) async {
    final g = FakeGateway();
    const texts = ['第零句', '第一句', '第二句', '第三句', '第四句', '第五句',
      '第六句', '第七句', '第八句'];
    g.state['media'] = {
      ...(g.state['media'] as Map<String, dynamic>),
      'lyrics': texts.join('\n'),
      'positionMs': 9000,
      'durationMs': 203000,
      'positionKnown': true,
    };
    final c = await ready(t, g);
    final view = t.widget<LyricsView>(
        find.byKey(const ValueKey('music-player-lyrics')));
    expect(view.visibleLines, 5, reason: '用户 2026-11-15 要求从 7 行收到 5 行');
    // 两档一起抬：高亮 34 / 普通 21，比例压在 1.6 倍上下。只放高亮会变成 2 倍，
    // 看着像标题不像歌词；普通行不跟着大，五行又显得单薄。
    expect(view.fontSize, Design.px(21));
    expect(view.activeFontSize, Design.px(34));
    expect(view.activeFontSize! / view.fontSize!, inInclusiveRange(1.45, 1.75));
    // 高亮行的行高要容得下它自己的字号（Text 高度约 1.16 倍），否则会被裁。
    expect(view.activeLineHeight!, greaterThan(view.activeFontSize! * 1.16));
    // 真渲染出来的行数就是 5（文档有 9 句，窗口只开 5 格）。
    final rows = find.byWidgetPredicate((w) =>
        w.key is ValueKey<String> &&
        (w.key as ValueKey<String>).value.startsWith('lyric-line-'));
    expect(rows, findsNWidgets(5));
    await t.pumpWidget(const SizedBox());
    c.dispose();
    await g.dispose();
  });

  testWidgets('两张音乐卡：点第 2 页那张，铺满的也是它，收起仍停在第 2 页', (t) async {
    t.view.physicalSize = const Size(1920, 1080);
    t.view.devicePixelRatio = 1;
    final g = FakeGateway();
    final c = LauncherController(g);
    await c.initialize();
    c.cards = [
      const LauncherCard('m1', 'music', '音乐', 0, 0, 4, 4, 0),
      const LauncherCard('m2', 'music', '音乐', 1, 0, 4, 4, 1),
    ];
    await t.pumpWidget(LauncherApp(controller: c));
    await t.pumpAndSettle();
    await c.switchPage(1);
    await t.pumpAndSettle();
    expect(c.page, 1);

    // 用户 2026-11-15 反馈的「每次返回都回首页」：以前这里固定取 cards 里第一张
    // 音乐卡（m1，在第 1 页），于是先把桌面翻回第一屏再铺满。
    await t.tap(find.byKey(const ValueKey('music-card-open-panel')).last);
    await t.pumpAndSettle();
    expect(c.focusedCard.value, 'm2', reason: '铺满的必须是点的那一张');
    expect(c.page, 1, reason: '不该把桌面翻到别的页');

    await t.tap(find.byKey(const ValueKey('card-focus-close')));
    await t.pumpAndSettle();
    expect(c.focusedCard.value, isNull);
    expect(c.page, 1, reason: '收起后停在音乐卡所在的这一页');
    await t.pumpWidget(const SizedBox());
    c.dispose();
    await g.dispose();
  });

  testWidgets('铺满时按返回键（back）收起，不用非点右上角箭头', (t) async {
    t.view.physicalSize = const Size(1920, 1080);
    t.view.devicePixelRatio = 1;
    final g = FakeGateway();
    final c = LauncherController(g);
    await c.initialize();
    c.cards = [const LauncherCard('m', 'music', '音乐', 0, 0, 4, 4, 0)];
    await t.pumpWidget(LauncherApp(controller: c));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('music-card-open-panel')));
    await t.pumpAndSettle();
    expect(c.focusedCard.value, 'm');

    c.back();
    await t.pumpAndSettle();
    expect(c.focusedCard.value, isNull);
    expect(find.byKey(const ValueKey('music-player-title')), findsNothing);
    await t.pumpWidget(const SizedBox());
    c.dispose();
    await g.dispose();
  });

  testWidgets('铺满时点空白收起，点功能键不收起', (t) async {
    t.view.physicalSize = const Size(1920, 1080);
    t.view.devicePixelRatio = 1;
    final g = FakeGateway();
    final c = LauncherController(g);
    await c.initialize();
    c.cards = [const LauncherCard('m', 'music', '音乐', 0, 0, 4, 4, 0)];
    await t.pumpWidget(LauncherApp(controller: c));
    await t.pumpAndSettle();

    // 铺满档内容居中，卡片左右两侧是空白。
    await t.tap(find.byKey(const ValueKey('music-card-open-panel')));
    await t.pumpAndSettle();
    final rect = t.getRect(find.byKey(const ValueKey('card-focus-m')));
    await t.tapAt(Offset(rect.left + 30, rect.center.dy));
    await t.pumpAndSettle();
    expect(c.focusedCard.value, isNull, reason: '点空白要收起');

    // 网格左右各 32 画布的边距在铺满层之外（`card-focus` 只覆盖网格区），
    // 那条缝也算「空白」：用户 2026-11-15 说「点空白没反应」，补的就是它。
    await t.tap(find.byKey(const ValueKey('music-card-open-panel')));
    await t.pumpAndSettle();
    final grid = t.getRect(find.byKey(const ValueKey('card-grid')));
    final focused = t.getRect(find.byKey(const ValueKey('card-focus-m')));
    expect(focused.left, greaterThan(grid.left + 1), reason: '先确认这条边距存在');
    await t
        .tapAt(Offset((grid.left + focused.left) / 2, focused.center.dy));
    await t.pumpAndSettle();
    expect(c.focusedCard.value, isNull, reason: '卡片外侧的边距也要能收起');

    // 再铺满一次，点播放/暂停键：内层手势先赢，铺满层不该跟着收。
    await t.tap(find.byKey(const ValueKey('music-card-open-panel')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('music-player-toggle')));
    await t.pumpAndSettle();
    expect(c.focusedCard.value, 'm', reason: '点功能键不收起');
    await t.pumpWidget(const SizedBox());
    c.dispose();
    await g.dispose();
  });
}
