import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../model/ambient_light.dart';
import 'audio_spectrum.dart';

/// Drives the head unit ambient strip from the music that is playing.
///
/// The spectrum to colour mapping lives in [AmbientPalette] so it can be
/// unit tested without a device. This class owns the platform channel and the
/// spectrum subscription.
///
/// Nothing reaches the head unit until the user turns the music ambience on.
/// The strip is only lit while the spectrum is actually available, so a car
/// without the vendor framework simply reports that it is unavailable instead
/// of failing silently.
///
/// The live colour is exposed through [color] as a separate notifier: a
/// spectrum frame arrives ten times a second, and the settings page must not
/// rebuild ten times a second because of it.
class AmbientLightService extends ChangeNotifier {
  /// One shared instance per process, so the strip is driven by one writer.
  static final AmbientLightService shared = AmbientLightService();

  /// The channel that reaches the vendor SDK writer.
  static const MethodChannel defaultChannel =
      MethodChannel('xyz.i4o.uni.launcher/ambient-light');

  final MethodChannel methods;
  final AudioSpectrumService spectrum;

  AmbientLightService({
    MethodChannel? methods,
    AudioSpectrumService? spectrum,
  })  : methods = methods ?? defaultChannel,
        spectrum = spectrum ?? AudioSpectrumService.shared {
    this.spectrum.addListener(onSpectrumFrame);
  }

  AmbientLightSettings _settings = const AmbientLightSettings();
  bool _channelAvailable = false;
  String _reason = '';
  bool _spectrumReady = false;
  bool _spectrumGranted = false;

  /// The colour of the most recent frame. Listeners get the live value.
  final ValueNotifier<AmbientColor?> color = ValueNotifier<AmbientColor?>(null);

  double _fallbackHue = 0;

  /// The current settings.
  AmbientLightSettings get settings => _settings;

  /// Whether the head unit side of the channel is usable.
  bool get channelAvailable => _channelAvailable;

  /// Why the channel cannot be used, or an empty string.
  String get reason => _reason;

  /// Whether the music ambience is switched on.
  bool get enabled => _settings.enabled;

  /// Whether a spectrum frame can currently be read.
  bool get spectrumReady => _spectrumReady;

  /// Whether the spectrum needs the microphone permission first.
  bool get needsPermission => !_spectrumGranted;

  /// Reads the capability state of the head unit channel.
  Future<void> refreshStatus() async {
    try {
      final raw = await methods.invokeMapMethod<String, dynamic>('status');
      if (raw == null) {
        _channelAvailable = false;
        _reason = '此设备没有原车氛围灯接口';
      } else {
        _channelAvailable = raw['available'] == true;
        _reason = raw['reason'] is String ? raw['reason'] as String : '';
        if (!_channelAvailable && _reason.isEmpty) {
          _reason = '此设备没有原车氛围灯接口';
        }
      }
    } catch (_) {
      _channelAvailable = false;
      _reason = '氛围灯通道暂不可用';
    }
    _spectrumReady = spectrum.available && spectrum.levels.isNotEmpty;
    _spectrumGranted = spectrum.granted;
    notifyListeners();
  }

  /// Applies new settings and syncs them to the head unit.
  ///
  /// The call is idempotent: settings that did not change are not written
  /// again, because several engines share this service.
  Future<void> applySettings(AmbientLightSettings next) async {
    if (next == _settings) return;
    final wasEnabled = _settings.enabled;
    _settings = next;
    if (next.enabled != wasEnabled) {
      await _syncEnabled();
    } else if (next.enabled) {
      // The mapping changed, so the next frame already carries the new colour.
      await _syncBrightness();
    }
    notifyListeners();
  }

  /// Switches the music ambience on or off.
  Future<void> setEnabled(bool value) =>
      applySettings(_settings.copyWith(enabled: value));

  /// Turns the strip on and starts the spectrum capture it needs.
  Future<void> _syncEnabled() async {
    if (_settings.enabled) {
      spectrum.setDemand(this, true);
      await _send('enable', true);
    } else {
      spectrum.setDemand(this, false);
      await _send('enable', false);
      color.value = null;
    }
  }

  /// Pushes the current brightness once, used after a settings change.
  Future<void> _syncBrightness() async {
    final current = color.value;
    if (current != null) await _sendBrightness(current.brightness);
  }

  /// Maps one spectrum frame to a colour and hands it to the head unit.
  void onSpectrumFrame() {
    // A spectrum frame arrives ten times a second. Only a change of the
    // spectrum state is worth a notification, otherwise every listener would
    // rebuild ten times a second.
    final ready = spectrum.available && spectrum.levels.isNotEmpty;
    if (ready != _spectrumReady || spectrum.granted != _spectrumGranted) {
      _spectrumReady = ready;
      _spectrumGranted = spectrum.granted;
      notifyListeners();
    }
    if (!_settings.enabled) return;
    final bands = spectrum.levels;
    if (bands.isEmpty) return;
    final computed = AmbientPalette.colorFrom(
      bands: bands,
      level: spectrum.peakLevel,
      mode: _settings.mode,
      fixedHue: _settings.fixedHue,
      sensitivity: _settings.sensitivity,
      minBrightness: _settings.minBrightness,
      maxBrightness: _settings.maxBrightness,
      fallbackHue: _fallbackHue,
    );
    _fallbackHue = AmbientPalette.spectrumHue(bands, _fallbackHue);
    color.value = computed;
    // The native writer drops frames that arrive too often or did not change
    // the colour much, so the stream stays ten frames a second here.
    unawaited(_send('color', {
      'r': computed.r,
      'g': computed.g,
      'b': computed.b,
    }));
    unawaited(_sendBrightness(computed.brightness));
  }

  Future<void> _sendBrightness(int brightness) =>
      _send('brightness', brightness);

  Future<void> _send(String method, Object? arguments) async {
    try {
      await methods.invokeMethod<void>(method, arguments);
    } catch (_) {
      // The head unit side is optional; a failed write must not take the
      // launcher down.
    }
  }

  @override
  void dispose() {
    spectrum.removeListener(onSpectrumFrame);
    color.dispose();
    super.dispose();
  }
}
