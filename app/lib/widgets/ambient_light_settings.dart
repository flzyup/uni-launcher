import 'package:flutter/material.dart';

import '../model/ambient_light.dart';
import '../model/ambient_presets.dart';
import '../platform/ambient_light.dart';
import '../theme/design_tokens.dart';
import '../theme/launcher_theme.dart';
import 'color_picker.dart';
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
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        Text('跟随音乐律动',
            style: TextStyle(fontSize: Design.px(20), color: s.muted)),
        const Spacer(),
        Switch(
            key: const ValueKey('ambient-light-switch'),
            value: settings.enabled,
            onChanged: (value) => onChanged(settings.copyWith(enabled: value)))
      ]),
      SizedBox(height: Design.px(12)),
      AmbientLightPreview(service: service, settings: settings),
      SizedBox(height: Design.px(18)),
      Text('颜色跟随', style: TextStyle(fontSize: Design.px(20), color: s.muted)),
      SizedBox(height: Design.px(10)),
      Wrap(spacing: Design.px(12), runSpacing: Design.px(12), children: [
        for (var mode = 0; mode < AmbientPalette.modeLabels.length; mode++)
          ChoiceChip(
              key: ValueKey('ambient-mode-$mode'),
              label: Text(AmbientPalette.modeLabels[mode]),
              selected: settings.mode == mode,
              side: s.technicalFrame
                  ? s.controlSide(settings.mode == mode)
                  : null,
              shape: s.controlShape(selected: settings.mode == mode),
              onSelected: (_) => onChanged(settings.copyWith(mode: mode)))
      ]),
      if (settings.mode == AmbientPalette.modeFixed) ...[
        SizedBox(height: Design.px(18)),
        _HueRow(
            hue: settings.fixedHue,
            onChanged: (hue) => onChanged(settings.copyWith(fixedHue: hue)))
      ],
      // The three colour regions belong to the rhythm engine: it maps each
      // frequency region to its own hue, and keeping them far apart is
      // what stops the strip from collapsing into one blue family.
      if (settings.engine == AmbientLightSettings.engineRhythm &&
          settings.mode == AmbientPalette.modeSpectrum) ...[
        SizedBox(height: Design.px(18)),
        Text('氛围灯色彩',
            style: TextStyle(fontSize: Design.px(20), color: s.muted)),
        SizedBox(height: Design.px(12)),
        Row(children: [
          Expanded(
              child: _RhythmColorCard(
                  id: 'bass',
                  label: '低频',
                  hue: settings.bassHue,
                  custom: settings.bassCustom,
                  onChanged: (selection) => onChanged(settings.copyWith(
                      bassHue: selection.$1, bassCustom: selection.$2)))),
          SizedBox(width: Design.px(14)),
          Expanded(
              child: _RhythmColorCard(
                  id: 'mid',
                  label: '中频',
                  hue: settings.midHue,
                  custom: settings.midCustom,
                  onChanged: (selection) => onChanged(settings.copyWith(
                      midHue: selection.$1, midCustom: selection.$2)))),
          SizedBox(width: Design.px(14)),
          Expanded(
              child: _RhythmColorCard(
                  id: 'treble',
                  label: '高频',
                  hue: settings.trebleHue,
                  custom: settings.trebleCustom,
                  onChanged: (selection) => onChanged(settings.copyWith(
                      trebleHue: selection.$1, trebleCustom: selection.$2))))
        ]),
      ],
      if (settings.engine == AmbientLightSettings.engineRhythm) ...[
        SizedBox(height: Design.px(18)),
        _SliderRow(
            label: '节拍提前量',
            hint: '补偿原车氛围灯过渡延迟；灯光偏慢则调大',
            value: settings.beatLeadMs.toDouble(),
            min: 0,
            max: 250,
            divisions: 25,
            display: '${settings.beatLeadMs}ms',
            onChanged: (value) => onChanged(
                settings.copyWith(beatLeadMs: value.round().clamp(0, 250)))),
      ],
      if (settings.engine != AmbientLightSettings.engineV2 ||
          settings.customMode) ...[
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
      ],
      SizedBox(height: Design.px(14)),
      // 亮度上下限是**旧版链路**的参数（旧版是「下限 + (上限−下限)×电平^γ」
      // 的线性映射）。新版用「基础亮度 + 感知明度区间映射」，
      // 压根不读这两个值 —— 放在这儿拖了没反应，只能藏起来。
      if (settings.engine != AmbientLightSettings.engineV2) ...[
        _SliderRow(
            label: '最低亮度',
            hint: '音乐停止时颜色保留的最低明暗',
            value: settings.minBrightness.toDouble(),
            min: 0,
            max: 100,
            divisions: 20,
            display: '${settings.minBrightness}',
            onChanged: (value) => onChanged(settings.copyWith(
                minBrightness:
                    value.round().clamp(0, settings.maxBrightness)))),
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
      ],
      SizedBox(height: Design.px(8)),
      Text(
          settings.engine == AmbientLightSettings.engineV2 &&
                  !settings.customMode
              ? '预设模式只显示结果：灵敏度、车机亮度、分区编排这些滑杆都收进了'
                  '「动感引擎 → 自定义」。想微调就点一下「自定义」。'
              : settings.engine == AmbientLightSettings.engineV2
                  ? '音乐的强弱体现在颜色的明暗上；新版的明暗区间在「动感引擎」里调，'
                      '车机亮度档位由上面的滑杆决定。'
                  : settings.engine == AmbientLightSettings.engineRhythm
                      ? '音乐的强弱体现在颜色的明暗上；节奏引擎每拍写一次峰值与谷值，'
                          '车机亮度档位由上面的滑杆决定。'
                      : '音乐的强弱体现在颜色的明暗上；车机亮度档位由上面的滑杆决定。',
          style: TextStyle(fontSize: Design.px(16), color: s.muted)),
      SizedBox(height: Design.px(18)),
      _MotionEngineSection(settings: settings, onChanged: onChanged),
      if (settings.engine != AmbientLightSettings.engineV2 ||
          settings.customMode) ...[
        SizedBox(height: Design.px(18)),
        _ZoneChoreoSection(settings: settings, onChanged: onChanged),
      ],
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

