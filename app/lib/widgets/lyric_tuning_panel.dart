import 'package:flutter/material.dart';
import '../platform/lyric_tuning.dart';
import '../theme/design_tokens.dart';
import '../theme/launcher_theme.dart';

/// Lyric calibration, sitting directly under the player picker.
///
/// The panel and the desktop card both read one playback clock, so a value set here moves
/// the highlight on both. Two controls, because latency has two parts: a constant one for the
/// output path (Bluetooth, USB, the head unit's DSP) and a per-track one for the recordings
/// that were mastered a beat early or late.
class LyricTuningPanel extends StatefulWidget {
  const LyricTuningPanel({super.key});

  @override
  State<LyricTuningPanel> createState() => _LyricTuningPanelState();
}

class _LyricTuningPanelState extends State<LyricTuningPanel> {
  LyricTuning _tuning = const LyricTuning();
  bool _loaded = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    LyricTuning.load().then((value) {
      if (!mounted) return;
      setState(() {
        _tuning = value;
        _loaded = true;
      });
    });
  }

  static int _step(int value, int delta) =>
      (value + delta).clamp(-LyricTuning.limitMs, LyricTuning.limitMs);

  Future<void> _saveOffset({int? global, int? track}) async {
    final next = _tuning.copyWith(globalMs: global, trackMs: track);
    setState(() => _tuning = next);
    await LyricTuning.saveOffset(
      globalMs: next.globalMs,
      title: next.title,
      artist: next.artist,
      trackMs: next.trackMs,
    );
  }

  Future<void> _saveCache({String? policy, int? limitMb}) async {
    final next = _tuning.copyWith(policy: policy, limitMb: limitMb);
    setState(() {
      _tuning = next;
      _saving = true;
    });
    final applied = await LyricTuning.saveCache(
        policy: next.policy, limitMb: next.limitMb);
    if (!mounted) return;
    setState(() {
      _tuning = _tuning.copyWith(policy: applied);
      _saving = false;
    });
  }

  String get _seconds => (_tuning.effectiveMs / 1000).toStringAsFixed(2);

  @override
  Widget build(BuildContext context) {
    final s = SurfaceStyle.of(context);
    final label = TextStyle(fontSize: Design.px(19), color: s.muted, height: 1.5);
    final value = TextStyle(fontSize: Design.px(21), color: s.accent);
    Widget nudge(String key, int valueMs, VoidCallback? back,
            VoidCallback? forward, String caption) =>
        Row(children: [
          Expanded(child: Text(caption, style: label)),
          IconButton(
              key: ValueKey('$key-down'),
              onPressed: back,
              icon: const Icon(Icons.remove, size: 18)),
          SizedBox(
              width: Design.px(78),
              child: Text('${valueMs > 0 ? '+' : ''}$valueMs',
                  textAlign: TextAlign.center, style: value)),
          IconButton(
              key: ValueKey('$key-up'),
              onPressed: forward,
              icon: const Icon(Icons.add, size: 18)),
        ]);

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text('歌词偏移与缓存', style: TextStyle(fontSize: Design.px(21), color: s.text)),
      SizedBox(height: Design.px(6)),
      Row(children: [
        Expanded(
          child: Text(
              _loaded
                  ? '当前生效 ${_seconds}s（正数让歌词更晚，负数更早）。微调只作用于当前曲目 '
                      '${_tuning.hasTrack ? '「${_tuning.title}」' : '（尚未在播放）'}。'
                  : '正在读取当前设置…',
              style: label),
        ),
        IconButton(
            key: const ValueKey('lyric-tuning-refresh'),
            tooltip: '换曲后刷新当前曲目',
            onPressed: () async {
              final value = await LyricTuning.load();
              if (!mounted) return;
              setState(() => _tuning = value.copyWith(
                  globalMs: _tuning.globalMs,
                  policy: _tuning.policy,
                  limitMb: _tuning.limitMb));
            },
            icon: const Icon(Icons.refresh, size: 18)),
      ]),
      SizedBox(height: Design.px(6)),
      nudge(
          'lyric-offset',
          _tuning.globalMs,
          _tuning.globalMs <= -LyricTuning.limitMs
              ? null
              : () => _saveOffset(global: _step(_tuning.globalMs, -100)),
          _tuning.globalMs >= LyricTuning.limitMs
              ? null
              : () => _saveOffset(global: _step(_tuning.globalMs, 100)),
          '全局偏移（每 100 ms）'),
      nudge(
          'lyric-track-offset',
          _tuning.trackMs,
          !_tuning.hasTrack || _tuning.trackMs <= -LyricTuning.limitMs
              ? null
              : () => _saveOffset(track: _step(_tuning.trackMs, -100)),
          !_tuning.hasTrack || _tuning.trackMs >= LyricTuning.limitMs
              ? null
              : () => _saveOffset(track: _step(_tuning.trackMs, 100)),
          '当前曲目微调'),
      SizedBox(height: Design.px(10)),
      DropdownButtonFormField<String>(
          key: const ValueKey('lyric-cache-policy'),
          initialValue: LyricCachePolicy.normalise(_tuning.policy),
          isExpanded: true,
          decoration: InputDecoration(
              labelText: '歌词缓存',
              helperText: _saving ? '正在保存…' : LyricCachePolicy.label(_tuning.policy)),
          items: LyricCachePolicy.all
              .map((policy) => DropdownMenuItem(
                  value: policy, child: Text(LyricCachePolicy.label(policy))))
              .toList(),
          onChanged: (policy) {
            if (policy != null) _saveCache(policy: policy);
          }),
      if (LyricCachePolicy.normalise(_tuning.policy) == LyricCachePolicy.capacity)
        DropdownButtonFormField<int>(
            key: const ValueKey('lyric-cache-limit'),
            initialValue: _tuning.limitMb,
            isExpanded: true,
            decoration: const InputDecoration(labelText: '容量上限'),
            items: const [8, 16, 24, 48, 96]
                .map((mb) =>
                    DropdownMenuItem(value: mb, child: Text('$mb MB')))
                .toList(),
            onChanged: (mb) {
              if (mb != null) _saveCache(limitMb: mb);
            }),
    ]);
  }
}
