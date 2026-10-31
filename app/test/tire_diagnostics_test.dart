import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uni_launcher/controller/launcher_controller.dart';
import 'package:uni_launcher/model/appearance.dart';
import 'package:uni_launcher/theme/launcher_theme.dart';
import 'package:uni_launcher/widgets/tire_diagnostics.dart';
import 'fake_gateway.dart';

void main() {
  testWidgets('diagnostics show only fresh readings and preserve raw details',
      (t) async {
    final g = FakeGateway();
    g.state['demo'] = false;
    g.state['vehicle'] = {
      'connected': true,
      'fields': {
        'pressureFrontLeft': {
          'valid': true,
          'value': 2.46,
          'unit': 'bar',
          'raw': 246,
          'source': 'PA',
          'updatedAtMs': DateTime.now().millisecondsSinceEpoch
        },
        'pressureFrontRight': {
          'valid': false,
          'raw': 0,
          'source': 'PA',
          'reason': '不可用'
        }
      }
    };
    final c = LauncherController(g);
    await c.initialize();
    await t.pumpWidget(MaterialApp(
        theme: launcherTheme(SurfaceStyle.from(const Appearance(), true)),
        home: Scaffold(
            body:
                SingleChildScrollView(child: TireDiagnostics(controller: c)))));
    await t.tap(find.byKey(const ValueKey('tire-diagnostics')));
    await t.pumpAndSettle();
    expect(find.text('左前  2.46 bar'), findsOneWidget);
    expect(find.textContaining('原始值 246'), findsOneWidget);
    expect(find.text('右前  —'), findsOneWidget);
    expect(find.textContaining('不可用'), findsOneWidget);
    expect(g.commands, isEmpty);
    await t.pumpWidget(const SizedBox.shrink());
    c.dispose();
    await g.dispose();
  });
}
