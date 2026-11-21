import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uni_launcher/controller/launcher_controller.dart';
import 'package:uni_launcher/launcher_app.dart';
import 'package:uni_launcher/model/appearance.dart';
import 'package:uni_launcher/widgets/glass_surface.dart';
import 'fake_gateway.dart';

/// 「全部应用」是一整页，压在**桌面**上，不是压在其他卡片上的弹层。
///
/// 暗夜原来把它当弹层做：route 是 opaque，页面底是 s.strong，面板再叠一层
/// 98% 的 sheet 底 —— 桌面根本不绘制，玻璃无从采样，用户看到的就是一块
/// 均匀的灰板（2026-11-19 实车反馈）。这里锁住三件事：route 不拦桌面、
/// 页面底透明、面板只留一层整页玻璃。
void main() {
  Future<(LauncherController, FakeGateway)> setup(
      WidgetTester t, Appearance appearance) async {
    t.view.physicalSize = const Size(1920, 1080);
    t.view.devicePixelRatio = 1;
    final g = FakeGateway();
    g.state['globalDock'] = {
      'enabled': false,
      'running': false,
      'allowed': true,
      'panel': '',
      'panelRevision': 0
    };
    g.state['apps'] = <Map<String, dynamic>>[
      {'id': 'test.player/.Main', 'package': 'test.player', 'label': '测试播放器'}
    ];
    final c = LauncherController(g);
    await c.initialize();
    c.setAppearance(appearance, save: false);
    addTearDown(() async {
      await t.pumpWidget(const SizedBox.shrink());
      c.dispose();
      await g.dispose();
      t.view.resetPhysicalSize();
      t.view.resetDevicePixelRatio();
    });
    return (c, g);
  }

  Future<void> openApps(WidgetTester t, LauncherController c) async {
    await t.pumpWidget(LauncherApp(controller: c));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('all-apps')));
    await t.pumpAndSettle();
  }

  for (final (label, appearance) in <(String, Appearance)>[
    ('暗夜深色', const Appearance(mode: 'dark', themeStyle: 'nocturne',
        wallpaper: 'coastal')),
    ('暗夜浅色', const Appearance(mode: 'light', themeStyle: 'nocturne',
        wallpaper: 'coastal')),
  ]) {
    testWidgets('$label：全部应用透出桌面，不套弹层实底', (t) async {
      final (c, _) = await setup(t, appearance);
      await openApps(t, c);

      // route 必须非 opaque：opaque 的 route 根本不绘制下层桌面，整页就只剩
      // 自己那层底，壁纸一点都透不上来。
      final route = ModalRoute.of(
          t.element(find.byKey(const ValueKey('apps-panel'))))!;
      expect(route.opaque, isFalse, reason: '整页不能挡住桌面');

      // 整页玻璃：page 而不是 sheet（sheet 会给 98% 实底）。
      final material = t.widget<GlassSurface>(
          find.byKey(const ValueKey('apps-page-material')));
      expect(material.page, isTrue);
      expect(material.sheet, isFalse);
      // 和设置页那两栏同一档：只一层半透明底 + 细描边，不许加模糊。
      expect(
          find.descendant(
              of: find.byKey(const ValueKey('apps-page-material')),
              matching: find.byType(BackdropFilter)),
          findsNothing,
          reason: '整页不做磨砂，壁纸要看得清');

      // 内层面板不再画第二张玻璃卡（否则两层实底叠加，桌面又没了），
      // 只留和设置页 `SettingBlock` 同一档的淡块：网格区要浮在整页底上。
      expect(t.widget(find.byKey(const ValueKey('apps-panel'))),
          isNot(isA<GlassSurface>()));

      // 页面底板也不能是实色。
      final page = t.widget<Scaffold>(find
          .ancestor(
              of: find.byKey(const ValueKey('apps-page-material')),
              matching: find.byType(Scaffold))
          .first);
      expect(page.backgroundColor, Colors.transparent);
      expect(t.takeException(), isNull);
    });
  }

  testWidgets('经典皮肤保持原样：不套整页玻璃，route 仍不透明', (t) async {
    final (c, _) = await setup(
        t, const Appearance(mode: 'dark', themeStyle: 'classic'));
    await openApps(t, c);

    expect(find.byKey(const ValueKey('apps-page-material')), findsNothing);
    final route =
        ModalRoute.of(t.element(find.byKey(const ValueKey('apps-panel'))))!;
    expect(route.opaque, isTrue);
    expect(t.takeException(), isNull);
  });
}
