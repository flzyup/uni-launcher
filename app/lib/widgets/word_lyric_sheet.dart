import 'dart:async';

import 'package:flutter/material.dart';

import '../controller/launcher_controller.dart';
import '../model/lyric_timeline.dart';
import '../model/lyrics.dart' show MediaTimeline;
import '../theme/design_tokens.dart';
import '../theme/launcher_theme.dart';
import 'card_content.dart' show mapOf;
import 'lyric_tuning_panel.dart';
import 'launcher_dialog.dart';

/// 词级歌词 · 时间轴（eclipse 设计稿 f40）。
///
/// 全部读源码已有的数据：`media['lyricTimeline']` 经 [LyricTimeline.parse]
/// 得到逐词时间戳，`media` 经 [MediaTimeline] 得到当前播放位置。这一页是
/// 诊断视图——底栏、音乐卡、仪表投屏用的是同一份数据，这里把它摊开。
///
/// 没有逐字数据时不会假装对齐：直接显示「这一行没有逐字时间戳」，与
/// `LyricTimeline.hasWordTiming` 的语义一致。
Future<void> showWordLyricSheet(
        BuildContext context, LauncherController controller) =>
    showLauncherSheet<void>(
      context,
      title: '词级歌词 · 时间轴',
      subtitle: '逐字时间戳驱动填充；底栏、音乐卡、仪表投屏共用同一份数据',
      closeLabel: '关闭词级歌词',
      width: Design.px(1440),
      glowType: 'music',
      builder: (context) => _WordLyricBody(controller: controller),
    );

class _WordLyricBody extends StatefulWidget {
  final LauncherController controller;
  const _WordLyricBody({required this.controller});
  @override
  State<_WordLyricBody> createState() => _WordLyricBodyState();
}

