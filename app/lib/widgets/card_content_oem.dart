part of 'card_content.dart';

class _BodyCard extends StatelessWidget {
  final LauncherCard card;
  final Map<String, dynamic> native;
  const _BodyCard({required this.card, required this.native});
  @override
  Widget build(BuildContext context) {
    // 稿子 f2 的副标题是「全部正常 · 1 处关注」——按车门/尾门/前舱的开闭状态算，
    // 胎压阈值没有可靠来源，不编。
    final doors = VehicleDoorSnapshot.fromNative(native);
    final open = [
      doors.frontLeft,
      doors.frontRight,
      doors.rearLeft,
      doors.rearRight,
      doors.tailgate,
      doors.hood
    ].where((value) => value == true).length;
    return _CardCanvas(
        minHeight: 300,
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _Heading(card.title == '车门状态' ? '车况与胎压' : card.title, '', 'car',
              sub: open == 0 ? '全部正常' : '车门未关 · $open 处'),
          Expanded(child: VehicleStatusDiagram(native: native)),
        ]));
  }
}

String _calendarDetail(Map<String, dynamic> calendar) {
  if (calendar['authorized'] != true) return '轻触授权读取系统日历';
  if (calendar['eventAvailable'] != true) return '系统日历';
  final location = '${calendar['location'] ?? ''}'.trim();
  final begin = (calendar['beginMs'] as num?)?.toInt();
  if (begin == null) return location.isEmpty ? '系统日历' : location;
  final time = DateTime.fromMillisecondsSinceEpoch(begin);
  final clock = calendar['allDay'] == true
      ? '全天'
      : '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
  return location.isEmpty ? clock : '$clock · $location';
}

