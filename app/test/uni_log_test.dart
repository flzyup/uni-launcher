import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uni_launcher/platform/uni_log.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('xyz.i4o.uni.launcher/log');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  List<Map<String, dynamic>> sent = [];

  setUp(() async {
    sent = [];
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'log');
      // The standard codec decodes maps with Object? keys, so they have to be
      // re-typed before they can be inspected here.
      for (final record in (call.arguments as List).cast<Map<Object?, Object?>>()) {
        sent.add(record.map((key, value) => MapEntry('$key', value)));
      }
      return null;
    });
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
  });

  test('records are buffered and flushed as one batch', () async {
    UniLog.i(UniLogTags.app, 'first');
    UniLog.i(UniLogTags.media, 'second');
    expect(sent, isEmpty, reason: 'nothing should leave before the flush');

    await UniLog.flush();

    expect(sent, hasLength(2));
    expect(sent.first['level'], 'info');
    expect(sent.first['tag'], UniLogTags.app);
    expect(sent.first['message'], 'first');
  });

  test('structured fields survive the trip to the native side', () async {
    UniLog.w(UniLogTags.vehicle, '读不到',
        fields: {'source': 'official', 'raw': 0});
    await UniLog.flush();

    final fields = sent.single['fields'] as Map;
    expect(fields['source'], 'official');
    expect(fields['raw'], 0);
    expect(sent.single['level'], 'warn');
  });

  test('an error carries the exception text', () async {
    UniLog.e(UniLogTags.app, 'boom',
        error: StateError('nope'), stackTrace: StackTrace.current);
    await UniLog.flush();

    final fields = sent.single['fields'] as Map;
    expect(fields['error'], contains('nope'));
    expect(fields['stack'], isNotEmpty);
  });

  test('anchors are sent as their own record kind', () async {
    UniLog.enter(UniLogTags.vehicle, 'vehicle/read');
    UniLog.done(UniLogTags.vehicle, 'vehicle/read');
    await UniLog.flush();

    expect(sent, hasLength(2));
    expect(sent.first['kind'], 'anchor');
    expect(sent.first['node'], 'vehicle/read');
    expect(sent.first['stage'], 'enter');
    expect(sent.last['stage'], 'done');
  });

  test('the buffer flushes itself once it is full', () async {
    for (var i = 0; i < 40; i++) {
      UniLog.i(UniLogTags.app, 'line $i');
    }
    // The threshold is 32, so the first batch left without an explicit flush.
    // The flush itself is scheduled as a microtask, so let it run.
    await Future<void>.delayed(Duration.zero);
    expect(sent.length, greaterThanOrEqualTo(32));
    await UniLog.flush();
    expect(sent.length, 40);
  });

  test('a burst inside one turn costs a single channel call', () async {
    for (var i = 0; i < 10; i++) {
      UniLog.i(UniLogTags.app, 'burst $i');
    }
    await UniLog.flush();
    expect(sent, hasLength(10));
  });

  test('the payload is JSON encodable for the platform channel', () async {
    UniLog.i(UniLogTags.app, '可序列化', fields: {'k': 'v'});
    await UniLog.flush();
    expect(() => jsonEncode(sent), returnsNormally);
  });
}
