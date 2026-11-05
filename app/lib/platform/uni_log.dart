import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Log levels; the native side keeps anything below its threshold out of the
/// persisted file so a long-running head unit does not fill its storage.
enum UniLogLevel { debug, info, warn, error }

/// Log tags; one owner per functional domain so a subsystem can be collected
/// on its own with a single grep.
class UniLogTags {
  static const String app = 'UNI/App';
  static const String vehicle = 'UNI/Vehicle';
  static const String signal = 'UNI/Signal';
  static const String hvac = 'UNI/Hvac';
  static const String media = 'UNI/Media';
  static const String lyric = 'UNI/Lyric';
  static const String spectrum = 'UNI/Spectrum';
  static const String ambient = 'UNI/Ambient';
  static const String nav = 'UNI/Nav';
  static const String traffic = 'UNI/Traffic';
  static const String weather = 'UNI/Weather';
  static const String calendar = 'UNI/Calendar';
  static const String ota = 'UNI/Ota';
  static const String dock = 'UNI/Dock';
  static const String apps = 'UNI/Apps';
  static const String setting = 'UNI/Setting';
  static const String sys = 'UNI/Sys';
  static const String theme = 'UNI/Theme';
  static const String wallpaper = 'UNI/Wallpaper';
  static const String transfer = 'UNI/Transfer';
  static const String debug = 'UNI/Debug';
  static const String ui = 'UNI/UI';
  static const String log = 'UNI/Log';
}

/// The Dart half of the unified log facade.
///
/// Most of the launcher's functional nodes live on this side (cards, pages,
/// settings, OTA), while the native side only executes. Both halves must land
/// in the **same file**, otherwise the exported diagnostic package shows half
/// a chain and still cannot answer "where did it stop".
///
/// Records are buffered and flushed in batches: a home launcher repaints at
/// 60fps, and one platform-channel call per line would cost more than the
/// logging is worth.
class UniLog {
  UniLog._();

  static const MethodChannel _channel =
      MethodChannel('xyz.i4o.uni.launcher/log');

  /// Flush as soon as this many records are pending.
  static const int _flushThreshold = 32;

  static final List<Map<String, dynamic>> _buffer = [];
  static Future<void> _chain = Future<void>.value();
  static bool _flushScheduled = false;
  static bool _nativeAvailable = true;

  /// Whether records are forwarded to the native file sink.
  ///
  /// Widget tests have no platform channel; turning this off keeps them quiet
  /// instead of throwing on every call.
  static bool get nativeAvailable => _nativeAvailable;

  /// Debug-level detail; native keeps it out of the file by default.
  static void d(String tag, String message, {Map<String, Object?> fields = const {}}) =>
      _write(UniLogLevel.debug, tag, message, fields);

  /// Key state and user actions; persisted by default.
  static void i(String tag, String message, {Map<String, Object?> fields = const {}}) =>
      _write(UniLogLevel.info, tag, message, fields);

  /// Failures and degradations; always persisted.
  static void w(String tag, String message,
          {Map<String, Object?> fields = const {}}) =>
      _write(UniLogLevel.warn, tag, message, fields);

  /// Errors; always persisted.
  static void e(String tag, String message,
          {Object? error, StackTrace? stackTrace,
          Map<String, Object?> fields = const {}}) {
    final merged = <String, Object?>{
      ...fields,
      if (error != null) 'error': error.toString(),
      if (stackTrace != null) 'stack': stackTrace.toString(),
    };
    _write(UniLogLevel.error, tag, message, merged);
  }

  /// A user-visible interaction, prefixed with `[EVT]` on the native side.
  static void event(String tag, String message,
          {Map<String, Object?> fields = const {}}) =>
      i(tag, '[EVT] $message', fields: fields);

  /// A key functional node.
  ///
  /// The node name should be stable (`domain/action`, e.g. `card/open`), so
  /// that one grep returns the whole chain:
  /// `adb logcat | grep '\[ANCHOR\] card/open'`.
  static void anchor(String tag, String node, String stage,
          {Map<String, Object?> fields = const {}}) {
    _channelSend({
      'kind': 'anchor',
      'tag': tag,
      'node': node,
      'stage': stage,
      'fields': fields,
    });
  }

  /// Anchor stage: entered.
  static void enter(String tag, String node,
          {Map<String, Object?> fields = const {}}) =>
      anchor(tag, node, 'enter', fields: fields);

  /// Anchor stage: finished.
  static void done(String tag, String node,
          {Map<String, Object?> fields = const {}}) =>
      anchor(tag, node, 'done', fields: fields);

  /// Anchor stage: failed.
  static void fail(String tag, String node,
          {Map<String, Object?> fields = const {}}) =>
      anchor(tag, node, 'fail', fields: fields);

  /// Anchor stage: intentionally skipped.
  static void skip(String tag, String node,
          {Map<String, Object?> fields = const {}}) =>
      anchor(tag, node, 'skip', fields: fields);

  static void _write(UniLogLevel level, String tag, String message,
      Map<String, Object?> fields) {
    if (kDebugMode) {
      developer.log(message,
          name: tag,
          level: switch (level) {
            UniLogLevel.debug => 500,
            UniLogLevel.info => 800,
            UniLogLevel.warn => 900,
            UniLogLevel.error => 1000,
          },
          error: fields.isEmpty ? null : fields);
    }
    _channelSend({
      'kind': 'log',
      'level': level.name,
      'tag': tag,
      'message': message,
      'fields': fields,
    });
  }

  /// Queue a record and schedule a flush.
  ///
  /// The flush is scheduled as a microtask rather than a timer on purpose:
  /// a timer would still be pending when a widget test tears down, and the
  /// window it opens is exactly the window where the last records before a
  /// crash would be lost. A microtask leaves the isolate at the end of the
  /// current turn, so a burst of records still costs one channel call.
  static void _channelSend(Map<String, dynamic> record) {
    if (!_nativeAvailable) return;
    _buffer.add(record);
    if (_buffer.length >= _flushThreshold) {
      flush();
      return;
    }
    if (_flushScheduled) return;
    _flushScheduled = true;
    scheduleMicrotask(() {
      _flushScheduled = false;
      flush();
    });
  }

  /// Send everything that is pending.
  ///
  /// Safe to call at any time; failures are swallowed on purpose — a logger
  /// must never take the launcher down. Concurrent calls are chained so the
  /// batches keep their order.
  static Future<void> flush() async {
    if (_buffer.isEmpty) return _chain;
    final batch = List<Map<String, dynamic>>.from(_buffer);
    _buffer.clear();
    _chain = _chain.then((_) => _send(batch));
    return _chain;
  }

  static Future<void> _send(List<Map<String, dynamic>> batch) async {
    try {
      await _channel.invokeMethod<void>('log', batch);
    } on MissingPluginException {
      // No native side (unit tests): stop trying.
      _nativeAvailable = false;
    } catch (error) {
      if (kDebugMode) {
        developer.log('日志发送失败', name: UniLogTags.log, error: error);
      }
    }
  }
}
