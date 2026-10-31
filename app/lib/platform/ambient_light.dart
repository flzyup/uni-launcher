import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../model/ambient_light.dart';
import '../model/ambient_motion.dart';
import '../model/ambient_rhythm.dart';
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
/// spectrum frame arrives twenty times a second, and the settings page must
/// not rebuild twenty times a second because of it.
class AmbientLightService extends ChangeNotifier {
  /// One shared instance per process, so the strip is driven by one writer.
  static final AmbientLightService shared = AmbientLightService();

  /// The channel that reaches the vendor SDK writer.
  static const MethodChannel defaultChannel =
      MethodChannel('xyz.i4o.uni.launcher/ambient-light');

  /// How often the capability is re-read while the ambience is switched on.
  ///
  /// The native side pushes a change as soon as something happens, so this is
  /// only a safety net for a push that never arrives.
  static const Duration statusPoll = Duration(seconds: 5);

  /// The nominal frame interval of the spectrum (milliseconds).
  ///
  /// Only used for the first frame, which has no previous frame to subtract.
  /// After that the real elapsed time is used, so the smoothing does not
  /// depend on the frame rate.
  static const int defaultFrameMs = 50;

  /// The interval between the frame log lines (milliseconds).
  ///
  /// One line per frame, so two neighbouring lines are two neighbouring
  /// frames and the per frame jump can be measured for real.
  static const int frameLogIntervalMs = 100;

  final MethodChannel methods;
  final AudioSpectrumService spectrum;

  AmbientLightService({
    MethodChannel? methods,
    AudioSpectrumService? spectrum,
    int Function()? clock,
  })  : methods = methods ?? defaultChannel,
        spectrum = spectrum ?? AudioSpectrumService.shared,
        _clock = clock ?? _monotonicMillis {
    this.spectrum.addListener(onSpectrumFrame);
    this.methods.setMethodCallHandler(handleNativeCall);
  }

  /// The monotonic clock in milliseconds.
  ///
  /// A [Stopwatch] rather than the wall clock: the system time can jump when
  /// it is corrected, and a negative elapsed time would break the smoothing.
  static final Stopwatch _stopwatch = Stopwatch()..start();

  static int _monotonicMillis() => _stopwatch.elapsedMilliseconds;

  AmbientLightSettings _settings = const AmbientLightSettings();
  bool _channelAvailable = false;
  String _reason = '';
  bool _spectrumReady = false;
  bool _spectrumGranted = false;
  bool _switchApplied = false;
  bool _lastWriteOk = true;
  List<String> _unresolved = const [];
  int? _writtenBrightness;
  Timer? _poll;
  Timer? _fallbackTimer;
  final AmbientRhythm _rhythm = AmbientRhythm();
  int _lastSignalAt = 0;
  int _lastAmbientWriteAt = 0;
  int _valleyWriteAt = 0;
  int _lastPeakWriteAt = 0;
  int? _predictedBeatAt;
  int? _lastPeakBand;

  /// The native status of the spectrum capture: idle, starting, listening,
  /// permission-required or unavailable.
  String _spectrumStatus = '';

  /// The native reason of a failed capture, in the words of the native side.
  String _spectrumDetail = '';

  /// Where the spectrum is taken from: output-mix, session or none.
  String _spectrumSource = '';

  /// The frames the native capture has delivered, and how many of them
  /// carried a signal.
  int _spectrumFrames = 0;
  int _spectrumSignalFrames = 0;

  /// The capture size the native side settled on, and the sample rate.
  int _spectrumCaptureSize = 0;
  int _spectrumSampleRate = 0;

  /// Whether the hidden API restriction was lifted for this process.
  String _spectrumHiddenApi = '';

  /// The motion layer, which turns the spectrum targets into a flow.
  final AmbientMotion _motion = const AmbientMotion();

  /// The state of the motion layer, kept across frames.
  AmbientMotionState _motionState = const AmbientMotionState();

  /// The monotonic clock, in milliseconds.
  final int Function() _clock;

  /// The moment of the previous frame, for the elapsed time.
  int _lastFrameAt = 0;

  /// The moment of the previous frame log, for the log throttle.
  int _lastFrameLogAt = 0;

  /// The colour of the most recent frame. Listeners get the live value.
  final ValueNotifier<AmbientColor?> color = ValueNotifier<AmbientColor?>(null);

  /// The current settings.
  AmbientLightSettings get settings => _settings;

  /// Whether the head unit side of the channel is usable.
  bool get channelAvailable => _channelAvailable;

