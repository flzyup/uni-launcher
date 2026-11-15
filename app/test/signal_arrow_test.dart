import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uni_launcher/widgets/signal_arrow.dart';

void main() {
  test('稿子两条路径 + 镜像 + 掉头都画得出来', () {
    for (final direction in ['left', 'straight', 'right', 'uturn']) {
      final path = SignalArrowPaths.of(direction);
      expect(path, isNotNull, reason: direction);
      // 路径要闭合、有面积：只画一条线或者空路径都会在 metrics 上露馅。
      expect(path!.getBounds().width, greaterThan(9), reason: direction);
      expect(path.getBounds().height, greaterThan(6), reason: direction);
    }
    // 未知方向交给调用方兜底。
    expect(SignalArrowPaths.of('unknown'), isNull);
    expect(SignalArrowPaths.of(''), isNull);
  });

  test('四个方向都落在 24 视口内，右转不额外扩边', () {
    for (final direction in ['left', 'straight', 'right', 'uturn']) {
      final Rect bounds = SignalArrowPaths.of(direction)!.getBounds();
      expect(bounds.left, greaterThanOrEqualTo(0), reason: direction);
      expect(bounds.top, greaterThanOrEqualTo(0), reason: direction);
      expect(bounds.right, lessThanOrEqualTo(SignalArrow.viewBox),
          reason: direction);
      expect(bounds.bottom, lessThanOrEqualTo(SignalArrow.viewBox),
          reason: direction);
    }
    // 右转沿竖直轴镜像左转，所以两者包围盒一模一样（镜像发生在画的时候）。
    expect(SignalArrowPaths.of('right')!.getBounds(),
        SignalArrowPaths.of('left')!.getBounds());
    expect(SignalArrowPaths.mirrored('right'), isTrue);
    expect(SignalArrowPaths.mirrored('left'), isFalse);
  });

  test('左转那颗箭头有弯角：纵向跨度远大于一根横线', () {
    // 旧图标是一根横线加箭头，采样点几乎全落在同一条 y 上；稿子这条左转路径
    // 先向上、再拐弯、箭头朝左，整条外框纵跨 15 个单位。
    final metrics = SignalArrowPaths.of('left')!.computeMetrics().toList();
    expect(metrics.length, 1);
    final ys = <double>[];
    for (var i = 0; i <= 64; i++) {
      final tangent =
          metrics.single.getTangentForOffset(metrics.single.length * i / 64)!;
      ys.add(tangent.position.dy);
    }
    expect(ys.reduce((a, b) => a < b ? a : b), lessThan(16));
    expect(
        ys.reduce((a, b) => a > b ? a : b) - ys.reduce((a, b) => a < b ? a : b),
        greaterThan(10));
  });
}
