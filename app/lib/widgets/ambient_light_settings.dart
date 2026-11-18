import 'package:flutter/material.dart';

import 'choice_button.dart';
import 'setting_block.dart';

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
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _LampBlock(settings: settings, onChanged: onChanged),
      SizedBox(height: Design.dz(8)),
      _SliderBlock(settings: settings, onChanged: onChanged),
      SizedBox(height: Design.dz(8)),
      _ZoneBlock(settings: settings, onChanged: onChanged),
      if (service.needsPermission) ...[
        SizedBox(height: Design.dz(10)),
        Align(
            alignment: Alignment.centerLeft,
            child: DesignSmallAction('授权录音权限以启用频谱',
                key: const ValueKey('ambient-request-permission'),
                onPressed: service.spectrum.requestPermission))
      ],
      SizedBox(height: Design.dz(12)),
      const DesignFieldLabel('实时状态'),
      SizedBox(height: Design.dz(8)),
      AmbientLightPreview(service: service, settings: settings),
    ]);
  }
}

/// f13 第一块：开关在标题行右端，下面分两列 —— 左「颜色跟随」、右「动感引擎」。
class _LampBlock extends StatelessWidget {
  final AmbientLightSettings settings;
  final ValueChanged<AmbientLightSettings> onChanged;

  const _LampBlock({required this.settings, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final s = SurfaceStyle.of(context);
    final rhythm = settings.engine == AmbientLightSettings.engineRhythm;
    return SettingBlock(
        title: '音乐律动氛围灯',
        note: '按正在播放的音乐频谱换算颜色与亮度',
        padding: EdgeInsets.fromLTRB(
            Design.dz(17), Design.dz(10), Design.dz(17), Design.dz(11)),
        trailing: DesignSwitch(
            key: const ValueKey('ambient-light-switch'),
            value: settings.enabled,
            semanticLabel: '音乐律动氛围灯',
            onChanged: (value) => onChanged(settings.copyWith(enabled: value))),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Container(height: Design.dz(1), color: s.text.withValues(alpha: .07)),
          SizedBox(height: Design.dz(9)),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
                child: _ColourColumn(settings: settings, onChanged: onChanged)),
            SizedBox(width: Design.dz(40)),
            Expanded(
                child: _EngineColumn(settings: settings, onChanged: onChanged)),
          ]),
          // 节奏引擎把频段映射到三个颜色区，取色面板只能整行铺开。
          if (rhythm && settings.mode == AmbientPalette.modeSpectrum) ...[
            SizedBox(height: Design.dz(12)),
            const DesignFieldLabel('低频 / 中频 / 高频 分别取色'),
            SizedBox(height: Design.dz(8)),
            Row(children: [
              Expanded(
                  child: _RhythmColorCard(
                      id: 'bass',
                      label: '低频',
                      hue: settings.bassHue,
                      custom: settings.bassCustom,
                      onChanged: (selection) => onChanged(settings.copyWith(
                          bassHue: selection.$1, bassCustom: selection.$2)))),
              SizedBox(width: Design.dz(14)),
              Expanded(
                  child: _RhythmColorCard(
                      id: 'mid',
                      label: '中频',
                      hue: settings.midHue,
                      custom: settings.midCustom,
                      onChanged: (selection) => onChanged(settings.copyWith(
                          midHue: selection.$1, midCustom: selection.$2)))),
              SizedBox(width: Design.dz(14)),
              Expanded(
                  child: _RhythmColorCard(
                      id: 'treble',
                      label: '高频',
                      hue: settings.trebleHue,
                      custom: settings.trebleCustom,
                      onChanged: (selection) => onChanged(settings.copyWith(
                          trebleHue: selection.$1,
                          trebleCustom: selection.$2)))),
            ]),
          ],
        ]));
  }
}

/// 左列：颜色跟随三档 + （固定色时才有的）氛围灯色彩。
class _ColourColumn extends StatelessWidget {
  final AmbientLightSettings settings;
  final ValueChanged<AmbientLightSettings> onChanged;

