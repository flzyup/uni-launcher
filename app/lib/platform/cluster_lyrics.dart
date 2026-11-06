import 'dart:async';

import 'package:flutter/services.dart';

/// One display the unit exposes, as reported by the native cast service.
///
/// [presentation] means Android listed it under
/// `DisplayManager.DISPLAY_CATEGORY_PRESENTATION`, i.e. it advertises itself as a
/// secondary output. A cluster that never appears in the settings list is driven by
/// another process and cannot be drawn on from here — that is a fact about the car,
/// not about the launcher.
int _asInt(Object? value, [int fallback = 0]) =>
    value is num ? value.toInt() : fallback;

double _asDouble(Object? value, double fallback) {
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value) ?? fallback;
  return fallback;
}

class ClusterDisplay {
  final int id;
  final String name;
  final String label;
  final bool presentation;
  final int width;
  final int height;
  final int densityDpi;

  const ClusterDisplay({
    required this.id,
    required this.name,
    required this.label,
    this.presentation = false,
    this.width = 0,
    this.height = 0,
    this.densityDpi = 0,
  });

  factory ClusterDisplay.fromJson(Map<dynamic, dynamic> json) => ClusterDisplay(
        id: _asInt(json['id']),
        name: '${json['name'] ?? ''}',
        label: '${json['label'] ?? ''}',
        presentation: json['presentation'] == true,
        width: _asInt(json['width']),
        height: _asInt(json['height']),
        densityDpi: _asInt(json['densityDpi']),
      );

  /// The saveable half of the identity: names survive a reboot, ids do not.
  String get identity => name;
}

/// What the native cast service is currently doing.
class ClusterCastStatus {
  final bool enabled;
  final int displayId;
  final String displayName;
  final double fontSp;
  final bool solidBackground;

  /// Panel centre and width as fractions of the target display. These are what the
  /// draggable preview edits, and the only placement values that survive a reboot.
  final double xRatio;
  final double yRatio;
  final double widthRatio;

  /// Visible lyric rows, 1–3.
  final int rows;

  /// Highlight colour as 0xAARRGGBB.
  final int accent;

  /// `plain` (bare text), `pill` (translucent plate) or `glow`.
  final String style;

  /// Last attach outcome, human readable. This is the field to show when nothing
  /// appears on the cluster: it says whether the window was added, refused, or
  /// whether no target display was resolved at all.
  final String report;

  /// What the cast window is being fed right now, so "no lyrics" can be told apart from
  /// "no window": the track it resolved, how many lyric lines it holds, and the source.
  final String track;
  final String artist;
  final int lyricLines;
  final String lyricLabel;
  final bool playing;

  const ClusterCastStatus({
    this.enabled = false,
    this.displayId = -1,
    this.displayName = '',
    this.fontSp = 34,
    this.solidBackground = true,
    this.xRatio = 0.5,
    this.yRatio = 0.62,
    this.widthRatio = 0.94,
    this.rows = 3,
    this.accent = 0xFF7FE3D4,
    this.style = 'pill',
    this.report = '',
    this.track = '',
    this.artist = '',
    this.lyricLines = 0,
    this.lyricLabel = '',
    this.playing = false,
  });

  static const unknown = ClusterCastStatus();

  factory ClusterCastStatus.fromJson(Map<dynamic, dynamic> json) => ClusterCastStatus(
        enabled: json['enabled'] == true,
        displayId: _asInt(json['displayId'], -1),
        displayName: '${json['displayName'] ?? ''}',
        fontSp: _asDouble(json['fontSp'], 34),
        solidBackground: json['solidBackground'] != false,
        xRatio: _asDouble(json['xRatio'], 0.5),
        yRatio: _asDouble(json['yRatio'], 0.62),
        widthRatio: _asDouble(json['widthRatio'], 0.94),
        rows: _asInt(json['rows'], 3),
        accent: _asInt(json['accent'], 0xFF7FE3D4),
        style: '${json['style'] ?? 'pill'}',
        report: '${json['report'] ?? ''}',
        track: '${json['track'] ?? ''}',
        artist: '${json['artist'] ?? ''}',
        lyricLines: _asInt(json['lyricLines'], 0),
        lyricLabel: '${json['lyricLabel'] ?? ''}',
        playing: json['playing'] == true,
      );

