/// Text mapping is source-independent. Numeric provider codes must be decoded
/// by that provider, never shared between CMA/QWeather/AMap.
enum WeatherKind {
  clear('晴'),
  partlyCloudy('晴间多云'),
  cloudy('多云'),
  overcast('阴'),
  shower('阵雨'),
  thunderstorm('雷阵雨'),
  hail('雷阵雨伴冰雹'),
  lightRain('小雨'),
  moderateRain('中雨'),
  heavyRain('大雨'),
  rainstorm('暴雨'),
  severeRainstorm('大暴雨'),
  extremeRainstorm('特大暴雨'),
  freezingRain('冻雨'),
  sleet('雨夹雪'),
  snowShower('阵雪'),
  lightSnow('小雪'),
  moderateSnow('中雪'),
  heavySnow('大雪'),
  blizzard('暴雪'),
  mist('轻雾'),
  fog('雾'),
  denseFog('浓雾'),
  severeFog('强浓雾'),
  haze('霾'),
  moderateHaze('中度霾'),
  heavyHaze('重度霾'),
  severeHaze('严重霾'),
  dust('浮尘'),
  blowingSand('扬沙'),
  sandstorm('沙尘暴'),
  severeSandstorm('强沙尘暴'),
  wind('大风'),
  gale('烈风'),
  tropicalStorm('热带风暴'),
  hot('热'),
  cold('冷'),
  unknown('未知');

  final String label;
  const WeatherKind(this.label);
  static WeatherKind fromText(Object? text) {
    final value = text?.toString().trim() ?? '';
    for (final k in values) {
      if (k.name == value || k.label == value) return k;
    }
    const aliases = {
      '少云': partlyCloudy,
      '晴转多云': partlyCloudy,
      '晴朗': clear,
      '阴天': overcast,
      '雷雨': thunderstorm,
      '雷电': thunderstorm,
      '冰雹': hail,
      '雨雪天气': sleet,
      '小到中雨': moderateRain,
      '中到大雨': heavyRain,
      '大到暴雨': rainstorm,
      '暴雨到大暴雨': severeRainstorm,
      '大暴雨到特大暴雨': extremeRainstorm,
      '小到中雪': moderateSnow,
      '中到大雪': heavySnow,
      '大到暴雪': blizzard,
      '雨': lightRain,
      '雪': lightSnow,
      '毛毛雨': lightRain,
      '细雨': lightRain,
      '雨凇': freezingRain,
      '薄雾': mist,
      '大雾': fog,
      '特强浓雾': severeFog,
      '中霾': moderateHaze,
      '重霾': heavyHaze,
      '沙尘': dust,
      '台风': tropicalStorm,
      '飓风': tropicalStorm,
      '强风': wind,
      '狂风': gale,
      'clear': clear,
      'sunny': clear,
      'cloudy': cloudy,
      'overcast': overcast,
      'rain': lightRain,
      'snow': lightSnow,
      'fog': fog,
      'haze': haze,
    };
    if (aliases.containsKey(value)) return aliases[value]!;
    // Transition reports describe current and subsequent conditions; prefer the latter.
    if (value.contains('转')) return fromText(value.split('转').last);
    return unknown;
  }

  /// WMO weather interpretation codes used by the optional forecast source.
  /// These codes are deliberately kept separate from the OEM provider codes.
  static WeatherKind fromWmo(Object? code) => switch (code) {
        0 => clear,
        1 || 2 => partlyCloudy,
        3 => overcast,
        45 => fog,
        48 => freezingRain,
        51 || 53 || 55 => lightRain,
        56 || 57 => freezingRain,
        61 => lightRain,
        63 => moderateRain,
        65 => heavyRain,
        66 || 67 => freezingRain,
        71 => lightSnow,
        73 => moderateSnow,
        75 => heavySnow,
        77 => snowShower,
        80 => shower,
        81 => moderateRain,
        82 => rainstorm,
        85 => snowShower,
        86 => heavySnow,
        95 => thunderstorm,
        96 || 99 => hail,
        _ => unknown,
      };
}

class WeatherForecast {
  final DateTime? date;
  final WeatherKind condition;
  final num? minimum, maximum, precipitation, windSpeed;
  const WeatherForecast(
      {required this.date,
      required this.condition,
      this.minimum,
      this.maximum,
      this.precipitation,
      this.windSpeed});