  /// Why the channel cannot be used, or an empty string.
  String get reason => _reason;

  /// Whether the music ambience is switched on.
  bool get enabled => _settings.enabled;

  /// Whether the spectrum needs the microphone permission first.
  bool get needsPermission => !_spectrumGranted;

  /// Whether a spectrum frame can currently be read.
  bool get spectrumReady => _spectrumReady;

  /// The native status of the spectrum capture.
  String get spectrumStatus => _spectrumStatus;

  /// Why the capture is not running, in the words of the native side.
  String get spectrumDetail => _spectrumDetail;

  /// Where the spectrum is taken from: output-mix, session or none.
  String get spectrumSource => _spectrumSource;

  /// The frames the native capture delivered, and how many carried a signal.
  int get spectrumFrames => _spectrumFrames;

  int get spectrumSignalFrames => _spectrumSignalFrames;

  /// The loudest band of the newest frame (0..1).
  double get spectrumPeak => spectrum.peakLevel;

  /// The capture size the native side settled on, and the sample rate.
  int get spectrumCaptureSize => _spectrumCaptureSize;

  int get spectrumSampleRate => _spectrumSampleRate;

  /// Whether the hidden API restriction was lifted for this process.
  String get spectrumHiddenApi => _spectrumHiddenApi;

  /// Whether the head unit accepted the most recent write.
  bool get writeOk => _lastWriteOk;

  /// Whether the head unit accepted the switch-on sequence.
  ///
  /// The strip needs a sequence of writes to light up: the main colour
  /// source, the experience mode, the three zones and the interactive effect.
  /// Until that sequence succeeded the colours have nothing to show on.
  bool get switchApplied => _switchApplied;

  /// Vendor constants that do not resolve on this head unit.
  List<String> get unresolved => _unresolved;

  /// Reads the capability state of the head unit channel.
  Future<void> refreshStatus() async {
    try {
      final raw = await methods.invokeMapMethod<String, dynamic>('status');
      if (raw == null) {
        _channelAvailable = false;
        _reason = '此设备没有原车氛围灯接口';
      } else {
        applyNativeState(raw);
      }
    } catch (_) {
      _channelAvailable = false;
      _reason = '氛围灯通道暂不可用';
    }
    // The spectrum state lives in its own channel, so it is read there too.
    // Without this the page would keep the values of the last packet and
    // could not tell "capturing but silent" from "not capturing at all".
    try {
      await spectrum.refreshStatus();
    } catch (_) {}
    _applySpectrumState();
    notifyListeners();
  }

  /// Takes over the state the spectrum service knows about.
  void _applySpectrumState() {
    _spectrumReady = spectrum.available && spectrum.levels.isNotEmpty;
    _spectrumGranted = spectrum.granted;
    _spectrumStatus = spectrum.status;
    _spectrumDetail = spectrum.detail;
    _spectrumSource = spectrum.source;
    _spectrumFrames = spectrum.frames;
    _spectrumSignalFrames = spectrum.signalFrames;
    _spectrumCaptureSize = spectrum.captureSize;
    _spectrumSampleRate = spectrum.sampleRateHz;
    _spectrumHiddenApi = spectrum.hiddenApi;
  }

  /// Takes over the capability state reported by the native side.
  void applyNativeState(Map<String, dynamic> raw) {
    final available = raw['available'] == true;
    final nativeReason = raw['reason'] is String ? raw['reason'] as String : '';
    _channelAvailable = available;
    _reason = nativeReason;
    if (!available && _reason.isEmpty) {
      _reason = '此设备没有原车氛围灯接口';
    }
    _switchApplied = raw['switchApplied'] == true;
    final lastWrite = raw['lastWrite'];
    if (lastWrite is Map) {
      _lastWriteOk = lastWrite['ok'] != false;
    }
    final missing = raw['unresolved'];
    _unresolved = missing is List
        ? missing.map((value) => '$value').toList(growable: false)
        : const [];
  }

