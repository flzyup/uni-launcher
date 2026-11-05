import 'dart:async';

import 'package:flutter/material.dart';

import '../model/cluster_layout.dart';
import '../platform/cluster_lyrics.dart';
import '../theme/design_tokens.dart';
import '../theme/launcher_theme.dart';
import 'glass_surface.dart';
import 'setting_block.dart';

/// Settings for the lyric cast: which display the words land on, where exactly they sit on
/// that display, how big they are and what they look like.
///
/// The display list is produced by the native service from `DisplayManager`, so it shows what
/// the unit actually exposes rather than what this project hopes for. An empty list is an
/// answer: on that car the cluster is driven by another process and no window from here can
/// reach it.
///
/// Placement is edited by dragging a preview block. The preview and the cluster run the same
/// maths ([ClusterLayout] here, `ClusterPanelGeometry` natively), so what the finger drops on
/// the mock screen is where the panel actually appears — the alternative, four number fields
/// for centre-x, centre-y, width and offsets, is unusable while parked and unverifiable while
/// driving.
class ClusterLyricsSettingsTab extends StatefulWidget {
  const ClusterLyricsSettingsTab({super.key, this.client = const ClusterLyrics()});

  final ClusterLyrics client;

  @override
  State<ClusterLyricsSettingsTab> createState() =>
      _ClusterLyricsSettingsTabState();
}

class _ClusterLyricsSettingsTabState extends State<ClusterLyricsSettingsTab> {
  List<ClusterDisplay> _displays = const [];
  ClusterCastStatus _status = ClusterCastStatus.unknown;
  bool _loading = true;
  Timer? _poll;

  /// Live position while a drag is in flight; persisted when the finger lifts.
  double? _dragX;
  double? _dragY;

