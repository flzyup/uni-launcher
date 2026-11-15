import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../theme/design_tokens.dart';
import '../theme/launcher_theme.dart';

/// Draws playback progress behind the dock music controls.
///
/// 打开 [fluid] 时走 `assets/shaders/fluid_progress.frag`：原版 WebGL 蓝紫流体
/// 的直译（三层刀口 + domain-warp 烟雾 + gamma 0.94 + 暗角），边缘带弹簧与
/// echo 拖影。关掉（或 shader 加载不出来）就是原来那条纯渐变发光。
///
/// 每帧成本 = 一次覆盖胶囊的 shader 绘制，没有回读、没有逐帧上传位图。
class DockMusicProgressBackground extends StatefulWidget {
  final Map<String, dynamic> media;
  final bool enabled;

  /// 走 shader 那条「烟雾流体」；关掉回落到纯渐变发光。
  /// 以前这是跟着皮肤走的（只有暗夜），现在由设置页那颗开关决定。
  final bool fluid;
  final Widget child;
  const DockMusicProgressBackground({
    super.key,
    required this.media,
    required this.enabled,
    this.fluid = true,
    required this.child,
  });

  @override
  State<DockMusicProgressBackground> createState() =>
      _DockMusicProgressBackgroundState();
}

class _DockMusicProgressBackgroundState
    extends State<DockMusicProgressBackground> with TickerProviderStateMixin {
  static const _asset = 'assets/shaders/fluid_progress.frag';

  late final AnimationController _glow = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 2100));
  final _drive = _FluidDrive();
  Ticker? _ticker;

  /// 着色器建一次就复用。
  ///
  /// 以前在 paint() 里每帧 `program.fragmentShader()`：播放时 60 次/秒新建一个
  /// shader 对象，Impeller 下每次都要重新绑 uniform buffer。着色器本身没变，
  /// 重建纯属浪费。
  ui.FragmentShader? _shader;
  Duration _last = Duration.zero;
  bool _tickerEnabled = false;
  SurfaceStyle? _style;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick);
    _ingestMedia();
    _updateTarget();
    _load();
  }

  Future<void> _load() async {
    // 编不出来（老驱动 / 资源缺失）就回落细渐变，不能把异步异常抛进 zone。
    // 失败重试一次：首帧前后引擎还在预热，偶发一次 stderr 不值得永久关掉装饰。
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        final program = await ui.FragmentProgram.fromAsset(_asset);
        if (!mounted) return;
        setState(() => _shader = program.fragmentShader());
        _syncAnimation();
        _reportMode();
        return;
      } catch (error) {
        debugPrint('UniDock fluid shader=failed attempt=${attempt + 1} '
            'error=$error');
        if (attempt == 1) return;
        await Future<void>.delayed(const Duration(milliseconds: 1200));
        if (!mounted) return;
      }
    }
  }

  /// 热更新（hot reload）会把已持有的 FragmentShader 句柄弄失效，paint 里
  /// `setFloat` 会拿到 null 抛 `type 'Null' is not a subtype of type
  /// 'FragmentShader'`，底栏进度条直接不画。这里重新从 asset 取一份，
  /// 让带 shader 的组件也能热更新，不必整轮重启。
  @override
  void reassemble() {
    super.reassemble();
    _shader = null;
    _load();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _style = SurfaceStyle.of(context);
    _tickerEnabled = TickerMode.valuesOf(context).enabled;
    _syncAnimation();
  }

  @override
  void didUpdateWidget(DockMusicProgressBackground oldWidget) {
    super.didUpdateWidget(oldWidget);
    _ingestMedia();
    _updateTarget();
    _syncAnimation();
  }

  // ---- 播放进度：本地锚点 ----
  // 原生两条链路的字段不一样：
  //  · 桌面（MediaAdapter）：positionMs + durationMs + positionKnown + sampledAtMs
  //  · 全局底栏（GlobalDockService 白名单）：只转发 positionMs + durationMs
  // 旧实现要求 positionKnown == true，全局底栏下永远判「未知」，进度条就死死
  // 贴在最左边不动（用户实测）。改为：只要有 durationMs 就认为可算进度；
  // 采样时刻优先用 sampledAtMs，没有就用「收到这次推送的时刻」当锚点，
  // 两次推送之间按 playing 线性外推——播放中每帧都在走，暂停时停住。
  int _posMs = 0, _durMs = 0, _anchorMs = 0;
  bool _playing = false;

  void _ingestMedia() {
    final m = widget.media;
    final pos = (m['positionMs'] as num?)?.toInt() ?? -1;
    final dur = (m['durationMs'] as num?)?.toInt() ?? 0;
    final sampled = (m['sampledAtMs'] as num?)?.toInt() ?? 0;
    final playing = m['playing'] == true;
    if (playing && dur > 0 && pos >= 0) {
      // 位置或时长变了才重锚，否则保留原锚点继续外推。
      if (pos != _posMs || dur != _durMs || !_playing) {
        _posMs = pos;
        _durMs = dur;
        _anchorMs =
            sampled > 0 ? sampled : DateTime.now().millisecondsSinceEpoch;
      }
      _playing = true;
    } else {
      _playing = false;
      if (dur > 0) _durMs = dur;
      if (pos >= 0) _posMs = pos;
    }
  }

  /// 当前进度 0..1；暂停时停在最后一次已知位置。
  double get _progress {
    if (_durMs <= 0) return 0;
    final elapsed = _playing && _anchorMs > 0
        ? (DateTime.now().millisecondsSinceEpoch - _anchorMs).clamp(0, _durMs)
        : 0;
    return ((_posMs + elapsed) / _durMs).clamp(0.0, 1.0);
  }

  /// 流体只属于暗夜皮肤。
  ///
  /// shader 的调色板是写死的暗夜色（#0F1A18 底 + 近白刀口），浅色底栏上没有
  /// 对得上的版本——试过反着推一版浅色调色板，出来仍是灰糊一块。所以浅色两套
  /// 皮肤回落到原来那条细渐变发光，开关也只在暗夜下露出来。
  ///
  /// **不再跟着帧预算降级走**（2026-11-13 实车反馈）：这一档是用户在设置里显式
  /// 打开的，`AdaptiveQuality` 一降级就把它悄悄换成细渐变，用户看到的就是
  /// 「开关怎么拨都是老进度条」。而且它只是覆盖底栏那一条胶囊（一次绘制、一层
  /// 4 octave fbm），和降级要保的「1600 宽实时高斯」不是一个量级；真机上也量不出
  /// 差异。降级仍然管实时模糊（`SurfaceStyle.liveBlur` 与阴影），那一层才是贵的。
  bool get _fluid =>
      widget.fluid &&
      _style?.nocturne == true &&
      _shader != null &&
      widget.enabled;

  bool get _active => widget.enabled && _tickerEnabled && _playing;

  void _syncAnimation() {
    final t = _ticker;
    if (t == null) return;
    if (_fluid && _active) {
      if (!t.isActive) {
        _last = Duration.zero;
        t.start();
      }
      _glow.stop();
    } else if (_active) {
      if (t.isActive) t.stop();
      if (!_glow.isAnimating) _glow.repeat();
    } else {
      if (t.isActive) t.stop();
      _glow.stop();
      _glow.value = 0;
    }
  }

  void _updateTarget() => _drive.target = _progress;

  void _onTick(Duration elapsed) {
    final dt = _last == Duration.zero
        ? 1 / 60
        : ((elapsed - _last).inMicroseconds / 1e6).clamp(0.0, 0.05);
    _last = elapsed;
    _updateTarget();
    _drive.time += dt;
    _drive.step(dt);
    _drive.bump();
  }

  @override
  void dispose() {
    _ticker?.dispose();
    _drive.dispose();
    _glow.dispose();
    super.dispose();
  }

  /// 一行诊断：实车上「到底走的哪一条、被哪道门挡住」看这个就够。
  ///
  /// 只在**状态组合**变化时打，不跟着进度/帧号刷屏（一台车一整天也就几行）。
  String _lastMode = '';
  void _reportMode() {
    final fluid =
        widget.fluid && (_style?.nocturne ?? false) && _shader != null && widget.enabled;
    final mode = '${fluid ? 'fluid' : 'gradient'}|${widget.enabled}|'
        '${widget.fluid}|${_style?.nocturne}|${_style?.lowPower}|'
        '${_shader != null}|$_playing';
    if (mode == _lastMode) return;
    _lastMode = mode;
    debugPrint('UniDock progress=${fluid ? 'fluid' : 'gradient'} '
        'enabled=${widget.enabled} setting=${widget.fluid} '
        'nocturne=${_style?.nocturne} lowPower=${_style?.lowPower} '
        'shader=${_shader != null} playing=$_playing '
        'dur=$_durMs pos=$_posMs progress=${_progress.toStringAsFixed(3)}');
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return widget.child;
    final style = SurfaceStyle.of(context);
    final shader = _shader;
    final fluid =
        widget.fluid && style.nocturne && shader != null;
    _reportMode();
    return RepaintBoundary(
        child: fluid
            ? CustomPaint(
                key: const ValueKey('dock-music-progress'),
                painter: _FluidPainter(
                    shader: shader, drive: _drive, radius: style.controlRadius),
                child: widget.child)
            : AnimatedBuilder(
                animation: _glow,
                builder: (context, _) => CustomPaint(
                    key: const ValueKey('dock-music-progress'),
                    painter: _DockMusicProgressPainter(
                        style: style,
                        progress: _progress,
                        glow: _glow.value,
                        animate: _glow.isAnimating),
                    child: widget.child)));
  }
}

