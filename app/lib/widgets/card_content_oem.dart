part of 'card_content.dart';

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
    final levelName = '${account['memberLevelName'] ?? ''}'.trim();
    final level = (account['memberLevel'] as num?)?.toInt() ?? 0;
    final levelLabel = levelName.isNotEmpty
        ? levelName
        : level > 0
            ? 'Lv. $level'
            : '';
    final calendar = mapOf(controller.native.value['calendar']);
    return LayoutBuilder(builder: (context, box) {
      final compact = box.maxHeight < Design.px(380);
      final title =
          card.type == 'member' && card.title == '领克账号' ? '账号' : card.title;
      final content = _CardCanvas(
          minHeight: card.type == 'member'
              ? 340
              : card.type == 'tpms'
                  ? 310
                  : 300,
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            _Heading(
                title,
                card.type == 'member' ? '账号中心' : specFor(card.type).source,
                cardSymbol(card.type)),
            if (card.type == 'member') ...[
              Expanded(
                  child: Center(
                      child: Row(children: [
                AccountAvatar(
                    account: account, size: Design.px(compact ? 72 : 116)),
                SizedBox(width: Design.px(compact ? 18 : 26)),
                Expanded(
                    child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Text(
                          demo
                              ? '演示账号'
                              : account['known'] == true &&
                                      account['loggedIn'] == true
                                  ? '${account['name'] ?? '领克账号'}'
                                  : '领克账号',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: Design.px(compact ? 25 : 31),
                              height: 1.2,
                              fontWeight: FontWeight.w500)),
                      SizedBox(height: Design.px(compact ? 10 : 13)),
                      if (demo || account['known'] == true)
                        Row(children: [
                          Container(
                              width: Design.px(8),
                              height: Design.px(8),
                              decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: demo || account['loggedIn'] == true
                                      ? s.accent
                                      : s.muted)),
                          SizedBox(width: Design.px(9)),
                          Flexible(
                              child: Text(
                                  demo
                                      ? '演示数据'
                                      : account['known'] == true
                                          ? (account['loggedIn'] == true
                                              ? '已登录'
                                              : '未登录')
                                          : '—',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                      fontSize: Design.px(compact ? 17 : 20),
                                      color: s.muted)))
                        ]),
                      if (levelLabel.isNotEmpty) ...[
                        SizedBox(height: Design.px(compact ? 8 : 11)),
                        Text(levelLabel,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: Design.px(compact ? 15 : 18),
                                color: s.accent)),
                      ],
                      SizedBox(height: Design.px(compact ? 10 : 14)),
                      Text('点击查看账号详情',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: Design.px(compact ? 15 : 17),
                              color: s.muted)),
                    ]))
              ]))),
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
        .map((a) => Map<String, dynamic>.from(a))
        .toList();
    final byId = {
      for (final app in available)
        if (app['id'] is String) app['id'] as String: app
    };
    final capacity = card.h <= 2
        ? 4
        : card.h == 3
            ? 8
            : 12;
    final selected = card.shortcutApps.take(capacity).toList();
    Future<void> edit() async {
      if (controller.editing) return;
      final result = await showLauncherSheet<List<String>>(context,
          title: '管理快捷应用',
          subtitle: '选择最多 $capacity 个应用',
          width: Design.px(900),
          height: Design.px(700),
          builder: (_) => _ShortcutPicker(
              apps: available,
              initial: card.shortcutApps,
              capacity: capacity,
              controller: controller));
      if (result != null) await controller.setShortcutApps(card.id, result);
    }

    return _CardCanvas(
        minHeight: 190,
        child: Column(children: [
          Row(children: [
            Expanded(
                child: Text(card.title,
                    style: TextStyle(fontSize: Design.px(23), color: s.muted))),
            IconAction(
                key: ValueKey('shortcuts-edit-${card.id}'),
                icon: Icons.edit_outlined,
                label: '管理快捷应用',
                size: Design.px(38),
                onTap: controller.editing ? null : edit),
          ]),
          SizedBox(height: Design.px(8)),
          Expanded(
              child: GridView.count(
                  crossAxisCount: 4,
                  childAspectRatio: card.h <= 2 ? 1.05 : 1.12,
                  mainAxisSpacing: Design.px(4),
                  crossAxisSpacing: Design.px(4),
                  children: [
                for (final id in selected)
                  Builder(builder: (context) {
                    final app = byId[id];
                    final bytes = app?['iconBytes'];
                    final name =
                        app == null ? '应用不可用' : controller.appName(app);
                    return InkWell(
                        key: ValueKey('shortcut-$id'),
                        onTap: controller.editing || app == null
                            ? null
                            : () => controller.command('launch-app', value: id),
                        child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Expanded(
                                  child: Center(
                                      child: bytes is Uint8List
                                          ? Image.memory(bytes,
                                              width: Design.px(50),
                                              height: Design.px(50),
                                              errorBuilder: (_, __, ___) =>
                                                  Icon(Icons.apps,
                                                      color: s.muted))
                                          : Icon(Icons.apps,
                                              size: Design.px(40),
                                              color: s.muted))),
                              Text(name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                      fontSize: Design.px(16), color: s.muted)),
                            ]));
                  }),
                if (selected.length < capacity)
                  IconButton(
                      key: ValueKey('shortcuts-add-${card.id}'),
                      tooltip: '添加应用',
                      onPressed: controller.editing ? null : edit,
                      icon: const Icon(Icons.add_circle_outline)),
              ])),
        ]));
  }
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