  const _ColourColumn({required this.settings, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final fixed = settings.mode == AmbientPalette.modeFixed;
    return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const DesignFieldLabel('颜色跟随'),
          SizedBox(height: Design.dz(8)),
          Wrap(
              spacing: Design.dz(11.67),
              runSpacing: Design.dz(11.67),
              children: [
                for (var mode = 0;
                    mode < AmbientPalette.modeLabels.length;
                    mode++)
                  ambientChip(
                      key: ValueKey('ambient-mode-$mode'),
                      label: AmbientPalette.modeLabels[mode],
                      selected: settings.mode == mode,
                      onTap: () => onChanged(settings.copyWith(mode: mode)))
              ]),
          SizedBox(height: Design.dz(10)),
          // 设计稿这一排色点常驻。点一下就是「用这个颜色」——顺带把
          // 「颜色跟随」切到 固定色，否则改了 fixedHue 灯不会变色。
          const DesignFieldLabel('氛围灯色彩'),
          SizedBox(height: Design.dz(8)),
          _HueRow(
              hue: settings.fixedHue,
              active: fixed,
              showSlider: fixed,
              onChanged: (hue) => onChanged(settings.copyWith(
                  fixedHue: hue, mode: AmbientPalette.modeFixed))),
        ]);
  }
}

/// 右列：动感引擎三档 + 预设。
class _EngineColumn extends StatelessWidget {
  final AmbientLightSettings settings;
  final ValueChanged<AmbientLightSettings> onChanged;

  const _EngineColumn({required this.settings, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final s = SurfaceStyle.of(context);
    final v2 = settings.engine == AmbientLightSettings.engineV2;
    final index = !v2
        ? -1
        : AmbientPresets.match(
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
    return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const DesignFieldLabel('动感引擎'),
          SizedBox(height: Design.dz(8)),
          Wrap(
              spacing: Design.dz(11.67),
              runSpacing: Design.dz(11.67),
              children: [
                for (var engine = 0; engine < 3; engine++)
                  ambientChip(
                      key: ValueKey('ambient-engine-$engine'),
                      label: kAmbientEngineLabels[engine],
                      selected: settings.engine == engine,
                      onTap: () => onChanged(settings.copyWith(engine: engine)))
              ]),
          if (v2) ...[
            SizedBox(height: Design.dz(10)),
            const DesignFieldLabel('预设'),
            SizedBox(height: Design.dz(8)),
            Wrap(
                spacing: Design.dz(11.67),
                runSpacing: Design.dz(11.67),
                children: [
                  for (var i = 0; i < AmbientPresets.all.length; i++)
                    ambientChip(
                        key: ValueKey('ambient-preset-$i'),
                        label: AmbientPresets.all[i].name,
                        selected: !settings.customMode && index == i,
                        onTap: () =>
                            onChanged(_apply(settings, AmbientPresets.all[i]))),
                  ambientChip(
                      key: const ValueKey('ambient-preset-custom'),
                      label: '自定义',
                      selected: settings.customMode,
                      onTap: () =>
                          onChanged(settings.copyWith(customMode: true)))
                ]),
            if (!settings.customMode && index >= 0) ...[
              SizedBox(height: Design.dz(6)),
              Text(AmbientPresets.all[index].summary,
                  key: const ValueKey('ambient-preset-summary'),
                  style: TextStyle(
                      fontSize: Design.dz(12.5), height: 1.45, color: s.muted))
            ],
          ],
        ]);
  }

