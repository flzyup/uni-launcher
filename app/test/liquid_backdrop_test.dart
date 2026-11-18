import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uni_launcher/model/appearance.dart';
import 'package:uni_launcher/theme/contrast.dart';
import 'package:uni_launcher/theme/launcher_theme.dart';
import 'package:uni_launcher/widgets/glass_surface.dart';
import 'package:uni_launcher/widgets/spec_panel.dart';

void main() {
  for (final dark in [false, true]) {
    testWidgets('menu, dock and nested panel glass stay consistent in $dark',
        (t) async {
      final style = SurfaceStyle.from(
          Appearance(
              themeStyle: 'blueGlass',
              mode: dark ? 'dark' : 'light',
              glass: true),
          dark,
          lowPower: true);
      final boundary = GlobalKey();
      Future<Color> render(
          {bool sheet = false,
          bool dock = false,
          int groups = 0,
          Color backdrop = const Color(0xFFCA683A)}) async {
        Widget child = const SizedBox.expand();
        for (var i = 0; i < groups; i++) {
          child = SpecPanel(child: child);
        }
        await t.pumpWidget(MaterialApp(
            theme: launcherTheme(style),
            home: Center(
                child: RepaintBoundary(
                    key: boundary,
                    child: SizedBox(
                        width: 120,
                        height: 120,
                        child: Stack(fit: StackFit.expand, children: [
                          ColoredBox(color: backdrop),
                          GlassSurface(
                              sheet: sheet,
                              dock: dock,
                              radius: 0,
                              shadow: false,
                              padding: EdgeInsets.zero,
                              child: child),
                        ]))))));
        await t.pumpAndSettle();
        // Group count must not multiply backdrop sampling or blur group text.
        expect(find.byType(BackdropFilter), findsOneWidget);
        return (await t.runAsync(() async {
          final image = await (boundary.currentContext!.findRenderObject()
                  as RenderRepaintBoundary)
              .toImage();
          final data =
              (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
          final index = (60 * image.width + 60) * 4;
          final result = Color.fromARGB(255, data.getUint8(index),
              data.getUint8(index + 1), data.getUint8(index + 2));
          image.dispose();
          return result;
        }))!;
      }

      final menu = await render(sheet: true);
      expect(await render(dock: true), menu);
      expect(await render(), menu);
      for (final background in [
        Colors.black,
        Colors.white,
        const Color(0xFFCA683A)
      ]) {
        final pixel = await render(groups: 2, backdrop: background);
        for (final foreground in [style.text, style.muted, style.accent]) {
          expect(contrastRatio(foreground, pixel), greaterThanOrEqualTo(4.5));
        }
      }
      expect(t.takeException(), isNull);
    });
  }
  for (final dark in [false, true]) {
    testWidgets(
        'regular $dark material preserves backdrop color and readable ink',
        (t) async {
      final style = SurfaceStyle.from(
          Appearance(
              themeStyle: 'blueGlass',
              mode: dark ? 'dark' : 'light',
              glass: true),
          dark);
      final boundary = GlobalKey();
      for (final color in [
        Colors.black,
        Colors.white,
        const Color(0xFFCA683A)
      ]) {
        await t.pumpWidget(MaterialApp(
            theme: launcherTheme(style),
            home: Center(
                child: RepaintBoundary(
                    key: boundary,
                    child: SizedBox(
                        width: 120,
                        height: 120,
                        child: Stack(fit: StackFit.expand, children: [
                          ColoredBox(color: color),
                          const GlassSurface(
                              card: true,
                              radius: 0,
                              shadow: false,
                              padding: EdgeInsets.zero,
                              child: SizedBox.expand()),
                        ]))))));
        await t.pumpAndSettle();
        final pixel = (await t.runAsync(() async {
          final image = await (boundary.currentContext!.findRenderObject()
                  as RenderRepaintBoundary)
              .toImage();
          final data =
              (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
          final index = (60 * image.width + 60) * 4;
          final color = Color.fromARGB(255, data.getUint8(index),
              data.getUint8(index + 1), data.getUint8(index + 2));
          image.dispose();
          return color;
        }))!;
        expect(contrastRatio(style.text, pixel), greaterThanOrEqualTo(4.5));
        expect(contrastRatio(style.muted, pixel), greaterThanOrEqualTo(4.5));
        expect(contrastRatio(style.accent, pixel), greaterThanOrEqualTo(4.5));
        if (color == const Color(0xFFCA683A)) {
          // Opaque milk paint erases this color difference. Verify real raster
          // output, rather than just asserting an opacity constant.
          expect(pixel.r - pixel.g, greaterThan(dark ? .10 : .20));
        }
      }
      expect(t.takeException(), isNull);
    });
  }
}
