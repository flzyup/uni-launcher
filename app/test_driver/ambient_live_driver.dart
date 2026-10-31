import 'dart:convert';
import 'dart:io';

import 'package:integration_test/integration_test_driver_extended.dart';

/// Driver for the live ambient light test.
///
/// The test feeds its own spectrum frames (an emulator has no usable audio
/// output for a non system app), but everything after that is the production
/// chain and the production widgets. The driver saves the report so the run
/// leaves the evidence on disk.
///
/// The emulator guard is kept on purpose: the test drives a real device
/// process, so it must never run on an actual vehicle.
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
      Platform.environment['UNI_AMBIENT_OUT'] ?? 'verification/ambient-live')
    ..createSync(recursive: true);
  await integrationDriver(
    responseDataCallback: (data) async {
      final report = Map<String, dynamic>.from(data ?? {});
      await File('${out.path}/emulator-report.json').writeAsString(
          '${const JsonEncoder.withIndent('  ').convert(report)}\n');
    },
    writeResponseOnFailure: true,
  );
}
