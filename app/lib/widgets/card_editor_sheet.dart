part of 'editable_card.dart';

const _libraryDescriptions = {
  'nav': '原车导航与引导信息',
  'trafficLight': '方向、灯态与倒计时，支持多方向信号',
  'music': '原车媒体与播放信息',
  'weather': '原车城市与天气信息',
  'calendar': '原车日期与日程',
  'member': '原车账号与登录状态',
  'cleanup': '原车清理信息与操作',
  'tpms': '原车四轮胎压信息',
  'body': '四轮胎压与车门、尾门状态',
  'battery': '电量、混动与充电状态',
  'fuel': '\u5269\u4f59\u6cb9\u91cf\u4e0e\u71c3\u6cb9\u7eed\u822a',
  'air': '车内 PM2.5 与独立 AQI 读数',
  'clock': '时间、日期与星期',
  'clockWeather': '时钟与天气组合，可切换四种布局',
  'shortcuts': '自选应用，一键启动',
  'vehicle': '车速、总里程、续航与距保养',
};
const _desktopTypes = {
  'clock',
  'clockWeather',
  'shortcuts',
  'vehicle',
  'trafficLight'
};

/// 卡片库。稿子 `#f16`：1120×694 的弹层，头部只有标题 + X，分组头是
/// 「标签 + 渐隐细线 + 右侧计数」。桌面扩展（稿子 `#f18`）按用户 2026-11-14 的决定
/// **不拆独立弹层**，仍作为这里的第一组下半段，所以列数统一 4 列。
Future<void> showCardLibrary(BuildContext context, LauncherController c) =>
    showLauncherSheet<void>(context,
        title: '添加卡片',
        closeLabel: '关闭卡片库',
        width: Design.dz(1120),
        height: Design.dz(694),
        glowType: 'shortcuts',
        builder: (context) {
      final groups = [
        ('原车卡片', false, '来自原车服务 · 共 ${_libraryCount(false)} 张'),
        ('桌面扩展', true, '系统级卡片 · 共 ${_libraryCount(true)} 张'),
      ];
      return SingleChildScrollView(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        for (var i = 0; i < groups.length; i++) ...[
          if (i > 0) SizedBox(height: Design.dz(26)),
          _LibraryGroupHeader(
              label: groups[i].$1, note: groups[i].$3),
          SizedBox(height: Design.dz(14)),
          GridView.count(
              crossAxisCount: 4,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              padding: EdgeInsets.zero,
              mainAxisSpacing: Design.dz(14),
              crossAxisSpacing: Design.dz(14),
              // 稿子 tile 是自适应高度；Grid 里只能给比例。按「预览 64 + 两行字 +
              // padding 20×2」实测，1.5 才不会挤（1.62 会溢出 1.9px）。
              childAspectRatio: 1.5,
              children: [
                for (final spec in librarySpecs.where((spec) =>
                    _desktopTypes.contains(spec.type) == groups[i].$2))
                  _LibraryTile(
                      spec: spec,
                      onTap: () {
                        if (c.add(spec.type)) {
                          Navigator.pop(context);
                        } else {
                          showLauncherToast(context, '桌面页已满，请先移除一张卡片');
                        }
                      }),
              ]),
        ],
      ]));
    });

int _libraryCount(bool desktop) =>
    librarySpecs.where((spec) => _desktopTypes.contains(spec.type) == desktop).length;

/// 稿子 `.k-label` + 一条 10% 墨色渐隐到透明的细线 + 右侧小字计数。
class _LibraryGroupHeader extends StatelessWidget {
  final String label, note;
  const _LibraryGroupHeader({required this.label, required this.note});
  @override
  Widget build(BuildContext context) {
    final s = SurfaceStyle.of(context);
    return Row(children: [
      Text(label,
          style: TextStyle(
              fontSize: Design.dz(13),
              letterSpacing: Design.dz(1.6),
              color: s.muted)),
      SizedBox(width: Design.dz(12)),
      Expanded(
          child: Container(
              height: 1,
              decoration: BoxDecoration(
                  gradient: LinearGradient(colors: [
                s.text.withValues(alpha: .10),
                s.text.withValues(alpha: 0)
              ])))),
      SizedBox(width: Design.dz(12)),
      Text(note,
          style: TextStyle(fontSize: Design.dz(12), color: s.muted)),
    ]);
  }
}

