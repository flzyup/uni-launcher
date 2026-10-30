import 'package:flutter/material.dart';

import '../model/ambient_light.dart';
import '../platform/ambient_light.dart';
import '../theme/design_tokens.dart';
import '../theme/launcher_theme.dart';
import 'glass_surface.dart';

/// Settings block for the music driven ambient light.
///
/// The live preview is isolated behind a [ValueListenableBuilder], because a
/// spectrum frame arrives ten times a second and the rest of the settings
/// page must not rebuild at that rate.
class AmbientLightSettingsPanel extends StatelessWidget {
  final AmbientLightSettings settings;
  final AmbientLightService service;
  final ValueChanged<AmbientLightSettings> onChanged;

  const AmbientLightSettingsPanel({
    super.key,
    required this.settings,
    required this.service,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final s = SurfaceStyle.of(context);
    return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            Text('跟随音乐律动',
                style: TextStyle(fontSize: Design.px(20), color: s.muted)),
            const Spacer(),
            Switch(
                key: const ValueKey('ambient-light-switch'),
                value: settings.enabled,
                onChanged: (value) =>
                    onChanged(settings.copyWith(enabled: value)))
          ]),
          SizedBox(height: Design.px(12)),
          AmbientLightPreview(service: service, settings: settings),
          SizedBox(height: Design.px(18)),
          Text('颜色跟随',
              style: TextStyle(fontSize: Design.px(20), color: s.muted)),
          SizedBox(height: Design.px(10)),
          Wrap(
              spacing: Design.px(12),
              runSpacing: Design.px(12),
              children: [
                for (var mode = 0;
                    mode < AmbientPalette.modeLabels.length;
                    mode++)
                  ChoiceChip(
                      key: ValueKey('ambient-mode-$mode'),
                      label: Text(AmbientPalette.modeLabels[mode]),
                      selected: settings.mode == mode,
                      side: s.technicalFrame
                          ? s.controlSide(settings.mode == mode)
                          : null,
                      shape: s.controlShape(selected: settings.mode == mode),
                      onSelected: (_) =>
                          onChanged(settings.copyWith(mode: mode)))
              ]),
          if (settings.mode == AmbientPalette.modeFixed) ...[
            SizedBox(height: Design.px(18)),
            _HueRow(
                hue: settings.fixedHue,
                onChanged: (hue) =>
                    onChanged(settings.copyWith(fixedHue: hue)))
          ],
          SizedBox(height: Design.px(18)),
          _SliderRow(
              label: '灵敏度',
              hint: '数值越大，微弱的声音也越能点亮氛围灯',
              value: settings.sensitivity,
              min: AmbientPalette.minSensitivity,
              max: AmbientPalette.maxSensitivity,
              divisions: 27,
              display: settings.sensitivity.toStringAsFixed(1),
              onChanged: (value) =>
                  onChanged(settings.copyWith(sensitivity: value))),
          SizedBox(height: Design.px(14)),
          _SliderRow(
              label: '车机亮度',
              hint: '车机氛围灯的绝对亮度，厂商只有高／低／关三档',
              value: settings.vehicleBrightness.toDouble(),
              min: 0,
              max: 100,
              divisions: 20,
              display: '${settings.vehicleBrightness}',
              onChanged: (value) => onChanged(settings.copyWith(
                  vehicleBrightness: value.round().clamp(0, 100)))),
          SizedBox(height: Design.px(14)),
          _SliderRow(
              label: '最低亮度',
              hint: '音乐停止时颜色保留的最低明暗',
              value: settings.minBrightness.toDouble(),
              min: 0,
              max: 100,
              divisions: 20,
              display: '${settings.minBrightness}',
              onChanged: (value) => onChanged(settings.copyWith(
                  minBrightness: value.round().clamp(0, settings.maxBrightness)))),
          SizedBox(height: Design.px(14)),
          _SliderRow(
              label: '最高亮度',
              hint: '音乐最响时颜色能达到的最亮明暗',
              value: settings.maxBrightness.toDouble(),
              min: 0,
              max: 100,
              divisions: 20,
              display: '${settings.maxBrightness}',
              onChanged: (value) => onChanged(settings.copyWith(
                  maxBrightness:
                      value.round().clamp(settings.minBrightness, 100)))),
          SizedBox(height: Design.px(8)),
          Text('音乐的强弱体现在颜色的明暗上；车机亮度档位由上面的滑杆决定。',
              style: TextStyle(fontSize: Design.px(16), color: s.muted)),
          if (service.needsPermission) ...[
            SizedBox(height: Design.px(16)),
            Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                    key: const ValueKey('ambient-request-permission'),
                    onPressed: service.spectrum.requestPermission,
                    icon: const Icon(Icons.mic_none),
                    label: const Text('授权录音权限以启用频谱'))),
          ],
        ]);
  }
}