/// Spring + echo state, ported 1:1 from the web reference.
class _FluidDrive extends ChangeNotifier {
  double current = 0, target = 0, velocity = 0, impulse = 0;
  double echo1 = 0, echo2 = 0;
  double time = 0;

  /// 0 when nothing is chasing, 1 when the edge is snapping to a new position.
  double get echoAct {
    final v = ((current - echo1).abs() + (echo1 - echo2).abs()) * 18;
    return v.clamp(0.0, 1.0);
  }

  void step(double dt) {
    const stiffness = 26.0, damping = 9.5;
    velocity += (target - current) * stiffness * dt;
    velocity *= math.exp(-damping * dt);
    final next = current + velocity * dt;
    if ((next <= 0 && velocity < 0) || (next >= 1 && velocity > 0)) {
      velocity = 0;
    }
    current = next.clamp(0.0, 1.0);

    final delta = (target - current).abs();
    impulse += (delta * 2.2 - impulse) * math.min(1.0, dt * 5.2);

    echo1 += (current - echo1) * (1 - math.exp(-18 * dt));
    echo2 += (echo1 - echo2) * (1 - math.exp(-18 * .58 * dt));

    if (delta < .0004 && velocity.abs() < .0004) {
      current = target;
      velocity = 0;
      impulse = 0;
    }
  }