/// 稿子 `.lib-it`：圆角 18 / 1px 8% 描边 / 3.5% 底 / padding 20，内部依次是
/// 64 高预览块（卡片色 6% 底 + 32px 圆角 10 图标块 + 两条骨架条）、标题 15、副标题 12、
/// 右下那颗 24px 的 `+`。以前整块比稿子大一号（86 预览 / 54 图标 / 23 号字），4 列显挤。
class _LibraryTile extends StatelessWidget {
  final CardSpec spec;
  final VoidCallback onTap;
  const _LibraryTile({required this.spec, required this.onTap});

  /// 稿子每张卡预览块都有自己的色相（导航=主题色、音乐=粉、天气=青、日历=紫）。
  /// 没在稿子里出现过的类型统一用主题色。
  Color _tint(SurfaceStyle s) => switch (spec.type) {
        'music' => const Color(0xFFFF5FA8),
        'weather' || 'air' => CardTint.cyan,
        'calendar' || 'member' || 'cleanup' => CardTint.violet,
        'trafficLight' || 'ride' => CardTint.amber,
        'battery' || 'fuel' || 'tpms' || 'body' || 'vehicle' => CardTint.mint,
        _ => s.accent,
      };

  @override
  Widget build(BuildContext context) {
    final s = SurfaceStyle.of(context), tint = _tint(s);
    return Material(
        color: s.text.withValues(alpha: .035),
        // 深蓝玻璃那套有自己的框架描边（technicalFrame），别把它覆盖成圆角矩形。
        shape: s.technicalFrame
            ? s.controlShape().copyWith(side: s.controlSide(false))
            : RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(s.controlRadius),
                side: BorderSide(color: s.text.withValues(alpha: .08))),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
            key: ValueKey('add-${spec.type}'),
            onTap: onTap,
            child: Padding(
                padding: EdgeInsets.all(Design.dz(20)),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Container(
                          height: Design.dz(64),
                          padding: EdgeInsets.symmetric(
                              horizontal: Design.dz(14), vertical: Design.dz(12)),
                          decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(Design.dz(12)),
                              color: tint.withValues(alpha: .06)),
                          child: Row(children: [
                            Container(
                                width: Design.dz(32),
                                height: Design.dz(32),
                                decoration: BoxDecoration(
                                    color: tint.withValues(alpha: .16),
                                    borderRadius:
                                        BorderRadius.circular(Design.dz(10))),
                                child: Center(
                                    child: UniIcon(cardSymbol(spec.type),
                                        size: Design.dz(17), color: tint))),
                            SizedBox(width: Design.dz(11)),
                            Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  for (final width in [62.0, 42.0]) ...[
                                    Container(
                                        width: Design.dz(width),
                                        height: Design.dz(6),
                                        decoration: BoxDecoration(
                                            color: s.text.withValues(
                                                alpha: width == 62 ? .22 : .10),
                                            borderRadius: BorderRadius.circular(
                                                Design.dz(3)))),
                                    if (width == 62)
                                      SizedBox(height: Design.dz(7)),
                                  ],
                                ]),
                          ])),
                      SizedBox(height: Design.dz(12)),
                      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Expanded(
                            child: Row(children: [
                          Flexible(
                              child: Text(
                                  spec.type == 'member' ? '账号' : spec.label,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                      fontSize: Design.dz(15),
                                      color: s.text.withValues(alpha: .86)))),
                          if (spec.type == 'air') ...[
                            SizedBox(width: Design.dz(8)),
                            Text('按车型',
                                style: TextStyle(
                                    fontSize: Design.dz(11), color: s.muted)),
                          ],
                        ])),
                        UniIcon('plus',
                            size: Design.dz(24),
                            color: s.accent),
                      ]),
                      SizedBox(height: Design.dz(4)),
                      Text(_libraryDescriptions[spec.type] ?? spec.source,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: Design.dz(12), color: s.muted)),
                    ]))));
  }
}