/// The motion engine: which chain drives the strip and how it behaves.
///
/// The parameters only exist for the new engine. The legacy chain is the
/// production look that was verified on the car, so it has nothing to tune
/// — the sliders are hidden instead of being shown greyed out.
class _MotionEngineSection extends StatelessWidget {
  final AmbientLightSettings settings;
  final ValueChanged<AmbientLightSettings> onChanged;

  const _MotionEngineSection({required this.settings, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final s = SurfaceStyle.of(context);
    final v2 = settings.engine == AmbientLightSettings.engineV2;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text('动感引擎', style: TextStyle(fontSize: Design.px(20), color: s.muted)),
      SizedBox(height: Design.px(10)),
      Wrap(spacing: Design.px(12), runSpacing: Design.px(12), children: [
        for (var engine = 0; engine < 3; engine++)
          ChoiceChip(
              key: ValueKey('ambient-engine-$engine'),
              label: Text(const [
                '新版（流畅）',
                '旧版（现网观感）',
                '节奏（峰值冲击）',
              ][engine]),
              selected: settings.engine == engine,
              side: s.technicalFrame
                  ? s.controlSide(settings.engine == engine)
                  : null,
              shape: s.controlShape(selected: settings.engine == engine),
              onSelected: (_) => onChanged(settings.copyWith(engine: engine)))
      ]),
      SizedBox(height: Design.px(10)),
      if (!v2)
        Text(
          settings.engine == AmbientLightSettings.engineRhythm
              ? '节奏引擎每拍写一次峰值（颜色 + 车机高亮档）与一次谷值（暗一档），'
                  '两拍之间不写，所以「一拍一个冲击」而不是连续流动。\n\n'
                  '低频／中频／高频各有一个颜色区域，可以在上面分别取色。'
              : '旧版是实车验证过的现网链路：10Hz 步进、HSV 配色、亮度线性缩放。\n\n'
                  '它被评价为「灯在跳，不是灯在流动」。保留它是为了在同一台车、同一首歌上直接对比。',
          key: const ValueKey('ambient-engine-note'),
          style: TextStyle(fontSize: Design.px(16), color: s.muted),
        )
      else ...[
        _PresetChips(settings: settings, onChanged: onChanged),
        SizedBox(height: Design.px(14)),
        if (!settings.customMode)
          _PresetSummary(settings: settings, onChanged: onChanged)
        else ...[
          _SliderRow(
              label: '亮度起 attack',
              hint: '声音变大时颜色变亮的快慢',
              value: settings.attackMs.toDouble(),
              min: 10,
              max: 300,
              divisions: 58,
              display: '${settings.attackMs} ms',
              onChanged: (value) => onChanged(
                  settings.copyWith(attackMs: value.round().clamp(10, 300)))),
          SizedBox(height: Design.px(14)),
          _SliderRow(
              label: '亮度落 decay',
              hint: '声音变小后颜色变暗的快慢（越慢越有余韵）',
              value: settings.decayMs.toDouble(),
              min: 60,
              max: 1200,
              divisions: 57,
              display: '${settings.decayMs} ms',
              onChanged: (value) => onChanged(
                  settings.copyWith(decayMs: value.round().clamp(60, 1200)))),
          SizedBox(height: Design.px(14)),
          _SliderRow(
              label: '色相平滑 τ',
              hint: '颜色在色相环上移动时的时间常数',
              value: settings.hueTauMs.toDouble(),
              min: 60,
              max: 1200,
              divisions: 57,
              display: '${settings.hueTauMs} ms',
              onChanged: (value) => onChanged(
                  settings.copyWith(hueTauMs: value.round().clamp(60, 1200)))),
          SizedBox(height: Design.px(14)),
          _SliderRow(
              label: '色相限速',
              hint: '颜色每秒最多转多少度',
              value: settings.hueMaxDeg.toDouble(),
              min: 10,
              max: 180,
              divisions: 17,
              display: '${settings.hueMaxDeg} °/s',
              onChanged: (value) => onChanged(
                  settings.copyWith(hueMaxDeg: value.round().clamp(10, 180)))),
          SizedBox(height: Design.px(14)),
          _SliderRow(
              label: '色相限加速',
              hint: '色相加速的上限：消掉「甩过去再顿一下」',
              value: settings.hueMaxAccel.toDouble(),
              min: 30,
              max: 800,
              divisions: 77,
              display: '${settings.hueMaxAccel} °/s²',
              onChanged: (value) => onChanged(settings.copyWith(
                  hueMaxAccel: value.round().clamp(30, 800)))),
          SizedBox(height: Design.px(14)),
          _SliderRow(
              label: '每帧色差上限',
              hint: '相邻两帧允许的最大感知色差（ΔE00），越小越平滑',
              value: settings.maxDeltaE,
              min: 0.2,
              max: 6.0,
              divisions: 58,
              display: settings.maxDeltaE.toStringAsFixed(1),
              onChanged: (value) => onChanged(
                  settings.copyWith(maxDeltaE: value.clamp(0.2, 6.0)))),
          SizedBox(height: Design.px(14)),
          _SliderRow(
              label: '基础亮度',
              hint: '音乐停了也保留的底光',
              value: settings.floor.toDouble(),
              min: 0,
              max: 30,
              divisions: 30,
              display: '${settings.floor} %',
              onChanged: (value) => onChanged(
                  settings.copyWith(floor: value.round().clamp(0, 30)))),
          SizedBox(height: Design.px(14)),
          _SliderRow(
              label: '饱和度上限',
              hint: '颜色最多能有多艳',
              value: settings.saturation,
              min: 0,
              max: 1,
              divisions: 100,
              display: '${(settings.saturation * 100).round()} %',
              onChanged: (value) =>
                  onChanged(settings.copyWith(saturation: value.clamp(0, 1)))),
          SizedBox(height: Design.px(14)),
          _SliderRow(
              label: '色相跨度',
              hint: '色相最多能走多远：150° 是安全带，360° 是整圈',
              value: settings.hueSpanDeg.toDouble(),
              min: AmbientPalette.hueSpanMin,
              max: AmbientPalette.hueSpanMax,
              divisions: 21,
              display: '${settings.hueSpanDeg} °',
              onChanged: (value) => onChanged(settings.copyWith(
                  hueSpanDeg: value.round().clamp(150, 360)))),
          SizedBox(height: Design.px(14)),
          _SliderRow(
              label: '色相自转',
              hint: '质心不动时（副歌反复）靠时间把色相推着走',
              value: settings.hueRotateDegPerSec.toDouble(),
              min: 0,
              max: AmbientPalette.maxHueRotateDegPerSec,
              divisions: 30,
              display: '${settings.hueRotateDegPerSec} °/s',
              onChanged: (value) => onChanged(settings.copyWith(
                  hueRotateDegPerSec: value.round().clamp(0, 30)))),
          SizedBox(height: Design.px(14)),
          _SliderRow(
              label: '彩度上限',
              hint: '颜色最多能有多艳（0.22 是旧上限，0.32 才能出红绿）',
              value: settings.maxChromaHundredths.toDouble(),
              min: 10,
              max: 40,
              divisions: 30,
              display: settings.maxChromaValue.toStringAsFixed(2),
              onChanged: (value) => onChanged(settings.copyWith(
                  maxChromaHundredths: value.round().clamp(10, 40)))),
          SizedBox(height: Design.px(10)),
          Text(
            '想要五彩：把色相跨度拉到 360°，或直接选预设 彩虹'
            '（跨度 360° + 质心展开 + 彩度上限 0.32 + 18°/s 自转）。\n\n'
            '只拉跨度不展开质心的话，色相仍只走 100° 出头 —— '
            '真实音乐的谱质心只在 0.3~0.6 之间移动，必须把这段拉伸开。',
            key: const ValueKey('ambient-rainbow-note'),
            style: TextStyle(fontSize: Design.px(16), color: s.muted),
          ),
          SizedBox(height: Design.px(14)),
          _SliderRow(
              label: '色相跳变',
              hint: '0 是连续平滑；120° 是每次大跳 1/3 圈（三段一组）',
              value: settings.hueJumpDeg.toDouble(),
              min: 0,
              max: 180,
              divisions: 12,
              sliderKey: 'ambient-hue-jump',
              display: settings.hueJumpDeg == 0
                  ? '关（连续）'
                  : '${settings.hueJumpDeg}° 档',
              onChanged: (value) => onChanged(
                  settings.copyWith(hueJumpDeg: value.round().clamp(0, 180)))),
          SizedBox(height: Design.px(14)),
          _SliderRow(
              label: '起拍闪光',
              hint: '每次起拍把亮度顶多高：0.35× 是旧值，跳跃用 1.20×',
              value: settings.pulseGainHundredths.toDouble(),
              min: 0,
              max: 200,
              divisions: 40,
              sliderKey: 'ambient-pulse-gain',
              display:
                  '${(settings.pulseGainHundredths / 100).toStringAsFixed(2)}×',
              onChanged: (value) => onChanged(settings.copyWith(
                  pulseGainHundredths: value.round().clamp(0, 200)))),
          SizedBox(height: Design.px(14)),
          _SliderRow(
              label: '起拍间隔',
              hint: '两次起拍闪光之间至少隔多久：越小闪得越密',
              value: settings.beatMinGapMs.toDouble(),
              min: 80,
              max: 600,
              divisions: 26,
              sliderKey: 'ambient-beat-gap',
              display: '${settings.beatMinGapMs} ms',
              onChanged: (value) => onChanged(settings.copyWith(
                  beatMinGapMs: value.round().clamp(80, 600)))),
          SizedBox(height: Design.px(14)),
          _SliderRow(
              label: '换色间隔',
              hint: '没鼓点时也强制换色的上限：0 是只跟拍子',
              value: settings.jumpHoldMs.toDouble(),
              min: 0,
              max: 1000,
              divisions: 50,
              sliderKey: 'ambient-jump-hold',
              display: settings.jumpHoldMs == 0
                  ? '只跟拍子'
                  : '${settings.jumpHoldMs} ms 强制换',
              onChanged: (value) => onChanged(settings.copyWith(
                  jumpHoldMs:
                      value.round() == 0 ? 0 : value.round().clamp(80, 1000)))),
          SizedBox(height: Design.px(10)),
          Text(
            '想要「跳跃」：直接选预设 跳跃'
            '（色相跳变 120° + 起拍闪光 1.20× + 起拍间隔 120 ms + 换色间隔 380 ms）。\n\n'
            '色相跳变 0 是连续平滑，120° 是每次大跳 1/3 圈 —— 这不是「把平滑调快」'
            '能得到的：平滑越快只是把滑动缩短，跳变要直接落到档位上。'
            '跳变模式下每个起拍还会再前进一档；没鼓点时按「换色间隔」强制换，'
            '灯才会一直在闪，而不是定在一个颜色上。\n\n'
            '跳跃模式下两层 ΔE 限速都会关掉：限速器会把一次换色抹成十几帧的滑坡，'
            '那就是「还是太平顺」的来源。\n\n'
            '这一组晃眼，夜间行车建议换回 均衡 / 夜驾柔和；'
            '每拍换色 + 闪光是高频闪烁，对闪烁敏感 / 光敏性癫痫者不要用。',
            key: const ValueKey('ambient-jump-note'),
            style: TextStyle(fontSize: Design.px(16), color: s.muted),
          ),
          SizedBox(height: Design.px(14)),
          _SliderRow(
              label: '空闲呼吸',
              hint: '没有音乐时底光的呼吸幅度',
              value: settings.breath,
              min: 0,
              max: 0.4,
              divisions: 40,
              display: '${(settings.breath * 100).round()} %',
              onChanged: (value) =>
                  onChanged(settings.copyWith(breath: value.clamp(0, 0.4)))),
          SizedBox(height: Design.px(8)),
          Text(
            '新版在 60Hz 独立时钟上逐帧积分（频谱仍是 10Hz），'
            '颜色用 OKLCH 感知色空间，相邻帧的感知色差被硬限制在上面的上限内。\n\n'
            '色相限加速消除「甩过去再顿一下」；亮度起快落慢；'
            '空闲时色相缓慢漂移 + 呼吸底光，不是冻在最后一个颜色。',
            key: const ValueKey('ambient-engine-note'),
            style: TextStyle(fontSize: Design.px(16), color: s.muted),
          ),
        ], // custom mode sliders
      ],
    ]);
  }
}

