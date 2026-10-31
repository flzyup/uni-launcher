import 'package:flutter_test/flutter_test.dart';
import 'package:uni_launcher/widgets/vehicle_visuals.dart';

void main() {
  test('partial closed data does not claim all openings are closed', () {
    expect(const VehicleDoorSnapshot(frontLeft: false).statusLabel, '部分车门状态未知');
    expect(const VehicleDoorSnapshot(frontLeft: true).statusLabel, '左前门开启');
    expect(
      const VehicleDoorSnapshot(frontLeft: false, frontRight: false,
          rearLeft: false, rearRight: false, tailgate: false, hood: false)
          .statusLabel,
      '车门均已关闭',
    );
  });
}
