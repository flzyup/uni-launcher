import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uni_launcher/model/appearance.dart';
import 'package:uni_launcher/theme/launcher_theme.dart';
import 'package:uni_launcher/widgets/choice_button.dart';
import 'package:uni_launcher/widgets/glass_surface.dart';
import 'package:uni_launcher/widgets/liquid_material.dart';

void main() {
  for (final dark in [true, false]) {
    testWidgets(
        'live glass samples once, expands and lights at the touch in $dark',
        (t) async {
      var taps = 0;
      final style = SurfaceStyle.from(
          Appearance(
              themeStyle: 'blueGlass',
              mode: dark ? 'dark' : 'light',
              radius: 24,
              glass: true),
          dark);
      await t.pumpWidget(MaterialApp(
          theme: launcherTheme(style),
          home: Scaffold(
              body: Center(
                  child: SizedBox(
                      width: 360,
                      child: GlassSurface(
                          card: true,
                          child: ChoiceButton(
                              selected: true,
                              onPressed: () => taps++,
                              child: const Text('选择'))))))));
      expect(style.liveBlur, isTrue);
      // Nested buttons share the parent's material rather than sampling its text.
      expect(find.byType(BackdropFilter), findsOneWidget);
      final transform = find.byKey(const ValueKey('liquid-lens-transform'));
      double scale() => t.widget<Transform>(transform).transform.storage[0];
      final gesture = await t.startGesture(t.getCenter(find.text('选择')));
      await t.pump();
      await t.pump(const Duration(milliseconds: 130));
      expect(scale(), greaterThan(1.025));
      final optics = t
          .widgetList<CustomPaint>(find.byType(CustomPaint))
          .map((w) => w.painter)
          .whereType<LiquidOpticsPainter>();
      expect(optics.any((p) => p.amount > .9), isTrue);
      await gesture.up();
      await t.pumpAndSettle();
      expect(taps, 1);
      expect(scale(), closeTo(1, .001));
      expect(t.hasRunningAnimations, isFalse);
    });
  }
  testWidgets(
      'reduced motion preserves touch light without movement and cancel settles',
      (t) async {
    final style = SurfaceStyle.from(
        const Appearance(themeStyle: 'blueGlass', glass: true, radius: 28),
        true);
    await t.pumpWidget(MaterialApp(
        theme: launcherTheme(style),
        home: MediaQuery(
            data: const MediaQueryData(disableAnimations: true),
            child: Scaffold(
                body: Center(
                    child: ChoiceButton(
                        selected: false,
                        onPressed: () {},
                        child: const Text('按住')))))));
    final gesture = await t.startGesture(t.getCenter(find.text('按住')));
    await t.pump();
    expect(
        t
            .widget<Transform>(
                find.byKey(const ValueKey('liquid-lens-transform')))
            .transform
            .storage[0],
        1);
    await gesture.cancel();
    await t.pumpAndSettle();
    expect(t.hasRunningAnimations, isFalse);
  });
  testWidgets(
      'quality fallback keeps one live blur without edge passes and disposes safely',
      (t) async {
    final style = SurfaceStyle.from(
        const Appearance(themeStyle: 'blueGlass', glass: true), true,
        lowPower: true);
    await t.pumpWidget(MaterialApp(
        theme: launcherTheme(style),
        home: Scaffold(
            body: GlassSurface(
                child: ChoiceButton(
                    selected: false,
                    onPressed: () {},
                    child: const Text('选择'))))));
    expect(find.byType(BackdropFilter), findsOneWidget);
    expect(
        find.byWidgetPredicate(
            (w) => w is BackdropFilter && w.filterConfig is LiquidLensFilter),
        findsNothing);
    final gesture = await t.startGesture(t.getCenter(find.text('选择')));
    await t.pumpWidget(const SizedBox());
    await gesture.cancel();
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
  });
}