  /// The preset applied to the current settings.
  ///
  /// Only the look and feel parameters are taken from the preset — the
  /// engine, the colour mode, the brightness and the zone choreography are
  /// the user's choices and must survive a preset switch.
  static AmbientLightSettings _apply(
          AmbientLightSettings settings, AmbientPreset preset) =>
      settings.copyWith(
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

const List<String> kAmbientEngineLabels = [
  '新版（流畅）',
  '旧版（现网观感）',
  '节奏（峰值冲击）',
];

/// f13 第二块：两列滑杆（`#f13 .sl2`）。
///
/// 左列是亮度与节拍，右列是动感引擎参数。设计稿把全部滑杆都摆在明面上，
/// 预设只负责「填值」，不再是「一个只看的摘要页」—— 所以这里不再按
/// 预设/自定义把滑杆藏起来。
class _SliderBlock extends StatelessWidget {
  final AmbientLightSettings settings;
  final ValueChanged<AmbientLightSettings> onChanged;

  const _SliderBlock({required this.settings, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final s = SurfaceStyle.of(context);
    final v2 = settings.engine == AmbientLightSettings.engineV2;
    final legacy = settings.engine == AmbientLightSettings.engineLegacy;
    final rhythm = settings.engine == AmbientLightSettings.engineRhythm;

    final bright = <Widget>[
      if (rhythm)
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
      // 亮度上下限是旧版链路的参数（旧版是「下限 + (上限−下限)×电平^γ」
      // 的线性映射）。新版压根不读这两个值，放在这儿拖了没反应，只能藏起来。
      if (legacy) ...[
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
      if (v2) ...[
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
        _SliderRow(
            label: '起拍间隔',
            hint: '两次起拍闪光之间至少隔多久：越小闪得越密',
            value: settings.beatMinGapMs.toDouble(),
            min: 80,
            max: 600,
            divisions: 26,
            sliderKey: 'ambient-beat-gap',
            display: '${settings.beatMinGapMs}ms',
            onChanged: (value) => onChanged(
                settings.copyWith(beatMinGapMs: value.round().clamp(80, 600)))),
      ],
    ];

    final colour = <Widget>[
      if (v2) ...[
        _SliderRow(
            label: '亮度起 attack',
            hint: '声音变大时颜色变亮的快慢',
            value: settings.attackMs.toDouble(),
            min: 10,
            max: 300,
            divisions: 58,
            display: '${settings.attackMs}',
            onChanged: (value) => onChanged(
                settings.copyWith(attackMs: value.round().clamp(10, 300)))),
        _SliderRow(
            label: '亮度落 decay',
            hint: '声音变小后颜色变暗的快慢（越慢越有余韵）',
            value: settings.decayMs.toDouble(),
            min: 60,
            max: 1200,
            divisions: 57,
            display: '${settings.decayMs}',
            onChanged: (value) => onChanged(
                settings.copyWith(decayMs: value.round().clamp(60, 1200)))),
        _SliderRow(
            label: '色相平滑 τ',
            hint: '颜色在色相环上移动时的时间常数',
            value: settings.hueTauMs.toDouble(),
            min: 60,
            max: 1200,
            divisions: 57,
            display: (settings.hueTauMs / 1000).toStringAsFixed(2),
            onChanged: (value) => onChanged(
                settings.copyWith(hueTauMs: value.round().clamp(60, 1200)))),
        _SliderRow(
            label: '色相跨度',
            hint: '色相最多能走多远：150° 是安全带，360° 是整圈',
            value: settings.hueSpanDeg.toDouble(),
            min: AmbientPalette.hueSpanMin,
            max: AmbientPalette.hueSpanMax,
            divisions: 21,
            display: '${settings.hueSpanDeg}°',
            onChanged: (value) => onChanged(
                settings.copyWith(hueSpanDeg: value.round().clamp(150, 360)))),
        _SliderRow(
            label: '饱和度上限',
            hint: '颜色最多能有多艳',
            value: settings.saturation,
            min: 0,
            max: 1,
            divisions: 100,
            display: '${(settings.saturation * 100).round()}',
            onChanged: (value) =>
                onChanged(settings.copyWith(saturation: value.clamp(0, 1)))),
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
        _SliderRow(
            label: '每帧色差上限',
            hint: '相邻两帧允许的最大感知色差（ΔE00），越小越平滑',
            value: settings.maxDeltaE,
            min: 0.2,
            max: 6.0,
            divisions: 58,
            display: settings.maxDeltaE.toStringAsFixed(1),
            onChanged: (value) =>
                onChanged(settings.copyWith(maxDeltaE: value.clamp(0.2, 6.0)))),
        _SliderRow(
            label: '色相限速',
            hint: '颜色每秒最多转多少度',
            value: settings.hueMaxDeg.toDouble(),
            min: 10,
            max: 180,
            divisions: 17,
            display: '${settings.hueMaxDeg}°/s',
            onChanged: (value) => onChanged(
                settings.copyWith(hueMaxDeg: value.round().clamp(10, 180)))),
        _SliderRow(
            label: '色相限加速',
            hint: '色相加速的上限：消掉「甩过去再顿一下」',
            value: settings.hueMaxAccel.toDouble(),
            min: 30,
            max: 800,
            divisions: 77,
            display: '${settings.hueMaxAccel}',
            onChanged: (value) => onChanged(
                settings.copyWith(hueMaxAccel: value.round().clamp(30, 800)))),
        _SliderRow(
            label: '色相自转',
            hint: '质心不动时（副歌反复）靠时间把色相推着走',
            value: settings.hueRotateDegPerSec.toDouble(),
            min: 0,
            max: AmbientPalette.maxHueRotateDegPerSec,
            divisions: 30,
            display: '${settings.hueRotateDegPerSec}°/s',
            onChanged: (value) => onChanged(settings.copyWith(
                hueRotateDegPerSec: value.round().clamp(0, 30)))),
        _SliderRow(
            label: '色相跳变',
            hint: '0 是连续平滑；120° 是每次大跳 1/3 圈（三段一组）',
            value: settings.hueJumpDeg.toDouble(),
            min: 0,
            max: 180,
            divisions: 12,
            sliderKey: 'ambient-hue-jump',
            display: settings.hueJumpDeg == 0 ? '关' : '${settings.hueJumpDeg}°',
            onChanged: (value) => onChanged(
                settings.copyWith(hueJumpDeg: value.round().clamp(0, 180)))),
        _SliderRow(
            label: '换色间隔',
            hint: '没鼓点时也强制换色的上限：0 是只跟拍子',
            value: settings.jumpHoldMs.toDouble(),
            min: 0,
            max: 1000,
            divisions: 50,
            sliderKey: 'ambient-jump-hold',
            display: settings.jumpHoldMs == 0 ? '跟拍' : '${settings.jumpHoldMs}',
            onChanged: (value) => onChanged(settings.copyWith(
                jumpHoldMs:
                    value.round() == 0 ? 0 : value.round().clamp(80, 1000)))),
      ],
    ];

    return SettingBlock(
        padding: EdgeInsets.fromLTRB(
            Design.dz(17), Design.dz(10), Design.dz(17), Design.dz(11)),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                const DesignFieldLabel('亮度与节拍'),
                SizedBox(height: Design.dz(2)),
                ...bright
              ])),
          SizedBox(width: Design.dz(40)),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                DesignFieldLabel(v2
                    ? '动感引擎参数 · ${kAmbientEngineLabels[settings.engine]}'
                    : '动感引擎参数'),
                SizedBox(height: Design.dz(2)),
                if (v2)
                  ...colour
                else
                  Padding(
                      padding: EdgeInsets.only(top: Design.dz(6)),
                      child: Text(
                        rhythm
                            ? '节奏引擎每拍写一次峰值（颜色 + 车机高亮档）与一次谷值'
                                '（暗一档），两拍之间不写，所以是「一拍一个冲击」'
                                '而不是连续流动。\n\n'
                                '低频／中频／高频各有一个颜色区域，可以在上面分别取色。'
                            : '旧版是实车验证过的现网链路：10Hz 步进、HSV 配色、'
                                '亮度线性缩放。\n\n'
                                '它被评价为「灯在跳，不是灯在流动」。保留它是为了在'
                                '同一台车、同一首歌上直接对比。',
                        key: const ValueKey('ambient-engine-note'),
                        style: TextStyle(
                            fontSize: Design.dz(12.5),
                            height: 1.5,
                            color: s.muted),
                      )),
              ])),
        ]));
  }
}