  /// 供外部 tick 推进后触发重绘。notifyListeners 是 protected，
  /// 不能在类外直接调，所以在这里包一层。
  void bump() => notifyListeners();
}

class _FluidPainter extends CustomPainter {
  final ui.FragmentShader shader;
  final _FluidDrive drive;
  final double radius;
  _FluidPainter({
    required this.shader,
    required this.drive,
    required this.radius,
  }) : super(repaint: drive);

  // 薄荷深渊：接全局主色 #3BE2C0，同色系五段阶梯。
  // 明度节奏沿用原版蓝紫（深靛→紫→蓝→浅蓝→近白），只把色相整体转到 165° 左右，
  // 所以刀口亮度和烟雾层次都不变，纯粹换色。
  static const _seed = 2.54;
  static const _darkRight = [.058, .104, .096]; // #0F1A18 极深墨绿
  static const _darkLeft = [.032, .075, .069]; // #081311
  static const _c0 = [.039, .180, .161]; // #0A2E29 拖尾最深
  static const _c1 = [.071, .412, .353]; // #12695A 深青
  static const _c2 = [.133, .702, .608]; // #22B39B 青绿
  static const _c3 = [.231, .886, .753]; // #3BE2C0 全局主色
  static const _c4 = [.890, 1.000, .973]; // #E3FFF8 亮芯

