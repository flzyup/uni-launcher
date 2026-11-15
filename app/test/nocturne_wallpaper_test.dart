import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uni_launcher/model/appearance.dart';
import 'package:uni_launcher/theme/launcher_theme.dart';
import 'package:uni_launcher/widgets/scene_background.dart';

/// 暗夜 + 壁纸这一档的两个坑（用户 2026-11-13 实车反馈）：
///
/// 1. 卡片、按钮、底栏胶囊全都半透明地浮在照片上——暗夜的表层只有 5% 白，
///    是围着「近黑画布」设计的；照片一进来就透。
/// 2. 「叠加主题渐变」这个开关在暗夜下**完全没读**，拨了没反应。
void main() {
  const wall =
      Appearance(mode: 'dark', themeStyle: 'nocturne', wallpaper: 'coastal');
  const plain = Appearance(mode: 'dark', themeStyle: 'nocturne');

  test('暗夜 + 壁纸：表层色换成压得住照片的实底，没壁纸时保持原样', () {
    final backed = SurfaceStyle.from(wall, true);
    expect(backed.wallpaperBacked, isTrue);
    // 卡片底、按钮底都要够实（原来分别是 8% 和 6% 白）。
    expect(backed.surface.a, greaterThan(.85));
    expect(backed.soft.a, greaterThan(.6));
    expect(backed.edge.a, greaterThan(.12));

    final canvas = SurfaceStyle.from(plain, true);
    expect(canvas.wallpaperBacked, isFalse);
    expect(canvas.surface.a, lessThan(.12));
    expect(canvas.soft.a, lessThan(.12));
    // 另两套皮肤不吃这个标记。
    expect(
        SurfaceStyle.from(
                const Appearance(
                    mode: 'dark', themeStyle: 'classic', wallpaper: 'coastal'),
                true)
            .wallpaperBacked,
        isFalse);
  });

  testWidgets('暗夜 + 壁纸：叠加主题渐变开关真的改变背景', (t) async {
    Future<void> show(Appearance a) => t.pumpWidget(MaterialApp(
        theme: launcherTheme(SurfaceStyle.from(a, true)),
        home: Scaffold(
            body: SceneBackground(
                appearance: a, child: const SizedBox.expand()))));

    await show(wall.copyWith(wallpaperOverlay: true));
    await t.pump();
    expect(find.byKey(const ValueKey('nocturne-wallpaper-overlay')),
        findsOneWidget);

    await show(wall.copyWith(wallpaperOverlay: false));
    await t.pump();
    expect(
        find.byKey(const ValueKey('nocturne-wallpaper-overlay')), findsNothing);
    expect(t.takeException(), isNull);
  });
}