  @override
  void initState() {
    super.initState();
    _load();
    // The cast service changes state on its own: it attaches after the reply to an Apply,
    // backs off and retries when a display is refused, and the lyric line count moves as the
    // track plays. Without polling, the page would keep showing whatever the last reply said —
    // which is how "已关闭" once sat next to a switch that was clearly on.
    _poll = Timer.periodic(const Duration(seconds: 2), (_) => _refreshStatus());
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _refreshStatus() async {
    if (!mounted) return;
    final status = await widget.client.status();
    if (!mounted) return;
    setState(() => _status = status);
  }

  Future<void> _load() async {
    final displays = await widget.client.displays();
    final status = await widget.client.status();
    if (!mounted) return;
    setState(() {
      _displays = displays;
      _status = status;
      _loading = false;
    });
  }

  /// The display the saved identity still points at. Names survive a reboot, ids do not,
  /// which is why the pair is kept and the name is what re-finds the panel.
  ClusterDisplay? get _selected {
    for (final display in _displays) {
      if (display.id == _status.displayId) return display;
    }
    for (final display in _displays) {
      if (display.name.isNotEmpty && display.name == _status.displayName) {
        return display;
      }
    }
    return null;
  }

  Future<void> _apply({
    ClusterDisplay? display,
    bool? enabled,
    double? fontSp,
    bool? solidBackground,
    double? xRatio,
    double? yRatio,
    double? widthRatio,
    int? rows,
    int? accent,
    String? style,
  }) async {
    final turnOn = enabled ?? (display != null ? true : _status.enabled);
    final target = display ?? (turnOn ? (_selected ?? _firstSecondary) : null);
    final next = await widget.client.apply(
      display: target,
      fontSp: fontSp ?? _status.fontSp,
      solidBackground: solidBackground ?? _status.solidBackground,
      xRatio: xRatio ?? _dragX ?? _status.xRatio,
      yRatio: yRatio ?? _dragY ?? _status.yRatio,
      widthRatio: widthRatio ?? _status.widthRatio,
      rows: rows ?? _status.rows,
      accent: accent ?? _status.accent,
      style: style ?? _status.style,
    );
    if (!mounted) return;
    setState(() {
      _status = next;
      _dragX = null;
      _dragY = null;
    });
    // The report is the only place a refusal by the system shows up, so a failure also
    // re-reads the display list: a cluster that slept and woke on a new id re-resolves.
    if (display != null && !next.enabled) _load();
  }

  /// The display a bare "turn it on" lands on.
  ///
  /// A presentation display is what the unit itself calls a secondary output, so that is the
  /// only safe automatic choice. Falling back to "any non-zero id" picked up this launcher's own
  /// virtual navigation display on the test unit, which is a screen the user is already looking
  /// at — the lyrics then appear on the map instead of the cluster. Display 0 is the honest
  /// fallback: at least it is a screen the user can see and judge.
  ClusterDisplay? get _firstSecondary {
    for (final display in _displays) {
      if (display.presentation) return display;
    }
    for (final display in _displays) {
      if (display.id == 0) return display;
    }
    for (final display in _displays) {
      if (display.id > 0) return display;
    }
    return null;
  }

  void _drag(double xRatio, double yRatio) {
    setState(() {
      _dragX = xRatio;
      _dragY = yRatio;
    });
  }

  Future<void> _commitDrag() async {
    if (_dragX == null && _dragY == null) return;
    await _apply(xRatio: _dragX, yRatio: _dragY);
  }

  @override
  Widget build(BuildContext context) {
    final s = SurfaceStyle.of(context);
    final x = _dragX ?? _status.xRatio;
    final y = _dragY ?? _status.yRatio;
    return SingleChildScrollView(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SettingBlock(
          title: '歌词投到仪表盘',
          note: _status.enabled ? '已开启' : '未开启',
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                DesignSwitchTile(
                  key: const ValueKey('cluster-lyrics-switch'),
                  contentPadding: EdgeInsets.zero,
                  title: const Text('在当前选择的车机屏幕上显示歌词'),
                  subtitle: const Text(
                      '只叠加歌词窗口，不接管那个屏幕的触摸，也不修改原车机的仪表界面'),
                  value: _status.enabled,
                  onChanged: _loading
                      ? null
                      : (value) async {
                          if (value) {
                            final target = _selected ?? _firstSecondary;
                            if (target == null) return;
                            await _apply(display: target, enabled: true);
                          } else {
                            await _apply(enabled: false);
                          }
                        },
                ),
                SizedBox(height: Design.px(16)),
                Text(_status.report.isEmpty ? '尚未尝试投射' : _status.report,
                    style: TextStyle(
                        fontSize: Design.px(17),
                        color: _status.enabled ? s.accent : s.muted)),
                SizedBox(height: Design.px(8)),
                Text(_status.lyricSummary,
                    key: const ValueKey('cluster-lyric-summary'),
                    style: TextStyle(
                        fontSize: Design.px(17),
                        color: _status.lyricLines > 0 ? s.accent : s.muted)),
              ]),
        ),
        SizedBox(height: Design.px(18)),
        SettingBlock(
          title: '位置与大小',
          note: '${(x * 100).round()}% · ${(y * 100).round()}% · '
              '宽 ${(ClusterLayout.widthRatio(_status.widthRatio) * 100).round()}%',
          trailing: TextButton(
            key: const ValueKey('cluster-position-reset'),
            onPressed: _loading
                ? null
                : () => _apply(
                      xRatio: ClusterLayout.defaultX,
                      yRatio: ClusterLayout.defaultY,
                      widthRatio: ClusterLayout.defaultWidth,
                    ),
            child: const Text('回到中间'),
          ),
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _CastPreview(
                  display: _selected,
                  status: _status,
                  xRatio: x,
                  yRatio: y,
                  onDrag: _loading || !_status.enabled ? null : _drag,
                  onCommit: _loading || !_status.enabled ? null : _commitDrag,
                ),
                SizedBox(height: Design.px(12)),
                Text(
                  _status.enabled
                      ? '按住歌词块拖到想放的位置，松手即生效；百分比随屏幕尺寸等比生效，换分辨率也不会跑偏。'
                      : '先打开上面的开关，再拖动预览里的歌词块。',
                  style: TextStyle(fontSize: Design.px(17), color: s.muted, height: 1.4),
                ),
                SizedBox(height: Design.px(14)),
                _LabelRow(label: '可见行数', value: _status.rows),
                Row(children: [
                  for (final count in const [1, 2, 3])
                    Padding(
                      padding: EdgeInsets.only(right: Design.px(12)),
                      child: OutlinedButton(
                        key: ValueKey('cluster-rows-$count'),
                        style: s.selectionStyle(_status.rows == count),
                        onPressed: () => _apply(rows: count),
                        child: Text('$count 行'),
                      ),
                    ),
                  const Spacer(),
                ]),
                SizedBox(height: Design.px(10)),
                _LabelRow(
                    label: '宽度',
                    value:
                        (ClusterLayout.widthRatio(_status.widthRatio) * 100).round()),
                Row(children: [
                  for (final ratio in const [0.5, 0.7, 0.86, 0.94, 1.0])
                    Padding(
                      padding: EdgeInsets.only(right: Design.px(12)),
                      child: OutlinedButton(
                        key: ValueKey('cluster-width-${(ratio * 100).round()}'),
                        style: s.selectionStyle(
                            (ClusterLayout.widthRatio(_status.widthRatio) - ratio)
                                    .abs() <
                                0.01),
                        onPressed: () => _apply(widthRatio: ratio),
                        child: Text('${(ratio * 100).round()}%'),
                      ),
                    ),
                  const Spacer(),
                ]),
              ]),
        ),
        SizedBox(height: Design.px(18)),
        SettingBlock(
          title: '目标屏幕',
          note: _loading ? '读取中' : '${_displays.length} 个',
          trailing: TextButton(
            onPressed: _loading ? null : _load,
            child: const Text('重新扫描'),
          ),
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (!_loading && _displays.isEmpty)
                  Text('这台车机没有向应用暴露任何副屏，歌词无法投出。',
                      style: TextStyle(
                          fontSize: Design.px(18), color: s.muted))
                else
                  Wrap(
                    spacing: Design.px(14),
                    runSpacing: Design.px(14),
                    children: [
                      for (final display in _displays)
                        OutlinedButton(
                          key: ValueKey('cluster-display-${display.id}'),
                          style: s.selectionStyle(_selected?.id == display.id),
                          onPressed: _loading
                              ? null
                              : () => _apply(
                                  display: _status.enabled &&
                                          _selected?.id == display.id
                                      ? null
                                      : display),
                          child: Padding(
                            padding: EdgeInsets.symmetric(
                                horizontal: Design.px(18),
                                vertical: Design.px(14)),
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(display.label,
                                      style: TextStyle(
                                          fontSize: Design.px(19),
                                          fontWeight: FontWeight.w500)),
                                  SizedBox(height: Design.px(6)),
                                  Text(
                                      display.presentation
                                          ? '系统标记为副屏'
                                          : '系统未标记为副屏',
                                      style: TextStyle(
                                          fontSize: Design.px(16),
                                          color: s.muted)),
                                ]),
                          ),
                        )
                    ],
                  ),
                SizedBox(height: Design.px(14)),
                Text('选择后立刻生效，并会被记住；重启后按屏幕名称重新匹配。',
                    style:
                        TextStyle(fontSize: Design.px(17), color: s.muted)),
              ]),
        ),
        SizedBox(height: Design.px(18)),
        SettingBlock(
          title: '字形与配色',
          note: '${_status.fontSp.round()} sp',
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(children: [
                  for (final step in const [24.0, 30.0, 36.0, 44.0, 54.0])
                    Padding(
                      padding: EdgeInsets.only(right: Design.px(12)),
                      child: OutlinedButton(
                        key: ValueKey('cluster-font-${step.round()}'),
                        style: s.selectionStyle(_status.fontSp == step),
                        onPressed: () => _apply(fontSp: step),
                        child: Text('${step.round()}'),
                      ),
                    ),
                  const Spacer(),
                ]),
                SizedBox(height: Design.px(14)),
                _LabelRow(label: '高亮色', value: null),
                Wrap(spacing: Design.px(12), runSpacing: Design.px(12), children: [
                  for (final swatch in _accents)
                    _AccentSwatch(
                      key: ValueKey('cluster-accent-${swatch.toRadixString(16)}'),
                      color: Color(swatch),
                      selected: _status.accent == swatch,
                      onTap: () => _apply(accent: swatch),
                    ),
                ]),
                SizedBox(height: Design.px(14)),
                _LabelRow(label: '样式', value: null),
                Row(children: [
                  for (final option in _styles)
                    Padding(
                      padding: EdgeInsets.only(right: Design.px(12)),
                      child: OutlinedButton(
                        key: ValueKey('cluster-style-${option.$1}'),
                        style: s.selectionStyle(_status.style == option.$1),
                        onPressed: () => _apply(style: option.$1),
                        child: Text(option.$2),
                      ),
                    ),
                  const Spacer(),
                ]),
                SizedBox(height: Design.px(10)),
                DesignSwitchTile(
                  key: const ValueKey('cluster-background-switch'),
                  contentPadding: EdgeInsets.zero,
                  title: const Text('文字下方加深色底板'),
                  subtitle: const Text('关闭后文字直接压在原车机画面上，适合纯黑仪表底'),
                  value: _status.solidBackground,
                  onChanged: (value) => _apply(solidBackground: value),
                ),
              ]),
        ),
        SizedBox(height: Design.px(18)),
        SettingBlock(
          title: '实现方式',
          note: '说明',
          child: Text(
            '投屏窗口由系统进程内的窗口管理器绘制在目标屏幕自己的窗口上，'
            '使用应用悬浮窗类型，不获取焦点、不拦截触摸。位置按屏幕百分比保存，'
            '与服务端的排版公式一致，因此预览里拖到哪里，仪表上就出现在哪里。'
            '歌词数据由投射服务自己按固定节奏向媒体适配器取，不依赖桌面是否在前台，'
            '所以打开音乐应用全屏时歌词照样走。',
            style: TextStyle(fontSize: Design.px(18), color: s.muted, height: 1.5),
          ),
        ),
      ]),
    );
  }
}

