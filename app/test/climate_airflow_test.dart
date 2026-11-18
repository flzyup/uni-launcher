import 'package:flutter_test/flutter_test.dart';
import 'package:uni_launcher/widgets/climate_airflow.dart';

void main() {
  test('方向组合可往返转换，未知状态不会伪装为具体方向', () {
    for (var mask = 1; mask <= 7; mask++) {
      expect(airflowMask(airflowMode(mask)), mask);
    }
    expect(airflowMode(0), isNull);
    expect(airflowMask('auto'), 0);
    expect(airflowLabel(null), '风向未知');
  });
}
