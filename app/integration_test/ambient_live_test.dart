import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:uni_launcher/model/ambient_light.dart';
import 'package:uni_launcher/model/appearance.dart';
import 'package:uni_launcher/platform/ambient_light.dart';
import 'package:uni_launcher/platform/audio_spectrum.dart';
import 'package:uni_launcher/theme/launcher_theme.dart';
import 'package:uni_launcher/widgets/ambient_light_settings.dart';

/// **The colour and the brightness really move with the music** — on a real
/// emulator, on the real chain, with the real widgets on screen.
///
/// The spectrum source is replaced by packets that carry the shape of a real
/// FFT frame: a kick in the low end, a moving melody in the middle and
/// cymbals up top, so the low centroid really travels. Everything after that
/// is the production path: the perception layer, the palette, the second
/// order motion layer, the Delta E00 limiter and the platform channel.
///
/// The point of this test is the **evidence**, not a green tick: it reads the
/// **pixels that were actually rendered** out of the layer tree, so the
/// numbers below are the pixels on the glass and not a copy of the engine's
/// own bookkeeping.
///
/// ## Why the pixels are read from the layer tree
///
/// `binding.takeScreenshot()` needs `convertFlutterSurfaceToImage()` on
/// Android, and that call **replaces the Flutter surface with an offscreen
/// image reader**: from that moment on the emulator screen stops being
/// refreshed, so every later screenshot of the device shows the very same
/// frozen picture. Reading the repaint boundary directly avoids the whole
/// surface conversion and still measures what was drawn.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  const spectrumMethods = MethodChannel('test/ambient-live-spectrum-control');
  const spectrumEvents = EventChannel('test/ambient-live-spectrum-events');
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

  /// One synthetic music frame.
  ///
  /// [phase] walks through the bar: the kick lands on every beat, the melody
  /// moves from the low mids to the top and back, and the cymbal hits on the
  /// off beats. The energy therefore travels across the bands, which is what
  /// the low centroid (and with it the hue) follows.
  List<double> musicFrame(double phase) {
    final bands = List<double>.filled(24, 0.06);
    final beat = phase % 1.0;
    // The kick: a short burst in the very low bands.
    final kick = math.exp(-beat * 14);
    for (var i = 0; i < 3; i++) {
      bands[i] = 0.35 + 0.62 * kick;
    }
    // The melody: a band that travels from the low mids to the top.
    final melodyBand = 3 + (phase * 6).round() % 8;
    bands[melodyBand] = 0.80;
    if (melodyBand + 1 < 24) bands[melodyBand + 1] = 0.55;
    // The cymbals: on the off beat.
    final off = (phase + 0.5) % 1.0;
    final cymbal = math.exp(-off * 20);
    for (var i = 16; i < 24; i++) {
      bands[i] = 0.10 + 0.55 * cymbal;
    }
    return bands;
  }

  testWidgets('the colour and the brightness follow the music', (t) async {
    final spectrum = AudioSpectrumService(
        methods: spectrumMethods, events: spectrumEvents);
    final service = AmbientLightService(spectrum: spectrum);
    addTearDown(() {
      service.dispose();
      spectrum.dispose();
    });

    const settings = AmbientLightSettings(
      enabled: true,
      mode: AmbientPalette.modeBass,
      engine: AmbientLightSettings.engineV2,
    );

    // The **real** settings panel on the screen: it shows the live colour
    // and the live brightness while the music plays.
    //
    // The repaint boundary is what makes the pixel measurement possible:
    // it is the painted result of the real widgets.
    final previewKey = GlobalKey();
    await t.pumpWidget(MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: launcherTheme(SurfaceStyle.from(const Appearance(), true)),
      home: Scaffold(
        body: SingleChildScrollView(
          child: RepaintBoundary(
            key: previewKey,
            child: AmbientLightSettingsPanel(
              settings: settings,
              service: service,
              onChanged: (_) {},
            ),
          ),
        ),
      ),
    ));

    await service.applySettings(settings);
    await t.pump(const Duration(milliseconds: 300));

    // The things that are measured on the screen:
    //
    // * the **colour swatch** — a flat block of the live colour;
    // * the **brightness bar** — its filled width is the live brightness.
    //
    // Both are located by their widget key, so the measurement follows the
    // layout instead of hard coded pixels.
    final swatchBox = t.renderObject<RenderBox>(
        find.byKey(const ValueKey('ambient-color-swatch')));
    final barBox = t.renderObject<RenderBox>(
        find.byKey(const ValueKey('ambient-brightness-bar')));

    /// Reads the **rendered pixels** of the swatch out of the layer tree.
    ///
    /// The bytes come straight from the rasterised picture, so this is what
    /// the glass shows: the swatch is one flat colour, and the centre pixel
    /// is that colour.
    Future<({int r, int g, int b})> readSwatch() async {
      final boundary = previewKey.currentContext!.findRenderObject()!
          as RenderRepaintBoundary;
      final origin = swatchBox.localToGlobal(Offset.zero);
      final image = await boundary.toImage(pixelRatio: 1.0);
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      image.dispose();
      final bytes = data!.buffer.asUint8List();
      final cx = (origin.dx + swatchBox.size.width / 2).round();
      final cy = (origin.dy + swatchBox.size.height / 2).round();
      final offset = (cy * image.width + cx) * 4;
      return (r: bytes[offset], g: bytes[offset + 1], b: bytes[offset + 2]);
    }

    /// Measures the filled width of the brightness bar in rendered pixels.
    ///
    /// The bar is a flat colour over a flat background, so the fill ends
    /// where the colour stops.
    ///
    /// ## Why the longest run and not the run from the left edge
    ///
    /// The bar has rounded corners, so the very first pixel of the row is
    /// the anti aliased edge and not the fill colour. Starting there would
    /// report a fill of one pixel. The longest run of the fill colour in the
    /// row is the fill itself, and the bar is the only thing on that row in
    /// the live colour.
    Future<int> measureBarFill() async {
      final boundary = previewKey.currentContext!.findRenderObject()!
          as RenderRepaintBoundary;
      final origin = barBox.localToGlobal(Offset.zero);
      final image = await boundary.toImage(pixelRatio: 1.0);
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      image.dispose();
      final bytes = data!.buffer.asUint8List();
      final width = image.width;
      final y = (origin.dy + barBox.size.height / 2).round();
      if (y < 0 || y >= image.height) return 0;
      // The fill colour is the live colour, so it is read from the swatch.
      final swatch = await readSwatch();
      final target = (swatch.r, swatch.g, swatch.b);
      var best = 0;
      var run = 0;
      for (var x = 0; x < width; x++) {
        final o = (y * width + x) * 4;
        final px = (bytes[o], bytes[o + 1], bytes[o + 2]);
        if ((px.$1 - target.$1).abs() <= 8 &&
            (px.$2 - target.$2).abs() <= 8 &&
            (px.$3 - target.$3).abs() <= 8) {
          run++;
          if (run > best) best = run;
        } else {
          run = 0;
        }
      }
      return best;
    }

    final series = <Map<String, dynamic>>[];
    // Thirty seconds of music: enough for the perception layer to settle
    // (its reference has a time constant of 2 s) and for the melody to walk
    // through the whole low end many times over.
    const frames = 300;
    for (var i = 0; i < frames; i++) {
      final phase = (i / 10) % 4.0;
      spectrum.accept({
        'granted': true,
        'available': true,
        'status': 'listening',
        'levels': musicFrame(phase),
        'peakLevel': .95,
      });
      await t.pump(const Duration(milliseconds: 100));
      final color = service.color.value;
      if (color == null) continue;
      series.add({
        'tMs': i * 100,
        'hex': color.hex,
        'brightness': color.brightness,
      });
    }

    // ---- the pixel measurement ----
    //
    // The series above is the engine's own bookkeeping. Now the **same**
    // widgets are measured again, this time in **rendered pixels**: the
    // swatch colour and the filled width of the brightness bar.
    final pixels = <Map<String, dynamic>>[];
    for (var i = 0; i < 40; i++) {
      final phase = (i / 10) % 4.0;
      spectrum.accept({
        'granted': true,
        'available': true,
        'status': 'listening',
        'levels': musicFrame(phase),
        'peakLevel': .95,
      });
      await t.pump(const Duration(milliseconds: 120));
      final color = service.color.value;
      if (color == null) continue;
      final swatch = await readSwatch();
      final filled = await measureBarFill();
      pixels.add({
        'tMs': 30000 + i * 120,
        'engineHex': color.hex,
        'engineBrightness': color.brightness,
        'pixelHex':
            '#${swatch.r.toRadixString(16).padLeft(2, '0')}'
                '${swatch.g.toRadixString(16).padLeft(2, '0')}'
                '${swatch.b.toRadixString(16).padLeft(2, '0')}',
        'pixelLuma': swatch.r + swatch.g + swatch.b,
        'barFilledPx': filled,
        'barWidthPx': barBox.size.width.round(),
      });
    }

    // ---- the evidence ----
    final hexes = series.map((e) => e['hex'] as String).toSet();
    final brightness =
        series.map((e) => e['brightness'] as int).toList();
    final minBrightness = brightness.reduce(math.min);
    final maxBrightness = brightness.reduce(math.max);

    // The **pixel** series: what the glass showed.
    final pixelHexes = pixels.map((e) => e['pixelHex'] as String).toSet();
    final luma =
        pixels.map((e) => e['pixelLuma'] as int).toList();
    final minLuma = luma.reduce(math.min);
    final maxLuma = luma.reduce(math.max);
    final fills =
        pixels.map((e) => e['barFilledPx'] as int).toList();
    final minFill = fills.reduce(math.min);
    final maxFill = fills.reduce(math.max);

    // ignore: avoid_print
    print('distinct colours: ${hexes.length}');
    // ignore: avoid_print
    print('brightness range: $minBrightness .. $maxBrightness');
    // ignore: avoid_print
    print('first 12: ${series.take(12).map((e) => '${e['hex']}/${e['brightness']}').join(' ')}');
    // ignore: avoid_print
    print('last 12: ${series.skip(series.length - 12).map((e) => '${e['hex']}/${e['brightness']}').join(' ')}');
    // ignore: avoid_print
    print('distinct pixel colours: ${pixelHexes.length} / ${pixels.length}');
    // ignore: avoid_print
    print('pixel luma range: $minLuma .. $maxLuma');
    // ignore: avoid_print
    print('bar fill range: $minFill .. $maxFill px');
    // ignore: avoid_print
    print('pixel samples: ${pixels.map((e) => '${e['pixelHex']}(${e['engineHex']})').join(' ')}');

    expect(series.length, greaterThan(100));
    // The colour has to change, not only the brightness.
    expect(hexes.length, greaterThan(10),
        reason: 'the colour only took ${hexes.length} values');
    // And the brightness has to move as well.
    expect(maxBrightness - minBrightness, greaterThan(5),
        reason: 'the brightness only moved ${maxBrightness - minBrightness}');

    // The **rendered pixels** have to move too, and they have to be the
    // colour the engine computed.
    expect(pixels.length, greaterThan(20));
    expect(pixelHexes.length, greaterThan(5),
        reason: 'the rendered colour only took ${pixelHexes.length} values');
    expect(maxLuma - minLuma, greaterThan(30),
        reason: 'the rendered pixels only moved ${maxLuma - minLuma}');
    expect(maxFill - minFill, greaterThan(20),
        reason: 'the rendered brightness bar only moved ${maxFill - minFill} px');
    for (final sample in pixels) {
      expect(sample['pixelHex'], sample['engineHex'],
          reason: 'the rendered pixel does not match the engine colour');
    }

    final report = binding.reportData ??= <String, dynamic>{};
    report['ambientLive'] = {
      'frames': series.length,
      'distinctColours': hexes.length,
      'brightnessRange': '$minBrightness..$maxBrightness',
      'pixelColours': pixelHexes.length,
      'pixelLumaRange': '$minLuma..$maxLuma',
      'barFillRange': '$minFill..$maxFill',
      'series': series,
      'pixels': pixels,
    };
  });
}
