part of 'card_content.dart';

/// 稿子 f5 里音乐页固定的三档配光色：
/// `.ovl2` 的粉（左下大片）+ 紫（右上），以及 `.pl-cv::before` 封面上那圈更浓的粉。
///
/// 这三处**不吃主题强调色**——跟着 accent 走在暗夜里会变成薄荷绿，封面底下那片
/// 粉红就没了（用户 2026-11-13 对着设计稿截图指出来的就是这个）。
const _musicPink = Color(0xFFE2558E);
const _musicViolet = Color(0xFF8E6CFF);
const _musicHalo = Color(0xFFFF5FA8);

/// 音乐卡的**铺满档**（稿子 f5 的版式）。
///
/// 点开卡片时网格把这张卡铺到整块桌面区域（`_CardFocus` 在 desktop.dart 里），
/// 卡片自己按 `w >= 12` 走到这里：左列封面 + 光晕倒影 + 频谱，右列标题 / 标签 /
/// 歌词 / 进度 / 控制键。顶部栏与底栏仍在外面，退出就是收起这张卡。
///
/// 稿子左侧本来是一条音量滑条（`.pl-vol2`）：原车没有可写的媒体音量通道，
/// 按用户 2026-11-13 的决定换成实时频谱，与右侧控制键同底。
class _MusicCardFull extends StatelessWidget {
  final LauncherController controller;
  const _MusicCardFull({required this.controller});

  @override
  Widget build(BuildContext context) {
    final s = SurfaceStyle.of(context);
    // 稿子 f5 的底色是 `rgba(3,4,6,.992)`。暗夜按稿子来；其他两套皮肤先不动。
    final backdrop = s.nocturne ? const Color(0xFD030406) : Colors.transparent;
    return ColoredBox(
        color: backdrop,
        child: NativeSliceBuilder(
            valueListenable: controller.native,
            select: (state) => [
                  state['media'],
                  state['apps'],
                  state['appNames'],
                  state['integrationPreferences'],
                  state['demo'],
                  state['mediaDemo'],
                ],
            builder: (context, state) =>
                CanvasScope(child: _page(context, state))));
  }

