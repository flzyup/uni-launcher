import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uni_launcher/controller/launcher_controller.dart';
import 'package:uni_launcher/launcher_app.dart';
import 'package:uni_launcher/theme/design_tokens.dart';
import 'package:uni_launcher/widgets/circulation_icon.dart';
import 'package:uni_launcher/widgets/uni_icon.dart';
import 'fake_gateway.dart';

void main() {
  testWidgets(
      'dock indicators and climate panel use current circulation and a single-line AUTO',
      (t) async {
    t.view.physicalSize = const Size(1920, 1080);
    t.view.devicePixelRatio = 1;
    final g = FakeGateway();
    g.state['climate'] = {
      ...g.state['climate'] as Map,
      'auto': true,
      'recirc': true,
      'ac': true
    };
    final c = LauncherController(g);
    await c.initialize();
    await t.pumpWidget(LauncherApp(controller: c));
    await t.pumpAndSettle();
    final ac = find.byKey(const ValueKey('dock-ac-indicator'));
    final fan = find.byKey(const ValueKey('climate'));
    final circulation =
        find.byKey(const ValueKey('dock-circulation-indicator'));
    final left = find.byKey(const ValueKey('dock-temperature-left'));
    final right = find.byKey(const ValueKey('dock-temperature-right'));
    final home = t.getRect(find.byKey(const ValueKey('home')));
    final music = t.getRect(find.byKey(const ValueKey('dock-music-frame')));
    final climateFrame =
        t.getRect(find.byKey(const ValueKey('dock-climate-frame')));
    expect(home.width, closeTo(music.height, .1));
    expect(home.height, closeTo(music.height, .1));
    expect(climateFrame.height, closeTo(music.height, .1));
    for (final finder in [
      ac,
      find.byKey(const ValueKey('climate')),
      left,
      right,
      circulation,
      find.byKey(const ValueKey('climate-power'))
    ]) {
      final rect = t.getRect(finder);
      expect(rect.width, closeTo(home.width, .1), reason: '$finder');
      expect(rect.height, closeTo(home.height, .1), reason: '$finder');
    }
    final pressColors = <Color>{
      for (final key in [
        'system-back',
        'home',
        'all-apps',
        'recents',
        'camera',
        'dock-ac-indicator',
        'dock-temperature-left',
        'climate',
        'dock-circulation-indicator',
        'dock-temperature-right',
        'climate-power',
        'previous',
        'play-pause',
        'next',
        'uni-menu',
      ])
        t
            .widget<InkWell>(find
                .descendant(
                    of: find.byKey(ValueKey(key)),
                    matching: find.byType(InkWell))
                .first)
            .overlayColor!
            .resolve({WidgetState.pressed})!,
    };
    expect(pressColors, hasLength(1));
    expect(t.getCenter(ac).dx, lessThan(t.getCenter(left).dx));
    expect(t.getCenter(left).dx, lessThan(t.getCenter(fan).dx));
    expect(t.getCenter(right).dx, greaterThan(t.getCenter(circulation).dx));
    expect(t.getCenter(circulation).dx, greaterThan(t.getCenter(fan).dx));
    expect(find.byTooltip('降低主驾温度'), findsNothing);
    expect(find.byTooltip('升高副驾温度'), findsNothing);
    expect(
        t
            .widget<CirculationIcon>(find.descendant(
                of: circulation, matching: find.byType(CirculationIcon)))
            .recirculating,
        true);
    await t.tap(ac);
    await t.pumpAndSettle();
    expect(g.commands.last['action'], 'climate-mode');
    expect(g.commands.last['value'], 'ac');
    await t.tap(circulation);
    await t.pumpAndSettle();
    expect(g.commands.last['action'], 'climate-mode');
    expect(g.commands.last['value'], 'recirc');
    await t.tap(fan);
    await t.pumpAndSettle();
    expect(
        t.widget<UniIcon>(find.byKey(const ValueKey('climate-fan-icon'))).size,
        greaterThanOrEqualTo(Design.px(36)));
    expect(
        t.getCenter(find.byKey(const ValueKey('climate-card-left'))).dy,
        closeTo(
            t.getCenter(find.byKey(const ValueKey('climate-card-fan'))).dy, 1));
    final autoLabels = t.widgetList<Text>(find.text('AUTO'));
    expect(
        autoLabels.any((text) => text.maxLines == 1 && text.softWrap == false),
        isTrue);
    expect(
        t
            .widget<CirculationIcon>(
                find.byKey(const ValueKey('climate-circulation-icon')))
            .recirculating,
        true);
    g.state['climate'] = {...g.state['climate'] as Map, 'recirc': false};
    g.stream.add(Map.of(g.state));
    await t.pumpAndSettle();
    expect(
        t
            .widget<CirculationIcon>(
                find.byKey(const ValueKey('climate-circulation-icon')))
            .recirculating,
        false);
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox.shrink());
    c.dispose();
    await g.dispose();
    t.view.resetPhysicalSize();
    t.view.resetDevicePixelRatio();
  });
}