/// Live colour, brightness and spectrum preview.
class AmbientLightPreview extends StatelessWidget {
  final AmbientLightService service;
  final AmbientLightSettings settings;

  const AmbientLightPreview(
      {super.key, required this.service, required this.settings});

  @override
  Widget build(BuildContext context) {
    final s = SurfaceStyle.of(context);
    return GlassSurface(
        tone: SurfaceTone.soft,
        padding: EdgeInsets.all(Design.px(16)),
        shadow: false,
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(children: [
                ValueListenableBuilder<AmbientColor?>(
                    valueListenable: service.color,
                    builder: (context, color, _) {
                      final swatch = color == null
                          ? s.soft
                          : Color(0xFF000000 | color.packed);
                      return Container(
                          key: const ValueKey('ambient-color-swatch'),
                          width: Design.px(64),
                          height: Design.px(64),
                          decoration: BoxDecoration(
                              color: swatch,
                              borderRadius: BorderRadius.circular(s.radius * .4),
                              border: Border.all(color: s.edge)));
                    }),
                SizedBox(width: Design.px(16)),
                Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Text('当前颜色',
                          style: TextStyle(
                              fontSize: Design.px(20), color: s.muted)),
                      SizedBox(height: Design.px(6)),
                      ValueListenableBuilder<AmbientColor?>(
                          valueListenable: service.color,
                          builder: (context, color, _) => Text(
                              color == null
                                  ? '等待音乐'
                                  : '${color.hex} · 明暗 ${color.brightness}',
                              key: const ValueKey('ambient-color-readout'),
                              style: TextStyle(fontSize: Design.px(22))))
                    ])),
              ]),
              SizedBox(height: Design.px(14)),
              _BrightnessBar(service: service, surface: s),
              SizedBox(height: Design.px(12)),
              _SpectrumStrip(service: service, surface: s),
              SizedBox(height: Design.px(12)),
              Text(_statusText(service),
                  key: const ValueKey('ambient-status'),
                  style: TextStyle(fontSize: Design.px(18), color: s.muted)),
              SizedBox(height: Design.px(4)),
              Text(_spectrumDiagnostics(service),
                  key: const ValueKey('ambient-spectrum-diagnostics'),
                  style: TextStyle(fontSize: Design.px(16), color: s.muted)),
              if (service.unresolved.isNotEmpty) ...[
                SizedBox(height: Design.px(6)),
                Text(
                  '车机上按名解析不到的功能号：'
                  '${service.unresolved.take(6).join('、')}'
                  '${service.unresolved.length > 6 ? ' 等 ${service.unresolved.length} 个' : ''}',
                  key: const ValueKey('ambient-unresolved'),
                  style: TextStyle(fontSize: Design.px(16), color: s.muted),
                )
              ]
            ]));
  }

  /// The capability line.
  ///
  /// It has to say *why* the strip is not lit. "This device has no ambient
  /// light interface" and "the vehicle service is not connected yet" lead to
  /// completely different actions, so the native reason is shown verbatim.
  static String _statusText(AmbientLightService service) {
    if (!service.channelAvailable) {
      final reason = service.reason.isEmpty ? '此设备没有原车氛围灯接口' : service.reason;
      return '通道：$reason';
    }
    final channel = '通道：原车氛围灯已接入';
    if (service.needsPermission) {
      return '$channel · 频谱需要录音权限';
    }
    if (!service.enabled) {
      return '$channel · 尚未开启';
    }
    if (!service.switchApplied) {
      return '$channel · 正在点亮车机氛围灯';
    }
    return '$channel · ${_spectrumText(service)}';
  }

  /// Why the spectrum has nothing to show.
  ///
  /// The four cases need four different actions, so they must not collapse
  /// into one "waiting for music": the permission is missing, the capture
  /// could not be started, the capture runs but hears nothing, or the
  /// capture delivers a signal.
  static String _spectrumText(AmbientLightService service) {
    final status = service.spectrumStatus;
    if (status == 'permission-required') return '频谱需要录音权限';
    if (status == 'unavailable') {
      final detail = service.spectrumDetail;
      return detail.isEmpty ? '频谱采集不可用' : '频谱采集不可用（$detail）';
    }
    if (status == 'starting') return '正在启动频谱采集';
    if (!service.spectrumReady) return '等待频谱采集';
    // The capture runs. Without a single frame that carried a signal there is
    // simply nothing playing yet.
    if (service.spectrumSignalFrames == 0) return '等待音乐播放';
    return '频谱采集中';
  }

  /// The spectrum diagnostics, for the case where the light does not react.
  ///
  /// A car has no logcat to read, so the page itself has to say where the
  /// spectrum comes from and whether anything was heard at all.
  static String _spectrumDiagnostics(AmbientLightService service) {
    final source = switch (service.spectrumSource) {
      'output-mix' => '输出混音',
      'session' => '播放会话',
      _ => '无',
    };
    final size = service.spectrumCaptureSize;
    final rate = service.spectrumSampleRate;
    final text = StringBuffer('频谱：$source');
    if (size > 0) text.write(' · 采集点数 $size');
    if (rate > 0) text.write(' · ${rate ~/ 1000}kHz');
    text.write(' · 已收到 ${service.spectrumSignalFrames}/'
        '${service.spectrumFrames} 帧信号');
    final hidden = service.spectrumHiddenApi;
    if (hidden.isNotEmpty) text.write(' · 隐藏 API $hidden');
    final detail = service.spectrumDetail;
    if (detail.isNotEmpty) text.write(' · $detail');
    return text.toString();
  }
}

