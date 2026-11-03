import 'vehicle_data.dart';

const vehicleModeLabels = {
  'ECO': '经济',
  'COMFORT': '舒适',
  'DYNAMIC': '运动',
  'INDIVIDUAL': '个性',
  'XC': '越野',
  'HDC': '陡坡缓降',
  'PURE': '纯电',
  'HYBRID': '混动',
  'POWER': '动力',
  'RACE': '赛道',
  'ECO_HEV_PHEV': '混动经济',
  'COMFORT_HEV': '混动舒适',
};
const vehicleEnergyLabels = {
  'NOT_READY': '未就绪',
  'MAIN_CHARGING': '主充电',
  'BOOST': '动力助力',
  'EAWD': '电动四驱',
  'ENGINE_ONLY': '发动机驱动',
  'ENGINE_ONLY_AND_CHARGE': '发动机驱动并发电',
  'ELECTRIC_DRIVE': '电力驱动',
  'STANDSTILL_ENGINE_OFF': '静止 · 发动机关闭',
  'STANDSTILL_ENGINE_ON': '静止 · 发动机运行',
  'STANDSTILL_ENGINE_ON_CHARGE': '静止发电',
  'ENGINE_OFF_REGEN_BRAKE': '制动回收',
  'ENGINE_ON_REGEN_BRAKE': '发动机运行 · 回收',
  'ENGINE_ON_REGEN_BRAKE_CHARGE': '制动回收并发电',
};

/// Each status comes from its own valid HAL property; battery SOC supplies none.
String vehicleStatusLabel(Map<String, dynamic> native, String key,
    {int? nowMs}) {
  final vehicle = native['vehicle'];
  if (vehicle is! Map || vehicle['connected'] != true) return '未连接';
  final fields = vehicle['fields'];
  final field = fields is Map ? fields[key] : null;
  if (field is! Map) return '待同步';
  final stamp = field['updatedAtMs'];
  if (stamp is! num || !stamp.isFinite || stamp <= 0 || field['valid'] != true)
    return '待同步';
  final age = (nowMs ?? DateTime.now().millisecondsSinceEpoch) - stamp;
  if (age < -1000 || age > 5000) return '等待更新';
  final value = field['value'];
  if (key == 'driveMode') return vehicleModeLabels[value] ?? '待同步';
  if (key == 'energyFlow') return vehicleEnergyLabels[value] ?? '待同步';
  if (key == 'hybridSelected' && value is bool) return value ? '已选混动' : '未选混动';
  return '待同步';
}

enum VehicleReadingState {
  live,
  disconnected,
  stale,
  unconfirmedUnit,
  unavailable
}

/// Read-only presentation of the seven official vehicle sensor fields.
/// Raw/sampleValue/SDK defaults never substitute for a valid field value.
class VehicleCardReading {
  final double? value;
  final String unit;
  final VehicleReadingState state;
  final int updatedAtMs;
  const VehicleCardReading._(
      this.value, this.unit, this.state, this.updatedAtMs);

  bool get available => value != null;
  String get status => switch (state) {
        VehicleReadingState.live => '已同步',
        VehicleReadingState.disconnected => '未连接',
        VehicleReadingState.stale => '等待更新',
        VehicleReadingState.unconfirmedUnit => '单位待确认',
        VehicleReadingState.unavailable => '暂无数据',
      };
  String get display {
    if (value == null) return '\u2014';
    if (unit == 'km/h') {
      if (value! <= 0.5) return '0';
      final offset = value! < 3.0 ? (value! - 0.5) * (2.0 / 2.5) : 2.0;
      return (value! + offset).round().toString();
    }
    if (unit == 'mph') {
      return value!.round().toString();
    }
    final text = value!.toStringAsFixed(1);
    return text.endsWith('.0') ? text.substring(0, text.length - 2) : text;
  }

