import 'package:flutter/services.dart';

/// Lyric timing and cache preferences, as stored by the native side.
///
/// Both live next to the "关联的音乐播放器" picker because they only make sense there: the
/// offset compensates for the latency of the path the chosen player feeds (Bluetooth, USB,
/// the head unit's own DSP), and the cache policy decides how much of that player's catalogue
/// is kept on the device.
class LyricTuning {
  static const MethodChannel channel =
      MethodChannel('xyz.i4o.uni.launcher/platform');

  /// Positive values move the highlight later, negative earlier. Native clamps to ±3000 ms.
  static const int limitMs = 3000;

  const LyricTuning({
    this.globalMs = 0,
    this.trackMs = 0,
    this.title = '',
    this.artist = '',
    this.policy = LyricCachePolicy.thirtyDays,
    this.limitMb = 24,
  });

  /// Offset applied to every track.
  final int globalMs;

  /// Extra correction for [title]/[artist], on top of [globalMs].
  final int trackMs;
  final String title;
  final String artist;

  /// One of [LyricCachePolicy.forever], [LyricCachePolicy.thirtyDays],
  /// [LyricCachePolicy.capacity].
  final String policy;
  final int limitMb;

  bool get hasTrack => title.trim().isNotEmpty;

  /// Total shift the panel and the card are using right now.
  int get effectiveMs =>
      (globalMs + (hasTrack ? trackMs : 0)).clamp(-limitMs, limitMs);

  factory LyricTuning.fromJson(Map<dynamic, dynamic> json) {
    int intOf(Object? value) {
      if (value is num) return value.toInt();
      if (value is String) return int.tryParse(value) ?? 0;
      return 0;
    }

    return LyricTuning(
      globalMs: intOf(json['globalMs']),
      trackMs: intOf(json['trackMs']),
      title: '${json['title'] ?? ''}',
      artist: '${json['artist'] ?? ''}',
      policy: LyricCachePolicy.normalise('${json['policy'] ?? ''}'),
      limitMb: intOf(json['limitMb']) == 0 ? 24 : intOf(json['limitMb']),
    );
  }

  LyricTuning copyWith({
    int? globalMs,
    int? trackMs,
    String? title,
    String? artist,
    String? policy,
    int? limitMb,
  }) =>
      LyricTuning(
        globalMs: globalMs ?? this.globalMs,
        trackMs: trackMs ?? this.trackMs,
        title: title ?? this.title,
        artist: artist ?? this.artist,
        policy: policy ?? this.policy,
        limitMb: limitMb ?? this.limitMb,
      );

  /// Read both halves in one round trip. Never throws: a missing native side reads as defaults.
  static Future<LyricTuning> load() async {
    try {
      final raw = await channel
          .invokeMethod<Map<dynamic, dynamic>>('lyricTuningStatus');
      if (raw == null) return const LyricTuning();
      return LyricTuning.fromJson(raw);
    } on PlatformException {
      return const LyricTuning();
    } on MissingPluginException {
      return const LyricTuning();
    }
  }

  /// Persist the offsets. [title]/[artist] identify the track [trackMs] belongs to; pass an
  /// empty title to leave the per-track table alone.
  static Future<bool> saveOffset({
    required int globalMs,
    String title = '',
    String artist = '',
    int trackMs = 0,
  }) async {
    try {
      await channel.invokeMethod<Map<dynamic, dynamic>>('lyricTuning', {
        'globalMs': globalMs,
        'trackMs': trackMs,
        if (title.trim().isNotEmpty) 'title': title,
        if (artist.trim().isNotEmpty) 'artist': artist,
      });
      return true;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// Persist the cache policy; returns the value the native side accepted.
  static Future<String> saveCache({
    required String policy,
    required int limitMb,
  }) async {
    try {
      final applied = await channel.invokeMethod<String>('lyricCache', {
        'policy': policy,
        'limitMb': limitMb,
      });
      return LyricCachePolicy.normalise(applied ?? policy);
    } on PlatformException {
      return LyricCachePolicy.normalise(policy);
    } on MissingPluginException {
      return LyricCachePolicy.normalise(policy);
    }
  }
}

/// The three retention policies the native cache understands.
class LyricCachePolicy {
  const LyricCachePolicy._();

  /// Keep everything; a lyric is fetched once, ever.
  static const String forever = 'forever';

  /// Drop documents unused for 30 days (default).
  static const String thirtyDays = '30d';

  /// Keep the most recent documents under a size ceiling.
  static const String capacity = 'capacity';

  static const String defaultPolicy = thirtyDays;

  static String normalise(String value) {
    switch (value.trim().toLowerCase()) {
      case forever:
        return forever;
      case capacity:
        return capacity;
      case thirtyDays:
        return thirtyDays;
    }
    return defaultPolicy;
  }

  static String label(String value) {
    switch (normalise(value)) {
      case forever:
        return '永久保留';
      case capacity:
        return '按容量清理';
    }
    return '30 天未用即清理';
  }

  static const List<String> all = [thirtyDays, forever, capacity];
}
