import 'dart:convert';
import 'dart:io';
import 'package:integration_test/integration_test_driver_extended.dart';

Future<void> main() async {
  final serial = Platform.environment['UNI_EMULATOR_SERIAL'] ?? 'emulator-5554';
  if (!RegExp(r'^emulator-\d+$').hasMatch(serial))
    throw StateError('Emulator required');
  final device = await Process.run(
      'adb', ['-s', serial, 'shell', 'getprop', 'ro.kernel.qemu']);
  if ('${device.stdout}'.trim() != '1') throw StateError('Emulator required');
  final out = Directory(Platform.environment['UNI_THEME_VERIFY_OUT'] ??
      'verification/theme-contrast')
    ..createSync(recursive: true);
  await integrationDriver(
      onScreenshot: (name, bytes, [args]) async {
        if (!RegExp(r'^theme-[a-zA-Z0-9-]+$').hasMatch(name)) return false;
        await File('${out.path}/$name.png').writeAsBytes(bytes);
        return true;
      },
      responseDataCallback: (data) async {
        final report = Map<String, dynamic>.from(data ?? {});
        final shots = report.remove('screenshots') as List? ?? [];
        report['screenshots'] =
            shots.map((s) => '${s['screenshotName']}.png').toList();
        // flutter drive removes its fixture APK (and private files) on exit.
        // Pull images before acknowledging the final test response.
        final folder = report['screenshotDirectory'] as String;
        if (!folder.startsWith('/data/') || folder.contains('..')) {
          throw StateError('Unexpected screenshot directory');
        }
        for (final file in (report['files'] as List).cast<String>()) {
          if (!RegExp(r'^theme-[a-zA-Z0-9-]+\.png$').hasMatch(file)) {
            throw StateError('Unexpected screenshot filename');
          }
          final result = await Process.run(
              'adb',
              [
                '-s',
                serial,
                'exec-out',
                'run-as',
                'xyz.i4o.uni.uni_theme_verification',
                'cat',
                '$folder/$file'
              ],
              stdoutEncoding: null);
          if (result.exitCode != 0) throw StateError('${result.stderr}');
          await File('${out.path}/$file')
              .writeAsBytes(result.stdout as List<int>);
        }
        await File('${out.path}/report.json').writeAsString(
            '${const JsonEncoder.withIndent('  ').convert(report)}\n');
      },
      writeResponseOnFailure: true);
}
