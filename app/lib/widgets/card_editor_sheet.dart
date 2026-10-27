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
  'battery': '电量、混动与充电状态',
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

Future<void> showCardLibrary(BuildContext context, LauncherController c) =>
    showLauncherSheet<void>(context,
        title: '添加卡片',
        subtitle: '原车卡片使用官方信息来源，统一为桌面样式',
        closeLabel: '关闭卡片库',
        width: Design.px(1560),
        height: Design.px(850), builder: (context) {
      final s = SurfaceStyle.of(context);
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Expanded(
            child: SingleChildScrollView(
                child: Padding(
                    padding: EdgeInsets.only(right: Design.px(10)),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (final group in const [
                            ('原车卡片', false),
                            ('桌面扩展', true)
                          ]) ...[
                            if (group.$2) SizedBox(height: Design.px(28)),
                            Text(group.$1,
                                style: TextStyle(
                                    fontSize: Design.px(22), color: s.muted)),
                            SizedBox(height: Design.px(18)),
                            GridView.count(
                                crossAxisCount: 4,
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                padding: EdgeInsets.zero,
                                mainAxisSpacing: Design.px(18),
                                crossAxisSpacing: Design.px(18),
                                childAspectRatio: 1.76,
                                children: [
                                  for (final spec in librarySpecs.where(
                                      (spec) =>
                                          _desktopTypes.contains(spec.type) ==
                                          group.$2))
                                    _LibraryTile(
                                        spec: spec,
                                        onTap: () {
                                          if (c.add(spec.type)) {
                                            Navigator.pop(context);
                                          } else {
                                            showLauncherToast(
                                                context, '桌面页已满，请先移除一张卡片');
                                          }
                                        }),
                                ]),
                          ],
                        ])))),
        SizedBox(height: Design.px(28)),
        Text('可重复添加 · 空间不足时添加到新页 · 其他车型卡片见样式总览',
            style: TextStyle(
                fontSize: Design.px(18), height: 1.2, color: s.muted)),
      ]);
    });

class _LibraryTile extends StatelessWidget {
  final CardSpec spec;
  final VoidCallback onTap;
  const _LibraryTile({required this.spec, required this.onTap});
  @override
  Widget build(BuildContext context) {
    final s = SurfaceStyle.of(context);
    return Material(
        color: s.soft,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(s.radius * .8),
            side: BorderSide(color: s.edge)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
            key: ValueKey('add-${spec.type}'),
            onTap: onTap,
            child: Padding(
                padding: EdgeInsets.all(Design.px(16)),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Container(
                          height: Design.px(86),
                          padding: EdgeInsets.all(Design.px(15)),
                          decoration: BoxDecoration(
                              borderRadius:
                                  BorderRadius.circular(s.controlRadius),
                              color: s.soft,
                              gradient: RadialGradient(
                                  center: Alignment.topLeft,
                                  radius: 1.3,
                                  colors: [
                                    s.seed.withValues(alpha: .20),
                                    Colors.transparent
                                  ])),
                          child: Row(children: [
                            Container(
                                width: Design.px(54),
                                height: Design.px(54),
                                decoration: BoxDecoration(
                                    color: s.soft,
                                    borderRadius:
                                        BorderRadius.circular(s.controlRadius)),
                                child: Center(
                                    child: UniIcon(cardSymbol(spec.type),
                                        size: Design.px(30), color: s.accent))),
                            SizedBox(width: Design.px(23)),
                            Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  for (final width in [80, 56]) ...[
                                    Container(
                                        width: Design.px(width),
                                        height: Design.px(8),
                                        decoration: BoxDecoration(
                                            color: s.edge.withValues(
                                                alpha: width == 80 ? .3 : .18),
                                            borderRadius: BorderRadius.circular(
                                                Design.px(8)))),
                                    if (width == 80)
                                      SizedBox(height: Design.px(14)),
                                  ],
                                ]),
                          ])),
                      SizedBox(height: Design.px(14)),
                      Row(children: [
                        Expanded(
                            child: Row(children: [
                          Flexible(
                              child: Text(
                                  spec.type == 'member' ? '账号' : spec.label,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                      fontSize: Design.px(23), height: 1.2))),
                          if (spec.type == 'air') ...[
                            SizedBox(width: Design.px(10)),
                            Text('按车型',
                                style: TextStyle(
                                    fontSize: Design.px(13), color: s.muted)),
                          ],
                        ])),
                        UniIcon('plus', size: Design.px(25), color: s.accent),
                      ]),
                      SizedBox(height: Design.px(9)),
                      Text(_libraryDescriptions[spec.type] ?? spec.source,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: Design.px(15),
                              height: 1.2,
                              color: s.muted)),
                    ]))));
  }
}

Future<void> editCard(
        BuildContext context, LauncherController c, LauncherCard card) =>
    showLauncherSheet<void>(context,
        title: '编辑${specFor(card.type).label}卡片',
        subtitle: '调整展示，保持官方信息来源',
        closeLabel: '关闭卡片设置',
        width: Design.px(780),
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
        const {'battery', 'air', 'vehicle'}.contains(draft.type);
    final sizes = draft.type == 'trafficLight'
        ? <(int, int)>[(4, 2), (4, 3)]
        : draft.type == 'shortcuts'
            ? <(int, int)>[(4, 2), (4, 3), (4, 4)]
            : draft.type == 'music'
                ? <(int, int)>[(4, 2), (4, 3), (4, 4), (8, 6)]
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
                child: OutlinedButton(
                    key: ValueKey('clock-weather-layout-${option.id}'),
                    onPressed: () => setState(
                        () => draft = draft.copyWith(layout: option.id)),
                    style: OutlinedButton.styleFrom(
                        foregroundColor:
                            clockWeatherLayoutId(draft.layout) == option.id
                                ? s.accent
                                : s.text,
                        side: BorderSide(
                            color:
                                clockWeatherLayoutId(draft.layout) == option.id
                                    ? s.accent
                                    : s.edge)),
                    child: Text(option.label)))
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

class _SizeOption extends StatelessWidget {
  final (int, int) size;
  final bool selected;
  final VoidCallback onTap;
  const _SizeOption(
      {required this.size, required this.selected, required this.onTap});
  @override
  Widget build(BuildContext context) {
    final s = SurfaceStyle.of(context), color = selected ? s.accent : s.muted;
    return Semantics(
        button: true,
        selected: selected,
        label: '${size.$1} × ${size.$2}',
        child: SizedBox(
            height: Design.px(120),
            child: Material(
                color: s.soft,
                shape: s
                    .controlShape(selected: selected)
                    .copyWith(side: s.controlSide(selected)),
                child: InkWell(
                    key: ValueKey('card-size-${size.$1}-${size.$2}'),
                    onTap: onTap,
                    borderRadius: BorderRadius.circular(s.controlRadius),
                    child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                              height: Design.px(37),
                              width: Design.px(37 * size.$1 / size.$2),
                              decoration: BoxDecoration(
                                  border: Border.all(
                                      color: color, width: Design.px(2)),
                                  borderRadius:
                                      BorderRadius.circular(Design.px(7)))),
                          SizedBox(height: Design.px(14)),
                          Text('${size.$1} × ${size.$2}',
                              style: TextStyle(
                                  fontSize: Design.px(19), color: color)),
                        ])))));
  }
}
