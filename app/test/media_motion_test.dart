import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uni_launcher/controller/launcher_controller.dart';
import 'package:uni_launcher/launcher_app.dart';
import 'package:uni_launcher/model/appearance.dart';
import 'package:uni_launcher/model/page_motion.dart';
import 'package:uni_launcher/model/lyrics.dart';
import 'package:uni_launcher/widgets/lyrics_view.dart';
import 'package:uni_launcher/widgets/media_progress.dart';
import 'package:uni_launcher/widgets/page_transition.dart';
import 'fake_gateway.dart';
import 'package:uni_launcher/theme/launcher_theme.dart';
import 'package:uni_launcher/theme/design_tokens.dart';

void main() {
  test('LRC supports multiple timestamps, precision, offset and backward seek',
      () {
    final l = Lyrics.parse(
        '[ar:Artist]\n[offset:-500]\n[00:01.2][00:03.25]重复行\n[00:02.123]另一行\n[00:65]非法秒');
    expect(l.timed, true);
    expect(l.lines.map((v) => v.timeMs), [700, 1623, 2750]);
    expect(l.activeAt(699), -1);
    expect(l.activeAt(1623), 1);
    expect(l.activeAt(5000), 2);
    expect(l.activeAt(800), 0);
    expect(l.lines.map((v) => v.text), ['重复行', '另一行', '重复行']);
  });
  test(
      'Plain lyrics have no fabricated timing; malformed and oversized inputs are bounded',
      () {
    final l = Lyrics.parse('第一行\n第二行');
    expect(l.timed, false);
    expect(l.activeAt(90000), -1);
    expect(l.lines.length, 2);
    expect(Lyrics.parse(null).lines, isEmpty);
    expect(Lyrics.parse('x' * 131073).lines, isEmpty);
  });
  test('Playback clock extrapolates speed, pauses and clamps duration', () {
    Map<String, dynamic> state = {
      'positionMs': 1000,
      'sampledAtMs': 10000,
      'durationMs': 5000,
      'speed': 2,
      'playing': true,
      'positionKnown': true
    };
    expect(MediaTimeline.fromJson(state).at(11000), 3000);
    expect(MediaTimeline.fromJson(state).at(15000), 5000);
    expect(
        MediaTimeline.fromJson({...state, 'playing': false}).at(15000), 1000);
    expect(MediaTimeline.fromJson(state).at(9000), 1000);
  });
  testWidgets(
      'Lyrics follow progress, seek backward and clear on track without lyrics',
      (t) async {
    Future<void> display(String lyrics, int position) async {
      await t.pumpWidget(MaterialApp(
          theme: launcherTheme(SurfaceStyle.from(const Appearance(), true)),
          home: Scaffold(
              body: SizedBox(
                  width: 400,
                  child: LyricsView(media: {
                    'lyrics': lyrics,
                    'playing': false,
                    'positionMs': position,
                    'positionKnown': true
                  })))));
      await t.pumpAndSettle();
    }

    const lrc = '[00:00]第一行\n[00:03]第二行\n[00:06]第三行\n[00:09]第四行';
    await display(lrc, 6500);
    expect(find.byKey(const ValueKey('lyric-line-2-active')), findsOneWidget);
    final scroll = t.state<ScrollableState>(find.descendant(
        of: find.byKey(const ValueKey('lyrics-scroll')),
        matching: find.byType(Scrollable)));
    expect(scroll.position.pixels, 60);
    await display(lrc, 1000);
    expect(scroll.position.pixels, 0);
    expect(find.byKey(const ValueKey('lyric-line-0-active')), findsOneWidget);
    await display('', 0);
    expect(find.byKey(const ValueKey('lyrics-empty')), findsOneWidget);
    expect(find.text('第三行'), findsNothing);
    expect(t.takeException(), null);
  });
  testWidgets(
      'current dock lyric wraps to two lines and centers short and long text',
      (t) async {
    Future<void> show(String line) async {
      await t.pumpWidget(MaterialApp(
          theme: launcherTheme(SurfaceStyle.from(const Appearance(), true)),
          home: Scaffold(
              body: SizedBox(
                  width: 240,
                  height: 80,
                  child: LyricsView(
                      media: {'lyricLine': line},
                      currentLineMaxLines: 2,
                      lineHeight: 32,
                      fontSize: 26)))));
      await t.pumpAndSettle();
    }

    const key = ValueKey('current-lyric-wrapped');
    await show('一句歌词');
    final single = t.getSize(find.byKey(key)).height;
    expect(t.getCenter(find.byKey(key)), t.getCenter(find.byType(LyricsView)));
    await show('这是一句需要自动换行且超过两行时以省略号结束的很长歌词' * 3);
    expect(t.getSize(find.byKey(key)).height, closeTo(single * 2, .1));
    expect(t.getCenter(find.byKey(key)), t.getCenter(find.byType(LyricsView)));
    final text = t.widget<Text>(find.byKey(key));
    expect(text.maxLines, 2);
    expect(text.softWrap, true);
    expect(text.overflow, TextOverflow.ellipsis);
    expect(text.textAlign, TextAlign.center);
    expect(t.takeException(), isNull);
  });
  testWidgets(
      'single-line dock keeps a long unavailable-lyrics reason inside its row',
      (t) async {
    await t.pumpWidget(MaterialApp(
        theme: launcherTheme(SurfaceStyle.from(const Appearance(), true)),
        home: Scaffold(
            body: SizedBox(
                width: 240,
                child: LyricsView(
                    visibleLines: 1,
                    lineHeight: 40,
                    fontSize: 26,
                    media: const {
                      'lyricsReason': '网易云当前版本未向桌面共享歌词，请选择其他音源'
                    })))));
    await t.pumpAndSettle();
    final label = t.widget<Text>(find.byKey(const ValueKey('lyrics-empty')));
    expect(label.maxLines, 1);
    expect(label.overflow, TextOverflow.ellipsis);
    expect(t.getSize(find.byType(LyricsView)).height, Design.px(40));
    expect(t.takeException(), isNull);
  });
  testWidgets(
      'Three-line source callbacks keep real neighbors and current line centered',
      (t) async {
    await t.pumpWidget(MaterialApp(
        theme: launcherTheme(SurfaceStyle.from(const Appearance(), true)),
        home: Scaffold(
            body: SizedBox(
                width: 400,
                child: LyricsView(
                    visibleLines: 3,
                    lineHeight: 22,
                    fontSize: 16,
                    media: const {
                      'lyricPrevious': '已唱过',
                      'lyricLine': '正在唱',
                      'lyricNext': '将唱到'
                    })))));
    await t.pumpAndSettle();
    expect(find.text('已唱过'), findsOneWidget);
    expect(find.text('正在唱'), findsOneWidget);
    expect(find.text('将唱到'), findsOneWidget);
    expect(t.getCenter(find.text('正在唱')).dy,
        closeTo(t.getCenter(find.byType(LyricsView)).dy, .1));
  });
  testWidgets(
      'Seek gesture sends one bounded position and unsupported source is read only',
      (t) async {
    final positions = <int>[];
    Future<void> display(bool supported) async {
      await t.pumpWidget(MaterialApp(
          theme: launcherTheme(SurfaceStyle.from(const Appearance(), true)),
          home: Scaffold(
              body: SizedBox(
                  width: 600,
                  child: MediaProgress(
                    media: {
                      'durationMs': 180000,
                      'positionMs': 10000,
                      'positionKnown': true,
                      'playing': false,
                      'canSeek': supported
                    },
                    onSeek: positions.add,
                  )))));
      await t.pumpAndSettle();
    }

    await display(true);
    final slider = find.byKey(const ValueKey('media-seek'));
    await t.drag(slider, const Offset(200, 0));
    await t.pumpAndSettle();
    expect(positions.length, 1);
    expect(positions.single, inInclusiveRange(10000, 180000));
    await display(false);
    expect(find.byType(Slider), findsNothing);
    expect(positions.length, 1);
  });
  test('Transition preference has a safe default and round trips', () {
    expect(Appearance.fromJson({}).pageTransition, 'slide');
    expect(Appearance.fromJson({'pageTransition': 'unknown'}).pageTransition,
        'slide');
    for (final effect in pageEffects.map((e) => e.id)) {
      expect(
          Appearance.fromJson(
                  const Appearance().copyWith(pageTransition: effect).toJson())
              .pageTransition,
          effect);
    }
  });
  testWidgets('Motion setting persists; real pages move while dock stays fixed',
      (t) async {
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
    c.openSettings();
    c.tab('motion');
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('transition-slide')));
    await t.pumpAndSettle();
    expect(jsonDecode(g.saved!)['preferences']['pageTransition'], 'slide');
    c.home();
    await t.pumpAndSettle();
    final dockBefore = t.getRect(find.byKey(const ValueKey('bottom-dock')));
    final indicator = find.byKey(const ValueKey('page-indicator-active'));
    expect(t.getRect(indicator).center.dy, lessThan(64));
    final start = t.getRect(indicator).left;
    final nav = find.byKey(const ValueKey('nav-1'));
    final navStart = t.getRect(nav).left;
    // A slow drag, not a fling. It must move before release, even at zero velocity.
    final gesture = await t.startGesture(const Offset(1810, 770));
    await gesture.moveBy(const Offset(-30, 0));
    await t.pump();
    await gesture.moveBy(const Offset(-550, 0));
    await t.pump();
    expect(c.page, 0);
    expect(t.getRect(indicator).left, greaterThan(start));
    expect(t.getRect(nav).left, lessThan(navStart - 300));
    expect(find.byKey(const ValueKey('tpms-1')), findsOneWidget);
    expect(t.getRect(find.byKey(const ValueKey('bottom-dock'))), dockBefore);
    await gesture.up();
    await t.pumpAndSettle();
    expect(c.page, 1);
    expect(find.byKey(const ValueKey('nav-1')), findsNothing);
    expect(t.getRect(indicator).left, greaterThan(start));
    for (final effect in ['fade', 'zoom', 'depth', 'none']) {
      c.setAppearance(c.appearance.copyWith(pageTransition: effect));
      await t.pumpAndSettle();
      await c.switchPage(0);
      await t.pump();
      if (effect != 'none') {
        await t.pump(const Duration(milliseconds: 90));
        expect(find.byKey(const ValueKey('tpms-1')), findsOneWidget);
      }
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('nav-1')), findsOneWidget);
      expect(find.byKey(const ValueKey('tpms-1')), findsNothing);
      await c.switchPage(1);
      await t.pumpAndSettle();
    }
    expect(t.takeException(), isNull);
  });
  testWidgets('System reduced motion disables workspace animation', (t) async {
    Future<void> show(int page) => t.pumpWidget(MaterialApp(
        home: MediaQuery(
            data: const MediaQueryData(disableAnimations: true),
            child: DesktopPageStack(
                page: page,
                effect: 'slide',
                children: const [Text('page 1'), Text('page 2')]))));
    await show(0);
    await show(1);
    await t.pump();
    expect(find.text('page 1'), findsNothing);
    expect(find.text('page 2'), findsOneWidget);
    final transform = t.widget<FractionalTranslation>(find.descendant(
        of: find.byType(DesktopPageStack),
        matching: find.byType(FractionalTranslation)));
    expect(transform.translation, Offset.zero);
    expect(t.binding.transientCallbackCount, 0);
  });

  testWidgets('workspace animations retain mounted native-card state',
      (t) async {
    final initialized = <int>[], disposed = <int>[];
    final children = [
      for (int i = 0; i < 2; i++)
        _LifetimeProbe(index: i, initialized: initialized, disposed: disposed)
    ];
    Future<void> show(int page, String effect) async {
      await t.pumpWidget(MaterialApp(
          home: DesktopPageStack(
              page: page, effect: effect, children: children)));
    }

    await show(0, 'slide');
    expect(initialized, [0, 1]);
    for (final effect in ['slide', 'fade', 'none', 'slide']) {
      await show(1, effect);
      await t.pump(const Duration(milliseconds: 60));
      await show(0, effect); // Reverse before the previous motion completes.
      await t.pumpAndSettle();
      expect(initialized, [0, 1],
          reason: '$effect must not recreate map/card state');
      expect(disposed, isEmpty,
          reason: 'finishing motion must not detach native views');
    }
    await t.pumpWidget(const SizedBox.shrink());
    expect(disposed, containsAll([0, 1]));
  });
}

class _LifetimeProbe extends StatefulWidget {
  final int index;
  final List<int> initialized, disposed;
  const _LifetimeProbe(
      {required this.index, required this.initialized, required this.disposed});
  @override
  State<_LifetimeProbe> createState() => _LifetimeProbeState();
}

class _LifetimeProbeState extends State<_LifetimeProbe> {
  @override
  void initState() {
    super.initState();
    widget.initialized.add(widget.index);
  }

  @override
  void dispose() {
    widget.disposed.add(widget.index);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Text('workspace ${widget.index}');
}
