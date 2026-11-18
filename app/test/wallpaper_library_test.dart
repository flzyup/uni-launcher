import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uni_launcher/controller/launcher_controller.dart';
import 'package:uni_launcher/model/appearance.dart';
import 'package:uni_launcher/theme/launcher_theme.dart';
import 'package:uni_launcher/widgets/choice_button.dart';
import 'package:uni_launcher/widgets/wallpaper_library_sheet.dart';

import 'fake_gateway.dart';

/// 壁纸库（eclipse f28）在三套皮肤下都要能开、能选、能空态。
/// 这是「三主题匹配」契约的回归点：新页面只吃 SurfaceStyle 令牌，
/// 任何一套皮肤下出现不可见元素，这里会先炸。
void main() {
  Future<LauncherController> open(WidgetTester t, String themeStyle) async {
    t.view.physicalSize = const Size(1920, 1080);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    final gateway = FakeGateway();
    final controller = LauncherController(gateway);
    await controller.initialize();
    controller.setAppearance(
        controller.appearance.copyWith(themeStyle: themeStyle), save: false);
    late BuildContext context;
    await t.pumpWidget(MaterialApp(
        theme: launcherTheme(SurfaceStyle.from(controller.appearance, true)),
        home: Scaffold(
            body: Builder(builder: (ctx) {
          context = ctx;
          return const SizedBox.shrink();
        }))));
    showWallpaperLibrary(context, controller);
    await t.pumpAndSettle();
    addTearDown(controller.dispose);
    return controller;
  }

  for (final style in Appearance.themeStyles) {
    testWidgets('$style 皮肤下壁纸库可开、可选、可空态', (t) async {
      final c = await open(t, style);
      expect(find.text('壁纸库'), findsWidgets);
      // 系统预设磁贴按 id 建 key，六张预设 + 本地入口都在。
      expect(find.byKey(const ValueKey('library-wallpaper-graphite')),
          findsOneWidget);
      expect(find.byKey(const ValueKey('library-wallpaper-custom')),
          findsOneWidget);
      // 动态壁纸开关在源码里没有数据源，必须置灰而不是假装能用。
      final dynamicSwitch = t.widget<DesignSwitch>(
          find.byKey(const ValueKey('wallpaper-dynamic-switch')));
      expect(dynamicSwitch.onChanged, isNull);

      await t.tap(find.byKey(const ValueKey('library-wallpaper-graphite')));
      await t.pumpAndSettle();
      expect(c.appearance.wallpaper, 'graphite');

      // 「动态」分类没有任何数据源，落地为空态提示。
      await t.tap(find.byKey(const ValueKey('wallpaper-tab-dynamic')));
      await t.pumpAndSettle();
      expect(find.text('动态壁纸待接入'), findsOneWidget);

      expect(t.takeException(), isNull);
    });
  }

  // 导入本地图片要开系统文件选择器：取消、没权限、或者当前环境根本没有选择器
  // （Windows 预览）都会拿到 null。以前这里直接 return，按下去一点反馈都没有，
  // 看起来就是「按键无效」，所以必须回一句话。
  testWidgets('导入本地图片没拿到图片时给出提示', (t) async {
    final c = await open(t, 'nocturne');
    expect(c.gateway is FakeGateway, isTrue);
    expect((c.gateway as FakeGateway).wallpaper, isNull);

    await t.tap(find.byKey(const ValueKey('wallpaper-import')));
    await t.pumpAndSettle();

    expect(find.textContaining('没有选中图片'), findsOneWidget);
    await t.pump(const Duration(seconds: 3));
    await t.pumpAndSettle();
  });
}
