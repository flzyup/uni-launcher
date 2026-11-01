part of 'card_content.dart';

String _mediaValue(
    Map<String, dynamic> state, String key, String demoValue, String waiting) {
  final value = mapOf(state['media'])[key]?.toString().trim() ?? '';
  return value.isNotEmpty
      ? value
      : state['demo'] == true
          ? demoValue
          : waiting;
}

String mediaSourceLabel(Map<String, dynamic> state) {
  if (state['demo'] == true) return '媒体播放示例';
  final media = mapOf(state['media']);
  final preferred = mapOf(state['integrationPreferences'])['mediaPackage'];
  final source = media['source'] ?? (preferred == 'auto' ? null : preferred);
  for (final raw in state['apps'] is List ? state['apps'] as List : const []) {
    final app = mapOf(raw);
    if (app['package'] == source && source != null)
      return '${app['label'] ?? source}';
  }
  final label = media['sourceLabel'];
  if (label is String && label.isNotEmpty) return label;
  return source?.toString() ?? '音乐播放器';
}

class _MediaCover extends StatelessWidget {
  final bool demo;
  final double size;
  final Map<String, dynamic> media;
  const _MediaCover(
      {required this.demo, required this.size, required this.media});
  @override
  Widget build(BuildContext context) {
    final s = SurfaceStyle.of(context);
    return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(s.radius * .93),
            boxShadow: [
              BoxShadow(
                  color: s.shadow,
                  offset: Offset(0, Design.px(18)),
                  blurRadius: Design.px(40))
            ]),
        child: ClipRRect(
            borderRadius: BorderRadius.circular(s.radius * .93),
            child: MediaArtwork(media: media, demo: demo)));
  }
}

class _MusicMetadata extends StatelessWidget {
  final String title, artist, album;
  final bool compact, centered;
  const _MusicMetadata(
      {required this.title,
      required this.artist,
      required this.album,
      this.compact = false,
      this.centered = false});
  @override
  Widget build(BuildContext context) {
    final s = SurfaceStyle.of(context);
    return Column(
        key: const ValueKey('music-card-metadata'),
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment:
            centered ? CrossAxisAlignment.center : CrossAxisAlignment.start,
        children: [
          Text(title,
              textAlign: centered ? TextAlign.center : TextAlign.start,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: Design.px(compact ? 25 : 30),
                  height: 1.2,
                  fontWeight: FontWeight.w500)),
          SizedBox(height: Design.px(compact ? 6 : 10)),
          Text(artist,
              textAlign: centered ? TextAlign.center : TextAlign.start,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: Design.px(compact ? 17 : 20), color: s.muted)),
          if (album.isNotEmpty) ...[
            SizedBox(height: Design.px(4)),
            Text(album,
                textAlign: centered ? TextAlign.center : TextAlign.start,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: Design.px(compact ? 16 : 18), color: s.muted)),
          ],
        ]);
  }
}

class _MusicCard extends StatelessWidget {
  final LauncherCard card;
  final LauncherController controller;
  final Map<String, dynamic> state;
  const _MusicCard(
      {required this.card, required this.controller, required this.state});

