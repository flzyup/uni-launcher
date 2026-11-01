import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uni_launcher/controller/launcher_controller.dart';
import 'package:uni_launcher/model/appearance.dart';
import 'package:uni_launcher/theme/launcher_theme.dart';
import 'package:uni_launcher/widgets/media_artwork.dart';
import 'fake_gateway.dart';

const pixel =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAACklEQVR4nGMAAQAABQABDQottAAAAABJRU5ErkJggg==';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
      'repeated snapshots retain only current buffers and reuse unchanged icons',
      () async {
    final gateway = FakeGateway();
    final controller = LauncherController(gateway);
    await controller.initialize();
    addTearDown(() async {
      controller.dispose();
      await gateway.dispose();
    });
    Uint8List? icon;
    for (var i = 0; i < 200; i++) {
      final raw = base64Encode(List.generate(2048, (n) => (n + i) % 256));
      gateway.stream.add({
        'apps': [
          {'package': 'app', 'icon': pixel}
        ],
        'recentTasks': [
          {'id': 1, 'icon': pixel, 'snapshot': raw}
        ]
      });
      final app = (controller.native.value['apps'] as List).single as Map;
      final task =
          (controller.native.value['recentTasks'] as List).single as Map;
      if (icon != null) expect(identical(app['iconBytes'], icon), isTrue);
      icon = app['iconBytes'] as Uint8List;
      expect(task['snapshotBytes'], base64Decode(raw));
      expect(controller.imageCacheStats['iconCount'], 1);
      expect(controller.imageCacheStats['recentCount'], 2);
      expect(
          controller.imageCacheStats['recentBytes'],
          raw.length * 2 +
              2048 +
              pixel.length * 2 +
              base64Decode(pixel).length);
    }
    // Budgets are sized for the 2GB head units: icons ship as WebP now, so the
    // decoded-picture cache needs far less room to stay warm.
    expect(
        PaintingBinding.instance.imageCache.maximumSizeBytes, 10 * 1024 * 1024);
    expect(PaintingBinding.instance.imageCache.maximumSize, 64);
  });

  test(
      'entry and byte budgets reject excess and malformed data before retention',
      () async {
    final gateway = FakeGateway();
    final controller = LauncherController(gateway);
    await controller.initialize();
    addTearDown(() async {
      controller.dispose();
      await gateway.dispose();
    });
    gateway.stream.add({
      'apps': [
        for (var i = 0; i < 300; i++)
          {
            'icon': base64Encode([i ~/ 256, i % 256])
          }
      ],
      'recentTasks': [
        for (var i = 0; i < 80; i++)
          {
            'snapshot': base64Encode([i])
          }
      ]
    });
    expect(controller.imageCacheStats['iconCount'], 256);
    expect(controller.imageCacheStats['recentCount'], 48);
    final large = base64Encode(Uint8List(400000));
    gateway.stream.add({
      'apps': [
        for (var i = 0; i < 20; i++) {'icon': 'data:image/$i;base64,$large'}
      ],
      'recentTasks': [
        for (var i = 0; i < 20; i++) {'snapshot': 'data:image/$i;base64,$large'}
      ]
    });
    expect(controller.imageCacheStats['iconBytes'],
        lessThanOrEqualTo(4 * 1024 * 1024));
    expect(controller.imageCacheStats['recentBytes'],
        lessThanOrEqualTo(12 * 1024 * 1024));
    expect(controller.imageCacheStats['iconCount'], inExclusiveRange(0, 20));
    expect(controller.imageCacheStats['recentCount'], inExclusiveRange(0, 20));
    expect((controller.native.value['apps'] as List).first['iconBytes'],
        base64Decode(large));
    gateway.stream.add({
      'apps': [
        {'icon': '!', 'iconBytes': Uint8List(4)}
      ],
      'recentTasks': [
        {'snapshot': 'A' * (7 * 1024 * 1024)}
      ]
    });
    expect(controller.imageCacheStats.values, everyElement(0));
    expect(
        (controller.native.value['apps'] as List)
            .single
            .containsKey('iconBytes'),
        false);
  });

  test(
      'closing or omitting recents purges cache; pressure preserves visible data',
      () async {
    final gateway = FakeGateway();
    final controller = LauncherController(gateway);
    await controller.initialize();
    final open = <String, dynamic>{
      'globalDock': {'panel': 'recents'},
      'recentTasks': [
        {'snapshot': pixel}
      ]
    };
    gateway.stream.add(open);
    final current = (controller.native.value['recentTasks'] as List)
        .single['snapshotBytes'];
    WidgetsBinding.instance.handleMemoryPressure();
    expect(controller.imageCacheStats.values, everyElement(0));
    expect(
        identical(
            (controller.native.value['recentTasks'] as List)
                .single['snapshotBytes'],
            current),
        true);
    gateway.stream.add(open);
    expect(controller.imageCacheStats['recentCount'], 1);
    expect(
        identical(
            (controller.native.value['recentTasks'] as List)
                .single['snapshotBytes'],
            current),
        true,
        reason: 'the event after pressure reuses the still-visible buffer');
    gateway.stream.add({
      ...open,
      'globalDock': {'panel': ''}
    });
    expect(controller.imageCacheStats['recentCount'], 0);
    expect(controller.native.value['recentTasks'], isEmpty);
    gateway.stream.add(open);
    gateway.stream.add({});
    expect(controller.imageCacheStats.values, everyElement(0));
    gateway.stream.add(open);
    controller.dispose();
    WidgetsBinding.instance.handleMemoryPressure();
    expect(controller.imageCacheStats.values, everyElement(0));
    await gateway.dispose();
  });

  test('telemetry-only packets keep the payloads they omit', () async {
    final gateway = FakeGateway();
    final controller = LauncherController(gateway);
    await controller.initialize();
    addTearDown(() async {
      controller.dispose();
      await gateway.dispose();
    });
    gateway.stream.add({
      'apps': [
        {'package': 'app', 'icon': pixel}
      ],
      'recentTasks': [
        {'id': 1, 'snapshot': pixel}
      ],
      'media': {'title': 'A', 'artwork': pixel, 'lyrics': '[00:01.00]one'},
      'appNames': {'app': 'My player'},
      'savedDesign': '{"preferences":{}}'
    });
    final icon = (controller.native.value['apps'] as List).single['iconBytes'];
    expect(controller.imageCacheStats['iconCount'], 1);
    expect(controller.imageCacheStats['recentCount'], 1);
    // Android sends icons, artwork, lyrics, names and design once, then streams
    // telemetry without them; the retained copy must survive untouched.
    gateway.stream
        .add({'partial': true, 'demo': true, 'media': {'title': 'B'}});
    final state = controller.native.value;
    expect((state['apps'] as List).single['iconBytes'], same(icon));
    expect((state['recentTasks'] as List).single['snapshotBytes'],
        base64Decode(pixel));
    expect((state['media'] as Map)['title'], 'B');
    expect((state['media'] as Map)['artwork'], pixel);
    expect((state['media'] as Map)['lyrics'], '[00:01.00]one');
    expect(state['appNames'], {'app': 'My player'});
    expect(state['savedDesign'], '{"preferences":{}}');
    expect(state.containsKey('partial'), false);
    expect(controller.imageCacheStats['iconCount'], 1,
        reason: 'a packet without icons must not evict the visible ones');
    expect(controller.imageCacheStats['recentCount'], 1);
    expect(controller.appName({'package': 'app'}), 'My player');
    // A full packet still replaces everything, including retiring old images.
    gateway.stream.add({
      'apps': [
        {'package': 'other', 'icon': pixel}
      ]
    });
    expect(controller.imageCacheStats['recentCount'], 0);
  });

  test('cache changes preserve persisted app renames', () async {
    final gateway = FakeGateway();
    final controller = LauncherController(gateway);
    await controller.initialize();
    await controller.renameApp('app', 'My player');
    controller.trimMemory();
    gateway.stream.add({
      'apps': [
        {'package': 'app', 'icon': pixel}
      ]
    });
    expect(controller.appName({'package': 'app', 'label': 'Original'}),
        'My player');
    expect(jsonDecode(gateway.saved!)['appNames']['app'], 'My player');
    controller.dispose();
    final restored = LauncherController(gateway);
    gateway.state['savedDesign'] = gateway.saved;
    await restored.initialize();
    expect(restored.appName({'package': 'app'}), 'My player');
    restored.dispose();
    await gateway.dispose();
  });

  testWidgets('retired task snapshots leave Flutter ImageCache',
      (tester) async {
    final gateway = FakeGateway();
    final controller = LauncherController(gateway);
    await controller.initialize();
    for (var i = 0; i < 30; i++) {
      gateway.stream.add({
        'recentTasks': [
          {
            'snapshot': base64Encode([...base64Decode(pixel), i])
          }
        ]
      });
      final bytes = (controller.native.value['recentTasks'] as List)
          .single['snapshotBytes'] as Uint8List;
      await tester.pumpWidget(Directionality(
          textDirection: TextDirection.ltr,
          child: Image.memory(bytes, gaplessPlayback: true)));
      await tester.pumpAndSettle();
      expect(PaintingBinding.instance.imageCache.currentSize,
          lessThanOrEqualTo(1));
      expect(controller.imageCacheStats['recentCount'], 1);
      expect(tester.takeException(), isNull);
    }
    final last = tester.widget<Image>(find.byType(Image)).image;
    gateway.stream.add({});
    await tester.pumpWidget(const SizedBox.shrink());
    expect(PaintingBinding.instance.imageCache.statusForKey(last).keepAlive,
        false);
    controller.dispose();
    await gateway.dispose();
  });

  testWidgets(
      'artwork reuses current provider and evicts retired and disposed images',
      (tester) async {
    Future<void> show(String raw) async {
      await tester.pumpWidget(MaterialApp(
        theme: launcherTheme(SurfaceStyle.from(const Appearance(), true)),
        home: MediaArtwork(media: {'artwork': raw}, demo: false),
      ));
      await tester.pumpAndSettle();
    }

    await show(pixel);
    final first = tester.widget<Image>(find.byType(Image)).image as MemoryImage;
    await show(pixel);
    expect(tester.widget<Image>(find.byType(Image)).image, first);
    expect(tester.widget<Image>(find.byType(Image)).gaplessPlayback, true);
    // Trailing bytes vary the encoded payload while preserving the valid PNG.
    for (var i = 0; i < 20; i++) {
      final previous =
          tester.widget<Image>(find.byType(Image)).image as MemoryImage;
      await show(base64Encode([...base64Decode(pixel), i]));
      expect(
          PaintingBinding.instance.imageCache.statusForKey(previous).keepAlive,
          false);
      expect(PaintingBinding.instance.imageCache.currentSize,
          lessThanOrEqualTo(1));
      expect(tester.takeException(), isNull);
    }
    final last = tester.widget<Image>(find.byType(Image)).image;
    await tester.pumpWidget(const SizedBox.shrink());
    expect(PaintingBinding.instance.imageCache.statusForKey(last).keepAlive,
        false);
    await show('invalid');
    expect(find.byType(Image), findsNothing);
    await show('A' * 1000000);
    expect(find.byType(Image), findsNothing);
    await show('');
    expect(find.byType(Image), findsNothing);
  });
}
