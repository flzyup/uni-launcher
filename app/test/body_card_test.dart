import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uni_launcher/controller/launcher_controller.dart';
import 'package:uni_launcher/model/appearance.dart';
import 'package:uni_launcher/model/card_layout.dart';
import 'package:uni_launcher/theme/launcher_theme.dart';
import 'package:uni_launcher/widgets/body_diagnostics.dart';
import 'package:uni_launcher/widgets/card_content.dart';
import 'package:uni_launcher/widgets/glass_surface.dart';
import 'fake_gateway.dart';

void main() {
  testWidgets('body card and diagnostics do not interpret unverified PA data',
      (t) async {
    final preview = Platform.environment['UNI_BODY_PREVIEW'];
    if (preview != null) {
      await t.runAsync(() async {
        final bytes =
            await File('/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc')
                .readAsBytes();
        final loader = FontLoader('BodyPreview')
          ..addFont(Future.value(ByteData.sublistView(bytes)));
        await loader.load();
      });
    }
    final gateway = FakeGateway();
    gateway.state['vehicle'] = {
      'connected': true,
      'fields': {
        'doorFrontLeft': {
          'valid': false,
          'raw': 1,
          'updatedAtMs': DateTime.now().millisecondsSinceEpoch
        },
        for (final key in [
          'pressureFrontLeft',
          'pressureFrontRight',
          'pressureRearLeft',
          'pressureRearRight'
        ])
          key: {
            'valid': true,
            'value': 2.45,
            'unit': 'bar',
            'unitVerified': true,
            'updatedAtMs': DateTime.now().millisecondsSinceEpoch
          }
      },
      'bodyProbe': {
        'observedAtMs': DateTime.now().millisecondsSinceEpoch,
        'properties': [
          {'name': 'driver', 'active': true, 'raw': 1}
        ]
      }
    };
    final controller = LauncherController(gateway);
    await controller.initialize();
    const card = LauncherCard('body-test', 'body', '车门状态', 0, 0, 4, 3, 0);
    expect(card.inBounds, isTrue);
    final style = SurfaceStyle.from(
        const Appearance(
            mode: 'dark', palette: 'blue', themeStyle: 'blueGlass', radius: 0),
        true);
    final theme = launcherTheme(style);
    await t.pumpWidget(MaterialApp(
        theme: preview == null
            ? theme
            : theme.copyWith(
                textTheme: theme.textTheme.apply(fontFamily: 'BodyPreview')),
        home: Scaffold(
            body: Column(children: [
          RepaintBoundary(
              key: const ValueKey('body-card-preview'),
              child: SizedBox(
                  width: 480,
                  height: 300,
                  child: GlassSurface(
                      padding: EdgeInsets.zero,
                      child: CardContent(card: card, controller: controller)))),
          Expanded(
              child: SingleChildScrollView(
                  child: BodyDiagnostics(controller: controller)))
        ]))));
    await t.pump();
    expect(find.text('车门状态待验证'), findsOneWidget);
    for (final key in [
      'pressureFrontLeft',
      'pressureFrontRight',
      'pressureRearLeft',
      'pressureRearRight'
    ]) {
      expect(find.byKey(ValueKey('tire-pressure-$key')), findsOneWidget);
    }
    expect(find.text('2.45'), findsNWidgets(4));
    Offset pressureCenter(String key) =>
        t.getCenter(find.byKey(ValueKey('tire-pressure-$key')));
    final leftFront = pressureCenter('pressureFrontLeft');
    final rightFront = pressureCenter('pressureFrontRight');
    final leftRear = pressureCenter('pressureRearLeft');
    final rightRear = pressureCenter('pressureRearRight');
    expect(leftFront.dy, greaterThan(rightFront.dy));
    expect(leftRear.dy, greaterThan(rightRear.dy));
    expect(leftFront.dx, lessThan(leftRear.dx));
    expect(rightFront.dx, lessThan(rightRear.dx));
    final artwork =
        t.getRect(find.byKey(const ValueKey('vehicle-status-artwork')));
    for (final key in [
      'pressureFrontLeft',
      'pressureFrontRight',
      'pressureRearLeft',
      'pressureRearRight'
    ]) {
      expect(
          t
              .getRect(find.byKey(ValueKey('tire-pressure-$key')))
              .overlaps(artwork),
          isFalse,
          reason: '$key must remain outside the vehicle artwork');
    }
    expect(find.byKey(const ValueKey('vehicle-opening-alert')), findsNothing);
    final vehicle =
        Map<String, dynamic>.from(controller.native.value['vehicle'] as Map);
    final fields = Map<String, dynamic>.from(vehicle['fields'] as Map);
    fields['doorFrontLeft'] = {
      'valid': true,
      'value': true,
      'updatedAtMs': DateTime.now().millisecondsSinceEpoch,
    };
    controller.native.value = {
      ...controller.native.value,
      'vehicle': {...vehicle, 'fields': fields}
    };
    await t.pump();
    expect(find.byKey(const ValueKey('vehicle-opening-alert')), findsOneWidget);
    expect(
        find.byKey(const ValueKey('vehicle-door-front-left')), findsOneWidget);
    expect(find.text('左前门开启'), findsOneWidget);
    expect(find.text('2.45'), findsNWidgets(4));
    final doorKeys = [
      'doorFrontLeft',
      'doorFrontRight',
      'doorRearLeft',
      'doorRearRight'
    ];
    final markerKeys = ['front-left', 'front-right', 'rear-left', 'rear-right'];
    for (var mask = 0; mask < 16; mask++) {
      final now = DateTime.now().millisecondsSinceEpoch;
      final nextFields = Map<String, dynamic>.from(fields);
      for (var i = 0; i < doorKeys.length; i++) {
        nextFields[doorKeys[i]] = {
          'valid': true,
          'value': (mask & (1 << i)) != 0,
          'updatedAtMs': now
        };
      }
      controller.native.value = {
        ...controller.native.value,
        'vehicle': {...vehicle, 'fields': nextFields}
      };
      await t.pump();
      for (var i = 0; i < markerKeys.length; i++) {
        expect(find.byKey(ValueKey('vehicle-door-${markerKeys[i]}')),
            (mask & (1 << i)) != 0 ? findsOneWidget : findsNothing,
            reason: 'door mask $mask');
      }
    }
    if (preview != null) {
      await t.runAsync(() => precacheImage(
          const AssetImage(
              'assets/art/vehicle-status-front-left-transparent.png'),
          t.element(find.byKey(const ValueKey('body-card-preview')))));
      await t.pumpAndSettle();
      await t.runAsync(() async {
        final boundary = t.renderObject<RenderRepaintBoundary>(
            find.byKey(const ValueKey('body-card-preview')));
        final image = await boundary.toImage(pixelRatio: 2);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await File(preview).writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
    }
    await t.tap(find.byKey(const ValueKey('body-diagnostics')));
    await t.pumpAndSettle();
    expect(find.text('驾驶员前门  原始值 1'), findsOneWidget);
    expect(find.text('待核对'), findsOneWidget);
    expect(gateway.commands, isEmpty);
    await t.pumpWidget(const SizedBox.shrink());
    controller.dispose();
    await gateway.dispose();
  });
}