const List<int> _accents = [
  0xFF7FE3D4,
  0xFF8CC8FF,
  0xFFFFC46B,
  0xFFFF8FA3,
  0xFFB6A8FF,
  0xFFFFFFFF,
];

const List<(String, String)> _styles = [
  ('pill', '胶囊底板'),
  ('plain', '纯文字'),
  ('glow', '发光'),
];

class _LabelRow extends StatelessWidget {
  const _LabelRow({required this.label, required this.value});

  final String label;
  final int? value;

  @override
  Widget build(BuildContext context) {
    final s = SurfaceStyle.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: Design.px(8)),
      child: Row(children: [
        Text(label, style: TextStyle(fontSize: Design.px(18), color: s.muted)),
        if (value != null) ...[
          const Spacer(),
          Text('$value', style: TextStyle(fontSize: Design.px(18), color: s.muted)),
        ],
      ]),
    );
  }
}

class _AccentSwatch extends StatelessWidget {
  const _AccentSwatch({
    super.key,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: Design.px(46),
        height: Design.px(46),
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(
            width: Design.px(selected ? 4 : 1),
            color: selected ? Colors.white : Colors.white24,
          ),
          boxShadow: [
            if (selected)
              BoxShadow(color: color.withValues(alpha: 0.55), blurRadius: Design.px(18)),
          ],
        ),
      ),
    );
  }
}

