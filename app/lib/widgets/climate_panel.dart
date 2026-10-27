import 'package:flutter/material.dart';
import '../controller/launcher_controller.dart';
import '../theme/design_tokens.dart';
import '../theme/launcher_theme.dart';
import 'glass_surface.dart';
import 'uni_icon.dart';
import 'circulation_icon.dart';
import '../model/vehicle_data.dart';
import 'launcher_dialog.dart';
import 'seat_controls.dart';
import 'card_content.dart' show mapOf;

Future<void> showClimatePanel(
    BuildContext context, LauncherController c) async {
  if (await c.presentGlobalPanel('climate') || !context.mounted) return;
  await showLauncherSheet<void>(context,
      title: '座舱舒适',
      subtitle: c.native.value['demo'] == true ? '操作预览 · 不控制车辆' : '空调与座椅',
      closeLabel: '关闭空调',
      width: Design.px(1120),
      builder: (context) => ValueListenableBuilder<Map<String, dynamic>>(
          valueListenable: c.native,
          builder: (context, n, _) {
            final s = SurfaceStyle.of(context),
                demo = n['demo'] == true,
                climate = mapOf(n['climate']);
            final autoField = VehicleField.fromNative(n, 'auto');
            final fanField = VehicleField.fromNative(n, 'fan');
            final automatic = demo
                ? climate['auto'] == true
                : (autoField.valid && autoField.value == true) ||
                    (fanField.valid &&
                        '${fanField.value}'.toLowerCase() == 'auto');
            Widget step(String label, IconData icon, VoidCallback? tap) =>
                IconAction(
                    icon: icon,
                    label: label,
                    size: Design.px(64),
                    iconSize: Design.px(32),
                    soft: true,
                    onTap: tap);
            return SingleChildScrollView(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                  SizedBox(height: Design.px(10)),
                  Row(children: [
                    for (final zone in ['left', 'right']) ...[
                      if (zone == 'right') SizedBox(width: Design.px(50)),
                      Expanded(
                          child: Column(children: [
                        Text(zone == 'left' ? '主驾' : '副驾',
                            style: TextStyle(
                                fontSize: Design.px(23), color: s.muted)),
                        SizedBox(height: Design.px(24)),
                        Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              step(
                                  '降低${zone == 'left' ? '主驾' : '副驾'}温度',
                                  Icons.remove,
                                  climateWritable(n, zone)
                                      ? () => c.command('temp-down', zone: zone)
                                      : null),
                              Text(
                                  demo
                                      ? '${(climate[zone] as num? ?? 22.5).toStringAsFixed(1)}°'
                                      : '${VehicleField.fromNative(n, zone).display()}°',
                                  style: TextStyle(
                                      fontSize: Design.px(64),
                                      fontWeight: FontWeight.w300)),
                              step(
                                  '提高${zone == 'left' ? '主驾' : '副驾'}温度',
                                  Icons.add,
                                  climateWritable(n, zone)
                                      ? () => c.command('temp-up', zone: zone)
                                      : null)
                            ])
                      ]))
                    ]
                  ]),
                  SizedBox(height: Design.px(42)),
                  Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    UniIcon('fan', size: Design.px(28), color: s.accent),
                    SizedBox(width: Design.px(25)),
                    Text('风量', style: TextStyle(fontSize: Design.px(24))),
                    SizedBox(width: Design.px(25)),
                    step(
                        '降低风量',
                        Icons.remove,
                        climateWritable(n, 'fan')
                            ? () => c.command('fan-down')
                            : null),
                    SizedBox(width: Design.px(25)),
                    SizedBox(
                        width: Design.px(90),
                        child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                                automatic
                                    ? 'AUTO'
                                    : (demo
                                        ? '${climate['fan'] ?? 3}'
                                        : fanField.display(decimals: 0)),
                                textAlign: TextAlign.center,
                                maxLines: 1,
                                softWrap: false,
                                style: TextStyle(fontSize: Design.px(38))))),
                    SizedBox(width: Design.px(25)),
                    step(
                        '提高风量',
                        Icons.add,
                        climateWritable(n, 'fan')
                            ? () => c.command('fan-up')
                            : null)
                  ]),
                  SizedBox(height: Design.px(28)),
                  Row(children: [
                    for (final mode in [
                      ('auto', 'AUTO'),
                      ('ac', 'A/C'),
                      ('sync', '双区同步'),
                      ('recirc', '内循环')
                    ])
                      Expanded(
                          child: Padding(
                              padding: EdgeInsets.only(
                                  right:
                                      mode.$1 == 'recirc' ? 0 : Design.px(18)),
                              child: SizedBox(
                                  height: Design.px(64),
                                  child: OutlinedButton(
                                      key: ValueKey('climate-mode-${mode.$1}'),
                                      onPressed: climateWritable(n, mode.$1)
                                          ? () => c.command('climate-mode',
                                              value: mode.$1)
                                          : null,
                                      style: s.selectionStyle((demo || VehicleField.fromNative(n, mode.$1).valid) && climate[mode.$1] == true).copyWith(
                                          padding: const WidgetStatePropertyAll(
                                              EdgeInsets.zero)),
                                      child: mode.$1 == 'recirc'
                                          ? CirculationIcon(
                                              key: const ValueKey('climate-circulation-icon'),
                                              recirculating: (demo || VehicleField.fromNative(n, 'recirc').valid) ? (demo ? climate['recirc'] == true : VehicleField.fromNative(n, 'recirc').value == true) : null,
                                              color: (demo || VehicleField.fromNative(n, 'recirc').valid) ? s.accent : s.muted,
                                              size: Design.px(34))
                                          : Text(mode.$2, maxLines: 1, softWrap: false, style: TextStyle(fontSize: Design.px(23)))))))
                  ]),
                  SeatControls(controller: c, native: n),
                  if (!demo && vehicleCommandLabel(n).isNotEmpty)
                    Padding(
                        padding: EdgeInsets.only(top: Design.px(16)),
                        child: Text(vehicleCommandLabel(n),
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                color: s.muted, fontSize: Design.px(18)))),
                  if (!demo)
                    Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                            onPressed: () =>
                                c.command('open-official', value: 'climate'),
                            child: const Text('打开空调应用'))),
                ]));
          }));
}
