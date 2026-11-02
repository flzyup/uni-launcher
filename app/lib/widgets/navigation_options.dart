import '../controller/launcher_controller.dart';

/// Shared installed navigation sources from native capability discovery.
Map<String, String> navigationOptions(
    LauncherController controller, Map<String, dynamic> native) {
  final navigation = native['navigation'];
  final rawOptions = navigation is Map ? navigation['options'] : null;
  final apps = (native['apps'] is List ? native['apps'] as List : const [])
      .whereType<Map>();
  final result = <String, String>{};
  for (final raw
      in (rawOptions is List ? rawOptions : const []).whereType<Map>()) {
    final pkg = raw['package'];
    if (pkg is! String || pkg.isEmpty) continue;
    final app = apps.where((a) => a['package'] == pkg).firstOrNull;
    final details = Map<String, dynamic>.from(app ?? raw)
      ..putIfAbsent('package', () => pkg);
    result.putIfAbsent(pkg, () => controller.appName(details));
  }
  return result;
}
