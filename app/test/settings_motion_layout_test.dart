import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uni_launcher/controller/launcher_controller.dart';
import 'package:uni_launcher/launcher_app.dart';
import 'package:uni_launcher/widgets/settings_cards.dart';

import 'fake_gateway.dart';

/// sim f12（动画与频谱）的分区排布：五张翻屏卡 + 四张频谱卡各自一行排开，
/// 尺寸等宽。设计稿是 `flex:1 + min-width:180`，所以「一行放得下就一行」，
/// 放不下才掉行——这里钉住 1920 下的行数与等宽，防止以后改回两列/三列。
void main() {
  Future<(LauncherController, FakeGateway)> openMotion(WidgetTester t,
      {String theme = 'nocturne'}) async {
    t.view.physicalSize = const Size(1920, 1080);
    t.view.devicePixelRatio = 1;
    final g = FakeGateway();
    g.state['demo'] = false;
    final c = LauncherController(g);
    await c.initialize();
    c.setAppearance(c.appearance.copyWith(themeStyle: theme), save: false);
    await t.pumpWidget(LauncherApp(controller: c));
    c.openSettings();
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('tab-motion')));
    await t.pumpAndSettle();
    addTearDown(() async {
      await t.pumpWidget(const SizedBox.shrink());
      c.dispose();
      await g.dispose();
      t.view.resetPhysicalSize();
      t.view.resetDevicePixelRatio();
    });
    return (c, g);
  }

  void expectOneRow(WidgetTester t, List<String> keys) {
    final rects = [
      for (final key in keys)
        t.getRect(find.byKey(ValueKey(key))),
    ];
    for (final rect in rects) {
      expect(rect.top, closeTo(rects.first.top, .5), reason: '$keys 不在同一行');
      expect(rect.width, closeTo(rects.first.width, .5), reason: '$keys 不等宽');
    }
  }

  testWidgets('five page-transition cards sit on one row', (t) async {
    await openMotion(t);
    expectOneRow(t, [
      'transition-slide',
      'transition-fade',
      'transition-zoom',
      'transition-depth',
      'transition-none',
    ]);
    // 每张卡都要有静态小样，不能只剩文字。
    expect(find.byType(PageEffectPreview), findsNWidgets(5));
    expect(t.takeException(), isNull);
  });

  testWidgets('four spectrum cards sit on one row', (t) async {
    await openMotion(t);
    await t.ensureVisible(find.byKey(const ValueKey('spectrum-style-bars')));
    await t.pumpAndSettle();
    expectOneRow(t, [
      'spectrum-style-bars',
      'spectrum-style-segments',
      'spectrum-style-mirror',
      'spectrum-style-outline',
    ]);
    expect(t.takeException(), isNull);
  });

  testWidgets('tapping a transition card still writes the setting', (t) async {
    final (c, _) = await openMotion(t);
    await t.tap(find.byKey(const ValueKey('transition-depth')));
    await t.pumpAndSettle();
    expect(c.appearance.pageTransition, 'depth');
    expect(t.takeException(), isNull);
  });
}
