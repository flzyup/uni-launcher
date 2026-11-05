import 'package:flutter/services.dart';

import 'uni_log.dart';

/// The outcome of a diagnostic package export.
class LogExportResult {
  /// True when the package was written.
  final bool ok;

  /// Where the package landed, for picking it up from the head unit.
  final String path;

  /// How many log files went into the package.
  final int files;

  /// Size of the package in bytes.
  final int bytes;

  /// Why the export failed; empty on success.
  final String reason;

  /// The message to show the user.
  final String message;

  const LogExportResult(
      {required this.ok,
      required this.path,
      required this.files,
      required this.bytes,
      required this.reason,
      required this.message});

  static LogExportResult from(Object? raw, String fallbackMessage) {
    if (raw is Map) {
      final map = Map<String, dynamic>.from(raw);
      return LogExportResult(
          ok: map['ok'] == true,
          path: '${map['path'] ?? ''}',
          files: (map['files'] as num?)?.toInt() ?? 0,
          bytes: (map['bytes'] as num?)?.toInt() ?? 0,
          reason: '${map['reason'] ?? ''}',
          message: '${map['message'] ?? fallbackMessage}');
    }
    return LogExportResult(
        ok: false,
        path: '',
        files: 0,
        bytes: 0,
        reason: '',
        message: fallbackMessage);
  }
}

/// User-facing operations on the diagnostic package.
///
/// The export writes a zip to the public Download folder, so a user can pull
/// it off the head unit without a debugger attached.
class LogTools {
  LogTools._();

  static const MethodChannel _channel =
      MethodChannel('xyz.i4o.uni.launcher/log');

  /// Export the diagnostic package (logs + runtime snapshot) as a zip.
  ///
  /// Returns the message to show the user; empty on success.
  static Future<LogExportResult> export() async {
    final raw = await _invoke<Object?>('export');
    final result = LogExportResult.from(raw, '');
    UniLog.event(UniLogTags.log, '导出诊断包', fields: {
      'ok': result.ok,
      'files': result.files,
      'bytes': result.bytes,
      if (result.reason.isNotEmpty) 'reason': result.reason,
    });
    return result;
  }

  /// Export the package and open the system share sheet.
  static Future<LogExportResult> exportAndShare() async {
    final raw = await _invoke<Object?>('exportAndShare');
    final result = LogExportResult.from(raw, '');
    UniLog.event(UniLogTags.log, '导出并分享诊断包',
        fields: {'ok': result.ok, 'files': result.files});
    return result;
  }

  /// Delete every persisted log file.
  static Future<String> clear() async {
    final message = await _invoke<String>('clear');
    return message ?? '';
  }

  /// The last [lines] log lines, for the "is it writing at all?" check.
  static Future<String> preview({int lines = 60}) async {
    final text = await _invoke<String>('preview', lines);
    return text ?? '(暂无日志)';
  }

  /// Log system state: level, bytes on disk, degraded flag, anchor count.
  static Future<Map<String, dynamic>> status() async {
    final raw = await _invoke<Map<Object?, Object?>>('status');
    return raw == null ? <String, dynamic>{} : Map<String, dynamic>.from(raw);
  }

  /// Ask for the storage permission the export needs.
  ///
  /// Android 9 and below write the package straight into the public Download
  /// folder, which needs `WRITE_EXTERNAL_STORAGE`; without it the export fails
  /// outright. Android 10+ goes through MediaStore and needs nothing, so the
  /// native side reports "granted" straight away.
  ///
  /// Returns whether the export can go ahead.
  static Future<bool> ensureStoragePermission() async {
    final granted = await _invoke<bool>('ensurePermission');
    return granted == true;
  }

  /// Change the persistence threshold and return the effective level.
  static Future<String> setLevel(UniLogLevel level) async {
    final name = await _invoke<String>('level', level.name.toUpperCase());
    return name ?? level.name;
  }

  static Future<T?> _invoke<T>(String method, [Object? argument]) async {
    try {
      return await _channel.invokeMethod<T>(method, argument);
    } on MissingPluginException {
      return null;
    } on PlatformException catch (error) {
      UniLog.w(UniLogTags.log, '日志操作失败',
          fields: {'method': method, 'error': error.message});
      return null;
    }
  }
}
