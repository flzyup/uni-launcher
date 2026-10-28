import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uni_launcher/controller/launcher_controller.dart';
import 'package:uni_launcher/launcher_app.dart';
import 'package:uni_launcher/model/appearance.dart';
import 'package:uni_launcher/screens/global_dock_app.dart';
import 'package:uni_launcher/screens/global_panel_app.dart';
import 'package:uni_launcher/theme/launcher_theme.dart';
import 'package:uni_launcher/widgets/bottom_dock.dart';
import 'package:uni_launcher/widgets/launcher_dialog.dart';
import 'package:uni_launcher/widgets/glass_surface.dart';
import 'package:uni_launcher/widgets/card_content.dart';
import 'package:uni_launcher/model/card_layout.dart';
import 'package:uni_launcher/widgets/lyrics_view.dart';
import 'fake_gateway.dart';
import 'package:uni_launcher/widgets/recent_tasks_panel.dart';
import 'package:uni_launcher/widgets/uni_icon.dart';

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
    c.native.value = {...c.native.value, 'vehicle': {'speed': 42}};
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
      'vehicle'
    ];
    for (var i = 1; i < order.length; i++) {
      expect(t.getCenter(find.byKey(ValueKey(order[i]))).dx,
          greaterThan(t.getCenter(find.byKey(ValueKey(order[i - 1]))).dx));
    }
    await t.tap(find.byKey(const ValueKey('recents')));
    expect(g.commands.last['action'], 'show-recents');
    final cameraIcon = t.widget<UniIcon>(find.descendant(
        of: find.byKey(const ValueKey('camera')),
        matching: find.byType(UniIcon)));
    expect(cameraIcon.name, 'camera-360');
    final title = t.getCenter(find.byKey(const ValueKey('dock-track-title')));
    expect(find.byKey(const ValueKey('audio-spectrum-paint')), findsOneWidget);
    await t.drag(find.byKey(const ValueKey('dock-music-visual-pages')),
        const Offset(-400, 0));
    await t.pumpAndSettle();
    final lyric = t.getCenter(find.byKey(const ValueKey('dock-lyrics')));
    expect(lyric.dx, greaterThan(title.dx));
    expect(lyric.dy, closeTo(title.dy, .1));
    expect(find.text('当前句'), findsOneWidget);
    final lyrics = t.widget<LyricsView>(find.byType(LyricsView));
    expect(lyrics.visibleLines, 1);
    expect(lyrics.currentLineMaxLines, 2);
    expect(t.takeException(), isNull);
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

  testWidgets(
      'music card sizes keep lyrics only in 4x4 and 8x6 with metadata on left',
      (t) async {
    final (c, _) = await setup(t);
    for (final size in [
      (3, 2, 450.0, 240.0),
      (4, 2, 600.0, 240.0),
      (4, 3, 600.0, 390.0),
      (4, 4, 600.0, 530.0),
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
      expect(find.text('测试播放器'), findsOneWidget);
      expect(find.text('正在播放'), findsOneWidget);
      if (size.$2 < 4) {
        expect(find.byType(LyricsView), findsNothing);
        await t.tap(find.byKey(const ValueKey('media-source-entry')));
        expect(c.gateway, isA<FakeGateway>());
        expect((c.gateway as FakeGateway).commands.last['action'],
            'launch-player');
      } else {
        expect(find.byKey(const ValueKey('music-card-lyrics')), findsOneWidget);
        expect(
            t.getCenter(find.byKey(const ValueKey('music-card-lyrics'))).dx,
            greaterThan(t
                .getCenter(find.byKey(const ValueKey('music-card-metadata')))
                .dx));
      }
      expect(t.takeException(), isNull);
    }
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

  testWidgets('music title opens player and bottom dock selects global panel',
      (t) async {
    final (c, g) = await setup(t, global: true);
    await t.pumpWidget(LauncherApp(controller: c));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('media-source-entry')).first);
    await t.pumpAndSettle();
    expect(g.commands.last['action'], 'launch-player');
    expect(find.byType(LauncherSheet), findsNothing);
    await t.pumpWidget(GlobalDockApp(controller: c));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('music-info')));
    await t.pumpAndSettle();
    expect(g.commands.last['action'], 'show-dock-panel');
    expect(g.commands.last['value'], 'media');
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
    expect(find.text('座舱舒适'), findsOneWidget);
    panel('media', 2);
    await t.pumpAndSettle();
    expect(find.text('座舱舒适'), findsNothing);
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
      'navigation binding entry stays visible with one map and accepts other installed apps',
      (t) async {
    final (c, g) = await setup(t);
    (g.state['apps'] as List).add({
      'id': 'only.map/.MainActivity',
      'package': 'only.map',
      'label': '唯一地图'
    });
    await c.renameApp('only.map', '通勤导航');
    g.state['navigation'] = {
      'package': 'only.map',
      'preferredPackage': 'only.map',
      'label': '唯一地图',
      'options': [
        {'package': 'only.map', 'label': '唯一地图'}
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
    await t.tap(find.byKey(const ValueKey('nav-show-all')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('nav-option-custom.map')));
    await t.pumpAndSettle();
    expect(g.commands.last['action'], 'select-navigation');
    expect(g.commands.last['value'], 'custom.map');
  });

  testWidgets('local music sheet disables backdrop filters when glass is off',
      (t) async {
    final (c, _) = await setup(t);
    await t.pumpWidget(LauncherApp(controller: c));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('music-info')));
    await t.pumpAndSettle();
    expect(find.byType(LauncherSheet), findsOneWidget);
    expect(find.byType(BackdropFilter), findsNothing);
    expect(
        find.descendant(
            of: find.byType(LauncherSheet), matching: find.text('测试播放器')),
        findsOneWidget);
    await t.tap(find.byTooltip('关闭音乐详情'));
    await t.pumpAndSettle();
    c.setAppearance(c.appearance.copyWith(themeStyle: 'classic', glass: true),
        save: false);
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('music-info')));
    await t.pumpAndSettle();
    expect(find.byType(BackdropFilter), findsWidgets);
  });
}