/// A mock cluster screen with a draggable lyric block.
///
/// The block is sized by the same formula the native panel uses ([ClusterLayout.previewBlock]),
/// including the target display's density, so 24 sp really is smaller than 44 sp here and the
/// row count changes the block height the way it will on the cluster.
class _CastPreview extends StatefulWidget {
  const _CastPreview({
    required this.display,
    required this.status,
    required this.xRatio,
    required this.yRatio,
    required this.onDrag,
    required this.onCommit,
  });

  final ClusterDisplay? display;
  final ClusterCastStatus status;
  final double xRatio;
  final double yRatio;
  final void Function(double xRatio, double yRatio)? onDrag;
  final Future<void> Function()? onCommit;

  @override
  State<_CastPreview> createState() => _CastPreviewState();
}

class _CastPreviewState extends State<_CastPreview> {
  bool _dragging = false;
  Offset? _start;
  bool _moved = false;

  /// Finger travel before the panel follows. A tap on the mock screen must not move the
  /// lyrics: this page is also poked at while the car is standing still, and a 4 px slip is
  /// not an instruction. 12 logical pixels is above touch slop but below a deliberate drag.
  static const double _deadZone = 12;

  ClusterDisplay? get display => widget.display;
  ClusterCastStatus get status => widget.status;
  double get xRatio => widget.xRatio;
  double get yRatio => widget.yRatio;
  void Function(double xRatio, double yRatio)? get onDrag => widget.onDrag;
  Future<void> Function()? get onCommit => widget.onCommit;

