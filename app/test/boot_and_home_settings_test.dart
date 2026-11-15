import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uni_launcher/controller/launcher_controller.dart';
import 'package:uni_launcher/launcher_app.dart';
import 'package:uni_launcher/screens/settings_screen.dart';
import 'package:uni_launcher/widgets/choice_button.dart';
import 'package:uni_launcher/widgets/glass_surface.dart';
import 'fake_gateway.dart';

/// 两页布局：导航卡在第 1 页，第 2 页放一张卡把页数撑出来。
/// [bootPage] 原样写进 preferences，`-1` 就是「上次停留」。
String bootDesign({required int bootPage}) => jsonEncode({
      'version': 6,
      'preferences': {'custom': '#38A4A0', 'bootPage': bootPage},
      'ambientLight': <String, dynamic>{},
      'cards': [
        {
          'id': 'nav-1',
          'type': 'nav',
          'title': '导航',
          'x': 0,
          'y': 0,
          'w': 8,
          'h': 6,
          'page': 0
        },
        {
          'id': 'music-1',
          'type': 'music',
          'title': '正在播放',
          'x': 0,
          'y': 0,
          'w': 4,
          'h': 4,
          'page': 1
        },
      ],
      'pageCount': 2,
      'appNames': <String, dynamic>{},
    });

