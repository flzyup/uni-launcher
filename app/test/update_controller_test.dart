import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uni_launcher/ota/update_controller.dart';

void main() {
  testWidgets('startup checks once with periodic checks disabled by default',
      (tester) async {
    const bridge = MethodChannel('xyz.i4o.uni.launcher/platform');
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final dir = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('uni-update-schedule-')))!;
    messenger.setMockMethodCallHandler(bridge, (call) async {
      if (call.method == 'otaInfo') return {
        'directory': dir.path, 'versionCode': 1, 'sdk': 28, 'abis': ['arm64-v8a']
      };
      return null;
    });
    final u = UpdateController();
    await tester.runAsync(u.initialize);
    expect(u.enabled, isFalse);
    expect(u.intervalMinutes, 30);
    await tester.runAsync(() async {
      final done = Completer<void>();
      messenger.handlePlatformMessage('xyz.i4o.uni.launcher/ota-events',
          const StandardMethodCodec().encodeMethodCall(const MethodCall('boot-check')),
          (_) => done.complete());
      await done.future;
    });
    expect(u.lastAttempt, isNotNull);
    final first = u.lastAttempt;
    u.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await tester.pump();
    expect(u.lastAttempt, first);
    await u.setEnabled(true);
    await u.setInterval(120);
    expect(u.intervalMinutes, 120);
    await u.setInterval(15);
    expect(u.intervalMinutes, 120);
    u.dispose();
    messenger.setMockMethodCallHandler(bridge, null);
    await tester.runAsync(() => dir.delete(recursive: true));
  });
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
        await File('${dir.path}/update.apk').delete();
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
        await File('${dir.path}/update.apk').delete();
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

  testWidgets('reuses a verified cached APK and replaces a corrupt cache',
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
      final dir = await Directory.systemTemp.createTemp('uni-ota-cache-');
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final bytes = utf8.encode('verified update');
      final digest = sha256.convert(bytes).toString();
      var requests = 0;
      final sub = server.listen((request) async {
        requests++;
        request.response.add(bytes);
        await request.response.close();
      });
      try {
        final u = UpdateController(
            allowHttpForTesting: true, hostsForTesting: {'127.0.0.1'});
        u.info = {'directory': dir.path};
        u.release = {
          'artifact': {
            'url': 'http://127.0.0.1:${server.port}/update',
            'sha256': digest,
            'size_bytes': bytes.length,
          }
        };
        final apk = File('${dir.path}/update.apk');
        final partial = File('${dir.path}/update.part');
        final identity = File('${dir.path}/update.identity');
        await apk.writeAsBytes(bytes);
        await partial.writeAsBytes([1, 2]);
        await identity.writeAsString('old');
        await u.download();
        expect(requests, 0);
        expect(installs, 1);
        expect(await partial.exists(), isFalse);
        expect(await identity.exists(), isFalse);
        await apk.writeAsBytes(List.filled(bytes.length, 0));
        await u.download();
        expect(requests, 1);
        expect(installs, 2);
        expect(await apk.readAsBytes(), bytes);
        expect(u.state, 'install');
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

  testWidgets('startup prunes stale and duplicate OTA cache files',
      (tester) async {
    final binding = TestDefaultBinaryMessengerBinding.instance;
    const bridge = MethodChannel('xyz.i4o.uni.launcher/platform');
    await tester.runAsync(() async {
      final dir = await Directory.systemTemp.createTemp('uni-ota-prune-');
      binding.defaultBinaryMessenger.setMockMethodCallHandler(bridge,
          (call) async {
        if (call.method == 'otaInfo') return {'directory': dir.path};
        return null;
      });
      final target = File('${dir.path}/update.apk');
      final partial = File('${dir.path}/update.part');
      final identity = File('${dir.path}/update.identity');
      try {
        await target.writeAsBytes([1]);
        await partial.writeAsBytes([2]);
        await identity.writeAsString('test');
        final first = UpdateController();
        await first.initialize();
        expect(await target.exists(), isTrue);
        expect(await partial.exists(), isFalse);
        expect(await identity.exists(), isFalse);
        first.dispose();

        await target
            .setLastModified(DateTime.now().subtract(const Duration(days: 31)));
        await partial.writeAsBytes([2]);
        await partial
            .setLastModified(DateTime.now().subtract(const Duration(days: 8)));
        await identity.writeAsString('test');
        final second = UpdateController();
        await second.initialize();
        expect(await target.exists(), isFalse);
        expect(await partial.exists(), isFalse);
        expect(await identity.exists(), isFalse);
        second.dispose();
      } finally {
        binding.defaultBinaryMessenger.setMockMethodCallHandler(bridge, null);
        await dir.delete(recursive: true);
      }
    });
  });
}