  factory WeatherForecast.fromNative(Map<dynamic, dynamic> raw) {
    final dateText = raw['date']?.toString();
    return WeatherForecast(
        date: dateText == null ? null : DateTime.tryParse(dateText),
        condition: raw['wmoCode'] is num
            ? WeatherKind.fromWmo((raw['wmoCode'] as num).toInt())
            : WeatherKind.fromText(raw['condition']),
        minimum: raw['minimum'] is num ? raw['minimum'] as num : null,
        maximum: raw['maximum'] is num ? raw['maximum'] as num : null,
        precipitation:
            raw['precipitation'] is num ? raw['precipitation'] as num : null,
        windSpeed: raw['windSpeed'] is num ? raw['windSpeed'] as num : null);
  }
}

class WeatherSnapshot {
  final WeatherKind condition;
  final bool night, available, forecastCityFallback;
  final String city,
      description,
      source,
      forecastSource,
      forecastReason,
      forecastLocation;
  final num? temperature,
      apparentTemperature,
      humidity,
      windSpeed,
      windDirection;
  final int? syncedAtMs, forecastUpdatedAtMs;
  final List<WeatherForecast> forecasts;
  const WeatherSnapshot(
      {required this.condition,
      required this.night,
      required this.available,
      required this.city,
      required this.description,
      required this.source,
      required this.forecastSource,
      required this.forecastReason,
      required this.forecasts,
      this.forecastLocation = '',
      this.forecastCityFallback = false,
      this.temperature,
      this.apparentTemperature,
      this.humidity,
      this.windSpeed,
      this.windDirection,
      this.syncedAtMs,
      this.forecastUpdatedAtMs});
  factory WeatherSnapshot.fromNative(Map<String, dynamic> n) {
    final raw = n['weather'] is Map ? n['weather'] as Map : const {};
    final demo = n['demo'] == true && raw['available'] != true;
    final available = raw['available'] == true;
    final text = raw['condition'] ?? raw['description'];
    final rawForecasts =
        raw['forecasts'] is List ? raw['forecasts'] as List : const [];
    final forecasts = rawForecasts
        .whereType<Map>()
        .map(WeatherForecast.fromNative)
        .toList(growable: false);
    final now = DateTime.now();
    return WeatherSnapshot(
        condition: available
            ? WeatherKind.fromText(text)
            : demo
                ? WeatherKind.cloudy
                : WeatherKind.unknown,
        night: raw['night'] == true,
        available: available || demo,
        city: available
            ? '${raw['city'] ?? '天气'}'
            : demo
                ? n['simulationMode'] == 'highFidelity'
                    ? '上海市 · 黄浦区'
                    : '杭州'
                : '天气',
        description: available
            ? (text?.toString() ?? '未知')
            : demo
                ? '多云'
                : '—',
        source: available
            ? '${raw['source'] ?? '原车天气'}'
            : demo
                ? '天气示例'
                : '原车天气',
        forecastSource: forecasts.isNotEmpty
            ? '${raw['forecastSource'] ?? '天气预报'}'
            : demo
                ? '天气示例'
                : '',
        forecastReason: '${raw['forecastReason'] ?? ''}',
        forecastLocation: '${raw['forecastLocation'] ?? ''}',
        forecastCityFallback: raw['forecastCityFallback'] == true,
        forecasts: forecasts.isNotEmpty
            ? forecasts
            : demo
                ? List.generate(
                    5,
                    (index) => WeatherForecast(
                        date: DateTime(now.year, now.month, now.day + index),
                        condition: const [
                          WeatherKind.cloudy,
                          WeatherKind.partlyCloudy,
                          WeatherKind.lightRain,
                          WeatherKind.overcast,
                          WeatherKind.clear
                        ][index],
                        minimum: 17 + index,
                        maximum: 24 + index,
                        precipitation: const [20, 10, 70, 30, 5][index],
                        windSpeed: 12 + index))
                : const [],
        temperature: available
            ? (raw['temperature'] is num ? raw['temperature'] as num : null)
            : demo
                ? 24
                : null,
        apparentTemperature: raw['apparentTemperature'] is num
            ? raw['apparentTemperature'] as num
            : demo
                ? 25
                : null,
        humidity: raw['humidity'] is num
            ? raw['humidity'] as num
            : demo
                ? 62
                : null,
        windSpeed: raw['windSpeed'] is num
            ? raw['windSpeed'] as num
            : demo
                ? 12
                : null,
        windDirection:
            raw['windDirection'] is num ? raw['windDirection'] as num : null,
        syncedAtMs: raw['syncedAtMs'] is num
            ? (raw['syncedAtMs'] as num).toInt()
            : null,
        forecastUpdatedAtMs: raw['forecastUpdatedAtMs'] is num
            ? (raw['forecastUpdatedAtMs'] as num).toInt()
            : null);
  }
}
