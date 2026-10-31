import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// OTA endpoint and COS download hosts are supplied by the release build.
const otaBase = String.fromEnvironment('UNI_OTA_URL');
const otaHosts = String.fromEnvironment('UNI_OTA_DOWNLOAD_HOSTS');
const otaHttpHosts = String.fromEnvironment('UNI_OTA_HTTP_DOWNLOAD_HOSTS');
const otaPlatform =
    String.fromEnvironment('UNI_OTA_PLATFORM', defaultValue: 'unknown');
const _bridge = MethodChannel('xyz.i4o.uni.launcher/platform');
const defaultContributors = ['卢AI玩', 'Felix', '十一', 'ChainStrong'];

@visibleForTesting
bool isTrustedDownload(Uri uri, Set<String> hosts, Set<String> httpHosts) =>
    uri.userInfo.isEmpty &&
    hosts.contains(uri.host.toLowerCase()) &&
    (uri.scheme == 'https' ||
        (uri.scheme == 'http' && httpHosts.contains(uri.host.toLowerCase())));

class UpdateController extends ChangeNotifier with WidgetsBindingObserver {
  @visibleForTesting
  final bool allowHttpForTesting;
  @visibleForTesting
  final Set<String>? hostsForTesting;
  UpdateController({this.allowHttpForTesting = false, this.hostsForTesting});
  Map<String, dynamic> info = {};
  Map<String, dynamic>? release;
  List<String> contributors = List.of(defaultContributors);
  String state = 'idle', error = '';
  double progress = 0;
  bool enabled = true, cancelled = false, foreground = true, dialogOpen = false;
  DateTime? lastChecked, dismissedAt, lastAttempt, lastContributorsRefresh;
  bool _disposed = false;
  int? dismissedVersion;
  Timer? timer, startupTimer;
  VoidCallback? onAvailable;
  HttpClient? _downloadClient;
  bool _checking = false;
  Uri get _base {
    final uri = Uri.parse(otaBase);
    if (uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment) throw StateError('更新服务尚未配置');
    return uri;
  }

  Uri _url(String path, [Map<String, String>? q]) =>
      _base.resolve(path).replace(queryParameters: q);
  Future<void> initialize() async {
    WidgetsBinding.instance.addObserver(this);
    try {
      info = Map<String, dynamic>.from(
          await _bridge.invokeMapMethod<String, dynamic>('otaInfo') ?? {});
      if (_disposed) return;
      enabled = info['enabled'] != false;
      final dismissedMs = (info['dismissedAt'] as num?)?.toInt() ?? 0;
      dismissedVersion = (info['dismissedVersion'] as num?)?.toInt();
      if (dismissedMs > 0)
        dismissedAt = DateTime.fromMillisecondsSinceEpoch(dismissedMs);
      final cache = File('${info['directory']}/contributors.json');
      try {
        if (await cache.exists()) {
          _acceptContributors(jsonDecode(await cache.readAsString()));
          lastContributorsRefresh = await cache.lastModified();
        }
      } catch (_) {/* Keep bundled contributors on corrupt cache. */}
      if (_disposed) return;
      notifyListeners();
      timer = Timer.periodic(const Duration(minutes: 5), (_) {
        if (enabled) check();
      });
      if (enabled)
        startupTimer = Timer(const Duration(seconds: 30), () {
          if (enabled) check();
        });
    } catch (_) {
      error = '无法读取应用版本';
      notifyListeners();
    }
  }