/// f13 第三块：分区编排（`.set-row` + 三段分区条 + 分区名）。
class _ZoneBlock extends StatelessWidget {
  final AmbientLightSettings settings;
  final ValueChanged<AmbientLightSettings> onChanged;

  const _ZoneBlock({required this.settings, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final s = SurfaceStyle.of(context);
    Widget bar(bool active) => Expanded(
        child: Container(
            height: Design.dz(18),
            decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(Design.dz(9)),
                gradient: active
                    ? LinearGradient(
                        colors: [s.accent, s.accentLo],
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight)
                    : null,
                color: active ? null : s.accent.withValues(alpha: .22))));
    return SettingBlock(
        padding: EdgeInsets.fromLTRB(
            Design.dz(17), Design.dz(12), Design.dz(17), Design.dz(15)),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SettingRow(
              label: '分区编排 · 区域巡游',
              note: '三个分区轮流点亮（仅建议驻车 / 展示时开启）',
              height: 44,
              divider: false,
              trailing: DesignSwitch(
                  key: const ValueKey('ambient-zone-choreo'),
                  value: settings.zoneChoreo,
                  semanticLabel: '分区编排',
                  onChanged: (value) =>
                      onChanged(settings.copyWith(zoneChoreo: value)))),
          SizedBox(height: Design.dz(6)),
          Row(children: [
            bar(true),
            SizedBox(width: Design.dz(7)),
            bar(false),
            SizedBox(width: Design.dz(7)),
            bar(false)
          ]),
          SizedBox(height: Design.dz(6)),
          Row(children: [
            for (final (index, label) in const ['主驾区', '中控区', '副驾区'].indexed)
              Expanded(
                  child: Text(label,
                      textAlign: index == 0
                          ? TextAlign.left
                          : (index == 1 ? TextAlign.center : TextAlign.right),
                      style:
                          TextStyle(fontSize: Design.dz(12), color: s.muted)))
          ]),
          if (settings.zoneChoreo) ...[
            SizedBox(height: Design.dz(6)),
            _SliderRow(
                label: '分区驻留',
                hint: '每个分区停留多久：低于 700ms 会看出硬边',
                value: settings.zoneDwellMs.toDouble(),
                min: 700,
                max: 2000,
                divisions: 26,
                display: '${settings.zoneDwellMs}ms',
                onChanged: (value) => onChanged(settings.copyWith(
                    zoneDwellMs: value.round().clamp(700, 2000))))
          ],
          SizedBox(height: Design.dz(6)),
          Text(
            '这台车机只有分区开关，没有分区颜色和分区亮度，所以切换必然是硬边：'
            '一片亮、一片黑。编排用「先开新的、再关旧的」让中间态是多一片亮着。',
            style:
                TextStyle(fontSize: Design.dz(12), height: 1.5, color: s.muted),
          ),
        ]));
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

  /// `.sl2 .slrow`：40 高单行 —— 104 宽标签 + 轨道 + 42 宽读数。
  ///
  /// 设计稿的滑杆行没有说明文字，这里把说明挂到长按提示上：车内是一块
  /// 触屏，长按出一个 tooltip 比在每行底下塞一句 12.5 号灰字更省版面。
  @override
  Widget build(BuildContext context) {
    final s = SurfaceStyle.of(context);
    return SizedBox(
        height: Design.dz(40),
        child: Row(children: [
          SizedBox(
              width: Design.dz(104),
              child: Tooltip(
                  message: hint,
                  waitDuration: const Duration(milliseconds: 500),
                  child: Text(label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: Design.dz(14.5), color: s.muted)))),
          Expanded(
              child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                      trackHeight: Design.dz(6),
                      activeTrackColor: s.accent,
                      inactiveTrackColor: s.text.withValues(alpha: .12),
                      // 拇指自己画渐变，这里只兜底：浅色底上仍要白。
                      thumbColor: s.dark ? s.text : Colors.white,
                      overlayShape: SliderComponentShape.noOverlay,
                      thumbShape: _PillThumbShape(
                          surface: s, width: 15, height: 26, radius: 8),
                      showValueIndicator: ShowValueIndicator.never),
                  child: Padding(
                      padding: EdgeInsets.symmetric(horizontal: Design.dz(8)),
                      child: Slider(
                          key: ValueKey(sliderKey ?? 'ambient-slider-$label'),
                          value: value.clamp(min, max),
                          min: min,
                          max: max,
                          divisions: divisions,
                          onChanged: onChanged)))),
          SizedBox(
              width: Design.dz(48),
              child: Text(display,
                  textAlign: TextAlign.right,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: Design.dz(13.5), color: s.muted))),
        ]));
  }
}

