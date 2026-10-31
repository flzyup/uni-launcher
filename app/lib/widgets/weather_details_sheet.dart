import 'dart:async';
import 'package:flutter/material.dart';
import '../controller/launcher_controller.dart';
import '../model/weather_condition.dart';
import '../theme/design_tokens.dart';
import '../theme/launcher_theme.dart';
import 'glass_surface.dart';
import 'launcher_dialog.dart';
import 'weather_icon.dart';

Future<void> showWeatherDetails(
    BuildContext context, LauncherController controller) async {
  unawaited(controller.command('weather-forecast-refresh'));
  await showLauncherSheet<void>(context,
      title: '天气详情',
      subtitle: '当前天气与未来预报',
      closeLabel: '关闭天气详情',
      width: Design.px(1320),
      height: Design.px(740),
      builder: (_) => ValueListenableBuilder<Map<String, dynamic>>(
          valueListenable: controller.native,
          builder: (context, native, __) => WeatherDetailsContent(
              weather: WeatherSnapshot.fromNative(native))));
}

class WeatherDetailsContent extends StatelessWidget {
  final WeatherSnapshot weather;
  const WeatherDetailsContent({super.key, required this.weather});

  String _number(num? value, {String suffix = ''}) {
    if (value == null) return '—';
    final text = value == value.roundToDouble()
        ? value.toInt().toString()
        : value.toStringAsFixed(1);
    return '$text$suffix';
  }

  String _time(int? milliseconds) {
    if (milliseconds == null) return '—';
    final value = DateTime.fromMillisecondsSinceEpoch(milliseconds);
    return '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';
  }

  String _windDirection(num? degrees) {
    if (degrees == null) return '';
    const names = ['北', '东北', '东', '东南', '南', '西南', '西', '西北'];
    return '${names[((degrees.toDouble() + 22.5) ~/ 45) % 8]}风 ';
  }

  @override
  Widget build(BuildContext context) {
    final s = SurfaceStyle.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SizedBox(
          height: Design.px(220),
          child: GlassSurface(
              key: const ValueKey('weather-current-detail'),
              tone: SurfaceTone.soft,
              shadow: false,
              padding: EdgeInsets.symmetric(
                  horizontal: Design.px(30), vertical: Design.px(24)),
              child: Row(children: [
                WeatherIcon(
                    condition: weather.condition,
                    night: weather.night,
                    size: Design.px(126),
                    color: s.accent),
                SizedBox(width: Design.px(28)),
                SizedBox(
                    width: Design.px(250),
                    child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(weather.city,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  color: s.muted, fontSize: Design.px(22))),
                          SizedBox(height: Design.px(8)),
                          Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(_number(weather.temperature),
                                    style: TextStyle(
                                        fontSize: Design.px(72),
                                        height: .95,
                                        fontWeight: FontWeight.w300)),
                                Text('°',
                                    style: TextStyle(fontSize: Design.px(38)))
                              ]),
                          SizedBox(height: Design.px(8)),
                          Text(weather.description,
                              style: TextStyle(fontSize: Design.px(24)))
                        ])),
                Container(width: 1, height: Design.px(150), color: s.edge),
                SizedBox(width: Design.px(34)),
                Expanded(
                    child: Wrap(
                        spacing: Design.px(18),
                        runSpacing: Design.px(16),
                        children: [
                      _WeatherMetric(
                          icon: Icons.thermostat_outlined,
                          label: '体感温度',
                          value: _number(weather.apparentTemperature,
                              suffix: '°')),
                      _WeatherMetric(
                          icon: Icons.water_drop_outlined,
                          label: '相对湿度',
                          value: _number(weather.humidity, suffix: '%')),
                      _WeatherMetric(
                          icon: Icons.air,
                          label: '风速',
                          value:
                              '${_windDirection(weather.windDirection)}${_number(weather.windSpeed, suffix: ' km/h')}'),
                      _WeatherMetric(
                          icon: Icons.update,
                          label: '当前天气更新',
                          value: _time(weather.syncedAtMs)),
                    ]))
              ]))),
      SizedBox(height: Design.px(24)),
      Row(children: [
        Text('未来天气',
            style: TextStyle(
                fontSize: Design.px(27), fontWeight: FontWeight.w500)),
        SizedBox(width: Design.px(16)),
        if (weather.forecastLocation.isNotEmpty) ...[
          Flexible(
              child: Text(
                  '${weather.forecastLocation}${weather.forecastCityFallback ? ' · 城市预报' : ''}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: Design.px(17), color: s.muted))),
          SizedBox(width: Design.px(16)),
        ],
        if (weather.forecastUpdatedAtMs != null)
          Text('更新于 ${_time(weather.forecastUpdatedAtMs)}',
              style: TextStyle(fontSize: Design.px(17), color: s.muted)),
        const Spacer(),
        if (weather.forecastSource.isNotEmpty)
          Text('数据来源：${weather.forecastSource}',
              style: TextStyle(fontSize: Design.px(17), color: s.muted))
      ]),
      SizedBox(height: Design.px(16)),
      Expanded(
          child: weather.forecasts.isEmpty
              ? _ForecastUnavailable(reason: weather.forecastReason)
              : Row(children: [
                  for (int i = 0;
                      i < weather.forecasts.length && i < 7;
                      i++) ...[
                    if (i > 0) SizedBox(width: Design.px(14)),
                    Expanded(
                        child: _ForecastDay(
                            forecast: weather.forecasts[i], index: i))
                  ]
                ])),
    ]);
  }
}