  Widget _page(BuildContext context, Map<String, dynamic> state) {
    final s = SurfaceStyle.of(context);
    final media = mapOf(state['media']);
    final demo = mediaIsDemo(state);
    final title = _mediaValue(state, 'title', '午夜立交', '暂无播放');
    final artist = _mediaValue(state, 'artist', '昼夜电台', '等待媒体会话');
    final album = _mediaValue(state, 'collection', '环线', '');
    final subtitle =
        [artist, album].where((value) => value.isNotEmpty).join(' · ');
    return Stack(children: [
      // 稿子 `.ovl2`：左下粉光 + 右上紫光，暗夜才加（浅色皮肤先不动）。
      if (s.nocturne) ...[
        Positioned.fill(
            child: IgnorePointer(
                child: DecoratedBox(
                    decoration: BoxDecoration(
                        gradient: RadialGradient(
                            center: const Alignment(-.5, .42),
                            radius: .92,
                            colors: [
              _musicPink.withValues(alpha: .21),
              _musicPink.withValues(alpha: 0)
            ]))))),
        Positioned.fill(
            child: IgnorePointer(
                child: DecoratedBox(
                    decoration: BoxDecoration(
                        gradient: RadialGradient(
                            center: const Alignment(.78, -.68),
                            radius: .7,
                            colors: [
              _musicViolet.withValues(alpha: .10),
              _musicViolet.withValues(alpha: 0)
            ]))))),
      ],
      // 两列**底部对齐**：左边最后一格是频谱、右边最后一格是控制键，
      // 两者底边落在同一条线上（用户要求「频谱与按钮部分对齐」）。
      Center(
          child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
            SizedBox(
                width: Design.px(372),
                child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _Cover(media: media, demo: demo),
                      SizedBox(height: Design.px(16)),
                      // 稿子 `.pl-vol2` 那条音量滑条的位置：原车没有可写音量通道，
                      // 这里换成实时频谱，画法固定音柱（不要 segments 的底格）。
                      ClipRect(
                          child: ShaderMask(
                              blendMode: BlendMode.dstIn,
                              shaderCallback: (bounds) => const LinearGradient(
                                    begin: Alignment.centerLeft,
                                    end: Alignment.centerRight,
                                    colors: [
                                      Colors.transparent,
                                      Colors.white,
                                      Colors.white,
                                      Colors.transparent
                                    ],
                                    stops: [0, .06, .94, 1],
                                  ).createShader(bounds),
                              child: AudioSpectrum(
                                  key: const ValueKey('music-player-spectrum'),
                                  playing: !demo && media['playing'] == true,
                                  // 画法跟随设置里的频谱样式，与卡片 / 底栏一致。
                                  height: 84))),
                    ])),
            SizedBox(width: Design.px(80)),
            SizedBox(
                width: Design.px(724),
                child: _side(context, media,
                    demo: demo, title: title, subtitle: subtitle)),
          ])),
      // `.v2-src`：右上角换音源
      Positioned(
          right: Design.px(84),
          top: Design.px(14),
          child: _SourcePill(controller: controller)),
    ]);
  }

  /// 右列：标题 / 副标题 / 音质标签 / 歌词 / 进度 / 控制键。
  Widget _side(BuildContext context, Map<String, dynamic> media,
      {required bool demo, required String title, required String subtitle}) {
    final s = SurfaceStyle.of(context);
    final playing = media['playing'] == true;
    final available = demo || media['available'] == true;
    bool can(String key) => demo || media[key] == true;
    VoidCallback? send(String action, String? gate) =>
        !available || (gate != null && !can(gate))
            ? null
            : () => controller.command(action);
    return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              key: const ValueKey('music-player-title'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: Design.px(42),
                  height: 1.1,
                  letterSpacing: Design.px(.5),
                  fontWeight: FontWeight.w300,
                  color: s.text.withValues(alpha: .96))),
          SizedBox(height: Design.px(11)),
          Text(subtitle,
              key: const ValueKey('music-player-subtitle'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: Design.px(16.5), color: s.muted)),
          SizedBox(height: Design.px(17)),
          const _MediaTags(scale: 1.1),
          // `.lyr-hd`
          Padding(
              padding: EdgeInsets.only(
                  left: Design.px(24),
                  top: Design.px(30),
                  bottom: Design.px(4)),
              child: Row(children: [
                Text('LYRICS · 逐句',
                    style: TextStyle(
                        fontSize: Design.px(10.5),
                        letterSpacing: Design.px(2.5),
                        color: s.muted)),
                SizedBox(width: Design.px(10)),
                Expanded(
                    child: Container(
                        height: 1,
                        decoration: BoxDecoration(
                            gradient: LinearGradient(colors: [
                          s.text.withValues(alpha: .12),
                          s.text.withValues(alpha: 0)
                        ]))))
              ])),
          _LyricsWindow(media: media),
          SizedBox(height: Design.px(26)),
          RepaintBoundary(
              child: MediaProgress(
                  media: media,
                  trackHeight: Design.px(4),
                  thumbRadius: Design.px(5),
                  labelSize: Design.px(12.5),
                  onSeek: (value) =>
                      controller.command('seek', value: '$value'))),
          SizedBox(height: Design.px(30)),
          // 控制键在右列里居中，而不是贴着左边；键距 44（稿子 20 在实车太挤）。
          Center(
              child: Row(mainAxisSize: MainAxisSize.min, children: [
            _RoundButton(
                key: const ValueKey('music-player-previous'),
                icon: Icons.skip_previous_rounded,
                label: '上一首',
                onTap: send('previous', 'canPrevious')),
            SizedBox(width: Design.px(44)),
            _PlayButton(
                playing: playing, onTap: send('toggle-play', 'canToggle')),
            SizedBox(width: Design.px(44)),
            _RoundButton(
                key: const ValueKey('music-player-next'),
                icon: Icons.skip_next_rounded,
                label: '下一首',
                onTap: send('next', 'canNext')),
          ])),
        ]);
  }
}