/// The six parameter presets, plus 自定义.
///
/// Fifteen sliders are a lot to drag in a car, so the presets give six
/// ready made starting points. A preset is the front door: it hides every
/// slider and shows a read-only summary. 自定义 keeps the current values and
/// brings the sliders back.
class _PresetChips extends StatelessWidget {
  final AmbientLightSettings settings;
  final ValueChanged<AmbientLightSettings> onChanged;

  const _PresetChips({required this.settings, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final s = SurfaceStyle.of(context);
    final index = AmbientPresets.match(
      attackMs: settings.attackMs,
      decayMs: settings.decayMs,
      hueTauMs: settings.hueTauMs,
      hueMaxDeg: settings.hueMaxDeg,
      hueMaxAccel: settings.hueMaxAccel,
      maxDeltaE: settings.maxDeltaE,
      floor: settings.floor,
      breath: settings.breath,
      saturation: settings.saturation,
      hueSpanDeg: settings.hueSpanDeg,
      centroidWindowLowHundredths: settings.centroidWindowLowHundredths,
      centroidWindowSpanHundredths: settings.centroidWindowSpanHundredths,
      hueRotateDegPerSec: settings.hueRotateDegPerSec,
      maxChromaHundredths: settings.maxChromaHundredths,
      hueJumpDeg: settings.hueJumpDeg,
      pulseGainHundredths: settings.pulseGainHundredths,
      beatMinGapMs: settings.beatMinGapMs,
      jumpHoldMs: settings.jumpHoldMs,
    );
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        Text('预设', style: TextStyle(fontSize: Design.px(20))),
        const Spacer(),
        Text(
            settings.customMode || index < 0
                ? '自定义'
                : AmbientPresets.all[index].name,
            key: const ValueKey('ambient-preset-readout'),
            style: TextStyle(fontSize: Design.px(20), color: s.muted))
      ]),
      SizedBox(height: Design.px(10)),
      Wrap(spacing: Design.px(12), runSpacing: Design.px(12), children: [
        for (var i = 0; i < AmbientPresets.all.length; i++)
          ChoiceChip(
              key: ValueKey('ambient-preset-$i'),
              label: Text(AmbientPresets.all[i].name),
              selected: !settings.customMode && index == i,
              side: s.technicalFrame
                  ? s.controlSide(!settings.customMode && index == i)
                  : null,
              shape:
                  s.controlShape(selected: !settings.customMode && index == i),
              onSelected: (_) => onChanged(_apply(AmbientPresets.all[i]))),
        ChoiceChip(
            key: const ValueKey('ambient-preset-custom'),
            label: const Text('自定义'),
            selected: settings.customMode,
            side: s.technicalFrame ? s.controlSide(settings.customMode) : null,
            shape: s.controlShape(selected: settings.customMode),
            onSelected: (_) => onChanged(settings.copyWith(customMode: true)))
      ]),
    ]);
  }

  /// The preset applied to the current settings.
  ///
  /// Only the look and feel parameters are taken from the preset — the
  /// engine, the colour mode, the brightness and the zone choreography are
  /// the user's choices and must survive a preset switch.
  AmbientLightSettings _apply(AmbientPreset preset) => settings.copyWith(
        attackMs: preset.attackMs,
        decayMs: preset.decayMs,
        hueTauMs: preset.hueTauMs,
        hueMaxDeg: preset.hueMaxDeg,
        hueMaxAccel: preset.hueMaxAccel,
        maxDeltaE: preset.maxDeltaE,
        floor: preset.floor,
        breath: preset.breath,
        saturation: preset.saturation,
        hueSpanDeg: preset.hueSpanDeg,
        centroidWindowLowHundredths: preset.centroidWindowLowHundredths,
        centroidWindowSpanHundredths: preset.centroidWindowSpanHundredths,
        hueRotateDegPerSec: preset.hueRotateDegPerSec,
        maxChromaHundredths: preset.maxChromaHundredths,
        hueJumpDeg: preset.hueJumpDeg,
        pulseGainHundredths: preset.pulseGainHundredths,
        beatMinGapMs: preset.beatMinGapMs,
        jumpHoldMs: preset.jumpHoldMs,
        // Choosing a preset is a deliberate leave of the custom page.
        customMode: false,
      );
}

