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
    final built = await _build(_asset);
    if (!mounted) return;
    setState(() => _shader = built);
    _syncAnimation();
    _reportMode();
  }

  /// 编不出来（老驱动 / 资源缺失）就回落细渐变，不能把异步异常抛进 zone。
  /// 失败重试一次：首帧前后引擎还在预热，偶发一次 stderr 不值得永久关掉装饰。
  Future<ui.FragmentShader?> _build(String asset) async {
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        final program = await ui.FragmentProgram.fromAsset(asset);
        return program.fragmentShader();
      } catch (error) {
        debugPrint('UniDock fluid shader=$asset failed attempt=${attempt + 1} '
            'error=$error');
        if (attempt == 1) return null;
        await Future<void>.delayed(const Duration(milliseconds: 1200));
        if (!mounted) return null;
      }
    }
    return null;
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

  /// 流体只在**暗夜深色**下生效，而且只有一份 shader（`fluid_progress.frag`）。
  ///
  /// 深色版是「加法发光」+ 墨绿底，只能在近黑底上成立；浅色底栏是 55% 白的
  /// 玻璃，那层墨绿铺上去就是一块脏色（用户 2026-11-19：「浅色模式下明显
  /// 不好看，看上去很脏」）。浅色试过单写一份 over 合成的 shader、也试过「只让
  /// 刀口走 shader」，用户最后定的都是回到原来的进度条 ——「浅色下就还是用原来
  /// 的进度条，相当于关闭了烟雾流动」，只保留刀口颜色跟主题色走。所以浅色那份
  /// shader 与配套的 HSL 旋转调色板已于同日删除，浅色走
  /// [_DockMusicProgressPainter]。
  ///
  /// **不再跟着帧预算降级走**（2026-11-13 实车反馈）：这一档是用户在设置里显式
  /// 打开的，`AdaptiveQuality` 一降级就把它悄悄换成细渐变，用户看到的就是
  /// 「开关怎么拨都是老进度条」。而且它只是覆盖底栏那一条胶囊（一次绘制、一层
  /// 4 octave fbm），和降级要保的「1600 宽实时高斯」不是一个量级；真机上也量不出
  /// 差异。降级仍然管实时模糊（`SurfaceStyle.liveBlur` 与阴影），那一层才是贵的。
  bool get _fluid =>
      widget.fluid &&
      _style?.nocturne == true &&
      (_style?.dark ?? true) &&
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
    final dark = _style?.dark ?? true;
    final fluid = widget.fluid &&
        (_style?.nocturne ?? false) &&
        dark &&
        _shader != null &&
        widget.enabled;
    final mode = '${fluid ? 'fluid' : 'gradient'}|${widget.enabled}|'
        '${widget.fluid}|${_style?.nocturne}|${_style?.lowPower}|$dark|'
        '${_shader != null}|$_playing';
    if (mode == _lastMode) return;
    _lastMode = mode;
    debugPrint('UniDock progress=${fluid ? 'fluid' : 'gradient'} '
        'enabled=${widget.enabled} setting=${widget.fluid} '
        'nocturne=${_style?.nocturne} lowPower=${_style?.lowPower} '
        'dark=$dark shader=${_shader != null} playing=$_playing '
        'dur=$_durMs pos=$_posMs progress=${_progress.toStringAsFixed(3)}');
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return widget.child;
    final style = SurfaceStyle.of(context);
    final shader = _shader;
    final fluid =
        widget.fluid && style.nocturne && style.dark && shader != null;
    _reportMode();
    return RepaintBoundary(
        child: fluid
            ? CustomPaint(
                key: const ValueKey('dock-music-progress'),
                painter: _FluidPainter(
                    shader: shader,
                    drive: _drive,
                    radius: style.controlRadius),
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

  /// 右端基色 = 底栏外壳合成后的颜色（95% 半透 `#1A1E20→#0E1012` 叠壁纸，
  /// 取音乐块中位约 `#14171A`）。
  ///
  /// **不能直接把目标色填进来。** shader 尾部还有两道处理：
  /// `color = color/(1+color*0.14)` 再 `pow(color, 0.94)` —— 后者对暗部是
  /// 明显提亮（0.058 → 0.068，+18%）。上一版把目标色 `#15191B` 原样填进去，
  /// 出来实际是 `≈#181B1E`，比外壳亮一档，所以「还是接不上」。
  ///
  /// 这里填的是反推值：先按 `m = y/(1-0.14y)`、`y = t^(1/0.94)` 把目标
  /// `#14171A` 还原到混色前的量，再按 rightMask 0.92 的权重除掉。
  /// 之前的 `#0F1A18` 则是纯墨绿（g-b 高、r 低），色相上就和中性灰的外壳
  /// 不在一条线上，光调亮度永远对不上。
  static const _darkRight = [.0706, .0784, .0902]; // #121517 对齐外壳合成色
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
    for (final c in const [
      _darkRight,
      _darkLeft,
      _c0,
      _c1,
      _c2,
      _c3,
      _c4,
    ]) {
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
      old.shader != shader ||
      old.radius != radius ||
      old.drive != drive;
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

    // 刀口：**和烟雾版同一个亮芯色**（`_FluidPainter` 那七段里的第七段，
    // 按 accent 旋过来的饱和色），所以开关一开一关只换形态、不换颜色。
    //
    // 旧版是 `lerp(accent, Colors.white, .22)` —— 白底上那是一条**发灰**的线，
    // 而且填充区本身已经被 accent 染到 ~45%，灰线压上去等于没有边界。换成
    // 饱和色之后才读得出「一道透光的缝」（用户 2026-11-19：「把刀口和颜色
    // 换一下」）。
    final blade = _bladeColor;
    final lineHeight = size.height * .72;
    final lineTop = (size.height - lineHeight) / 2;
    final alpha = animate ? .92 : .70;
    // 外层一圈同色柔光，宽度按 8px 走；不用 MaskFilter.blur —— 小矩形上的
    // 模糊在 Impeller 里反而更贵，两层纯色矩形看起来是一样的。
    canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromLTWH(dividerX - 4, lineTop, 8, lineHeight),
            const Radius.circular(4)),
        Paint()
          ..color = blade.withValues(alpha: alpha * .17)
          ..style = PaintingStyle.fill);
    canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromLTWH(dividerX - 1, lineTop, 2, lineHeight),
            const Radius.circular(1)),
        Paint()
          ..color = blade.withValues(alpha: alpha)
          ..strokeWidth = 0
          ..style = PaintingStyle.fill);
    canvas.restore();
  }

  /// 刀口颜色 = `accent` 提亮 22%，和经典 / 蓝玻璃同一条公式。
  ///
  /// 暗夜浅色 2026-11-19 对齐经典皮肤（用户拿经典截图对照后：「只要把浅色的
  /// 按那个经典模式一样做就行了」）。经典里那条线其实比填充**暗**：填充靠刀口
  /// 一侧 `#C096A3` → 刀口线 `#AF7487` → 未播放 `#E5DFE0`，靠的是「填充是极淡
  /// 的同色、刀口是浓缩的同色」，不是提亮成一发光体。所以浅色不再取烟雾版
  /// 调色板的饱和亮芯（那版 `#12E6BE` 艳得像荧光笔），直接复用经典这条公式；
  /// 颜色仍随主题 `accent` 走。
  ///
  /// 深色走不进这里 —— 整块都由 shader 画，刀口是 shader 里那条近白亮芯。
  Color get _bladeColor => Color.lerp(style.accent, Colors.white, .22)!;

  @override
  bool shouldRepaint(covariant _DockMusicProgressPainter oldDelegate) =>
      oldDelegate.style != style ||
      oldDelegate.progress != progress ||
      oldDelegate.glow != glow ||
      oldDelegate.animate != animate;
}