  int get _displayWidth => (display?.width ?? 0) > 0 ? display!.width : 1920;
  int get _displayHeight => (display?.height ?? 0) > 0 ? display!.height : 720;
  int get _density => (display?.densityDpi ?? 0) > 0 ? display!.densityDpi : 240;

  @override
  Widget build(BuildContext context) {
    final s = SurfaceStyle.of(context);
    final aspect = _displayWidth / _displayHeight;
    final rows = ClusterLayout.rows(status.rows);
    final accent = Color(status.accent);
    return LayoutBuilder(builder: (context, constraints) {
      // The mock screen is capped in height: a 1229×880 display at full card width would be
      // taller than the window, and a preview whose bottom half is off-screen cannot be used
      // to place anything. The aspect ratio is kept so the proportions still read true.
      var boxWidth = constraints.maxWidth;
      var boxHeight = aspect <= 0 ? boxWidth * 9 / 16 : boxWidth / aspect;
      final cap = Design.px(340);
      if (boxHeight > cap) {
        boxHeight = cap;
        boxWidth = cap * aspect;
      }
      return Center(
        child: SizedBox(
          width: boxWidth,
          height: boxHeight,
          child: _previewSurface(context, s, Size(boxWidth, boxHeight), rows, accent),
        ),
      );
    });
  }

