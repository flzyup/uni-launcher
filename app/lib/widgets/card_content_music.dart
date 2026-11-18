part of 'card_content.dart';

String _mediaValue(
    Map<String, dynamic> state, String key, String demoValue, String waiting) {
  final value = mapOf(state['media'])[key]?.toString().trim() ?? '';
  return value.isNotEmpty
      ? value
      : mediaIsDemo(state)
          ? demoValue
          : waiting;
}

String mediaSourceLabel(Map<String, dynamic> state) {
  if (mediaIsDemo(state)) return '媒体播放示例';
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

  /// 圆角；不传沿用卡片圆角的 .93 倍（稿子音乐的封面是 22）。
  final double? radius;

  /// 封面投影颜色；不传用卡片阴影。稿子音乐卡是粉色光晕。
  final Color? glow;
  const _MediaCover(
      {required this.demo,
      required this.size,
      required this.media,
      this.radius,
      this.glow});
  @override
  Widget build(BuildContext context) {
    final s = SurfaceStyle.of(context);
    final corner = radius ?? s.radius * .93;
    return RepaintBoundary(
        child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(corner),
                boxShadow: [
                  BoxShadow(
                      color: glow ?? s.shadow,
                      offset: Offset(0, Design.px(8)),
                      blurRadius: Design.px(16))
                ]),
            child: ClipRRect(
                borderRadius: BorderRadius.circular(corner),
                child: MediaArtwork(media: media, demo: demo))));
  }
}

/// 稿子 `.mu-tags` 那三颗音质标签：VIP / SQ / Hi-Res。
///
/// **静态装饰**：原车 MediaSession 只给 title/artist/album/artwork/position，没有
/// 音质字段（码率、母带、无损格式都拿不到），这三颗是按稿子配色画出来的样子货，
/// 不代表当前曲目的真实音质。卡片与播放器弹层共用同一份。
class _MediaTags extends StatelessWidget {
  /// 缩放：卡片按可用宽度等比缩，弹层是 1。
  final double scale;
  const _MediaTags({this.scale = 1});

  /// 稿子三色（金 / 薄荷 / 钢蓝）配边线与底色，`.lmini` 那一档的字距也照抄。
  static const _tags = [
    ('VIP', 0xFFD8AE5C, .46, .07, .12),
    ('SQ', 0xFF3BDCC0, .42, .07, .12),
    ('Hi-Res', 0xFFAFC0D2, .34, .05, .06),
  ];

  @override
  Widget build(BuildContext context) {
    final s = SurfaceStyle.of(context);
    return Wrap(
        spacing: Design.dz(8) * scale,
        runSpacing: Design.dz(6) * scale,
        children: [
          for (final (label, hex, border, background, spacing) in _tags)
            Container(
                key: ValueKey('music-quality-$label'),
                padding: EdgeInsets.symmetric(
                    horizontal: Design.dz(9) * scale,
                    vertical: Design.dz(4) * scale),
                decoration: BoxDecoration(
                    color: _tint(s, hex).withValues(alpha: background),
                    borderRadius: BorderRadius.circular(Design.dz(7) * scale),
                    border: Border.all(
                        color: _tint(s, hex).withValues(alpha: border))),
                child: Text(label,
                    style: TextStyle(
                        fontSize: Design.dz(10.5) * scale,
                        height: 1.2,
                        letterSpacing: Design.dz(10.5 * spacing) * scale,
                        color: _tint(s, hex).withValues(alpha: .95))))
        ]);
  }

  /// 稿子的三色是按暗底调的：浅色皮肤上薄荷与钢蓝会糊，往正文墨色压深一档。
  Color _tint(SurfaceStyle s, int hex) =>
      s.dark ? Color(hex) : Color.lerp(Color(hex), s.text, .35)!;
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
          MarqueeText(
              key: const ValueKey('music-card-title'),
              data: title,
              textAlign: centered ? TextAlign.center : TextAlign.start,
              style: TextStyle(
                  fontSize: Design.px(compact ? 25 : 30),
                  height: 1.2,
                  fontWeight: FontWeight.w500)),
          SizedBox(height: Design.px(compact ? 6 : 10)),
          MarqueeText(
              key: const ValueKey('music-card-artist'),
              data: artist,
              textAlign: centered ? TextAlign.center : TextAlign.start,
              style: TextStyle(
                  fontSize: Design.px(compact ? 17 : 20), color: s.muted)),
          if (album.isNotEmpty) ...[
            SizedBox(height: Design.px(4)),
            MarqueeText(
                key: const ValueKey('music-card-album'),
                data: album,
                textAlign: centered ? TextAlign.center : TextAlign.start,
                style: TextStyle(
                    fontSize: Design.px(compact ? 16 : 18), color: s.muted)),
          ],
        ]);
  }
}

