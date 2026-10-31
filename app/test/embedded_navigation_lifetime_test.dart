import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uni_launcher/controller/launcher_controller.dart';
import 'package:uni_launcher/launcher_app.dart';
import 'package:uni_launcher/model/appearance.dart';
import 'package:uni_launcher/theme/design_tokens.dart';
import 'package:uni_launcher/theme/launcher_theme.dart';
import 'package:uni_launcher/widgets/embedded_navigation.dart';
import 'package:uni_launcher/widgets/page_transition.dart';
import 'fake_gateway.dart';

/// Channel-level fake: creating a map must never create an Android PlatformView.
class LiveMapHarness {
  LiveMapHarness(this.t) {
    controller = LauncherController(gateway);
    final messenger = t.binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(host, (call) async {
      if (call.method == 'create') {
        creates.add(Map<String, dynamic>.from(call.arguments as Map));
        return pendingCreate == null
            ? nativeStatus
            : await pendingCreate!.future;
      }
      if (call.method == 'dispose') disposed.add(call.arguments as int);
      return null;
    });
    messenger.setMockMethodCallHandler(map, (call) async {
      if (call.method == 'status') return nativeStatus;
      if (call.method == 'visible') visibility.add(call.arguments as bool);
      if (call.method == 'resize') {
        resizes.add(Map<String, dynamic>.from(call.arguments as Map));
      }
      if (call.method == 'touch') {
        touches.add(Map<String, dynamic>.from(call.arguments as Map));
      }
      return null;
    });
    messenger.setMockMethodCallHandler(SystemChannels.platform_views,
        (call) async {
      platformCalls.add(call.method);
      return null;
    });
    addTearDown(() async {
      await t.pumpWidget(const SizedBox.shrink());
      await t.pump();
      messenger.setMockMethodCallHandler(host, null);
      messenger.setMockMethodCallHandler(map, null);
      messenger.setMockMethodCallHandler(SystemChannels.platform_views, null);
      controller.dispose();
      await gateway.dispose();
    });
  }

  final WidgetTester t;
  final gateway = FakeGateway();
  late final LauncherController controller;
  static const host = MethodChannel('xyz.i4o.uni.launcher/navigation');
  static const map = MethodChannel('xyz.i4o.uni.launcher/map/17');
  final creates = <Map<String, dynamic>>[];
  final resizes = <Map<String, dynamic>>[];
  final touches = <Map<String, dynamic>>[];
  final visibility = <bool>[];
  final disposed = <int>[];
  final platformCalls = <String>[];
  Completer<Map<String, dynamic>>? pendingCreate;
  Map<String, dynamic> nativeStatus = {
    'id': 17,
    'textureId': 71,
    'phase': 'ready',
    'ready': true,
    'width': 600,
    'height': 400,
    'renderMode': 'realtime',
  };

  Widget card({bool active = true, bool moving = false, bool allowed = true}) {
    return EmbeddedContentPolicy(
        enabled: allowed,
        visible: active,
        child: DesktopMotionScope(
            moving: moving,
            child: EmbeddedNavigationCard(
                controller: controller,
                navigation: const {
                  'package': 'test.map',
                  'label': '地图',
                  'canEmbed': true,
                })));
  }

  Future<void> show(
      {bool moving = false,
      bool active = true,
      bool settings = false,
      double width = 600,
      double height = 450,
      bool allowed = true}) async {
    controller.settings = settings;
    await t.pumpWidget(MaterialApp(
        theme: launcherTheme(SurfaceStyle.from(const Appearance(), false)),
        home: Scaffold(
            body: Align(
                alignment: Alignment.topLeft,
                child: SizedBox(
                    width: width,
                    height: height,
                    child: card(
                        active: active, moving: moving, allowed: allowed))))));
    await flush();
  }

  Future<void> flush() async {
    // Loading has an animated spinner; never pumpAndSettle that state.
    for (var i = 0; i < 4; i++) {
      await t.pump();
    }
  }