/// `.sld b`：15×26 的竖胶囊滑块，白色→#E2EAE6 的竖向渐变 + 一圈浅光。
class _PillThumbShape extends SliderComponentShape {
  final SurfaceStyle surface;
  final double width, height, radius;

  const _PillThumbShape(
      {required this.surface,
      required this.width,
      required this.height,
      required this.radius});

  @override
  Size getPreferredSize(bool isEnabled, bool isDiscrete) =>
      Size(Design.dz(width), Design.dz(height));

  @override
  void paint(PaintingContext context, Offset center,
      {required Animation<double> activationAnimation,
      required Animation<double> enableAnimation,
      required bool isDiscrete,
      required TextPainter labelPainter,
      required RenderBox parentBox,
      required SliderThemeData sliderTheme,
      required TextDirection textDirection,
      required double value,
      required double textScaleFactor,
      required Size sizeWithOverflow}) {
    final rect = Rect.fromCenter(
        center: center, width: Design.dz(width), height: Design.dz(height));
    final rrect =
        RRect.fromRectAndRadius(rect, Radius.circular(Design.dz(radius)));
    // 这颗滑块的「白」不能取 surface.text：暗色皮肤下它正好是白，浅色下是深墨，
    // 于是同一颗胶囊在浅色里变成一根深灰柱子。浅色固定用白→#E7EEEA 的竖渐变，
    // 投影也收轻一档（白底上 40% 黑太重）。
    final paint = Paint()
      ..shader = LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: surface.dark
                  ? [surface.text, const Color(0xFFE2EAE6)]
                  : [Colors.white, const Color(0xFFE7EEEA)])
          .createShader(rect);
    context.canvas.drawShadow(
        Path()..addRRect(rrect),
        surface.dark ? const Color(0x66000000) : const Color(0x33000000),
        Design.dz(3),
        true);
    context.canvas.drawRRect(rrect, paint);
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

