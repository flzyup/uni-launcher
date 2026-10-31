import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../model/ambient_color_space.dart';
import '../model/ambient_light.dart';
import '../model/ambient_motion.dart';
import '../model/ambient_motion_legacy.dart';
import '../model/ambient_rhythm.dart';
import '../model/spectrum_perception.dart';
import 'audio_spectrum.dart';

/// Drives the head unit ambient strip from the music that is playing.
///
/// The spectrum to colour mapping lives in [AmbientPalette] so it can be
/// unit tested without a device. This class owns the platform channel, the
/// spectrum subscription and the render clock.
///
/// Nothing reaches the head unit until the user turns the music ambience on.
/// The strip is only lit while the spectrum is actually available, so a car
/// without the vendor framework simply reports that it is unavailable instead
/// of failing silently.
///
/// The live colour is exposed through [color] as a separate notifier: the
/// settings page must not rebuild on every frame.
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
  static const int defaultFrameMs = 100;

  /// The interval between the frame log lines (milliseconds).
  static const int frameLogIntervalMs = 50;

  /// The **render clock** interval (milliseconds) — 60 Hz.
  ///
  /// ## Why the render clock is separate from the spectrum
  ///
  /// The legacy chain was one step: a spectrum frame arrives, a colour is
  /// computed, the colour is written. Everything ran at 10 Hz, so the
  /// smoothing (the rate limit, the attack and decay) could only ever
  /// connect the 100 ms steps into a ramp — and a ramp with a corner every
  /// 100 ms still looks like a jump.
  ///
  /// V2 splits the two:
  ///
  /// | | spectrum | colour and motion | write |
  /// | --- | --- | --- | --- |
  /// | legacy | 10 Hz | 10 Hz | 10 Hz (100 ms) |
  /// | **V2** | 10 Hz | **60 Hz** (this timer) | **20 Hz** (50 ms) |
  ///
  /// The spectrum is still 10 Hz (the capture cannot go faster), but the
  /// motion layer integrates every frame at 60 Hz, so the curve really is
  /// continuous.
  static const int renderIntervalMs = 16;

  /// The frame interval of the legacy engine (milliseconds).
  ///
  /// The legacy chain steps with the spectrum, so its elapsed time is the
  /// spectrum interval. Following the wall clock instead would only add
  /// jitter.
  static const int legacyFrameMs = 100;

  /// How often the live colour is pushed to the listeners (milliseconds).
  ///
  /// 20 Hz is enough for a preview, and it keeps the settings page from
  /// rebuilding on every render frame.
  static const int publishIntervalMs = 50;

  /// The interval between two colour writes (milliseconds).
  ///
  /// This is the **write cadence of the head unit** and has to match the
  /// throttle of the native writer (`AmbientLightWriter.MIN_INTERVAL_MS`).
  ///
  /// ## Why the render budget is divided by it
  ///
  /// The render clock runs at 60 Hz, but only every [writeIntervalMs] does a
  /// frame actually reach the car. The colour difference that lands on the
  /// car is therefore the **sum of the render steps inside one write
  /// window** — so the per frame budget has to be a fraction of the total
  /// budget, otherwise the colour drifts further and further away from the
  /// music (see [_perFrameDeltaECap]).
  static const int writeIntervalMs = 50;

  /// The relative level below which nothing is playing (the idle state).
  static const double silentRelativeLevel = 0.02;

  /// The brightness compensation when only one zone is lit.
  ///
  /// ## Why it is not the full 3
  ///
  /// This head unit has **no zone brightness**, only one global RGB, so the
  /// compensation can only act on the single lit zone.
  ///
  /// Compensating fully would need a factor of 3 (three zones of one third
  /// of the light each), and that would blow out the colour. So only a part
  /// is compensated and the rest of the dip is absorbed by the order of the
  /// writes: the new zone is opened **before** the old one is closed, so
  /// the in between state has one zone *too many* lit rather than one too
  /// few.
  static const double zoneBrightnessCompensation = 1.6;

  /// The default dwell time of the zone choreography (milliseconds).
  ///
  /// Below 700 ms the hard edge of the zone switch becomes visible.
  static const int defaultZoneDwellMs = 800;

  /// The number of zones (main, top, bottom).
  static const int zoneCount = 3;

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

  /// The perception layer: absolute dB to relative level.
  ///
  /// Without it the absolute dB of a heavily compressed master keeps every
  /// band above 0.7, so the strip is always bright and the movement is
  /// invisible. See [SpectrumPerception].
  final SpectrumPerception _perception = SpectrumPerception();

  /// The normalised bands of the perception layer (V2 only).
  List<double> _perceivedBands = const [];

  /// The motion layer of the V2 engine.
  AmbientMotion? _motion;

  /// The state of the V2 motion layer, kept across frames.
  AmbientMotionState _motionState = const AmbientMotionState();

  /// The legacy motion layer.
  final AmbientMotionLegacy _legacyMotion = const AmbientMotionLegacy();

  /// The state of the legacy motion layer.
  AmbientMotionLegacyState _legacyMotionState = const AmbientMotionLegacyState();

  // —— The targets of the art layer (V2). ——
  double _targetHue = 0;
  double _targetLevel = 0;
  double _targetChroma = 0;
  double _bass = 0;
  bool _silent = true;

  /// The accumulated hue self-rotation phase (degrees, normalized).
  double _rotationPhaseDeg = 0;

  /// The hue self-rotation speed, cached from the settings.
  ///
  /// The 60 Hz frame loop must not read the settings every frame: the value
  /// only changes when [_rebuildMotion] runs.
  double _hueRotateDegPerSec = 0;

  /// The monotonic clock, in milliseconds.
  final int Function() _clock;

  /// The moment of the previous frame, for the elapsed time.
  int _lastFrameAt = 0;

  /// The moment of the previous frame log, for the log throttle.
  int _lastFrameLogAt = 0;

  /// The moment of the last published colour, for the publish throttle.
  int _lastPublishAt = 0;

  /// Whether a new spectrum frame arrived since the last render frame.
  bool _spectrumDirty = false;

  /// The render clock.
  Timer? _renderTimer;

  // —— The rhythm engine (upstream's chain). ——
  //
  // It writes one peak colour and one valley colour per beat instead of
  // rendering a continuous flow: the vendor strip low-passes a moving
  // target, so holding each extreme long enough is what reads as an impact.

  /// The beat detector of the rhythm engine.
  final AmbientRhythm _rhythm = AmbientRhythm();

  /// Writes a static colour every second while nothing is playing.
  Timer? _fallbackTimer;

  /// The moment of the last spectrum frame that actually carried sound.
  int _lastSignalAt = 0;

  /// The moment of the last colour write (rhythm engine).
  int _lastAmbientWriteAt = 0;

  /// The moment the valley colour is due (0 = none scheduled).
  int _valleyWriteAt = 0;

  /// The moment of the last peak write.
  int _lastPeakWriteAt = 0;

  /// The predicted beat that was already written, so it is not repeated.
  int _predictedBeatAt = 0;

  /// The frequency region of the last peak write.
  int? _lastPeakBand;

  /// The colour of the previous **render** frame, the base of the Delta E00
  /// speed limit.
  AmbientColor? _lastRenderedColor;

  /// The zone that is currently lit (-1 = the whole cabin).
  int _zoneIndex = -1;

  /// The moment of the next zone switch.
  int _zoneNextAt = 0;

  /// How many zones are lit (1 while the choreography runs, 3 otherwise).
  int _zoneLitCount = zoneCount;

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

  /// The frames the capture delivered, and how many carried a signal.
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

  /// Whether the V2 engine drives the strip.
  bool get v2Engine => _settings.engine == AmbientLightSettings.engineV2;

  /// Whether the rhythm engine drives the strip.
  bool get rhythmEngine => _settings.engine == AmbientLightSettings.engineRhythm;

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
    final engineChanged = next.engine != _settings.engine;
    _settings = next;
    _rebuildMotion();
    if (next.enabled != wasEnabled) {
      await _syncEnabled();
    } else if (next.enabled) {
      // The mapping changed, so the next frame already carries the new colour.
      await _syncBrightness();
      // The engine changed: the state of the other engine must not leak in.
      if (engineChanged) {
        _resetMotionState();
        _renderFrame();
      }
    }
    notifyListeners();
  }

  /// Switches the music ambience on or off.
  Future<void> setEnabled(bool value) =>
      applySettings(_settings.copyWith(enabled: value));

  /// Turns the strip on and starts the spectrum capture it needs.
  Future<void> _syncEnabled() async {
    if (_settings.enabled) {
      // A fresh switch-on starts the self-rotation from zero, so the colour
      // does not jump to a phase left over from the last session.
      _rotationPhaseDeg = 0;
      spectrum.setDemand(this, true);
      await _send('enable', true);
      // The brightness is the user's absolute value, so it is written once
      // here instead of on every spectrum frame.
      await _syncBrightness();
      _startPolling();
      if (rhythmEngine) {
        // The rhythm chain writes from the spectrum callback, so it does not
        // need the 60 Hz render clock. While the capture starts (or when
        // nothing plays) a static colour keeps the strip visibly on.
        _rhythm.reset();
        _lastSignalAt = 0;
        _valleyWriteAt = 0;
        _lastAmbientWriteAt = 0;
        _predictedBeatAt = 0;
        await _writeFallback();
        _fallbackTimer?.cancel();
        _fallbackTimer = Timer.periodic(const Duration(seconds: 1), (_) {
          final now = _clock();
          if (_settings.enabled && now - _lastSignalAt > 1500) {
            unawaited(_writeFallback());
          }
        });
      } else {
        _fallbackTimer?.cancel();
        _fallbackTimer = null;
        _startRenderClock();
      }
    } else {
      spectrum.setDemand(this, false);
      await _send('enable', false);
      _stopPolling();
      _stopRenderClock();
      _fallbackTimer?.cancel();
      _fallbackTimer = null;
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

  /// Starts the 60 Hz render clock.
  void _startRenderClock() {
    _renderTimer?.cancel();
    _renderTimer = Timer.periodic(
      const Duration(milliseconds: renderIntervalMs),
      (_) => _renderFrame(),
    );
  }

  void _stopRenderClock() {
    _renderTimer?.cancel();
    _renderTimer = null;
  }

  /// Pushes the current brightness once, used after a settings change.
  Future<void> _syncBrightness() async {
    final value = _settings.vehicleBrightness;
    if (value == _writtenBrightness) return;
    if (await _send('brightness', value)) _writtenBrightness = value;
  }

  /// Rebuilds the motion layer from the current settings.
  ///
  /// The parameters are constructor arguments, not runtime values, so a
  /// settings change replaces the instance.
  void _rebuildMotion() {
    // Cached here (the cardesk controller does the same): the render loop
    // reads it every frame and must not touch the settings object.
    _hueRotateDegPerSec = _settings.hueRotateDegPerSec.toDouble();
    // The legacy chain has its own motion layer; V2 and the rhythm engine
    // both use AmbientMotion.
    if (_settings.engine == AmbientLightSettings.engineLegacy) {
      _motion = null;
      return;
    }
    _motion = AmbientMotion(
      hueTauMs: _settings.hueTauMs.toDouble(),
      hueMaxDegPerSec: _settings.hueMaxDeg.toDouble(),
      hueMaxAccelDegPerSec2: _settings.hueMaxAccel.toDouble(),
      hueJumpDeg: _settings.hueJumpDeg.toDouble(),
      attackMs: _settings.attackMs.toDouble(),
      decayMs: _settings.decayMs.toDouble(),
      breathAmount: _settings.breath,
      pulseGain: _settings.pulseGainValue,
      beatMinGapMs: _settings.beatMinGapMs,
      jumpHoldMs: _settings.jumpHoldMs,
    );
  }

  /// Clears the motion state, so one engine does not inherit the other.
  void _resetMotionState() {
    _motionState = const AmbientMotionState();
    _legacyMotionState = const AmbientMotionLegacyState();
    _lastRenderedColor = null;
    _zoneIndex = -1;
    _zoneLitCount = zoneCount;
    // The rotation phase belongs to the engine, so switching engines starts
    // it over instead of carrying a phase into the other chain.
    _rotationPhaseDeg = 0;
    _rhythm.reset();
    _lastSignalAt = 0;
    _valleyWriteAt = 0;
    _lastAmbientWriteAt = 0;
    _predictedBeatAt = 0;
    _lastPeakBand = null;
  }

  /// Takes one spectrum frame and turns it into the targets of the art layer.
  ///
  /// ## This layer does not produce a colour
  ///
  /// The colour is composed on the 60 Hz render clock (see [_renderFrame]).
  /// The spectrum cannot go faster than 10 Hz, but the targets stay the same
  /// between two frames, so the motion layer still walks them smoothly at
  /// 60 Hz.
  void onSpectrumFrame() {
    // A spectrum frame arrives ten times a second. Only a change of the
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
    if (bands.isEmpty) return;

    if (rhythmEngine) {
      _renderRhythmFrame(bands);
    } else if (v2Engine) {
      // The perception layer: absolute dB to relative level.
      _perceivedBands = _perception.process(bands, defaultFrameMs);
      _computeTargets();
    }
    _spectrumDirty = true;
  }

  /// The art layer: bands and relative level to hue, lightness and chroma.
  ///
  /// ## The three signals are deliberately out of step
  ///
  /// | output | driven by | time scale |
  /// | --- | --- | --- |
  /// | hue | the spectral centroid (the timbre) | seconds |
  /// | lightness | the overall relative level | 10 to 100 ms |
  /// | chroma | the high frequency transient | 10 to 50 ms |
  ///
  /// They come from different statistics of the spectrum, so they are
  /// naturally out of step: the strip reads as a flow instead of everything
  /// shaking together.
  void _computeTargets() {
    final bands = _perceivedBands;
    final rel = _perception.relativeLevel;
    final spanDeg = _settings.hueSpanDeg.toDouble();
    final windowLow = _settings.centroidWindowLow;
    final windowSpan = _settings.centroidWindowSpan;
    switch (_settings.mode) {
      case AmbientPalette.modeFixed:
        _targetHue = AmbientPalette.normalizeHue(_settings.fixedHue);
      case AmbientPalette.modeSpectrum:
        _targetHue = AmbientPalette.centroidHue(
          bands,
          _motionState.hue,
          spanDeg: spanDeg,
          windowLow: windowLow,
          windowSpan: windowSpan,
        );
      default:
        _targetHue = AmbientPalette.lowCentroidHue(
          bands,
          _motionState.hue,
          spanDeg: spanDeg,
          windowLow: windowLow,
          windowSpan: windowSpan,
        );
    }
    _targetLevel = AmbientPalette.levelFromRelative(
      relative: rel,
      sensitivity: _settings.sensitivity,
      floorPercent: _settings.floor.toDouble(),
    );
    _targetChroma = AmbientPalette.chromaTarget(
      bands,
      _settings.saturation,
      maxChroma: _settings.maxChromaValue,
    );
    _bass = AmbientPalette.bassEnergy(bands);
    _silent = rel < silentRelativeLevel;
  }

  /// Renders one frame on the 60 Hz clock.
  void _renderFrame() {
    if (!_settings.enabled) return;
    if (rhythmEngine) return;
    final now = _clock();
    final dt = _lastFrameAt > 0 ? now - _lastFrameAt : renderIntervalMs;
    _lastFrameAt = now;

    _updateZoneChoreo(now);

    if (v2Engine) {
      _renderV2(now, dt);
    } else {
      // The legacy engine steps **with the spectrum**, so it only integrates
      // when a new frame arrived. That is the "production car" look, not
      // "the new one running slower".
      if (!_spectrumDirty) return;
      _spectrumDirty = false;
      _renderLegacy(now);
    }
  }

  /// The V2 render: the motion layer integrates, then OKLCH makes the colour.
  void _renderV2(int now, int dt) {
    final motion = _motion ??= AmbientMotion();
    // The self-rotation: when the centroid stops moving (a repeated chorus)
    // time alone keeps pushing the hue around the circle. The fixed-colour
    // mode must not rotate, otherwise the user's picked colour drifts away.
    var targetHue = _targetHue;
    if (_hueRotateDegPerSec > 0 &&
        _settings.mode != AmbientPalette.modeFixed) {
      _rotationPhaseDeg = AmbientPalette.rotationPhase(
          _rotationPhaseDeg, _hueRotateDegPerSec, dt);
      targetHue = AmbientPalette.normalizeHue(_targetHue + _rotationPhaseDeg);
    }
    _motionState = motion.step(
      prev: _motionState,
      targetHue: targetHue,
      targetLevel: _targetLevel,
      targetChroma: _targetChroma,
      bass: _bass,
      dtMs: dt,
      nowMs: now,
      silent: _silent,
    );
    // The level of the motion layer is a relative energy: as the perceptual
    // lightness it keeps a floor, so the dark end is not black.
    final lightness = AmbientPalette.perceptualLightness(_motionState.level);
    final color = AmbientPalette.colorOfOklch(
      _motionState.hue,
      lightness,
      _motionState.chroma,
    );
    _publishColor(color, now);
  }

  // —— 节奏引擎（上游 7c548f8）：峰值/谷值写灯 ——

  /// Writes a visible static colour while capture is starting, silent or
  /// unavailable.
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

  /// Writes the peak of a beat: the colour plus the user's brightness step.
  ///
  /// The vendor strip low-passes rapid colour targets; its own high/low
  /// brightness ladder is much more visible, so the beat toggles both.
  Future<void> _writePeak(AmbientColor frame) async {
    _lastAmbientWriteAt = _clock();
    _valleyWriteAt = 0;
    color.value = frame;
    await _send('color', {'r': frame.r, 'g': frame.g, 'b': frame.b});
    await _send('brightness', _settings.vehicleBrightness);
  }

  /// Writes the valley after a peak: the colour plus a dimmer step.
  Future<void> _writeValley(AmbientColor frame) async {
    _lastAmbientWriteAt = _clock();
    _valleyWriteAt = 0;
    color.value = frame;
    await _send('color', {'r': frame.r, 'g': frame.g, 'b': frame.b});
    if (_settings.vehicleBrightness > 50) {
      await _send('brightness', (_settings.vehicleBrightness * .38).round());
    }
  }

  /// The saturation of a region's custom colour, or the palette default.
  double _bandSaturation(int band) {
    final custom = switch (band) {
      AmbientRhythm.bassBand => _settings.bassCustom,
      AmbientRhythm.midBand => _settings.midCustom,
      _ => _settings.trebleCustom,
    };
    return AmbientPalette.saturationOfHex(custom) ?? AmbientPalette.saturation;
  }

  /// One spectrum frame of the rhythm engine.
  void _renderRhythmFrame(List<double> bands) {
    if (!_spectrumReady || bands.isEmpty || spectrum.peakLevel < .025) return;
    final now = _clock();
    _lastSignalAt = now;
    final rhythm = _rhythm.step(bands, now);

    // —— Step one: the targets. The raw spectrum picks a hue and a level. ——
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
      // voice/guitar reads green, and cymbals read blue-violet.
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
    _motionState = (_motion ??= AmbientMotion()).step(
      prev: _motionState,
      targetHue: targetHue,
      targetLevel: targetLevel.toDouble(),
      targetChroma: _motionState.chroma,
      bass: bass,
      dtMs: dt,
      nowMs: now,
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
    if (predictedBeat) _predictedBeatAt = rhythm.nextBeatMs!;
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
      _logFrame(now, peak);
      return;
    }
    if (actualBeat && duplicatePredictedPeak) return;
    if (_valleyWriteAt > 0 && now >= _valleyWriteAt) {
      final valley =
          AmbientPalette.colorOf(valleyHue, valleyLevel, valleySaturation);
      unawaited(_writeValley(valley));
      _logFrame(now, valley);
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
      _logFrame(now, scaled);
      unawaited(_send('color', {
        'r': scaled.r,
        'g': scaled.g,
        'b': scaled.b,
      }));
    }
  }

  /// The legacy render: the chain that was verified on the car (HSV plus a
  /// linear RGB scale, stepping at 10 Hz).
  void _renderLegacy(int now) {
    final bands = spectrum.levels;
    if (bands.isEmpty) return;
    final targetHue = AmbientPalette.targetHue(
      bands: bands,
      mode: _settings.mode,
      fixedHue: _settings.fixedHue,
      // Silence keeps the *current* hue, so the strip does not jump back
      // to zero degrees.
      fallbackHue: _legacyMotionState.hue,
    );
    final targetLevel = AmbientPalette.targetLevel(
      bands: bands,
      level: spectrum.peakLevel,
      mode: _settings.mode,
      sensitivity: _settings.sensitivity,
      minBrightness: _settings.minBrightness,
      maxBrightness: _settings.maxBrightness,
    );
    _legacyMotionState = _legacyMotion.step(
      prev: _legacyMotionState,
      targetHue: targetHue,
      targetLevel: targetLevel,
      bass: AmbientPalette.bassEnergy(bands),
      dtMs: legacyFrameMs,
    );
    final color = AmbientPalette.colorOf(
      _legacyMotionState.hue,
      (_legacyMotionState.brightness * 100).round(),
    );
    _publishColor(color, now);
  }

  /// Publishes the colour and hands it to the head unit.
  ///
  /// ## The brightness is not written here
  ///
  /// The head unit brightness is the user's absolute value (see
  /// [_syncBrightness]); the music shows in the colour instead.
  ///
  /// ## The legacy chain is not rate limited
  ///
  /// The legacy engine is the **production look that was verified on the
  /// car**: 10 Hz hard jumps. The Delta E00 limiter is a V2 thing — putting
  /// it on the legacy chain as well would flatten it into a slow ramp and
  /// make the "old vs new" comparison meaningless.
  void _publishColor(AmbientColor frame, int now) {
    final compensated = _applyZoneCompensation(frame);
    // The jump mode switches the render limiter off as well: a limiter smears
    // one colour jump into a dozen frames of ramp — that is exactly the
    // "still too smooth" look. The jump has to land in one or two frames.
    final jumpMode = _settings.hueJumpDeg > 0;
    final adjusted =
        v2Engine && !jumpMode ? _limitDeltaE(compensated) : compensated;
    _logFrame(now, adjusted);
    if (now - _lastPublishAt >= publishIntervalMs) {
      _lastPublishAt = now;
      color.value = adjusted;
    }
    // The native writer drops the frames that arrive too often or did not
    // change the colour much, so the stream stays at the write rate. The
    // colour is handed over on **every** render frame on purpose: the
    // writer has to be able to pick the newest one as soon as its window
    // opens, otherwise the colour on the car is one window behind and the
    // next frame jumps twice as far.
    unawaited(_send('color', {
      'r': adjusted.r,
      'g': adjusted.g,
      'b': adjusted.b,
    }));
  }

  // ------------------------------------------------------------------ Delta E00 speed limit

  /// The colour difference budget of **one render frame** (Delta E00).
  ///
  /// = `maxDeltaE * render interval / write interval`
  ///
  /// ## Why the budget has to be divided
  ///
  /// The render clock runs at 60 Hz and the write cadence is 50 ms, so one
  /// write window holds about three render frames.
  ///
  /// | | how far the colour may travel |
  /// | --- | --- |
  /// | the render layer (three frames) | 3 x the frame budget |
  /// | the write layer (one frame) | the whole budget |
  ///
  /// If both layers used the **same** budget the candidate would run twice
  /// as fast as the writes could follow, so the write layer would pull it
  /// back every time — and the difference between the written colour and
  /// the real colour would **pile up** frame after frame. After a few
  /// seconds the colour on the car has nothing to do with the music any
  /// more.
  ///
  /// Dividing the budget by the number of frames per write window keeps the
  /// two in step: the render layer never gets ahead of the write layer, so
  /// the write layer stays a pure safety net.
  double get _perFrameDeltaECap {
    final total = _settings.maxDeltaE;
    if (total <= 0) return 0;
    return total * renderIntervalMs / writeIntervalMs;
  }

  /// Limits the candidate colour so it stays within the cap of the previous
  /// **render** frame.
  ///
  /// ## Why the limit lives here and not in the native writer
  ///
  /// The native side is a **pure pipe**: it throttles the writes (50 ms) and
  /// writes the newest colour it was given, but it does not know anything
  /// about colours. All the colour maths therefore lives in Dart — otherwise
  /// CIEDE2000 would have to be implemented twice, in Kotlin and in Java.
  ///
  /// That makes this the **only** limiter, so it has to carry the whole
  /// guarantee:
  ///
  /// | | base | what it guarantees |
  /// | --- | --- | --- |
  /// | render layer (here) | the previous render frame (60 Hz) | the rendered curve is continuous, **and** the frames that reach the car stay within the cap — because the budget is sized against the write window |
  /// | native writer | the last **written** colour | the write cadence (50 ms) and "only the newest frame" |
  ///
  /// Limiting only at the write would not work here: the native side has no
  /// perceptual notion of "how far the colour may travel", and the frames
  /// that were dropped in between pile up into the next write, so two frames
  /// on the car can differ by several times the cap.
  AmbientColor _limitDeltaE(AmbientColor color) {
    final prev = _lastRenderedColor;
    final cap = _perFrameDeltaECap;
    if (prev == null || cap <= 0) {
      _lastRenderedColor = color;
      return color;
    }
    final (r, g, b) = AmbientColorSpace.limitByDeltaE(
      prev.r,
      prev.g,
      prev.b,
      color.r,
      color.g,
      color.b,
      cap,
    );
    final limited = AmbientColor(r, g, b, color.brightness);
    _lastRenderedColor = limited;
    return limited;
  }

  // ------------------------------------------------------------------ zone choreography

  /// The zone choreography state machine.
  ///
  /// ## Why only a slow choreography
  ///
  /// This head unit has **only zone switches, no zone colour and no zone
  /// brightness** (the {@code 0x2A} segment is not implemented, so a set
  /// always fails). A zone switch is therefore a **hard edge**: one zone
  /// lit, the others dark.
  ///
  /// Three rules make it read like a breath instead of a flash:
  /// 1. **The dwell**: at least [defaultZoneDwellMs] per zone, slower than
  ///    the 1 to 2 Hz of the music, so the two do not fight each other;
  /// 2. **The brightness compensation**: the global RGB is lifted a little
  ///    while only one zone is lit, so the total light flux does not dip;
  /// 3. **The order**: the new zone is opened **before** the old one is
  ///    closed, so the in between state has one zone too many lit rather
  ///    than one too few.
  void _updateZoneChoreo(int now) {
    if (!_settings.enabled) return;
    if (!_settings.zoneChoreo) {
      // The choreography was switched off: the zones the choreography had
      // darkened have to come back on, otherwise the cabin stays half lit.
      if (_zoneIndex >= 0) {
        for (var zone = 0; zone < zoneCount; zone++) {
          _sendZone(zone, true);
        }
        _zoneIndex = -1;
        _zoneLitCount = zoneCount;
      }
      return;
    }
    if (_zoneIndex < 0) {
      // The choreography starts at the first zone.
      _zoneIndex = 0;
      _zoneNextAt = now + _settings.zoneDwellMs;
      _zoneLitCount = 1;
      _sendZone(0, true);
      return;
    }
    if (now >= _zoneNextAt) {
      final next = (_zoneIndex + 1) % zoneCount;
      final previous = _zoneIndex;
      _zoneIndex = next;
      _zoneNextAt = now + _settings.zoneDwellMs;
      _zoneLitCount = 1;
      // The new zone first, then the old one: the in between state has one
      // zone too many lit, never one too few.
      _sendZone(next, true);
      _sendZone(previous, false);
    }
  }

  /// Writes one zone switch to the head unit.
  void _sendZone(int zone, bool enabled) {
    unawaited(_send('zone', {'zone': zone, 'enabled': enabled}));
  }

  /// Compensates the brightness while only one zone is lit.
  AmbientColor _applyZoneCompensation(AmbientColor color) {
    if (_zoneLitCount >= zoneCount) return color;
    final k = zoneBrightnessCompensation;
    return AmbientColor(
      (color.r * k).round().clamp(0, 255),
      (color.g * k).round().clamp(0, 255),
      (color.b * k).round().clamp(0, 255),
      color.brightness,
    );
  }

  /// Writes one line per frame, throttled.
  ///
  /// Whether the light is flowing or jumping is invisible otherwise: the
  /// settings page only shows the current colour. Putting the target next to
  /// the smoothed value makes "the target is a step, the current value is a
  /// ramp" obvious in the log.
  void _logFrame(int now, AmbientColor color) {
    if (now - _lastFrameLogAt < frameLogIntervalMs) return;
    _lastFrameLogAt = now;
    final hue = _settings.engine == AmbientLightSettings.engineLegacy
        ? _legacyMotionState.hue
        : _motionState.hue;
    final engineLabel = _settings.engine == AmbientLightSettings.engineV2
        ? '新版'
        : _settings.engine == AmbientLightSettings.engineRhythm
            ? '节奏'
            : '旧版';
    debugPrint('氛围灯帧 engine=$engineLabel '
        'targetHue=${_targetHue.toStringAsFixed(1)} '
        'hue=${hue.toStringAsFixed(1)} '
        'targetLevel=${(_targetLevel * 100).round()} '
        'brightness=${((v2Engine ? _motionState.brightness : _legacyMotionState.brightness) * 100).round()} '
        'bass=${_bass.toStringAsFixed(3)} '
        'hex=${color.hex}');
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
    _stopRenderClock();
    _fallbackTimer?.cancel();
    spectrum.removeListener(onSpectrumFrame);
    color.dispose();
    super.dispose();
  }
}