  ClusterCastStatus copyWith({
    bool? enabled,
    int? displayId,
    String? displayName,
    double? fontSp,
    bool? solidBackground,
    double? xRatio,
    double? yRatio,
    double? widthRatio,
    int? rows,
    int? accent,
    String? style,
    String? report,
    String? track,
    String? artist,
    int? lyricLines,
    String? lyricLabel,
    bool? playing,
  }) =>
      ClusterCastStatus(
        enabled: enabled ?? this.enabled,
        displayId: displayId ?? this.displayId,
        displayName: displayName ?? this.displayName,
        fontSp: fontSp ?? this.fontSp,
        solidBackground: solidBackground ?? this.solidBackground,
        xRatio: xRatio ?? this.xRatio,
        yRatio: yRatio ?? this.yRatio,
        widthRatio: widthRatio ?? this.widthRatio,
        rows: rows ?? this.rows,
        accent: accent ?? this.accent,
        style: style ?? this.style,
        report: report ?? this.report,
        track: track ?? this.track,
        artist: artist ?? this.artist,
        lyricLines: lyricLines ?? this.lyricLines,
        lyricLabel: lyricLabel ?? this.lyricLabel,
        playing: playing ?? this.playing,
      );

  /// One line for the settings header: whether lyrics actually reached the panel.
  String get lyricSummary {
    if (!enabled) return '未开启';
    if (lyricLines > 0) {
      final source = lyricLabel.isEmpty ? '歌词' : lyricLabel;
      return '$source · $lyricLines 行 · ${track.isEmpty ? '当前曲目未命名' : track}';
    }
    if (track.isEmpty) return '等待播放';
    return '正在匹配「$track」的歌词';
  }
}

/// Client for the native lyric cast: lyrics painted on a display that is not the
/// launcher's own.
///
/// Everything here is configuration and reporting — the actual painting happens in
/// `ClusterLyricsService`, driven by the same `LyricCast` state the card reads, so the
/// fill edge on the cluster is the same one on the desktop. Flutter never sends frames.
class ClusterLyrics {
  static const MethodChannel channel =
      MethodChannel('xyz.i4o.uni.launcher/platform');

  const ClusterLyrics();

  /// Every attached display, launcher's own display included.
  Future<List<ClusterDisplay>> displays() async {
    try {
      final raw = await channel.invokeMethod<List<dynamic>>('clusterLyricsDisplays');
      if (raw == null) return const [];
      return raw
          .whereType<Map<dynamic, dynamic>>()
          .map(ClusterDisplay.fromJson)
          .toList(growable: false);
    } on PlatformException {
      return const [];
    } on MissingPluginException {
      return const [];
    }
  }

  Future<ClusterCastStatus> status() async {
    try {
      final raw = await channel.invokeMethod<Map<dynamic, dynamic>>('clusterLyricsStatus');
      if (raw == null) return ClusterCastStatus.unknown;
      return ClusterCastStatus.fromJson(raw);
    } on PlatformException {
      return ClusterCastStatus.unknown;
    } on MissingPluginException {
      return ClusterCastStatus.unknown;
    }
  }

  /// Persist the whole configuration and apply it.
  ///
  /// [display] of null turns the cast off. Everything else defaults to the value already in
  /// [ClusterCastStatus.unknown], so a caller that only moves the panel does not have to
  /// repeat the font, the rows or the accent.
  Future<ClusterCastStatus> apply({
    ClusterDisplay? display,
    double fontSp = 34,
    bool solidBackground = true,
    double xRatio = 0.5,
    double yRatio = 0.62,
    double widthRatio = 0.94,
    int rows = 3,
    int accent = 0xFF7FE3D4,
    String style = 'pill',
  }) async {
    try {
      final raw = await channel.invokeMethod<Map<dynamic, dynamic>>('clusterLyricsApply', {
        'enabled': display != null,
        'displayId': display?.id ?? -1,
        'displayName': display?.name ?? '',
        'fontSp': fontSp,
        'solidBackground': solidBackground,
        'xRatio': xRatio,
        'yRatio': yRatio,
        'widthRatio': widthRatio,
        'rows': rows,
        'accent': accent,
        'style': style,
      });
      if (raw == null) return ClusterCastStatus.unknown;
      return ClusterCastStatus.fromJson(raw);
    } on PlatformException catch (error) {
      return ClusterCastStatus.unknown.copyWith(report: error.message ?? '投射控制失败');
    } on MissingPluginException {
      return ClusterCastStatus.unknown.copyWith(report: '原生投射服务不可用');
    }
  }
}

