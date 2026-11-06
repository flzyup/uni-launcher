import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

/// 帧预算看门狗：连续掉帧就把最贵的那一档效果降下来，恢复平滑后再打开。
///
/// 车机（820A / Adreno 530）上「卡不卡」不取决于平均帧率，而取决于最贵的
/// 那几帧：一张卡片上的一层实时高斯在 1600 宽的画布上就是 5~7 ms，两张叠在
/// 一起、再碰上一次后台任务抢占，帧时间就跨过 16.7 ms。
///
/// 所以这一层不做「猜」，而是直接读引擎报上来的真实帧时间（build + raster）：
///
/// * 滚动窗口里 [degradeAbove] 以上占多数 → 降级（关掉实时模糊，改用静态色阶）；
/// * 降级后窗口持续低于 [recoverBelow] 满 [_recoverHold] → 恢复；
/// * 启动后 [_warmup] 内的帧不参与判断（冷启动本来就慢，不该因此永久降级）。
///
/// 降级只改一个布尔值，交给 `SurfaceStyle.lowPower` 走主题层扩散：一次
/// ThemeData 变化就让所有取 `SurfaceStyle.of(context)` 的地方重建，
/// 不需要每张卡片各自订阅，也就不存在「降级本身又掉帧」的问题。
class AdaptiveQuality extends ChangeNotifier {
  AdaptiveQuality._();

  /// 主窗口、底栏、面板引擎各有一份（帧时间本来就是每个引擎自己的）。
  static final AdaptiveQuality shared = AdaptiveQuality._();

  /// 单帧总耗时（build + raster）超过这个就记一次「贵帧」。
  static const double degradeAbove = 22.0;

  /// 恢复要求：窗口内所有帧都低于这个值。
  static const double recoverBelow = 14.0;

  /// 判断用的滚动窗口长度（帧）。
  static const int _window = 40;

  /// 窗口里至少要有这么多帧才开始下结论。
  static const int _minimumFrames = 24;

  /// 启动后的宽限期：这段时间内的帧不参与判断。
  static const Duration _warmup = Duration(seconds: 4);

  /// 降级后要持续平滑这么久才恢复（抖动一次不要来回翻）。
  static const Duration _recoverHold = Duration(seconds: 3);

  final Stopwatch _clock = Stopwatch();
  final List<double> _frames = <double>[];
  Timer? _retry;
  bool _degraded = false;
  bool _started = false;
  Duration? _smoothSince;
  Duration _lastReport = Duration.zero;
  bool _baselineReported = false;

  /// 帧预算告急时报一次的间隔（安静时不打日志，车上不该被诊断刷屏）。
  static const Duration _reportEvery = Duration(seconds: 30);

  /// 是否已经降级（真机上表现为「玻璃卡片不再做实时模糊」）。
  bool get degraded => _degraded;

  /// 当前滚动窗口的平均帧时间（毫秒），诊断用。
  double get averageFrameMs => _frames.isEmpty
      ? 0
      : _frames.reduce((a, b) => a + b) / _frames.length;

  /// 开始采样。重复调用无害。
  void start() {
    if (_started) return;
    _started = true;
    _clock.start();
    SchedulerBinding.instance.addTimingsCallback(_onTimings);
  }

  void _onTimings(List<FrameTiming> timings) {
    if (timings.isEmpty) return;
    if (_clock.elapsed < _warmup) return;
    var worst = 0.0;
    var total = 0.0;
    for (final t in timings) {
      // build + raster 才是这一帧真实占用的时间；vsync 间隔本身不代表成本。
      final ms = t.buildDuration.inMicroseconds / 1000 +
          t.rasterDuration.inMicroseconds / 1000;
      total += ms;
      if (ms > worst) worst = ms;
    }
    var sample = worst;
    if (timings.length > 1) {
      // 一次回调带多帧时取「最贵的」，它才是用户看到的那次卡顿。
      sample = math.max(worst, total / timings.length);
    }
    _frames.add(sample);
    while (_frames.length > _window) {
      _frames.removeAt(0);
    }
    if (_frames.length < _minimumFrames) return;

    final average = averageFrameMs;
    // 每次启动报一次基线：实车上一行就能看出这台车这一版到底多少毫秒。
    if (!_baselineReported && _clock.elapsed >= _reportEvery) {
      _baselineReported = true;
      _lastReport = _clock.elapsed;
      _report('baseline');
    } else if (_clock.elapsed - _lastReport >= _reportEvery && average > recoverBelow) {
      _lastReport = _clock.elapsed;
      _report('window');
    }
    if (!_degraded) {
      _smoothSince = null;
      final heavy = _frames.where((ms) => ms > degradeAbove).length;
      if (average > degradeAbove || heavy * 3 >= _frames.length) _setDegraded(true);
      return;
    }
    final now = _clock.elapsed;
    if (average > recoverBelow) {
      _smoothSince = null;
      return;
    }
    _smoothSince ??= now;
    if (now - _smoothSince! >= _recoverHold && _frames.every((ms) => ms < recoverBelow)) {
      _frames.clear();
      _setDegraded(false);
    }
  }

  void _setDegraded(bool value) {
    if (_degraded == value) return;
    _degraded = value;
    _report(value ? 'degraded' : 'recovered');
    notifyListeners();
    // 刚恢复的那几帧仍然是旧设置渲染出来的，别让它把自己立刻又判回去。
    _retry?.cancel();
    _retry = Timer(const Duration(seconds: 2), () => _frames.clear());
  }

  /// 一行诊断：实车上「到底降没降、卡在哪个量级」看这个就够。
  void _report(String what) {
    if (_frames.isEmpty) return;
    final worst = _frames.reduce(math.max);
    debugPrint('UniQuality $what avg=${averageFrameMs.toStringAsFixed(1)}ms '
        'worst=${worst.toStringAsFixed(1)}ms n=${_frames.length} '
        'degraded=$_degraded');
  }

  @override
  void dispose() {
    _retry?.cancel();
    if (_started) SchedulerBinding.instance.removeTimingsCallback(_onTimings);
    _started = false;
    super.dispose();
  }
}
