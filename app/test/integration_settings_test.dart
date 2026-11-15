import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uni_launcher/controller/launcher_controller.dart';
import 'package:uni_launcher/theme/launcher_theme.dart';
import 'package:uni_launcher/widgets/choice_button.dart';
import 'package:uni_launcher/widgets/integration_settings.dart';

import 'fake_gateway.dart';

/// 导航与媒体页里那几颗新增开关必须真的接到原生：点下去要发命令、原生落
/// prefs 后要能回读，而不是点完被下一次快照弹回原位（那看起来就是「哑开关」）。
void main() {
  Future<(LauncherController, FakeGateway)> boot(WidgetTester t) async {
    t.view.physicalSize = const Size(1920, 1080);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    final gateway = FakeGateway();
    final controller = LauncherController(gateway);
    await controller.initialize();
    addTearDown(controller.dispose);
    await t.pumpWidget(MaterialApp(
        theme: launcherTheme(SurfaceStyle.from(controller.appearance, true)),
        home: Scaffold(
            body: ValueListenableBuilder<Map<String, dynamic>>(
          valueListenable: controller.native,
          builder: (context, native, _) =>
              IntegrationSettings(controller: controller, native: native),
        ))));
    await t.pumpAndSettle();
    return (controller, gateway);
  }

  testWidgets('仪表自带媒体控件默认关，打开后命令下发且开关回读为开', (t) async {
    final (_, gateway) = await boot(t);

    final before = t.widget<DesignSwitch>(
        find.byKey(const ValueKey('dim-cluster-switch')));
    expect(before.value, isFalse, reason: '这是第三条链路，默认不接管');

    before.onChanged!(true);
    await t.pumpAndSettle();
    expect(
        gateway.commands.any((cmd) =>
            cmd['action'] == 'dim-cluster' && cmd['enabled'] == true),
        isTrue,
        reason: 'point 下去必须发 dim-cluster 命令');

    final after = t.widget<DesignSwitch>(
        find.byKey(const ValueKey('dim-cluster-switch')));
    expect(after.value, isTrue, reason: '原生 publish 后开关要跟着亮');
    expect(t.takeException(), isNull);
  });

  testWidgets('方向盘接管与仪表同步两颗开关各自独立，互不影响', (t) async {
    final (_, gateway) = await boot(t);

    t.widget<DesignSwitch>(
            find.byKey(const ValueKey('steering-keys-switch')))
        .onChanged!(false);
    await t.pumpAndSettle();
    expect(
        gateway.commands.any((cmd) =>
            cmd['action'] == 'steering-keys' && cmd['enabled'] == false),
        isTrue);
    // 关方控不该顺手关掉仪表同步。
    expect(
        t
            .widget<DesignSwitch>(
                find.byKey(const ValueKey('instrument-sync-switch')))
            .value,
        isTrue);
    expect(t.takeException(), isNull);
  });
}
