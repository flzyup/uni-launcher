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
  final bool compact;
  const _MusicMetadata(
      {required this.title,
      required this.artist,
      required this.album,
      this.compact = false});
  @override
  Widget build(BuildContext context) {
    final s = SurfaceStyle.of(context);
    return Column(
        key: const ValueKey('music-card-metadata'),
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: Design.px(compact ? 25 : 30),
                  height: 1.2,
                  fontWeight: FontWeight.w500)),
          SizedBox(height: Design.px(compact ? 6 : 10)),
          Text(artist,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: Design.px(compact ? 17 : 20), color: s.muted)),
          if (album.isNotEmpty) ...[
            SizedBox(height: Design.px(4)),
            Text(album,
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
    final lyrics = (card.w == 4 && card.h == 4) || (card.w == 8 && card.h == 6);
    final large = card.w == 8 && card.h == 6;
    final metadata = _MusicMetadata(
        title: _mediaValue(state, 'title', '向海而行', '暂无播放'),
        artist: _mediaValue(state, 'artist', 'Coastline', '等待媒体会话'),
        album: _mediaValue(state, 'collection', '晨间驾驶歌单', ''),
        compact: compact);
    final spectrum = AudioSpectrum(
        playing: !demo && media['playing'] == true,
        height: compact
            ? 24
            : large
                ? 58
                : 34);
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
                        onTap: controller.editing
                            ? null
                            : () => showMusicPicker(context, controller)),
                  ]),
                  SizedBox(height: Design.px(compact ? 10 : 16)),
                  Expanded(child: LayoutBuilder(builder: (context, box) {
                    final cover = Design.px(compact
                        ? 86
                        : large
                            ? 260
                            : 132);
                    if (!lyrics) {
                      return Row(children: [
                        _MediaCover(demo: demo, size: cover, media: media),
                        SizedBox(width: Design.px(compact ? 16 : 22)),
                        Expanded(
                            child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                              metadata,
                              SizedBox(height: Design.px(compact ? 6 : 12)),
                              spectrum,
                            ])),
                      ]);
                    }
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
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            _MediaCover(
                                                demo: demo,
                                                size: cover,
                                                media: media),
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
                                spectrum,
                                SizedBox(height: Design.px(12)),
                                Flexible(
                                    child: Center(
                                        key:
                                            const ValueKey('music-card-lyrics'),
                                        child: LyricsView(
                                            media: media,
                                            visibleLines: large ? 7 : 5,
                                            lineHeight: large ? 48 : 32,
                                            fontSize: large ? 28 : 21,
                                            textAlign: TextAlign.start))),
                              ])),
                    ]);
                  })),
                  if (!compact) ...[
                    SizedBox(height: Design.px(10)),
                    MediaProgress(
                        media: media,
                        onSeek: (v) => controller.command('seek', value: '$v')),
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
                              onTap: available &&
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