  Future<void> status(bool ready) async {
    nativeStatus = {
      ...nativeStatus,
      'phase': ready ? 'ready' : 'loading',
      'ready': ready
    };
    await t.binding.defaultBinaryMessenger.handlePlatformMessage(
        map.name,
        const StandardMethodCodec()
            .encodeMethodCall(MethodCall('status', nativeStatus)),
        (_) {});
    await flush();
  }
}

void main() {
  testWidgets(
      'wallpaper settings and theme changes retain the real desktop map subtree',
      (t) async {
    t.view.physicalSize = const Size(1920, 1080);
    t.view.devicePixelRatio = 1;
    addTearDown(() {
      t.view.resetPhysicalSize();
      t.view.resetDevicePixelRatio();
    });
    final h = LiveMapHarness(t);
    h.gateway.state['demo'] = false;
    h.gateway.state['media'] = {'available': false, 'playing': false};
    h.gateway.state['navigation'] = {
      'package': 'test.map',
      'label': '地图',
      'canEmbed': true
    };
    await h.controller.initialize();
    h.controller
        .setAppearance(const Appearance(mode: 'dark', wallpaper: 'graphite'));
    await t.pumpWidget(LauncherApp(controller: h.controller));
    await h.flush();
    expect(h.creates, hasLength(1));
    final texture =
        find.byKey(const ValueKey('map-live-texture'), skipOffstage: false);
    final original = t.element(texture);
    for (final theme in ['classic', 'blueGlass', 'classic']) {
      h.controller.openSettings();
      await h.flush();
      expect(h.disposed, isEmpty,
          reason: 'Settings wallpaper tint must not reparent the desktop');
      expect(t.element(texture), same(original));
      h.controller
          .setAppearance(h.controller.appearance.copyWith(themeStyle: theme));
      await h.flush();
      expect(h.disposed, isEmpty,
          reason: 'Changing background style must retain embedded resources');
      h.controller.setAppearance(
          h.controller.appearance.copyWith(wallpaper: 'gradient'));
      await h.flush();
      expect(h.disposed, isEmpty,
          reason: 'Changing wallpaper must not recreate maps');
      h.controller.setAppearance(
          h.controller.appearance.copyWith(wallpaper: 'graphite'));
      await h.flush();
      h.controller.home();
      await h.flush();
      expect(h.creates, hasLength(1));
      expect(t.element(texture), same(original));
    }
    expect(h.visibility, contains(false));
    expect(h.visibility.last, true);
    expect(t.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));

  testWidgets(
      'one live texture survives loading, motion and real constraint resize',
      (t) async {
    final h = LiveMapHarness(t);
    await h.show();
    expect(h.creates, hasLength(1));
    final input = find.byKey(const ValueKey('map-live-input'));
    final texture = find.byKey(const ValueKey('map-live-texture'));
    final element = t.element(texture);
    final localSize = t.getSize(input);
    final scale = t.view.physicalSize.width / Design.canvasWidth;
    expect(h.creates.single, {
      'width': (localSize.width * scale).round(),
      'scale': 1.0,
      'height': (localSize.height * scale).round(),
    });
    for (final ready in [false, true, false, true]) {
      await h.status(ready);
      expect(t.element(texture), same(element));
      expect(t.widget<Texture>(texture).textureId, 71);
      expect(t.widget<Texture>(texture).freeze, false);
      expect(find.byType(CircularProgressIndicator),
          ready ? findsNothing : findsOneWidget);
      expect(find.byType(Image), findsNothing);
    }
    await h.show(moving: true);
    await h.show();
    expect(h.visibility, [true]);
    expect(h.resizes, isEmpty);
    expect(t.element(texture), same(element));
    await h.show(width: 550);
    expect(h.resizes, hasLength(1));
    final resized = t.getSize(input);
    expect(h.resizes.single['width'], (resized.width * scale).round());
    expect(h.resizes.single['height'], (resized.height * scale).round());
    await h.show(width: 550);
    expect(h.resizes, hasLength(1));
    expect(t.element(texture), same(element));
    expect(h.creates, hasLength(1));
    expect(h.disposed, isEmpty);
    expect(h.platformCalls, isEmpty);
    await t.pumpWidget(const SizedBox.shrink());
    await h.flush();
    expect(h.disposed, [17]);
    expect(t.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));

  testWidgets('card editing defers map resize until the final size is settled',
      (t) async {
    final h = LiveMapHarness(t);
    await h.show();
    h.controller.beginEdit();
    await h.show(width: 550);
    await h.show(width: 500);
    expect(h.resizes, isEmpty);
    h.controller.cancelEdit();
    await h.show(width: 500);
    expect(h.resizes, hasLength(1));
    expect(h.creates, hasLength(1));
    expect(h.disposed, isEmpty);
    expect(t.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));

  testWidgets('map scale toggle sends reduced texture scale only when enabled',
      (t) async {
    final h = LiveMapHarness(t);
    // 开关默认关闭：按 1:1 下发，不缩放。
    await h.show();
    expect(h.creates.single['scale'], 1.0);
    // 开启「嵌入地图缩放」：按 mapTextureScale 降分辨率。
    h.controller.native.value = {
      ...h.controller.native.value,
      'integrationPreferences': {'mapTextureScale': true},
    };
    h.creates.clear();
    h.disposed.clear();
    await h.show();
    expect(h.creates.single['scale'], mapTextureScale);
    expect(h.disposed, [17]);
    expect(t.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));

  testWidgets(
      'normalized multitouch includes lifted pointer and cancels on hide',
      (t) async {
    final h = LiveMapHarness(t);
    await h.show();
    final input = find.byKey(const ValueKey('map-live-input'));
    final rect = t.getRect(input);
    final a = await t.startGesture(
        rect.topLeft + Offset(rect.width * .25, rect.height * .3),
        pointer: 10);
    final b = await t.startGesture(
        rect.topLeft + Offset(rect.width * .75, rect.height * .7),
        pointer: 20);
    await a.moveBy(Offset(rect.width * .1, 0));
    await b.up();
    await a.up();
    await h.flush();
    expect(h.touches.map((v) => v['action']), [0, 5, 2, 6, 1]);
    final down = (h.touches.first['pointers'] as List).single as Map;
    expect(down['x'], closeTo(.25, .001));
    expect(down['y'], closeTo(.3, .001));
    final secondDown = h.touches[1];
    expect(secondDown['actionIndex'], 1);
    expect((secondDown['pointers'] as List).map((p) => p['id']), [0, 1]);
    expect(h.touches[3]['actionIndex'], 1);
    expect(h.touches[3]['pointers'], hasLength(2));
    expect(h.touches.last['pointers'], hasLength(1));
    final c = await t.startGesture(rect.center, pointer: 30);
    await c.moveTo(rect.bottomRight + const Offset(100, 100));
    await h.flush();
    final outside = (h.touches.last['pointers'] as List).single as Map;
    expect(outside['x'], 1.0);
    expect(outside['y'], 1.0);
    await h.show(active: false);
    expect(h.touches.last['action'], 3);
    final count = h.touches.length;
    await c.up();
    await h.flush();
    expect(h.touches, hasLength(count));
    expect(h.visibility.last, false);
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));

  testWidgets(
      'late create is disposed after unmount without creating a platform view',
      (t) async {
    final h = LiveMapHarness(t);
    h.pendingCreate = Completer<Map<String, dynamic>>();
    await h.show();
    expect(h.creates, hasLength(1));
    await t.pumpWidget(const SizedBox.shrink());
    h.pendingCreate!.complete(h.nativeStatus);
    await h.flush();
    expect(h.disposed, [17]);
    expect(h.platformCalls, isEmpty);
    expect(t.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));
}