void main() {
  testWidgets('BootAndHomeSettings displays toggles and dispatches commands',
      (tester) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1;
    final gateway = FakeGateway();
    gateway.state['integrationPreferences'] = {
      'bootAutostart': true,
      'homeKeyTarget': 'uni',
    };
    final controller = LauncherController(gateway);
    await controller.initialize();
    await tester.pumpWidget(LauncherApp(controller: controller));
    await tester.pumpAndSettle();
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
      await gateway.dispose();
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    expect(controller.bootAutostart, isTrue);
    expect(controller.homeKeyTarget, equals('uni'));

    // Navigate to settings -> dock tab
    controller.openSettings();
    controller.tab('dock');
    await tester.pumpAndSettle();

    // Verify BootAndHomeSettings widgets exist by scrolling them into view
    final dockScrollable = find.descendant(
        of: find.byType(DockSettings), matching: find.byType(Scrollable));
    final bootSwitchFinder = find.byKey(const ValueKey('boot-autostart-switch'));
    await tester.scrollUntilVisible(bootSwitchFinder, 300,
        scrollable: dockScrollable);
    expect(bootSwitchFinder, findsOneWidget);

    final uniTargetFinder = find.byKey(const ValueKey('home-target-uni'));
    final oemTargetFinder = find.byKey(const ValueKey('home-target-oem'));
    expect(uniTargetFinder, findsOneWidget);
    expect(oemTargetFinder, findsOneWidget);

    // 统一控件标准：开关必须是 46×26 自绘那颗、档位必须是 ChoiceButton，
    // 不许再退回上游那套 DesignSwitchTile / OutlinedButton 画法。
    final block = find.byType(BootAndHomeSettings);
    expect(
        find.descendant(of: block, matching: find.byType(DesignSwitchTile)),
        findsNothing);
    expect(find.descendant(of: block, matching: find.byType(DesignSwitch)),
        findsOneWidget);
    // HOME 键两颗档位 + 开机页（上次停留 + 当前页数）。
    expect(find.descendant(of: block, matching: find.byType(ChoiceButton)),
        findsNWidgets(2 + 1 + controller.pageCount));

    final openSettingsFinder =
        find.byKey(const ValueKey('open-home-settings-button'));
    await tester.scrollUntilVisible(openSettingsFinder, 300,
        scrollable: dockScrollable);
    expect(openSettingsFinder, findsOneWidget);

    // Tap boot autostart switch to turn it off
    await tester.tap(bootSwitchFinder);
    await tester.pumpAndSettle();
    expect(
        gateway.commands
            .any((c) => c['action'] == 'boot-autostart' && c['enabled'] == false),
        isTrue);
    expect(tester.widget<DesignSwitch>(bootSwitchFinder).value, isFalse);

    // Tap OEM target
    await tester.tap(oemTargetFinder);
    await tester.pumpAndSettle();
    expect(
        gateway.commands
            .any((c) => c['action'] == 'home-key-target' && c['value'] == 'oem'),
        isTrue);
    // 点完必须真的切过去：原生落 prefs → publish → 选中态跟着走。
    // 少这一段就是「按下去按钮没反应」——预览网关漏了这条命令时就是这样。
    expect(tester.widget<ChoiceButton>(oemTargetFinder).selected, isTrue);
    expect(tester.widget<ChoiceButton>(uniTargetFinder).selected, isFalse);

    // 开机进入：点「第 2 页」要真的选中，并把选择落进设计 JSON。
    final bootSecond = find.byKey(const ValueKey('boot-page-1'));
    await tester.scrollUntilVisible(bootSecond, 300,
        scrollable: dockScrollable);
    await tester.tap(bootSecond);
    await tester.pumpAndSettle();
    expect(tester.widget<ChoiceButton>(bootSecond).selected, isTrue);
    expect(
        tester
            .widget<ChoiceButton>(find.byKey(const ValueKey('boot-page-last')))
            .selected,
        isFalse);
    expect(gateway.saved, contains('"bootPage":1'));

    // Tap Open home settings button
    await tester.tap(openSettingsFinder);
    await tester.pumpAndSettle();
    expect(
        gateway.commands.any((c) => c['action'] == 'open-home-settings'),
        isTrue);
  });

  testWidgets('BootAndHomeSettings supports custom third-party launchers',
      (tester) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1;
    final gateway = FakeGateway();
    gateway.state['integrationPreferences'] = {
      'bootAutostart': true,
      'homeKeyTarget': 'xyz.i4o.uni.launcher',
      'homeApps': [
        {'package': 'xyz.i4o.uni.launcher', 'label': 'UNI 桌面', 'isUni': true},
        {'package': 'ecarx.launcher3', 'label': '原车系统桌面', 'isUni': false},
        {'package': 'com.junjun.carlauncher', 'label': '君君桌面', 'isUni': false},
      ],
    };
    final controller = LauncherController(gateway);
    await controller.initialize();
    await tester.pumpWidget(LauncherApp(controller: controller));
    await tester.pumpAndSettle();
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
      await gateway.dispose();
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    controller.openSettings();
    controller.tab('dock');
    await tester.pumpAndSettle();

    final dockScrollable = find.descendant(
        of: find.byType(DockSettings), matching: find.byType(Scrollable));
    final junjunFinder =
        find.byKey(const ValueKey('home-target-com.junjun.carlauncher'));
    await tester.scrollUntilVisible(junjunFinder, 300,
        scrollable: dockScrollable);
    await tester.drag(dockScrollable, const Offset(0, -150));
    await tester.pumpAndSettle();
    expect(junjunFinder, findsOneWidget);

    await tester.tap(junjunFinder);
    await tester.pumpAndSettle();
    expect(
        gateway.commands.any((c) =>
            c['action'] == 'home-key-target' &&
            c['value'] == 'com.junjun.carlauncher'),
        isTrue);
  });

  group('开机进入哪一页', () {
    Future<LauncherController> boot(FakeGateway g) async {
      final c = LauncherController(g);
      await c.initialize();
      addTearDown(() async {
        c.dispose();
        await g.dispose();
      });
      return c;
    }

    test('用户指定的页优先于「上次停留」', () async {
      final g = FakeGateway();
      g.state['savedDesign'] = bootDesign(bootPage: 1);
      g.state['lastDesktopPage'] = 0;
      expect((await boot(g)).page, 1);
    });

    test('「上次停留」读原生记住的那一页', () async {
      final g = FakeGateway();
      g.state['savedDesign'] = bootDesign(bootPage: -1);
      g.state['lastDesktopPage'] = 1;
      expect((await boot(g)).page, 1);
    });

    test('指定页超过实际页数时回落到最后一页，不清空配置', () async {
      final g = FakeGateway();
      // 布局只有 2 页（索引 0/1），却指定了第 6 页。
      g.state['savedDesign'] = bootDesign(bootPage: 5);
      final c = await boot(g);
      expect(c.page, 1);
      expect(c.appearance.bootPage, 5, reason: '页加回来要能自动生效');
    });

    test('老配置没有这个字段时按「上次停留」处理', () async {
      final g = FakeGateway();
      final legacy = jsonDecode(bootDesign(bootPage: -1)) as Map;
      (legacy['preferences'] as Map).remove('bootPage');
      g.state['savedDesign'] = jsonEncode(legacy);
      final c = await boot(g);
      expect(c.appearance.bootPage, -1);
      expect(c.page, 0);
    });

    test('选择会落进设计 JSON 并 clamp 到现有页数', () async {
      final g = FakeGateway();
      g.state['savedDesign'] = bootDesign(bootPage: -1);
      final c = await boot(g);
      await c.setBootPage(1);
      expect(c.appearance.bootPage, 1);
      expect(g.saved, contains('"bootPage":1'));
      // 超出页数的值不该写进去：页数缩小时页码会被 clamp 成最后一页。
      await c.setBootPage(9);
      expect(c.appearance.bootPage, 1);
    });
  });
}