  /// Handles the native push that reports a capability change.
  Future<Object?> handleNativeCall(MethodCall call) async {
    if (call.method != 'state') return null;
    final raw = call.arguments;
    if (raw is Map) applyNativeState(Map<String, dynamic>.from(raw));
    notifyListeners();
    return null;
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
      _rhythm.reset();
      _lastSignalAt = 0;
      _lastAmbientWriteAt = 0;
      _valleyWriteAt = 0;
      _lastPeakWriteAt = 0;
      _predictedBeatAt = null;
      _lastPeakBand = null;
      spectrum.setDemand(this, true);
      await _send('enable', true);
      // The brightness is the user's absolute value, so it is written once
      // here instead of on every spectrum frame.
      await _syncBrightness();
      await _writeFallback();
      _fallbackTimer?.cancel();
      _fallbackTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (_settings.enabled &&
            (_lastSignalAt == 0 || _clock() - _lastSignalAt > 1500)) {
          unawaited(_writeFallback());
        }
      });
      _startPolling();
    } else {
      _fallbackTimer?.cancel();
      _fallbackTimer = null;
      spectrum.setDemand(this, false);
      await _send('enable', false);
      _stopPolling();
      color.value = null;
    }
  }

  /// Keeps the capability line honest while the ambience is on.
  void _startPolling() {
    _poll?.cancel();
    _poll = Timer.periodic(statusPoll, (_) => refreshStatus());
  }

  void _stopPolling() {
    _poll?.cancel();
    _poll = null;
  }

  /// Pushes the current brightness once, used after a settings change.
  Future<void> _syncBrightness() async {
    final value = _settings.vehicleBrightness;
    if (value == _writtenBrightness) return;
    if (await _send('brightness', value)) _writtenBrightness = value;
  }

  /// A visible static colour while capture is starting, silent or unavailable.
  Future<void> _writeFallback() async {
    if (!_settings.enabled) return;
    final ceiling = _settings.maxBrightness.clamp(0, 100);
    final level = (_settings.minBrightness < 30 ? 30 : _settings.minBrightness)
        .clamp(0, ceiling);
    final fallback = AmbientPalette.colorOf(_settings.fixedHue, level);
    color.value = fallback;
    await _send('color', {'r': fallback.r, 'g': fallback.g, 'b': fallback.b});
    if (_writtenBrightness != _settings.vehicleBrightness) {
      if (await _send('brightness', _settings.vehicleBrightness)) {
        _writtenBrightness = _settings.vehicleBrightness;
      }
    }
  }

  Future<void> _writePeak(AmbientColor color) async {
    _lastAmbientWriteAt = _clock();
    _valleyWriteAt = 0;
    this.color.value = color;
    await _send('color', {'r': color.r, 'g': color.g, 'b': color.b});
    // The vendor strip low-passes rapid colour targets. Its own high/low
    // brightness ladder is much more visible, and is only toggled on beats.
    await _send('brightness', _settings.vehicleBrightness);
  }

  Future<void> _writeValley(AmbientColor color) async {
    _lastAmbientWriteAt = _clock();
    _valleyWriteAt = 0;
    this.color.value = color;
    await _send('color', {'r': color.r, 'g': color.g, 'b': color.b});
    if (_settings.vehicleBrightness > 50) {
      await _send('brightness', (_settings.vehicleBrightness * .38).round());
    }
  }

  double _bandSaturation(int band) {
    final custom = switch (band) {
      AmbientRhythm.bassBand => _settings.bassCustom,
      AmbientRhythm.midBand => _settings.midCustom,
      _ => _settings.trebleCustom,
    };
    if (custom.isEmpty) return AmbientPalette.saturation;
    return HSVColor.fromColor(
            Color(0xFF000000 | int.parse(custom.substring(1), radix: 16)))
        .saturation;
  }

  /// Maps one spectrum frame to a colour and hands it to the head unit.
  void onSpectrumFrame() {
    // A spectrum frame arrives twenty times a second. Only a change of the
    // spectrum state is worth a notification, otherwise every listener would
    // rebuild ten times a second. The frame counters are left out on purpose:
    // they change on every frame.
    final before = '$_spectrumReady|$_spectrumGranted|$_spectrumStatus|'
        '$_spectrumDetail|$_spectrumSource';
    _applySpectrumState();
    final after = '$_spectrumReady|$_spectrumGranted|$_spectrumStatus|'
        '$_spectrumDetail|$_spectrumSource';
    if (before != after) notifyListeners();
    if (!_settings.enabled) return;
    final bands = spectrum.levels;
    if (!_spectrumReady || bands.isEmpty || spectrum.peakLevel < .025) return;
    final now = _clock();
    _lastSignalAt = now;
    final rhythm = _rhythm.step(bands, now);

    // —— Step one: the targets. Same as before, the raw spectrum picks a
    // hue and a level. ——
    var targetHue = AmbientPalette.targetHue(
      bands: bands,
      mode: _settings.mode,
      fixedHue: _settings.fixedHue,
      // Silence keeps the *current* hue, so the strip does not jump back
      // to zero degrees.
      fallbackHue: _motionState.hue,
    );
    if (_settings.mode == AmbientPalette.modeSpectrum) {
      // Keep the three frequency regions visibly apart: bass reads warm,
      // voice/guitar reads green, and cymbals read blue-violet. The previous
      // violet/cyan/pale-blue mapping sat inside one narrow blue family.
      final sum = rhythm.bass + rhythm.mid + rhythm.treble;
      if (sum > .02) {
        final x = math.cos(_settings.bassHue * math.pi / 180) * rhythm.bass +
            math.cos(_settings.midHue * math.pi / 180) * rhythm.mid +
            math.cos(_settings.trebleHue * math.pi / 180) * rhythm.treble;
        final y = math.sin(_settings.bassHue * math.pi / 180) * rhythm.bass +
            math.sin(_settings.midHue * math.pi / 180) * rhythm.mid +
            math.sin(_settings.trebleHue * math.pi / 180) * rhythm.treble;
        targetHue =
            AmbientPalette.normalizeHue(math.atan2(y, x) * 180 / math.pi);
      }
    }
    final rawLevel = AmbientPalette.targetLevel(
      bands: bands,
      level: spectrum.peakLevel,
      mode: _settings.mode,
      sensitivity: _settings.sensitivity,
      minBrightness: _settings.minBrightness,
      maxBrightness: _settings.maxBrightness,
    );
    final floor = _settings.minBrightness.clamp(0, _settings.maxBrightness);
    // Keep the between-beat level in a visible valley. Without this reserve,
    // compressed pop music keeps the strip near maximum and a kick cannot
    // read as an impact.
    final baselineScale = rhythm.bpm == null
        ? .68
        : rhythm.intervalMs >= 600
            ? .44
            : rhythm.intervalMs >= 430
                ? .52
                : .60;
    final targetLevel = floor + ((rawLevel - floor) * baselineScale).round();

    // —— Step two: the motion layer turns the targets into a smooth flow. ——
    final dt = _lastFrameAt > 0 ? now - _lastFrameAt : defaultFrameMs;
    _lastFrameAt = now;
    final bass = AmbientPalette.bassEnergy(bands);
    _motionState = _motion.step(
      prev: _motionState,
      targetHue: targetHue,
      targetLevel: targetLevel,
      bass: bass,
      dtMs: dt,
      onset: rhythm.onset,
      impact: rhythm.impact,
      pulseDecayMs: (rhythm.intervalMs * .58).clamp(180.0, 620.0),
      pulseGain: rhythm.intervalMs >= 600
          ? 1.7
          : rhythm.intervalMs >= 430
              ? 1.4
              : 1.0,
    );

    final actualBeat = rhythm.impact > 0;
    final predictedBeat = rhythm.nextBeatMs != null &&
        rhythm.bpm != null &&
        now >= rhythm.nextBeatMs! - _settings.beatLeadMs &&
        _predictedBeatAt != rhythm.nextBeatMs;
    if (predictedBeat) _predictedBeatAt = rhythm.nextBeatMs;
    final peakDue = actualBeat || predictedBeat;
    final eventBand = actualBeat ? rhythm.band : rhythm.predictedBand;
    final duplicatePredictedPeak = actualBeat &&
        now - _lastPeakWriteAt < 160 &&
        _lastPeakBand == eventBand;
    final peakLevel = (72 + rhythm.impact * 28).round().clamp(72, 100).toInt();
    final valleyLevel = (_settings.minBrightness +
            (_settings.maxBrightness - _settings.minBrightness) * .16)
        .round()
        .clamp(0, 100)
        .toInt();
    final spectrumMode = _settings.mode == AmbientPalette.modeSpectrum;
    final otherBands = <(double, double, double)>[
      if (eventBand != AmbientRhythm.bassBand)
        (
          _settings.bassHue,
          rhythm.bass,
          _bandSaturation(AmbientRhythm.bassBand)
        ),
      if (eventBand != AmbientRhythm.midBand)
        (_settings.midHue, rhythm.mid, _bandSaturation(AmbientRhythm.midBand)),
      if (eventBand != AmbientRhythm.trebleBand)
        (
          _settings.trebleHue,
          rhythm.treble,
          _bandSaturation(AmbientRhythm.trebleBand)
        ),
    ];
    final otherWeight = otherBands.fold<double>(
        0, (sum, entry) => sum + entry.$2.clamp(0.0, 1.0));
    final otherX = otherBands.fold<double>(
        0,
        (sum, entry) =>
            sum +
            math.cos(entry.$1 * math.pi / 180) * entry.$2.clamp(0.0, 1.0));
    final otherY = otherBands.fold<double>(
        0,
        (sum, entry) =>
            sum +
            math.sin(entry.$1 * math.pi / 180) * entry.$2.clamp(0.0, 1.0));
    final valleyHue = spectrumMode && otherWeight > .01
        ? AmbientPalette.normalizeHue(
            math.atan2(otherY, otherX) * 180 / math.pi)
        : _motionState.hue;
    final valleySaturation = otherWeight <= 0
        ? AmbientPalette.saturation
        : otherBands.fold<double>(
                0, (sum, entry) => sum + entry.$3 * entry.$2.clamp(0.0, 1.0)) /
            otherWeight;
    final peakHue = !spectrumMode || !peakDue
        ? _motionState.hue
        : switch (eventBand) {
            AmbientRhythm.bassBand => _settings.bassHue,
            AmbientRhythm.midBand => _settings.midHue,
            _ => _settings.trebleHue,
          };

    // The physical strip low-passes a continuously moving target. Hold the
    // peak and valley long enough for its transition to reach the LED, then
    // stop writing until the next onset. This makes one beat read as one
    // impact instead of ten tiny intermediate colours.
    if (peakDue && !duplicatePredictedPeak) {
      final peak = AmbientPalette.colorOf(
          peakHue, peakLevel, _bandSaturation(eventBand));
      _lastPeakWriteAt = now;
      _lastPeakBand = eventBand;
      unawaited(_writePeak(peak));
      _valleyWriteAt =
          now + (rhythm.intervalMs * .22).clamp(100.0, 230.0).round();
      _logFrame(targetHue, peakLevel, bass, peak, dt);
      return;
    }
    if (actualBeat && duplicatePredictedPeak) return;
    if (_valleyWriteAt > 0 && now >= _valleyWriteAt) {
      final valley =
          AmbientPalette.colorOf(valleyHue, valleyLevel, valleySaturation);
      unawaited(_writeValley(valley));
      _logFrame(targetHue, valleyLevel, bass, valley, dt);
      return;
    }

    // Between the valley and the next beat, keep the target stable. If no
    // reliable pulse exists, fall back to a gentle 5Hz colour flow.
    if (_valleyWriteAt == 0 &&
        rhythm.bpm == null &&
        (_lastAmbientWriteAt == 0 || now - _lastAmbientWriteAt >= 200)) {
      final scaled = AmbientPalette.colorOf(
        _motionState.hue,
        (math.pow(_motionState.brightness.clamp(0.0, 1.0), 1.28) * 100).round(),
      );
      color.value = scaled;
      _lastAmbientWriteAt = now;
      _logFrame(targetHue, targetLevel, bass, scaled, dt);
      unawaited(_send('color', {
        'r': scaled.r,
        'g': scaled.g,
        'b': scaled.b,
      }));
    }
    return;
  }

  /// Writes one line per frame, throttled.
  ///
  /// Whether the light is flowing or jumping is invisible otherwise: the
  /// settings page only shows the current colour. Putting the target next to
  /// the smoothed value makes "the target is a step, the current value is a
  /// ramp" obvious in the log.
  void _logFrame(double targetHue, int targetLevel, double bass,
      AmbientColor color, int dt) {
    final now = _clock();
    if (now - _lastFrameLogAt < frameLogIntervalMs) return;
    _lastFrameLogAt = now;
    debugPrint('氛围灯帧 targetHue=${targetHue.toStringAsFixed(1)} '
        'hue=${_motionState.hue.toStringAsFixed(1)} '
        'targetLevel=$targetLevel '
        'brightness=${(_motionState.brightness * 100).round()} '
        'bass=${bass.toStringAsFixed(3)} '
        'dtMs=$dt hex=${color.hex}');
  }

  Future<bool> _send(String method, Object? arguments) async {
    try {
      await methods.invokeMethod<void>(method, arguments);
      return true;
    } catch (_) {
      // The head unit side is optional; a failed write must not take the
      // launcher down.
      return false;
    }
  }

  @override
  void dispose() {
    _stopPolling();
    _fallbackTimer?.cancel();
    spectrum.removeListener(onSpectrumFrame);
    color.dispose();
    super.dispose();
  }
}