/// What a preset decided, without the sliders.
///
/// In preset mode the page stays short: the chip row names the preset, this
/// card lists the values it set, and one button opens the sliders again.
class _PresetSummary extends StatelessWidget {
  final AmbientLightSettings settings;
  final ValueChanged<AmbientLightSettings> onChanged;

  const _PresetSummary({required this.settings, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final s = SurfaceStyle.of(context);
    final index = _presetIndex(settings);
    final preset = index >= 0 ? AmbientPresets.all[index] : null;
    final rows = <String>[
      '亮度包络 ${settings.attackMs} / ${settings.decayMs} ms',
      '色相平滑 ${settings.hueTauMs} ms，限速 ${settings.hueMaxDeg} °/s',
      '每帧色差上限 ${settings.maxDeltaE.toStringAsFixed(1)} ΔE00',
      '色相跨度 ${settings.hueSpanDeg}°，彩度上限 '
          '${(settings.maxChromaHundredths / 100).toStringAsFixed(2)}',
      if (settings.hueJumpDeg > 0)
        '色相跳变 ${settings.hueJumpDeg}° 一档'
            '${settings.jumpHoldMs > 0 ? '，换色间隔 ${settings.jumpHoldMs} ms' : ''}'
      else
        '连续平滑（无色相跳变）',
      if (settings.hueRotateDegPerSec > 0)
        '色相自转 ${settings.hueRotateDegPerSec} °/s',
      '底光 ${settings.floor}%，呼吸 ${(settings.breath * 100).round()}%',
    ];
    return Container(
      key: const ValueKey('ambient-preset-summary'),
      padding: EdgeInsets.all(Design.px(16)),
      decoration: BoxDecoration(
        border: Border.all(color: s.muted.withValues(alpha: 0.25)),
        borderRadius: BorderRadius.circular(Design.px(12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(preset?.name ?? '自定义参数',
              style: TextStyle(fontSize: Design.px(20))),
          SizedBox(height: Design.px(8)),
          for (final row in rows)
            Padding(
              padding: EdgeInsets.only(bottom: Design.px(6)),
              child: Text(row,
                  style: TextStyle(fontSize: Design.px(16), color: s.muted)),
            ),
          SizedBox(height: Design.px(4)),
          Text(
            '预设模式不显示滑杆：想让这组参数变成自己的，点「自定义」把它们放出来。',
            style: TextStyle(fontSize: Design.px(16), color: s.muted),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              key: const ValueKey('ambient-preset-customize'),
              onPressed: () => onChanged(settings.copyWith(customMode: true)),
              child: const Text('自定义'),
            ),
          ),
        ],
      ),
    );
  }
}

/// The index of the preset the current parameters match, or -1.
int _presetIndex(AmbientLightSettings settings) => AmbientPresets.match(
      attackMs: settings.attackMs,
      decayMs: settings.decayMs,
      hueTauMs: settings.hueTauMs,
      hueMaxDeg: settings.hueMaxDeg,
      hueMaxAccel: settings.hueMaxAccel,
      maxDeltaE: settings.maxDeltaE,
      floor: settings.floor,
      breath: settings.breath,
      saturation: settings.saturation,
      hueSpanDeg: settings.hueSpanDeg,
      centroidWindowLowHundredths: settings.centroidWindowLowHundredths,
      centroidWindowSpanHundredths: settings.centroidWindowSpanHundredths,
      hueRotateDegPerSec: settings.hueRotateDegPerSec,
      maxChromaHundredths: settings.maxChromaHundredths,
      hueJumpDeg: settings.hueJumpDeg,
      pulseGainHundredths: settings.pulseGainHundredths,
      beatMinGapMs: settings.beatMinGapMs,
      jumpHoldMs: settings.jumpHoldMs,
    );

/// The zone choreography.
///
/// The head unit only has zone switches (no zone colour, no zone
/// brightness), so a zone switch is a hard edge. The choreography is
/// therefore slow and off by default: driving with the zones taking turns
/// is distracting.
class _ZoneChoreoSection extends StatelessWidget {
  final AmbientLightSettings settings;
  final ValueChanged<AmbientLightSettings> onChanged;

