import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uni_launcher/model/appearance.dart';
import 'package:uni_launcher/theme/launcher_theme.dart';
import 'package:uni_launcher/widgets/scene_background.dart';

void main() {
  testWidgets('blue glass theme-gradient reacts to the chosen theme color',
      (t) async {
    Future<List<Color>> colors(String palette) async {
      final appearance =
          Appearance(themeStyle: 'blueGlass', mode: 'dark', palette: palette);
      await t.pumpWidget(MaterialApp(
          theme: launcherTheme(SurfaceStyle.from(appearance, true)),
          home: SceneBackground(
              appearance: appearance, child: const SizedBox())));
      await t.pumpAndSettle();
      final box = t.widget<DecoratedBox>(
          find.byKey(const ValueKey('technical-theme-gradient')));
      return (box.decoration as BoxDecoration).gradient!.colors;
    }

    final blue = await colors('blue');
    final amber = await colors('amber');
    expect(blue.toSet().length, greaterThan(1));
    expect(blue.first, isNot(amber.first));
  });
}