class _OemCard extends StatelessWidget {
  final LauncherCard card;
  final LauncherController controller;
  final bool demo;
  const _OemCard(
      {required this.card, required this.controller, required this.demo});
  @override
  Widget build(BuildContext context) {
    final s = SurfaceStyle.of(context), editing = controller.editing;
    final account =
        mapOf(mapOf(controller.native.value['systemStatus'])['account']);
    final calendar = mapOf(controller.native.value['calendar']);
    return LayoutBuilder(builder: (context, box) {
      // 账号卡按 4×6 排（头像 + 4 行键值 + 主按钮），压到 4×3 时整块等比缩小
      // 会糊成一团，所以它的紧凑档门槛按 4×6 的高度来定：4×3 直接走紧凑版式
      // （头像 + 姓名 + 状态徽章），其余卡片维持原来的 380。
      final compact =
          box.maxHeight < Design.px(card.type == 'member' ? 700 : 380);
      final title =
          card.type == 'member' && card.title == '领克账号' ? '账号' : card.title;
      final content = _CardCanvas(
          // 账号卡是 4×6（502×733 画布单位 = 602×880 源码 px）：版式里有头像、
          // 4 行键值和一个主按钮，按 340 的下限排会被压到溢出。给足设计尺寸，
          // 卡片真被压小的时候由 _CardCanvas 的 FittedBox 等比缩。
          minWidth: card.type == 'member' && !compact ? 602 : 340,
          minHeight: card.type == 'member'
              ? (compact ? 300 : 880)
              : card.type == 'tpms'
                  ? 310
                  : 300,
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            _Heading(
                title,
                card.type == 'member' ? '账号中心' : specFor(card.type).source,
                cardSymbol(card.type),
                // 稿子里「胎压」卡头与「车况与胎压」是同一枚车形图形
                // （tire.svg 没有对应稿子图形，会退成环里一枚轮胎图标）。
                kind: card.type == 'tpms' ? 'car' : null),
            if (card.type == 'member') ...[
              Expanded(
                  child: _AccountCardBody(
                      account: account,
                      demo: demo,
                      compact: compact,
                      onOpen: editing
                          ? null
                          : () => showAccountDetails(context, controller))),
            ] else if (card.type == 'cleanup') ...[
              Expanded(
                  child: Row(children: [
                Container(
                    width: Design.px(editing ? 70 : 92),
                    height: Design.px(editing ? 70 : 92),
                    decoration: BoxDecoration(
                        color: s.soft,
                        borderRadius: BorderRadius.circular(s.radius * .8)),
                    child: Center(
                        child: UniIcon('broom',
                            size: Design.px(editing ? 40 : 49),
                            color: s.accent))),
                SizedBox(width: Design.px(26)),
                Expanded(
                    child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Text('—',
                          style: TextStyle(
                              fontSize: Design.px(editing ? 46 : 68),
                              height: 1,
                              fontWeight: FontWeight.w300)),
                      SizedBox(height: Design.px(14)),
                      Text('释放运行内存',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: Design.px(editing ? 18 : 20),
                              color: s.muted)),
                    ])),
              ])),
              _OpenCardButton('打开清理',
                  compact: editing,
                  onTap: () =>
                      controller.command('official-widget', value: 'cleanup')),
            ] else if (card.type == 'calendar') ...[
              SizedBox(height: Design.px(editing ? 12 : 18)),
              Row(children: [
                Text('${demo ? 24 : calendar['day'] ?? '—'}',
                    style: TextStyle(
                        fontSize: Design.px(editing ? 65 : 94),
                        height: 1,
                        fontWeight: FontWeight.w300,
                        color: s.accent)),
                SizedBox(width: Design.px(26)),
                Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Text(demo ? '星期六' : '${calendar['weekday'] ?? '—'}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style:
                              TextStyle(fontSize: Design.px(25), height: 1.2)),
                      SizedBox(height: Design.px(12)),
                      Text(
                          demo
                              ? '2026 年 10 月'
                              : '${calendar['monthLabel'] ?? '等待日期'}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: Design.px(20),
                              height: 1.2,
                              color: s.muted)),
                    ])),
              ]),
              const Spacer(),
              InkWell(
                  key: const ValueKey('calendar-agenda'),
                  onTap: !demo && calendar['authorized'] != true
                      ? () => controller.command('calendar-access')
                      : null,
                  child: Container(
                      padding:
                          EdgeInsets.only(top: Design.px(editing ? 12 : 20)),
                      decoration: BoxDecoration(
                          border: Border(top: BorderSide(color: s.edge))),
                      child: Row(children: [
                        Container(
                            width: Design.px(4),
                            height: Design.px(39),
                            decoration: BoxDecoration(
                                color: s.accent,
                                borderRadius:
                                    BorderRadius.circular(Design.px(3)))),
                        SizedBox(width: Design.px(16)),
                        Expanded(
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                              Text(
                                  demo
                                      ? '10:30  车辆保养预约'
                                      : calendar['eventAvailable'] == true
                                          ? '${calendar['title'] ?? '未命名日程'}'
                                          : calendar['authorized'] == true
                                              ? '暂无日程'
                                              : '点击授权日历',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                      fontSize: Design.px(editing ? 19 : 22),
                                      height: 1.2)),
                              SizedBox(height: Design.px(editing ? 6 : 10)),
                              Text(demo ? '领克中心' : _calendarDetail(calendar),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                      fontSize: Design.px(editing ? 16 : 18),
                                      height: 1.2,
                                      color: s.muted)),
                            ])),
                      ]))),
            ] else if (card.type == 'tpms') ...[
              Expanded(child: TireDiagram(native: controller.native.value)),
              _StateLine(
                  VehicleField.fromNative(
                              controller.native.value, 'pressureFrontLeft')
                          .valid
                      ? '实时胎压 · bar'
                      : '等待车辆数据',
                  dot: true),
            ] else ...[
              Expanded(
                  child: Center(
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  UniIcon('ride', size: Design.px(60), color: s.accent),
                  SizedBox(width: Design.px(18)),
                  Text('出行服务', style: TextStyle(fontSize: Design.px(30))),
                ]),
              ]))),
              const _StateLine('其他车型配置 · 本车未确认'),
            ],
          ]));
      if (card.type != 'member') return content;
      return Material(
          type: MaterialType.transparency,
          child: InkWell(
              key: const ValueKey('member-card-open'),
              borderRadius: BorderRadius.circular(s.radius),
              onTap: editing
                  ? null
                  : () => showAccountDetails(context, controller),
              child: content));
    });
  }
}