class _WordLyricBodyState extends State<_WordLyricBody> {
  Timer? _tick;
  @override
  void initState() {
    super.initState();
    // 只有这一页打开时才跑；250ms 足够让进度条跟手，又不会像逐帧那样吃预算。
    _tick = Timer.periodic(const Duration(milliseconds: 250), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = SurfaceStyle.of(context);
    return ValueListenableBuilder<Map<String, dynamic>>(
        valueListenable: widget.controller.native,
        builder: (context, native, _) {
          final media = mapOf(native['media']);
          final timeline = LyricTimeline.parse(media['lyricTimeline']);
          final clock = MediaTimeline.fromJson(media);
          final now = clock.at(DateTime.now().millisecondsSinceEpoch);
          final index = timeline.indexAt(now);
          final line = index >= 0 && index < timeline.lines.length
              ? timeline.lines[index]
              : null;
          final next = index + 1 < timeline.lines.length
              ? timeline.lines[index + 1]
              : null;
          final progress = line == null || line.durationMs <= 0
              ? 0.0
              : ((now - line.timeMs) / line.durationMs).clamp(0.0, 1.0);
          // 弹层只给一个 Flexible 的高度：歌词行多、校准面板展开时这页会比
          // 一屏高，得自己滚，否则整块被裁掉（还会报 RenderFlex 溢出）。
          return SingleChildScrollView(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                _preview(s, media, line, next, progress, now, clock),
                SizedBox(height: Design.px(14)),
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(flex: 11, child: _wordTable(s, line)),
                  SizedBox(width: Design.px(14)),
                  Expanded(flex: 9, child: _rules(s, line, progress)),
                ]),
                SizedBox(height: Design.px(10)),
                Text(
                    timeline.isEmpty
                        ? '当前没有歌词时间轴：media.lyricTimeline 为空，底栏与音乐卡会退回纯文本歌词。'
                        : '共 ${timeline.lineCount} 行'
                            '${timeline.hasWordTiming ? ' · 含逐字时间戳' : ' · 无逐字时间戳'}'
                            '${timeline.hasTranslation ? ' · 含翻译行' : ''}'
                            ' · 播放位置 ${_mmss(now)} / ${_mmss(clock.durationMs)}',
                    style: TextStyle(fontSize: Design.px(16), color: s.muted)),
                SizedBox(height: Design.px(18)),
                // 偏移校准原本挂在导航与媒体页右栏；design 版式里那一页没有位置，
                // 但「蓝牙/USB/车机延迟不同」必须能手调，挪进这条数据链路的弹层。
                const LyricTuningPanel(),
              ]));
        });
  }

  Widget _preview(SurfaceStyle s, Map<String, dynamic> media, LyricLine? line,
      LyricLine? next, double progress, int now, MediaTimeline clock) {
    final title = '${media['title'] ?? '暂无播放'}';
    final current = line == null ? '—' : line.text;
    final upcoming = next?.text ?? '';
    // 逐字填充：已唱部分用强调色，未唱部分保持暗。句首没有逐字数据时按句均分。
    final sung = line != null && line.words.isNotEmpty
        ? line.words
            .where((w) => now >= w.startMs + w.durationMs)
            .map((w) => w.text)
            .join()
        : '';
    return Container(
        padding: EdgeInsets.fromLTRB(
            Design.px(26), Design.px(20), Design.px(26), Design.px(18)),
        decoration: BoxDecoration(
            color: s.soft,
            borderRadius: BorderRadius.circular(s.controlRadius * .8)),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Text('底栏歌词位 · 1.9× 特写',
                style: TextStyle(fontSize: Design.px(15), color: s.muted)),
            const Spacer(),
            Text(title,
                style: TextStyle(fontSize: Design.px(15), color: s.muted)),
          ]),
          SizedBox(height: Design.px(18)),
          Text.rich(
              TextSpan(children: [
                TextSpan(
                    text: sung,
                    style: TextStyle(
                        fontSize: Design.px(44),
                        fontWeight: FontWeight.w300,
                        color: s.accent)),
                TextSpan(
                    text: sung.isEmpty
                        ? current
                        : current
                            .substring(sung.length.clamp(0, current.length)),
                    style: TextStyle(
                        fontSize: Design.px(44),
                        fontWeight: FontWeight.w300,
                        color: s.muted)),
              ]),
              maxLines: 1,
              overflow: TextOverflow.ellipsis),
          SizedBox(height: Design.px(12)),
          Text(upcoming,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: Design.px(30),
                  fontWeight: FontWeight.w300,
                  color: s.text.withValues(alpha: .2))),
          SizedBox(height: Design.px(22)),
          Row(children: [
            Text(_mmss(now),
                style: TextStyle(fontSize: Design.px(15), color: s.muted)),
            SizedBox(width: Design.px(14)),
            Expanded(
                child: ClipRRect(
                    borderRadius: BorderRadius.circular(Design.px(2)),
                    child: LinearProgressIndicator(
                        key: const ValueKey('lyric-progress'),
                        value: clock.durationMs > 0
                            ? (now / clock.durationMs).clamp(0.0, 1.0)
                            : 0,
                        minHeight: Design.px(3),
                        backgroundColor: s.soft,
                        valueColor: AlwaysStoppedAnimation(s.accent)))),
            SizedBox(width: Design.px(14)),
            Text(_mmss(clock.durationMs),
                style: TextStyle(fontSize: Design.px(15), color: s.muted)),
          ]),
          SizedBox(height: Design.px(8)),
          Text('当前句填充 ${(progress * 100).round()}%',
              style: TextStyle(fontSize: Design.px(14), color: s.muted)),
        ]));
  }

  Widget _wordTable(SurfaceStyle s, LyricLine? line) {
    Widget cell(String text, {bool head = false, Color? color}) => Padding(
        padding: EdgeInsets.symmetric(vertical: Design.px(7)),
        child: Text(text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
                fontSize: Design.px(head ? 15 : 17),
                color: color ?? (head ? s.muted : s.text))));
    final words = line?.words ?? const <LyricWord>[];
    return Container(
        padding: EdgeInsets.fromLTRB(
            Design.px(18), Design.px(16), Design.px(18), Design.px(16)),
        decoration: BoxDecoration(
            color: s.soft,
            borderRadius: BorderRadius.circular(s.controlRadius * .7)),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Text('当前句时间轴',
                style: TextStyle(
                    fontSize: Design.px(20),
                    fontWeight: FontWeight.w500,
                    color: s.text)),
            const Spacer(),
            Text(words.isEmpty ? '无逐字数据' : '${words.length} 词',
                style: TextStyle(fontSize: Design.px(15), color: s.muted)),
          ]),
          SizedBox(height: Design.px(8)),
          Row(children: [
            SizedBox(width: Design.px(64), child: cell('词', head: true)),
            Expanded(child: cell('起', head: true)),
            Expanded(child: cell('止', head: true)),
            SizedBox(width: Design.px(78), child: cell('时长', head: true)),
          ]),
          const Divider(height: 1),
          if (words.isEmpty)
            Padding(
                padding: EdgeInsets.symmetric(vertical: Design.px(18)),
                child: Text('这一行没有逐字时间戳：整句淡入，不假装对齐（estimated 路径）。',
                    style: TextStyle(
                        fontSize: Design.px(16), color: s.muted, height: 1.6)))
          else
            for (final w in words.take(10))
              Row(children: [
                SizedBox(width: Design.px(64), child: cell(w.text)),
                Expanded(child: cell(_mmss(w.startMs, base: 0))),
                Expanded(child: cell(_mmss(w.startMs + w.durationMs, base: 0))),
                SizedBox(
                    width: Design.px(78), child: cell('${w.durationMs}ms')),
              ]),
        ]));
  }

  Widget _rules(SurfaceStyle s, LyricLine? line, double progress) {
    Widget rule(String mono, String text) => Padding(
        padding: EdgeInsets.only(bottom: Design.px(9)),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(
              width: Design.px(110),
              child: Text(mono,
                  style: TextStyle(fontSize: Design.px(14), color: s.accent))),
          Expanded(
              child: Text(text,
                  style: TextStyle(
                      fontSize: Design.px(16), color: s.muted, height: 1.6))),
        ]));
    return Container(
        padding: EdgeInsets.fromLTRB(
            Design.px(18), Design.px(16), Design.px(18), Design.px(16)),
        decoration: BoxDecoration(
            color: s.soft,
            borderRadius: BorderRadius.circular(s.controlRadius * .7)),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('填充规则',
              style: TextStyle(
                  fontSize: Design.px(20),
                  fontWeight: FontWeight.w500,
                  color: s.text)),
          SizedBox(height: Design.px(12)),
          rule('sungPrefix', '整句已有前缀时长，句首直接铺满'),
          rule('wordTiming', '逐词时间戳优先；缺词按字数均分句长'),
          rule('estimated', '无逐字数据时退回整句淡入，不假装对齐'),
          rule('en / ja', '按空格与音节切，长词内部不再细分'),
          SizedBox(height: Design.px(8)),
          ClipRRect(
              borderRadius: BorderRadius.circular(Design.px(3)),
              child: LinearProgressIndicator(
                  value: progress,
                  minHeight: Design.px(6),
                  backgroundColor: s.strong,
                  valueColor: AlwaysStoppedAnimation(s.accent))),
          SizedBox(height: Design.px(8)),
          Text(
              line == null
                  ? '当前没有活跃的行'
                  : '当前句 ${line.words.length} 词 · 填充 ${(progress * 100).round()}%',
              style: TextStyle(fontSize: Design.px(14), color: s.muted)),
          SizedBox(height: Design.px(12)),
          Wrap(spacing: Design.px(8), runSpacing: Design.px(8), children: [
            for (final tag in ['纯音乐行', '未对齐行', '翻译行'])
              Container(
                  padding: EdgeInsets.symmetric(
                      horizontal: Design.px(12), vertical: Design.px(7)),
                  decoration: BoxDecoration(
                      color: s.strong,
                      borderRadius: BorderRadius.circular(s.controlRadius * .5),
                      border: Border.all(color: s.edge)),
                  child: Text(tag,
                      style:
                          TextStyle(fontSize: Design.px(14), color: s.text))),
          ]),
        ]));
  }

  static String _mmss(int ms, {int? base}) {
    if (ms <= 0) return '--:--';
    final d = Duration(milliseconds: ms);
    final m = d.inMinutes.toString().padLeft(2, '0');
    final sec = (d.inSeconds % 60).toString().padLeft(2, '0');
    final frac = ((d.inMilliseconds % 1000) / 1000 * 100).round();
    if (base == 0) {
      return '$m:$sec.${frac.toString().padLeft(2, '0')}';
    }
    return '$m:$sec';
  }
}