  @override
  Widget build(BuildContext context) {
    final demo = state['demo'] == true, media = mapOf(state['media']);
    final compact = card.h <= 2;
    final tall = card.w == 4 && card.h >= 5;
    final lyricCard =
        (card.w == 4 && card.h >= 4) || (card.w == 8 && card.h == 6);
    final large = card.w == 8 && card.h == 6;
    final metadata = _MusicMetadata(
        title: _mediaValue(state, 'title', '向海而行', '暂无播放'),
        artist: _mediaValue(state, 'artist', 'Coastline', '等待媒体会话'),
        album: _mediaValue(state, 'collection', '晨间驾驶歌单', ''),
        compact: compact || tall,
        centered: card.w == 4 && card.h == 4);
    final double spectrumHeight = compact
        ? 0.0
        : tall
            ? (card.h >= 6 ? 54 : 46)
            : card.w == 4 && card.h == 4
                ? 40
                : large
                    ? 58
                    : 34;
    final spectrum = compact
        ? const SizedBox.shrink(key: ValueKey('music-card-spectrum-disabled'))
        : AudioSpectrum(
            playing: !demo && media['playing'] == true,
            height: spectrumHeight,
          );
    Widget heading() => AnimatedBuilder(
        animation: controller,
        builder: (context, _) => controller.editing
            ? const SizedBox.shrink()
            : Column(children: [
                Row(children: [
                  Expanded(
                      child: MediaSourceBadge(
                          controller: controller,
                          titleBar: true,
                          compact: true)),
                  IconAction(
                      key: const ValueKey('music-app-picker'),
                      icon: Icons.swap_horiz,
                      label: '选择音乐应用',
                      size: Design.px(38),
                      onTap: () => showMusicPicker(context, controller)),
                ]),
                SizedBox(height: Design.px(compact ? 10 : 16)),
              ]));

    const lyricRowHeight = 44.0;
    const lyricFontSize = 26.0;
    int lyricLines(double height, int maximum) {
      var lines =
          (height / Design.px(lyricRowHeight)).floor().clamp(1, maximum);
      if (lines > 1 && lines.isEven) lines--;
      return lines;
    }

    Widget lyricsView(int lines, double fontSize) => Center(
        key: const ValueKey('music-card-lyrics'),
        child: ShaderMask(
            key: const ValueKey('music-card-lyrics-fade'),
            blendMode: BlendMode.dstIn,
            shaderCallback: (bounds) {
              final edge = bounds.height > 0
                  ? (Design.px(24) / bounds.height).clamp(0.0, .2)
                  : 0.0;
              return LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: const [
                  Colors.transparent,
                  Colors.white,
                  Colors.white,
                  Colors.transparent
                ],
                stops: [0, edge, 1 - edge, 1],
              ).createShader(bounds);
            },
            child: LyricsView(
                media: media,
                visibleLines: lines,
                lineHeight: lyricRowHeight,
                fontSize: fontSize,
                textAlign: TextAlign.center)));

    Widget body(BoxConstraints box) {
      final compactCover = Design.px(compact
          ? 86
          : tall
              ? 104
              : 132);
      if (compact) {
        return Row(children: [
          _MediaCover(demo: demo, size: compactCover, media: media),
          SizedBox(width: Design.px(16)),
          Expanded(child: metadata),
        ]);
      }
      if (tall) {
        return Column(children: [
          Row(children: [
            _MediaCover(demo: demo, size: compactCover, media: media),
            SizedBox(width: Design.px(18)),
            Expanded(child: metadata),
          ]),
          SizedBox(height: Design.px(6)),
          Expanded(child: LayoutBuilder(builder: (context, constraints) {
            return lyricsView(
                lyricLines(constraints.maxHeight, 21), lyricFontSize);
          })),
          SizedBox(height: Design.px(6)),
          spectrum,
        ]);
      }
      if (card.w == 4 && card.h == 4) {
        return Row(children: [
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Expanded(child: LayoutBuilder(builder: (context, constraints) {
                  final size = constraints.biggest.shortestSide;
                  return Center(
                      child: _MediaCover(demo: demo, size: size, media: media));
                })),
                SizedBox(height: Design.px(8)),
                Center(child: metadata),
              ])),
          SizedBox(width: Design.px(16)),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                Expanded(child: LayoutBuilder(builder: (context, constraints) {
                  return lyricsView(
                      lyricLines(constraints.maxHeight, 11), lyricFontSize);
                })),
                SizedBox(height: Design.px(6)),
                spectrum,
              ])),
        ]);
      }
      if (!lyricCard) {
        return Row(children: [
          _MediaCover(demo: demo, size: compactCover, media: media),
          SizedBox(width: Design.px(22)),
          Expanded(
              child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                metadata,
                SizedBox(height: Design.px(12)),
                spectrum
              ]))
        ]);
      }
      final largeCover = Design.px(260);
      return Row(children: [
        Expanded(
            flex: 4,
            child: Center(
                child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: SizedBox(
                        width: box.maxWidth * 4 / 9,
                        child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _MediaCover(
                                  demo: demo, size: largeCover, media: media),
                              SizedBox(height: Design.px(18)),
                              metadata,
                            ]))))),
        SizedBox(width: Design.px(26)),
        Expanded(
            flex: 5,
            child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: lyricsView(7, lyricFontSize)),
                  SizedBox(height: Design.px(12)),
                  spectrum,
                ])),
      ]);
    }

    return _CardCanvas(
        minHeight: compact
            ? 190
            : card.h == 3
                ? 290
                : 320,
        child: GestureDetector(
            key: const ValueKey('music-card-open-panel'),
            behavior: HitTestBehavior.opaque,
            onTap: controller.editing
                ? null
                : () => showMediaPanel(context, controller),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  heading(),
                  Expanded(
                      child:
                          LayoutBuilder(builder: (context, box) => body(box))),
                  if (!compact) ...[
                    SizedBox(height: Design.px(10)),
                    MediaProgress(
                        media: media,
                        onSeek: (v) =>
                            controller.command('seek', value: '${'$v'}')),
                  ],
                ])));
  }
}