/// 两行档（`h <= 2`）右侧那颗圆形播放/暂停键。
///
/// 稿子这两行版式只给了封面 + 标题/歌手/专辑，没有可点的传输键——缩到两行时
/// 想暂停得点整张卡进播放器弹层，多一步。这里补一颗 `.mu-act` 那种圆键：
/// 外圈细环 + 实心圆底，跟随皮肤 accent（暗夜薄荷 / 经典墨绿 / 蓝玻璃靛蓝）。
/// 状态取自原生媒体会话的 `playing`，点击走 `toggle-play` 通道，和底栏、弹层一致。
class _CompactPlayButton extends StatelessWidget {
  final bool playing, enabled;
  final VoidCallback onTap;

  /// 直径；不传用 62（稿子 `.mu-act` 是 64，收 2 是为了跟红绿灯环的 60 齐平）。
  /// 一格档按卡高算，传一个更小的值。
  final double? size;
  const _CompactPlayButton(
      {super.key,
      required this.playing,
      required this.enabled,
      required this.onTap,
      this.size});

  @override
  Widget build(BuildContext context) {
    final s = SurfaceStyle.of(context);
    // 62 是照着红绿灯那颗环（`.tlg-c` 外径 60）定的：这颗键减掉 5 内衬与
    // 1.6 描边后，实心圆约 51，比环内实心区（60-11=49）略大，两块并排才齐。
    // 原来 4×2 档写的是 px(64)=53.3，实心圆只有 43，比旁边那颗环小一圈。
    final side = size ?? Design.dz(62), ring = Design.px(1.6);
    final fill = enabled ? s.accent : s.soft;
    final icon = enabled ? s.accentText : s.disabled;
    return Tooltip(
        message: playing ? '暂停' : '播放',
        child: Semantics(
            button: true,
            enabled: enabled,
            label: playing ? '暂停' : '播放',
            child: SizedBox(
                width: side,
                height: side,
                child: Material(
                    color: Colors.transparent,
                    shape: const CircleBorder(),
                    child: InkWell(
                        customBorder: const CircleBorder(),
                        onTap: enabled ? onTap : null,
                        child: Container(
                            padding: EdgeInsets.all(Design.px(5)),
                            decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                    color: fill.withValues(
                                        alpha: enabled ? .3 : .16),
                                    width: ring)),
                            child: DecoratedBox(
                                decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: fill,
                                    boxShadow: enabled && playing
                                        ? [
                                            BoxShadow(
                                                color: s.accent
                                                    .withValues(alpha: .34),
                                                blurRadius: Design.px(18))
                                          ]
                                        : null),
                                child: Center(
                                    child: Icon(
                                        playing
                                            ? Icons.pause
                                            : Icons.play_arrow,
                                        // 稿子 30 / 64 = .47，按直径走，
                                        // 一格档缩小时图标跟着缩。
                                        size: side * .47,
                                        color: icon)))))))));
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
    // 铺满档：网格把这张卡铺到整块桌面区域（desktop.dart 的 _CardFocus 会把它
    // 归一成 12×6），版式换成稿子 f5 那套。
    if (card.w >= 12) return _MusicCardFull(controller: controller);
    final demo = mediaIsDemo(state), media = mapOf(state['media']);
    final compact = card.h <= 2;
    // 一格外档（4×1）：卡高只有 ~100 逻辑像素，卡头和 86 的封面都放不下。
    // 这一档不画卡头，封面按卡高算，只留「封面 + 曲目 + 播放键」一行。
    final bare = card.h <= 1;
    // 稿子 f1 给的是 4×4（502×482）：封面 + 信息块在上、迷你歌词窗在中、细进度条
    // 与音柱贴在底下。4×5 / 4×6 只是多给歌词行，8×6 太宽仍走两列。
    final draft = card.w == 4 && card.h >= 4;
    final large = card.w == 8 && card.h == 6;
    final lyricCard = draft || large;
    final metadata = _MusicMetadata(
        title: _mediaValue(state, 'title', '午夜立交', '暂无播放'),
        artist: _mediaValue(state, 'artist', '昼夜电台', '等待媒体会话'),
        album: _mediaValue(state, 'collection', '环线', ''),
        compact: compact,
        centered: false);
    final double spectrumHeight = compact
        ? 0.0
        : draft
            ? 34
            : card.h == 3
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
    // 稿子 f1 这张卡没有卡片头：来源应用在播放器弹层里看，换应用也挪到弹层右上角
    // 那颗 `.mu-act` 去了（卡片上留那两颗键等于同一件事做两遍）。
    Widget heading() => AnimatedBuilder(
        animation: controller,
        builder: (context, _) => controller.editing || draft || bare
            ? const SizedBox.shrink()
            : Column(children: [
                Row(children: [
                  Expanded(
                      child: MediaSourceBadge(
                          controller: controller,
                          titleBar: true,
                          compact: true)),
                ]),
                SizedBox(height: Design.px(compact ? 10 : 16)),
              ]));

    const lyricRowHeight = 44.0;
    const lyricFontSize = 26.0;

    Widget lyricsView(int lines, double fontSize) => Center(
        key: const ValueKey('music-card-lyrics'),
        child: RepaintBoundary(
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
                    textAlign: TextAlign.center))));

    /// 稿子 `.lmini`：左侧 2px 渐变竖线 + 上下淡出的迷你歌词窗。
    Widget miniLyrics(BuildContext context, double height, double k) {
      final s = SurfaceStyle.of(context);
      final normalSize = Design.dz(17.5) * k, activeSize = Design.dz(25) * k;
      final normalRow = Design.dz(29) * k, activeRow = Design.dz(41) * k;
      // 稿子窗口 154 = 29 + 29 + 41 + 29 再加一点余量；高卡多给几行。
      final lines =
          height <= 0 ? 3 : ((height - activeRow) / normalRow).floor() + 1;
      return RepaintBoundary(
          child: Stack(children: [
        Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            child: Container(
                width: Design.dz(2) * k,
                decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(Design.dz(1) * k),
                    gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          s.accent.withValues(alpha: 0),
                          s.accent.withValues(alpha: .24),
                          s.accent.withValues(alpha: .48),
                          s.accent.withValues(alpha: .24),
                          s.accent.withValues(alpha: 0)
                        ],
                        stops: const [
                          0,
                          .22,
                          .5,
                          .78,
                          1
                        ])))),
        Padding(
            padding: EdgeInsets.only(left: Design.dz(19) * k),
            child: ShaderMask(
                key: const ValueKey('music-card-lyrics-fade'),
                blendMode: BlendMode.dstIn,
                shaderCallback: (bounds) => const LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.transparent,
                        Colors.white,
                        Colors.white,
                        Colors.transparent
                      ],
                      stops: [0, .11, .84, 1],
                    ).createShader(bounds),
                child: Center(
                    child: LyricsView(
                        key: const ValueKey('music-card-lyrics'),
                        media: media,
                        mini: true,
                        visibleLines: lines.clamp(3, 7),
                        lineHeight: normalRow,
                        fontSize: normalSize,
                        activeFontSize: activeSize,
                        activeLineHeight: activeRow,
                        textAlign: TextAlign.start)))),
      ]));
    }

    /// 稿子 f1 的 4×4：封面 150（`.mu-cv`）+ 右侧标题 24 / 副标题 14.5（`mu-info`）
    /// + 迷你歌词（`.lmini`）+ 3px 进度条（`mu-prog`）+ 底部音柱（`.wave`）。
    /// 稿子按 502×482 排，这里按可用宽度等比缩放。
    Widget draftBody(BuildContext context, BoxConstraints box,
        Map<String, dynamic> media, bool demo) {
      final s = SurfaceStyle.of(context);
      final k = (box.maxWidth / Design.dz(442)).clamp(.7, 1.25);
      final artist = _mediaValue(state, 'artist', '昼夜电台', '等待媒体会话');
      final album = _mediaValue(state, 'collection', '环线', '');
      final subtitle =
          [artist, album].where((value) => value.isNotEmpty).join(' · ');
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _MediaCover(
              demo: demo,
              size: Design.dz(150) * k,
              media: media,
              radius: Design.dz(22) * k,
              glow: s.cardGlow('music') ?? s.shadow),
          SizedBox(width: Design.dz(16) * k),
          Expanded(
              child: Padding(
                  padding: EdgeInsets.only(top: Design.dz(8) * k),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        MarqueeText(
                            key: const ValueKey('music-card-title'),
                            data: _mediaValue(state, 'title', '午夜立交', '暂无播放'),
                            style: TextStyle(
                                fontSize: Design.dz(24) * k,
                                height: 1.2,
                                fontWeight: FontWeight.w500)),
                        SizedBox(height: Design.dz(7) * k),
                        MarqueeText(
                            key: const ValueKey('music-card-artist'),
                            data: subtitle,
                            style: TextStyle(
                                fontSize: Design.dz(14.5) * k, color: s.muted)),
                        SizedBox(height: Design.dz(12) * k),
                        // 静态装饰标签，见 _MediaTags 注释。
                        _MediaTags(scale: k),
                      ]))),
        ]),
        SizedBox(height: Design.dz(18) * k),
        Expanded(
            child: LayoutBuilder(
                builder: (context, inner) =>
                    miniLyrics(context, inner.maxHeight, k))),
        SizedBox(height: Design.dz(8) * k),
        RepaintBoundary(
            child: MediaProgress(
                dense: true,
                media: media,
                onSeek: (v) => controller.command('seek', value: '$v'))),
        SizedBox(height: Design.dz(8) * k),
        // AudioSpectrum 的 height 走 1920 稿面单位（内部再乘 1600/1920），
        // 这里要的是卡片按 k 缩放后的逻辑像素，所以再乘回去。
        AudioSpectrum(
            playing: !demo && media['playing'] == true,
            height:
                spectrumHeight * k * Design.artworkWidth / Design.canvasWidth),
      ]);
    }

    Widget body(BoxConstraints box) {
      final compactCover = Design.px(compact ? 86 : 132);
      if (bare) {
        // 一格档：所有尺寸按卡高反推，不写死。封面直接吃满可用高度（上下只留
        // 6 画布的内边距），否则 4 格宽的一行里封面会缩成一小块；播放键缩到
        // 封面七成，跟封面重新构成一条水平的东西，而不是一小一大两块。
        final s = SurfaceStyle.of(context);
        final side = math.min(box.maxHeight, Design.px(120));
        // 播放键对齐红绿灯那颗环的量级（环外径 60），一格档里两颗圆并排看着
        // 一样大；上限 62 而不是 px(56)=46.7——那个值实心圆只剩 36，比环小一圈。
        // 比例 .78 照旧管着编辑态被压矮时跟着缩，FittedBox 再兜一层。
        final play = math.min(side * .78, Design.dz(62));
        final artist = _mediaValue(state, 'artist', '昼夜电台', '等待媒体会话');
        final album = _mediaValue(state, 'collection', '环线', '');
        final subtitle =
            [artist, album].where((value) => value.isNotEmpty).join(' · ');
        // 标题只放两行：一行档的高度放三行会把字缩到看不清，专辑并进副标题。
        // 下限 20 画布是给编辑态留的——拖动条吃掉一截高度后，字号再往下掉就
        // 只剩一团糊字，FittedBox 会兜住那点溢出。
        final titleSize = (box.maxHeight * .26)
            .clamp(Design.px(20), Design.px(28))
            .toDouble();
        final canToggle = media['canToggle'] == true;
        final textWidth = math.max(Design.px(40),
            box.maxWidth - side - Design.px(16) - play - Design.px(12));
        return Row(children: [
          _MediaCover(demo: demo, size: side, media: media),
          SizedBox(width: Design.px(16)),
          // 文字块外包一层 FittedBox：编辑态卡顶要让出 64 画布给拖动条，
          // 内容区只剩 ~40 px，两行字按卡高算出来的字号仍会顶出 2.6 px。
          // 正常态不缩放（内容本来就比可用高度矮），压缩时才等比缩。
          Expanded(
              child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: SizedBox(
                      width: textWidth,
                      child: Column(
                          key: const ValueKey('music-card-metadata'),
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            MarqueeText(
                                key: const ValueKey('music-card-title'),
                                data:
                                    _mediaValue(state, 'title', '午夜立交', '暂无播放'),
                                style: TextStyle(
                                    fontSize: titleSize,
                                    height: 1.2,
                                    fontWeight: FontWeight.w500)),
                            SizedBox(height: Design.px(6)),
                            MarqueeText(
                                key: const ValueKey('music-card-artist'),
                                data: subtitle,
                                style: TextStyle(
                                    fontSize: titleSize * .68, color: s.muted)),
                          ])))),
          SizedBox(width: Design.px(12)),
          // 播放键用 FittedBox 兜一层：卡再被压矮时跟着缩，不会顶出边界。
          FittedBox(
              fit: BoxFit.scaleDown,
              child: _CompactPlayButton(
                  key: const ValueKey('music-card-compact-play'),
                  size: play,
                  playing: !demo && media['playing'] == true,
                  enabled: demo || (media['available'] == true && canToggle),
                  onTap: () => controller.command('toggle-play'))),
        ]);
      }
      if (compact) {
        // 两行档补一颗播放/暂停键：不然想暂停只能点进播放器弹层。
        // 可用性判定跟 MediaPanel 的 toggle-play 保持同一套（demo 视为可用）。
        final canToggle = media['canToggle'] == true;
        return Row(children: [
          _MediaCover(demo: demo, size: compactCover, media: media),
          SizedBox(width: Design.px(16)),
          Expanded(child: metadata),
          SizedBox(width: Design.px(14)),
          _CompactPlayButton(
              key: const ValueKey('music-card-compact-play'),
              playing: !demo && media['playing'] == true,
              enabled: demo || (media['available'] == true && canToggle),
              onTap: () => controller.command('toggle-play')),
        ]);
      }
      if (draft) return draftBody(context, box, media, demo);
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
        // 一格档按真实尺寸排版：minHeight 190 是「卡头 + 一行内容」的基准，
        // 卡高只有 ~100 px 时走 FittedBox 会被整体缩到一半，封面和字反而更小。
        // minWidth 同理——这个尺寸的卡不需要等比兜底。
        minWidth: bare ? 0 : 340,
        minHeight: bare
            ? 0
            : (compact
                ? 190
                : card.h == 3
                    ? 290
                    : 320),
        padded: !bare,
        child: GestureDetector(
            key: const ValueKey('music-card-open-panel'),
            behavior: HitTestBehavior.opaque,
            onTap: controller.editing
                ? null
                : () => showMusicPlayer(context, controller, cardId: card.id),
            child: bare
                ? Padding(
                    // 一格高的卡只有 ~100 px：28 的上下留白会吃掉一半，
                    // 水平也收到 14，让封面和标题占满整行。
                    padding: EdgeInsets.symmetric(
                        horizontal: Design.px(14), vertical: Design.px(6)),
                    child: LayoutBuilder(builder: (context, box) => body(box)))
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                        heading(),
                        Expanded(
                            child: LayoutBuilder(
                                builder: (context, box) => body(box))),
                        if (!compact && !draft) ...[
                          SizedBox(height: Design.px(10)),
                          RepaintBoundary(
                              child: MediaProgress(
                                  media: media,
                                  onSeek: (v) =>
                                      controller.command('seek', value: '$v'))),
                        ],
                      ])));
  }
}

class MediaPanel extends StatelessWidget {
  final LauncherController controller;
  const MediaPanel({super.key, required this.controller});
  @override
  Widget build(BuildContext context) => NativeSliceBuilder(
      valueListenable: controller.native,
      select: (state) => [
            state['demo'],
            state['mediaDemo'],
            state['media'],
            state['apps'],
            state['appNames'],
          ],
      builder: (context, state) {
        final s = SurfaceStyle.of(context), m = mapOf(state['media']);
        final demo = mediaIsDemo(state),
            available = demo || m['available'] == true;
        final artist = _mediaValue(state, 'artist', '昼夜电台', '等待媒体会话');
        final collection = _mediaValue(state, 'collection', '环线', '');
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
                          Text(_mediaValue(state, 'title', '午夜立交', '暂无播放'),
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
                          SizedBox(height: Design.px(18)),
                          // 稿子 f5 `.tags` 与卡片同一套静态标签。
                          const _MediaTags(scale: 2),
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
