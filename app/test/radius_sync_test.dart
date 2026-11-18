import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uni_launcher/controller/launcher_controller.dart';
import 'package:uni_launcher/model/appearance.dart';
import 'package:uni_launcher/theme/launcher_theme.dart';
import 'package:uni_launcher/widgets/choice_button.dart';
import 'package:uni_launcher/widgets/glass_surface.dart';
import 'package:uni_launcher/widgets/spec_panel.dart';

import 'fake_gateway.dart';

void main() {
  testWidgets('radius previews propagate to the independent dock and persist',
      (tester) async {
    final desktopGateway = FakeGateway();
    final dockGateway = FakeGateway();
    dockGateway.state['hostMode'] = 'global-dock';
    final desktop = LauncherController(desktopGateway);
    final dock = LauncherController(dockGateway);
    await desktop.initialize();
    await dock.initialize();
    addTearDown(() async {
      desktop.dispose();
      dock.dispose();
      await desktopGateway.dispose();
      await dockGateway.dispose();
    });

    desktop.previewRadius(7);
    desktop.previewRadius(0);
    await tester.pump(const Duration(milliseconds: 160));
    await tester.pump();
    final saved = desktopGateway.saved!;
    expect(jsonDecode(saved)['preferences']['radius'], 0);
    dockGateway.stream.add({...dockGateway.state, 'savedDesign': saved});
    expect(dock.appearance.radius, 0);

    desktop.previewRadius(40);
    desktop.finishRadiusChange();
    await tester.pump();
    await tester.pump();
    expect(jsonDecode(desktopGateway.saved!)['preferences']['radius'], 40);
    dockGateway.stream
        .add({...dockGateway.state, 'savedDesign': desktopGateway.saved});
    expect(dock.appearance.radius, 40);
  });

  for (final skin in ['classic', 'blueGlass', 'nocturne']) {
    testWidgets('surfaces and controls follow radius in $skin', (tester) async {
      Future<void> render(double radius) async {
        final appearance = Appearance(themeStyle: skin, radius: radius);
        await tester.pumpWidget(MaterialApp(
            theme: launcherTheme(SurfaceStyle.from(appearance, true)),
            home: const Scaffold(
                body: Column(children: [
              GlassSurface(key: ValueKey('surface'), child: Text('card')),
              SpecPanel(key: ValueKey('spec'), child: Text('panel')),
              ChoiceButton(
                  key: ValueKey('choice'),
                  selected: false,
                  onPressed: null,
                  child: Text('button')),
            ]))));
        await tester.pumpAndSettle();
      }

      await render(0);
      final specFinder = find.descendant(
          of: find.byKey(const ValueKey('spec')),
          matching: find.byWidgetPredicate(
              (w) => w is Container && w.decoration is BoxDecoration));
      BoxDecoration specDecoration() =>
          tester.widget<Container>(specFinder.first).decoration!
              as BoxDecoration;
      BorderRadiusGeometry specRadius() => skin == 'blueGlass'
          ? tester
              .widget<ClipRRect>(find
                  .descendant(
                      of: find.byKey(const ValueKey('spec')),
                      matching: find.byType(ClipRRect))
                  .first)
              .borderRadius
          : specDecoration().borderRadius!;
      expect(specRadius(), BorderRadius.zero);
      if (skin == 'nocturne') {
        BoxDecoration choiceDecoration() => tester
            .widget<DecoratedBox>(find
                .descendant(
                    of: find.byKey(const ValueKey('choice')),
                    matching: find.byType(DecoratedBox))
                .first)
            .decoration as BoxDecoration;
        expect(choiceDecoration().borderRadius, BorderRadius.zero);
        await render(40);
        expect((specRadius() as BorderRadius).topLeft.x, greaterThan(0));
        expect((choiceDecoration().borderRadius! as BorderRadius).topLeft.x,
            greaterThan(0));
      } else {
        await render(40);
        expect((specRadius() as BorderRadius).topLeft.x, greaterThan(0));
      }
    });
  }
}