Future<void> editCard(
        BuildContext context, LauncherController c, LauncherCard card) =>
    showLauncherSheet<void>(context,
        title: '编辑${specFor(card.type).label}卡片',
        subtitle: '选择尺寸与位置',
        closeLabel: '关闭卡片设置',
        width: Design.px(780),
        glowType: card.type,
        builder: (context) => _CardEditor(controller: c, card: card));

class _CardEditor extends StatefulWidget {
  final LauncherController controller;
  final LauncherCard card;
  const _CardEditor({required this.controller, required this.card});
  @override
  State<_CardEditor> createState() => _CardEditorState();
}

class _CardEditorState extends State<_CardEditor> {
  late final TextEditingController input;
  late LauncherCard draft;
  String? error;
  @override
  void initState() {
    super.initState();
    draft = widget.card;
    final previewCity = draft.type == 'weather' &&
        widget.controller.native.value['demo'] == true;
    input = TextEditingController(
        text: previewCity && draft.title == '天气' ? '杭州' : draft.title);
  }

  @override
  void dispose() {
    input.dispose();
    super.dispose();
  }

  LauncherCard? place(LauncherCard candidate) {
    bool fits(LauncherCard next) =>
        next.inBounds &&
        !widget.controller.cards
            .any((other) => other.id != next.id && other.overlaps(next));
    if (fits(candidate)) return candidate;
    for (int y = 0; y <= 6 - candidate.h; y++) {
      for (int x = 0; x <= 12 - candidate.w; x++) {
        final next = candidate.copyWith(x: x, y: y);
        if (fits(next)) return next;
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final s = SurfaceStyle.of(context), spec = specFor(draft.type);
    final previewCity = draft.type == 'weather' &&
        widget.controller.native.value['demo'] == true;
    final vehicleCard =
        const {'battery', 'fuel', 'air', 'vehicle'}.contains(draft.type);
    final sizes = draft.type == 'trafficLight'
        // 4×1 是「只有一行读数」档：没有卡头，环和倒计时撑满卡高。
        ? <(int, int)>[(4, 1), (4, 2), (4, 3)]
        : draft.type == 'shortcuts'
            // 4×1 是「一行图标」档：没有卡头，应用不足 4 个用加号补齐。
            ? <(int, int)>[(4, 1), (4, 2), (4, 3), (4, 4)]
            : draft.type == 'music'
                // 4×1 同上：没有卡头，只留封面 + 曲目 + 播放键。
                ? <(int, int)>[(4, 1), (4, 2), (4, 3), (4, 4), (8, 6)]
                : <(int, int)>[
                    draft.type == 'weather' ? (4, 2) : (spec.minW, spec.minH),
                    if (vehicleCard)
                      (4, 3)
                    else
                      (
                        spec.minW > 4 ? spec.minW : 4,
                        spec.minH > 4 ? spec.minH : 4
                      ),
                    (spec.minW > 8 ? spec.minW : 8, 6),
                  ].toSet().toList();
    return SingleChildScrollView(
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SizedBox(height: Design.px(10)),
      Text(previewCity ? '预览城市（示例）' : '卡片名称',
          style: TextStyle(fontSize: Design.px(22), color: s.muted)),
      SizedBox(height: Design.px(14)),
      TextField(
          key: const ValueKey('card-title'),
          controller: input,
          maxLength: 20,
          style: TextStyle(fontSize: Design.px(25)),
          decoration: InputDecoration(
              counterText: '',
              contentPadding: EdgeInsets.symmetric(
                  horizontal: Design.px(20), vertical: Design.px(16)))),
      if (draft.type == 'clockWeather') ...[
        SizedBox(height: Design.px(30)),
        Text('卡片布局', style: TextStyle(fontSize: Design.px(22), color: s.muted)),
        SizedBox(height: Design.px(18)),
        Wrap(spacing: Design.px(14), runSpacing: Design.px(14), children: [
          for (final option in clockWeatherLayouts)
            SizedBox(
                width: Design.px(162),
                height: Design.px(58),
                // 选中态跟设置页同一套实心渐变（`.opt.on`），不再自写一份
                // 「描边 + 主题色字」——那样同一台车机上会出现两种选中态。
                child: ChoiceButton(
                    key: ValueKey('clock-weather-layout-${option.id}'),
                    kind: ChoiceKind.filled,
                    height: null,
                    radius: 11,
                    selected:
                        clockWeatherLayoutId(draft.layout) == option.id,
                    onPressed: () => setState(
                        () => draft = draft.copyWith(layout: option.id)),
                    child: Text(option.label,
                        style: TextStyle(fontSize: Design.px(19)))))
        ]),
      ],
      SizedBox(height: Design.px(30)),
      Text('卡片尺寸', style: TextStyle(fontSize: Design.px(22), color: s.muted)),
      SizedBox(height: Design.px(18)),
      Row(children: [
        for (int i = 0; i < sizes.length; i++) ...[
          if (i > 0) SizedBox(width: Design.px(18)),
          Expanded(
              child: _SizeOption(
                  size: sizes[i],
                  selected: draft.w == sizes[i].$1 && draft.h == sizes[i].$2,
                  onTap: () => setState(() {
                        final next = place(
                            draft.copyWith(w: sizes[i].$1, h: sizes[i].$2));
                        if (next == null) {
                          error = '此页空间不足，请先缩小或移动其他卡片';
                        } else {
                          draft = next;
                          error = null;
                        }
                      }))),
        ]
      ]),
      SizedBox(height: Design.px(30)),
      Row(children: [
        Text('信息来源', style: TextStyle(fontSize: Design.px(22), color: s.muted)),
        const Spacer(),
        Flexible(
            child: Text(spec.source,
                style: TextStyle(fontSize: Design.px(22)),
                textAlign: TextAlign.end))
      ]),
      if (error != null) ...[
        SizedBox(height: Design.px(18)),
        Text(error!,
            style: TextStyle(fontSize: Design.px(18), color: s.accent)),
      ],
      SizedBox(height: Design.px(36)),
      Row(mainAxisAlignment: MainAxisAlignment.end, children: [
        TextButton(
            onPressed: () => Navigator.pop(context), child: const Text('取消')),
        SizedBox(width: Design.px(20)),
        FilledButton(
            onPressed: () {
              final next = place(draft.copyWith(
                  title: input.text.trim().isEmpty
                      ? spec.label
                      : input.text.trim()));
              if (next != null && widget.controller.transform(next)) {
                Navigator.pop(context);
              } else {
                setState(() => error = '此页空间不足，请先缩小或移动其他卡片');
              }
            },
            child: const Text('保存卡片')),
      ]),
    ]));
  }
}

