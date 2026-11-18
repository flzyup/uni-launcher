import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uni_launcher/model/appearance.dart';
import 'package:uni_launcher/controller/launcher_controller.dart';
import 'package:uni_launcher/launcher_app.dart';
import '../test/fake_gateway.dart';
import 'package:uni_launcher/theme/contrast.dart';
import 'package:uni_launcher/theme/design_tokens.dart';
import 'package:uni_launcher/theme/launcher_theme.dart';
import 'package:uni_launcher/widgets/choice_button.dart';
import 'package:uni_launcher/widgets/glass_surface.dart';

void main() {
  final colors = [
    ...accentPresets.map((p) => (p.id, '#000000')),
    for (final hex in [
      '#FFFFFF',
      '#000000',
      '#FFFF00',
      '#00FF00',
      '#0000FF',
      '#FF0000',
      '#808080'
    ])
      ('custom', hex)
  ];
  test('all palettes retain body, secondary, accent and selection contrast',
      () {
    for (final skin in Appearance.themeStyles) {
      for (final mode in ['dark', 'light']) {
        for (final (palette, custom) in colors) {
          for (final glass in [true, false]) {
            final s = SurfaceStyle.from(
                Appearance(
                    themeStyle: skin,
                    mode: mode,
                    palette: palette,
                    custom: custom,
                    glass: glass),
                false);
            final label = '$skin/$mode/$palette/$custom/glass=$glass';
            final base = s.contrastBase;
            for (final fg in [s.text, s.muted, s.accent]) {
              expect(contrastRatio(fg, base), greaterThanOrEqualTo(4.5),
                  reason: label);
            }
            for (final bg in [s.accent, s.accentHi, s.accentLo]) {
              expect(contrastRatio(s.accentText, bg), greaterThanOrEqualTo(4.5),
                  reason: '$label solid/gradient');
            }
            final selection = s.selectionStyle(true);
            final selectionBg =
                Color.alphaBlend(selection.backgroundColor!.resolve({})!, base);
            expect(
                contrastRatio(
                    selection.foregroundColor!.resolve({})!, selectionBg),
                greaterThanOrEqualTo(4.5),
                reason: '$label selection');
            for (final bg in [
              Colors.black,
              Colors.white,
              Colors.red,
              Colors.green,
              Colors.blue,
              Colors.cyan,
              Colors.yellow,
              Colors.purple,
              Colors.grey
            ]) {
              if (!s.liquidGlass) continue;
              for (final fill in [
                ...s.liquidFill(),
                ...s.liquidFill(content: true),
                ...s.liquidFill(sheet: true),
              ]) {
                final plane = Color.alphaBlend(fill, s.liquidBackground(bg));
                for (final fg in [s.text, s.muted, s.accent]) {
                  expect(contrastRatio(fg, plane), greaterThanOrEqualTo(4.5),
                      reason: '$label photo/$bg/$fill');
                }
              }
            }
          }
        }
      }
    }
  });

  test('light liquid glass keeps the backdrop visible without white wash', () {
    final s = SurfaceStyle.from(
        const Appearance(themeStyle: 'blueGlass', mode: 'light', glass: true),
        false);
    for (final fill in [...s.liquidFill(), ...s.liquidFill(content: true)]) {
      expect(fill.a, lessThan(.08));
    }
    expect(s.liquidOpacity(sheet: true), lessThanOrEqualTo(.10));
    final solid = SurfaceStyle.from(
        const Appearance(themeStyle: 'blueGlass', mode: 'light', glass: false),
        false);
    expect(solid.liquidOpacity(), .96);
  });

  test('buttons share disabled state, height and theme geometry', () {
    for (final skin in Appearance.themeStyles) {
      final s =
          SurfaceStyle.from(Appearance(themeStyle: skin, radius: 24), true);
      final t = launcherTheme(s);
      final styles = [
        t.textButtonTheme.style!,
        t.outlinedButtonTheme.style!,
        t.filledButtonTheme.style!,
        t.elevatedButtonTheme.style!,
        s.selectionStyle(true),
        s.weakSelectionStyle(true)
      ];
      for (final style in styles) {
        expect(
            style.foregroundColor!.resolve({WidgetState.disabled}), s.disabled);
        expect(style.minimumSize!.resolve({})!.height, Design.controlHeight);
        expect(style.shape!.resolve({}), s.controlShape());
        expect(style.overlayColor!.resolve({WidgetState.pressed})!.a,
            greaterThan(0));
      }
    }
  });

  testWidgets('dark settings on a bright photo retain an opaque contrast plane',
      (t) async {
    t.view.physicalSize = const Size(1920, 1080);
    t.view.devicePixelRatio = 1;
    final gateway = FakeGateway();
    final c = LauncherController(gateway);
    await c.initialize();
    c.setAppearance(
        const Appearance(
            themeStyle: 'nocturne', mode: 'dark', wallpaper: 'coastal'),
        save: false);
    c.openSettings();
    await t.pumpWidget(LauncherApp(controller: c));
    await t.pumpAndSettle();
    final f = find.byKey(const ValueKey('settings-main-contrast-plane'));
    final box = t.widget<DecoratedBox>(f).decoration as BoxDecoration;
    final style = SurfaceStyle.of(t.element(f));
    expect(box.color!.a, greaterThanOrEqualTo(.90));
    final base = Color.alphaBlend(box.color!, Colors.white);
    expect(contrastRatio(style.text, base), greaterThanOrEqualTo(4.5));
    expect(contrastRatio(style.muted, base), greaterThanOrEqualTo(4.5));
    final scrim = find.byKey(const ValueKey('scene-text-contrast-scrim'));
    expect(scrim, findsWidgets);
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox());
    c.dispose();
    await gateway.dispose();
    t.view.resetPhysicalSize();
    t.view.resetDevicePixelRatio();
  });

  for (final (mode, wallpaper, dark) in [
    ('light', 'graphite', true),
    ('dark', 'coastal', false)
  ]) {
    testWidgets('liquid $mode header on $wallpaper has readable ink, no band',
        (t) async {
      t.view.physicalSize = const Size(1920, 1080);
      t.view.devicePixelRatio = 1;
      final gateway = FakeGateway();
      final c = LauncherController(gateway);
      await c.initialize();
      c.setAppearance(
          Appearance(themeStyle: 'blueGlass', mode: mode, wallpaper: wallpaper),
          save: false);
      c.openSettings();
      await t.pumpWidget(LauncherApp(controller: c));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('scene-text-contrast-scrim')),
          findsNothing);
      final title = find.text('桌面设置');
      final style = SurfaceStyle.of(t.element(title));
      expect(style.dark, dark);
      expect(DefaultTextStyle.of(t.element(title)).style.color, style.text);
      expect(contrastRatio(style.text, dark ? Colors.black : Colors.white),
          greaterThanOrEqualTo(4.5));
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
      c.dispose();
      await gateway.dispose();
      t.view.resetPhysicalSize();
      t.view.resetDevicePixelRatio();
    });
  }

  testWidgets('a desktop preview owns its glass plane inside another material',
      (t) async {
    final s = SurfaceStyle.from(
        const Appearance(themeStyle: 'blueGlass', glass: true), true);
    await t.pumpWidget(MaterialApp(
        theme: launcherTheme(s),
        home: const Scaffold(
            body: GlassSurface(
                child: GlassSurface(card: true, child: Text('预览卡片'))))));
    expect(find.byType(BackdropFilter), findsNWidgets(4));
    // Outer lens has blur + two edge filters; the content card adds one blur.
    expect(t.takeException(), isNull);
  });

  for (final skin in Appearance.themeStyles) {
    testWidgets('$skin disabled choices and compact actions inherit tokens',
        (t) async {
      final s = SurfaceStyle.from(
          Appearance(themeStyle: skin, mode: 'light', glass: true), false);
      await t.pumpWidget(MaterialApp(
          theme: launcherTheme(s),
          home: Scaffold(
              body: GlassSurface(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
            const ChoiceButton(
                selected: true, onPressed: null, child: Text('不可操作')),
            DesignSmallAction('刷新', onPressed: () {}),
            DesignTextAction('查看', onPressed: () {}),
            DesignSwitch(value: true, onChanged: (_) {}),
          ])))));
      await t.pumpAndSettle();
      expect(DefaultTextStyle.of(t.element(find.text('不可操作'))).style.color,
          s.disabled);
      expect(t.getSize(find.byType(DesignSmallAction)).height,
          Design.compactControlHeight);
      expect(t.getSize(find.byType(DesignTextAction)).height,
          Design.compactControlHeight);
      expect(t.takeException(), isNull);
    });
  }
}