class _WeatherMetric extends StatelessWidget {
  final IconData icon;
  final String label, value;
  const _WeatherMetric(
      {required this.icon, required this.label, required this.value});
  @override
  Widget build(BuildContext context) {
    final s = SurfaceStyle.of(context);
    return SizedBox(
        width: Design.px(270),
        child: Row(children: [
          Container(
              width: Design.px(48),
              height: Design.px(48),
              decoration: BoxDecoration(
                  color: s.accent.withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(s.controlRadius)),
              child: Icon(icon, size: Design.px(25), color: s.accent)),
          SizedBox(width: Design.px(13)),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(label,
                    style: TextStyle(fontSize: Design.px(16), color: s.muted)),
                SizedBox(height: Design.px(3)),
                Text(value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: Design.px(20)))
              ]))
        ]));
  }
}

class _ForecastDay extends StatelessWidget {
  final WeatherForecast forecast;
  final int index;
  const _ForecastDay({required this.forecast, required this.index});

  String _label() {
    if (index == 0) return '今天';
    if (index == 1) return '明天';
    const weekdays = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
    return forecast.date == null
        ? '第 ${index + 1} 天'
        : weekdays[forecast.date!.weekday - 1];
  }

  String _temperature(num? value) => value == null ? '—' : '${value.round()}°';

  @override
  Widget build(BuildContext context) {
    final s = SurfaceStyle.of(context);
    return GlassSurface(
        key: ValueKey('weather-forecast-$index'),
        tone: SurfaceTone.soft,
        shadow: false,
        borderColor: index == 0 ? s.accent : null,
        padding: EdgeInsets.symmetric(
            horizontal: Design.px(12), vertical: Design.px(18)),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Text(_label(), style: TextStyle(fontSize: Design.px(20))),
          if (forecast.date != null) ...[
            SizedBox(height: Design.px(4)),
            Text('${forecast.date!.month}/${forecast.date!.day}',
                style: TextStyle(fontSize: Design.px(15), color: s.muted))
          ],
          const Spacer(),
          WeatherIcon(
              condition: forecast.condition,
              night: false,
              size: Design.px(70),
              color: s.accent),
          SizedBox(height: Design.px(8)),
          Text(forecast.condition.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: Design.px(18))),
          SizedBox(height: Design.px(10)),
          Text(
              '${_temperature(forecast.maximum)} / ${_temperature(forecast.minimum)}',
              style: TextStyle(
                  fontSize: Design.px(21), fontWeight: FontWeight.w500)),
          SizedBox(height: Design.px(8)),
          Text(
              forecast.precipitation == null
                  ? '降水 —'
                  : '降水 ${forecast.precipitation!.round()}%',
              style: TextStyle(fontSize: Design.px(15), color: s.muted)),
        ]));
  }
}

class _ForecastUnavailable extends StatelessWidget {
  final String reason;
  const _ForecastUnavailable({required this.reason});
  @override
  Widget build(BuildContext context) {
    final s = SurfaceStyle.of(context);
    return GlassSurface(
        key: const ValueKey('weather-forecast-unavailable'),
        tone: SurfaceTone.soft,
        shadow: false,
        child: Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.cloud_sync_outlined, size: Design.px(50), color: s.muted),
          SizedBox(height: Design.px(16)),
          Text('未来天气暂不可用', style: TextStyle(fontSize: Design.px(23))),
          SizedBox(height: Design.px(8)),
          Text(reason.isEmpty ? '原车接口仅提供当前天气，联网后会自动补充未来预报' : reason,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: Design.px(17), color: s.muted))
        ])));
  }
}
