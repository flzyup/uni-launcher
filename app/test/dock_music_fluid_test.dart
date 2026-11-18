import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uni_launcher/controller/launcher_controller.dart';
import 'package:uni_launcher/model/appearance.dart';
import 'package:uni_launcher/theme/launcher_theme.dart';
import 'package:uni_launcher/widgets/bottom_dock.dart';
import 'fake_gateway.dart';

/// 底栏音乐条那一块：暗夜走 `fluid_progress.frag` 的烟雾流体，浅色回落细渐变。
///
/// 2026-11-13 实车反馈「拨开关还是老进度条」——原因是流体被帧预算降级
/// （`SurfaceStyle.lowPower`）一并关掉了，而用户看到的现象正是「和另外两套皮肤
/// 一样的进度条」。这里把两条都钉住：暗夜即使降级也要出流体；浅色仍然不画。
void main() {
  Future<String> painterOf(WidgetTester t, Appearance look) async {
    t.view.physicalSize = const Size(1600, 96);
    t.view.devicePixelRatio = 1;
    final g = FakeGateway();
    g.state['media'] = {
      ...(g.state['media'] as Map<String, dynamic>),
      'positionMs': 60000,
      'durationMs': 269000,
      'playing': true,
      'canNext': true,
      'canPrevious': true,
      'canToggle': true,
    };
    final c = LauncherController(g);
    await c.initialize();
    c.setAppearance(look, save: false);
    final style = SurfaceStyle.from(look, true,
        lowPower: look.themeStyle == 'nocturne' && _lowPower);
    await t.pumpWidget(MaterialApp(
        theme: launcherTheme(style),
        home: Scaffold(
            body: SizedBox(
                width: 1600, height: 96, child: BottomDock(controller: c)))));
    // 等 shader 那一次异步加载落定。
    await t.pump(const Duration(milliseconds: 400));
    await t.pump(const Duration(milliseconds: 400));
    final found =
        find.byKey(const ValueKey('dock-music-progress'), skipOffstage: false);
    final paint = t.widget<CustomPaint>(found);
    final name = paint.painter.runtimeType.toString();
    await t.pumpWidget(const SizedBox());
    c.dispose();
    await g.dispose();
    return name;
  }

  testWidgets('暗夜降级时仍然画烟雾流体（不被帧预算关掉）', (t) async {
    _lowPower = true;
    expect(
        await painterOf(t, const Appearance(mode: 'dark', themeStyle: 'nocturne')),
        '_FluidPainter');
  });

  testWidgets('暗夜正常档也是流体', (t) async {
    _lowPower = false;
    expect(
        await painterOf(t, const Appearance(mode: 'dark', themeStyle: 'nocturne')),
        '_FluidPainter');
  });

  testWidgets('浅色皮肤回落细渐变（shader 调色板只有暗夜一套）', (t) async {
    _lowPower = false;
    expect(
        await painterOf(t, const Appearance(mode: 'light', themeStyle: 'classic')),
        '_DockMusicProgressPainter');
  });
}

bool _lowPower = false;
