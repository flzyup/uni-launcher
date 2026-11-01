import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uni_launcher/model/ambient_light.dart';
import 'package:uni_launcher/model/ambient_presets.dart';
import 'package:uni_launcher/model/appearance.dart';
import 'package:uni_launcher/platform/ambient_light.dart';
import 'package:uni_launcher/platform/audio_spectrum.dart';
import 'package:uni_launcher/theme/launcher_theme.dart';
import 'package:uni_launcher/widgets/ambient_light_settings.dart';

/// The V2 part of the ambient light settings page.
///
/// The page is the only place where the engine, the presets and the nine
/// parameters can be changed, so a wiring mistake there is invisible to
/// every other test.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const methods = MethodChannel('test/ambient-light-settings');
  const spectrumMethods = MethodChannel('test/ambient-light-settings-spectrum');
  const spectrumEvents = EventChannel('test/ambient-light-settings-events');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  late AmbientLightService service;
  late List<AmbientLightSettings> changes;

  setUp(() {
    messenger.setMockMethodCallHandler(methods, (call) async => null);
    messenger.setMockMethodCallHandler(spectrumMethods, (call) async {
      if (call.method == 'status') {
        return {
          'granted': true,
          'available': true,
          'status': 'listening',
          'levels': List.filled(24, 0.3)
        };
      }
      return null;
    });
    messenger.setMockMethodCallHandler(MethodChannel(spectrumEvents.name),
        (call) async => null);
    service = AmbientLightService(
      methods: methods,
      spectrum: AudioSpectrumService(
          methods: spectrumMethods, events: spectrumEvents),
    );
    changes = [];
  });

  tearDown(() {
    service.dispose();
    messenger.setMockMethodCallHandler(methods, null);
    messenger.setMockMethodCallHandler(spectrumMethods, null);
    messenger.setMockMethodCallHandler(MethodChannel(spectrumEvents.name), null);
  });

  Future<void> show(WidgetTester t, AmbientLightSettings settings) async {
    t.view.physicalSize = const Size(1920, 1080);
    t.view.devicePixelRatio = 1;
    addTearDown(() {
      t.view.resetPhysicalSize();
      t.view.resetDevicePixelRatio();
    });
    await t.pumpWidget(MaterialApp(
        theme: launcherTheme(SurfaceStyle.from(const Appearance(), true)),
        home: Scaffold(
            body: SingleChildScrollView(
                child: SizedBox(
          width: 900,
          child: AmbientLightSettingsPanel(
            settings: settings,
            service: service,
            onChanged: (next) => changes.add(next),
          ),
        )))));
    await t.pumpAndSettle();
  }

  /// Taps a widget that may be below the fold.
  ///
  /// The settings page is one long column: the zone section sits at the
  /// bottom, so a plain tap would hit whatever is on the screen instead.
  Future<void> tap(WidgetTester t, Finder finder) async {
    await t.ensureVisible(finder);
    await t.pumpAndSettle();
    await t.tap(finder);
    await t.pumpAndSettle();
  }

  testWidgets('the engine chips switch the chain', (t) async {
    await show(t, const AmbientLightSettings());
    expect(find.byKey(const ValueKey('ambient-engine-0')), findsOneWidget);
    expect(find.byKey(const ValueKey('ambient-engine-1')), findsOneWidget);

    await tap(t, find.byKey(const ValueKey('ambient-engine-1')));
    expect(changes.last.engine, AmbientLightSettings.engineLegacy);
  });

  testWidgets('the legacy engine hides the parameter sliders', (t) async {
    // The V2 engine starts in preset mode: the sliders are hidden until 自定义.
    await show(t, const AmbientLightSettings());
    expect(find.byKey(const ValueKey('ambient-slider-亮度起 attack')),
        findsNothing);
    expect(find.byKey(const ValueKey('ambient-preset-summary')), findsOneWidget);

    await show(t, const AmbientLightSettings(
        engine: AmbientLightSettings.engineLegacy));
    expect(find.byKey(const ValueKey('ambient-slider-亮度起 attack')),
        findsNothing);
    // The engine note explains why there is nothing to tune.
    expect(find.byKey(const ValueKey('ambient-engine-note')), findsOneWidget);
  });

  testWidgets('a preset hides the sliders and 自定义 shows them again',
      (t) async {
    await show(t, const AmbientLightSettings());

    // Preset mode: chips + summary, no sliders.
    expect(find.byKey(const ValueKey('ambient-preset-summary')), findsOneWidget);
    expect(find.byKey(const ValueKey('ambient-slider-色相跨度')), findsNothing);
    expect(find.byKey(const ValueKey('ambient-slider-灵敏度')), findsNothing);
    expect(find.byKey(const ValueKey('ambient-zone-choreo')), findsNothing);
    // The default values are exactly the 均衡 preset, so it is the readout.
    expect(find.byKey(const ValueKey('ambient-preset-readout')), findsOneWidget);

    await tap(t, find.byKey(const ValueKey('ambient-preset-custom')));
    expect(changes.last.customMode, isTrue);
    // Applying a preset leaves the custom page again.
    await tap(t, find.byKey(const ValueKey('ambient-preset-2')));
    expect(changes.last.customMode, isFalse);

    await show(t, const AmbientLightSettings(customMode: true));
    expect(find.byKey(const ValueKey('ambient-preset-summary')), findsNothing);
    expect(find.byKey(const ValueKey('ambient-slider-色相跨度')), findsOneWidget);
    expect(find.byKey(const ValueKey('ambient-slider-灵敏度')), findsOneWidget);
    expect(find.byKey(const ValueKey('ambient-zone-choreo')), findsOneWidget);
  });

  testWidgets('the brightness bounds belong to the legacy chain only',
      (t) async {
    // The legacy chain maps the level linearly into [最低亮度, 最高亮度].
    // The V2 chain uses the perceptual window (基础亮度 + 区间映射) and never
    // reads those two values — a slider that does nothing must not be shown.
    await show(t, const AmbientLightSettings(customMode: true));
    expect(find.byKey(const ValueKey('ambient-slider-最低亮度')), findsNothing);
    expect(find.byKey(const ValueKey('ambient-slider-最高亮度')), findsNothing);
    expect(find.byKey(const ValueKey('ambient-slider-基础亮度')), findsOneWidget);

    await show(t, const AmbientLightSettings(
        engine: AmbientLightSettings.engineLegacy));
    expect(find.byKey(const ValueKey('ambient-slider-最低亮度')), findsOneWidget);
    expect(find.byKey(const ValueKey('ambient-slider-最高亮度')), findsOneWidget);
    expect(find.byKey(const ValueKey('ambient-slider-基础亮度')), findsNothing);
  });

  testWidgets('the colour mode chips work in both engines', (t) async {
    // 跟随低频 / 跟随频谱 / 固定色 —— 两条链路都读这个设置。
    for (final engine in [
      AmbientLightSettings.engineV2,
      AmbientLightSettings.engineLegacy,
    ]) {
      await show(t, AmbientLightSettings(engine: engine));
      for (var mode = 0; mode < 3; mode++) {
        expect(find.byKey(ValueKey('ambient-mode-$mode')), findsOneWidget,
            reason: 'the mode chip $mode is missing (engine $engine)');
      }
      await tap(t, find.byKey(const ValueKey('ambient-mode-1')));
      expect(changes.last.mode, 1);
    }
  });

  testWidgets('a preset applies the whole parameter set', (t) async {
    await show(t, const AmbientLightSettings());
    expect(find.byKey(const ValueKey('ambient-preset-0')), findsOneWidget);
    expect(find.byKey(const ValueKey('ambient-preset-3')), findsOneWidget);
    expect(find.byKey(const ValueKey('ambient-preset-4')), findsOneWidget);
    expect(find.byKey(const ValueKey('ambient-preset-5')), findsOneWidget);

    await tap(t, find.byKey(const ValueKey('ambient-preset-1')));
    final night = AmbientPresets.night;
    expect(changes.last.attackMs, night.attackMs);
    expect(changes.last.decayMs, night.decayMs);
    expect(changes.last.hueTauMs, night.hueTauMs);
    expect(changes.last.maxDeltaE, night.maxDeltaE);
    expect(changes.last.floor, night.floor);
    expect(changes.last.hueSpanDeg, night.hueSpanDeg);
    expect(changes.last.centroidWindowLowHundredths,
        night.centroidWindowLowHundredths);
    expect(changes.last.centroidWindowSpanHundredths,
        night.centroidWindowSpanHundredths);
    expect(changes.last.hueRotateDegPerSec, night.hueRotateDegPerSec);
    expect(changes.last.maxChromaHundredths, night.maxChromaHundredths);
    expect(changes.last.hueJumpDeg, night.hueJumpDeg);
    expect(changes.last.pulseGainHundredths, night.pulseGainHundredths);
    expect(changes.last.beatMinGapMs, night.beatMinGapMs);
    // A preset must not touch the engine, the mode, the brightness or the
    // zone choreography: those are the user's choices.
    expect(changes.last.engine, AmbientLightSettings.engineV2);
    expect(changes.last.vehicleBrightness, 100);
    expect(changes.last.zoneChoreo, isFalse);
    expect(changes.last.customMode, isFalse);
  });

  testWidgets('the parameters of a preset are inside the slider ranges',
      (t) async {
    await show(t, const AmbientLightSettings());
    for (var i = 0; i < AmbientPresets.all.length; i++) {
      await tap(t, find.byKey(ValueKey('ambient-preset-$i')));
      final preset = AmbientPresets.all[i];
      expect(changes.last.attackMs, inInclusiveRange(10, 300));
      expect(changes.last.decayMs, inInclusiveRange(60, 1200));
      expect(changes.last.hueTauMs, inInclusiveRange(60, 1200));
      expect(changes.last.hueMaxDeg, inInclusiveRange(10, 180));
      expect(changes.last.hueMaxAccel, inInclusiveRange(30, 800));
      expect(changes.last.maxDeltaE, inInclusiveRange(0.2, 6.0));
      expect(changes.last.floor, inInclusiveRange(0, 30));
      expect(changes.last.saturation, inInclusiveRange(0, 1));
      expect(changes.last.breath, inInclusiveRange(0, 0.4));
      expect(changes.last.hueSpanDeg, inInclusiveRange(150, 360));
      expect(changes.last.centroidWindowLowHundredths,
          inInclusiveRange(0, 70));
      expect(changes.last.centroidWindowSpanHundredths,
          inInclusiveRange(10, 100));
      expect(changes.last.hueRotateDegPerSec, inInclusiveRange(0, 30));
      expect(changes.last.maxChromaHundredths, inInclusiveRange(10, 40));
      expect(changes.last.hueJumpDeg, inInclusiveRange(0, 180));
      expect(changes.last.pulseGainHundredths, inInclusiveRange(0, 200));
      expect(changes.last.beatMinGapMs, inInclusiveRange(80, 600));
      expect(changes.last.attackMs, preset.attackMs);
      expect(changes.last.hueSpanDeg, preset.hueSpanDeg);
      expect(changes.last.maxChromaHundredths, preset.maxChromaHundredths);
    }
  });

  testWidgets('the zone choreography switch and the dwell slider',
      (t) async {
    await show(t, const AmbientLightSettings(customMode: true));
    expect(find.byKey(const ValueKey('ambient-zone-choreo')), findsOneWidget);
    // The dwell slider only shows when the choreography is on.
    expect(find.byKey(const ValueKey('ambient-slider-分区驻留')), findsNothing);

    await tap(t, find.byKey(const ValueKey('ambient-zone-choreo')));
    expect(changes.last.zoneChoreo, isTrue);

    await show(
        t, const AmbientLightSettings(customMode: true, zoneChoreo: true));
    expect(find.byKey(const ValueKey('ambient-slider-分区驻留')), findsOneWidget);
  });

  testWidgets('the fifteen parameter sliders are there', (t) async {
    await show(t, const AmbientLightSettings(customMode: true));
    const labels = [
      '亮度起 attack',
      '亮度落 decay',
      '色相平滑 τ',
      '色相限速',
      '色相限加速',
      '每帧色差上限',
      '基础亮度',
      '饱和度上限',
      '色相跨度',
      '色相自转',
      '彩度上限',
      '空闲呼吸',
    ];
    for (final label in labels) {
      expect(find.byKey(ValueKey('ambient-slider-$label')), findsOneWidget,
          reason: 'the slider of $label is missing');
    }
    // The three 「跳跃」 sliders carry explicit keys.
    for (final key in ['ambient-hue-jump', 'ambient-pulse-gain',
        'ambient-beat-gap']) {
      expect(find.byKey(ValueKey(key)), findsOneWidget,
          reason: 'the slider $key is missing');
    }
  });
}
