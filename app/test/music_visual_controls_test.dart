import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uni_launcher/controller/launcher_controller.dart';
import 'package:uni_launcher/model/appearance.dart';
import 'package:uni_launcher/model/card_layout.dart';
import 'package:uni_launcher/theme/launcher_theme.dart';
import 'package:uni_launcher/screens/global_dock_app.dart';
import 'package:uni_launcher/widgets/card_content.dart';
import 'package:uni_launcher/widgets/dock_climate_button.dart';
import 'package:uni_launcher/widgets/spectrum_painter.dart';
import 'package:uni_launcher/screens/settings_screen.dart';
import 'fake_gateway.dart';

void main() {
  Future<(LauncherController, FakeGateway)> setup(WidgetTester t) async {
    t.view.physicalSize = const Size(1920, 1080);
    t.view.devicePixelRatio = 1;
    final g = FakeGateway();
    final controller = LauncherController(g);
    await controller.initialize();
    addTearDown(() async {
      await t.pumpWidget(const SizedBox());
      controller.dispose();
      await g.dispose();
      t.view.resetPhysicalSize();
      t.view.resetDevicePixelRatio();
    });
    return (controller, g);
  }

  Widget host(Widget child, {Appearance a = const Appearance()}) => MaterialApp(
      theme: launcherTheme(SurfaceStyle.from(a, true)),
      home: Scaffold(body: Center(child: child)));

  testWidgets('music body opens the fullscreen player; edit suppresses it',
      (t) async {
    final (c, _) = await setup(t);
    Future<void> card() => t.pumpWidget(host(SizedBox(
        width: 600,
        height: 400,
        child: CardContent(
            card: const LauncherCard('m', 'music', '音乐', 0, 0, 4, 3, 0),
            controller: c))));
    await card();
    await t.pumpAndSettle();
    await t.tap(find.text('午夜立交'));
    await t.pumpAndSettle();
    // 稿子 f5：点进卡片就把这张卡铺满整页（铺满层在桌面里，这里断言状态）。
    expect(c.focusedCard.value, isNotNull);
    c.unfocusCard();
    await t.pumpAndSettle();
    expect(c.focusedCard.value, isNull);
    c.editing = true;
    await card();
    await t.pumpAndSettle();
    await t.tap(find.text('午夜立交'));
    await t.pumpAndSettle();
    expect(c.focusedCard.value, isNull, reason: '编辑态不该铺满');
  });

  testWidgets(
      'lyrics default first; horizontal dock swipe preserves spectrum selection across media updates',
      (t) async {
    final (c, g) = await setup(t);
    await t.pumpWidget(GlobalDockApp(controller: c));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('dock-lyrics')).hitTestable(),
        findsOneWidget);
    final pager = find.byKey(const ValueKey('dock-music-visual-pages'));
    await t.drag(pager, const Offset(-500, 0));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('audio-spectrum-paint')).hitTestable(),
        findsOneWidget);
    expect(find.byKey(const ValueKey('media-panel-content')), findsNothing);
    g.state['media'] = {
      ...g.state['media'] as Map,
      'title': '新曲目',
      'lyricLine': '新歌词'
    };
    g.stream.add(Map.of(g.state));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('audio-spectrum-paint')).hitTestable(),
        findsOneWidget);
    await t.drag(pager, const Offset(500, 0));
    await t.pumpAndSettle();
    // 底栏元数据槽也显示当前一句歌词，歌词页内的断言收窄到该子树。
    expect(
        find.descendant(
            of: find.byKey(const ValueKey('dock-lyrics')),
            matching: find.text('新歌词')),
        findsOneWidget);
  });

  testWidgets(
      'fan flower stays a flower; fan bars light up to the current gear; AUTO pill commands auto',
      (t) async {
    final (c, g) = await setup(t);
    final now = DateTime.now().millisecondsSinceEpoch;
    Map<String, dynamic> n({bool? auto, int? fan}) => {
          'demo': false,
          'climate': const {},
          'vehicle': {
            'connected': true,
            'fields': {
              if (auto != null)
                'auto': {'valid': true, 'value': auto, 'updatedAtMs': now},
              if (fan != null)
                'fan': {'valid': true, 'value': fan, 'updatedAtMs': now},
            }
          }
        };
    // 风扇单元：上面四瓣花、下面七根柱，整块只占一个 72 方格（AUTO 另起一格）。
    await t.pumpWidget(
        host(DockFanCluster(controller: c, native: n(auto: true, fan: 4))));
    expect(find.byKey(const ValueKey('dock-fan-flower')), findsOneWidget);
    expect(find.text('AUTO'), findsNothing);
    // 风量柱：七档与原生 fan 一一对应，不再折成三档。
    for (var index = 1; index <= 7; index++) {
      expect(find.byKey(ValueKey('dock-fan-segment-$index')), findsOneWidget);
    }
    expect(find.byKey(const ValueKey('dock-fan-segment-8')), findsNothing);
    Color segColor(int index) => ((t.widget<Container>(
                find.byKey(ValueKey('dock-fan-segment-$index'))))
            .decoration! as BoxDecoration)
        .color!;
    // 4 档：前 4 根亮、后 3 根暗，且暗柱仍有可见度（实车要求，不是全透明）。
    expect(segColor(4), isNot(segColor(5)));
    expect(segColor(5), segColor(7));
    expect(segColor(7).a, greaterThan(.05));
    // 1 档只亮第一根；7 档亮满。
    await t.pumpWidget(host(DockFanCluster(controller: c, native: n(fan: 1))));
    expect(segColor(1), isNot(segColor(2)));
    expect(segColor(2), segColor(7));
    await t.pumpWidget(host(DockFanCluster(controller: c, native: n(fan: 7))));
    expect(segColor(7), segColor(1));
    // 遥测缺失时没有柱被点亮。
    await t.pumpWidget(host(DockFanCluster(
        controller: c, native: {'demo': false, 'climate': const {}})));
    expect(segColor(1), segColor(7));
    // 自动空调时 dock 这一格**仍是花 + 柱**，不再被 AUTO 顶替：
    // AUTO 胶囊原来独占第七格，把六项间距全挤乱了（2026-11-15 方案 C）。
    // AUTO 状态只体现在触摸提示里，开关挪回空调面板。
    g.state['climate'] = {...g.state['climate'] as Map, 'auto': true};
    g.stream.add(Map.of(g.state));
    await t.pumpWidget(GlobalDockApp(controller: c));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('dock-auto-pill')), findsNothing);
    expect(find.byKey(const ValueKey('dock-fan-flower')), findsOneWidget);
    expect(find.byTooltip('空调与座椅，自动风量'), findsOneWidget);
  });

  testWidgets(
      'dock music progress background stays inside its area and keeps climate width',
      (t) async {
    final (c, g) = await setup(t);
    final now = DateTime.now().millisecondsSinceEpoch;
    g.state['media'] = {
      ...g.state['media'] as Map,
      'playing': true,
      'positionKnown': true,
      'positionMs': 50000,
      'durationMs': 200000,
      'sampledAtMs': now
    };
    g.stream.add(Map.of(g.state));
    await t.pumpWidget(GlobalDockApp(controller: c));
    await t.pump(const Duration(milliseconds: 100));
    expect(find.byKey(const ValueKey('dock-music-progress')), findsOneWidget);
    expect(find.byType(BackdropFilter), findsNothing);
    final climate = t.getRect(find.byKey(const ValueKey('dock-climate-frame')));
    final music = t.getRect(find.byKey(const ValueKey('dock-music-frame')));
    expect(climate.width, greaterThan(0));
    // 831 = 720.83 - 19 - 9.17：空调胶囊按设计稿 C 定宽到画布 459（+19），
    // 分隔线右侧由 5 改成 16（+9.17），两笔都从媒体区扣。
    expect(music.width, closeTo(831.0, 1));

    c.setAppearance(c.appearance.copyWith(dockMusicProgressBackground: false));
    await t.pump(const Duration(milliseconds: 100));
    expect(find.byKey(const ValueKey('dock-music-progress')), findsNothing);
    expect(t.getRect(find.byKey(const ValueKey('dock-climate-frame'))).width,
        climate.width);
    expect(t.takeException(), isNull);
  });

  testWidgets('enabled dock visual shares space equally with track metadata',
      (t) async {
    final (c, _) = await setup(t);
    await t.pumpWidget(GlobalDockApp(controller: c));
    await t.pumpAndSettle();
    final frame = t.getRect(find.byKey(const ValueKey('dock-music-frame')));
    final metadata = t.getRect(find.byKey(const ValueKey('dock-track-title')));
    final visual =
        t.getRect(find.byKey(const ValueKey('dock-music-visual-pages')));
    expect(metadata.right, lessThan(visual.left));
    expect(visual.width, closeTo(metadata.width, .1));
    expect(visual.width, greaterThan(frame.width * .25));
    expect(t.takeException(), isNull);
  });

  testWidgets('glass climate and music frames align in both dock layouts',
      (t) async {
    final (c, _) = await setup(t);
    for (final layout in ['floating', 'full']) {
      for (final visual in [true, false]) {
        c.setAppearance(c.appearance.copyWith(dockSize: 'extraLarge'));
        c.setAppearance(c.appearance.copyWith(
            themeStyle: 'blueGlass',
            dockLayout: layout,
            dockMusicVisual: visual));
        await t.pumpWidget(GlobalDockApp(controller: c));
        await t.pump(const Duration(milliseconds: 100));
        final climate =
            t.getRect(find.byKey(const ValueKey('dock-climate-frame')));
        final music = t.getRect(find.byKey(const ValueKey('dock-music-frame')));
        expect(climate.height, closeTo(music.height, .1),
            reason: '$layout $visual');
        expect(climate.center.dy, closeTo(music.center.dy, .1),
            reason: '$layout $visual');
        expect(t.takeException(), isNull);
      }
    }
  });

  testWidgets(
      'style settings use static previews and persist by normal appearance repository',
      (t) async {
    final (c, g) = await setup(t);
    await t.pumpWidget(AnimatedBuilder(
        animation: c,
        builder: (context, _) =>
            host(SpectrumSettings(controller: c), a: c.appearance)));
    for (final style in spectrumStyleLabels.keys) {
      await t.tap(find.byKey(ValueKey('spectrum-style-$style')));
      await t.pumpAndSettle();
      expect(c.appearance.spectrumStyle, style);
      await c.persist();
      expect(jsonDecode(g.saved!)['preferences']['spectrumStyle'], style);
    }
    final restored = FakeGateway()..state['savedDesign'] = g.saved;
    final loaded = LauncherController(restored);
    await loaded.initialize();
    expect(loaded.appearance.spectrumStyle, 'outline');
    loaded.dispose();
    await restored.dispose();
    expect(const Appearance().spectrumStyle, 'segments');
    expect(
        Appearance.fromJson({'spectrumStyle': 'bars'}).spectrumStyle, 'bars');
    expect(Appearance.fromJson({'spectrumStyle': 'invalid'}).spectrumStyle,
        'bars');
    expect(const Appearance().dockMusicProgressBackground, isTrue);
    expect(
        Appearance.fromJson({'dockMusicProgressBackground': false})
            .dockMusicProgressBackground,
        isFalse);
    expect(
        Appearance.fromJson({'dockMusicProgressBackground': 'invalid'})
            .dockMusicProgressBackground,
        isTrue);
    expect(t.takeException(), isNull);
  });

  testWidgets('dock music progress setting toggles and persists', (t) async {
    final (c, g) = await setup(t);
    await t.pumpWidget(AnimatedBuilder(
        animation: c,
        builder: (context, _) =>
            host(SpectrumSettings(controller: c), a: c.appearance)));
    expect(find.text('音乐进度动态背景'), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('dock-music-progress-switch')));
    await t.pumpAndSettle();
    expect(c.appearance.dockMusicProgressBackground, isFalse);
    await c.persist();
    expect(jsonDecode(g.saved!)['preferences']['dockMusicProgressBackground'],
        isFalse);
    final restored = FakeGateway()..state['savedDesign'] = g.saved;
    final loaded = LauncherController(restored);
    await loaded.initialize();
    expect(loaded.appearance.dockMusicProgressBackground, isFalse);
    loaded.dispose();
    await restored.dispose();
    expect(t.takeException(), isNull);
  });

  testWidgets('dock music visual setting toggles and persists', (t) async {
    final (c, g) = await setup(t);
    await t.pumpWidget(AnimatedBuilder(
        animation: c,
        builder: (context, _) =>
            host(DockSettings(controller: c), a: c.appearance)));
    expect(find.text('底部音乐工具条'), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('dock-music-visual-switch')));
    await t.pumpAndSettle();
    expect(c.appearance.dockMusicVisual, isFalse);
    await c.persist();
    expect(jsonDecode(g.saved!)['preferences']['dockMusicVisual'], isFalse);
    final restored = FakeGateway()..state['savedDesign'] = g.saved;
    final loaded = LauncherController(restored);
    await loaded.initialize();
    expect(loaded.appearance.dockMusicVisual, isFalse);
    loaded.dispose();
    await restored.dispose();
    expect(t.takeException(), isNull);
  });
}
