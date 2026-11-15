import 'dart:async';

import 'package:flutter/material.dart';

import '../model/cluster_layout.dart';
import '../platform/cluster_lyrics.dart';
import '../theme/design_tokens.dart';
import '../theme/launcher_type.dart';
import '../theme/launcher_theme.dart';
import 'choice_button.dart';
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

  /// 本机预览的注入点。
  ///
  /// Windows 上没有安卓的副屏投射服务，`clusterLyrics*` 三条通道无人应答，
  /// 整页就只剩一句「没有暴露任何副屏」，版式无从检查。`preview/main_preview.dart`
  /// 在 `UNI_PREVIEW_CLUSTER=1` 时塞一个假客户端进来；正式运行恒为 null。
  static ClusterLyrics? previewClient;

  @override
  State<ClusterLyricsSettingsTab> createState() =>
      _ClusterLyricsSettingsTabState();
}

class _ClusterLyricsSettingsTabState extends State<ClusterLyricsSettingsTab> {
  List<ClusterDisplay> _displays = const [];
  ClusterCastStatus _status = ClusterCastStatus.unknown;
  bool _loading = true;
  Timer? _poll;

  ClusterLyrics get _client =>
      ClusterLyricsSettingsTab.previewClient ?? widget.client;

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
    final status = await _client.status();
    if (!mounted) return;
    setState(() => _status = status);
  }

  Future<void> _load() async {
    final displays = await _client.displays();
    final status = await _client.status();
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
    String? motion,
  }) async {
    final turnOn = enabled ?? (display != null ? true : _status.enabled);
    final target = display ?? (turnOn ? (_selected ?? _firstSecondary) : null);
    // 先本地生效再问原生。
    //
    // 原生投射服务连不上时（Windows 预览、或这台车机没装投射桥），apply 会退回
    // unknown——那不是「被拒绝」，只是「问不到」。拿它覆盖界面上的值，用户点了
    // 样式/行数/宽度全都停在旧值，看起来像「选中态切换不了」。
    final optimistic = _status.copyWith(
      enabled: display != null || _status.enabled,
      displayId: target?.id ?? _status.displayId,
      displayName: target?.name ?? _status.displayName,
      fontSp: fontSp ?? _status.fontSp,
      solidBackground: solidBackground ?? _status.solidBackground,
      xRatio: xRatio ?? _dragX ?? _status.xRatio,
      yRatio: yRatio ?? _dragY ?? _status.yRatio,
      widthRatio: widthRatio ?? _status.widthRatio,
      rows: rows ?? _status.rows,
      accent: accent ?? _status.accent,
      style: style ?? _status.style,
      motion: motion ?? _status.motion,
    );
    if (optimistic.enabled != _status.enabled ||
        optimistic.displayId != _status.displayId ||
        optimistic.fontSp != _status.fontSp ||
        optimistic.solidBackground != _status.solidBackground ||
        optimistic.xRatio != _status.xRatio ||
        optimistic.yRatio != _status.yRatio ||
        optimistic.widthRatio != _status.widthRatio ||
        optimistic.rows != _status.rows ||
        optimistic.accent != _status.accent ||
        optimistic.style != _status.style ||
        optimistic.motion != _status.motion) {
      setState(() {
        _status = optimistic;
        _dragX = null;
        _dragY = null;
      });
    }
    final next = await _client.apply(
      display: target,
      fontSp: fontSp ?? _status.fontSp,
      solidBackground: solidBackground ?? _status.solidBackground,
      xRatio: xRatio ?? _dragX ?? _status.xRatio,
      yRatio: yRatio ?? _dragY ?? _status.yRatio,
      widthRatio: widthRatio ?? _status.widthRatio,
      rows: rows ?? _status.rows,
      accent: accent ?? _status.accent,
      style: style ?? _status.style,
      motion: motion ?? _status.motion,
    );
    if (!mounted) return;
    setState(() {
      // 桥不可用时 next 是 unknown：那是「不知道」，不是「原生说了不行」，
      // 保留刚点下去的值，只把原因挂到 report 上显示。
      _status = next.report == ClusterLyrics.bridgeUnavailable
          ? _status.copyWith(report: next.report)
          : next;
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
    // 拖动中的临时值优先：手指还在屏幕上时预览必须跟手，松手才把比例写进原生。
    final x = _dragX ?? _status.xRatio;
    final y = _dragY ?? _status.yRatio;
    // sim f38：左栏四块设置、右栏预览 + 字形，两栏各自滚动（1 : 1.08）。
    //
    // 设计稿的块间距 12 是按「内容刚好占满一屏」画的，实机上底部有多媒体
    // 底栏占位，可视高度只有 517 画布——原样搬过来，左栏正好切在「实现方式」
    // 的第三行上、右栏切在「高亮色」下面。块间距与内边距各让几像素后两栏
    // 都能一次放完，见 `cluster settings fit one screen without scrolling`。
    final leftColumn = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _castBlock(s),
        SizedBox(height: Design.dz(6)),
        _placeBlock(s, x, y),
        SizedBox(height: Design.dz(6)),
        _displayBlock(s),
        SizedBox(height: Design.dz(6)),
        _howBlock(s),
      ],
    );
    final rightColumn = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _previewBlock(s, x, y),
        SizedBox(height: Design.dz(6)),
        _typeBlock(s),
      ],
    );
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          flex: 25,
          child: SingleChildScrollView(
            key: const PageStorageKey('cluster-settings-left'),
            child: leftColumn,
          ),
        ),
        SizedBox(width: Design.dz(12)),
        Expanded(
          flex: 27,
          child: SingleChildScrollView(
            key: const PageStorageKey('cluster-settings-right'),
            child: rightColumn,
          ),
        ),
      ],
    );
  }

  /// f38 的块内边距：设计稿 12/14 会把这页顶到两屏，收到 8/9 后两栏都能一次放完。
  static final EdgeInsets _pad = EdgeInsets.fromLTRB(
      Design.dz(17), Design.dz(8), Design.dz(17), Design.dz(9));

  /// 小标签：设计稿 `.lb`，13.5 / 40% 墨色。
  Widget _label(SurfaceStyle s, String text) => Padding(
      padding: EdgeInsets.only(bottom: Design.dz(4)),
      child: Text(text,
          style: TextStyle(
              fontSize: Design.dz(15),
              color: s.text.withValues(alpha: .4))));

  /// 开关放在标题行右侧（设计稿 `.sw` 的位置），不用整行 SwitchTile。
  Widget _headerSwitch(String key, bool value, ValueChanged<bool>? onChanged) =>
      DesignSwitch(
          key: ValueKey(key), value: value, onChanged: onChanged);

  Widget _castBlock(SurfaceStyle s) => SettingBlock(
        title: '歌词投到仪表盘',
        dense: true,
        padding: _pad,
        note: _status.enabled ? '已开启' : '未开启',
        trailing: _headerSwitch(
            'cluster-lyrics-switch',
            _status.enabled,
            _loading
                ? null
                : (value) async {
                    if (value) {
                      final target = _selected ?? _firstSecondary;
                      if (target == null) return;
                      await _apply(display: target, enabled: true);
                    } else {
                      await _apply(enabled: false);
                    }
                  }),
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(children: [
                Container(
                    width: Design.dz(6),
                    height: Design.dz(6),
                    decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _status.enabled ? s.accent : s.disabled)),
                SizedBox(width: Design.dz(8)),
                Expanded(
                    child: Text(
                        _status.report.isEmpty ? '尚未尝试投射' : _status.report,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: Design.dz(12.5),
                            color: _status.enabled ? s.accent : s.muted))),
                Text('窗口随屏重建',
                    style:
                        TextStyle(fontSize: Design.dz(11.5), color: s.muted))
              ]),
              SizedBox(height: Design.dz(6)),
              Text(
                  '只叠加歌词窗口，不接管那个屏幕的触摸，也不修改原车机的仪表界面',
                  style: TextStyle(
                      fontSize: Design.dz(11.5), color: s.muted, height: LauncherType.lineLoose)),
              SizedBox(height: Design.dz(6)),
              Text(_status.lyricSummary,
                  key: const ValueKey('cluster-lyric-summary'),
                  style: TextStyle(
                      fontSize: Design.dz(11.5),
                      color: _status.lyricLines > 0 ? s.accent : s.muted)),
            ]),
      );

  Widget _placeBlock(SurfaceStyle s, double x, double y) => SettingBlock(
        title: '位置与大小',
        dense: true,
        padding: _pad,
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
            child: const Text('回到中间')),
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _label(s, '可见行数'),
              Row(children: [
                for (final (index, count) in const [1, 2, 3].indexed)
                  Expanded(
                      child: Padding(
                          padding: EdgeInsets.only(
                              right: index == 2 ? 0 : Design.dz(9)),
                          child: ChoiceButton(
                              key: ValueKey('cluster-rows-$count'),
                              kind: ChoiceKind.filled,
                              height: 40,
                              radius: 11,
                              selected: _status.rows == count,
                              onPressed: () => _apply(rows: count),
                              child: Text('$count 行',
                                  style: TextStyle(
                                      fontSize: Design.dz(13.5))))))
              ]),
              SizedBox(height: Design.dz(9)),
              _label(s, '宽度'),
              Row(children: [
                for (final (index, ratio)
                    in const [0.5, 0.7, 0.86, 0.94, 1.0].indexed)
                  Expanded(
                      child: Padding(
                          padding: EdgeInsets.only(
                              right: index == 4 ? 0 : Design.dz(8)),
                          child: ChoiceButton(
                              key: ValueKey(
                                  'cluster-width-${(ratio * 100).round()}'),
                              kind: ChoiceKind.filled,
                              height: 38,
                              radius: 11,
                              selected: (ClusterLayout.widthRatio(
                                              _status.widthRatio) -
                                          ratio)
                                      .abs() <
                                  0.01,
                              onPressed: () => _apply(widthRatio: ratio),
                              child: Text('${(ratio * 100).round()}%',
                                  style: TextStyle(
                                      fontSize: Design.dz(13.5))))))
              ]),
            ]),
      );

  Widget _displayBlock(SurfaceStyle s) => SettingBlock(
        title: '目标屏幕',
        dense: true,
        padding: _pad,
        note: _loading ? '读取中' : '${_displays.length} 个',
        trailing: TextButton(
            onPressed: _loading ? null : _load,
            child: const Text('重新扫描')),
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (!_loading && _displays.isEmpty)
                Text('这台车机没有向应用暴露任何副屏，歌词无法投出。',
                    style: TextStyle(fontSize: Design.dz(13), color: s.muted))
              else
                Row(children: [
                  for (final (index, display) in _displays.indexed)
                    Expanded(
                        child: Padding(
                            padding: EdgeInsets.only(
                                right: index == _displays.length - 1
                                    ? 0
                                    : Design.dz(9)),
                            child: SizedBox(
                                height: Design.dz(44),
                                child: ChoiceButton(
                                    key: ValueKey('cluster-display-${display.id}'),
                                    kind: ChoiceKind.filled,
                                    height: 44,
                                    radius: 11,
                                    onPressed: _loading
                                        ? null
                                        : () => _apply(
                                            display: _status.enabled &&
                                                    _selected?.id == display.id
                                                ? null
                                                : display),
                                    selected: _selected?.id == display.id,
                                    child: Column(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          Text(display.name,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                  fontSize: Design.dz(14))),
                                          SizedBox(height: Design.dz(2)),
                                          Text(
                                              display.width > 0
                                                  ? '${display.width}×${display.height}'
                                                  : '分辨率未知',
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                  fontSize: Design.dz(10.5),
                                                  fontWeight: FontWeight.w400))
                                        ])))))
                ]),
              SizedBox(height: Design.dz(9)),
              // 把「现在（或下次打开时）会投到哪块屏」的原始身份摊开：
              // 出问题时这是唯一能对得上的线索，也不至于让用户猜默认目标是哪块。
              Text(
                  (_selected ?? _firstSecondary) == null
                      ? '选择后立刻生效，并会被记住；重启后按屏幕名称重新匹配。'
                      : '${(_selected ?? _firstSecondary)!.label} · '
                          '${(_selected ?? _firstSecondary)!.presentation ? '系统标记为副屏' : '系统未标记为副屏'}',
                  style: TextStyle(
                      fontSize: Design.dz(11.5), color: s.muted, height: LauncherType.lineLoose)),
            ]),
      );

  Widget _howBlock(SurfaceStyle s) => SettingBlock(
        title: '实现方式',
        dense: true,
        padding: _pad,
        child: Text(
          '系统悬浮窗直接画在目标屏上，不抢焦点、不拦截触摸；'
          '位置按屏幕百分比保存，预览即仪表。'
          '歌词由投射服务自行获取，桌面不在前台也照常滚动。',
          style: TextStyle(
              fontSize: Design.dz(11.5), color: s.muted, height: LauncherType.lineLoose),
        ),
      );

  Widget _previewBlock(SurfaceStyle s, double x, double y) => SettingBlock(
        title: '预览 · ${_selected?.name ?? '中控副屏'}',
        // 原来块底还有一行「按住歌词块拖到想放的位置……」：一屏放不下时，
        // 那 20 逻辑像素正好把「字形与配色」顶出屏幕。指引并没有丢，收进
        // 标题右侧这行副标题里——未开启时先提示去开开关。
        note: _status.enabled
            ? 'x ${(x * 100).round()}% · y ${(y * 100).round()}% · 按住歌词块拖动，松手生效'
            : '先打开上面的开关，再拖动预览里的歌词块',
        dense: true,
        padding: _pad,
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 高度交给 [_CastPreview] 自己按目标屏的宽高比算：固定 300 在一台
              // 1920×720 的副屏上会上下各留 35 画布的空白，而那一截正是整页
              // 放不下的部分。
              _CastPreview(
                display: _selected,
                status: _status,
                xRatio: x,
                yRatio: y,
                onDrag: _loading || !_status.enabled ? null : _drag,
                onCommit: _loading || !_status.enabled ? null : _commitDrag,
              ),
            ]),
      );

  /// 字号按设计稿做成「− 44 ＋」步进，而不是五颗按钮：
  /// 档位是给手指用的，不是给眼睛数的。
  static const _fontSteps = [24.0, 30.0, 36.0, 44.0, 54.0];

  int get _fontIndex {
    var best = 0;
    for (var i = 1; i < _fontSteps.length; i++) {
      if ((_fontSteps[i] - _status.fontSp).abs() <
          (_fontSteps[best] - _status.fontSp).abs()) best = i;
    }
    return best;
  }

  Widget _stepButton(IconData icon, String key, VoidCallback? onTap) =>
      SizedBox(
          width: Design.dz(46),
          height: Design.dz(34),
          child: OutlinedButton(
              key: ValueKey(key),
              style: OutlinedButton.styleFrom(
                  padding: EdgeInsets.zero,
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(Design.dz(12)))),
              onPressed: onTap,
              child: Icon(icon, size: Design.dz(16))));

  /// 紧凑开关行。
  ///
  /// `DesignSwitchTile` 走的是 ListTile：title + subtitle 两行在 46 号开关旁边
  /// 会撑到 71 画布，这页两个就是 142——正好把「样式」整行挤出屏幕。这里自绘
  /// 一行 43 画布，字号与设计稿一致，只是不再吃 ListTile 的默认行高。
  Widget _switchRow(SurfaceStyle s, String key, String title, String subtitle,
          bool value, ValueChanged<bool>? onChanged) =>
      InkWell(
          key: ValueKey(key),
          borderRadius: BorderRadius.circular(Design.dz(10)),
          onTap: onChanged == null ? null : () => onChanged(!value),
          child: Padding(
              padding: EdgeInsets.symmetric(vertical: Design.dz(5)),
              child: Row(children: [
                Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Text(title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: Design.dz(13.5),
                              color: s.text
                                  .withValues(alpha: onChanged == null ? .5 : .9))),
                      SizedBox(height: Design.dz(2)),
                      Text(subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: Design.dz(11), color: s.muted)),
                    ])),
                SizedBox(width: Design.dz(12)),
                DesignSwitch(value: value, onChanged: onChanged),
              ])));

  /// 动效档位行：沿用 [_switchRow] 的 43 画布行高，尾部换成两枚档位按钮。
  ///
  /// 这一行的副标题跟着档位变：关着说「只在换行重绘一次」，开着说「上一行向上
  /// 淡出」。两段说明合成一行，是因为这页两栏都只剩几画布的余量，再多一行说明
  /// 就会把「样式」挤出屏幕（design_contract 盯着这件事）。
  Widget _motionRow(SurfaceStyle s) {
    final enabled = ClusterLayout.motionEnabled(_status.motion);
    return Padding(
        padding: EdgeInsets.symmetric(vertical: Design.dz(5)),
        child: Row(children: [
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text('歌词动效',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: Design.dz(13.5),
                        color: s.text.withValues(alpha: .9))),
                SizedBox(height: Design.dz(2)),
                Text(
                    enabled
                        ? '切行时上一行向上淡出、新行从下方浮起，唱到的字跟着高亮推进'
                        : '默认关闭：只在换行的那一刻重绘一次，两句之间完全不占帧，跑地图时最省',
                    key: const ValueKey('cluster-motion-note'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: Design.dz(11), color: s.muted)),
              ])),
          SizedBox(width: Design.dz(10)),
          for (final (index, option) in const [
            (ClusterLayout.motionNone, '无'),
            (ClusterLayout.motionWords, '逐次+动效'),
          ].indexed)
            Padding(
                padding: EdgeInsets.only(
                    right: index == 1 ? 0 : Design.dz(6)),
                child: ChoiceButton(
                    key: ValueKey('cluster-motion-${option.$1}'),
                    kind: ChoiceKind.filled,
                    height: 28,
                    radius: 9,
                    selected:
                        ClusterLayout.motion(_status.motion) == option.$1,
                    onPressed: () => _apply(motion: option.$1),
                    child: Text(option.$2,
                        style: TextStyle(fontSize: Design.dz(11.5))))),
        ]));
  }

  Widget _typeBlock(SurfaceStyle s) => SettingBlock(
        title: '字形与配色',
        note: '${_status.fontSp.round()} sp',
        dense: true,
        padding: _pad,
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(children: [
                SizedBox(
                    width: Design.dz(78),
                    child: Text('字号',
                        style: TextStyle(
                            fontSize: Design.dz(13.5),
                            color: s.text.withValues(alpha: .5)))),
                _stepButton(Icons.remove, 'cluster-font-down',
                    _loading || _fontIndex == 0
                        ? null
                        : () => _apply(fontSp: _fontSteps[_fontIndex - 1])),
                Expanded(
                    child: Center(
                        child: Text('${_status.fontSp.round()}',
                            style: TextStyle(
                                fontSize: Design.dz(17),
                                fontWeight: FontWeight.w300,
                                color: s.text.withValues(alpha: .9))))),
                _stepButton(Icons.add, 'cluster-font-up',
                    _loading || _fontIndex == _fontSteps.length - 1
                        ? null
                        : () => _apply(fontSp: _fontSteps[_fontIndex + 1])),
              ]),
              SizedBox(height: Design.dz(9)),
              _label(s, '高亮色'),
              Wrap(
                  spacing: Design.dz(9),
                  runSpacing: Design.dz(9),
                  children: [
                    for (final swatch in _accents)
                      _AccentSwatch(
                        key: ValueKey(
                            'cluster-accent-${swatch.toRadixString(16)}'),
                        color: Color(swatch),
                        selected: _status.accent == swatch,
                        onTap: () => _apply(accent: swatch),
                      ),
                  ]),
              SizedBox(height: Design.dz(9)),
              _label(s, '样式'),
              Row(children: [
                for (final (index, option) in _styles.indexed)
                  Expanded(
                      child: Padding(
                          padding: EdgeInsets.only(
                              right: index == _styles.length - 1
                                  ? 0
                                  : Design.dz(9)),
                          child: ChoiceButton(
                              key: ValueKey('cluster-style-${option.$1}'),
                              kind: ChoiceKind.filled,
                              height: 36,
                              radius: 11,
                              selected: _status.style == option.$1,
                              onPressed: () => _apply(style: option.$1),
                              child: Text(option.$2,
                                  style: TextStyle(
                                      fontSize: Design.dz(13.5))))))
              ]),
              SizedBox(height: Design.dz(4)),
              _switchRow(s, 'cluster-background-switch', '文字下方加深色底板',
                  '关闭后文字直接压在原车画面，适合纯黑仪表底',
                  _status.solidBackground,
                  (value) => _apply(solidBackground: value)),
              // 这一行设计稿是开关，但"跟随"没有独立开关：逐字时间轴有没有
              // 完全由音源决定，所以只把结果摊开，不摆一个骗人的开关。
              // 动效档位就落在这一行的尾部：两者是同一件事的两端——关着只在
              // 换行重绘一次，开着逐词推进；这页已经没有第二行说明的高度了。
              _motionRow(s),
            ]),
      );
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
        width: Design.px(40),
        height: Design.px(40),
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
      // 块高必须恒定等于 rows × 行距（与真机拖拽钳制一致），而换系统字体后
      // 每行行盒的向上取整会让总高多出 1~3px，撑出溢出条。
      // 用 LayoutBuilder 取到实际宽度后交给 FittedBox：宽度照旧撑满
      // （stretch + ellipsis 语义不变），高度超限时等比缩 1~2%。
      child: LayoutBuilder(
          builder: (context, box) => FittedBox(
                fit: BoxFit.scaleDown,
                child: SizedBox(
                    width: box.maxWidth,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
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
                              fontSize: i == (rows >= 3 ? 1 : 0)
                                  ? fontSize
                                  : fontSize * 0.74,
                              height: ClusterLayout.rowSpacing,
                              fontWeight: FontWeight.w500,
                              color: i == (rows >= 3 ? 1 : 0) ? accent : dim,
                              shadows: [
                                if (!plain)
                                  Shadow(
                                      color: accent.withValues(
                                          alpha: glow ? 0.5 : 0.22),
                                      blurRadius: fontSize * 0.5),
                              ],
                            ),
                          ),
                      ],
                    )))),
    );
  }
}
