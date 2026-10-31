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
      title: '空调与座椅',
      subtitle: c.native.value['demo'] == true ? '操作预览 · 不控制车辆' : null,
      closeLabel: '关闭空调',
      width: Design.px(1440),
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
                    size: Design.px(56),
                    framed: false,
                    iconSize: Design.px(32),
                    soft: true,
                    onTap: tap);
            return SingleChildScrollView(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                  _caption(context, '温度与风量'),
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    for (final zone in ['left', 'fan', 'right']) ...[
                      if (zone != 'left') SizedBox(width: Design.px(18)),
                      Expanded(
                          flex: zone == 'fan' ? 11 : 10,
                          child: GlassSurface(
                              key: ValueKey('climate-card-$zone'),
                              shadow: false,
                              padding: EdgeInsets.symmetric(
                                  horizontal: Design.px(16),
                                  vertical: Design.px(16)),
                              child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                        zone == 'left'
                                            ? '主驾温度'
                                            : zone == 'right'
                                                ? '副驾温度'
                                                : '风量',
                                        style: TextStyle(
                                            fontSize: Design.px(19),
                                            color: s.muted)),
                                    SizedBox(height: Design.px(14)),
                                    Row(children: [
                                      step(
                                          zone == 'fan'
                                              ? '降低风量'
                                              : '降低${zone == 'left' ? '主驾' : '副驾'}温度',
                                          Icons.remove,
                                          climateWritable(n, zone)
                                              ? () => zone == 'fan'
                                                  ? c.command('fan-down')
                                                  : c.command('temp-down',
                                                      zone: zone)
                                              : null),
                                      Expanded(
                                          child: Center(
                                              child: FittedBox(
                                                  fit: BoxFit.scaleDown,
                                                  child: Row(
                                                      mainAxisSize:
                                                          MainAxisSize.min,
                                                      children: [
                                                        if (zone == 'fan') ...[
                                                          UniIcon('fan',
                                                              size:
                                                                  Design.px(25),
                                                              color: s.accent),
                                                          SizedBox(
                                                              width:
                                                                  Design.px(8)),
                                                        ],
                                                        Text(
                                                            zone == 'fan'
                                                                ? (automatic
                                                                    ? 'AUTO'
                                                                    : (demo
                                                                        ? '${climate['fan'] ?? 3}'
                                                                        : fanField.display(
                                                                            decimals:
                                                                                0)))
                                                                : (demo
                                                                    ? '${(climate[zone] as num? ?? 22.5).toStringAsFixed(1)}°'
                                                                    : '${VehicleField.fromNative(n, zone).display()}°'),
                                                            key: zone == 'fan'
                                                                ? const ValueKey(
                                                                    'climate-fan-value')
                                                                : null,
                                                            maxLines: 1,
                                                            softWrap: false,
                                                            style: TextStyle(
                                                                fontSize: Design
                                                                    .px(zone ==
                                                                            'fan'
                                                                        ? 34
                                                                        : 48),
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w300))
                                                      ])))),
                                      step(
                                          zone == 'fan'
                                              ? '提高风量'
                                              : '提高${zone == 'left' ? '主驾' : '副驾'}温度',
                                          Icons.add,
                                          climateWritable(n, zone)
                                              ? () => zone == 'fan'
                                                  ? c.command('fan-up')
                                                  : c.command('temp-up',
                                                      zone: zone)
                                              : null)
                                    ])
                                  ])))
                    ]
                  ]),
                  _caption(context, '空调模式'),
                  Row(children: [
                    for (final mode in [
                      'ac',
                      'auto',
                      'recirc',
                      'sync',
                      'power'
                    ])
                      Expanded(
                          child: Padding(
                        padding: EdgeInsets.only(
                            right: mode == 'power' ? 0 : Design.px(12)),
                        child: Builder(builder: (context) {
                          final field = VehicleField.fromNative(n, mode);
                          final recirc = demo
                              ? climate['recirc'] as bool?
                              : (field.valid && mode == 'recirc'
                                  ? field.value as bool?
                                  : null);
                          final selected = mode == 'auto'
                              ? automatic
                              : mode == 'recirc'
                                  ? recirc != null
                                  : mode == 'power'
                                      ? climate['power'] == true
                                      : (demo || field.valid) &&
                                          climate[mode] == true;
                          final label = mode == 'ac'
                              ? 'A/C  制冷'
                              : mode == 'sync'
                                  ? 'SYNC  双区同步'
                                  : mode == 'power'
                                      ? '电源'
                                      : mode == 'recirc'
                                          ? (recirc == null
                                              ? '循环状态未知'
                                              : recirc
                                                  ? '内循环'
                                                  : '外循环')
                                          : 'AUTO';
                          return SizedBox(
                              height: Design.px(58),
                              child: DecoratedBox(
                                position: DecorationPosition.foreground,
                                decoration: const BoxDecoration(),
                                child: OutlinedButton(
                                  key: ValueKey('climate-mode-$mode'),
                                  onPressed: climateWritable(n, mode)
                                      ? () => mode == 'power'
                                          ? c.command('climate-power')
                                          : c.command('climate-mode',
                                              value: mode)
                                      : null,
                                  style: s
                                      .weakSelectionStyle(selected)
                                      .copyWith(
                                          backgroundColor:
                                              WidgetStatePropertyAll(selected
                                                  ? s.accent
                                                      .withValues(alpha: .16)
                                                  : s.soft),
                                          padding: const WidgetStatePropertyAll(
                                              EdgeInsets.zero)),
                                  child: FittedBox(
                                      fit: BoxFit.scaleDown,
                                      child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            if (mode == 'recirc') ...[
                                              CirculationIcon(
                                                  key: const ValueKey(
                                                      'climate-circulation-icon'),
                                                  recirculating: recirc,
                                                  color: s.accent,
                                                  size: Design.px(28)),
                                              SizedBox(width: Design.px(8)),
                                            ],
                                            if (mode == 'power') ...[
                                              UniIcon('power',
                                                  size: Design.px(26),
                                                  color: selected
                                                      ? s.accent
                                                      : s.muted),
                                              SizedBox(width: Design.px(8)),
                                            ],
                                            Text(label,
                                                maxLines: 1,
                                                softWrap: false,
                                                style: TextStyle(
                                                    fontSize: Design.px(19)))
                                          ])),
                                ),
                              ));
                        }),
                      ))
                  ]),
                  _caption(context, '座椅舒适'),
                  SeatControls(controller: c, native: n),
                  if (!demo && vehicleCommandLabel(n).isNotEmpty)
                    Padding(
                        padding: EdgeInsets.only(top: Design.px(16)),
                        child: Text(vehicleCommandLabel(n),
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                color: s.muted, fontSize: Design.px(18)))),
                ]));
          }));
}

Widget _caption(BuildContext context, String text) => Padding(
    padding: EdgeInsets.only(top: Design.px(20), bottom: Design.px(12)),
    child: Text(text,
        style: TextStyle(
            fontSize: Design.px(20), color: SurfaceStyle.of(context).muted)));
