import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// Original 32 × 32 line symbols shared with design/index.html.
class UniIcon extends StatelessWidget {
  final String name;
  final double size;
  final Color? color;
  const UniIcon(this.name, {super.key, this.size = 24, this.color});
  @override
  Widget build(BuildContext context) => SvgPicture.asset(
        'assets/icons/$name.svg',
        width: size,
        height: size,
        colorFilter: ColorFilter.mode(
            color ?? IconTheme.of(context).color ?? Colors.white,
            BlendMode.srcIn),
        excludeFromSemantics: true,
      );
}

final _originalIcons = <IconData, String>{
  Icons.settings_outlined: 'settings',
  Icons.home_outlined: 'home',
  Icons.apps: 'apps',
  Icons.air: 'fan',
  Icons.power_settings_new: 'power',
  Icons.skip_previous_outlined: 'back',
  Icons.skip_next_outlined: 'next',
  Icons.pause: 'pause',
  Icons.play_arrow: 'play',
  Icons.directions_car_outlined: 'car',
  Icons.surround_sound_outlined: 'camera-360',
  Icons.remove: 'minus',
  Icons.add: 'plus',
  Icons.close: 'close',
  Icons.arrow_back: 'arrow-left',
  Icons.arrow_forward: 'arrow-right',
  Icons.edit_outlined: 'edit',
  Icons.drag_indicator: 'move',
  Icons.open_in_full: 'fullscreen-diagonal',
  Icons.navigation_outlined: 'nav',
  Icons.music_note_outlined: 'music',
  Icons.cloud_outlined: 'cloud',
  Icons.location_on_outlined: 'pin',
  Icons.schedule: 'clock',
  Icons.calendar_month_outlined: 'calendar',
  Icons.person_outline: 'user',
  Icons.cleaning_services_outlined: 'broom',
  Icons.tire_repair_outlined: 'tire',
  Icons.battery_std_outlined: 'battery',
  Icons.local_gas_station_outlined: 'fuel',
  Icons.local_taxi_outlined: 'ride',
  Icons.check: 'check',
  Icons.light_mode_outlined: 'sun',
  Icons.dark_mode_outlined: 'moon',
  Icons.brightness_auto_outlined: 'auto-theme',
  Icons.turn_right: 'turn',
};
String? originalIconName(IconData icon) => _originalIcons[icon];

class DesignIcon extends StatelessWidget {
  final IconData icon;
  final double size;
  final Color? color;
  const DesignIcon(this.icon, {super.key, this.size = 24, this.color});
  @override
  Widget build(BuildContext context) {
    final name = originalIconName(icon);
    return name == null
        ? Icon(icon, size: size, color: color)
        : UniIcon(name, size: size, color: color);
  }
}
