import 'package:flutter/material.dart';
import '../theme/design_tokens.dart';
import 'audio_spectrum.dart';
import 'lyrics_view.dart';

/// Remains mounted across media updates; horizontal gestures only change this
/// region. Default page is the current lyric. Off-page FFT consumers are released.
class DockMusicVisual extends StatefulWidget {
  final Map<String, dynamic> media;
  final bool demo;
  const DockMusicVisual({super.key, required this.media, this.demo = false});
  @override
  State<DockMusicVisual> createState() => _DockMusicVisualState();
}

class _DockMusicVisualState extends State<DockMusicVisual> {
  final pages = PageController();
  int index = 0;
  @override
  void dispose() {
    pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox(
      height: Design.px(64),
      child: PageView(
          key: const ValueKey('dock-music-visual-pages'),
          controller: pages,
          onPageChanged: (value) => setState(() => index = value),
          children: [
            Semantics(
                label: '歌词，向左滑动显示频谱',
                child: Center(
                    key: const ValueKey('dock-lyrics'),
                    child: TickerMode(
                        enabled: index == 0,
                        child: LyricsView(
                            media: widget.media,
                            visibleLines: 1,
                            currentLineMaxLines: 2,
                            lineHeight: 32,
                            fontSize: 26,
                            textAlign: TextAlign.center)))),
            Semantics(
                label: '音频频谱，向右滑动显示歌词',
                child: Center(
                    child: TickerMode(
                        enabled: index == 1,
                        child: AudioSpectrum(
                            playing:
                                !widget.demo && widget.media['playing'] == true,
                            height: 48)))),
          ]));
}
