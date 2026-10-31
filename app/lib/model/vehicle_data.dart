/// A field is usable only while its own read is valid and fresh.
class VehicleField {
  final Object? value;
  final String unit, source;
  final bool valid;
  const VehicleField(
      {this.value, this.unit = '', this.source = '', this.valid = false});
  factory VehicleField.fromNative(Map<String, dynamic> native, String key,
      {int? nowMs}) {
    final vehicle =
        native['vehicle'] is Map ? native['vehicle'] as Map : const {};
    final fields =
        vehicle['fields'] is Map ? vehicle['fields'] as Map : const {};
    final field = fields[key] is Map ? fields[key] as Map : const {};
    final timestamp = (field['updatedAtMs'] as num?)?.toInt() ?? 0;
    final age = (nowMs ?? DateTime.now().millisecondsSinceEpoch) - timestamp;
    final valid = vehicle['connected'] == true &&
        field['valid'] == true &&
        timestamp > 0 &&
        age >= -1000 &&
        age <= 5000;
    return VehicleField(
        value: valid ? field['value'] : null,
        unit: '${field['unit'] ?? ''}',
        source: '${field['source'] ?? ''}',
        valid: valid);
  }
  String display({int decimals = 1}) => !valid
      ? '—'
      : value is num
          ? (value as num).toStringAsFixed(decimals)
          : value == true
              ? '开启'
              : value == false
                  ? '关闭'
                  : '$value';
}

/// A valid reading and a matching writable capability are both required.
bool climateWritable(Map<String, dynamic> native, String key) {
  if (native['demo'] == true) return true;
  final vehicle =
      native['vehicle'] is Map ? native['vehicle'] as Map : const {};
  final capabilities = vehicle['climateCapabilities'] is Map
      ? vehicle['climateCapabilities'] as Map
      : const {};
  final capability =
      capabilities[key] is Map ? capabilities[key] as Map : const {};
  final field = VehicleField.fromNative(native, key);
  final powerOffFallback = key == 'power' &&
      vehicle['connected'] == true &&
      capability['supported'] == true &&
      (native['climate'] is Map ? native['climate'] as Map : const {})['power'] == false;
  return !vehicleCommandPending(native) &&
      capability['writable'] == true &&
      (field.valid || powerOffFallback);
}

bool vehicleCommandPending(Map<String, dynamic> native) {
  final vehicle =
      native['vehicle'] is Map ? native['vehicle'] as Map : const {};
  final command =
      vehicle['lastCommand'] is Map ? vehicle['lastCommand'] as Map : const {};
  return command['status'] == 'queued' || command['status'] == 'sent';
}

String vehicleCommandLabel(Map<String, dynamic> native) {
  final vehicle =
      native['vehicle'] is Map ? native['vehicle'] as Map : const {};
  final command =
      vehicle['lastCommand'] is Map ? vehicle['lastCommand'] as Map : const {};
  return switch (command['status']) {
    'queued' || 'sent' => '正在等待车辆确认…',
    'confirmed' => '已同步车辆状态',
    'unchanged' => '当前已是所选状态',
    'failed' || 'timeout' || 'cancelled' => '车辆未确认，请稍后重试',
    _ => '',
  };
}
