import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../controller/launcher_controller.dart';
import '../model/card_layout.dart';
import '../theme/design_tokens.dart';
import '../theme/launcher_theme.dart';
import 'clock_card.dart';
import 'clock_weather_card.dart';
import 'account_details_sheet.dart';
import 'glass_surface.dart';
import 'launcher_dialog.dart';
import 'uni_icon.dart';
import 'lyrics_view.dart';
import 'media_progress.dart';
import 'embedded_navigation.dart';
import 'media_artwork.dart';
import 'audio_spectrum.dart';
import 'media_source_badge.dart';
import 'music_app_picker.dart';
import 'weather_icon.dart';
import 'weather_details_sheet.dart';
import 'vehicle_cards.dart';
import 'vehicle_visuals.dart';
import 'official_card_entry.dart';
import 'native_slice_builder.dart';
import '../model/weather_condition.dart';
import '../model/vehicle_data.dart';
import '../model/traffic_light.dart';
import 'traffic_light_card.dart';

export 'vehicle_visuals.dart' show TireDiagram, VehicleDoorSnapshot;

part 'card_content_music.dart';
part 'card_content_navigation.dart';
part 'card_content_oem.dart';
part 'card_content_panels.dart';

Map<String, dynamic> mapOf(dynamic value) =>
    value is Map ? Map<String, dynamic>.from(value) : {};

// Retained for callers using the original public IconData API.
IconData cardIcon(String type) =>
    const <String, IconData>{
      'nav': Icons.navigation_outlined,
      'trafficLight': Icons.traffic_outlined,
      'music': Icons.music_note_outlined,
      'weather': Icons.cloud_outlined,
      'calendar': Icons.calendar_month_outlined,
      'member': Icons.person_outline,
      'cleanup': Icons.cleaning_services_outlined,
      'tpms': Icons.tire_repair_outlined,
      'battery': Icons.battery_std_outlined,
      'air': Icons.air,
      'ride': Icons.local_taxi_outlined,
      'clock': Icons.schedule,
      'clockWeather': Icons.wb_cloudy_outlined,
      'shortcuts': Icons.apps,
      'vehicle': Icons.directions_car_outlined,
    }[type] ??
    Icons.apps;

String cardSymbol(String type) =>
    const {
      'trafficLight': 'traffic-light',
      'weather': 'cloud',
      'clockWeather': 'clock',
      'calendar': 'calendar',
      'member': 'user',
      'cleanup': 'broom',
      'tpms': 'tire',
      'battery': 'battery',
      'air': 'air',
      'vehicle': 'car',
      'shortcuts': 'apps',
    }[type] ??
    type;

class CardContent extends StatelessWidget {
  final LauncherCard card;
  final LauncherController controller;
  const CardContent({super.key, required this.card, required this.controller});
  @override
  Widget build(BuildContext context) => NativeSliceBuilder(
        valueListenable: controller.native,
        select: (native) => [
          native['demo'],
          for (final key in switch (card.type) {
            'nav' => ['navigation', 'apps', 'appNames'],
            'trafficLight' => [
                'trafficLights',
                'navigation',
                'apps',
                'appNames'
              ],
            'music' => ['media', 'apps', 'appNames', 'integrationPreferences'],
            'weather' || 'clockWeather' => ['weather'],
            'calendar' => ['calendar'],
            'member' => ['systemStatus'],
            'battery' || 'air' || 'vehicle' || 'tpms' || 'ride' => ['vehicle'],
            'shortcuts' => ['apps', 'appNames'],
            _ => <String>[],
          })
            native[key],
        ],
        builder: (context, native) => switch (card.type) {
          'trafficLight' => TrafficLightCard(
              snapshot: TrafficLightSnapshot.fromNative(native),
              title: card.title,
              editing: controller.editing,
              sourceLabel: controller.appName({
                'package': mapOf(native['navigation'])['package'],
                'label': mapOf(native['navigation'])['label'] ?? '地图导航',
              }),
              onOpenMap: mapOf(native['navigation'])['installed'] == true
                  ? () => controller.command('launch-navigation')
                  : null),
          'nav' => native['navigation'] is Map
              ? EmbeddedNavigationCard(
                  controller: controller,
                  navigation: mapOf(native['navigation']))
              : native['demo'] == true
                  ? const _NavigationDemo()
                  : _NavigationWaiting(card: card, controller: controller),
          'music' =>
            _MusicCard(card: card, controller: controller, state: native),
          'weather' => _WeatherCard(
              card: card,
              controller: controller,
              demo: native['demo'] == true,
              native: native,
              editing: controller.editing),
          'calendar' => OfficialCardEntry(
              type: 'calendar',
              label: '日历',
              controller: controller,
              child: _OemCard(
                  card: card,
                  controller: controller,
                  demo: native['demo'] == true)),
          'clock' => ClockCard(title: card.title),
          'clockWeather' => _ClockWeatherCardEntry(
              card: card, controller: controller, native: native),
          'battery' => BatteryCard(native: native, title: card.title),
          'air' => AirQualityCard(
              native: native,
              title: card.title == '空气质量' ? '车内空气' : card.title),
          'vehicle' => DrivingInfoCard(
              native: native,
              title: const ['车辆信息', '行驶信息'].contains(card.title)
                  ? '行车信息'
                  : card.title),
          'shortcuts' => _ShortcutCard(card: card, controller: controller),
          _ => _OemCard(
              card: card, controller: controller, demo: native['demo'] == true),
        },
      );
}