  /// 「颜色跟随」在 固定色 时才给色点挂描边、才显示色相滑杆：
  /// 跟随频谱时颜色由频谱算，这里点一下会顺手把模式切过去。
  final bool active;
  final bool showSlider;
  final ValueChanged<double> onChanged;

  const _HueRow(
      {required this.hue,
      required this.active,
      required this.showSlider,
      required this.onChanged});

  /// `.adot`：44×44、15 圆角、上亮下暗的竖向渐变 + 顶部一道高光；
  /// 选中的那个在 3px 外再套一圈 2px 的主题色描边。
  @override
  Widget build(BuildContext context) {
    final s = SurfaceStyle.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Wrap(spacing: Design.dz(20), runSpacing: Design.dz(12), children: [
        for (final preset in AmbientPalette.fixedColors)
          InkWell(
              key: ValueKey('ambient-hue-${preset.$1.toInt()}'),
              onTap: () => onChanged(preset.$1),
              borderRadius: BorderRadius.circular(Design.dz(24)),
              child: _Adot(
                  hue: preset.$1,
                  // 描边只认当前色相，不再要求「固定色」模式：跟随频谱时
                  // 这一颗也是颜色的基准，界面上必须看得出选的是哪颗。
                  selected: (hue - preset.$1).abs() < 1))
      ]),
      if (showSlider) ...[
        SizedBox(height: Design.dz(10)),
        SizedBox(
            height: Design.dz(34),
            child: SliderTheme(
                data: SliderTheme.of(context).copyWith(
                    trackHeight: Design.dz(6),
                    activeTrackColor:
                        HSVColor.fromAHSV(1, hue, .82, 1).toColor(),
                    inactiveTrackColor: s.text.withValues(alpha: .12),
                    overlayShape: SliderComponentShape.noOverlay,
                    thumbShape: _PillThumbShape(
                        surface: s, width: 15, height: 26, radius: 8),
                    showValueIndicator: ShowValueIndicator.never),
                child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: Design.dz(8)),
                    child: Slider(
                        key: const ValueKey('ambient-hue-slider'),
                        value: hue.clamp(0, 360),
                        min: 0,
                        max: 360,
                        divisions: 36,
                        onChanged: onChanged))))
      ]
    ]);
  }
}