  Widget _previewSurface(
      BuildContext context, SurfaceStyle s, Size box, int rows, Color accent) {
    final block = ClusterLayout.previewBlock(
      previewWidth: box.width,
      previewHeight: box.height,
      displayWidth: _displayWidth,
      displayHeight: _displayHeight,
      densityDpi: _density,
      fontSp: status.fontSp,
      rowsValue: rows,
      widthRatioValue: status.widthRatio,
      xRatio: xRatio,
      yRatio: yRatio,
    );
    // Faithful height, but never smaller than 8 px on screen: a 24 sp line on a 1229 px wide
    // display is unreadable in a 470 px wide mock, and an unreadable preview cannot be used to
    // judge which row is which.
    final fontSize = (block.height / rows / ClusterLayout.rowSpacing)
        .clamp(8.0, 64.0)
        .toDouble();
    final canDrag = onDrag != null;
    return GestureDetector(
      key: const ValueKey('cluster-preview'),
      behavior: HitTestBehavior.opaque,
      onPanStart: canDrag
          ? (details) {
              _start = details.localPosition;
              _moved = false;
              setState(() => _dragging = true);
            }
          : null,
      onPanUpdate: canDrag
          ? (details) {
              final start = _start;
              if (start != null &&
                  !_moved &&
                  (details.localPosition - start).distance < _deadZone) {
                return;
              }
              _moved = true;
              _report(details.localPosition, box, block);
            }
          : null,
      onPanEnd: canDrag
          ? (_) {
              setState(() => _dragging = false);
              final moved = _moved;
              _start = null;
              _moved = false;
              if (moved) onCommit?.call();
            }
          : null,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(Design.px(18)),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF101418), Color(0xFF1B2228)],
          ),
          border: Border.all(color: Colors.white10),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(Design.px(18)),
          child: Stack(children: [
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                height: box.height * 0.22,
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0x00000000), Color(0x33000000)],
                  ),
                ),
              ),
            ),
            Positioned(
              left: Design.px(16),
              top: Design.px(12),
              child: Text(
                '${_displayWidth}×$_displayHeight · ${display?.name ?? '预览'}',
                style: TextStyle(fontSize: Design.px(14), color: Colors.white38),
              ),
            ),
            Positioned(
              left: block.left,
              top: block.top,
              width: block.width,
              height: block.height,
              child: _PreviewBlock(
                rows: rows,
                fontSize: fontSize,
                accent: accent,
                solid: status.solidBackground,
                style: status.style,
                dragging: _dragging,
              ),
            ),
            if (canDrag)
              Positioned(
                right: Design.px(14),
                bottom: Design.px(12),
                child: Icon(Icons.open_with, size: Design.px(22), color: s.muted),
              ),
          ]),
        ),
      ),
    );
  }

  /// Turn the finger position into ratios, keeping the whole block on screen.
  void _report(Offset local, Size box, ({double left, double top, double width, double height}) block) {
    final halfW = block.width / 2 / box.width;
    final halfH = block.height / 2 / box.height;
    final x = (local.dx / box.width).clamp(halfW, 1 - halfW);
    final y = (local.dy / box.height).clamp(halfH, 1 - halfH);
    onDrag?.call(x, y);
  }
}

class _PreviewBlock extends StatelessWidget {
  const _PreviewBlock({
    required this.rows,
    required this.fontSize,
    required this.accent,
    required this.solid,
    required this.style,
    required this.dragging,
  });

  final int rows;
  final double fontSize;
  final Color accent;
  final bool solid;
  final String style;
  final bool dragging;

  @override
  Widget build(BuildContext context) {
    final plain = style == 'plain';
    final glow = style == 'glow';
    final dim = Color.lerp(accent, Colors.white, 0.35)!.withValues(alpha: 0.45);
    final lines = rows >= 3
        ? ['上一句歌词', '此刻正在唱的这句', '下一句歌词']
        : rows == 2
            ? ['此刻正在唱的这句', '下一句歌词']
            : ['此刻正在唱的这句'];
    return Container(
      key: const ValueKey('cluster-preview-block'),
      // No vertical padding: the native panel's height is exactly rows × pitch, and the
      // preview has to be that height too or the drag clamp would disagree with reality.
      padding: EdgeInsets.symmetric(horizontal: fontSize * 0.5),
      decoration: BoxDecoration(
        color: plain || !solid
            ? Colors.transparent
            : Colors.black.withValues(alpha: glow ? 0.38 : 0.7),
        borderRadius: BorderRadius.circular(fontSize * 0.7),
        border: Border.all(
          // The ring marks "this is the thing you drag"; it only brightens while dragging so
          // a parked screen does not look like a form with a focused field.
          color: accent.withValues(alpha: dragging ? 0.95 : 0.35),
          width: dragging ? 1.6 : 1,
        ),
        boxShadow: [
          if (glow)
            BoxShadow(
                color: accent.withValues(alpha: 0.35),
                blurRadius: fontSize * 0.9,
                spreadRadius: fontSize * 0.05),
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < lines.length; i++)
            Text(
              lines[i],
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: i == (rows >= 3 ? 1 : 0) ? fontSize : fontSize * 0.74,
                height: ClusterLayout.rowSpacing,
                fontWeight: FontWeight.w500,
                color: i == (rows >= 3 ? 1 : 0) ? accent : dim,
                shadows: [
                  if (!plain)
                    Shadow(
                        color: accent.withValues(alpha: glow ? 0.5 : 0.22),
                        blurRadius: fontSize * 0.5),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
