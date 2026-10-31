import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../controller/launcher_controller.dart';
import '../theme/launcher_theme.dart';
import '../theme/design_tokens.dart';
import 'glass_surface.dart';
import 'uni_icon.dart';
import 'navigation_app_picker.dart';

/// Desktop preview must never start a second map instance.
class EmbeddedContentPolicy extends InheritedWidget {
  final bool enabled;
  final bool visible;
  const EmbeddedContentPolicy(
      {super.key,
      required this.enabled,
      this.visible = true,
      required super.child});
  static bool allowed(BuildContext c) =>
      c.dependOnInheritedWidgetOfExactType<EmbeddedContentPolicy>()?.enabled ??
      true;
  static bool visibleOf(BuildContext c) =>
      c.dependOnInheritedWidgetOfExactType<EmbeddedContentPolicy>()?.visible ??
      true;
  @override
  bool updateShouldNotify(EmbeddedContentPolicy old) =>
      old.enabled != enabled || old.visible != visible;
}

/// 地图纹理尺寸相对卡片像素的缩放（「嵌入地图缩放」开关开启时生效）。
/// 导航 App 的 CPU 基本正比于它要填充的像素数，降分辨率省下的 CPU 直接变成桌面翻页的余量。
/// 0.875x 是「保持 dp 尺寸不变 + 不落入 ldpi 资源桶」的最大值：高德界面既不重排，
/// 固定像素的按钮也几乎不会被放大，仅画面轻微变软（填充量降到 77%）。
const double mapTextureScale = 0.875;

class EmbeddedNavigationCard extends StatefulWidget {
  final LauncherController controller;
  final Map<String, dynamic> navigation;
  const EmbeddedNavigationCard(
      {super.key, required this.controller, required this.navigation});
  @override
  State<EmbeddedNavigationCard> createState() => _EmbeddedNavigationCardState();
}

class _EmbeddedNavigationCardState extends State<EmbeddedNavigationCard> {
  static const host = MethodChannel('xyz.i4o.uni.launcher/navigation');
  MethodChannel? channel;
  int? nativeId, textureId;
  int generation = 0;
  bool desiredVisible = false;
  bool? sentVisible;
  bool scheduled = false, syncing = false;
  Size? desiredSize, sentSize;
  double? sentScale;
  Map<String, dynamic> status = {};
  final Map<int, Offset> pointers = {};
  final Map<int, int> pointerIds = {};
  Future<void> cleanup = Future<void>.value();
  String get package => '${widget.navigation['package'] ?? ''}';

  /// 设置「嵌入地图缩放」关闭时按 1:1 渲染，开启时用 [mapTextureScale] 降分辨率。
  double get textureScale {
    final prefs = widget.controller.native.value['integrationPreferences'];
    return (prefs is Map && prefs['mapTextureScale'] == true)
        ? mapTextureScale
        : 1.0;
  }

  void releaseNative() {
    generation++;
    cancelTouches();
    final id = nativeId;
    channel?.setMethodCallHandler(null);
    channel = null;
    nativeId = textureId = null;
    sentVisible = null;
    sentSize = null;
    sentScale = null;
    status = {};
    if (id != null) {
      cleanup = cleanup
          .then((_) => host.invokeMethod<void>('dispose', id))
          .catchError((Object _) {});
    }
  }

  @override
  void didUpdateWidget(EmbeddedNavigationCard old) {
    super.didUpdateWidget(old);
    if ('${old.navigation['package'] ?? ''}' != package ||
        old.navigation['canEmbed'] != widget.navigation['canEmbed']) {
      releaseNative();
    }
  }

  @override
  void dispose() {
    releaseNative();
    super.dispose();
  }