/// The brightness the strip would show right now.
class _BrightnessBar extends StatelessWidget {
  final AmbientLightService service;
  final SurfaceStyle surface;

  const _BrightnessBar({required this.service, required this.surface});

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<AmbientColor?>(
      valueListenable: service.color,
      builder: (context, color, _) {
        final level = (color?.brightness ?? 0) / 100;
        return ClipRRect(
            borderRadius: BorderRadius.circular(surface.radius * .3),
            child: SizedBox(
                height: Design.px(10),
                child: Stack(children: [
                  Container(color: surface.soft),
                  FractionallySizedBox(
                      widthFactor: level,
                      child: Container(
                          color: color == null
                              ? surface.edge
                              : Color(0xFF000000 | color.packed)))
                ])));
      });
}

/// The live spectrum, painted by the shared spectrum painter.
///
/// It listens to the spectrum service rather than to the colour: the colour
/// is throttled and may stay identical for many frames, while the bars have
/// to follow every frame.
class _SpectrumStrip extends StatelessWidget {
  final AmbientLightService service;
  final SurfaceStyle surface;

  const _SpectrumStrip({required this.service, required this.surface});

  @override
  Widget build(BuildContext context) => ListenableBuilder(
      listenable: service.spectrum,
      builder: (context, _) {
        final levels = service.spectrum.levels;
        final color = service.color.value;
        return SizedBox(
            height: Design.px(34),
            child: CustomPaint(
                key: const ValueKey('ambient-spectrum-strip'),
                painter: _StripPainter(
                    levels,
                    color == null ? surface.edge : Color(0xFF000000 | color.packed),
                    surface.edge)));
      });
}

