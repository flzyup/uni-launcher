import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uni_launcher/platform/cluster_lyrics.dart';

/// The cast control surface: a channel in, configuration out. The native side owns the
/// window on the other display; this only verifies the contract is carried faithfully.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('xyz.i4o.uni.launcher/platform');
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final calls = <MethodCall>[];

  setUp(() {
    calls.clear();
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      switch (call.method) {
        case 'clusterLyricsDisplays':
          return <Object>[
            <String, Object>{
              'id': 0,
              'name': '内置屏幕',
              'label': '内置屏幕  ·  ID 0',
              'presentation': false,
              'width': 1920,
              'height': 720,
              'densityDpi': 240,
            },
            <String, Object>{
              'id': 2,
              'name': '仪表',
              'label': '仪表  ·  ID 2  ·  1920×720  ·  240 dpi',
              'presentation': true,
              'width': 1920,
              'height': 720,
              'densityDpi': 240,
            },
          ];
        case 'clusterLyricsStatus':
          return <String, Object>{
            'enabled': true,
            'displayId': 2,
            'displayName': '仪表',
            'fontSp': 26.0,
            'solidBackground': true,
            'xRatio': 0.34,
            'yRatio': 0.72,
            'widthRatio': 0.86,
            'rows': 3,
            'accent': 0xFF8CC8FF,
            'style': 'glow',
            'report': '已投射 · 仪表 · ID 2',
            'track': '底牌',
            'artist': '框框',
            'lyricLines': 38,
            'lyricLabel': '网易云音乐',
            'playing': true,
          };
        case 'clusterLyricsApply':
          final args = Map<Object?, Object?>.from(call.arguments as Map);
          return <String, Object>{
            'enabled': args['enabled'] == true,
            'displayId': args['displayId'] as int,
            'displayName': '${args['displayName']}',
            'fontSp': (args['fontSp'] as num).toDouble(),
            'solidBackground': args['solidBackground'] == true,
            'report': '已投射 · 仪表 · ID 2',
          };
      }
      return null;
    });
  });

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('displays() carries id, name and the presentation flag', () async {
    final rows = await const ClusterLyrics().displays();
    expect(rows, hasLength(2));
    expect(rows.first.id, 0);
    expect(rows.first.presentation, isFalse);
    expect(rows.last.identity, '仪表');
    expect(rows.last.presentation, isTrue);
    expect(rows.last.width, 1920);
  });

  test('status() surfaces the native report, which is how a failed attach is explained',
      () async {
    final status = await const ClusterLyrics().status();
    expect(status.enabled, isTrue);
    expect(status.displayId, 2);
    expect(status.report, contains('已投射'));
  });

  test('status() carries placement, style and what the cast is being fed', () async {
    final status = await const ClusterLyrics().status();
    expect(status.xRatio, closeTo(0.34, 1e-9));
    expect(status.yRatio, closeTo(0.72, 1e-9));
    expect(status.widthRatio, closeTo(0.86, 1e-9));
    expect(status.rows, 3);
    expect(status.accent, 0xFF8CC8FF);
    expect(status.style, 'glow');
    expect(status.lyricLines, 38);
    expect(status.lyricSummary, contains('网易云音乐'));
    expect(status.lyricSummary, contains('38'));
  });

  test('apply() carries the whole placement so the preview and the panel agree',
      () async {
    const client = ClusterLyrics();
    await client.apply(
      display: const ClusterDisplay(id: 2, name: '仪表', label: '仪表  ·  ID 2'),
      fontSp: 44,
      xRatio: 0.22,
      yRatio: 0.31,
      widthRatio: 0.7,
      rows: 2,
      accent: 0xFFFFC46B,
      style: 'plain',
      solidBackground: false,
    );
    final sent = calls.last.arguments as Map;
    expect(sent['xRatio'], 0.22);
    expect(sent['yRatio'], 0.31);
    expect(sent['widthRatio'], 0.7);
    expect(sent['rows'], 2);
    expect(sent['accent'], 0xFFFFC46B);
    expect(sent['style'], 'plain');
    expect(sent['fontSp'], 44);
    expect(sent['solidBackground'], isFalse);
  });

  test('apply() sends the name + id pair and turns the cast off with a null display',
      () async {
    const client = ClusterLyrics();
    final on = await client.apply(
      display: const ClusterDisplay(id: 2, name: '仪表', label: '仪表  ·  ID 2'),
      fontSp: 30,
      solidBackground: false,
    );
    expect(on.enabled, isTrue);
    final sent = calls.last.arguments as Map;
    expect(sent['enabled'], isTrue);
    expect(sent['displayId'], 2);
    expect(sent['displayName'], '仪表');
    expect(sent['fontSp'], 30);
    expect(sent['solidBackground'], isFalse);

    final off = await client.apply();
    expect(off.enabled, isFalse);
    expect((calls.last.arguments as Map)['enabled'], isFalse);
    expect((calls.last.arguments as Map)['displayId'], -1);
  });

  test('a missing native handler degrades to empty instead of throwing', () async {
    messenger.setMockMethodCallHandler(channel, null);
    expect(await const ClusterLyrics().displays(), isEmpty);
    expect((await const ClusterLyrics().status()).enabled, isFalse);
  });
}
