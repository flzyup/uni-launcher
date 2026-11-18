class CardSpec {
  final String type, label, source;
  final int w, h, minW, minH;
  const CardSpec(
      this.type, this.label, this.source, this.w, this.h, this.minW, this.minH);
}

const cardSpecs = [
  CardSpec('nav', '导航', '原车导航服务', 8, 6, 6, 3),
  // minH 放到 1：一格高时两张卡都不画卡头，只留一行内容（灯态读数 / 封面
  // 与曲目）。默认尺寸不变，库里放进去仍是 4×2 / 4×3。
  CardSpec('trafficLight', '红绿灯', '高德路口信号', 4, 2, 4, 1),
  CardSpec('music', '音乐', '原车媒体中心', 4, 3, 3, 1),
  CardSpec('weather', '天气', '原车天气', 4, 2, 3, 2),
  CardSpec('calendar', '日历', '原车日历', 4, 3, 3, 2),
  CardSpec('member', '领克账号', '原车账号中心', 4, 6, 3, 3),
  CardSpec('cleanup', '系统清理', '原车安全中心', 4, 3, 3, 2),
  CardSpec('tpms', '胎压', '原车车辆信息', 4, 6, 4, 3),
  CardSpec('body', '车况与胎压', '车辆状态', 4, 3, 4, 3),
  CardSpec('battery', '动力电池', '原车动力电池', 4, 3, 3, 2),
  CardSpec('fuel', '剩余油量', '原车油量', 4, 3, 3, 2),
  CardSpec('air', '车内空气', '原车空气质量', 4, 3, 3, 2),
  CardSpec('ride', '出行服务', '其他车型的原厂出行服务', 4, 3, 3, 2),
  CardSpec('clock', '时钟', '系统时间', 4, 2, 3, 2),
  CardSpec('clockWeather', '时钟与天气', '系统时间与天气服务', 4, 3, 3, 2),
  // minH 从 2 放到 1：卡片小于 4×3 时整张卡按「一行大图标」画、没有卡头，
  // 两格高会在图标上下留一大片空。默认高度仍是 2（库里的规格不变）。
  CardSpec('shortcuts', '快捷应用', '系统应用', 4, 2, 3, 1),
  CardSpec('vehicle', '行车信息', '原车车辆信息', 4, 3, 3, 2),
];
final librarySpecs =
    cardSpecs.where((s) => s.type != 'ride').toList(growable: false);
CardSpec specFor(String type) => cardSpecs.firstWhere((s) => s.type == type);

class LauncherCard {
  final String id, type, title;
  final String layout;
  final List<String> shortcutApps;
  final int x, y, w, h, page;
  const LauncherCard(
      this.id, this.type, this.title, this.x, this.y, this.w, this.h, this.page,
      {this.layout = '', this.shortcutApps = const []});
  LauncherCard copyWith(
          {String? title,
          String? layout,
          List<String>? shortcutApps,
          int? x,
          int? y,
          int? w,
          int? h,
          int? page}) =>
      LauncherCard(id, type, title ?? this.title, x ?? this.x, y ?? this.y,
          w ?? this.w, h ?? this.h, page ?? this.page,
          layout: layout ?? this.layout,
          shortcutApps: shortcutApps ?? this.shortcutApps);
  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type,
        'title': title,
        'x': x,
        'y': y,
        'w': w,
        'h': h,
        'page': page,
        if (layout.isNotEmpty) 'layout': layout,
        if (shortcutApps.isNotEmpty) 'shortcutApps': shortcutApps,
      };
  factory LauncherCard.fromJson(Map<String, dynamic> j) => LauncherCard(
      j['id'] as String,
      j['type'] as String,
      j['title'] as String? ?? '',
      j['x'] as int,
      j['y'] as int,
      j['w'] as int,
      j['h'] as int,
      j['page'] as int,
      layout: j['layout'] as String? ?? '',
      shortcutApps:
          (j['shortcutApps'] is List ? j['shortcutApps'] as List : const [])
              .whereType<String>()
              .where((id) => id.isNotEmpty && id.length <= 512)
              .toSet()
              .take(12)
              .toList());
  bool get inBounds {
    if (!cardSpecs.any((s) => s.type == type)) return false;
    final s = specFor(type);
    return x >= 0 &&
        y >= 0 &&
        w >= s.minW &&
        h >= s.minH &&
        x + w <= 12 &&
        y + h <= 6 &&
        page >= 0 &&
        page < 20;
  }

  bool overlaps(LauncherCard b) =>
      page == b.page &&
      x < b.x + b.w &&
      x + w > b.x &&
      y < b.y + b.h &&
      y + h > b.y;
}

List<LauncherCard> defaultCards() => const [
      LauncherCard('nav-1', 'nav', '导航', 0, 0, 8, 6, 0),
      LauncherCard('music-1', 'music', '正在播放', 8, 0, 4, 4, 0),
      LauncherCard('traffic-light-1', 'trafficLight', '红绿灯', 8, 4, 4, 2, 0),
      LauncherCard('body-1', 'body', '车况与胎压', 0, 0, 4, 3, 1),
      LauncherCard('battery-1', 'battery', '动力电池', 4, 0, 4, 3, 1),
      LauncherCard('clock-weather-1', 'clockWeather', '时钟与天气', 8, 0, 4, 3, 1,
          layout: 'combined'),
      LauncherCard('shortcuts-1', 'shortcuts', '快捷应用', 0, 3, 4, 3, 1),
      LauncherCard('vehicle-1', 'vehicle', '行车信息', 4, 3, 4, 3, 1),
      LauncherCard('air-1', 'air', '车内空气', 8, 3, 4, 3, 1),
      // 默认只给两页。f3 那屏（大时钟 8×6 + 天气 + 日历）不再预置：主屏铺满
      // 三页反而显得空，谁想要自己从「添加卡片」里拖——clock / weather /
      // calendar 三种 CardSpec 都还在目录里。编辑器翻到草稿页放卡时 pageCount
      // 才会 +1，所以不给默认卡就不会出现第 3 页。
      //
      // 老布局里预置的那三张由 `_stripLegacyDefaultPage3` 清掉（仅当那一页
      // 没有用户自己加的卡）。
    ].toList();

/// 旧版本预置在第 3 页（page == 2）的默认卡。
///
/// 只在「第 3 页上全是这几张」时清掉——用户自己往里加过任何一张卡就整页保留，
/// 那是他的布局，不该被我们顺手删掉。
const legacyDefaultPage3Ids = {'clock-1', 'weather-1', 'calendar-1'};

/// 返回清理后的卡片表；没有可清的就原样返回同一个 list。
List<LauncherCard> stripLegacyDefaultPage3(List<LauncherCard> cards) {
  final onPage3 = cards.where((c) => c.page == 2).toList();
  if (onPage3.isEmpty) return cards;
  if (!onPage3.every((c) => legacyDefaultPage3Ids.contains(c.id))) return cards;
  return [
    for (final c in cards)
      if (c.page != 2) c
  ];
}
bool validLayout(List<LauncherCard> cards) {
  if (cards.length > 200 ||
      cards.map((c) => c.id).toSet().length != cards.length) return false;
  for (int i = 0; i < cards.length; i++) {
    if (!cards[i].inBounds) return false;
    for (int j = i + 1; j < cards.length; j++) {
      if (cards[i].overlaps(cards[j])) return false;
    }
  }
  return true;
}
