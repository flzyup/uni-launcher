import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uni_launcher/controller/launcher_controller.dart';
import 'package:uni_launcher/model/appearance.dart';
import 'package:uni_launcher/theme/design_tokens.dart';
import 'package:uni_launcher/theme/launcher_theme.dart';
import 'package:uni_launcher/widgets/glass_surface.dart';
import 'package:uni_launcher/widgets/launcher_dialog.dart';
import 'package:uni_launcher/widgets/navigation_app_picker.dart';
import 'package:uni_launcher/widgets/picker_row.dart';

import 'fake_gateway.dart';

/// 选择器弹层的版式取自 `theme-styles/eclipse/simulator.html` 的 `.dlg.pick`：
/// 600 宽、行高 64、图标 42、选中项带「使用中」角标、底部一行说明。
void main() {
  Future<(LauncherController, FakeGateway)> setup(WidgetTester t) async {
    t.view.physicalSize = const Size(1920, 1080);
    t.view.devicePixelRatio = 1;
    final g = FakeGateway();
    g.state['apps'] = [
      {
        'id': 'only.map/.MainActivity',
        'package': 'only.map',
        'label': '唯一地图'
      },
      {
        'id': 'other.app/.MainActivity',
        'package': 'other.app',
        'label': '其他应用'
      }
    ];
    g.state['navigation'] = {
      'package': 'only.map',
      'preferredPackage': 'only.map',
      'label': '唯一地图',
      'options': [
        {'package': 'only.map', 'label': '唯一地图'}
      ],
      'canEmbed': false
    };
    final c = LauncherController(g);
    await c.initialize();
    addTearDown(() async {
      await t.pumpWidget(const SizedBox.shrink());
      c.dispose();
      await g.dispose();
      t.view.resetPhysicalSize();
      t.view.resetDevicePixelRatio();
    });
    return (c, g);
  }

  /// 只挂弹层本身：版式断言不该被桌面卡片布局干扰。
  Future<void> pumpSheet(WidgetTester t, LauncherController c) async {
    await t.pumpWidget(MaterialApp(
        theme: launcherTheme(SurfaceStyle.from(const Appearance(), true)),
        home: Scaffold(
            body: LauncherSheet(
                title: '选择导航应用',
                closeLabel: '关闭面板',
                width: Design.px(720),
                compact: true,
                child: NavigationAppPicker(controller: c)))));
    await t.pumpAndSettle();
  }

  testWidgets('navigation picker follows the design sheet geometry',
      (t) async {
    final (c, _) = await setup(t);
    await pumpSheet(t, c);

    // 600 宽：稿子 `.dlg.pick{width:600px}`。
    final sheet = find.byWidgetPredicate((w) => w is GlassSurface && w.sheet);
    expect(t.getSize(sheet).width, closeTo(600, .5));

    // 标题 19 / 词距 .04em，不再是通用弹层的 28。
    final title = t.widget<Text>(find.text('选择导航应用'));
    expect(title.style?.fontSize, closeTo(19, .01));
    expect(title.style?.fontWeight, FontWeight.w500);

    // 行高 64、图标 42。
    expect(t.getSize(find.byKey(const ValueKey('nav-option-auto'))).height,
        closeTo(64, .5));
    expect(t.getSize(find.byType(PickerIcon).first), const Size(42, 42));

    // 选中项有「使用中」角标，且整行是 5.5% 墨色底。
    expect(find.text('使用中'), findsOneWidget);
    final row = t.widget<Container>(find.descendant(
        of: find.byKey(const ValueKey('nav-option-only.map')),
        matching: find.byType(Container)).first);
    expect((row.decoration as BoxDecoration?)?.color?.a, closeTo(.055, .002));

    // 稿子底部的说明。
    expect(find.textContaining('切换后地图卡与红绿灯卡同步换源'), findsOneWidget);

    // 无关应用默认不出现，展开「其他已安装应用」后才列出来。
    expect(find.byKey(const ValueKey('nav-show-all')), findsOneWidget);
    expect(find.byKey(const ValueKey('nav-option-other.app')), findsNothing);
    await t.tap(find.byKey(const ValueKey('nav-show-all')));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('nav-option-other.app')), findsOneWidget);
  });

  testWidgets('picker sheet height follows its content instead of a fixed box',
      (t) async {
    final (c, _) = await setup(t);
    await pumpSheet(t, c);
    final sheet = find.byWidgetPredicate((w) => w is GlassSurface && w.sheet);
    // 两行（自动选择 + 一个地图）+ 说明，远低于旧版写死的 541。
    expect(t.getSize(sheet).height, lessThan(Design.px(650)));
  });
}