/// 账号卡（稿子 `#f24`，4×6）的正文：头像行 → 渐隐分隔线 → 键值行 → 底部
/// 「进入账号中心」。
///
/// 稿子里那张 4×6 是：120 头像 + 27 号姓名 + 两枚徽章（已登录 / 车主认证）、
/// 一条紫色渐隐线、4 行 72 高键值（账号类型 / 会员等级 / 登录状态 / 信息来源）、
/// 底部描边主按钮。**账号类型与车主认证在原生账号快照里没有字段**，按
/// 2026-11-14 的口径不画；分隔线用主题强调色，换配色时跟整套同步。
class _AccountCardBody extends StatelessWidget {
  final Map<String, dynamic> account;
  final bool demo;
  final bool compact;
  final VoidCallback? onOpen;
  const _AccountCardBody(
      {required this.account,
      required this.demo,
      required this.compact,
      required this.onOpen});

  @override
  Widget build(BuildContext context) {
    final s = SurfaceStyle.of(context);
    final a = AccountSummary(account, demo);
    // 稿子那张 4×6 的键值块是 4 行（账号类型 / 会员等级 / 登录状态 / 信息来源）。
    // 账号类型原生没有字段，改用同源真实数据「账号名称」顶上——不编字段，
    // 也让键值块的节奏跟稿子一致（否则 4×6 的卡下半截会空一大片）。
    final rows = <(String, String)>[
      ('账号名称', a.name),
      if (a.level.isNotEmpty) ('会员等级', a.level),
      ('登录状态', a.status),
      ('信息来源', a.source),
    ];
    final avatarRow = Row(children: [
      AccountAvatar(
          account: account, name: a.name, size: Design.px(compact ? 96 : 144)),
      SizedBox(width: Design.px(compact ? 20 : 26)),
      Expanded(
          child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
            Text(a.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: Design.px(compact ? 24 : 32),
                    height: 1.2,
                    fontWeight: FontWeight.w500)),
            SizedBox(height: Design.px(compact ? 10 : 16)),
            if (a.known)
              Wrap(spacing: Design.px(9), runSpacing: Design.px(9), children: [
                AccountStatusChip(label: a.status, active: a.loggedIn)
              ]),
          ])),
    ]);
    if (compact) return Center(child: avatarRow);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SizedBox(height: Design.px(48)),
      avatarRow,
      SizedBox(height: Design.px(34)),
      // 稿子那条紫色渐隐线；这里跟着强调色走，三套皮肤 / 各配色自动同步。
      Container(
          height: Design.px(1.4) * .7,
          decoration: BoxDecoration(
              gradient: LinearGradient(colors: [
            s.accent.withValues(alpha: .5),
            s.accent.withValues(alpha: 0)
          ]))),
      SizedBox(height: Design.px(24)),
      for (final row in rows)
        AccountInfoRow(
            label: row.$1,
            value: row.$2,
            height: Design.px(86),
            divider: row != rows.last),
      const Spacer(),
      if (onOpen != null) _OpenCardButton('进入账号中心', onTap: onOpen!),
    ]);
  }
}

class _StateLine extends StatelessWidget {
  final String text;
  final bool dot;
  const _StateLine(this.text, {this.dot = false});
  @override
  Widget build(BuildContext context) {
    final s = SurfaceStyle.of(context);
    return ConstrainedBox(
        constraints: BoxConstraints(minHeight: Design.px(26)),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          if (dot) ...[
            Container(
                width: Design.px(6),
                height: Design.px(6),
                decoration:
                    BoxDecoration(color: s.muted, shape: BoxShape.circle)),
            SizedBox(width: Design.px(10)),
          ],
          Flexible(
              child: Text(text,
                  maxLines: 2,
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: Design.px(18), height: 1.2, color: s.muted))),
        ]));
  }
}

