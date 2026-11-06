import 'dart:convert';
import 'package:flutter/services.dart';

class PickedWallpaper {
  final String path;
  final double luminance;
  const PickedWallpaper(this.path, this.luminance);
}

abstract class NativeGateway {
  Future<Map<String, dynamic>> bootstrap();

  /// 首帧快速通道：只要外观与布局（偏好级，不构造任何适配器快照）。
  ///
  /// 拿不到就返回 null，调用方按原来的单段引导继续；这条通道的存在只是让
  /// 「第一帧」不必等整份 bootstrap。
  Future<Map<String, dynamic>?> prelude() async => null;
  Stream<Map<String, dynamic>> get events;
  Future<void> action(String action,
      {String? value, String? zone, bool? enabled});
  Future<void> save(String value);
  void onHome(void Function() callback);
  Future<PickedWallpaper?> pickWallpaper() async => null;
  Future<void> setDesktopPage(int page) async {}
}

class AndroidGateway implements NativeGateway {
  static const methods = MethodChannel('xyz.i4o.uni.launcher/platform');
  static const eventChannel = EventChannel('xyz.i4o.uni.launcher/events');
  void Function()? _home, _settings, _rebound;
  void onOpenSettings(void Function() callback) {
    _settings = callback;
  }

  /// 引擎被新窗口接管（Activity 重建）时回调：本进程的 Dart 树还活着，但
  /// 平台视图归旧窗口所有、已经被关掉，必须整体重建。
  void onHostRebound(void Function() callback) {
    _rebound = callback;
  }

  @override
  Future<Map<String, dynamic>> bootstrap() async => Map<String, dynamic>.from(
      jsonDecode(await methods.invokeMethod<String>('snapshot') ?? '{}'));
  @override
  Future<Map<String, dynamic>?> prelude() async {
    try {
      final raw = await methods.invokeMethod<Object?>('prelude');
      final decoded = raw is String ? jsonDecode(raw) : raw;
      if (decoded is! Map) return null;
      return Map<String, dynamic>.from(decoded);
    } catch (_) {
      // 快通道是「更好」而不是「必须」：任何异常都退回单段引导。
      return null;
    }
  }
  @override
  Stream<Map<String, dynamic>> get events => eventChannel
      .receiveBroadcastStream()
      .map((value) => Map<String, dynamic>.from(jsonDecode(value as String)));
  @override
  Future<void> action(String action,
      {String? value, String? zone, bool? enabled}) async {
    await methods.invokeMethod(
        'action',
        jsonEncode({
          'action': action,
          if (value != null) 'value': value,
          if (zone != null) 'zone': zone,
          if (enabled != null) 'enabled': enabled
        }));
  }

  @override
  Future<void> save(String value) async {
    if (await methods.invokeMethod<bool>('saveDesign', value) != true)
      throw StateError('保存未完成');
  }

  @override
  Future<PickedWallpaper?> pickWallpaper() async {
    final raw = await methods.invokeMapMethod<String, dynamic>('pickWallpaper');
    final path = raw?['path'];
    final luminance = raw?['luminance'];
    if (path is! String || path.isEmpty || luminance is! num) return null;
    return PickedWallpaper(path, luminance.toDouble().clamp(0, 1));
  }

  @override
  Future<void> setDesktopPage(int page) =>
      methods.invokeMethod<void>('desktopPage', page);

  @override
  void onHome(void Function() callback) {
    _home = callback;
    methods.setMethodCallHandler((call) async {
      if (call.method == 'home') _home?.call();
      if (call.method == 'open-settings') _settings?.call();
      if (call.method == 'rehost') _rebound?.call();
    });
  }
}