/// `.pl-cv`：372 封面 + 30 圆角 + 粉色外光 + 底部倒影。
class _Cover extends StatelessWidget {
  final Map<String, dynamic> media;
  final bool demo;
  const _Cover({required this.media, required this.demo});
  @override
  Widget build(BuildContext context) {
    final s = SurfaceStyle.of(context);
    final side = Design.px(372);
    final corner = Design.px(30);
    // 稿子 `.pl-cv::before`：粉 26% → 紫 13%（44%）→ 透明（72%）。浅色皮肤压淡。
    final halo = s.dark ? 1.0 : .55;
    return SizedBox(
        width: side,
        height: side + Design.px(14 + 74),
        child: Stack(clipBehavior: Clip.none, children: [
          Positioned(
              left: -Design.px(64),
              top: -Design.px(64),
              child: Container(
                  width: side + Design.px(128),
                  height: side + Design.px(128),
                  decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(colors: [
                        _musicHalo.withValues(alpha: .26 * halo),
                        _musicViolet.withValues(alpha: .13 * halo),
                        _musicHalo.withValues(alpha: 0)
                      ], stops: const [
                        0,
                        .44,
                        .72
                      ])))),
          Container(
              width: side,
              height: side,
              decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(corner),
                  boxShadow: [
                    BoxShadow(
                        color: _musicHalo.withValues(alpha: .55 * halo),
                        offset: Offset(0, Design.px(42)),
                        blurRadius: Design.px(82),
                        spreadRadius: -Design.px(34))
                  ]),
              child: ClipRRect(
                  borderRadius: BorderRadius.circular(corner),
                  child: MediaArtwork(media: media, demo: demo))),
          // `.rf`：封面正下方的倒影
          Positioned(
              left: side * .14,
              right: side * .14,
              top: side + Design.px(14),
              height: Design.px(74),
              child: ClipRect(
                  child: ShaderMask(
                      blendMode: BlendMode.dstIn,
                      shaderCallback: (bounds) => const LinearGradient(
                            begin: Alignment.centerLeft,
                            end: Alignment.centerRight,
                            colors: [
                              Colors.transparent,
                              Colors.white,
                              Colors.white,
                              Colors.transparent
                            ],
                            stops: [0, .22, .78, 1],
                          ).createShader(bounds),
                      child: DecoratedBox(
                          decoration: BoxDecoration(
                              borderRadius: BorderRadius.vertical(
                                  bottom: Radius.circular(Design.px(26))),
                              gradient: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [
                                    _musicPink.withValues(alpha: .22 * halo),
                                    _musicPink.withValues(alpha: .05 * halo),
                                    _musicPink.withValues(alpha: 0)
                                  ],
                                  stops: const [
                                    0,
                                    .42,
                                    .84
                                  ])))))),
        ]));
  }
}

/// `.pl-ctl .c`：54 圆、5.5% 墨底 + 9% 描边，图标 24。
class _RoundButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  const _RoundButton(
      {super.key, required this.icon, required this.label, this.onTap});
  @override
  Widget build(BuildContext context) {
    final s = SurfaceStyle.of(context);
    final enabled = onTap != null;
    return Semantics(
        button: true,
        enabled: enabled,
        label: label,
        child: GestureDetector(
            onTap: onTap,
            child: Container(
                width: Design.px(54),
                height: Design.px(54),
                decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: s.text.withValues(alpha: .055),
                    border: Border.all(color: s.text.withValues(alpha: .09))),
                child: Icon(icon,
                    size: Design.px(24),
                    color: enabled
                        ? s.text.withValues(alpha: .82)
                        : s.disabled))));
  }
}

/// `.pl-ctl .play`：72 圆、强调色渐变、外圈光。
class _PlayButton extends StatelessWidget {
  final bool playing;
  final VoidCallback? onTap;
  const _PlayButton({required this.playing, this.onTap});
  @override
  Widget build(BuildContext context) {
    final s = SurfaceStyle.of(context);
    final enabled = onTap != null;
    return Semantics(
        button: true,
        enabled: enabled,
        label: playing ? '暂停' : '播放',
        child: GestureDetector(
            key: const ValueKey('music-player-toggle'),
            onTap: onTap,
            child: Container(
                width: Design.px(72),
                height: Design.px(72),
                decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [s.accentHi, s.accentLo]),
                    boxShadow: [
                      BoxShadow(
                          color: s.accent.withValues(alpha: .10),
                          spreadRadius: Design.px(5)),
                      BoxShadow(
                          color: s.accent.withValues(alpha: .45),
                          offset: Offset(0, Design.px(16)),
                          blurRadius: Design.px(38),
                          spreadRadius: -Design.px(12))
                    ]),
                child: Icon(playing ? Icons.pause : Icons.play_arrow,
                    size: Design.px(28),
                    color: enabled ? s.accentText : s.disabled))));
  }
}