class _WeatherCard extends StatelessWidget {
  final LauncherCard card;
  final LauncherController controller;
  final bool demo, editing;
  final Map<String, dynamic> native;
  const _WeatherCard(
      {required this.card,
      required this.controller,
      required this.demo,
      required this.editing,
      required this.native});
  @override
  Widget build(BuildContext context) {
    final s = SurfaceStyle.of(context);
    // The title can also be used as a demo preview city; live weather stays unknown.
    final weather = WeatherSnapshot.fromNative(native);
    final city =
        demo ? (card.title == '天气' ? weather.city : card.title) : weather.city;
    return Material(
        type: MaterialType.transparency,
        child: InkWell(
            key: const ValueKey('weather-card-open'),
            borderRadius: BorderRadius.circular(s.radius),
            onTap:
                editing ? null : () => showWeatherDetails(context, controller),
            child: _CardCanvas(
                minHeight: editing ? 180 : 230,
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(children: [
                        UniIcon('pin', size: Design.px(23), color: s.text),
                        SizedBox(width: Design.px(8)),
                        Expanded(
                            child: Text(city,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    fontSize: Design.px(23), height: 1.2))),
                        Text(weather.source.replaceAll('原车', ''),
                            style: TextStyle(
                                fontSize: Design.px(20), color: s.muted)),
                      ]),
                      Expanded(
                          child: Row(children: [
                        Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(weather.temperature?.toString() ?? '—',
                                  style: TextStyle(
                                      fontSize: Design.px(editing ? 48 : 65),
                                      height: 1,
                                      fontWeight: FontWeight.w400,
                                      letterSpacing: Design.px(-2))),
                              Padding(
                                  padding: EdgeInsets.only(top: Design.px(7)),
                                  child: Text('°',
                                      style: TextStyle(
                                          fontSize:
                                              Design.px(editing ? 28 : 36),
                                          height: 1))),
                            ]),
                        SizedBox(width: Design.px(20)),
                        Expanded(
                            child: Text(weather.description,
                                style: TextStyle(fontSize: Design.px(25)))),
                        WeatherIcon(
                            condition: weather.condition,
                            night: weather.night,
                            size: Design.px(editing ? 80 : 100),
                            color: s.accent),
                      ])),
                    ]))));
  }
}

class _ShortcutCard extends StatelessWidget {
  final LauncherCard card;
  final LauncherController controller;
  const _ShortcutCard({required this.card, required this.controller});

