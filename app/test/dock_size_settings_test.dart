import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:uni_launcher/controller/launcher_controller.dart';
import 'package:uni_launcher/launcher_app.dart';
import 'package:uni_launcher/theme/design_tokens.dart';
import 'package:uni_launcher/widgets/glass_surface.dart';
import 'fake_gateway.dart';

void main() {
  testWidgets(
      'dock size scales glyphs uniformly while bar geometry stays fixed',
      (tester) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1;
    final gateway = FakeGateway();
    final controller = LauncherController(gateway);
    await controller.initialize();
    await tester.pumpWidget(LauncherApp(controller: controller));
    await tester.pumpAndSettle();
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
      await gateway.dispose();
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    expect(controller.appearance.dockSize, 'large');

    for (final (size, scale) in [
      ('small', 1.0),
      ('medium', 1.14),
      ('large', 1.3),
    ]) {
      controller.setAppearance(controller.appearance.copyWith(dockSize: size));
      await tester.pumpAndSettle();
      expect(controller.appearance.dockSize, size);
      final dock =
          tester.widget<SizedBox>(find.byKey(const ValueKey('bottom-dock')));
      expect(dock.height, Design.px(96));

      final home =
          tester.widget<IconAction>(find.byKey(const ValueKey('home')));
      expect(home.size, Design.px(72));
      expect(home.iconSize, moreOrLessEquals(Design.px(29 * scale)));

      final title = tester.widget<Text>(find
          .descendant(
              of: find.byKey(const ValueKey('dock-track-title')),
              matching: find.byType(Text))
          .first);
      expect(
        title.style?.fontSize,
        moreOrLessEquals(Design.px(23 * scale)),
      );
      expect(tester.takeException(), isNull);
    }
    expect(gateway.saved, contains('"dockSize":"large"'));
  });
}
