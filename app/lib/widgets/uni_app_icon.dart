import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

class UniAppIcon extends StatelessWidget {
  final double size;
  final BorderRadius? radius;
  const UniAppIcon({super.key, required this.size, this.radius});

  @override
  Widget build(BuildContext context) => ClipRRect(
      borderRadius: radius ?? BorderRadius.circular(size * .12),
      child: SvgPicture.asset('assets/art/uni-app-icon.svg',
          width: size, height: size, fit: BoxFit.cover));
}
