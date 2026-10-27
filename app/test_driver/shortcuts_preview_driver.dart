import 'dart:io';
import 'package:integration_test/integration_test_driver_extended.dart';

Future<void> main() async {
  final out = Directory('verification/shortcuts')..createSync(recursive: true);
  await integrationDriver(onScreenshot: (name, bytes, [args]) async {
    if (!RegExp(r'^shortcuts-[a-z0-9-]+$').hasMatch(name)) return false;
    await File('${out.path}/$name.png').writeAsBytes(bytes);
    return true;
  });
}