  @override
  Widget build(BuildContext context) {
    final s = SurfaceStyle.of(context);
    final available = (controller.native.value['apps'] is List
            ? controller.native.value['apps'] as List
            : const [])
        .whereType<Map>()
        .where((a) => a['enabled'] != false && a['launchable'] != false)
        .map((a) => Map<String, dynamic>.from(a))
        .toList();
    final byId = {
      for (final app in available)
        if (app['id'] is String) app['id'] as String: app
    };
    // 列数跟着卡宽走。4 列是稿子的排法，但快捷应用卡的 minW 是 3
    // （`CardSpec('shortcuts', …, 3, 2)`）——卡片缩到 3 格宽还排 4 列，
    // 每格只剩 ~50 画布宽，图标缩成小色块。容量跟着列数走，否则多出来的
    // 应用在网格里没有位置（取前 capacity 个，剩下的仍然存在，放大卡片会回来）。
    final cols = card.w >= 4 ? 4 : math.max(1, card.w);
    final rows = card.h <= 2
        ? 1
        : card.h == 3
            ? 2
            : 3;
    final capacity = cols * rows;
    final selected = card.shortcutApps.take(capacity).toList();
    Future<void> edit() async {
      if (controller.editing) return;
      final result = await showLauncherSheet<List<String>>(context,
          title: '管理快捷应用',
          subtitle: '选择最多 $capacity 个应用',
          width: Design.px(900),
          height: Design.px(700),
          glowType: 'shortcuts',
          builder: (_) => _ShortcutPicker(
              apps: available,
              initial: card.shortcutApps,
              capacity: capacity,
              controller: controller));
      if (result != null) await controller.setShortcutApps(card.id, result);
    }

    /// 一格应用：图标（行数够时带名字），点开启动（编辑态与已卸载应用不可点）。
    ///
    /// 图标尺寸由调用方按格子算出来。原来是写死的 Design.px(36)（=30 画布），
    /// 只占格宽四成，卡片越窄越认不出图标。
    Widget tile(String id, double side, bool showLabel) {
      final app = byId[id];
      final bytes = app?['iconBytes'];
      final name = app == null ? '应用不可用' : controller.appName(app);
      return _MiniAppTile(
          key: ValueKey('shortcut-$id'),
          side: side,
          showLabel: showLabel,
          label: name,
          icon: bytes is Uint8List
              ? Image.memory(bytes,
                  filterQuality: FilterQuality.medium,
                  errorBuilder: (_, __, ___) =>
                      Icon(Icons.apps, size: side, color: s.muted))
              : Icon(Icons.apps, size: side, color: s.muted),
          onTap: controller.editing || app == null
              ? null
              : () => controller.command('launch-app', value: id));
    }

    // 卡片小于 4×3 且应用不足 4 个时，整张卡按「一行大图标」画：不要卡头，
    // 应用不足列数时补一颗虚线加号——用户 2026-11-15 给的参考图就是这种
    // iOS 主屏横条。一格高（4×1）的卡本来就放不下卡头，无条件走这一套；
    // 一个应用都没选的 2 格卡保留卡头——纯一颗加号看不出这张卡是干什么的。
    final bare = card.h <= 1 ||
        (card.h <= 2 && selected.isNotEmpty && selected.length < 4);

    Widget grid(BoxConstraints box) {
      // 无卡头时把格间距收紧：参考图（iOS 主屏横条）的图标之间只留一条窄缝，
      // 12 画布在 4 格宽里会显得四颗图标各站一边。
      final gap = Design.px(bare ? 8 : 12);
      final cellW = (box.maxWidth - gap * (cols - 1)) / cols;
      final cellH = (box.maxHeight - gap * (rows - 1)) / rows;
      // 标签块 = 一行字（13.2 × 1.2）+ 与图标的间距。
      final labelBlock = Design.px(13.2) * 1.2 + Design.px(10.8);
      // 只有一行（最小档 3×2 / 4×2 / 4×1）就只显示图标：一行的高度全给图标
      // 更清楚，名字在编辑弹层里能看到。两行以上、且行高放得下
      // 「图标 44 + 标签」时才带名字——4×3 / 4×4 卡被压扁时同样退回图标。
      final showLabel = rows > 1 && cellH >= Design.px(44) + labelBlock;
      // 上限 96（=80 画布）：卡片被拉到 8 格宽时，格子会宽到 150 画布，
      // 不封顶就成了两三个巨型图标。
      // 上限只防「12 格宽的卡里四个巨型图标」这种极端情况。原来是 96
      // （=80 px），但卡宽是网格算的（4 格宽 ~608 px），图标却被这个上限
      // 钉在 80 px，卡片越宽显得越小——4×3 / 4×2 的图标全被它封住了。
      // 一格档（4×1 / 3×1）：格子高度就是整卡内容高，图标按 min(格宽,格高)
      // 吃满会直接顶住卡片的上下边框（用户 2026-11-15 截图反馈「顶住上下边框」）。
      // 收到 .72：4 格宽卡里图标 95.6 → 68.8 画布，上下各留 13.4（约卡高 14%）。
      // 第一版给 .78 只有 11% 的缝，真图标撑满框后看着还是紧。
      //
      // 判据用「格子比宽还扁」而不是 `rows == 1`：4×2 也是一行（rows 恒 1），
      // 但它的格子高 184、图标是**格宽**限制的，上下本来就有 35 的余量，
      // 不该跟着收——用户只让动真正顶边的那一档。
      final hugHeight = cellH <= cellW;
      final side = math.max(
          Design.px(20),
          math.min(
              Design.px(260),
              showLabel
                  ? math.min(cellW * .86, cellH - labelBlock)
                  : math.min(cellW, cellH) *
                      (bare && hugHeight ? .72 : (bare ? 1 : .84))));
      // 应用数不足列数时补一颗加号，刚好填满就收掉：4×1 选 3 个 → 3 图标 +
      // 1 加号；选 4 个 → 一行正好，不再补。只补一颗，不把整行摊满——
      // 空位本身也是「还能放」的提示，全塞成加号只是噪点。
      final addCount = selected.length < capacity ? 1 : 0;
      final tiles = <Widget>[
        for (final id in selected) tile(id, side, showLabel),
        for (var i = 0; i < addCount; i++)
          _MiniAppTile(
              key: ValueKey('shortcuts-add-${card.id}'),
              dashed: true,
              side: side,
              showLabel: showLabel,
              label: '添加',
              icon: Icon(Icons.add,
                  // Material 的 + 字形在 em 框里只占六成，.58 会显得比
                  // 旁边的图标小一圈，这里补到 .8。
                  size: side * .8,
                  color: s.text.withValues(alpha: .5)),
              onTap: controller.editing ? null : edit),
      ];
      // cols 列等分网格，行数按容量算而不是按已有卡片算——只放了三格时，
      // 第四格之后是空行。格子不再撑满行高（原来 stretch 会把图标格
      // 拉成竖长条，圆角框跟着变形），改成整格热区 + 内容居中：
      // 行高富余只是上下留白，图标永远是正方形。
      return Column(children: [
        for (var row = 0; row * cols < capacity; row++) ...[
          if (row > 0) SizedBox(height: gap),
          Expanded(
              child: Row(children: [
            for (var col = 0; col < cols; col++) ...[
              if (col > 0) SizedBox(width: gap),
              Expanded(
                  child: row * cols + col < tiles.length
                      ? tiles[row * cols + col]
                      : const SizedBox.shrink()),
            ],
          ])),
        ],
      ]);
    }

    // 入口只有两个，都不在右上角：长按整卡，或点虚线加号格。
    // 这里原来还有一颗铅笔按钮，2026-11-15 按设计意见去掉——稿子里卡头
    // 只写「长按编辑」，多一颗铅笔是第三种入口，视觉上还挤掉了标题宽度。
    // 代价：选满 capacity 个应用后虚线格消失，此时只剩长按一条路。
    final body = GestureDetector(
        behavior: HitTestBehavior.opaque,
        onLongPress: controller.editing ? null : edit,
        child: bare
            ? Padding(
                // 一格高的卡只有 ~77 画布，28 的上下留白会吃掉一半高度；
                // 水平也收到 14：无卡头的形态就是让图标吃满整行（参考图
                // 卡片内边距也很窄），30 会平白少掉一成图标宽度。
                padding: EdgeInsets.symmetric(
                    horizontal: Design.px(14),
                    vertical: Design.px(card.h <= 1 ? 6 : 28)),
                child: LayoutBuilder(builder: (_, box) => grid(box)))
            : Column(
                // stretch 跟 `_OemCard` 那份 Column 一致：卡头是 Row，默认 center
                // 看似也能撑满，但一旦有人往这里塞窄组件就会居中，两张卡的卡头
                // 从此对不齐。
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _Heading(card.title, '', 'apps', sub: '长按编辑'),
                  SizedBox(height: Design.px(12)),
                  Expanded(
                      child: LayoutBuilder(builder: (_, box) => grid(box))),
                ]));