  bool get _mayPrompt {
    final code = (release?['version_code'] as num?)?.toInt();
    return code != null &&
        (dismissedVersion != code ||
            dismissedAt == null ||
            DateTime.now().difference(dismissedAt!) >=
                const Duration(minutes: 5));
  }

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    // A platform view or permission sheet can temporarily take focus while
    // the launcher remains visible. Flutter reports this as inactive.
    foreground =
        s == AppLifecycleState.resumed || s == AppLifecycleState.inactive;
    if (foreground && state == 'permission') _resumeInstallIfAllowed();
    if (foreground && state == 'found' && !dialogOpen && _mayPrompt)
      onAvailable?.call();
    if (foreground &&
        enabled &&
        (lastAttempt == null ||
            DateTime.now().difference(lastAttempt!) >=
                const Duration(minutes: 5))) check();
  }

  Future<void> _resumeInstallIfAllowed() async {
    try {
      final allowed = await _bridge.invokeMethod<bool>('otaCanInstall');
      if (!_disposed &&
          foreground &&
          state == 'permission' &&
          allowed == true) {
        await install();
      }
    } catch (_) {/* The permission page or installer may be unavailable. */}
  }

  Future<void> setEnabled(bool v) async {
    enabled = v;
    notifyListeners();
    await _bridge.invokeMethod<void>('otaEnabled', v);
  }

  Future<Map<String, dynamic>> _get(Uri uri) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 10);
    try {
      final request =
          await client.getUrl(uri).timeout(const Duration(seconds: 12));
      request.followRedirects = false;
      final res = await request.close().timeout(const Duration(seconds: 15));
      if (res.statusCode != 200) throw HttpException('服务暂不可用');
      final bytes = <int>[];
      await for (final part in res.timeout(const Duration(seconds: 15))) {
        bytes.addAll(part);
        if (bytes.length > 65536) throw const FormatException('响应过大');
      }
      final v = jsonDecode(utf8.decode(bytes));
      if (v is! Map) throw const FormatException('响应格式错误');
      return Map<String, dynamic>.from(v);
    } finally {
      client.close(force: true);
    }
  }

  Future<void> check({bool manual = false}) async {
    if (_disposed ||
        _checking ||
        state == 'downloading' ||
        state == 'verifying') return;
    _checking = true;
    lastAttempt = DateTime.now();
    if (manual) {
      state = 'checking';
      notifyListeners();
    }
    try {
      final data = await _get(_url('/v1/updates/check', {
        'package': 'xyz.i4o.uni.launcher',
        'version_code': '${info['versionCode']}',
        'sdk': '${info['sdk']}',
        'abis': (info['abis'] as List).join(','),
        'channel': 'stable',
        'platform': otaPlatform,
      }));
      if (data['schema_version'] != 1 || data['update_available'] is! bool)
        throw const FormatException('响应格式错误');
      lastChecked = DateTime.now();
      if (data['update_available'] == true) {
        final r = Map<String, dynamic>.from(data['release'] as Map);
        final a = Map<String, dynamic>.from(r['artifact'] as Map);
        final code = (r['version_code'] as num).toInt(),
            size = (a['size_bytes'] as num).toInt();
        if (r['package_name'] != 'xyz.i4o.uni.launcher' ||
            code <= (info['versionCode'] as num).toInt() ||
            (a['abi'] != 'universal' &&
                !(info['abis'] as List).contains(a['abi'])) ||
            size <= 0 ||
            size > 512 * 1024 * 1024 ||
            !RegExp(r'^[a-fA-F0-9]{64}$').hasMatch('${a['sha256']}'))
          throw const FormatException('更新信息无效');
        release = r;
        state = 'found';
        if (!_disposed && !manual && foreground && !dialogOpen && _mayPrompt)
          onAvailable?.call();
      } else {
        release = null;
        state = data['reason'] == 'no_compatible_release'
            ? 'incompatible'
            : 'latest';
      }
      error = '';
    } catch (e) {
      debugPrint('UNI OTA check failed: ${e.runtimeType}');
      if (manual) {
        state = 'error';
        error = otaBase.isEmpty ? '更新服务尚未配置' : '检查失败，请检查网络或稍后重试';
      }
    } finally {
      _checking = false;
      notifyListeners();
    }
  }

  bool _acceptContributors(dynamic d) {
    if (d is! Map || d['schema_version'] != 1 || d['contributors'] is! List)
      return false;
    final l = d['contributors'] as List;
    if (l.isEmpty || l.length > 100) return false;
    final names = <String>[];
    for (final x in l) {
      if (x is! String ||
          x.trim() != x ||
          x.isEmpty ||
          x.runes.length > 40 ||
          x.contains(RegExp(r'[\r\n\x00]')) ||
          names.contains(x)) return false;
      names.add(x);
    }
    contributors = names;
    return true;
  }

  Future<void> refreshContributors() async {
    if (lastContributorsRefresh != null &&
        DateTime.now().difference(lastContributorsRefresh!) <
            const Duration(hours: 24)) return;
    try {
      final d = await _get(_url('/v1/contributors'));
      if (_acceptContributors(d)) {
        await File('${info['directory']}/contributors.json')
            .writeAsString(jsonEncode(d), flush: true);
        lastContributorsRefresh = DateTime.now();
        notifyListeners();
      }
    } catch (_) {}
  }

  void dismiss() {
    final n = release?['version_code'];
    dismissedVersion = n is num ? n.toInt() : null;
    dismissedAt = DateTime.now();
    if (dismissedVersion != null)
      _bridge
          .invokeMethod<void>('otaDismiss', dismissedVersion)
          .catchError((Object _) {});
  }

  Future<void> download({bool refreshed = false}) async {
    final r = release;
    if (r == null) return;
    cancelled = false;
    state = 'downloading';
    progress = 0;
    error = '';
    notifyListeners();
    try {
      final a = Map<String, dynamic>.from(r['artifact'] as Map);
      final uri = Uri.parse('${a['url']}');
      final allowed = hostsForTesting ??
          otaHosts
              .split(',')
              .map((s) => s.trim().toLowerCase())
              .where((s) => s.isNotEmpty)
              .toSet();
      final httpAllowed = allowHttpForTesting && hostsForTesting != null
          ? hostsForTesting!
          : otaHttpHosts
              .split(',')
              .map((s) => s.trim().toLowerCase())
              .where((s) => s.isNotEmpty)
              .toSet();
      if (!isTrustedDownload(uri, allowed, httpAllowed))
        throw const FormatException('下载地址不受信任');
      final expected = '${a['sha256']}'.toLowerCase(),
          size = (a['size_bytes'] as num).toInt();
      final dir = Directory('${info['directory']}');
      await dir.create(recursive: true);
      final partial = File('${dir.path}/update.part'),
          identity = File('${dir.path}/update.identity');
      if (!await identity.exists() ||
          await identity.readAsString() != '$expected:$size') {
        if (await partial.exists()) await partial.delete();
        await identity.writeAsString('$expected:$size', flush: true);
      }
      var start = await partial.exists() ? await partial.length() : 0;
      if (start > size) {
        await partial.delete();
        start = 0;
      }
      final client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 15);
      _downloadClient = client;
      try {
        if (start < size) {
          final req =
              await client.getUrl(uri).timeout(const Duration(seconds: 20));
          req.followRedirects = false;
          if (start > 0)
            req.headers.set(HttpHeaders.rangeHeader, 'bytes=$start-');
          final res = await req.close().timeout(const Duration(seconds: 30));
          if (start > 0 && res.statusCode == 200) {
            start = 0;
          } else if (start > 0 && res.statusCode == 206) {
            final cr = res.headers.value(HttpHeaders.contentRangeHeader);
            if (cr != 'bytes $start-${size - 1}/$size')
              throw const FormatException('续传范围无效');
          } else if (start == 0 && res.statusCode == 200) {
          } else if (res.statusCode == 401 || res.statusCode == 403) {
            throw const _ExpiredUpdateUrl();
          } else {
            throw HttpException('下载不可用，请重新检查后重试');
          }
          final sink = partial.openWrite(
              mode: start > 0 ? FileMode.append : FileMode.write);
          var count = start;
          var lastProgressNotice = DateTime.fromMillisecondsSinceEpoch(0);
          try {
            await for (final chunk
                in res.timeout(const Duration(seconds: 30))) {
              if (cancelled) throw StateError('cancelled');
              count += chunk.length;
              if (count > size) throw const FormatException('文件过大');
              sink.add(chunk);
              progress = count / size;
              final now = DateTime.now();
              if (count == size ||
                  now.difference(lastProgressNotice).inMilliseconds >= 200) {
                lastProgressNotice = now;
                notifyListeners();
              }
            }
            await sink.flush();
          } finally {
            await sink.close();
          }
          if (count != size) throw const FormatException('下载未完成');
        }
      } finally {
        client.close(force: true);
        _downloadClient = null;
      }
      if (cancelled) throw StateError('cancelled');
      state = 'verifying';
      notifyListeners();
      if (await partial.length() != size ||
          (await sha256.bind(partial.openRead()).first).toString() !=
              expected) {
        await partial.delete();
        throw const FormatException('安装包校验失败');
      }
      final target = File('${dir.path}/update.apk');
      if (await target.exists()) await target.delete();
      await partial.rename(target.path);
      if (await identity.exists()) await identity.delete();
      state = 'install';
      notifyListeners();
      await install();
    } on _ExpiredUpdateUrl {
      if (!refreshed && !cancelled) {
        state = 'idle';
        await check(manual: true);
        final previous = (r['artifact'] as Map)['sha256'];
        final current = release?['artifact'];
        if (state == 'found' &&
            current is Map &&
            current['sha256'] == previous) {
          await download(refreshed: true);
          return;
        }
      }
      state = 'error';
      error = '下载链接已过期，请重新检查后重试';
      notifyListeners();
    } catch (e) {
      if (cancelled) {
        state = 'found';
      } else {
        state = 'error';
        error = '下载或校验失败，请重新检查后重试';
      }
      notifyListeners();
    }
  }

  Future<void> install() async {
    try {
      final result = await _bridge.invokeMethod<String>('otaInstall');
      if (result == 'permission') {
        state = 'permission';
      } else {
        state = 'install';
      }
      notifyListeners();
    } catch (_) {
      state = 'error';
      error = '安装包不兼容或签名不一致';
      notifyListeners();
    }
  }

  void cancel() {
    cancelled = true;
    _downloadClient?.close(force: true);
  }

  @override
  void dispose() {
    _disposed = true;
    timer?.cancel();
    startupTimer?.cancel();
    _downloadClient?.close(force: true);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}

class _ExpiredUpdateUrl implements Exception {
  const _ExpiredUpdateUrl();
}
