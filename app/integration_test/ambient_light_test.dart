import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:uni_launcher/model/ambient_light.dart';
import 'package:uni_launcher/platform/ambient_light.dart';
import 'package:uni_launcher/platform/audio_spectrum.dart';

/// End to end check of the music driven ambient light.
///
/// The spectrum source is replaced by packets that carry the same shape as
/// the native FFT frames, because a head unit emulator has no usable audio
/// output. Everything else is the real path: the spectrum service, the
/// palette, the platform channel and the native writer that talks to the
/// vendor SDK.
///
/// The assertion is made on the native side: its write counters have to grow,
/// which proves that a spectrum packet really turned into a colour write on
/// the vehicle channel.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  const spectrumMethods = MethodChannel('test/ambient-spectrum-control');
  const spectrumEvents = EventChannel('test/ambient-spectrum-events');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  setUp(() {
    messenger.setMockMethodCallHandler(spectrumMethods, (call) async {
      if (call.method == 'status') {
        return {
          'granted': true,
          'available': true,
          'status': 'listening',
          'levels': List.filled(24, 0)
        };
      }
      return null;
    });
    messenger.setMockMethodCallHandler(MethodChannel(spectrumEvents.name),
        (call) async => null);
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(spectrumMethods, null);
    messenger.setMockMethodCallHandler(MethodChannel(spectrumEvents.name), null);
  });

  testWidgets(
      'a spectrum frame becomes a colour write on the vehicle channel',
      (t) async {
    final spectrum = AudioSpectrumService(
        methods: spectrumMethods, events: spectrumEvents);
    // The real ambient channel, so the native writer really runs.
    final service = AmbientLightService(spectrum: spectrum);
    addTearDown(() {
      service.dispose();
      spectrum.dispose();
    });

    final before = await _nativeStatus();
    final colorWritesBefore = (before['colorWrites'] as num?)?.toInt() ?? 0;

    await service.applySettings(const AmbientLightSettings(
        enabled: true, mode: AmbientPalette.modeSpectrum));
    await Future<void>.delayed(const Duration(milliseconds: 200));

    // A frame with energy in the middle of the spectrum.
    final bands = List<double>.filled(24, 0.02);
    for (var i = 8; i < 14; i++) {
      bands[i] = 0.85;
    }
    spectrum.accept({
      'granted': true,
      'available': true,
      'status': 'listening',
      'levels': bands,
      'peakLevel': 0.85,
    });
    await Future<void>.delayed(const Duration(milliseconds: 400));

    // The palette must have produced a colour for that frame.
    expect(service.color.value, isNotNull);
    final expected = AmbientPalette.scaleByBrightness(
        AmbientPalette.colorFrom(
      bands: bands,
      level: 0.85,
      mode: AmbientPalette.modeSpectrum,
      fixedHue: 210,
      sensitivity: 1.4,
      minBrightness: 15,
      maxBrightness: 100,
    ));
    expect(service.color.value!.r, expected.r);
    expect(service.color.value!.g, expected.g);
    expect(service.color.value!.b, expected.b);
    expect(service.color.value!.brightness, expected.brightness);
    // The energy sits in the middle of the spectrum, so the colour is not
    // the fallback hue of a silent frame.
    expect(service.color.value!.hex, isNot('#FF2626'));

    // The native writer must have received the colour write.
    final after = await _nativeStatus();
    final colorWritesAfter = (after['colorWrites'] as num?)?.toInt() ?? 0;
    expect(colorWritesAfter, greaterThan(colorWritesBefore),
        reason: 'the colour write reached the native writer');
    expect((after['brightnessWrites'] as num?)?.toInt() ?? 0,
        greaterThan((before['brightnessWrites'] as num?)?.toInt() ?? 0));

    // Hand the counters back to the host, so the report carries the evidence
    // instead of only a green tick.
    final report = binding.reportData ??= <String, dynamic>{};
    report['ambientLight'] = {
      'before': before,
      'after': after,
      'colorWrites': colorWritesAfter,
    };
  });

  testWidgets('the native state tells the three failure modes apart',
      (t) async {
    final spectrum = AudioSpectrumService(
        methods: spectrumMethods, events: spectrumEvents);
    final service = AmbientLightService(spectrum: spectrum);
    addTearDown(() {
      service.dispose();
      spectrum.dispose();
    });

    final state = await _nativeStatus();
    // A head unit without the vendor framework has no handle. A head unit
    // with a handle but unknown ids reports the missing names. Both must be
    // visible, otherwise the settings page cannot tell the user what is
    // wrong.
    expect(state.containsKey('handlePresent'), isTrue);
    expect(state.containsKey('switchApplied'), isTrue);
    expect(state.containsKey('resolvedIds'), isTrue);
    expect(state.containsKey('unresolved'), isTrue);
    final lastWrite = state['lastWrite'];
    expect(lastWrite, isA<Map>());
    expect((lastWrite as Map)['ok'], isA<bool>());
  });

  testWidgets('a silent frame keeps the previous hue and the minimum brightness',
      (t) async {
    final spectrum = AudioSpectrumService(
        methods: spectrumMethods, events: spectrumEvents);
    final service = AmbientLightService(spectrum: spectrum);
    addTearDown(() {
      service.dispose();
      spectrum.dispose();
    });
    await service.applySettings(const AmbientLightSettings(
        enabled: true, mode: AmbientPalette.modeSpectrum));
    await Future<void>.delayed(const Duration(milliseconds: 200));

    final loud = List<double>.filled(24, 0.02);
    for (var i = 4; i < 8; i++) {
      loud[i] = 0.9;
    }
    spectrum.accept({
      'granted': true,
      'available': true,
      'status': 'listening',
      'levels': loud,
      'peakLevel': 0.9,
    });
    await Future<void>.delayed(const Duration(milliseconds: 300));
    final loudColor = service.color.value;
    expect(loudColor, isNotNull);

    spectrum.accept({
      'granted': true,
      'available': true,
      'status': 'listening',
      'levels': List.filled(24, 0),
      'peakLevel': 0,
    });
    await Future<void>.delayed(const Duration(milliseconds: 300));
    final silent = service.color.value;
    expect(silent, isNotNull);
    expect(silent?.brightness, 15,
        reason: 'silence falls back to the lowest brightness');
    // The hue is kept, so the colour is the loud one dimmed to the minimum
    // brightness. The colour is scaled by that brightness, so the channels
    // differ while the hue stays the same.
    final loudHue = AmbientPalette.spectrumHue(loud, 0);
    final expected = AmbientPalette.scaleByBrightness(
        AmbientPalette.colorFrom(
      bands: List.filled(24, 0),
      level: 0,
      mode: AmbientPalette.modeSpectrum,
      fixedHue: 210,
      sensitivity: 1.4,
      minBrightness: 15,
      maxBrightness: 100,
      fallbackHue: loudHue,
    ));
    expect(silent?.r, expected.r);
    expect(silent?.g, expected.g);
    expect(silent?.b, expected.b);
    // The bright frame is the same hue, only brighter.
    final loudScaled = AmbientPalette.scaleByBrightness(
        AmbientPalette.colorFrom(
      bands: loud,
      level: 0.9,
      mode: AmbientPalette.modeSpectrum,
      fixedHue: 210,
      sensitivity: 1.4,
      minBrightness: 15,
      maxBrightness: 100,
    ));
    expect(loudColor?.r, loudScaled.r);
    expect(loudColor?.g, loudScaled.g);
    expect(loudColor?.b, loudScaled.b);
    expect(expected.r > 0, isTrue, reason: 'the hue is still there');
  });

  testWidgets('switching the ambience off stops the capture', (t) async {
    final spectrum = AudioSpectrumService(
        methods: spectrumMethods, events: spectrumEvents);
    final service = AmbientLightService(spectrum: spectrum);
    addTearDown(() {
      service.dispose();
      spectrum.dispose();
    });
    await service.applySettings(const AmbientLightSettings(enabled: true));
    expect(spectrum.activeConsumers, 1);
    await service.applySettings(const AmbientLightSettings(enabled: false));
    expect(spectrum.activeConsumers, 0);
    expect(service.color.value, isNull);
  });
}

/// Reads the native writer state through the real channel.
Future<Map<String, dynamic>> _nativeStatus() async {
  const channel = MethodChannel('xyz.i4o.uni.launcher/ambient-light');
  final raw = await channel.invokeMapMethod<String, dynamic>('status');
  return raw ?? const {};
}