    return _CardCanvas(
        // 无卡头时按真实尺寸排版：minHeight 190 是「卡头 + 一行内容」的基准，
        // 一格高的卡只有 ~77 画布，走 FittedBox 会被整体缩到四成，图标反而
        // 更小。minWidth 同理——这个尺寸的卡不需要等比兜底。
        minWidth: bare ? 0 : 340,
        minHeight: bare ? 0 : 190,
        padded: !bare,
        child: body);
  }
}

/// 一格应用：正方形图标（放得下时带一行名字），整格都是点击热区。
///
/// 2026-11-15 去掉了原来那层圆角墨底 + 描边：格宽只有 ~74 画布单位，框把
/// 图标压到 30，而卡片一高，被 stretch 撑满的框就拉成竖长条（截图里
/// 四根变形长框）。现在只画图标本身，尺寸按格子算，行高富余只留白。
///
/// [dashed] 是「添加」格：保留虚线框，否则空位看不出可点；它同样按
/// [side] 画成正方形，不跟格子高度走。
class _MiniAppTile extends StatelessWidget {
  final Widget icon;
  final String label;
  final VoidCallback? onTap;
  final bool dashed;

  /// 图标边长（正方形，画布单位）。
  final double side;

  /// 是否显示名字。最小档（只有一行）传 false，只留图标。
  final bool showLabel;
  const _MiniAppTile(
      {super.key,
      required this.icon,
      required this.label,
      required this.side,
      required this.showLabel,
      this.onTap,
      this.dashed = false});