class MediaPanel extends StatelessWidget {
  final LauncherController controller;
  const MediaPanel({super.key, required this.controller});
  @override
  Widget build(BuildContext context) => ValueListenableBuilder<
          Map<String, dynamic>>(
      valueListenable: controller.native,
      builder: (context, state, _) {
        final s = SurfaceStyle.of(context), m = mapOf(state['media']);
        final demo = state['demo'] == true,
            available = demo || m['available'] == true;
        final artist = _mediaValue(state, 'artist', 'Coastline', '等待媒体会话');
        final collection = _mediaValue(state, 'collection', '晨间驾驶歌单', '');
        return SingleChildScrollView(
            key: const ValueKey('media-panel-content'),
            child: Padding(
                padding: EdgeInsets.symmetric(vertical: Design.px(25)),
                child: Column(children: [
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    _MediaCover(demo: demo, size: Design.px(260), media: m),
                    SizedBox(width: Design.px(44)),
                    Expanded(
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                          Text(_mediaValue(state, 'title', '向海而行', '暂无播放'),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontSize: Design.px(42), height: 1.2)),
                          SizedBox(height: Design.px(18)),
                          Text(
                              [artist, if (collection.isNotEmpty) collection]
                                  .join(' · '),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontSize: Design.px(22),
                                  height: 1.4,
                                  color: s.muted)),
                          SizedBox(height: Design.px(20)),
                          AudioSpectrum(
                              playing: !demo && m['playing'] == true,
                              height: 48),
                          SizedBox(height: Design.px(16)),
                          LyricsView(media: m),
                          SizedBox(height: Design.px(20)),
                          MediaProgress(
                              media: m,
                              onSeek: (v) =>
                                  controller.command('seek', value: '$v')),
                        ])),
                  ]),
                  SizedBox(height: Design.px(26)),
                  Row(
                      key: const ValueKey('media-transport-controls'),
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        for (final action in [
                          'previous',
                          'toggle-play',
                          'next'
                        ]) ...[
                          if (action != 'previous')
                            SizedBox(width: Design.px(24)),
                          IconAction(
                              icon: action == 'previous'
                                  ? Icons.skip_previous_outlined
                                  : action == 'next'
                                      ? Icons.skip_next_outlined
                                      : m['playing'] == true
                                          ? Icons.pause
                                          : Icons.play_arrow,
                              label: action == 'previous'
                                  ? '上一首'
                                  : action == 'next'
                                      ? '下一首'
                                      : m['playing'] == true
                                          ? '暂停'
                                          : '播放',
                              solid: action == 'toggle-play',
                              size: Design.px(58),
                              iconSize: Design.px(28),
                              onTap: (action == 'toggle-play' && !available)
                                  ? () => controller.command(action)
                                  : available &&
                                          (demo ||
                                              m[action == 'next'
                                                      ? 'canNext'
                                                      : action == 'previous'
                                                          ? 'canPrevious'
                                                          : 'canToggle'] ==
                                                  true)
                                      ? () => controller.command(action)
                                      : null),
                        ],
                      ]),
                ])));
      });
}
