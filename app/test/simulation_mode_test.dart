import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uni_launcher/controller/launcher_controller.dart';
import 'package:uni_launcher/model/card_layout.dart';
import 'package:uni_launcher/model/appearance.dart';
import 'package:uni_launcher/model/simulation_mode.dart';
import 'package:uni_launcher/theme/launcher_theme.dart';
import 'package:uni_launcher/widgets/audio_spectrum.dart';
import 'package:uni_launcher/widgets/card_content.dart';
import 'package:uni_launcher/widgets/media_artwork.dart';
import 'package:uni_launcher/widgets/simulation_settings.dart';
import 'fake_gateway.dart';

void main() {
  test('media simulation stays independent from vehicle simulation', () {
    expect(mediaIsDemo({'demo': true}), isTrue);
    expect(mediaIsDemo({'demo': true, 'mediaDemo': false}), isFalse);
    expect(
        mediaIsDemo({'demo': true, 'simulationMode': 'highFidelity'}), isFalse);
    expect(mediaIsDemo({'demo': false}), isFalse);
  });

  testWidgets('high fidelity shows real artwork, player and spectrum',
      (t) async {
    t.view.physicalSize = const Size(1600, 900);
    t.view.devicePixelRatio = 1;
    final g = FakeGateway();
    g.state.addAll({
      'demo': true,
      'mediaDemo': false,
      'simulationMode': 'highFidelity',
      'apps': [
        {'package': 'com.netease.cloudmusic.iot', 'label': '网易云音乐'}
      ],
      'media': {
        'source': 'com.netease.cloudmusic.iot',
        'title': '真实歌曲',
        'artist': '真实歌手',
        'available': true,
        'playing': true,
        'canToggle': true,
      },
    });
    final c = LauncherController(g);
    await c.initialize();
    await t.pumpWidget(MaterialApp(
        theme: launcherTheme(SurfaceStyle.from(const Appearance(), true)),
        home: Scaffold(
            body: SizedBox(
                width: 800,
                height: 600,
                child: CardContent(
                    card: const LauncherCard('m', 'music', '音乐', 0, 0, 4, 4, 0),
                    controller: c)))));
    await t.pump(const Duration(milliseconds: 300));
    expect(mediaSourceLabel(c.native.value), '网易云音乐');
    expect(t.widget<MediaArtwork>(find.byType(MediaArtwork)).demo, isFalse);
    expect(t.widget<AudioSpectrum>(find.byType(AudioSpectrum)).playing, isTrue);
    expect(find.text('真实歌曲'), findsWidgets);
    expect(find.text('午夜立交'), findsNothing);
    await t.pumpWidget(const SizedBox.shrink());
    c.dispose();
    await g.dispose();
    t.view.resetPhysicalSize();
    t.view.resetDevicePixelRatio();
  });

  testWidgets('mode choices are emulator-only and send native mode action',
      (t) async {
    t.view.physicalSize = const Size(1600, 900);
    t.view.devicePixelRatio = 1;
    final g = FakeGateway();
    final c = LauncherController(g);
    await c.initialize();
    await t.pumpWidget(MaterialApp(
        theme: launcherTheme(SurfaceStyle.from(const Appearance(), true)),
        home: Scaffold(
            body: SizedBox(
                width: 660, child: SimulationSettings(controller: c)))));
    expect(find.text('模拟器运行模式'), findsNothing);
    g.state['simulation'] = {'supported': true};
    g.stream.add(Map.of(g.state));
    await t.pump();
    expect(find.text('模拟器运行模式'), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('simulation-highFidelity')));
    await t.pump();
    expect(g.commands.last['action'], 'simulation-mode');
    expect(g.commands.last['value'], 'highFidelity');
    expect(mediaIsDemo(c.native.value), isFalse);
    await t.pumpWidget(const SizedBox.shrink());
    c.dispose();
    await g.dispose();
    t.view.resetPhysicalSize();
    t.view.resetDevicePixelRatio();
  });
}