/// `.lyr`：318 高、左侧 2px 渐变竖线、上下渐隐，当前句放大发光。
class _LyricsWindow extends StatelessWidget {
  final Map<String, dynamic> media;
  const _LyricsWindow({required this.media});
  @override
  Widget build(BuildContext context) {
    final s = SurfaceStyle.of(context);
    return SizedBox(
        height: Design.px(318),
        child: Stack(children: [
          Positioned(
              left: 0,
              top: Design.px(38),
              bottom: Design.px(38),
              child: Container(
                  width: Design.px(2),
                  decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(Design.px(1)),
                      gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            s.accent.withValues(alpha: 0),
                            s.accent.withValues(alpha: .30),
                            s.accent.withValues(alpha: .55),
                            s.accent.withValues(alpha: .30),
                            s.accent.withValues(alpha: 0)
                          ],
                          stops: const [
                            0,
                            .3,
                            .5,
                            .7,
                            1
                          ])))),
          Padding(
              padding: EdgeInsets.only(left: Design.px(24)),
              child: ShaderMask(
                  key: const ValueKey('music-player-lyrics-fade'),
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
                        stops: [0, .13, .87, 1],
                      ).createShader(bounds),
                  child: Center(
                      child: LyricsView(
                          key: const ValueKey('music-player-lyrics'),
                          media: media,
                          mini: true,
                          // 5 行而不是 7 行（用户 2026-11-15 要求）：窗口少两行，
                          // 省下的高度全给中间那句——高亮行字号 29 → 40（逻辑
                          // 24.2 → 33.3，+38%），行高 46 → 62，普通行也稍微
                          // 松开一点（30 → 32），整块比原来矮 ~30，仍是居中。
                          // 5 行而不是 7 行（用户 2026-11-15 要求）：少两行，省下的
                          // 高度给中间那句。高亮 29 → 34、普通 19 → 21，两档一起
                          // 抬，比例压在 1.6 倍左右——只放高亮会变成 2 倍，太跳；
                          // 普通行也得跟着大一点，五行才不显得单薄。
                          visibleLines: 5,
                          lineHeight: Design.px(36),
                          fontSize: Design.px(21),
                          activeLineHeight: Design.px(56),
                          activeFontSize: Design.px(34),
                          textAlign: TextAlign.start)))),
        ]));
  }
}

/// `.v2-src`：右上角音源胶囊（圆点 + 应用名 + 下箭头），点开换应用。
class _SourcePill extends StatelessWidget {
  final LauncherController controller;
  const _SourcePill({required this.controller});
  @override
  Widget build(BuildContext context) {
    final s = SurfaceStyle.of(context);
    return NativeSliceBuilder(
        valueListenable: controller.native,
        select: (state) => [
              state['media'],
              state['apps'],
              state['appNames'],
              state['integrationPreferences'],
              state['demo'],
              state['mediaDemo'],
            ],
        builder: (context, state) {
          final demo = mediaIsDemo(state);
          return Material(
              type: MaterialType.transparency,
              child: InkWell(
                  key: const ValueKey('media-app-picker'),
                  onTap: () => showMusicPicker(context, controller),
                  borderRadius: BorderRadius.circular(Design.px(14)),
                  child: Container(
                      padding: EdgeInsets.symmetric(
                          horizontal: Design.px(16), vertical: Design.px(10)),
                      decoration: BoxDecoration(
                          color: s.text.withValues(alpha: .05),
                          borderRadius: BorderRadius.circular(Design.px(14)),
                          border:
                              Border.all(color: s.text.withValues(alpha: .10))),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        // 稿子那颗 7px 小圆点：示例态粉色，有真实会话时取强调色。
                        Container(
                            width: Design.px(7),
                            height: Design.px(7),
                            decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color:
                                    demo ? const Color(0xFFFF3A3A) : s.accent,
                                boxShadow: [
                                  BoxShadow(
                                      color: (demo
                                              ? const Color(0xFFFF3A3A)
                                              : s.accent)
                                          .withValues(alpha: .55),
                                      blurRadius: Design.px(8))
                                ])),
                        SizedBox(width: Design.px(9)),
                        Text(mediaSourceLabel(state),
                            style: TextStyle(
                                fontSize: Design.px(14.5),
                                color: s.text.withValues(alpha: .78))),
                        SizedBox(width: Design.px(8)),
                        Icon(Icons.keyboard_arrow_down,
                            size: Design.px(16),
                            color: s.text.withValues(alpha: .42)),
                      ]))));
        });
  }
}
