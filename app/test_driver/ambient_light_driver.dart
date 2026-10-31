import 'dart:convert';
import 'dart:io';

import 'package:integration_test/integration_test_driver_extended.dart';

/// Driver for the ambient light integration test.
///
/// Unlike the shared driver this one needs no media fixture: the test feeds
/// its own spectrum frames, because a head unit emulator has no usable audio
/// output. Everything else is the real path, including the native writer that
/// the test asserts on.
///
/// The emulator guard is kept on purpose. The test reads the write counters
/// of a real device process, so it must never run on an actual vehicle.
Future<void> main() async {
  final serial = Platform.environment['UNI_EMULATOR_SERIAL'] ?? 'emulator-5580';
  if (!RegExp(r'^emulator-\d+$').hasMatch(serial))
    throw StateError('Emulator required');
  Future<String> adb(List<String> args) async {
    final result = await Process.run('adb', ['-s', serial, ...args])
        .timeout(const Duration(seconds: 30));
    if (result.exitCode != 0)
      throw StateError('Emulator setup failed: ${result.stderr}');
    return '${result.stdout}'.trim();
  }

  if (await adb(['shell', 'getprop', 'ro.kernel.qemu']) != '1')
    throw StateError('Refusing to test a real vehicle');

  final out = Directory(
      Platform.environment['UNI_AMBIENT_OUT'] ?? 'verification/ambient-light')
    ..createSync(recursive: true);
  await integrationDriver(
    onScreenshot: (name, bytes, [args]) async {
      await File('${out.path}/$name.png').writeAsBytes(bytes);
      return true;
    },
    responseDataCallback: (data) async {
      final report = Map<String, dynamic>.from(data ?? {});
      final screenshots = report.remove('screenshots') as List? ?? [];
      report['screenshots'] =
          screenshots.map((shot) => '${shot['screenshotName']}.png').toList();
      await File('${out.path}/emulator-report.json').writeAsString(
          '${const JsonEncoder.withIndent('  ').convert(report)}\n');
    },
    writeResponseOnFailure: true,
  );
}