  /// 原版画布 940×238 的宽高比。
  static const _origAspect = 940 / 238;

  /// 边缘摆动幅度系数 —— HTML 版 EDGE_AMP。
  static const _edgeAmp = 1.38;

  /// 刀口收细系数 —— HTML 版 BLADE_K。
  static const _bladeK = 1.60;

  double _fitAmp(Size size) {
    final flat = (size.width / size.height) / _origAspect;
    if (flat <= 1) return _edgeAmp;
    return _edgeAmp / flat;
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    var i = 0;
    void f(double v) => shader.setFloat(i++, v);

    f(size.width);
    f(size.height);
    f(drive.time);
    f(drive.current);
    f(_seed);
    f(drive.velocity);
    f(drive.impulse);
    f(drive.echo1);
    f(drive.echo2);
    f(drive.echoAct);
    f(_fitAmp(size));
    f(_bladeK);
    for (final c in [_darkRight, _darkLeft, _c0, _c1, _c2, _c3, _c4]) {
      f(c[0]);
      f(c[1]);
      f(c[2]);
    }

    canvas.save();
    canvas.clipRRect(
        RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(radius)));
    canvas.drawRect(Offset.zero & size, Paint()..shader = shader);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _FluidPainter old) =>
      old.shader != shader || old.radius != radius || old.drive != drive;
}

class _DockMusicProgressPainter extends CustomPainter {
  final SurfaceStyle style;

  /// 0..1 的播放进度（由外层按本地锚点算出，见 `_progress`）。
  final double progress;
  final double glow;
  final bool animate;
  const _DockMusicProgressPainter({
    required this.style,
    required this.progress,
    required this.glow,
    required this.animate,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    if (progress <= 0) return;
    final dividerX = progress.clamp(0.0, 1.0) * size.width;
    if (dividerX < 1) return;

    final accent = style.accent;
    // 进度染色沿用经典主题的满高整块渐变，只多一层按音乐块圆角的裁剪：
    // 外层 GlassSurface 的裁剪盖得住四角、盖不住中间这两条 drawRect，胶囊
    // 里就会亮出一个直角方框（用户反馈「音乐外面那个框」）。
    canvas.save();
    canvas.clipRRect(RRect.fromRectAndRadius(
        Offset.zero & size, Radius.circular(style.controlRadius)));

    final fill = Paint()
      ..shader = ui.Gradient.linear(Offset.zero, Offset(dividerX, 0), [
        accent.withValues(alpha: .05),
        accent.withValues(alpha: .18),
      ]);
    canvas.drawRect(Rect.fromLTWH(0, 0, dividerX, size.height), fill);

    // First-version breathing glow anchored at the divider, with a smooth
    // leftward fade so the cycle reads as one continuous motion.
    final available = math.min(dividerX, Design.px(140));
    final spread = .50 + .50 * math.sin(math.pi * glow);
    final glowWidth = available * (.52 + .48 * spread);
    final glowLeft = math.max(0.0, dividerX - glowWidth);
    final strength = available / Design.px(140);
    final glowPaint = Paint()
      ..shader = ui.Gradient.linear(Offset(glowLeft, 0), Offset(dividerX, 0), [
        accent.withValues(alpha: 0),
        accent.withValues(alpha: .34 * spread * strength),
      ]);
    canvas.drawRect(
        Rect.fromLTWH(glowLeft, 0, dividerX - glowLeft, size.height),
        glowPaint);

    final lineColor = Color.lerp(accent, Colors.white, .22)!;
    final lineHeight = size.height * .72;
    final lineTop = (size.height - lineHeight) / 2;
    canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromLTWH(dividerX - 1, lineTop, 2, lineHeight),
            const Radius.circular(1)),
        Paint()
          ..color = lineColor.withValues(alpha: animate ? .92 : .70)
          ..strokeWidth = 0
          ..style = PaintingStyle.fill);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _DockMusicProgressPainter oldDelegate) =>
      oldDelegate.style != style ||
      oldDelegate.progress != progress ||
      oldDelegate.glow != glow ||
      oldDelegate.animate != animate;
}