  void scheduleSync() {
    if (scheduled || syncing) return;
    scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      scheduled = false;
      if (mounted) syncNative();
    });
  }

  /// 逻辑尺寸原样下发，纹理缩放交给原生同时缩像素与密度——导航 App 看到的 dp
  /// 尺寸不变，所以它自己的界面不会重排，只是我们把位图轻微放大。
  Map<String, dynamic> dimensions(Size size) => {
        'width': size.width.toInt(),
        'height': size.height.toInt(),
        'scale': textureScale,
      };

  Future<void> syncNative() async {
    if (syncing) return;
    syncing = true;
    // 缩放开关变了：原生端在 create 时才读取 scale，必须整体重建实时地图。
    if (channel != null && sentScale != null && sentScale != textureScale) {
      releaseNative();
    }
    final epoch = generation;
    try {
      await cleanup;
      if (!mounted || epoch != generation) return;
      if (!desiredVisible || widget.controller.editing) cancelTouches();
      if (channel == null) {
        final size = desiredSize;
        if (!desiredVisible || size == null || status['phase'] == 'failed')
          return;
        final result = await host.invokeMapMethod<String, dynamic>(
            'create', dimensions(size));
        if (result == null || result['id'] is! num) {
          throw StateError('Missing navigation id');
        }
        final id = (result['id'] as num).toInt();
        if (!mounted || epoch != generation) {
          await host.invokeMethod<void>('dispose', id);
          return;
        }
        nativeId = id;
        sentSize = size;
        sentScale = textureScale;
        final current = MethodChannel('xyz.i4o.uni.launcher/map/$id');
        channel = current;
        updateStatus(result);
        int events = 0;
        current.setMethodCallHandler((call) async {
          if (mounted &&
              channel == current &&
              call.method == 'status' &&
              call.arguments is Map) {
            events++;
            updateStatus(Map<String, dynamic>.from(call.arguments));
          }
        });
        final initial =
            await current.invokeMapMethod<String, dynamic>('status');
        if (!mounted || channel != current) return;
        if (initial != null && events == 0) updateStatus(initial);
      }
      final current = channel;
      if (current == null || epoch != generation) return;
      final size = desiredSize;
      // During card editing the grid emits a series of transient sizes.
      // Keep the same live texture and resize the virtual display only once
      // after editing ends, avoiding repeated relayouts inside navigation.
      if (desiredVisible &&
          !widget.controller.editing &&
          size != null &&
          size != sentSize) {
        await current.invokeMethod<void>('resize', dimensions(size));
        if (!mounted || channel != current) return;
        sentSize = size;
      }
      final visible = desiredVisible;
      if (sentVisible != visible) {
        await current.invokeMethod<void>('visible', visible);
        if (!mounted || channel != current) return;
        sentVisible = visible;
      }
    } catch (error) {
      if (mounted && epoch == generation) {
        updateStatus({'phase': 'failed', 'ready': false, 'reason': '地图连接已断开'});
      }
    } finally {
      syncing = false;
      if (mounted &&
          status['phase'] != 'failed' &&
          (epoch != generation ||
              (channel != null &&
                  (sentVisible != desiredVisible ||
                      (desiredVisible &&
                          !widget.controller.editing &&
                          sentSize != desiredSize))))) {
        scheduleSync();
        WidgetsBinding.instance.ensureVisualUpdate();
      }
    }
  }

  void updateStatus(Map<String, dynamic> value) {
    final nextTexture = value['textureId'];
    if (mapEquals(status, value) &&
        (nextTexture is! num || textureId == nextTexture.toInt())) return;
    setState(() {
      status = value;
      if (nextTexture is num) textureId = nextTexture.toInt();
    });
  }

  void sendTouch(int action, int index) {
    final current = channel;
    if (current == null || pointers.isEmpty) return;
    current.invokeMethod<void>('touch', {
      'action': action,
      'actionIndex': index,
      'pointers': [
        for (final entry in pointers.entries)
          {
            'id': pointerIds[entry.key],
            'x': entry.value.dx,
            'y': entry.value.dy
          }
      ],
    }).catchError((Object _) {});
  }

  void cancelTouches() {
    if (pointers.isNotEmpty) sendTouch(3, 0);
    pointers.clear();
    pointerIds.clear();
  }

  void touch(PointerEvent event, Size size, int action) {
    if (!desiredVisible ||
        widget.controller.editing ||
        channel == null ||
        size.isEmpty) return;
    final key = event.pointer;
    if (action == 0) {
      if (pointers.containsKey(key) || pointers.length >= 10) return;
      int id = 0;
      while (pointerIds.containsValue(id)) {
        id++;
      }
      pointerIds[key] = id;
    } else if (!pointers.containsKey(key)) {
      return;
    }
    pointers[key] = Offset(
        (event.localPosition.dx / size.width).clamp(0.0, 1.0).toDouble(),
        (event.localPosition.dy / size.height).clamp(0.0, 1.0).toDouble());
    final index = pointers.keys.toList().indexOf(key);
    if (action == 3) {
      cancelTouches();
      return;
    }
    sendTouch(
        pointers.length > 1 && action == 0
            ? 5
            : pointers.length > 1 && action == 1
                ? 6
                : action,
        index);
    if (action == 1) {
      pointers.remove(key);
      pointerIds.remove(key);
    }
  }

  Widget liveMap(BoxConstraints constraints) {
    final size = constraints.biggest;
    final scale = View.of(context).physicalSize.width / Design.canvasWidth;
    if (size.isFinite && !size.isEmpty && scale > 0) {
      desiredSize = Size((size.width * scale).round().clamp(1, 1920).toDouble(),
          (size.height * scale).round().clamp(1, 1080).toDouble());
      scheduleSync();
    }
    return RawGestureDetector(
      gestures: widget.controller.editing
          ? <Type, GestureRecognizerFactory>{}
          : <Type, GestureRecognizerFactory>{
              EagerGestureRecognizer:
                  GestureRecognizerFactoryWithHandlers<EagerGestureRecognizer>(
                () => EagerGestureRecognizer(),
                (instance) {},
              ),
            },
      child: Listener(
        key: const ValueKey('map-live-input'),
        behavior: HitTestBehavior.opaque,
        onPointerDown: (e) => touch(e, size, 0),
        onPointerMove: (e) => touch(e, size, 2),
        onPointerUp: (e) => touch(e, size, 1),
        onPointerCancel: (e) => touch(e, size, 3),
        child: Stack(fit: StackFit.expand, children: [
          if (textureId != null)
            Texture(
                key: const ValueKey('map-live-texture'), textureId: textureId!),
          if (status['ready'] != true)
            const Positioned(
                right: 12,
                top: 12,
                child: IgnorePointer(
                    child: SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2)))),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = SurfaceStyle.of(context), c = widget.controller;
    final displayName = c.appName(
        {'package': package, 'label': widget.navigation['label'] ?? '高德地图'});
    final allowed = EmbeddedContentPolicy.allowed(context);
    final canEmbed = widget.navigation['canEmbed'] == true &&
        allowed &&
        !kIsWeb &&
        defaultTargetPlatform == TargetPlatform.android;
    desiredVisible = canEmbed &&
        EmbeddedContentPolicy.visibleOf(context) &&
        !c.settings &&
        (ModalRoute.of(context)?.isCurrent ?? true);
    scheduleSync();
    final failed =
        status['phase'] == 'failed' || status['phase'] == 'unavailable';
    return Column(children: [
      Padding(
          padding: EdgeInsets.symmetric(
              horizontal: Design.px(24), vertical: Design.px(14)),
          child: Row(children: [
            UniIcon('nav', color: s.accent, size: Design.px(25)),
            SizedBox(width: Design.px(12)),
            Expanded(
                child: InkWell(
                    key: const ValueKey('nav-title-open'),
                    onTap: () => c.command('launch-navigation'),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Flexible(
                          child: Text(displayName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: Design.px(23)))),
                    ]))),
            IconAction(
                key: const ValueKey('nav-app-picker'),
                icon: Icons.swap_horiz,
                label: '选择导航应用',
                size: Design.px(38),
                onTap: () => showNavigationPicker(context, c)),
            IconAction(
                icon: Icons.open_in_full,
                label: '全屏打开导航',
                size: Design.px(38),
                onTap: () => c.command('launch-navigation')),
          ])),
      Expanded(
          child: canEmbed && (!failed || textureId != null)
              ? LayoutBuilder(
                  builder: (context, constraints) => liveMap(constraints))
              : Center(
                  child: Padding(
                      padding: EdgeInsets.all(Design.px(30)),
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        UniIcon('nav', size: Design.px(60), color: s.accent),
                        SizedBox(height: Design.px(20)),
                        Text(
                            !allowed
                                ? '地图卡片预览'
                                : (!canEmbed
                                        ? widget.navigation['reason']
                                            ?.toString()
                                        : status['reason']?.toString()) ??
                                    '等待导航应用',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                fontSize: Design.px(23), color: s.muted)),
                        SizedBox(height: Design.px(24)),
                        if (allowed)
                          FilledButton(
                              onPressed: () => c.command('launch-navigation'),
                              child: const Text('全屏打开导航')),
                        if (failed && allowed)
                          TextButton(
                              onPressed: () => setState(releaseNative),
                              child: const Text('重新尝试嵌入')),
                      ]))))
    ]);
  }
}
