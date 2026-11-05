import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uni_launcher/controller/launcher_controller.dart';
import 'package:uni_launcher/launcher_app.dart';
import 'package:uni_launcher/theme/launcher_theme.dart';
import 'fake_gateway.dart';

/// 引导被挂住的网关：prelude 立刻返回，bootstrap 等测试放行。
///
/// 真机上的顺序就是这样——外观一行偏好就能给出来，完整快照要等适配器。
class _TwoPhaseGateway extends FakeGateway {
  final preludeGate = Completer<void>();
  final bootstrapGate = Completer<void>();
  int preludes = 0;
  @override
  Future<Map<String, dynamic>?> prelude() async {
    await preludeGate.future;
    preludes++;
    return super.prelude();
  }

  @override
  Future<Map<String, dynamic>> bootstrap() async {
    await bootstrapGate.future;
    return super.bootstrap();
  }
}

String design({required String themeStyle, required String desktopName}) =>
    jsonEncode({
      'preferences': {
        'themeStyle': themeStyle,
        'desktopName': desktopName,
      },
      'cards': <dynamic>[],
    });

void main() {
  testWidgets('prelude 先到：首帧就是正确主题，bootstrap 之后才补齐', (t) async {
    t.view.physicalSize = const Size(1920, 1080);
    t.view.devicePixelRatio = 1;
    final g = _TwoPhaseGateway();
    g.state = {
      ...g.state,
      'savedDesign': design(themeStyle: 'nocturne', desktopName: 'Prelude 桌面')
    };
    final c = LauncherController(g);
    addTearDown(() async {
      await t.pumpWidget(const SizedBox.shrink());
      c.dispose();
      await g.dispose();
      t.view.resetPhysicalSize();
      t.view.resetDevicePixelRatio();
    });

    final pending = c.initialize();
    await t.pumpWidget(LauncherApp(controller: c));
    // 引导还没回来：根组件给的和 launch_background 同色的兜底画布。
    expect(c.designReady, isFalse);
    expect(find.byType(MaterialApp), findsNothing);

    g.preludeGate.complete();
    await t.pump();
    await t.pump();
    // prelude 到了：外观已经是 nocturne，界面挂上去了，bootstrap 仍在等。
    expect(g.preludes, 1);
    expect(c.designReady, isTrue);
    expect(c.appearance.themeStyle, 'nocturne');
    expect(c.appearance.desktopName, 'Prelude 桌面');
    expect(find.byType(MaterialApp), findsOneWidget);
    expect(c.ready, isFalse);

    g.bootstrapGate.complete();
    await pending;
    await t.pumpAndSettle();
    expect(c.ready, isTrue);
    expect(find.byType(MaterialApp), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('遥测通知不再重建卡片树，外观变化才会', (t) async {
    t.view.physicalSize = const Size(1920, 1080);
    t.view.devicePixelRatio = 1;
    final g = FakeGateway(), c = LauncherController(g);
    await c.initialize();
    await t.pumpWidget(LauncherApp(controller: c));
    await t.pumpAndSettle();
    addTearDown(() async {
      await t.pumpWidget(const SizedBox.shrink());
      c.dispose();
      await g.dispose();
      t.view.resetPhysicalSize();
      t.view.resetDevicePixelRatio();
    });

    final grid = find.byKey(const ValueKey('desktop-grid-0'));
    final before = t.widget<Stack>(grid);
    // 一条纯遥测：车辆/媒体每几秒就来一条，布局一点没动。
    g.stream.add({
      ...g.state,
      'partial': true,
      'systemStatus': {'volume': 7, 'brightness': 60}
    });
    await t.pump();
    expect(identical(t.widget<Stack>(grid), before), isTrue);

    // 换皮肤：卡片树必须跟着重建（网格点阵、拖放预览用的都是主题色）。
    // 默认外观就是 blueGlass，所以这里换到差异最大的 nocturne。
    c.setAppearance(c.appearance.copyWith(themeStyle: 'nocturne'), save: false);
    await t.pumpAndSettle();
    expect(identical(t.widget<Stack>(grid), before), isFalse);
    expect(t.takeException(), isNull);
  });

  test('画质降级只关实时模糊，配色尺寸都留着', () {
    final g = FakeGateway();
    final c = LauncherController(g);
    addTearDown(() {
      c.dispose();
      g.dispose();
    });
    final a = c.appearance.copyWith(themeStyle: 'classic', glass: true);
    final normal = SurfaceStyle.from(a, false),
        degraded = SurfaceStyle.from(a, false, lowPower: true);
    expect(normal.liveBlur, isTrue);
    expect(degraded.liveBlur, isFalse);
    // 降级必须是「另一个 style」，否则 ThemeData 不换、界面收不到通知。
    expect(degraded == normal, isFalse);
    expect(degraded.accent, normal.accent);
    expect(degraded.radius, normal.radius);
    expect(degraded.surface, normal.surface);
  });
}
