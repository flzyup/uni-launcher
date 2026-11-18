import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';

/// 兜底封面（也用于示例模式）：稿子那张暗紫同心圆，左上角 NOCTURNE，没有曲目文字。
///
/// 读不到原车封面时以前画的是一颗 48px 的音符图标，在一整块封面格里看着像「空白」
/// （用户 2026-11-13 实车反馈）。原图的「昼夜电台 / 环线」两块字已经抹掉，免得跟
/// 真实曲目对不上。
const _fallbackCover = 'assets/art/cover-default.png';

class MediaArtwork extends StatefulWidget {
  final Map<String, dynamic> media;
  final bool demo;
  const MediaArtwork({super.key, required this.media, required this.demo});
  @override
  State<MediaArtwork> createState() => _MediaArtworkState();
}

class _MediaArtworkState extends State<MediaArtwork> {
  String encoded = '';
  Uint8List? bytes;

  void evictArtwork() {
    final previous = bytes;
    if (previous != null) {
      PaintingBinding.instance.imageCache
          .evict(MemoryImage(previous), includeLive: false);
    }
  }

  @override
  void dispose() {
    evictArtwork();
    bytes = null;
    encoded = '';
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final value = !widget.demo && widget.media['artwork'] is String
        ? widget.media['artwork'] as String
        : '';
    if (value != encoded) {
      evictArtwork();
      encoded = value;
      try {
        bytes = value.length < 1000000 ? base64Decode(value) : null;
      } catch (_) {
        bytes = null;
      }
    }
    // 示例模式与「读不到封面」共用同一张兜底图。
    Widget fallback() => Image.asset(_fallbackCover,
        fit: BoxFit.cover,
        gaplessPlayback: true,
        filterQuality: FilterQuality.medium);
    if (widget.demo) return fallback();
    if (bytes == null || bytes!.isEmpty) return fallback();
    return Image.memory(bytes!,
        fit: BoxFit.cover,
        gaplessPlayback: true,
        errorBuilder: (_, error, stack) => fallback());
  }
}
