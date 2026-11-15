import 'package:flutter/material.dart';
import 'spectrum_painter.dart';
import '../platform/audio_spectrum.dart';
import '../theme/launcher_theme.dart';
import '../theme/design_tokens.dart';

/// Only the tiny painted region repaints when a native FFT frame arrives.
/// There is no ticker, per-frame setState, bitmap, shader animation or blur.
class AudioSpectrum extends StatefulWidget {
  final bool playing;
  final double height;
  final AudioSpectrumService? service;

  /// 指定画法（bars / segments / mirror / outline）；null 跟随设置里的频谱样式。
  /// 卡片、底栏与铺满档都不传：用户在设置里换哪一款，三处一起换。
  final String? style;
  const AudioSpectrum(
      {super.key,
      required this.playing,
      this.height = 42,
      this.service,
      this.style});
  @override
  State<AudioSpectrum> createState() => _AudioSpectrumState();
}

class _AudioSpectrumState extends State<AudioSpectrum>
    with WidgetsBindingObserver {
  late AudioSpectrumService service;
  bool visible = true, resumed = true, scheduled = false;
  String presentation = '';
  @override
  void initState() {
    super.initState();
    service = widget.service ?? AudioSpectrumService.shared;
    presentation = service.status;
    resumed = _canRender(WidgetsBinding.instance.lifecycleState);
    service.addListener(statusChanged);
    WidgetsBinding.instance.addObserver(this);
    service.refreshStatus();
  }

  // Android 9 can mark a visible launcher inactive when its embedded map
  // or global dock owns window focus. Hidden/paused still stop capture.
  bool _canRender(AppLifecycleState? state) =>
      state == null ||
      state == AppLifecycleState.resumed ||
      state == AppLifecycleState.inactive;

  void statusChanged() {
    if (!mounted || presentation == service.status) return;
    setState(() => presentation = service.status);
  }

  void scheduleDemand() {
    if (scheduled) return;
    scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      scheduled = false;
      if (mounted)
        service.setDemand(this, visible && resumed && widget.playing);
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    visible = TickerMode.valuesOf(context).enabled &&
        (ModalRoute.of(context)?.isCurrent ?? true);
    scheduleDemand();
  }

  @override
  void didUpdateWidget(AudioSpectrum old) {
    super.didUpdateWidget(old);
    if (old.service != widget.service) {
      service.removeListener(statusChanged);
      service.setDemand(this, false);
      service = widget.service ?? AudioSpectrumService.shared;
      presentation = service.status;
      service.addListener(statusChanged);
      service.refreshStatus();
    }
    scheduleDemand();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    resumed = _canRender(state);
    service.setDemand(this, visible && resumed && widget.playing);
    if (resumed) service.refreshStatus();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    service.removeListener(statusChanged);
    service.setDemand(this, false);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = SurfaceStyle.of(context);
    // 无声 / 暂停时画不出音柱，只剩底部那一排「刻度」（painter 里的 track）。
    // 暗夜皮肤的 edge 是偏亮的蓝灰（#31475E），压在近黑底上看得到；浅色皮肤的
    // edge 却是接近白的（classic #CAD6E4、蓝玻璃半透明白），落在白底上等于没画
    // （用户 2026-11-13 反馈）。浅色单独压深一档：用正文墨色的低透明度当刻度色。
    final track = s.dark ? s.edge : s.text.withValues(alpha: .44);
    return SizedBox(
        height: Design.px(widget.height),
        child: Semantics(
            label: '音频频谱，设备播放输出混音',
            child: RepaintBoundary(
                child: Stack(fit: StackFit.expand, children: [
              CustomPaint(
                  key: const ValueKey('audio-spectrum-paint'),
                  painter: AudioSpectrumPainter(
                      service, s.accent, track, widget.style ?? s.spectrumStyle)),
              if (!service.granted && presentation == 'permission-required')
                Center(
                    child: TextButton.icon(
                        key: const ValueKey('enable-audio-spectrum'),
                        onPressed: service.requestPermission,
                        style: TextButton.styleFrom(
                            minimumSize: Size.zero,
                            padding: EdgeInsets.symmetric(
                                horizontal: Design.px(10),
                                vertical: Design.px(3))),
                        icon: Icon(Icons.graphic_eq, size: Design.px(20)),
                        label: Text('启用频谱',
                            style: TextStyle(fontSize: Design.px(16))))),
            ]))));
  }
}

class AudioSpectrumPainter extends CustomPainter {
  final AudioSpectrumService service;
  final Color accent, edge;
  final String style;
  AudioSpectrumPainter(this.service, this.accent, this.edge, this.style)
      : super(repaint: service);
  @override
  void paint(Canvas canvas, Size size) => paintSpectrum(canvas, size,
      levels: service.available ? service.levels : const [],
      accent: accent,
      edge: edge,
      style: style);
  @override
  bool shouldRepaint(AudioSpectrumPainter old) =>
      old.service != service ||
      old.accent != accent ||
      old.edge != edge ||
      old.style != style;
}
