import 'dart:convert';
import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:uni_launcher/controller/launcher_controller.dart';
import 'package:uni_launcher/model/appearance.dart';
import 'package:uni_launcher/model/card_layout.dart';
import 'package:uni_launcher/theme/launcher_theme.dart';
import 'fake_gateway.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('glass defaults off and migrates missing old preference', () {
    expect(const Appearance().glass, false);
    expect(Appearance.fromJson({'radius': 0}).glass, false);
  });
  test('radius accepts square corners and clamps range', () {
    expect(Appearance.fromJson({'radius': 0}).radius, 0);
    expect(Appearance.fromJson({'radius': 99}).radius, 40);
    expect(Appearance.fromJson({'radius': -2}).radius, 0);
  });
  test('invalid accent and mode fall back to safe defaults', () {
    final a = Appearance.fromJson(
        {'custom': 'red;', 'palette': 'unknown', 'mode': 'other'});
    expect(a.custom, '#38A4A0');
    expect(a.mode, 'system');
    expect(a.palette, 'mint');
  });
  test('wallpaper selection and custom path round trip safely', () {
    final builtIn = Appearance.fromJson(
        const Appearance().copyWith(wallpaper: 'terrain').toJson());
    expect(builtIn.wallpaper, 'terrain');
    final custom = Appearance.fromJson(const Appearance()
        .copyWith(
            wallpaper: 'custom',
            wallpaperPath: '/data/user/wall.jpg',
            wallpaperLuminance: .24)
        .toJson());
    expect(custom.wallpaper, 'custom');
    expect(custom.wallpaperPath, '/data/user/wall.jpg');
    expect(custom.wallpaperLuminance, .24);
    expect(Appearance.fromJson({'wallpaper': 'invalid'}).wallpaper, 'gradient');
    expect(Appearance.fromJson({'wallpaperOverlay': true}).toJson(),
        isNot(contains('wallpaperOverlay')));
  });
  test('smart contrast follows wallpaper while manual themes remain explicit',
      () {
    expect(
        SurfaceStyle.from(
                const Appearance(mode: 'smart', wallpaper: 'neon'), false,
                adaptToWallpaper: true)
            .dark,
        true);
    expect(
        SurfaceStyle.from(
                const Appearance(mode: 'smart', wallpaper: 'precision'), true,
                adaptToWallpaper: true)
            .dark,
        false);
    expect(
        SurfaceStyle.from(
                const Appearance(mode: 'light', wallpaper: 'neon'), true,
                adaptToWallpaper: true)
            .dark,
        false);
    expect(
        SurfaceStyle.from(
                const Appearance(mode: 'dark', wallpaper: 'precision'), false,
                adaptToWallpaper: true)
            .dark,
        true);
  });
  test('renamed app is persisted by package and restored from native store',
      () async {
    final g = FakeGateway(), c = LauncherController(g);
    g.state['apps'] = [
      {'package': 'com.example.music', 'label': '系统名称'}
    ];
    await c.initialize();
    await c.renameApp('com.example.music', '我的音乐');
    expect(c.appNames['com.example.music'], '我的音乐');
    expect(g.commands.last, containsPair('action', 'rename-app'));
    expect(g.commands.last, containsPair('zone', 'com.example.music'));
    expect(jsonDecode(g.saved!)['appNames']['com.example.music'], '我的音乐');

    final next = FakeGateway()
      ..state['savedDesign'] = g.saved
      ..state['appNames'] = {'com.example.music': '我的音乐'}
      ..state['apps'] = [
        {'package': 'com.example.music', 'label': '系统名称'}
      ];
    final restored = LauncherController(next);
    await restored.initialize();
    expect(restored.appName(Map<String, dynamic>.from(next.state['apps'][0])),
        '我的音乐');
    c.dispose();
    restored.dispose();
    await g.dispose();
    await next.dispose();
  });
  test('page switch uses lightweight signal without vehicle snapshot rebuild',
      () async {
    final g = FakeGateway(), c = LauncherController(g);
    await c.initialize();
    var nativeRebuilds = 0;
    c.native.addListener(() => nativeRebuilds++);
    c.switchPage(1);
    await Future<void>.delayed(Duration.zero);
    expect(c.pageChanged.value, 1);
    expect(nativeRebuilds, 0);
    expect(g.commands.last, containsPair('action', 'desktop-page'));
    c.dispose();
    await g.dispose();
  });
  test('page switch waits for native hide and Home cancels an in-flight switch',
      () async {
    final g = _DelayedPageGateway(), c = LauncherController(g);
    await c.initialize();
    final first = c.switchPage(1);
    expect(c.page, 0,
        reason: 'native map must be hidden before Flutter paints another page');
    g.pending.single.complete();
    await first;
    expect(c.page, 1);
    final second = c.switchPage(0);
    c.home();
    g.pending.last.complete();
    await second;
    expect(c.page, 0);
    final cancelled = c.switchPage(1);
    c.home();
    g.pending.last.complete();
    await cancelled;
    expect(c.page, 0, reason: 'a delayed platform reply cannot undo Home');
    c.dispose();
    await g.dispose();
  });
  test('default OEM layout has no overlap', () {
    expect(validLayout(defaultCards()), true);
    expect(defaultCards().length, 9);
    final firstPage = defaultCards().where((card) => card.page == 0).toList();
    expect(
        firstPage.map((card) => card.type), ['nav', 'music', 'trafficLight']);
    final clockWeather =
        defaultCards().singleWhere((card) => card.type == 'clockWeather');
    expect((
      clockWeather.page,
      clockWeather.x,
      clockWeather.y,
      clockWeather.w,
      clockWeather.h,
      clockWeather.layout
    ), (
      1,
      8,
      0,
      4,
      3,
      'combined'
    ));
    final shortcut =
        defaultCards().singleWhere((card) => card.type == 'shortcuts');
    expect((shortcut.page, shortcut.x, shortcut.y, shortcut.w, shortcut.h),
        (1, 0, 3, 4, 3));
    final signal = firstPage.last;
    expect((signal.x, signal.y, signal.w, signal.h), (8, 4, 4, 2));
  });
  test('saved weather layout remains intact until reset', () async {
    final previous = defaultCards()
        .map((card) => card.id == 'traffic-light-1'
            ? const LauncherCard('weather-1', 'weather', '天气', 8, 4, 4, 2, 0)
            : card)
        .toList();
    final gateway = FakeGateway()
      ..state['savedDesign'] = jsonEncode({
        'preferences': <String, dynamic>{},
        'cards': previous.map((card) => card.toJson()).toList(),
      });
    final controller = LauncherController(gateway);
    await controller.initialize();
    expect(controller.cards.any((card) => card.id == 'weather-1'), isTrue);
    expect(
        controller.cards.any((card) => card.type == 'trafficLight'), isFalse);
    controller.resetLayout();
    expect(controller.cards.any((card) => card.type == 'trafficLight'), isTrue);
    controller.dispose();
    await gateway.dispose();
  });
  test('clock and weather layout choice survives design serialization', () {
    const card = LauncherCard(
        'clock-weather', 'clockWeather', '通勤', 0, 0, 4, 3, 0,
        layout: 'stacked');
    final restored = LauncherCard.fromJson(card.toJson());
    expect(restored.layout, 'stacked');
    expect(restored.toJson()['layout'], 'stacked');
    expect(validLayout([restored]), true);
  });
  test('rejects collision, bounds, duplicate identifiers and unknown type', () {
    final cards = defaultCards();
    expect(validLayout([...cards, cards.first]), false);
    expect(validLayout([cards.first.copyWith(x: 11)]), false);
    expect(validLayout([const LauncherCard('x', 'unknown', '', 0, 0, 4, 2, 0)]),
        false);
  });
  test('editing preserves committed layout on cancel', () async {
    final gateway = FakeGateway(), c = LauncherController(gateway);
    await c.initialize();
    c.beginEdit();
    c.remove('traffic-light-1');
    expect(c.cards.length, 8);
    c.cancelEdit();
    expect(c.cards.length, 9);
    c.dispose();
    await gateway.dispose();
  });
  test('adding to full page allocates page; cancel restores page count',
      () async {
    final g = FakeGateway(), c = LauncherController(g);
    await c.initialize();
    c.beginEdit();
    expect(c.add('air'), true);
    expect(c.pageCount, 3);
    expect(c.page, 2);
    c.cancelEdit();
    expect(c.pageCount, 2);
    c.dispose();
    await g.dispose();
  });
  test('edge drag placement moves a card to nearest free cell on any page',
      () async {
    final g = FakeGateway(), c = LauncherController(g);
    await c.initialize();
    c.beginEdit();
    c.remove('air-1');
    expect(
        c.moveToPage('traffic-light-1', 1, preferredX: 8, preferredY: 4), true);
    final moved = c.cards.singleWhere((card) => card.id == 'traffic-light-1');
    expect(moved.page, 1);
    expect(moved.x, 8);
    expect(moved.y, 4);
    expect(c.page, 1);
    expect(validLayout(c.cards), true);
    c.cancelEdit();
    expect(c.cards.singleWhere((card) => card.id == 'traffic-light-1').page, 0);
    c.dispose();
    await g.dispose();
  });
  test('empty trailing editor pages are not persisted or restored', () async {
    final g = FakeGateway(), c = LauncherController(g);
    await c.initialize();
    c.beginEdit();
    c.newPage();
    expect(c.pageCount, 3);
    c.finishEdit();
    expect(c.pageCount, 2);
    expect(c.page, 1);
    await c.persist();
    final saved = jsonDecode(g.saved!);
    saved['pageCount'] = 7;
    final next = FakeGateway()..state['savedDesign'] = jsonEncode(saved);
    final restored = LauncherController(next);
    await restored.initialize();
    expect(restored.pageCount, 2);
    c.dispose();
    restored.dispose();
    await g.dispose();
    await next.dispose();
  });
  test('glass and theme persist through native repository and reload',
      () async {
    final g = FakeGateway(), c = LauncherController(g);
    await c.initialize();
    c.setAppearance(
        c.appearance.copyWith(glass: true, palette: 'blue', radius: 0));
    await c.persist();
    expect(jsonDecode(g.saved!)['preferences']['glass'], true);
    final next = FakeGateway();
    next.state['savedDesign'] = g.saved;
    final loaded = LauncherController(next);
    await loaded.initialize();
    expect(loaded.appearance.glass, true);
    expect(loaded.appearance.radius, 0);
    expect(loaded.appearance.palette, 'blue');
    c.dispose();
    loaded.dispose();
    await g.dispose();
    await next.dispose();
  });
}

class _DelayedPageGateway extends FakeGateway {
  final pending = <Completer<void>>[];
  @override
  Future<void> setDesktopPage(int page) {
    final gate = Completer<void>();
    pending.add(gate);
    return gate.future;
  }
}
