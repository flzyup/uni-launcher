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
import 'card_glyph.dart';
import 'choice_button.dart';
import 'glass_surface.dart';
import 'launcher_dialog.dart';
import 'dock_window_scope.dart';
import 'canvas_scope.dart';
import 'uni_icon.dart';
import 'lyrics_view.dart';
import 'media_progress.dart';
import 'embedded_navigation.dart';
import 'media_artwork.dart';
import 'marquee_text.dart';
import 'audio_spectrum.dart';
import 'media_source_badge.dart';
import 'music_action_buttons.dart';
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

export 'vehicle_visuals.dart' show CardRing, TireDiagram, VehicleDoorSnapshot;

part 'card_content_music.dart';
part 'card_content_navigation.dart';
part 'card_content_oem.dart';
part 'card_content_panels.dart';
part 'music_player_page.dart';

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
      'body': Icons.directions_car_outlined,
      'battery': Icons.battery_std_outlined,
      'fuel': Icons.local_gas_station_outlined,
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
      'body': 'car',
      'battery': 'battery',
      'fuel': 'fuel',
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
            'nav' => [
                'navigation',
                'apps',
                'appNames',
                'integrationPreferences'
              ],
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
            'battery' || 'fuel' || 'air' || 'vehicle' || 'tpms' || 'body' || 'ride' => [
                'vehicle'
              ],
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
          'fuel' => FuelCard(native: native, title: card.title),
          'air' => AirQualityCard(
              native: native,
              title: card.title == '空气质量' ? '车内空气' : card.title),
          'vehicle' => DrivingInfoCard(
              native: native,
              title: const ['车辆信息', '行驶信息'].contains(card.title)
                  ? '行车信息'
                  : card.title),
          'body' => _BodyCard(card: card, native: native),
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

  /// 稿子 `.card-hd` 的第二行（`.k-sub`）。不传就把 [source] 当副标题——
  /// '原车/官方' 那类来源标注是给维护者看的，不该占副标题位置。
  final String? sub;

  /// 稿子卡片头的图形名（[CardGlyph]）。不传按 [symbol] 推：同一张图在稿子里
  /// 有两种画法的（车况与胎压 vs 行车信息都用 car.svg）要显式传。
  final String? kind;
  const _Heading(this.title, this.source, this.symbol,
      {this.sub, this.kind});

  @override
  Widget build(BuildContext context) {
    final s = SurfaceStyle.of(context);
    final fallback =
        !source.contains('原车') && !source.contains('官方') ? source : '';
    final secondary = (sub ?? fallback).trim();
    // 稿子 `.card-hd`：44 图标 + 两行（`.k-label` 11.5/600/字距 .2em + `.k-sub` 13），
    // gap 12。原来是「图标 + 一行标题 + 右侧来源」，副标题这一行整个缺失。
    return Row(children: [
      // 稿子 `.card-hd .ic`：44 见方的虚线开口环 + 环内渐变线描，不是一张
      // 通用线性图标。中心对齐，行高由这块 44 决定（文字块只有 33.4）。
      SizedBox(
          width: Design.px(52.8),
          height: Design.px(52.8),
          child: Center(
              child: CardGlyph(kind ?? glyphKindForSymbol(symbol),
                  symbol: symbol, size: 52.8))),
      SizedBox(width: Design.px(14.4)),
      Expanded(
          child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
            Text(title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: Design.px(13.8),
                    height: 1.2,
                    fontWeight: FontWeight.w600,
                    letterSpacing: Design.px(2.76),
                    color: s.text.withValues(alpha: .55))),
            if (secondary.isNotEmpty) ...[
              SizedBox(height: Design.px(4.8)),
              Text(secondary,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: Design.px(15.6),
                      height: 1.2,
                      color: s.muted)),
            ],
          ])),
    ]);
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
