import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// Cabin outline and direction of airflow. Null means the vehicle has not
/// reported a trustworthy circulation state; it must not imply fresh air.
class CirculationIcon extends StatelessWidget {
  final bool? recirculating;
  final Color color;
  final double size;
  const CirculationIcon(
      {super.key,
      required this.recirculating,
      required this.color,
      this.size = 28});

  @override
  Widget build(BuildContext context) => SizedBox(
      width: size * 1.6,
      height: size,
      child: SvgPicture.asset(
          'assets/icons/climate-air-${recirculating == null ? 'unknown' : recirculating! ? 'inner' : 'outer'}.svg',
          colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
          excludeFromSemantics: true));
}