class _ClockWeatherCardEntry extends StatelessWidget {
  final LauncherCard card;
  final LauncherController controller;
  final Map<String, dynamic> native;
  const _ClockWeatherCardEntry(
      {required this.card, required this.controller, required this.native});
  @override
  Widget build(BuildContext context) {
    final enabled =
        !controller.editing && clockWeatherLayoutId(card.layout) != 'clock';
    return Material(
        type: MaterialType.transparency,
        child: InkWell(
            key: const ValueKey('clock-weather-card-open'),
            borderRadius:
                BorderRadius.circular(SurfaceStyle.of(context).radius),
            onTap:
                enabled ? () => showWeatherDetails(context, controller) : null,
            child: ClockWeatherCard(
                card: card, native: native, editing: controller.editing)));
  }
}

/// Only undersized grids use a smaller fitted canvas. Default sizes retain the
/// exact design measurements; even the 64 px edit strip leaves no overflowing row.
class _CardCanvas extends StatelessWidget {
  final Widget child;
  final double minWidth, minHeight;
  final bool padded;
  const _CardCanvas(
      {required this.child,
      this.minWidth = 340,
      this.minHeight = 240,
      this.padded = true});
  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, box) {
        final width = math.max(box.maxWidth, Design.px(minWidth));
        final height = math.max(box.maxHeight, Design.px(minHeight));
        final content = padded
            ? Padding(
                padding: EdgeInsets.symmetric(
                    horizontal: Design.px(30), vertical: Design.px(28)),
                child: child)
            : child;
        if (width == box.maxWidth && height == box.maxHeight) return content;
        return FittedBox(
            fit: BoxFit.contain,
            alignment: Alignment.center,
            child: SizedBox(width: width, height: height, child: content));
      });
}

class _Heading extends StatelessWidget {
  final String title, source, symbol;
  const _Heading(this.title, this.source, this.symbol);
  @override
  Widget build(BuildContext context) {
    final s = SurfaceStyle.of(context);
    return SizedBox(
        height: Design.px(32),
        child: Row(children: [
          UniIcon(symbol, size: Design.px(27), color: s.accent),
          SizedBox(width: Design.px(12)),
          Expanded(
              child: Text(title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: Design.px(25), height: 1.2))),
          if (!source.contains('原车') && !source.contains('官方'))
            SizedBox(width: Design.px(14)),
          if (!source.contains('原车') && !source.contains('官方'))
            Flexible(
                child: Text(source,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.end,
                    style: TextStyle(
                        fontSize: Design.px(16), height: 1.2, color: s.muted))),
        ]));
  }
}

class _OpenCardButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  final bool compact;
  const _OpenCardButton(this.label,
      {required this.onTap, this.compact = false});
  @override
  Widget build(BuildContext context) {
    final s = SurfaceStyle.of(context);
    final arrow = UniIcon('arrow-right', size: Design.px(22), color: s.text);
    return SizedBox(
        width: double.infinity,
        height: Design.px(compact ? 45 : 56),
        child: OutlinedButton(
            onPressed: onTap,
            style: OutlinedButton.styleFrom(
                minimumSize: Size.zero,
                padding: EdgeInsets.symmetric(horizontal: Design.px(12)),
                textStyle: TextStyle(fontSize: Design.px(compact ? 18 : 20))),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Flexible(
                  child: Text(label,
                      maxLines: 1, overflow: TextOverflow.ellipsis)),
              SizedBox(width: Design.px(10)),
              arrow,
            ])));
  }
}
