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
      'title': '向海而行',
      'artist': 'Coastline',
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
