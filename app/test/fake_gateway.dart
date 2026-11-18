import 'dart:async';
import 'package:uni_launcher/platform/native_gateway.dart';

class FakeGateway implements NativeGateway {
  final stream = StreamController<Map<String, dynamic>>.broadcast(sync: true);
  Map<String, dynamic> state = {
    'demo': true,
    'dark': true,
    'hideNavigation': false,
    'globalNavigationGranted': false,
    'globalDock': {'enabled': false, 'allowed': true},
    'systemNavigationGranted': true,
    'systemNavigationHidden': false,
    'apps': <dynamic>[],
    'climate': {
      'left': 22.5,
      'right': 22.5,
      'fan': 3,
      'driverHeat': 0,
      'driverVent': 0,
      'passengerHeat': 0,
      'auto': true,
      'ac': true,
      'sync': false,
      'power': true
    },
    'media': {
      'title': '午夜立交',
      'artist': '昼夜电台',
      'available': true,
      'playing': true
    },
    'vehicle': {'writable': false, 'reason': '模拟器没有原车框架'},
    'savedDesign': ''
  };
  String? saved;
  PickedWallpaper? wallpaper;
  final List<Map<String, dynamic>> commands = [];
  @override
  Future<Map<String, dynamic>> bootstrap() async => Map.of(state);
  @override
  Future<Map<String, dynamic>?> prelude() async => {
        'savedDesign': state['savedDesign'],
        'appNames': state['appNames'],
        'lastDesktopPage': state['lastDesktopPage'],
        'dark': state['dark']
      };
  @override
  Stream<Map<String, dynamic>> get events => stream.stream;
  @override
  Future<void> action(String action,
      {String? value, String? zone, bool? enabled}) async {
    commands.add(
        {'action': action, 'value': value, 'zone': zone, 'enabled': enabled});
    if (action == 'hide-navigation')
      state = {...state, 'hideNavigation': enabled};
    if (action == 'system-navigation-hidden')
      state = {...state, 'systemNavigationHidden': enabled};
    if (action == 'global-dock')
      state = {
        ...state,
        'globalDock': {'enabled': enabled, 'allowed': true}
      };
    if (action == 'demo-mode') state = {...state, 'demo': enabled};
    if (action == 'simulation-mode')
      state = {
        ...state,
        'simulationMode': value,
        'demo': value != 'live',
        'mediaDemo': value == 'demo',
      };
    // 开机自启与 HOME 键目标：原生落 prefs 后再 publish，这里照做——
    // 少这一句，设置页点完按钮选中态不动，看起来就是「按钮按了没反应」。
    if (action == 'boot-autostart')
      state = {
        ...state,
        'integrationPreferences': {
          ...Map<String, dynamic>.from(
              state['integrationPreferences'] as Map? ?? const {}),
          'bootAutostart': enabled != false
        }
      };
    if (action == 'home-key-target') {
      // 和 LauncherRuntime 一样把别名归一成包名：uni → 自己，oem → 原车桌面。
      final raw = (value ?? '').trim();
      final target = raw.isEmpty || raw == 'uni'
          ? 'xyz.i4o.uni.launcher'
          : (raw == 'oem' ? 'ecarx.launcher3' : raw);
      state = {
        ...state,
        'integrationPreferences': {
          ...Map<String, dynamic>.from(
              state['integrationPreferences'] as Map? ?? const {}),
          'homeKeyTarget': target
        }
      };
    }
    // 集成偏好（导航与媒体那批开关）：原生落 prefs 后 publish 全量快照，
    // 假网关也照做，否则点一下就被下一次快照弹回去。
    const prefsFields = {
      'map-texture-scale': 'mapTextureScale',
      'navigation-card-title-hidden': 'navigationCardTitleHidden',
      'steering-keys': 'steeringKeysEnabled',
      'instrument-sync': 'instrumentSyncEnabled',
      'dim-cluster': 'dimClusterEnabled',
      'auto-play-music': 'autoPlayMusic',
    };
    final prefsField = prefsFields[action];
    if (prefsField != null) {
      state = {
        ...state,
        'integrationPreferences': {
          ...Map<String, dynamic>.from(
              state['integrationPreferences'] as Map? ?? const {}),
          prefsField: enabled == true
        }
      };
    }
    if (action == 'embed-navigation') {
      state = {
        ...state,
        'navigation': {
          ...Map<String, dynamic>.from(state['navigation'] as Map? ?? const {}),
          'enabled': enabled != false
        }
      };
    }
    if (action == 'rename-app' && zone != null) {
      final names = Map<String, dynamic>.from(state['appNames'] as Map? ?? {});
      if (value == null || value.isEmpty) {
        names.remove(zone);
      } else {
        names[zone] = value;
      }
      state = {...state, 'appNames': names};
    }
    stream.add(Map.of(state));
  }

  @override
  Future<void> save(String value) async {
    saved = value;
  }

  @override
  void onHome(void Function() callback) {}
  @override
  void onHomeFirst(void Function() callback) {}
  @override
  Future<PickedWallpaper?> pickWallpaper() async => wallpaper;
  @override
  Future<void> setDesktopPage(int page) async {
    commands.add({'action': 'desktop-page', 'value': '$page'});
  }

  Future<void> dispose() => stream.close();
}