/// 稿子 `#f17` 的尺寸块：74 高、圆角 14，选中 = 50% 主题色描边 + 8% 同色底 +
/// 文案「4×3 · 当前」，未选 = 10% 墨色描边 + 次要文字。
class _SizeOption extends StatelessWidget {
  final (int, int) size;
  final bool selected;
  final VoidCallback onTap;
  const _SizeOption(
      {required this.size, required this.selected, required this.onTap});
  @override
  Widget build(BuildContext context) {
    final s = SurfaceStyle.of(context);
    final label = '${size.$1}×${size.$2}${selected ? ' · 当前' : ''}';
    return Semantics(
        button: true,
        selected: selected,
        label: '${size.$1} × ${size.$2}',
        child: Material(
            color: selected ? s.accent.withValues(alpha: .08) : Colors.transparent,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(Design.dz(14)),
                side: BorderSide(
                    color: selected
                        ? s.accent.withValues(alpha: .5)
                        : s.text.withValues(alpha: .1))),
            child: InkWell(
                key: ValueKey('card-size-${size.$1}-${size.$2}'),
                onTap: onTap,
                borderRadius: BorderRadius.circular(Design.dz(14)),
                child: SizedBox(
                    height: Design.dz(74),
                    child: Center(
                        child: Text(label,
                            style: TextStyle(
                                fontSize: Design.dz(13),
                                color: selected
                                    ? s.text.withValues(alpha: .85)
                                    : s.muted)))))));
  }
}