  const _ZoneChoreoSection({required this.settings, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final s = SurfaceStyle.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text('分区编排', style: TextStyle(fontSize: Design.px(20), color: s.muted)),
      SizedBox(height: Design.px(10)),
      Row(children: [
        Text('区域巡游', style: TextStyle(fontSize: Design.px(20))),
        const Spacer(),
        Switch(
            key: const ValueKey('ambient-zone-choreo'),
            value: settings.zoneChoreo,
            onChanged: (value) =>
                onChanged(settings.copyWith(zoneChoreo: value)))
      ]),
      SizedBox(height: Design.px(4)),
      Text('三个分区轮流点亮（仅建议驻车 / 展示时开启）',
          style: TextStyle(fontSize: Design.px(17), color: s.muted)),
      if (settings.zoneChoreo) ...[
        SizedBox(height: Design.px(14)),
        _SliderRow(
            label: '分区驻留',
            hint: '每个分区停留多久：低于 700ms 会看出硬边',
            value: settings.zoneDwellMs.toDouble(),
            min: 700,
            max: 2000,
            divisions: 26,
            display: '${settings.zoneDwellMs} ms',
            onChanged: (value) => onChanged(settings.copyWith(
                zoneDwellMs: value.round().clamp(700, 2000)))),
      ],
      SizedBox(height: Design.px(8)),
      Text(
        '这台车机只有分区开关，没有分区颜色和分区亮度，'
        '所以切换必然是硬边：一片亮、一片黑。\n\n'
        '编排用「先开新的、再关旧的」让中间态是多一片亮着，'
        '并把全局亮度补一点，总光通量不会明显凹陷。',
        style: TextStyle(fontSize: Design.px(16), color: s.muted),
      ),
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
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            ValueListenableBuilder<AmbientColor?>(
                valueListenable: service.color,
                builder: (context, color, _) {
                  final swatch =
                      color == null ? s.soft : Color(0xFF000000 | color.packed);
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
                      style:
                          TextStyle(fontSize: Design.px(20), color: s.muted)),
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
                // The key lets the emulator test measure the **filled width**
                // of this bar in rendered pixels: the bar is the brightness
                // on the glass, so its width is the proof that the
                // brightness really moves with the music.
                key: const ValueKey('ambient-brightness-bar'),
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
                    color == null
                        ? surface.edge
                        : Color(0xFF000000 | color.packed),
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
      final rect =
          Rect.fromLTWH((i + .5) * step - width / 2, size.height - h, width, h);
      canvas.drawRRect(RRect.fromRectAndRadius(rect, const Radius.circular(1)),
          value > .015 ? bar : track);
    }
  }

  @override
  bool shouldRepaint(_StripPainter old) =>
      old.ink != ink || old.edge != edge || !_same(old.levels, levels);

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
  final String? sliderKey;
  final ValueChanged<double> onChanged;

  const _SliderRow(
      {required this.label,
      required this.hint,
      required this.display,
      required this.value,
      required this.min,
      required this.max,
      required this.divisions,
      this.sliderKey,
      required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final s = SurfaceStyle.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
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
              key: ValueKey(sliderKey ?? 'ambient-slider-$label'),
              value: value.clamp(min, max),
              min: min,
              max: max,
              divisions: divisions,
              onChanged: onChanged))
    ]);
  }
}

