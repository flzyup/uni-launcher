import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uni_launcher/controller/launcher_controller.dart';
import 'package:uni_launcher/launcher_app.dart';
import 'package:uni_launcher/model/appearance.dart';
import 'package:uni_launcher/screens/global_dock_app.dart';
import 'package:uni_launcher/screens/global_panel_app.dart';
import 'package:uni_launcher/theme/launcher_theme.dart';
import 'package:uni_launcher/theme/design_tokens.dart';
import 'package:uni_launcher/theme/technical_frame.dart';
import 'package:uni_launcher/widgets/bottom_dock.dart';
import 'package:uni_launcher/widgets/launcher_dialog.dart';
import 'package:uni_launcher/widgets/glass_surface.dart';
import 'package:uni_launcher/widgets/audio_spectrum.dart';
import 'package:uni_launcher/widgets/card_content.dart';
import 'package:uni_launcher/widgets/dock_nav_icons.dart';
import 'package:uni_launcher/widgets/media_artwork.dart';
import 'package:uni_launcher/widgets/integration_settings.dart';
import 'package:uni_launcher/model/card_layout.dart';
import 'package:uni_launcher/widgets/lyrics_view.dart';
import 'fake_gateway.dart';
import 'package:uni_launcher/widgets/recent_tasks_panel.dart';
import 'package:uni_launcher/widgets/desktop.dart';
import 'package:uni_launcher/widgets/editable_card.dart';