  factory VehicleCardReading.fromNative(Map<String, dynamic> native, String key,
      {int? nowMs}) {
    final vehicle =
        native['vehicle'] is Map ? native['vehicle'] as Map : const {};
    final fields =
        vehicle['fields'] is Map ? vehicle['fields'] as Map : const {};
    final field = fields[key] is Map ? fields[key] as Map : const {};
    final timestamp = field['updatedAtMs'];
    final updated =
        timestamp is num && timestamp.isFinite ? timestamp.toInt() : 0;
    VehicleCardReading missing(VehicleReadingState state) =>
        VehicleCardReading._(null, '', state, updated);
    if (vehicle['connected'] != true) {
      return missing(VehicleReadingState.disconnected);
    }
    final age = (nowMs ?? DateTime.now().millisecondsSinceEpoch) - updated;
    if (updated > 0 && age > 5000) return missing(VehicleReadingState.stale);
    final unit = '${field['unit'] ?? ''}'.replaceAll('μ', 'µ');
    final allowed = switch (key) {
      'batteryPercent' || 'fuelPercent' => const ['%'],
      'fuelLiters' => const ['L'],
      'pm25' => const ['µg/m³'],
      'aqi' => const [''],
      'speed' => const ['km/h', 'mph', 'm/s'],
      'odometer' || 'range' || 'maintenanceMileage' => const ['km', 'mi'],
      _ => const <String>[],
    };
    final driving = const ['speed', 'odometer', 'range', 'maintenanceMileage']
        .contains(key);
    final unitConfirmed = allowed.contains(unit) &&
        (driving
            ? field['unitVerified'] == true
            : field['unitVerified'] != false);
    if (!unitConfirmed &&
        (field['valid'] == true || field['sampleValid'] == true)) {
      return missing(VehicleReadingState.unconfirmedUnit);
    }
    // Reuse the existing per-field connection/validity/5-second contract after
    // validating the timestamp type, so malformed input cannot throw.
    if (updated <= 0 || timestamp is! num || !timestamp.isFinite) {
      return missing(VehicleReadingState.unavailable);
    }
    final reading = VehicleField.fromNative(native, key, nowMs: nowMs);
    final value = reading.value;
    if (!reading.valid ||
        !unitConfirmed ||
        value is! num ||
        !value.isFinite ||
        value < 0 ||
        (const ['batteryPercent', 'fuelPercent'].contains(key) &&
            value > 100)) {
      return missing(VehicleReadingState.unavailable);
    }
    return VehicleCardReading._(
        value.toDouble(), unit, VehicleReadingState.live, updated);
  }
}

enum PowertrainType { ice, ev, phev }

PowertrainType detectPowertrain(Map<String, dynamic> native, {int? nowMs}) {
  final vehicle =
      native['vehicle'] is Map ? native['vehicle'] as Map : const {};
  final declared = '${vehicle['powertrainType'] ?? ''}';
  if (declared == 'FUEL') return PowertrainType.ice;
  if (declared == 'BEV') return PowertrainType.ev;
  if (declared == 'PHEV' ||
      declared == 'HEV' ||
      declared == 'MHEV' ||
      declared == 'EREV') {
    return PowertrainType.phev;
  }
  final fields =
      vehicle['fields'] is Map ? vehicle['fields'] as Map : const {};
  final hasBattery = _isFieldUsable(fields, 'batteryPercent', nowMs);
  final hasFuel = _isFieldUsable(fields, 'fuelPercent', nowMs) ||
      _isFieldUsable(fields, 'fuelLiters', nowMs);
  final hasRange = _isFieldUsable(fields, 'range', nowMs);
  final capacity = vehicle['fuelCapacity'];
  final hasFuelCapacity = capacity is num && capacity > 0;

  if (hasBattery && hasFuel) return PowertrainType.phev;
  if (hasFuel) return PowertrainType.ice;
  if (hasBattery) return PowertrainType.ev;
  if (!hasBattery && (hasFuelCapacity || hasRange)) {
    return PowertrainType.ice;
  }
  return PowertrainType.phev;
}

bool _isFieldUsable(Map fields, String key, int? nowMs) {
  final f = fields[key];
  if (f is! Map || f['valid'] != true) return false;
  final stamp = f['updatedAtMs'];
  if (stamp is! num || !stamp.isFinite || stamp <= 0) return false;
  if (nowMs != null) {
    final age = nowMs - stamp;
    if (age < -1000 || age > 5000) return false;
  }
  return true;
}