/// Fixed hue presets plus a hue slider.
/// One frequency region: preset circles plus the shared colour picker.
class _RhythmColorCard extends StatelessWidget {
  final String id, label;
  final double hue;
  final String custom;
  final ValueChanged<(double, String)> onChanged;

  const _RhythmColorCard({
    required this.id,
    required this.label,
    required this.hue,
    required this.custom,
    required this.onChanged,
  });

  bool _matches(double preset) => (hue - preset).abs() < 1;

  @override
  Widget build(BuildContext context) {
    final s = SurfaceStyle.of(context);
    final customSelected = custom.isNotEmpty;
    final currentColor = customSelected
        ? Color(0xFF000000 | int.parse(custom.substring(1), radix: 16))
        : HSVColor.fromAHSV(1, hue, .85, 1).toColor();
    return GlassSurface(
        tone: SurfaceTone.soft,
        shadow: false,
        padding: EdgeInsets.all(Design.px(12)),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Text(label, style: TextStyle(fontSize: Design.px(20))),
            const Spacer(),
            Container(
                width: Design.px(24),
                height: Design.px(24),
                decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: currentColor,
                    border: Border.all(color: s.edge)))
          ]),
          SizedBox(height: Design.px(12)),
          LayoutBuilder(builder: (context, box) {
            final customColor = currentColor;
            Widget circle(
                    {required Color color,
                    required bool selected,
                    Key? key,
                    bool last = false,
                    Widget? child,
                    VoidCallback? onTap}) =>
                Padding(
                    padding: EdgeInsets.only(right: last ? 0 : Design.px(7)),
                    child: AspectRatio(
                        aspectRatio: 1,
                        child: Tooltip(
                            message: selected ? '$label·当前' : label,
                            child: InkWell(
                                key: key,
                                onTap: onTap,
                                child: Container(
                                    decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: color,
                                        border: Border.all(
                                            color: selected ? s.accent : s.edge,
                                            width: selected
                                                ? Design.px(4)
                                                : Design.px(1))),
                                    child: child)))));
            return Row(children: [
              for (final preset in AmbientPalette.fixedColors)
                Expanded(
                    child: circle(
                        key: ValueKey('ambient-$id-color-${preset.$1.toInt()}'),
                        color:
                            HSVColor.fromAHSV(1, preset.$1, .85, 1).toColor(),
                        selected: !customSelected && _matches(preset.$1),
                        onTap: () => onChanged((preset.$1, '')))),
              Expanded(
                  child: circle(
                      key: ValueKey('ambient-$id-custom'),
                      color: customSelected ? customColor : s.soft,
                      selected: customSelected,
                      last: true,
                      onTap: () async {
                        final value =
                            await _editRhythmColor(context, label, custom, hue);
                        if (value != null) {
                          final color = HSVColor.fromColor(Color(0xFF000000 |
                              int.parse(value.substring(1), radix: 16)));
                          onChanged((color.hue, value.toUpperCase()));
                        }
                      },
                      child: Icon(
                        Icons.tune,
                        size: Design.px(21),
                        color: customSelected
                            ? (ThemeData.estimateBrightnessForColor(
                                        customColor) ==
                                    Brightness.dark
                                ? Colors.white
                                : Colors.black)
                            : s.muted,
                      )))
            ]);
          })
        ]));
  }
}

