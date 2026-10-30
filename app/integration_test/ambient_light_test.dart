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
    final color = service.color.value;
    expect(color, isNotNull);
    // The motion layer lands on the target hue of the first frame and only
    // moves towards it afterwards, so the colour follows the spectrum.
    final targetHue = AmbientPalette.targetHue(
      bands: bands,
      mode: AmbientPalette.modeSpectrum,
      fixedHue: 210,
    );
    expect(_hueOf(color!), closeTo(targetHue, 5),
        reason: 'the colour follows the spectrum hue');
    // The brightness is smoothed towards the target of the frame, so it sits
    // above the floor and never above the target.
    final targetLevel = AmbientPalette.targetLevel(
      bands: bands,
      level: 0.85,
      mode: AmbientPalette.modeSpectrum,
      sensitivity: 1.4,
      minBrightness: 15,
      maxBrightness: 100,
    );
    expect(color.brightness, greaterThan(15));
    expect(color.brightness, lessThanOrEqualTo(targetLevel));
    // The energy sits in the middle of the spectrum, so the colour is not
    // the fallback hue of a silent frame.
    expect(color.hex, isNot('#FF2626'));

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
    expect(loudColor!.brightness, greaterThan(15));

    // Silence keeps the hue and fades the brightness down to the floor.
    // The native stream keeps delivering silent frames, so the light fades
    // out instead of freezing at the last colour.
    for (var i = 0; i < 30; i++) {
      spectrum.accept({
        'granted': true,
        'available': true,
        'status': 'listening',
        'levels': List.filled(24, 0),
        'peakLevel': 0,
      });
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    final silent = service.color.value;
    expect(silent, isNotNull);
    // The hue is kept, so the colour stays the loud one, only dimmer.
    expect(_hueOf(silent!), closeTo(_hueOf(loudColor), 5),
        reason: 'the hue is kept while the light fades');
    expect(silent.brightness, closeTo(15, 1),
        reason: 'silence falls back to the lowest brightness');
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

/// The hue of a colour in degrees.
///
/// The brightness scales the three channels, so the hue has to be recovered
/// from the ratios rather than from the raw values.
double _hueOf(AmbientColor color) {
  final r = color.r / 255, g = color.g / 255, b = color.b / 255;
  final max = r > g ? (r > b ? r : b) : (g > b ? g : b);
  final min = r < g ? (r < b ? r : b) : (g < b ? g : b);
  final delta = max - min;
  if (delta <= 0) return 0;
  final hue = max == r
      ? 60 * (((g - b) / delta) % 6)
      : max == g
          ? 60 * (((b - r) / delta) + 2)
          : 60 * (((r - g) / delta) + 4);
  return (hue + 360) % 360;
}