void main() {
  Future<(LauncherController, FakeGateway)> setup(WidgetTester t,
      {String? host, bool global = false}) async {
    t.view.physicalSize = const Size(1920, 1080);
    t.view.devicePixelRatio = 1;
    final g = FakeGateway();
    if (host != null) g.state['hostMode'] = host;
    g.state['globalDock'] = {
      'enabled': global,
      'running': global,
      'allowed': true,
      'panel': '',
      'panelRevision': 0
    };
    g.state['media'] = {
      'title': '曲名',
      'artist': '歌手',
      'source': 'test.player',
      'lyrics': '[00:00]上一句\n[00:03]当前句\n[00:06]下一句',
      'positionMs': 4000,
      'positionKnown': true,
      'playing': false
    };
    g.state['apps'] = [
      <String, dynamic>{
        'id': 'test.player/.MainActivity',
        'package': 'test.player',
        'label': '测试播放器'
      },
      {
        'id': 'custom.map/.MainActivity',
        'package': 'custom.map',
        'label': '自选导航'
      }
    ];
    final c = LauncherController(g);
    await c.initialize();
    addTearDown(() async {
      await t.pumpWidget(const SizedBox.shrink());
      if (host != 'global-panel') c.dispose();
      await g.dispose();
      t.view.resetPhysicalSize();
      t.view.resetDevicePixelRatio();
    });
    return (c, g);
  }

  testWidgets('header transfer icon follows service and opens global popup',
      (t) async {
    final (c, g) = await setup(t, global: true);
    await t.pumpWidget(MaterialApp(
      theme: launcherTheme(SurfaceStyle.from(const Appearance(), true)),
      home: Scaffold(body: Header(controller: c)),
    ));
    expect(find.byKey(const ValueKey('status-file-transfer')), findsNothing);
    g.state['transfer'] = {'running': true};
    g.stream.add(Map.of(g.state));
    await t.pump();
    expect(find.byKey(const ValueKey('status-file-transfer')), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('status-file-transfer')));
    await t.pump();
    expect(g.commands.last['action'], 'show-dock-panel');
    expect(g.commands.last['value'], 'transfer');
    g.state['transfer'] = {'running': false};
    g.stream.add(Map.of(g.state));
    await t.pump();
    expect(find.byKey(const ValueKey('status-file-transfer')), findsNothing);
  });

  testWidgets('custom recents renders task cards and native task actions',
      (t) async {
    final (c, g) = await setup(t, host: 'global-panel', global: true);
    g.state['systemStatus'] = {
      'memory': {'usedBytes': 2147483648, 'totalBytes': 4294967296}
    };
    g.state['globalDock'] = {
      'enabled': true,
      'running': true,
      'allowed': true,
      'panel': 'recents',
      'recentsReady': true,
      'recentsClearSupported': true
    };
    g.state['recentTasks'] = [
      {'taskId': 41, 'package': 'test.player', 'label': '测试播放器'},
      {'taskId': 42, 'package': 'custom.map', 'label': '自选导航'}
    ];
    g.stream.add(Map.of(g.state));
    await t.pump();
    await t.pumpWidget(MaterialApp(
        theme: launcherTheme(SurfaceStyle.from(const Appearance(), true)),
        home: Scaffold(
            body: SizedBox(
                width: 1920,
                height: 984,
                child: RecentTasksPanel(controller: c)))));
    await t.pumpAndSettle();
    expect(find.text('已用 2.00 GB / 4.00 GB'), findsOneWidget);
    expect(find.text('测试播放器'), findsOneWidget);
    expect(find.text('自选导航'), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('recent-task-41')));
    expect(g.commands.last['action'], 'open-recent-task');
    expect(g.commands.last['value'], '41');
    await t.drag(find.byKey(const ValueKey('recent-task-dismiss-41')),
        const Offset(0, -500));
    await t.pumpAndSettle();
    expect(g.commands.last['action'], 'remove-recent-task');
    expect(g.commands.last['value'], '41');
    await t.tap(find.byKey(const ValueKey('system-recents-clear')));
    expect(g.commands.last['action'], 'clear-system-recents');
    expect(t.takeException(), isNull);
    c.dispose();
  });
  testWidgets('all-app pressed material exactly matches the icon frame',
      (t) async {
    final (c, _) = await setup(t);
    c.beginEdit();
    await t.pumpWidget(MaterialApp(
        theme: launcherTheme(SurfaceStyle.from(const Appearance(), true)),
        home: Scaffold(
            body: SizedBox(
                width: 1560, height: 760, child: AppPanel(controller: c)))));
    await t.pumpAndSettle();
    final frame = find.byKey(const ValueKey('app-icon-frame-test.player'));
    final ink = find.byKey(const ValueKey('app-icon-ink-test.player'));
    expect(frame, findsOneWidget);
    expect(ink, findsOneWidget);
    expect(t.widget<Material>(frame).shape, isA<TechnicalFrameBorder>());
    expect(t.getSize(frame).width, t.getSize(frame).height);
    expect(t.getSize(frame).width, greaterThan(80));
    expect(t.getSize(ink), t.getSize(frame));
    expect(t.getTopLeft(ink), t.getTopLeft(frame));
    expect(t.getBottomRight(ink), t.getBottomRight(frame));
    expect(t.getTopLeft(find.text('测试播放器')).dy,
        greaterThan(t.getBottomRight(ink).dy));
    expect(t.takeException(), isNull);
  });
  testWidgets('all-app grid ignores unrelated telemetry updates', (t) async {
    final (c, _) = await setup(t);
    await t.pumpWidget(MaterialApp(
        theme: launcherTheme(SurfaceStyle.from(const Appearance(), true)),
        home: Scaffold(body: AppPanel(controller: c))));
    await t.pumpAndSettle();
    final gridBefore = t.widget<GridView>(find.byType(GridView));
    c.native.value = {
      ...c.native.value,
      'vehicle': {'speed': 42}
    };
    await t.pump();
    expect(t.widget<GridView>(find.byType(GridView)), same(gridBefore));
    c.native.value = {
      ...c.native.value,
      'apps': [
        ...c.native.value['apps'] as List,
        {'id': 'new/.Main', 'package': 'new', 'label': '新应用'}
      ]
    };
    await t.pump();
    expect(find.text('新应用'), findsOneWidget);
    expect(t.takeException(), isNull);
  });
  testWidgets('app rename updates the launcher label and persisted design',
      (t) async {
    final (c, g) = await setup(t);
    await t.pumpWidget(MaterialApp(
        theme: launcherTheme(SurfaceStyle.from(const Appearance(), true)),
        home: Scaffold(body: AppPanel(controller: c))));
    await t.pumpAndSettle();
    await t.longPress(find.text('测试播放器'));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('app-menu-rename')));
    await t.pumpAndSettle();
    await t.enterText(
        find.byKey(const ValueKey('app-name-input')), ' 我的音乐播放器 ');
    await t.tap(find.byKey(const ValueKey('app-name-save')));
    await t.pumpAndSettle();
    expect(
        c.appName(Map<String, dynamic>.from((g.state['apps'] as List).first)),
        '我的音乐播放器');
    expect(find.text('我的音乐播放器'), findsOneWidget);
    expect(g.saved, contains('"test.player":"我的音乐播放器"'));
    expect(t.takeException(), isNull);
  });
  testWidgets(
      'dock button order, recents command and centered current lyric with two-line limit',
      (t) async {
    final (c, g) = await setup(t);
    await t.pumpWidget(MaterialApp(
        theme: launcherTheme(SurfaceStyle.from(const Appearance(), true)),
        home: Scaffold(
            body: Align(
                alignment: Alignment.bottomCenter,
                child: BottomDock(controller: c)))));
    await t.pumpAndSettle();
    final order = [
      'system-back',
      'home',
      'all-apps',
      'recents',
      'camera',
      'climate',
      'previous',
      'play-pause',
      'next',
      'music-info',
      'uni-menu'
    ];
    for (var i = 1; i < order.length; i++) {
      expect(t.getCenter(find.byKey(ValueKey(order[i]))).dx,
          greaterThan(t.getCenter(find.byKey(ValueKey(order[i - 1]))).dx));
    }
    await t.tap(find.byKey(const ValueKey('recents')));
    expect(g.commands.last['action'], 'show-recents');
    // 设计稿复刻图标（circle + 360 字样）替代原 UniIcon 资产。
    expect(
        find.descendant(
            of: find.byKey(const ValueKey('camera')),
            matching: find.byType(NavCamera360Icon)),
        findsOneWidget);
    final title = t.getCenter(find.byKey(const ValueKey('dock-track-title')));
    expect(find.byKey(const ValueKey('dock-lyrics')).hitTestable(),
        findsOneWidget);
    // 底栏元数据槽也显示当前一句歌词，歌词页内的断言收窄到该子树。
    expect(
        find.descendant(
            of: find.byKey(const ValueKey('dock-lyrics')),
            matching: find.text('当前句')),
        findsOneWidget);
    final lyrics = t.widget<LyricsView>(find.byType(LyricsView));
    expect(lyrics.visibleLines, 1);
    expect(lyrics.currentLineMaxLines, 2);
    final lyric = t.getCenter(find.byKey(const ValueKey('dock-lyrics')));
    expect(lyric.dx, greaterThan(title.dx));
    expect(lyric.dy, closeTo(title.dy, .1));
    await t.drag(find.byKey(const ValueKey('dock-music-visual-pages')),
        const Offset(-400, 0));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('audio-spectrum-paint')).hitTestable(),
        findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('UNI dock menu opens vehicle details and desktop settings',
      (t) async {
    final (c, g) = await setup(t);
    await t.pumpWidget(MaterialApp(
        theme: launcherTheme(SurfaceStyle.from(const Appearance(), true)),
        home: Scaffold(
            body: Align(
                alignment: Alignment.bottomCenter,
                child: BottomDock(controller: c)))));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('uni-menu')));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('uni-popup-panel')), findsOneWidget);
    // 设计稿 sim 的四行是「标题 + 说明」两行；实车菜单把说明整行去掉了，标题
    // 从 17.6 抬到 20（行高仍是稿子的 58.5，不随 dock 档位缩放）。文案和副标题
    // 以前全跑偏过，所以两边都钉住。
    for (final title in ['车辆信息', '传文件 / 通网盘', '垃圾清理', 'UNI 桌面设置']) {
      expect(find.text(title), findsOneWidget, reason: '$title 标题文案');
    }
    expect(find.text('只读 · 胎压 / 座舱 / 能量'), findsNothing,
        reason: '说明行已去掉，不该再渲染副标题');
    expect(find.text('扫码上传 · 夸克网盘'), findsNothing, reason: '说明行已去掉');
    expect(find.text('缓存 · 日志 · 残留'), findsNothing, reason: '说明行已去掉');
    expect(find.text('外观 · 应用 · 动画'), findsNothing, reason: '说明行已去掉');
    expect(
        t.getRect(find.byKey(const ValueKey('uni-menu-vehicle'))).height,
        closeTo(58.5, .5),
        reason: '行高应为设计稿的 58.5 画布，不随 dock 档位缩放');
    await t.tap(find.byKey(const ValueKey('uni-menu-vehicle')));
    await t.pumpAndSettle();
    expect(find.byTooltip('关闭车辆信息'), findsOneWidget);
    await t.tap(find.byTooltip('关闭车辆信息'));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('uni-menu')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('uni-menu-settings')));
    await t.pumpAndSettle();
    expect(c.settings, isTrue);
    expect(g.commands, isEmpty);
    expect(t.takeException(), isNull);
  });

  testWidgets('UNI menu cleaner jumps into the settings cleaner tab',
      (t) async {
    final (c, g) = await setup(t);
    await t.pumpWidget(MaterialApp(
        theme: launcherTheme(SurfaceStyle.from(const Appearance(), true)),
        home: Scaffold(
            body: Align(
                alignment: Alignment.bottomCenter,
                child: BottomDock(controller: c)))));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('uni-menu')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('uni-menu-cleaner')));
    await t.pumpAndSettle();
    // 不再弹独立的清理窗口，而是打开设置并落在「垃圾清理」那一栏。
    expect(c.settings, isTrue);
    expect(c.settingsTab, 'cleaner');
    expect(find.text('扫全机缓存、临时文件与残留；照片、导航离线地图和行车记录不动'),
        findsNothing);
    expect(g.commands, isEmpty);
    expect(t.takeException(), isNull);
  });

  testWidgets('UNI menu opens transfer panel with live address and controls',
      (t) async {
    final (c, g) = await setup(t);
    g.state['transfer'] = {
      'running': true,
      'url': 'http://192.168.1.1:8080/',
      'files': []
    };
    g.stream.add(Map.of(g.state));
    await t.pumpWidget(MaterialApp(
        theme: launcherTheme(SurfaceStyle.from(const Appearance(), true)),
        home: Scaffold(
            body: Align(
                alignment: Alignment.bottomCenter,
                child: BottomDock(controller: c)))));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('uni-menu')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('uni-menu-transfer')));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('transfer-popup')), findsOneWidget);
    expect(find.text('http://192.168.1.1:8080/'), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('transfer-switch')));
    await t.pumpAndSettle();
    expect(g.commands.last['action'], 'transfer-stop');
    expect(t.takeException(), isNull);
  });

  testWidgets('global panel opens transfer and starts service', (t) async {
    final (c, g) = await setup(t, host: 'global-panel', global: true);
    await t.pumpWidget(GlobalPanelApp(controller: c));
    await t.pumpAndSettle();
    g.state['globalDock'] = {
      'enabled': true,
      'running': true,
      'panel': 'uni-menu',
      'panelRevision': 1
    };
    g.stream.add(Map.of(g.state));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('uni-menu-transfer')));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('transfer-popup')), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('transfer-switch')));
    await t.pumpAndSettle();
    expect(
        g.commands.any((entry) => entry['action'] == 'transfer-start'), isTrue);
    expect(t.takeException(), isNull);
  });

  testWidgets('direct global transfer panel signals readiness and closes',
      (t) async {
    final (c, g) = await setup(t, host: 'global-panel', global: true);
    await t.pumpWidget(GlobalPanelApp(controller: c));
    await t.pumpAndSettle();
    g.state['globalDock'] = {
      'enabled': true,
      'running': true,
      'panel': 'transfer',
      'panelRevision': 3
    };
    g.stream.add(Map.of(g.state));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('transfer-popup')), findsOneWidget);
    expect(
        g.commands.any((entry) =>
            entry['action'] == 'panel-ready' && entry['value'] == '3'),
        isTrue);
    await t.tap(find.byTooltip('关闭传文件'));
    await t.pumpAndSettle();
    expect(g.commands.any((entry) => entry['action'] == 'dismiss-dock-panel'),
        isTrue);
    expect(t.takeException(), isNull);
  });

  testWidgets('global panel engine presents the UNI menu and settings action',
      (t) async {
    final (c, g) = await setup(t, host: 'global-panel', global: true);
    await t.pumpWidget(GlobalPanelApp(controller: c));
    await t.pumpAndSettle();
    g.state['globalDock'] = {
      'enabled': true,
      'running': true,
      'panel': 'uni-menu',
      'panelRevision': 1
    };
    g.stream.add(Map.of(g.state));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('uni-popup-panel')), findsOneWidget);
    expect(find.byKey(const ValueKey('uni-menu-vehicle')), findsOneWidget);
    expect(find.byKey(const ValueKey('uni-menu-settings')), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('uni-menu-settings')));
    await t.pumpAndSettle();
    expect(
        g.commands.any((action) => action['action'] == 'show-desktop-settings'),
        isTrue);
    expect(g.commands.last['action'], 'dismiss-dock-panel');
    await t.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
      'global Home selection follows desktop state and clears for panels',
      (t) async {
    final (c, g) = await setup(t, host: 'global-dock', global: true);
    await t.pumpWidget(GlobalDockApp(controller: c));
    await t.pumpAndSettle();
    IconAction home() =>
        t.widget<IconAction>(find.byKey(const ValueKey('home')));
    expect(home().active, false);
    g.state['desktopSelected'] = true;
    g.stream.add(Map.of(g.state));
    await t.pumpAndSettle();
    expect(home().active, true);
    (g.state['globalDock'] as Map)['expanded'] = true;
    g.stream.add(Map.of(g.state));
    await t.pumpAndSettle();
    expect(home().active, false);
    (g.state['globalDock'] as Map)['expanded'] = false;
    g.state['desktopSelected'] = false;
    g.stream.add(Map.of(g.state));
    await t.pumpAndSettle();
    expect(home().active, false);
  });

  testWidgets('music card layouts put lyrics and spectrum by card size',
      (t) async {
    final (c, _) = await setup(t);
    for (final size in [
      (3, 2, 450.0, 240.0),
      (4, 2, 600.0, 240.0),
      (4, 3, 600.0, 390.0),
      (4, 4, 600.0, 530.0),
      (4, 5, 600.0, 690.0),
      (4, 6, 600.0, 820.0),
      (8, 6, 1200.0, 800.0)
    ]) {
      final card = LauncherCard(
          'test-music', 'music', '正在播放', 0, 0, size.$1, size.$2, 0);
      await t.pumpWidget(MaterialApp(
          theme: launcherTheme(SurfaceStyle.from(const Appearance(), true)),
          home: Scaffold(
              body: SizedBox(
                  width: size.$3,
                  height: size.$4,
                  child: CardContent(card: card, controller: c)))));
      await t.pumpAndSettle();
      final draft = size.$1 == 4 && size.$2 >= 4;
      // 「正在播放」是卡片头上来源标识的副标题；稿子尺寸没有卡片头。
      expect(find.text('正在播放'), draft ? findsNothing : findsOneWidget);
      if (size.$2 <= 3) {
        // 矮卡只放封面 + 曲名，没有歌词位；来源标识仍在卡片头上。
        expect(find.byType(LyricsView), findsNothing);
        if (size.$2 == 2) expect(find.byType(AudioSpectrum), findsNothing);
        expect(find.text('测试播放器'), findsOneWidget);
        await t.tap(find.byKey(const ValueKey('media-source-entry')));
        expect(c.gateway, isA<FakeGateway>());
        expect((c.gateway as FakeGateway).commands.last['action'],
            'launch-player');
      } else {
        expect(find.byKey(const ValueKey('music-card-lyrics')), findsOneWidget);
        expect(find.byKey(const ValueKey('music-card-lyrics-fade')),
            findsOneWidget);
        expect(find.byType(AudioSpectrum), findsOneWidget);
        final lyricView = t.widget<LyricsView>(find.byType(LyricsView));
        if (draft) {
          // 稿子 f1：卡片头整个省掉（来源与换音源都在播放器弹层里），歌词是
          // 迷你窗——当前行放大 + 左对齐 + 不滚动。
          expect(find.byKey(const ValueKey('media-source-entry')), findsNothing);
          expect(lyricView.mini, isTrue);
          expect(lyricView.textAlign, TextAlign.start);
          expect(lyricView.visibleLines, inInclusiveRange(3, 7));
          expect(lyricView.activeFontSize,
              greaterThan(lyricView.fontSize!));
          // 三颗音质标签是稿子的静态装饰（原车没有音质字段），位置在标题下面。
          for (final tag in ['VIP', 'SQ', 'Hi-Res']) {
            expect(find.byKey(ValueKey('music-quality-$tag')), findsOneWidget,
                reason: '$size $tag');
          }
          expect(
              t.getRect(find.byKey(const ValueKey('music-quality-VIP'))).top,
              greaterThan(
                  t.getRect(find.byKey(const ValueKey('music-card-artist')))
                      .top));
        } else {
          expect(lyricView.mini, isFalse);
          expect(lyricView.lineHeight, 44);
          expect(lyricView.fontSize, 26);
          expect(lyricView.textAlign, TextAlign.center);
        }
        final lyrics =
            t.getCenter(find.byKey(const ValueKey('music-card-lyrics')));
        final cover = t.getRect(find.byType(MediaArtwork).first);
        // 稿子版式：封面在上、歌词在下；8×6 宽卡仍是左右两列。
        if (draft) {
          expect(cover.bottom, lessThan(lyrics.dy));
        } else {
          expect(lyrics.dx, greaterThan(cover.right));
        }
        expect(
            t.getCenter(find.byType(AudioSpectrum)).dy, greaterThan(lyrics.dy));
      }
      expect(t.takeException(), isNull);
    }
  });

  testWidgets('4x4 music title sits beside the cover, lyrics below it',
      (t) async {
    final (c, g) = await setup(t);
    g.state['media'] = {
      ...(g.state['media'] as Map<String, dynamic>),
      'title': '这是一首特别长的歌曲名称用来验证右侧区域跑马灯布局',
      'collection': '这是一张特别长的专辑名称用来验证右侧区域跑马灯布局'
    };
    g.stream.add(Map.of(g.state));
    await t.pumpWidget(MaterialApp(
        theme: launcherTheme(SurfaceStyle.from(const Appearance(), true)),
        home: Scaffold(
            body: SizedBox(
                width: 600,
                height: 530,
                child: CardContent(
                    card: const LauncherCard(
                        'music-left', 'music', '正在播放', 0, 0, 4, 4, 0),
                    controller: c)))));
    await t.pump(const Duration(milliseconds: 100));

    final title = t.getRect(find.byKey(const ValueKey('music-card-title')));
    final artist = t.getRect(find.byKey(const ValueKey('music-card-artist')));
    final lyrics = t.getRect(find.byKey(const ValueKey('music-card-lyrics')));
    final cover = t.getRect(find.byType(MediaArtwork).first);
    // 稿子 `.mu-info`：标题与副标题在封面右侧、顶端对齐；专辑进了副标题那行。
    expect(title.left, greaterThan(cover.right));
    expect(title.right, lessThanOrEqualTo(lyrics.right + .1));
    expect(title.top, lessThan(cover.bottom));
    expect(artist.left, closeTo(title.left, .1));
    expect(artist.top, greaterThan(title.bottom));
    expect(lyrics.top, greaterThan(cover.bottom));
    expect(find.byKey(const ValueKey('music-card-album')), findsNothing);
    for (final key in ['music-card-title', 'music-card-artist']) {
      expect(
          find.descendant(
              of: find.byKey(ValueKey(key)),
              matching: find.byType(ShaderMask)),
          findsOneWidget,
          reason: key);
    }
    expect(t.takeException(), isNull);
  });

  testWidgets('two-row music card exposes a play/pause button on the right',
      (t) async {
    final (c, g) = await setup(t);
    g.state['demo'] = false;
    g.state['media'] = {
      ...(g.state['media'] as Map<String, dynamic>),
      'available': true,
      'canToggle': true,
      'playing': true
    };
    g.stream.add(Map.of(g.state));
    Future<void> pumpCard(LauncherCard card, double height) =>
        t.pumpWidget(MaterialApp(
            theme: launcherTheme(SurfaceStyle.from(const Appearance(), true)),
            home: Scaffold(
                body: SizedBox(
                    width: 600,
                    height: height,
                    child: CardContent(card: card, controller: c)))));

    final compact = LauncherCard('music', 'music', '音乐', 0, 0, 4, 2, 0);
    await pumpCard(compact, 240);
    await t.pump(const Duration(milliseconds: 100));

    const key = ValueKey('music-card-compact-play');
    expect(find.byKey(key), findsOneWidget);
    // 正在播放 → 暂停图标；按钮排在封面右边、卡片靠右那一侧。
    expect(find.descendant(of: find.byKey(key), matching: find.byIcon(Icons.pause)),
        findsOneWidget);
    final cover = t.getRect(find.byType(MediaArtwork).first);
    final button = t.getRect(find.byKey(key));
    expect(button.left, greaterThan(cover.right));
    expect(button.center.dx, greaterThan(300));

    await t.tap(find.byKey(key));
    await t.pump();
    expect(g.commands.last['action'], 'toggle-play');

    // 卡片变高走别的版式，这颗键不该再出现。
    await pumpCard(LauncherCard('music', 'music', '音乐', 0, 0, 4, 4, 0), 530);
    await t.pump(const Duration(milliseconds: 100));
    expect(find.byKey(key), findsNothing);
    expect(t.takeException(), isNull);
  });

  // 一格高（4×1）是 2026-11-15 新放开的档：卡高 ~100 px，卡头和 86 的封面
  // 都放不下，所以这一档只留「封面 + 曲目 + 播放键」一行。
  testWidgets('one-row music card drops the source header and stays in bounds',
      (t) async {
    final (c, g) = await setup(t);
    Future<void> pumpCard(int h, double height) => t.pumpWidget(MaterialApp(
        theme: launcherTheme(SurfaceStyle.from(const Appearance(), true)),
        home: Scaffold(
            body: SizedBox(
                width: 608,
                height: height,
                child: CardContent(
                    card: LauncherCard('music', 'music', '音乐', 0, 0, 4, h, 0),
                    controller: c)))));

    await pumpCard(1, 100);
    await t.pump(const Duration(milliseconds: 100));
    expect(t.takeException(), isNull);
    // 卡头是来源徽标（显示 '测试播放器'）：一格档整行不画。
    expect(find.text('测试播放器'), findsNothing);
    expect(find.byKey(const ValueKey('music-card-title')), findsOneWidget);
    expect(find.byKey(const ValueKey('music-card-artist')), findsOneWidget);
    final key = const ValueKey('music-card-compact-play');
    expect(find.byKey(key), findsOneWidget);

    final cover = t.getRect(find.byType(MediaArtwork).first);
    final button = t.getRect(find.byKey(key));
    // 封面按卡高算（吃掉 ~九成高度），按钮排在它右边，两者都不出卡。
    expect(cover.height, greaterThan(80));
    expect(cover.bottom, lessThanOrEqualTo(100));
    expect(button.left, greaterThan(cover.right));
    expect(button.top, greaterThanOrEqualTo(0));
    expect(button.bottom, lessThanOrEqualTo(100));

    // 4×2 起卡头回来（回归：不能因为一格档把来源行全局删了）。
    await pumpCard(2, 240);
    await t.pump(const Duration(milliseconds: 100));
    expect(find.text('测试播放器'), findsOneWidget);
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('long titles and albums are clipped in every music card size',
      (t) async {
    final (c, g) = await setup(t);
    g.state['media'] = {
      ...(g.state['media'] as Map<String, dynamic>),
      'title': '超长的歌曲名称' * 14,
      'artist': '超长的歌手名称' * 14,
      'collection': '超长的专辑名称' * 14
    };
    g.stream.add(Map.of(g.state));
    for (final size in [
      (3, 2, 450.0, 240.0),
      (4, 2, 600.0, 240.0),
      (4, 3, 600.0, 390.0),
      (4, 4, 600.0, 530.0),
      (4, 5, 600.0, 690.0),
      (4, 6, 600.0, 820.0),
      (8, 6, 1200.0, 800.0),
    ]) {
      await t.pumpWidget(MaterialApp(
          theme: launcherTheme(SurfaceStyle.from(const Appearance(), true)),
          home: Scaffold(
              body: SizedBox(
                  width: size.$3,
                  height: size.$4,
                  child: CardContent(
                      card: LauncherCard(
                          'music', 'music', '音乐', 0, 0, size.$1, size.$2, 0),
                      controller: c)))));
      await t.pump(const Duration(milliseconds: 200));
      // 稿子的 4×4+ 把专辑并进副标题那行，没有独立的 music-card-album。
      final draft = size.$1 == 4 && size.$2 >= 4;
      for (final key in [
        'music-card-title',
        'music-card-artist',
        if (!draft) 'music-card-album'
      ]) {
        final field = find.byKey(ValueKey(key));
        expect(find.descendant(of: field, matching: find.byType(ClipRect)),
            findsWidgets,
            reason: '$size $key');
        final painter = find.byKey(ValueKey('marquee-paint-$key'));
        expect(painter, findsOneWidget, reason: '$size $key');
        final bounds = t.getRect(field);
        final paintBounds = t.getRect(painter);
        expect(paintBounds.width, greaterThan(60), reason: '$size $key');
        expect(paintBounds.left, greaterThanOrEqualTo(bounds.left - .1));
        expect(paintBounds.right, lessThanOrEqualTo(bounds.right + .1));
      }
      expect(t.takeException(), isNull, reason: '$size');
    }
  });

  testWidgets('every card exposes an unobstructed resize drag target',
      (t) async {
    final (c, _) = await setup(t);
    c.beginEdit();
    for (final spec in cardSpecs) {
      bool started = false;
      final card = LauncherCard(
          'resize-check', spec.type, spec.label, 0, 0, spec.w, spec.h, 0);
      await t.pumpWidget(MaterialApp(
          theme: launcherTheme(SurfaceStyle.from(const Appearance(), true)),
          home: Scaffold(
              body: SizedBox(
                  width: 650,
                  height: 500,
                  child: EditableCard(
                      card: card,
                      controller: c,
                      unitX: 80,
                      unitY: 80,
                      onPlacementStart: (_, resize, __) =>
                          started = resize)))));
      await t.pump(const Duration(milliseconds: 100));
      final handle = find.byKey(const ValueKey('resize-resize-check'));
      expect(handle.hitTestable(), findsOneWidget, reason: spec.type);
      expect(t.getSize(handle).width, closeTo(Design.px(64), .1));
      await t.drag(handle, const Offset(-40, -30));
      await t.pump();
      expect(started, isTrue, reason: spec.type);
      expect(t.takeException(), isNull, reason: spec.type);
    }
  });

  testWidgets('music edit strip retains source and playing title', (t) async {
    final (c, _) = await setup(t);
    c.beginEdit();
    await t.pumpWidget(MaterialApp(
        theme: launcherTheme(SurfaceStyle.from(const Appearance(), true)),
        home: Scaffold(
            body: SizedBox(
                width: 600,
                height: 400,
                child: EditableCard(
                    card: const LauncherCard(
                        'music-edit', 'music', '正在播放', 0, 0, 4, 3, 0),
                    controller: c,
                    unitX: 150,
                    unitY: 100)))));
    await t.pumpAndSettle();
    expect(find.text('测试播放器'), findsOneWidget);
    expect(find.text('正在播放'), findsOneWidget);
    final title = t.getRect(find.byKey(const ValueKey('media-source-entry')));
    expect(title.top, lessThan(70));
    expect(find.byKey(const ValueKey('music-app-picker')).hitTestable(),
        findsNothing);
    expect(t.takeException(), isNull);
  });

  testWidgets(
      'app long press opens info and disables uninstall for system apps',
      (t) async {
    final (c, g) = await setup(t);
    (g.state['apps'] as List).first['canUninstall'] = false;
    await t.pumpWidget(MaterialApp(
        theme: launcherTheme(SurfaceStyle.from(const Appearance(), true)),
        home: Scaffold(body: AppPanel(controller: c))));
    await t.pumpAndSettle();
    await t.longPress(find.text('测试播放器'));
    await t.pumpAndSettle();
    expect(
        t
            .widget<ListTile>(find.byKey(const ValueKey('app-menu-uninstall')))
            .enabled,
        false);
    expect(g.commands, isEmpty);
    await t.tap(find.byKey(const ValueKey('app-menu-info')));
    await t.pumpAndSettle();
    expect(g.commands.last['action'], 'app-info');
    expect(g.commands.last['value'], 'test.player');
    (g.state['apps'] as List).first['canUninstall'] = true;
    g.stream.add(Map.of(g.state));
    await t.pumpAndSettle();
    await t.longPress(find.text('测试播放器'));
    await t.pumpAndSettle();
    expect(
        t
            .widget<ListTile>(find.byKey(const ValueKey('app-menu-uninstall')))
            .enabled,
        true);
  });

  testWidgets('locked recent tasks cannot be swiped away', (t) async {
    final (c, g) = await setup(t, host: 'global-panel', global: true);
    g.state['globalDock'] = {
      'enabled': true,
      'running': true,
      'allowed': true,
      'panel': 'recents',
      'recentsReady': true,
      'recentsClearSupported': true
    };
    g.state['recentTasks'] = [
      {'taskId': 51, 'package': 'locked.app', 'label': '锁定应用', 'locked': true}
    ];
    g.stream.add(Map.of(g.state));
    await t.pumpWidget(MaterialApp(
        theme: launcherTheme(SurfaceStyle.from(const Appearance(), true)),
        home: const Scaffold(body: SizedBox(width: 1920, height: 984))));
    await t.pump();
    await t.pumpWidget(MaterialApp(
        theme: launcherTheme(SurfaceStyle.from(const Appearance(), true)),
        home: SizedBox(
            width: 1920, height: 984, child: RecentTasksPanel(controller: c))));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('recent-task-lock-51')), findsOneWidget);
    g.commands.clear();
    final card = find.byKey(const ValueKey('recent-task-51'));
    final before = t.getCenter(card);
    final gesture = await t.startGesture(before);
    await gesture.moveBy(const Offset(0, -40));
    await t.pump();
    await gesture.moveBy(const Offset(0, -150));
    await t.pump();
    expect(t.getCenter(card).dy, lessThan(before.dy));
    await gesture.up();
    await t.pumpAndSettle();
    expect(t.getCenter(card).dy, closeTo(before.dy, 1));
    expect(
        g.commands.where((a) => a['action'] == 'remove-recent-task'), isEmpty);
    await t.tap(find.byKey(const ValueKey('recent-task-lock-51')));
    await t.pumpAndSettle();
    expect(g.commands.last['action'], 'toggle-recent-lock');
    expect(g.commands.last['value'], '51');
    expect(t.takeException(), isNull);
  });

  testWidgets('applications page separates enabled and disabled apps',
      (t) async {
    final (c, g) = await setup(t);
    (g.state['apps'] as List).add({
      'id': 'disabled.map/.Main',
      'package': 'disabled.map',
      'label': '已禁用地图',
      'enabled': false,
      'canChangeEnabled': true
    });
    g.stream.add(Map.of(g.state));
    await t.pumpWidget(LauncherApp(controller: c));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('all-apps')));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('apps-enabled-grid')), findsOneWidget);
    expect(find.text('已禁用地图'), findsNothing);
    await t.tap(find.byKey(const ValueKey('apps-disabled')));
    await t.pumpAndSettle();
    expect(find.text('已禁用地图'), findsOneWidget);
    await t.longPress(find.byKey(const ValueKey('app-icon-ink-disabled.map')));
    await t.pumpAndSettle();
    expect(find.text('启用'), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('app-menu-toggle-enabled')));
    await t.pumpAndSettle();
    expect(g.commands.last['action'], 'app-enable');
    expect(g.commands.last['value'], 'disabled.map');
  });

  testWidgets('applications page filters system apps and puts filters above grid',
      (t) async {
    final (c, g) = await setup(t);
    (g.state['apps'] as List).addAll(<Map<String, dynamic>>[
      {
        'id': 'system.app/.Main',
        'package': 'system.app',
        'label': '系统应用',
        'isSystem': true,
        'enabled': true
      },
      {
        'id': 'disabled.system/.Main',
        'package': 'disabled.system',
        'label': '已禁用系统应用',
        'isSystem': true,
        'enabled': false
      },
      {
        'id': 'com.ecars.mycar.inter/.Internal',
        'package': 'com.ecars.mycar.inter',
        'label': 'com.ecars.mycar.inter',
        'enabled': true,
        'launchable': false
      },
    ]);
    g.stream.add(Map.of(g.state));
    await t.pumpWidget(LauncherApp(controller: c));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('all-apps')));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('apps-show-system')), findsOneWidget);
    expect(
        find.descendant(
            of: find.byKey(const ValueKey('apps-show-system')),
            matching: find.byType(DesignToggle)),
        findsOneWidget);
    expect(find.text('系统应用'), findsNothing);
    expect(find.text('com.ecars.mycar.inter'), findsNothing);
    // 稿子 f6 把筛选从左侧竖列收进面板顶部一行（.ap-tools），网格吃满宽度。
    final pills = t.getRect(find.byKey(const ValueKey('apps-enabled')));
    final grid = t.getRect(find.byKey(const ValueKey('apps-enabled-grid')));
    expect(pills.bottom, lessThan(grid.top), reason: '筛选条应在网格上方');
    final panel = t.getRect(find.byKey(const ValueKey('apps-panel')));
    expect(panel.contains(pills.topLeft), isTrue, reason: '筛选与网格同住一张面板卡');
    expect(panel.contains(grid.topLeft), isTrue);
    expect(find.text('长按图标可编辑'), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('apps-show-system')));
    await t.pumpAndSettle();
    expect(find.text('系统应用'), findsOneWidget);
    expect(find.text('com.ecars.mycar.inter'), findsNothing);
    await t.tap(find.byKey(const ValueKey('apps-disabled')));
    await t.pumpAndSettle();
    expect(find.text('已禁用系统应用'), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('apps-show-system')));
    await t.pumpAndSettle();
    expect(find.text('已禁用系统应用'), findsNothing);
    expect(t.takeException(), isNull);
  });

  testWidgets('music title opens player and bottom dock selects global panel',
      (t) async {
    final (c, g) = await setup(t, global: true);
    // 4×3 才有卡片头上的来源标识（4×4 起按稿子走无头版式）。
    c.cards = [const LauncherCard('music-1', 'music', '音乐', 0, 0, 4, 3, 0)];
    await t.pumpWidget(LauncherApp(controller: c));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('media-source-entry')).first);
    await t.pumpAndSettle();
    expect(g.commands.last['action'], 'launch-player');
    expect(find.byType(LauncherSheet), findsNothing);
    // 底栏引擎（hostMode=global-dock）：点音乐块不再弹旧的媒体面板，而是请桌面
    // 把音乐卡铺满（2026-11-13 实车反馈：那个面板是另一套窗口，关掉还会卡桌面）。
    g.state['hostMode'] = 'global-dock';
    g.stream.add(Map.of(g.state));
    await t.pumpWidget(GlobalDockApp(controller: c));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('music-info')));
    await t.pumpAndSettle();
    expect(g.commands.last['action'], 'focus-music-card');
    expect(g.commands.map((e) => e['action']), isNot(contains('show-dock-panel')));
    expect(find.byType(LauncherSheet), findsNothing);
  });

  testWidgets(
      'global panel replacement, close revision, source badge and glass setting',
      (t) async {
    final (c, g) = await setup(t, host: 'global-panel', global: true);
    c.setAppearance(c.appearance.copyWith(themeStyle: 'classic', glass: true),
        save: false);
    await t.pumpWidget(GlobalPanelApp(controller: c));
    await t.pumpAndSettle();
    void panel(String name, int rev) {
      g.state['globalDock'] = {
        'enabled': true,
        'running': true,
        'panel': name,
        'panelRevision': rev
      };
      g.stream.add(Map.of(g.state));
    }

    panel('climate', 1);
    await t.pumpAndSettle();
    expect(find.text('空调与座椅'), findsOneWidget);
    panel('media', 2);
    await t.pumpAndSettle();
    expect(find.text('空调与座椅'), findsNothing);
    expect(find.text('正在播放'), findsOneWidget);
    expect(find.text('打开关联播放器'), findsNothing);
    expect(find.text('测试播放器'), findsOneWidget);
    expect(t.getCenter(find.byKey(const ValueKey('media-source-entry'))).dy,
        lessThan(t.getCenter(find.text('曲名')).dy));
    expect(
        t.getCenter(find.byKey(const ValueKey('media-transport-controls'))).dx,
        closeTo(
            t.getCenter(find.byKey(const ValueKey('media-panel-content'))).dx,
            .1));
    expect(find.byType(BackdropFilter), findsWidgets);
    expect(
        g.commands.where((a) => a['action'] == 'dismiss-dock-panel'), isEmpty,
        reason: 'the old route must not close the new panel');
    await t.tap(find.byKey(const ValueKey('media-source-entry')));
    expect(g.commands.last['action'], 'launch-player');
    await t.tap(find.byTooltip('关闭音乐详情'));
    await t.pumpAndSettle();
    expect(g.commands.last['action'], 'dismiss-dock-panel');
    expect(g.commands.last['value'], '2');
    // GlobalPanelApp owns this controller and disposes it on unmount.
    await t.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
      'navigation binding uses discovered maps and excludes unrelated apps',
      (t) async {
    final (c, g) = await setup(t);
    (g.state['apps'] as List).add({
      'id': 'only.map/.MainActivity',
      'package': 'only.map',
      'label': '唯一地图'
    });
    g.state['integrationPreferences'] = {
      ...(g.state['integrationPreferences'] as Map<String, dynamic>? ?? {}),
      'navigationCardTitleHidden': false
    };
    await c.renameApp('only.map', '通勤导航');
    g.state['navigation'] = {
      'package': 'only.map',
      'preferredPackage': 'only.map',
      'label': '唯一地图',
      'options': [
        {'package': 'only.map', 'label': '唯一地图'},
        {'package': 'custom.map', 'label': '自选导航'}
      ],
      'canEmbed': false
    };
    g.stream.add(Map.of(g.state));
    await t.pumpWidget(LauncherApp(controller: c));
    await t.pumpAndSettle();
    expect(find.text('通勤导航'), findsWidgets);
    expect(find.text('唯一地图'), findsNothing);
    await t.tap(find.byKey(const ValueKey('nav-title-open')));
    expect(g.commands.last['action'], 'launch-navigation');
    await t.tap(find.byKey(const ValueKey('nav-app-picker')));
    await t.pumpAndSettle();
    expect(find.text('选择导航应用'), findsOneWidget);
    expect(find.text('通勤导航'), findsWidgets);
    expect(find.text('唯一地图'), findsNothing);
    // 无关应用不进主列表，只在「其他已安装应用」展开后才出现。
    expect(find.byKey(const ValueKey('nav-show-all')), findsOneWidget);
    expect(find.byKey(const ValueKey('nav-option-test.player')), findsNothing);
    await t.tap(find.byKey(const ValueKey('nav-option-custom.map')));
    await t.pumpAndSettle();
    expect(g.commands.last['action'], 'select-navigation');
    expect(g.commands.last['value'], 'custom.map');
  });

  testWidgets('settings use the same navigation options and aligned buttons',
      (t) async {
    final (c, g) = await setup(t);
    g.state['navigation'] = {
      'preferredPackage': 'auto',
      'options': [
        {'package': 'custom.map', 'label': '自选导航'}
      ]
    };
    await c.renameApp('custom.map', '通勤导航');
    await t.pumpWidget(MaterialApp(
        theme: launcherTheme(SurfaceStyle.from(const Appearance(), true)),
        home: Scaffold(
            body: SizedBox(
                width: 1400,
                height: 900,
                child: IntegrationSettings(
                    controller: c, native: Map.of(g.state))))));
    final dropdown = t.widget<DropdownButton<String>>(find.descendant(
        of: find.byKey(const ValueKey('navigation-source')),
        matching: find.byType(DropdownButton<String>)));
    expect(dropdown.items!.map((item) => item.value),
        containsAll(['auto', 'custom.map']));
    expect(dropdown.items!.map((item) => item.value),
        isNot(contains('test.player')));
    expect(t.getTopLeft(find.text('打开导航应用')).dy,
        closeTo(t.getTopLeft(find.text('打开关联播放器')).dy, .1));
    expect(t.takeException(), isNull);
  });

  testWidgets('nocturne UNI popup uses the opaque sheet background', (t) async {
    final (c, _) = await setup(t);
    c.setAppearance(c.appearance.copyWith(themeStyle: 'nocturne'));
    await t.pumpWidget(LauncherApp(controller: c));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('uni-menu')));
    await t.pumpAndSettle();
    final popup =
        t.widget<GlassSurface>(find.byKey(const ValueKey('uni-popup-panel')));
    expect(popup.sheet, isTrue);
    expect(find.text('车辆信息'), findsWidgets);
    expect(t.takeException(), isNull);
  });

  testWidgets('focused music card fills the page without a backdrop filter',
      (t) async {
    final (c, _) = await setup(t);
    await t.pumpWidget(LauncherApp(controller: c));
    await t.pumpAndSettle();
    // 稿子 f5：底栏音乐块点进去把那张音乐卡铺满整页（头部与底栏仍在）。
    await t.tap(find.byKey(const ValueKey('music-info')));
    await t.pumpAndSettle();
    expect(c.focusedCard.value, isNotNull);
    expect(find.byKey(const ValueKey('music-player-title')), findsOneWidget);
    expect(find.byType(Header), findsOneWidget);
    // 铺满的卡片自己是不透明底，玻璃开关下都不挂 BackdropFilter。
    expect(
        find.descendant(
            of: find.byType(GlassSurface),
            matching: find.byType(BackdropFilter)),
        findsNothing);
    await t.tap(find.byKey(const ValueKey('card-focus-close')));
    await t.pumpAndSettle();
    expect(c.focusedCard.value, isNull);
    c.setAppearance(c.appearance.copyWith(themeStyle: 'classic', glass: true),
        save: false);
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('music-info')));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('music-player-title')), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('card-focus-close')));
    await t.pumpAndSettle();
  });

  testWidgets('long music card lyric wraps instead of ellipsizing', (t) async {
    final (c, g) = await setup(t);
    const longLine = '这一句歌词特别长，需要在音乐卡片中自动换行显示，不能在宽度不足时直接使用省略号截断';
    g.state['media'] = {
      ...(g.state['media'] as Map<String, dynamic>),
      'lyrics': '[00:00]$longLine',
      'positionMs': 0
    };
    g.stream.add(Map.of(g.state));
    await t.pumpWidget(MaterialApp(
        theme: launcherTheme(SurfaceStyle.from(const Appearance(), true)),
        home: Scaffold(
            body: Center(
                child: SizedBox(
                    width: 320,
                    height: 180,
                    child: LyricsView(
                        media: c.native.value['media'] as Map<String, dynamic>,
                        visibleLines: 3,
                        lineHeight: 44,
                        fontSize: 26,
                        textAlign: TextAlign.center))))));
    await t.pumpAndSettle();
    final paragraph = t.renderObject<RenderParagraph>(find.text(longLine));
    expect(paragraph.maxLines, isNull);
    expect(paragraph.overflow, isNot(TextOverflow.ellipsis));
    expect(paragraph.size.height, greaterThan(44));
    expect(t.takeException(), isNull);
  });
}