Future<String?> _editRhythmColor(
    BuildContext context, String label, String custom, double initial) async {
  final result = await showCustomColorPicker(context,
      title: '自定义$label颜色',
      subtitle: '从完整色域取色，或选择常用颜色',
      initial: custom.isNotEmpty
          ? Color(0xFF000000 | int.parse(custom.substring(1), radix: 16))
          : HSVColor.fromAHSV(1, initial, .85, 1).toColor(),
      presets: [
        for (final preset in AmbientPalette.fixedColors)
          HSVColor.fromAHSV(1, preset.$1, .85, 1).toColor(),
        ...standardPickerColors
      ]);
  if (result == null) return null;
  return result.toUpperCase();
}

class _HueRow extends StatelessWidget {
  final double hue;
  final ValueChanged<double> onChanged;

  const _HueRow({required this.hue, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final s = SurfaceStyle.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text('固定颜色', style: TextStyle(fontSize: Design.px(20), color: s.muted)),
      SizedBox(height: Design.px(10)),
      Wrap(spacing: Design.px(12), runSpacing: Design.px(12), children: [
        for (final preset in AmbientPalette.fixedColors)
          InkWell(
              key: ValueKey('ambient-hue-${preset.$1.toInt()}'),
              onTap: () => onChanged(preset.$1),
              child: Container(
                  width: Design.px(40),
                  height: Design.px(40),
                  decoration: BoxDecoration(
                      color: HSVColor.fromAHSV(1, preset.$1, .82, 1).toColor(),
                      borderRadius: BorderRadius.circular(s.radius * .4),
                      border: Border.all(
                          color:
                              (hue - preset.$1).abs() < 1 ? s.accent : s.edge,
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
