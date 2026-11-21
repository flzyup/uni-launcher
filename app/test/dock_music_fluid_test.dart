import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uni_launcher/controller/launcher_controller.dart';
import 'package:uni_launcher/model/appearance.dart';
import 'package:uni_launcher/theme/launcher_theme.dart';
import 'package:uni_launcher/widgets/bottom_dock.dart';
import 'fake_gateway.dart';

/// 底栏音乐条那一块：暗夜深色走烟雾流体，其余一律细渐变填充。
///
/// 2026-11-13 实车反馈「拨开关还是老进度条」——原因是流体被帧预算降级
/// （`SurfaceStyle.lowPower`）一并关掉了，而用户看到的现象正是「和另外两套皮肤
/// 一样的进度条」。这里把几条都钉住：暗夜深色即使降级也要出流体；浅色就是
/// 原来的进度条、相当于关掉烟雾流动（2026-11-19 用户定的），只是刀口颜色跟着
/// 主题色走；其他皮肤仍是细渐变。
void main() {
  Future<CustomPainter> painterOf(WidgetTester t, Appearance look) async {
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
    final painter = t.widget<CustomPaint>(found).painter!;
    await t.pumpWidget(const SizedBox());
    c.dispose();
    await g.dispose();
    return painter;
  }

  testWidgets('暗夜降级时仍然画烟雾流体（不被帧预算关掉）', (t) async {
    _lowPower = true;
    final painter = await painterOf(
        t, const Appearance(mode: 'dark', themeStyle: 'nocturne'));
    expect(painter.runtimeType.toString(), '_FluidPainter');
  });

  testWidgets('暗夜正常档也是流体', (t) async {
    _lowPower = false;
    final painter = await painterOf(
        t, const Appearance(mode: 'dark', themeStyle: 'nocturne'));
    expect(painter.runtimeType.toString(), '_FluidPainter');
  });

  testWidgets('暗夜浅色就是原来的进度条（烟雾不生效）', (t) async {
    _lowPower = false;
    final painter = await painterOf(
        t, const Appearance(mode: 'light', themeStyle: 'nocturne'));
    expect(painter.runtimeType.toString(), '_DockMusicProgressPainter');
  });

  testWidgets('其他皮肤浅色仍是细渐变', (t) async {
    _lowPower = false;
    final painter = await painterOf(
        t, const Appearance(mode: 'light', themeStyle: 'classic'));
    expect(painter.runtimeType.toString(), '_DockMusicProgressPainter');
  });
}

bool _lowPower = false;
