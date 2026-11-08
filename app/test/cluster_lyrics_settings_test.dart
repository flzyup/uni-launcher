import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uni_launcher/model/appearance.dart';
import 'package:uni_launcher/model/cluster_layout.dart';
import 'package:uni_launcher/platform/cluster_lyrics.dart';
import 'package:uni_launcher/theme/launcher_theme.dart';
import 'package:uni_launcher/widgets/cluster_lyrics_settings.dart';

class _ApplyCall {
  const _ApplyCall(this.display, this.status);
  final ClusterDisplay? display;
  final ClusterCastStatus status;
}

class _FakeClient extends ClusterLyrics {
  const _FakeClient(this.rows, this.current);
  final List<ClusterDisplay> rows;
  final ClusterCastStatus current;

  static final List<_ApplyCall> calls = <_ApplyCall>[];

  @override
  Future<List<ClusterDisplay>> displays() async => rows;

  @override
  Future<ClusterCastStatus> status() async => current;

  @override
  Future<ClusterCastStatus> apply({
    ClusterDisplay? display,
    double fontSp = 34,
    bool solidBackground = true,
    double xRatio = 0.5,
    double yRatio = 0.62,
    double widthRatio = 0.94,
    int rows = 3,
    int accent = 0xFF7FE3D4,
    String style = 'pill',
    String motion = 'none',
  }) async {
    final next = current.copyWith(
      enabled: display != null,
      displayId: display?.id ?? -1,
      displayName: display?.name ?? '',
      fontSp: fontSp,
      solidBackground: solidBackground,
      xRatio: xRatio,
      yRatio: yRatio,
      widthRatio: widthRatio,
      rows: rows,
      accent: accent,
      style: style,
      motion: motion,
    );
    calls.add(_ApplyCall(display, next));
    return next;
  }
}

const _cluster = ClusterDisplay(
  id: 2,
  name: '仪表',
  label: '仪表  ·  ID 2  ·  1920×720  ·  240 dpi',
  presentation: true,
  width: 1920,
  height: 720,
  densityDpi: 240,
);

