import 'package:flutter/material.dart';
import '../controller/launcher_controller.dart';
import '../model/vehicle_data.dart';
import '../model/vehicle_card_data.dart';
import '../theme/design_tokens.dart';
import '../theme/launcher_theme.dart';

/// 设计稿 `#f29`（`theme-styles/eclipse/simulator.html`）：1466×760 的只读
/// 数据页。左栏是车模 + 四轮胎压角标 + 最高/最低两行；右栏是 2×2 的字段组
/// （座舱 / 座椅 / 能量 / 行驶）和顶部四个状态块；头部 30/300 标题，
/// 底部一行来源说明。
class VehicleReadout extends StatelessWidget {
  final LauncherController controller;
  final Map<String, dynamic> native;
  const VehicleReadout(
      {super.key, required this.controller, required this.native});

  static const _cockpit = Color(0xFF6FD3FF);
  static const _seat = Color(0xFFFFB057);
  static const _drive = Color(0xFF8E6CFF);
  static const _amber = Color(0xFFFFB25C);

  @override
  Widget build(BuildContext context) {
    final s = SurfaceStyle.of(context), ink = s.text;
    final vehicle =
        native['vehicle'] is Map ? native['vehicle'] as Map : const {};
    final connected = vehicle['connected'] == true;

    String read(String key, {int decimals = 1}) =>
        VehicleField.fromNative(native, key).display(decimals: decimals);

    // 四条胎压一起算最高/最低，用来点亮角标和底部提示。
    const tires = [
      ('pressureFrontLeft', '左前'),
      ('pressureFrontRight', '右前'),
      ('pressureRearLeft', '左后'),
      ('pressureRearRight', '右后')
    ];
    double? number(String key) {
      final field = VehicleField.fromNative(native, key);
      return field.valid && field.value is num
          ? (field.value as num).toDouble()
          : null;
    }

    final pressures = {
      for (final t in tires) t.$1: number(t.$1),
    };
    final valid = pressures.values.whereType<double>().toList();
    final maxPressure =
        valid.isEmpty ? null : valid.reduce((a, b) => a > b ? a : b);
    final minPressure =
        valid.isEmpty ? null : valid.reduce((a, b) => a < b ? a : b);
    final minKey = minPressure == null
        ? null
        : pressures.entries
            .firstWhere((e) => e.value == minPressure,
                orElse: () => const MapEntry('', null))
            .key;
    String tireLabel(String key) =>
        tires.firstWhere((t) => t.$1 == key, orElse: () => ('', '')).$2;

    Widget dot(Color color, {double size = 5}) => Container(
        width: Design.dz(size),
        height: Design.dz(size),
        decoration: BoxDecoration(shape: BoxShape.circle, color: color));

    /// `.vh-row`：39 高、下沿 3.8% 分隔线；值后面跟一枚 11.5 的小单位。
    Widget row(String label, String value, {String? unit, Color? color}) {
      final empty = value == '—';
      return Container(
          height: Design.dz(39),
          decoration: BoxDecoration(
              border: Border(
                  bottom: BorderSide(color: ink.withValues(alpha: .038)))),
          child: Row(children: [
            Text(label,
                style: TextStyle(
                    fontSize: Design.dz(13.5),
                    color: ink.withValues(alpha: .58))),
            const Spacer(),
            Text(value,
                style: TextStyle(
                    fontSize: Design.dz(15.5),
                    letterSpacing: Design.dz(.15),
                    fontFeatures: const [FontFeature.tabularFigures()],
                    color: empty
                        ? ink.withValues(alpha: .22)
                        : (color ?? ink.withValues(alpha: .90)))),
            if (unit != null && !empty) ...[
              SizedBox(width: Design.dz(4)),
              Text(unit,
                  style: TextStyle(
                      fontSize: Design.dz(11.5),
                      fontWeight: FontWeight.w300,
                      color: ink.withValues(alpha: .34)))
            ]
          ]));
    }

    /// `.vh-g`：15·18·8 内边距、17 圆角、带内高光的分组卡。
    Widget group(String title, Color accent, List<Widget> rows) => Container(
        padding: EdgeInsets.fromLTRB(
            Design.dz(18), Design.dz(15), Design.dz(18), Design.dz(8)),
        decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(s.controlRadius),
            gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  ink.withValues(alpha: .042),
                  ink.withValues(alpha: .016)
                ]),
            border: Border.all(color: ink.withValues(alpha: .07))),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
              padding: EdgeInsets.only(bottom: Design.dz(9)),
              decoration: BoxDecoration(
                  border: Border(
                      bottom: BorderSide(color: ink.withValues(alpha: .05)))),
              child: Row(children: [
                dot(accent),
                SizedBox(width: Design.dz(8)),
                Text(title,
                    style: TextStyle(
                        fontSize: Design.dz(11),
                        fontWeight: FontWeight.w600,
                        letterSpacing: Design.dz(2.2),
                        color: ink.withValues(alpha: .42)))
              ])),
          ...rows
        ]));

    Widget stateBlock(String key, Widget value) => Expanded(
        child: Container(
            height: Design.dz(66),
            padding: EdgeInsets.symmetric(horizontal: Design.dz(16)),
            decoration: BoxDecoration(
                color: ink.withValues(alpha: .028),
                border: Border.all(color: ink.withValues(alpha: .065)),
                borderRadius: BorderRadius.circular(s.controlRadius)),
            child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(key,
                      style: TextStyle(
                          fontSize: Design.dz(11),
                          letterSpacing: Design.dz(1.55),
                          color: ink.withValues(alpha: .34))),
                  SizedBox(height: Design.dz(6)),
                  value
                ])));

    Widget stateValue(Widget child) =>
        Row(mainAxisSize: MainAxisSize.min, children: [child]);

    final aqc = read('aqi', decimals: 0);

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      // ── 头部 ───────────────────────────────────────────────
      Container(
          padding: EdgeInsets.fromLTRB(
              Design.dz(38), Design.dz(32), Design.dz(38), Design.dz(20)),
          decoration: BoxDecoration(
              border: Border(
                  bottom: BorderSide(color: ink.withValues(alpha: .07)))),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('车辆信息',
                  style: TextStyle(
                      fontSize: Design.dz(30),
                      fontWeight: FontWeight.w300,
                      letterSpacing: Design.dz(.3),
                      height: 1.1,
                      color: ink.withValues(alpha: .96))),
              SizedBox(height: Design.dz(10)),
              Row(children: [
                Text('车辆数据 · 只读',
                    style: TextStyle(
                        fontSize: Design.dz(12.5),
                        letterSpacing: Design.dz(.25),
                        color: ink.withValues(alpha: .48))),
                SizedBox(width: Design.dz(10)),
                dot(ink.withValues(alpha: .24), size: 4),
                SizedBox(width: Design.dz(10)),
                Text('原车 CAN 总线',
                    style: TextStyle(
                        fontSize: Design.dz(12.5),
                        letterSpacing: Design.dz(.25),
                        color: ink.withValues(alpha: .48))),
                SizedBox(width: Design.dz(10)),
                dot(ink.withValues(alpha: .24), size: 4),
                SizedBox(width: Design.dz(10)),
                Text('500 ms 刷新',
                    style: TextStyle(
                        fontSize: Design.dz(12.5),
                        letterSpacing: Design.dz(.25),
                        color: ink.withValues(alpha: .48)))
              ])
            ]),
            const Spacer(),
            Container(
                height: Design.dz(30),
                padding: EdgeInsets.symmetric(horizontal: Design.dz(13)),
                decoration: BoxDecoration(
                    color: ink.withValues(alpha: .04),
                    border: Border.all(color: ink.withValues(alpha: .07)),
                    borderRadius: BorderRadius.circular(Design.dz(9))),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  dot(s.accent.withValues(alpha: .9), size: 5),
                  SizedBox(width: Design.dz(7)),
                  Text(connected ? '同步中' : '未连接',
                      style: TextStyle(
                          fontSize: Design.dz(11.5),
                          color: ink.withValues(alpha: .5)))
                ])),
            SizedBox(width: Design.dz(14)),
            Tooltip(
                message: '关闭车辆信息',
                child: Semantics(
                    button: true,
                    label: '关闭车辆信息',
                    child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => Navigator.pop(context),
                        child: Container(
                            width: Design.dz(44),
                            height: Design.dz(44),
                            decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: ink.withValues(alpha: .06),
                                border: Border.all(
                                    color: ink.withValues(alpha: .09))),
                            child: Center(
                                child: Icon(Icons.close,
                                    size: Design.dz(17),
                                    color: ink.withValues(alpha: .70)))))))
          ])),

      // ── 主体 ───────────────────────────────────────────────
      Expanded(
          child: Padding(
              padding: EdgeInsets.fromLTRB(
                  Design.dz(38), Design.dz(18), Design.dz(38), Design.dz(20)),
              child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // 左：车模 + 四轮胎压
                    SizedBox(
                        width: Design.dz(520),
                        child: Column(children: [
                          Expanded(
                              child: Stack(children: [
                            // 车底那圈强调色光晕
                            Positioned.fill(
                                child: DecoratedBox(
                                    decoration: BoxDecoration(
                                        gradient: RadialGradient(
                                            radius: .62,
                                            colors: [
                                  s.accent.withValues(alpha: .13),
                                  s.accent.withValues(alpha: .04),
                                  Colors.transparent
                                ],
                                            stops: const [
                                  0,
                                  .46,
                                  .74
                                ])))),
                            Positioned.fill(
                                child: Padding(
                                    padding: EdgeInsets.symmetric(
                                        vertical: Design.dz(26)),
                                    child: Image.asset(
                                        'assets/art/vehicle-status-front-left-transparent.webp',
                                        fit: BoxFit.contain,
                                        filterQuality: FilterQuality.medium,
                                        semanticLabel: '车辆立体示意图'))),
                            _tire(context, '右前', 'pressureFrontRight',
                                left: Design.dz(38), top: Design.dz(6)),
                            _tire(context, '右后', 'pressureRearRight',
                                right: Design.dz(38), top: Design.dz(6)),
                            _tire(context, '左前', 'pressureFrontLeft',
                                left: Design.dz(32), bottom: Design.dz(6)),
                            _tire(context, '左后', 'pressureRearLeft',
                                right: Design.dz(30),
                                bottom: Design.dz(6),
                                warn: minPressure != null && minPressure < 2.3)
                          ])),
                          SizedBox(height: Design.dz(4)),
                          row('最高胎压', maxPressure?.toStringAsFixed(2) ?? '—',
                              unit: 'bar'),
                          row('最低胎压', minPressure?.toStringAsFixed(2) ?? '—',
                              unit: 'bar',
                              color: minPressure != null && minPressure < 2.3
                                  ? _amber
                                  : null),
                          Container(
                              margin: EdgeInsets.only(top: Design.dz(6)),
                              padding: EdgeInsets.only(
                                  top: Design.dz(14), left: Design.dz(2)),
                              decoration: BoxDecoration(
                                  border: Border(
                                      top: BorderSide(
                                          color: ink.withValues(alpha: .06)))),
                              child: Row(children: [
                                dot(s.accent.withValues(alpha: .85)),
                                SizedBox(width: Design.dz(10)),
                                Text('实时胎压 · bar',
                                    style: TextStyle(
                                        fontSize: Design.dz(12),
                                        color: ink.withValues(alpha: .38))),
                                const Spacer(),
                                if (minPressure != null && minPressure < 2.3)
                                  Text(
                                      '${tireLabel(minKey ?? '')}偏低 '
                                      '${(2.42 - minPressure).toStringAsFixed(2)} bar',
                                      style: TextStyle(
                                          fontSize: Design.dz(12),
                                          color: _amber.withValues(alpha: .78)))
                              ]))
                        ])),

                    SizedBox(width: Design.dz(32)),

                    // 右：四组字段 + 状态块
                    Expanded(
                        child: Column(children: [
                      Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                                child: group('座舱', _cockpit, [
                              row('主驾温度', read('left'), unit: '°C'),
                              row('副驾温度', read('right'), unit: '°C'),
                              row('后排温度', read('rear'), unit: '°C'),
                              row('风量', read('fan', decimals: 0), unit: '档')
                            ])),
                            SizedBox(width: Design.dz(16)),
                            Expanded(
                                child: group('座椅', _seat, [
                              row('主驾加热', read('driverHeat', decimals: 0),
                                  unit: '档'),
                              row('主驾通风', read('driverVent', decimals: 0),
                                  unit: '档'),
                              row('副驾加热', read('passengerHeat', decimals: 0),
                                  unit: '档'),
                              row('副驾通风', read('passengerVent', decimals: 0),
                                  unit: '档')
                            ]))
                          ]),
                      SizedBox(height: Design.dz(13)),
                      Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                                child: group('能量', s.accent, [
                              row('动力电池', read('batteryPercent', decimals: 0),
                                  unit: '%', color: s.accent),
                              row('电池温度', read('batteryTemp', decimals: 0),
                                  unit: '°C'),
                              row('剩余续航', read('range', decimals: 0),
                                  unit: 'km'),
                              row('车内 PM2.5', read('pm25', decimals: 0),
                                  unit: 'µg/m³')
                            ])),
                            SizedBox(width: Design.dz(16)),
                            Expanded(
                                child: group('行驶', _drive, [
                              row('车速', read('speed', decimals: 0),
                                  unit: 'km/h'),
                              row('总里程', read('odometer', decimals: 0),
                                  unit: 'km'),
                              row('小计里程', read('tripDistance'), unit: 'km'),
                              row('平均能耗', read('avgConsumption', decimals: 1),
                                  unit: 'kWh/100km')
                            ]))
                          ]),
                      const Spacer(),
                      Row(children: [
                        stateBlock(
                            '驾驶模式',
                            stateValue(Text(
                                vehicleStatusLabel(native, 'driveMode'),
                                style: TextStyle(
                                    fontSize: Design.dz(17),
                                    color: ink.withValues(alpha: .90))))),
                        SizedBox(width: Design.dz(11)),
                        stateBlock(
                            '混动选择',
                            stateValue(Text(
                                '${vehicleStatusLabel(native, 'hybridSelected')}',
                                style: TextStyle(
                                    fontSize: Design.dz(15),
                                    color: _amber.withValues(alpha: .9))))),
                        SizedBox(width: Design.dz(11)),
                        stateBlock(
                            '能量流',
                            Row(mainAxisSize: MainAxisSize.min, children: [
                              dot(s.accent.withValues(alpha: .9), size: 5),
                              SizedBox(width: Design.dz(7)),
                              Text(vehicleStatusLabel(native, 'energyFlow'),
                                  style: TextStyle(
                                      fontSize: Design.dz(15),
                                      color: ink.withValues(alpha: .90)))
                            ])),
                        SizedBox(width: Design.dz(11)),
                        stateBlock(
                            '车内 AQC',
                            Row(mainAxisSize: MainAxisSize.min, children: [
                              Text(aqc,
                                  style: TextStyle(
                                      fontSize: Design.dz(17),
                                      color: ink.withValues(alpha: .90))),
                              SizedBox(width: Design.dz(4)),
                              Text('优',
                                  style: TextStyle(
                                      fontSize: Design.dz(12),
                                      color: ink.withValues(alpha: .34)))
                            ]))
                      ])
                    ]))
                  ]))),

      // ── 脚注 ───────────────────────────────────────────────
      // 只留左侧的只读说明：右下角那行「数据源 · systemStatus / tirePressure /
      // energyFlow」是给开发看的字段映射，车上没人需要，去掉。
      Padding(
          padding: EdgeInsets.fromLTRB(
              Design.dz(38), 0, Design.dz(38), Design.dz(24)),
          child: Text('此页只读，不提供任何写操作 · 空调与座椅未开启时对应字段为空',
              style: TextStyle(
                  fontSize: Design.dz(11.5),
                  letterSpacing: Design.dz(.25),
                  color: ink.withValues(alpha: .30))))
    ]);
  }

  /// 车模四角的胎压角标（`.tp`）：23 的读数 + 11 的方位。
  Widget _tire(BuildContext context, String label, String field,
      {double? left,
      double? right,
      double? top,
      double? bottom,
      bool warn = false}) {
    final s = SurfaceStyle.of(context);
    final reading = VehicleField.fromNative(native, field);
    return Positioned(
        left: left,
        right: right,
        top: top,
        bottom: bottom,
        child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(reading.display(decimals: 2),
                  style: TextStyle(
                      fontSize: Design.dz(23),
                      fontFeatures: const [FontFeature.tabularFigures()],
                      color: !reading.valid
                          ? s.text.withValues(alpha: .22)
                          : warn
                              ? const Color(0xFFFFB25C)
                              : s.text.withValues(alpha: .92))),
              SizedBox(height: Design.dz(4)),
              Text(label,
                  style: TextStyle(
                      fontSize: Design.dz(11),
                      letterSpacing: Design.dz(.88),
                      color: s.muted))
            ]));
  }
}