/// 一个 `.adot` 色块（44 的渐变方块 + 选中描边）。
class _Adot extends StatelessWidget {
  final double hue;
  final bool selected;
  const _Adot({required this.hue, required this.selected});

  @override
  Widget build(BuildContext context) {
    final s = SurfaceStyle.of(context);
    final base = HSVColor.fromAHSV(1, hue, .82, 1).toColor();
    return Container(
        width: Design.dz(54),
        height: Design.dz(54),
        decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
                color: selected
                    ? s.accent.withValues(alpha: .55)
                    : Colors.transparent,
                width: Design.dz(2))),
        alignment: Alignment.center,
        child: Container(
            width: Design.dz(44),
            height: Design.dz(44),
            decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(Design.dz(15)),
                gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Color.lerp(base, Colors.white, .38)!,
                      base,
                      Color.lerp(base, Colors.black, .3)!
                    ],
                    stops: const [
                      0,
                      .55,
                      1
                    ]),
                boxShadow: [
                  BoxShadow(
                      color: Colors.black.withValues(alpha: .45),
                      blurRadius: Design.dz(14),
                      offset: Offset(0, Design.dz(6)),
                      spreadRadius: -Design.dz(6)),
                  BoxShadow(
                      color: Colors.white.withValues(alpha: .2),
                      blurRadius: Design.dz(3),
                      offset: Offset(0, Design.dz(2)),
                      spreadRadius: -Design.dz(1))
                ]),
            child: Align(
                alignment: Alignment.topCenter,
                child: FractionallySizedBox(
                    heightFactor: .45,
                    child: Container(
                        margin: EdgeInsets.fromLTRB(
                            Design.dz(3), Design.dz(2), Design.dz(3), 0),
                        decoration: BoxDecoration(
                            borderRadius: const BorderRadius.vertical(
                                top: Radius.circular(12),
                                bottom: Radius.circular(10)),
                            gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  Colors.white.withValues(alpha: .32),
                                  Colors.white.withValues(alpha: 0)
                                ])))))));
  }
}

/// 氛围灯页的选项胶囊：sim `.chip`（47 高、26 内距、选中渐变实心）。
Widget ambientChip(
        {Key? key,
        required String label,
        required bool selected,
        required VoidCallback onTap}) =>
    ChoiceButton(
        key: key,
        height: Design.controlHeight,
        radius: 14,
        shrink: true,
        selected: selected,
        onPressed: onTap,
        padding: EdgeInsets.symmetric(horizontal: Design.dz(26)),
        child: Text(label, style: TextStyle(fontSize: Design.dz(16))));