Widget _host(Widget child) => MaterialApp(
      theme: launcherTheme(SurfaceStyle.from(const Appearance(), true)),
      home: Scaffold(body: child),
    );

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    _FakeClient.calls.clear();
    // The settings page is a tall scroll column (preview editor + four control blocks). The
    // default 800×600 test surface would push half of it off-screen and every tap would land
    // outside the render tree, so give the tests a phone-tall viewport and scroll to targets.
    binding.platformDispatcher.views.first.physicalSize = const Size(900, 2600);
    binding.platformDispatcher.views.first.devicePixelRatio = 1;
  });

  tearDown(() {
    binding.platformDispatcher.views.first.resetPhysicalSize();
    binding.platformDispatcher.views.first.resetDevicePixelRatio();
  });

  testWidgets('lists what the unit exposes and defaults to off', (tester) async {
    await tester.pumpWidget(_host(const ClusterLyricsSettingsTab(
      client: _FakeClient([_cluster], ClusterCastStatus.unknown),
    )));
    await tester.pumpAndSettle();
    expect(find.text('歌词投到仪表盘'), findsOneWidget);
    expect(find.textContaining('仪表  ·  ID 2'), findsOneWidget);
    expect(find.textContaining('系统标记为副屏'), findsOneWidget);
  });

  testWidgets('an empty display list is stated as the answer, not as an error',
      (tester) async {
    await tester.pumpWidget(_host(const ClusterLyricsSettingsTab(
      client: _FakeClient([], ClusterCastStatus.unknown),
    )));
    await tester.pumpAndSettle();
    expect(find.textContaining('没有向应用暴露任何副屏'), findsOneWidget);
  });

  testWidgets('picking a display applies it immediately', (tester) async {
    await tester.pumpWidget(_host(const ClusterLyricsSettingsTab(
      client: _FakeClient([_cluster], ClusterCastStatus.unknown),
    )));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('cluster-display-2')));
    await tester.pumpAndSettle();
    expect(_FakeClient.calls, hasLength(1));
    expect(_FakeClient.calls.last.display?.id, 2);
    expect(_FakeClient.calls.last.display?.identity, '仪表');
  });

  testWidgets('the switch turns the cast off with no target', (tester) async {
    await tester.pumpWidget(_host(const ClusterLyricsSettingsTab(
      client: _FakeClient([_cluster],
          const ClusterCastStatus(enabled: true, displayId: 2, displayName: '仪表')),
    )));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('cluster-lyrics-switch')));
    await tester.pumpAndSettle();
    expect(_FakeClient.calls, hasLength(1));
    expect(_FakeClient.calls.last.display, isNull);
    expect(_FakeClient.calls.last.status.enabled, isFalse);
  });

  testWidgets('the preview block is where the stored ratio says it is',
      (tester) async {
    await tester.pumpWidget(_host(const ClusterLyricsSettingsTab(
      client: _FakeClient([_cluster],
          const ClusterCastStatus(
              enabled: true,
              displayId: 2,
              displayName: '仪表',
              widthRatio: 0.5,
              xRatio: 0.3,
              yRatio: 0.7)),
    )));
    await tester.pumpAndSettle();
    final screenRect = tester.getRect(find.byKey(const ValueKey('cluster-preview')));
    final block = tester.getRect(find.byKey(const ValueKey('cluster-preview-block')));
    // Centre of the block must sit at the stored fraction of the mock screen, within a
    // pixel or two of rounding. A half-width panel can reach 0.3 at all; the default 94%
    // panel is physically unable to centre that far left, which is why it is clamped.
    expect(block.center.dx - screenRect.left, closeTo(screenRect.width * 0.3, 3));
    expect(block.center.dy - screenRect.top, closeTo(screenRect.height * 0.7, 3));
    expect(block.width, closeTo(screenRect.width * 0.5, 3));
  });

  testWidgets('dragging the preview moves the panel and saves the ratio',
      (tester) async {
    await tester.pumpWidget(_host(const ClusterLyricsSettingsTab(
      client: _FakeClient([_cluster],
          const ClusterCastStatus(enabled: true, displayId: 2, displayName: '仪表')),
    )));
    await tester.pumpAndSettle();
    final rect = tester.getRect(find.byKey(const ValueKey('cluster-preview')));
    final target = Offset(rect.left + rect.width * 0.3, rect.top + rect.height * 0.35);
    await tester.dragFrom(rect.center, target - rect.center);
    await tester.pumpAndSettle();
    expect(_FakeClient.calls, isNotEmpty);
    final saved = _FakeClient.calls.last.status;
    // The drag is clamped so the block stays on screen; 94% wide cannot reach 30% left.
    expect(saved.xRatio, closeTo(0.47, 0.02));
    expect(saved.yRatio, closeTo(0.35, 0.03));
  });

  testWidgets('a tap does not move the panel, only a drag does', (tester) async {
    await tester.pumpWidget(_host(const ClusterLyricsSettingsTab(
      client: _FakeClient([_cluster],
          const ClusterCastStatus(enabled: true, displayId: 2, displayName: '仪表')),
    )));
    await tester.pumpAndSettle();
    final rect = tester.getRect(find.byKey(const ValueKey('cluster-preview')));
    await tester.tapAt(rect.center);
    await tester.pumpAndSettle();
    // Tapping must not be read as placement: a finger poking the mock screen while the user
    // is only looking should not move the lyrics on the cluster.
    expect(_FakeClient.calls, isEmpty);
  });

  testWidgets('rows, width, accent and style each reach the native side',
      (tester) async {
    await tester.pumpWidget(_host(const ClusterLyricsSettingsTab(
      client: _FakeClient([_cluster],
          const ClusterCastStatus(enabled: true, displayId: 2, displayName: '仪表')),
    )));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('cluster-rows-2')));
    await tester.pumpAndSettle();
    expect(_FakeClient.calls.last.status.rows, 2);

    // Width is a slider now: drag the thumb, and the value must only be committed on release.
    final width = find.byKey(const ValueKey('cluster-width-slider'));
    final widthRect = tester.getRect(width);
    await tester.dragFrom(
        widthRect.centerLeft + const Offset(4, 0), Offset(widthRect.width * 0.3, 0));
    await tester.pumpAndSettle();
    final widthRatio = _FakeClient.calls.last.status.widthRatio;
    expect(widthRatio, greaterThan(ClusterLayout.minWidthRatio));
    expect(widthRatio, lessThan(ClusterLayout.maxWidthRatio));

    await tester.tap(find.byKey(const ValueKey('cluster-style-plain')));
    await tester.pumpAndSettle();
    expect(_FakeClient.calls.last.status.style, 'plain');

    await tester.tap(find.byKey(const ValueKey('cluster-accent-ffffc46b')));
    await tester.pumpAndSettle();
    expect(_FakeClient.calls.last.status.accent, 0xFFFFC46B);
  });

  testWidgets('the font slider moves the size and pins it inside the range',
      (tester) async {
    await tester.pumpWidget(_host(const ClusterLyricsSettingsTab(
      client: _FakeClient([_cluster],
          const ClusterCastStatus(
              enabled: true, displayId: 2, displayName: '仪表', fontSp: 34)),
    )));
    await tester.pumpAndSettle();
    final font = find.byKey(const ValueKey('cluster-font-slider'));
    final rect = tester.getRect(font);
    // Drag past the right end: the widget must clamp to MAX, not send 90 sp to the cluster.
    await tester.dragFrom(rect.center, Offset(rect.width, 0));
    await tester.pumpAndSettle();
    expect(_FakeClient.calls.last.status.fontSp,
        closeTo(ClusterLayout.maxFontSp, 1e-9));
    // And back past the left end.
    await tester.dragFrom(rect.center, Offset(-rect.width * 2, 0));
    await tester.pumpAndSettle();
    expect(_FakeClient.calls.last.status.fontSp,
        closeTo(ClusterLayout.minFontSp, 1e-9));
  });

  testWidgets('effects are off by default and can be switched on', (tester) async {
    await tester.pumpWidget(_host(const ClusterLyricsSettingsTab(
      client: _FakeClient([_cluster],
          const ClusterCastStatus(enabled: true, displayId: 2, displayName: '仪表')),
    )));
    await tester.pumpAndSettle();
    // Nothing has been applied yet: the default has to come from the stored status, which is
    // `none` unless a previous choice said otherwise.
    expect(_FakeClient.calls, isEmpty);
    expect(find.textContaining('只在换行的那一刻重绘一次'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('cluster-motion-words')));
    await tester.pumpAndSettle();
    expect(_FakeClient.calls.last.status.motion, ClusterLayout.motionWords);
    expect(find.textContaining('向上淡出'), findsOneWidget);
  });

  testWidgets('the reset button returns the panel to the default placement',
      (tester) async {
    await tester.pumpWidget(_host(const ClusterLyricsSettingsTab(
      client: _FakeClient([_cluster],
          const ClusterCastStatus(
              enabled: true, displayId: 2, displayName: '仪表', xRatio: 0.1, yRatio: 0.1)),
    )));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('cluster-position-reset')));
    await tester.pumpAndSettle();
    final saved = _FakeClient.calls.last.status;
    expect(saved.xRatio, closeTo(ClusterLayout.defaultX, 1e-9));
    expect(saved.yRatio, closeTo(ClusterLayout.defaultY, 1e-9));
    expect(saved.widthRatio, closeTo(ClusterLayout.defaultWidth, 1e-9));
  });

  testWidgets('the header says whether lyrics actually reached the panel',
      (tester) async {
    await tester.pumpWidget(_host(const ClusterLyricsSettingsTab(
      client: _FakeClient([_cluster],
          const ClusterCastStatus(
              enabled: true,
              displayId: 2,
              displayName: '仪表',
              track: '底牌',
              lyricLines: 38,
              lyricLabel: '网易云音乐')),
    )));
    await tester.pumpAndSettle();
    expect(find.textContaining('38 行'), findsOneWidget);
    expect(find.textContaining('网易云音乐'), findsOneWidget);
  });
}
