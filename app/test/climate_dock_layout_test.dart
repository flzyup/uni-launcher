import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uni_launcher/controller/launcher_controller.dart';
import 'package:uni_launcher/launcher_app.dart';
import 'package:uni_launcher/widgets/circulation_icon.dart';
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