  @override
  Widget build(BuildContext context) {
    final s = SurfaceStyle.of(context);
    final radius = side * .22;
    final mark = SizedBox.square(
        dimension: side,
        child: dashed
            ? CustomPaint(
                painter: _DashedBorderPainter(
                    color: s.text.withValues(alpha: .16), radius: radius),
                child: Center(child: icon))
            // contain 而不是 scaleDown：系统图标常常只有 48~96px，
            // 不放大就补不满格子，看起来还是「小图标」。
            : FittedBox(fit: BoxFit.contain, child: icon));
    return InkWell(
        borderRadius: BorderRadius.circular(Design.px(16)),
        onTap: onTap,
        child: Center(
            child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
              mark,
              if (showLabel) ...[
                SizedBox(height: Design.px(10.8)),
                Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: Design.px(13.2),
                        letterSpacing: Design.px(.53),
                        color: s.muted)),
              ],
            ])));
  }
}

/// 虚线圆角框。Flutter 的 Border 不支持虚线，稿子的「添加」格是
/// `border:1px dashed`，这里按 6 / 4 的短划把圆角矩形描一遍。
class _DashedBorderPainter extends CustomPainter {
  final Color color;
  final double radius;
  const _DashedBorderPainter({required this.color, required this.radius});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..isAntiAlias = true;
    final rect = Rect.fromLTWH(.5, .5, size.width - 1, size.height - 1);
    final path = Path()
      ..addRRect(RRect.fromRectAndRadius(rect, Radius.circular(radius)));
    // 短划长度跟着框走：图标格小到 40 画布单位时，固定的 6/4 会密成一圈虚线。
    final dash = (size.width * .1).clamp(4.0, 8.0);
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final end = distance + dash < metric.length
            ? distance + dash
            : metric.length;
        canvas.drawPath(metric.extractPath(distance, end), paint);
        distance += dash + 4;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedBorderPainter old) =>
      old.color != color || old.radius != radius;
}

class _ShortcutPicker extends StatefulWidget {
  final List<Map<String, dynamic>> apps;
  final List<String> initial;
  final int capacity;
  final LauncherController controller;
  const _ShortcutPicker(
      {required this.apps,
      required this.initial,
      required this.capacity,
      required this.controller});
  @override
  State<_ShortcutPicker> createState() => _ShortcutPickerState();
}

class _ShortcutPickerState extends State<_ShortcutPicker> {
  late final List<String> selected = List.of(widget.initial);
  @override
  Widget build(BuildContext context) {
    final installed = {
      for (final app in widget.apps)
        if (app['id'] is String) app['id'] as String: app
    };
    return Column(children: [
      Expanded(
          child: ListView(children: [
        for (final id in selected.where((id) => !installed.containsKey(id)))
          ListTile(
              key: ValueKey('shortcut-option-$id'),
              title: Text('应用不可用：$id'),
              trailing: const Icon(Icons.remove_circle_outline),
              onTap: () => setState(() => selected.remove(id))),
        for (final app in widget.apps)
          if (app['id'] is String)
            Builder(builder: (context) {
              final id = app['id'] as String, chosen = selected.contains(id);
              final bytes = app['iconBytes'];
              return ListTile(
                  key: ValueKey('shortcut-option-$id'),
                  leading: SizedBox.square(
                      dimension: Design.px(36),
                      child: bytes is Uint8List
                          ? Image.memory(bytes,
                              errorBuilder: (_, __, ___) =>
                                  const Icon(Icons.apps))
                          : const Icon(Icons.apps)),
                  title: Text(widget.controller.appName(app)),
                  trailing: Icon(
                      chosen ? Icons.check_circle : Icons.add_circle_outline),
                  enabled: chosen || selected.length < widget.capacity,
                  onTap: () => setState(() {
                        if (chosen) {
                          selected.remove(id);
                        } else if (selected.length < widget.capacity) {
                          selected.add(id);
                        }
                      }));
            }),
      ])),
      TextButton(
          key: const ValueKey('shortcut-picker-save'),
          onPressed: () => Navigator.pop(context, selected),
          child: const Text('完成')),
    ]);
  }
}