class _StripPainter extends CustomPainter {
  final List<double> levels;
  final Color ink, edge;

  _StripPainter(this.levels, this.ink, this.edge);

  @override
  void paint(Canvas canvas, Size size) {
    const count = 24;
    if (size.isEmpty) return;
    final step = size.width / count;
    final width = (step * .56).clamp(1.0, 9.0);
    final track = Paint()..color = edge.withValues(alpha: .45);
    final bar = Paint()..color = ink;
    for (var i = 0; i < count; i++) {
      final value = i < levels.length && levels[i].isFinite
          ? levels[i].clamp(0.0, 1.0)
          : 0.0;
      final h = (value * (size.height - 2)).clamp(1.0, size.height);
      final rect = Rect.fromLTWH((i + .5) * step - width / 2,
          size.height - h, width, h);
      canvas.drawRRect(
          RRect.fromRectAndRadius(rect, const Radius.circular(1)),
          value > .015 ? bar : track);
    }
  }

  @override
  bool shouldRepaint(_StripPainter old) =>
      old.ink != ink ||
      old.edge != edge ||
      !_same(old.levels, levels);

  static bool _same(List<double> a, List<double> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

/// A labelled slider with a value readout.
class _SliderRow extends StatelessWidget {
  final String label, hint, display;
  final double value, min, max;
  final int divisions;
  final ValueChanged<double> onChanged;

  const _SliderRow(
      {required this.label,
      required this.hint,
      required this.display,
      required this.value,
      required this.min,
      required this.max,
      required this.divisions,
      required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final s = SurfaceStyle.of(context);
    return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            Text(label, style: TextStyle(fontSize: Design.px(20))),
            const Spacer(),
            Text(display, style: TextStyle(fontSize: Design.px(20), color: s.muted))
          ]),
          SizedBox(height: Design.px(4)),
          Text(hint, style: TextStyle(fontSize: Design.px(17), color: s.muted)),
          SliderTheme(
              data: SliderTheme.of(context).copyWith(trackHeight: Design.px(4)),
              child: Slider(
                  key: ValueKey('ambient-slider-$label'),
                  value: value.clamp(min, max),
                  min: min,
                  max: max,
                  divisions: divisions,
                  onChanged: onChanged))
        ]);
  }
}

/// Fixed hue presets plus a hue slider.
class _HueRow extends StatelessWidget {
  final double hue;
  final ValueChanged<double> onChanged;

  const _HueRow({required this.hue, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final s = SurfaceStyle.of(context);
    return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('固定颜色',
              style: TextStyle(fontSize: Design.px(20), color: s.muted)),
          SizedBox(height: Design.px(10)),
          Wrap(
              spacing: Design.px(12),
              runSpacing: Design.px(12),
              children: [
                for (final preset in AmbientPalette.fixedColors)
                  InkWell(
                      key: ValueKey('ambient-hue-${preset.$1.toInt()}'),
                      onTap: () => onChanged(preset.$1),
                      child: Container(
                          width: Design.px(40),
                          height: Design.px(40),
                          decoration: BoxDecoration(
                              color: HSVColor.fromAHSV(
                                      1, preset.$1, .82, 1)
                                  .toColor(),
                              borderRadius:
                                  BorderRadius.circular(s.radius * .4),
                              border: Border.all(
                                  color: (hue - preset.$1).abs() < 1
                                      ? s.accent
                                      : s.edge,
                                  width: (hue - preset.$1).abs() < 1
                                      ? Design.px(3)
                                      : Design.px(1)))))
              ]),
          SizedBox(height: Design.px(10)),
          SliderTheme(
              data: SliderTheme.of(context).copyWith(trackHeight: Design.px(4)),
              child: Slider(
                  key: const ValueKey('ambient-hue-slider'),
                  value: hue.clamp(0, 360),
                  min: 0,
                  max: 360,
                  divisions: 36,
                  activeColor: HSVColor.fromAHSV(1, hue, .82, 1).toColor(),
                  onChanged: onChanged))
        ]);
  }
}
