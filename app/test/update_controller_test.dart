import 'dart:io';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uni_launcher/ota/update_controller.dart';

void main() {
  test('HTTP downloads are limited to explicitly allowed hosts', () {
    const hosts = {'share-ota.circleai.tech', 'secure.example'};
    const httpHosts = {'share-ota.circleai.tech'};
    expect(
        isTrustedDownload(
            Uri.parse('http://share-ota.circleai.tech/file'), hosts, httpHosts),
        isTrue);
    expect(
        isTrustedDownload(
            Uri.parse('http://secure.example/file'), hosts, httpHosts),
        isFalse);
    expect(
        isTrustedDownload(
            Uri.parse('https://secure.example/file'), hosts, httpHosts),
        isTrue);
    expect(
        isTrustedDownload(
            Uri.parse('http://attacker.example/file'), hosts, httpHosts),
        isFalse);
    expect(
        isTrustedDownload(Uri.parse('http://user@share-ota.circleai.tech/file'),
            hosts, httpHosts),
        isFalse);
  });
  testWidgets('resumes partial APK with validated Range and rejects bad ranges',
      (tester) async {
    final binding = TestDefaultBinaryMessengerBinding.instance;
    const bridge = MethodChannel('xyz.i4o.uni.launcher/platform');
    var installs = 0;
    binding.defaultBinaryMessenger.setMockMethodCallHandler(bridge,
        (call) async {
      if (call.method == 'otaInstall') {
        installs++;
        return 'started';
      }
      return null;
    });
    await tester.runAsync(() async {
      final previous = HttpOverrides.current;
      HttpOverrides.global = null;
      final dir = await Directory.systemTemp.createTemp('uni-ota-test-');
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final bytes = utf8.encode('0123456789abcdef');
      final digest = sha256.convert(bytes).toString();
      var badRange = false;
      var ignoreRange = false;
      var corrupt = false;
      var receivedRange = '';
      final sub = server.listen((req) async {
        receivedRange = req.headers.value('range') ?? '';
        if (receivedRange.isNotEmpty && !ignoreRange) {
          req.response.statusCode = 206;
          req.response.headers.set(
              'content-range', badRange ? 'bytes 0-15/16' : 'bytes 5-15/16');
          req.response.add(bytes.sublist(5));
        } else {
          req.response.add(corrupt ? List<int>.filled(bytes.length, 0) : bytes);
        }
        await req.response.close();
      });
      try {
        final u = UpdateController(
            allowHttpForTesting: true, hostsForTesting: {'127.0.0.1'});
        u.info = {'directory': dir.path};
        u.release = {
          'artifact': {
            'url': 'http://127.0.0.1:${server.port}/a.apk',
            'sha256': digest,
            'size_bytes': bytes.length
          }
        };
        await File('${dir.path}/update.part').writeAsBytes(bytes.sublist(0, 5));
        await File('${dir.path}/update.identity')
            .writeAsString('$digest:${bytes.length}');
        await u.download();
        expect(receivedRange, 'bytes=5-');
        expect(await File('${dir.path}/update.apk').readAsBytes(), bytes);
        expect(installs, 1);
        expect(u.state, 'install');
        await File('${dir.path}/update.part').writeAsBytes(bytes.sublist(0, 5));
        await File('${dir.path}/update.identity')
            .writeAsString('$digest:${bytes.length}');
        badRange = true;
        await u.download();
        expect(u.state, 'error');
        expect(installs, 1);
        badRange = false;
        ignoreRange = true;
        await u.download();
        expect(u.state, 'install');
        expect(await File('${dir.path}/update.apk').readAsBytes(), bytes);
        expect(installs, 2);
        corrupt = true;
        await u.download();
        expect(u.state, 'error');
        expect(installs, 2);
        u.dispose();
      } finally {
        await sub.cancel();
        await server.close(force: true);
        await dir.delete(recursive: true);
        HttpOverrides.global = previous;
      }
    });
    binding.defaultBinaryMessenger.setMockMethodCallHandler(bridge, null);
  });
}
