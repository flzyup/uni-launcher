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

  testWidgets(
      'music body opens shared panel; source title still launches player; edit suppresses panel',
      (t) async {
    final (c, g) = await setup(t);
    Future<void> card() => t.pumpWidget(host(SizedBox(
        width: 600,
        height: 400,
        child: CardContent(
            card: const LauncherCard('m', 'music', '音乐', 0, 0, 4, 3, 0),
            controller: c))));
    await card();
    await t.pumpAndSettle();
    await t.tap(find.text('向海而行'));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('media-panel-content')), findsOneWidget);
    await t.tap(find.byTooltip('关闭音乐详情'));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('media-source-entry')));
    await t.pump();
    expect(g.commands.last['action'], 'launch-player');
    c.editing = true;
    await card();
    await t.pumpAndSettle();
    await t.tap(find.text('向海而行'));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('media-panel-content')), findsNothing);
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
    expect(find.text('新歌词').hitTestable(), findsOneWidget);
  });

  testWidgets(
      'fan shows fresh AUTO or manual gear; stale telemetry never implies AUTO',
      (t) async {
    final (c, _) = await setup(t);
    final now = DateTime.now().millisecondsSinceEpoch;
    Map<String, dynamic> n(bool auto, {bool valid = true}) => {
          'demo': false,
          'climate': {'auto': true, 'fan': 9},
          'vehicle': {
            'connected': true,
            'fields': {
              'auto': {'valid': valid, 'value': auto, 'updatedAtMs': now},
              'fan': {'valid': valid, 'value': 4, 'updatedAtMs': now}
            }
          }
        };
    await t.pumpWidget(host(DockClimateButton(controller: c, native: n(true))));
    expect(find.text('AUTO'), findsOneWidget);
    expect(find.byKey(const ValueKey('dock-fan-segment-7')), findsNothing);
    await t
        .pumpWidget(host(DockClimateButton(controller: c, native: n(false))));
    expect(find.text('AUTO'), findsNothing);
    expect(find.text('4'), findsNothing);
    for (var index = 1; index <= 7; index++) {
      expect(find.byKey(ValueKey('dock-fan-segment-$index')), findsOneWidget);
    }
    await t.pumpWidget(
        host(DockClimateButton(controller: c, native: n(true, valid: false))));
    expect(find.text('AUTO'), findsNothing);
    expect(find.text('—'), findsNothing);
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
    expect(music.width, closeTo(866.462, .1));

    c.setAppearance(c.appearance.copyWith(dockMusicProgressBackground: false));
    await t.pump(const Duration(milliseconds: 100));
    expect(find.byKey(const ValueKey('dock-music-progress')), findsNothing);
    expect(t.getRect(find.byKey(const ValueKey('dock-climate-frame'))).width,
        climate.width);
    expect(t.takeException(), isNull);
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
            host(SpectrumSettings(controller: c), a: c.appearance)));
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
