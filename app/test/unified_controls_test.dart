import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uni_launcher/model/appearance.dart';
import 'package:uni_launcher/theme/design_tokens.dart';
import 'package:uni_launcher/theme/launcher_theme.dart';
import 'package:uni_launcher/widgets/choice_button.dart';
import 'package:uni_launcher/widgets/glass_surface.dart';

void main() {
  for (final skin in ['classic', 'blueGlass', 'nocturne']) {
    testWidgets('$skin switches share sizing, style and tap behavior',
        (t) async {
      var one = false;
      var two = false;
      await t.pumpWidget(MaterialApp(
          theme: launcherTheme(
              SurfaceStyle.from(Appearance(themeStyle: skin, radius: 0), true)),
          home: Scaffold(
              body: StatefulBuilder(
                  builder: (context, setState) => Column(children: [
                        DesignSwitch(
                            key: const ValueKey('direct'),
                            value: one,
                            onChanged: (v) => setState(() => one = v)),
                        DesignSwitchTile(
                            title: const Text('开关'),
                            value: two,
                            onChanged: (v) => setState(() => two = v)),
                      ])))));
      final direct = find.byKey(const ValueKey('direct'));
      final tile = find.byType(DesignSwitchTile);
      final switches = find.byType(DesignSwitch);
      expect(switches, findsNWidgets(2));
      expect(t.getSize(direct),
          const Size(Design.switchWidth, Design.switchHeight));
      final track = t.widget<AnimatedContainer>(find.descendant(
          of: direct, matching: find.byType(AnimatedContainer)));
      expect(track.decoration, isA<BoxDecoration>());
      await t.tap(direct);
      await t.pumpAndSettle();
      expect(one, isTrue);
      await t
          .tap(find.descendant(of: tile, matching: find.byType(DesignSwitch)));
      await t.pumpAndSettle();
      expect(two, isTrue);
      await t.tap(find.text('开关'));
      await t.pumpAndSettle();
      expect(two, isFalse);
    });
  }
}
