import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../model/vehicle_card_data.dart';
import '../theme/design_tokens.dart';
import '../theme/launcher_theme.dart';
import 'uni_icon.dart';

typedef VehicleCardClock = int Function();

/// Content only: the desktop's EditableCard owns the themed glass surface,
/// corners, edit controls and layout. These widgets never send vehicle commands.
class BatteryCard extends StatelessWidget {
  final Map<String, dynamic> native;
  final String title;
  final VehicleCardClock? nowMs;
  const BatteryCard(
      {super.key, required this.native, this.title = '动力电池', this.nowMs});
  @override
  Widget build(BuildContext context) => _VehicleFrame(
      native: native,
      fields: const ['batteryPercent'],
      nowMs: nowMs,
      builder: (context, readings, compact) {
        final reading = readings.single, s = SurfaceStyle.of(context);
        final now = nowMs?.call();
        final energyFlow = () {
          final vehicle = native['vehicle'];
          final fields = vehicle is Map ? vehicle['fields'] : null;
          final field = fields is Map ? fields['energyFlow'] : null;
          if (field is! Map || field['valid'] != true) return null;
          return '${field['value']}';
        }();
        return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _VehicleHeading(title, '电量', 'battery', compact),
              Expanded(
                  child: Align(
                      alignment: Alignment.centerLeft,
                      child: _Value(reading,
                          field: 'batteryPercent',
                          size: compact ? 56 : 80,
                          unit: '%',
                          accent: true))),
              BatteryLevelBar(value: reading.value),
              SizedBox(height: Design.px(compact ? 10 : 18)),
              _Footer('剩余电量', '',
                  color: reading.available ? s.accent : s.muted),
              SizedBox(height: Design.px(compact ? 8 : 16)),
              if (!compact) ...[
                EnergyFlowDiagram(state: energyFlow),
                SizedBox(height: Design.px(14)),
              ],
              Container(height: 1, color: s.edge),
              SizedBox(height: Design.px(compact ? 8 : 16)),
              _Footer(
                  '驾驶模式', vehicleStatusLabel(native, 'driveMode', nowMs: now)),
              SizedBox(height: Design.px(4)),
              if (compact)
                _Footer(
                    '能量流', vehicleStatusLabel(native, 'energyFlow', nowMs: now))
              else
                Row(children: [
                  Text('能量流',
                      style:
                          TextStyle(fontSize: Design.px(16), color: s.muted)),
                  SizedBox(width: Design.px(12)),
                  Expanded(
                      child: Text(
                          vehicleStatusLabel(native, 'energyFlow', nowMs: now)
                              .replaceAll('待同步', '—'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: Design.px(16),
                              color: vehicleStatusLabel(native, 'energyFlow',
                                          nowMs: now) ==
                                      '未连接'
                                  ? s.muted
                                  : s.accent))),
                  Text('外接充电',
                      style:
                          TextStyle(fontSize: Design.px(16), color: s.muted)),
                  SizedBox(width: Design.px(12)),
                  Text('—',
                      style:
                          TextStyle(fontSize: Design.px(16), color: s.muted)),
                ]),
              if (compact) ...[
                SizedBox(height: Design.px(4)),
                const _Footer('外接充电', '—'),
              ],
            ]);
      });
}

/// A continuous track: 95% occupies exactly .95 of the available width.
/// An unavailable value is a neutral track; its main reading remains an em dash.
class BatteryLevelBar extends StatelessWidget {
  final double? value;
  const BatteryLevelBar({super.key, required this.value});
  @override
  Widget build(BuildContext context) {
    final s = SurfaceStyle.of(context);
    final percent =
        value != null && value!.isFinite && value! >= 0 && value! <= 100
            ? value
            : null;
    return ExcludeSemantics(
        child: SizedBox(
            height: Design.px(10),
            child: ClipRRect(
                borderRadius: BorderRadius.circular(s.radius * .12),
                child: Stack(fit: StackFit.expand, children: [
                  ColoredBox(
                      key: const ValueKey('battery-track'),
                      color: s.muted.withValues(alpha: .16)),
                  FractionallySizedBox(
                      alignment: Alignment.centerLeft,
                      widthFactor: percent == null ? 0 : percent / 100,
                      child: ColoredBox(
                          key: const ValueKey('battery-fill'),
                          color: s.accent)),
                ]))));
  }
}

/// Official-state energy flow rendered as a compact technical schematic.
/// Moving particles follow the actual direction decoded from the IP753 hybrid
/// enum. Unknown or stale values keep every path dim.
class EnergyFlowDiagram extends StatefulWidget {
  final String? state;
  const EnergyFlowDiagram({super.key, required this.state});

  @override
  State<EnergyFlowDiagram> createState() => _EnergyFlowDiagramState();
}

class _EnergyFlowDiagramState extends State<EnergyFlowDiagram>
    with SingleTickerProviderStateMixin {
  late final AnimationController controller;
  Timer? cycle;
  bool tickerEnabled = true;

  @override
  void initState() {
    super.initState();
    controller = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1300));
    _syncAnimation();
  }

  @override
  void didUpdateWidget(covariant EnergyFlowDiagram oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.state != widget.state) _syncAnimation();
  }

  void _syncAnimation() {
    cycle?.cancel();
    final plan = _EnergyFlowPlan.fromState(widget.state);
    if (!plan.hasFlow) {
      controller.value = 0;
      return;
    }
    controller.forward(from: 0);
    cycle = Timer.periodic(const Duration(milliseconds: 1600), (_) {
      if (mounted && tickerEnabled) controller.forward(from: 0);
    });
  }

  @override
  void dispose() {
    cycle?.cancel();
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    tickerEnabled = TickerMode.valuesOf(context).enabled;
    final s = SurfaceStyle.of(context);
    final plan = _EnergyFlowPlan.fromState(widget.state);
    return Semantics(
        label: '混动能量流，${vehicleEnergyLabels[widget.state] ?? '状态未同步'}',
        child: Container(
            height: Design.px(92),
            decoration: BoxDecoration(
                color: s.muted.withValues(alpha: .065),
                borderRadius: BorderRadius.circular(s.radius * .42),
                border: Border.all(color: s.edge.withValues(alpha: .72))),
            child: ClipRRect(
                borderRadius: BorderRadius.circular(s.radius * .42),
                child: AnimatedBuilder(
                    animation: controller,
                    builder: (context, _) => CustomPaint(
                        key: const ValueKey('hybrid-energy-flow'),
                        painter: _EnergyFlowPainter(
                            style: s,
                            plan: plan,
                            progress: controller.value))))));
  }
}

@immutable
class _EnergyFlowPlan {
  final bool engineOn, batteryOn, wheelsOn;
  final bool engineDrive, engineCharge, electricDrive, regen;
  const _EnergyFlowPlan(
      {this.engineOn = false,
      this.batteryOn = false,
      this.wheelsOn = false,
      this.engineDrive = false,
      this.engineCharge = false,
      this.electricDrive = false,
      this.regen = false});

  factory _EnergyFlowPlan.fromState(String? state) => switch (state) {
        'ELECTRIC_DRIVE' || 'EAWD' => const _EnergyFlowPlan(
            batteryOn: true, wheelsOn: true, electricDrive: true),
        'ENGINE_ONLY' => const _EnergyFlowPlan(
            engineOn: true, wheelsOn: true, engineDrive: true),
        'ENGINE_ONLY_AND_CHARGE' => const _EnergyFlowPlan(
            engineOn: true,
            batteryOn: true,
            wheelsOn: true,
            engineDrive: true,
            engineCharge: true),
        'STANDSTILL_ENGINE_ON_CHARGE' => const _EnergyFlowPlan(
            engineOn: true, batteryOn: true, engineCharge: true),
        'BOOST' => const _EnergyFlowPlan(
            engineOn: true,
            batteryOn: true,
            wheelsOn: true,
            engineDrive: true,
            electricDrive: true),
        // The firmware enum does not prove that a charge cable is attached.
        // Keep the battery active without inventing a source or direction.
        'MAIN_CHARGING' => const _EnergyFlowPlan(batteryOn: true),
        'ENGINE_OFF_REGEN_BRAKE' =>
          const _EnergyFlowPlan(batteryOn: true, wheelsOn: true, regen: true),
        'ENGINE_ON_REGEN_BRAKE' => const _EnergyFlowPlan(
            engineOn: true, batteryOn: true, wheelsOn: true, regen: true),
        'ENGINE_ON_REGEN_BRAKE_CHARGE' => const _EnergyFlowPlan(
            engineOn: true,
            batteryOn: true,
            wheelsOn: true,
            engineCharge: true,
            regen: true),
        'STANDSTILL_ENGINE_ON' => const _EnergyFlowPlan(engineOn: true),
        _ => const _EnergyFlowPlan(),
      };

  bool get hasFlow => engineDrive || engineCharge || electricDrive || regen;
}

class _EnergyFlowPainter extends CustomPainter {
  final SurfaceStyle style;
  final _EnergyFlowPlan plan;
  final double progress;
  const _EnergyFlowPainter(
      {required this.style, required this.plan, required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final engine = Offset(size.width * .13, size.height * .45);
    final motor = Offset(size.width * .50, size.height * .45);
    final wheels = Offset(size.width * .86, size.height * .45);
    final battery = Offset(size.width * .50, size.height * .83);
    final electric = style.accent;
    const fuel = Color(0xffffb45c);
    final dim = style.muted.withValues(alpha: .24);

    Path line(Offset a, Offset b, {Offset? control}) {
      final path = Path()..moveTo(a.dx, a.dy);
      if (control == null) {
        path.lineTo(b.dx, b.dy);
      } else {
        path.quadraticBezierTo(control.dx, control.dy, b.dx, b.dy);
      }
      return path;
    }

    final engineMotor = line(engine, motor);
    final motorWheels = line(motor, wheels);
    final batteryMotor = line(battery, motor);
    final engineBattery = line(engine, battery,
        control: Offset(size.width * .26, size.height * .84));

    final carBody = Path()
      ..moveTo(size.width * .54, size.height * .29)
      ..quadraticBezierTo(size.width * .68, size.height * .20, size.width * .83,
          size.height * .29)
      ..quadraticBezierTo(size.width * .94, size.height * .45, size.width * .83,
          size.height * .61)
      ..quadraticBezierTo(size.width * .68, size.height * .70, size.width * .54,
          size.height * .61)
      ..quadraticBezierTo(size.width * .49, size.height * .45, size.width * .54,
          size.height * .29)
      ..close();
    canvas.drawPath(
        carBody,
        Paint()
          ..color = style.accent.withValues(alpha: .055)
          ..style = PaintingStyle.fill);
    canvas.drawPath(
        carBody,
        Paint()
          ..color = style.accent.withValues(alpha: .18)
          ..style = PaintingStyle.stroke
          ..strokeWidth = Design.px(.8));

    void flow(Path path, bool active, Color color, {bool reverse = false}) {
      canvas.drawPath(
          path,
          Paint()
            ..color = active ? color.withValues(alpha: .56) : dim
            ..style = PaintingStyle.stroke
            ..strokeWidth = Design.px(active ? 2 : 1.1)
            ..strokeCap = StrokeCap.round);
      if (!active) return;
      final metrics = path.computeMetrics().toList();
      if (metrics.isEmpty) return;
      final metric = metrics.first;
      for (int i = 0; i < 3; i++) {
        var t = (progress + i / 3) % 1;
        if (reverse) t = 1 - t;
        final tangent = metric.getTangentForOffset(metric.length * t);
        if (tangent == null) continue;
        canvas.drawCircle(
            tangent.position,
            Design.px(2.5),
            Paint()
              ..color = color
              ..maskFilter = MaskFilter.blur(BlurStyle.normal, Design.px(2)));
      }
    }

    flow(engineMotor, plan.engineDrive, fuel);
    flow(motorWheels, plan.engineDrive || plan.electricDrive || plan.regen,
        plan.electricDrive || plan.regen ? electric : fuel,
        reverse: plan.regen);
    flow(batteryMotor, plan.electricDrive || plan.regen, electric,
        reverse: plan.regen);
    flow(engineBattery, plan.engineCharge, fuel);

    void labelNode(Offset center, String label, _EnergyGlyph glyph, bool active,
        {Color? color}) {
      final c = active ? (color ?? electric) : style.muted;
      final radius = Design.px(17);
      canvas.drawCircle(
          center,
          radius,
          Paint()
            ..color = c.withValues(alpha: active ? .14 : .065)
            ..style = PaintingStyle.fill);
      canvas.drawCircle(
          center,
          radius,
          Paint()
            ..color = c.withValues(alpha: active ? .7 : .28)
            ..style = PaintingStyle.stroke
            ..strokeWidth = Design.px(1));
      _drawEnergyGlyph(canvas, center, Design.px(12), glyph,
          c.withValues(alpha: active ? 1 : .55));
      final text = _labelPainter(label, style.muted);
      text.paint(canvas,
          Offset(center.dx - text.width / 2, center.dy + Design.px(20)));
    }

    labelNode(engine, '发动机', _EnergyGlyph.engine, plan.engineOn, color: fuel);
    labelNode(motor, '电驱', _EnergyGlyph.motor, plan.hasFlow);
    labelNode(wheels, '车轮', _EnergyGlyph.wheels, plan.wheelsOn);
    labelNode(battery, '动力电池', _EnergyGlyph.battery, plan.batteryOn);
  }

  @override
  bool shouldRepaint(covariant _EnergyFlowPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.plan != plan ||
      oldDelegate.style != style;

  // This painter repaints for as long as energy flows. Four labels were shaped on
  // every frame; the glyph size is fixed, so only text and colour type the result.
  static final Map<String, TextPainter> _labelCache = {};
  static TextPainter _labelPainter(String label, Color color) {
    final key = '$label|${color.toARGB32()}';
    final cached = _labelCache[key];
    if (cached != null) return cached;
    if (_labelCache.length > 48) _labelCache.clear();
    return _labelCache[key] = TextPainter(
        text: TextSpan(
            text: label,
            style: TextStyle(fontSize: Design.px(10.5), color: color)),
        textDirection: TextDirection.ltr)
      ..layout();
  }
}

enum _EnergyGlyph { engine, motor, battery, wheels }

void _drawEnergyGlyph(Canvas canvas, Offset center, double radius,
    _EnergyGlyph glyph, Color color) {
  final paint = Paint()
    ..color = color
    ..style = PaintingStyle.stroke
    ..strokeWidth = math.max(1, Design.px(1.4))
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round;
  switch (glyph) {
    case _EnergyGlyph.engine:
      canvas.drawCircle(center, radius * .46, paint);
      canvas.drawCircle(center, radius * .15, paint);
      for (int i = 0; i < 6; i++) {
        final angle = i * math.pi / 3;
        canvas.drawLine(
            center + Offset(math.cos(angle), math.sin(angle)) * radius * .50,
            center + Offset(math.cos(angle), math.sin(angle)) * radius * .76,
            paint);
      }
    case _EnergyGlyph.motor:
      final bolt = Path()
        ..moveTo(center.dx + radius * .12, center.dy - radius * .72)
        ..lineTo(center.dx - radius * .43, center.dy + radius * .04)
        ..lineTo(center.dx - radius * .03, center.dy + radius * .04)
        ..lineTo(center.dx - radius * .14, center.dy + radius * .72)
        ..lineTo(center.dx + radius * .47, center.dy - radius * .10)
        ..lineTo(center.dx + radius * .08, center.dy - radius * .10)
        ..close();
      canvas.drawPath(bolt, paint);
    case _EnergyGlyph.battery:
      final rect = RRect.fromRectAndRadius(
          Rect.fromCenter(
              center: center, width: radius * 1.18, height: radius * .90),
          Radius.circular(radius * .15));
      canvas.drawRRect(rect, paint);
      canvas.drawLine(
          Offset(center.dx + radius * .59, center.dy - radius * .20),
          Offset(center.dx + radius * .73, center.dy - radius * .20),
          paint);
      canvas.drawLine(
          Offset(center.dx + radius * .59, center.dy + radius * .20),
          Offset(center.dx + radius * .73, center.dy + radius * .20),
          paint);
      canvas.drawLine(Offset(center.dx - radius * .28, center.dy),
          Offset(center.dx + radius * .28, center.dy), paint);
    case _EnergyGlyph.wheels:
      canvas.drawCircle(center, radius * .64, paint);
      canvas.drawCircle(center, radius * .27, paint);
      canvas.drawLine(Offset(center.dx - radius * .64, center.dy),
          Offset(center.dx + radius * .64, center.dy), paint);
      canvas.drawLine(Offset(center.dx, center.dy - radius * .64),
          Offset(center.dx, center.dy + radius * .64), paint);
  }
}

class AirQualityCard extends StatelessWidget {
  final Map<String, dynamic> native;
  final String title;
  final VehicleCardClock? nowMs;
  const AirQualityCard(
      {super.key, required this.native, this.title = '车内空气', this.nowMs});
  @override
  Widget build(BuildContext context) => _VehicleFrame(
      native: native,
      fields: const ['pm25', 'aqi'],
      nowMs: nowMs,
      builder: (context, readings, compact) {
        final pm = readings[0], aqi = readings[1];
        final s = SurfaceStyle.of(context);
        return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _VehicleHeading(title, '车内', 'air', compact),
              SizedBox(height: Design.px(compact ? 8 : 18)),
              Text('PM2.5',
                  style: TextStyle(fontSize: Design.px(18), color: s.muted)),
              Expanded(
                  child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                    Expanded(
                        child: _Value(pm,
                            field: 'pm25',
                            size: compact ? 54 : 76,
                            unit: 'µg/m³',
                            accent: true)),
                  ])),
              SizedBox(height: Design.px(compact ? 8 : 16)),
              Container(height: 1, color: s.edge),
              SizedBox(height: Design.px(compact ? 8 : 16)),
              Row(children: [
                Text('车内 AQI',
                    style: TextStyle(fontSize: Design.px(18), color: s.muted)),
                SizedBox(width: Design.px(12)),
                Expanded(
                    child: Align(
                        alignment: Alignment.centerRight,
                        child: _Value(aqi,
                            field: 'aqi', size: compact ? 25 : 30))),
              ]),
            ]);
      });
}

class DrivingInfoCard extends StatelessWidget {
  final Map<String, dynamic> native;
  final String title;
  final VehicleCardClock? nowMs;
  const DrivingInfoCard(
      {super.key, required this.native, this.title = '行车信息', this.nowMs});
  @override
  Widget build(BuildContext context) => _VehicleFrame(
      native: native,
      fields: const ['speed', 'odometer', 'range', 'maintenanceMileage'],
      nowMs: nowMs,
      builder: (context, readings, compact) {
        final s = SurfaceStyle.of(context);
        return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _VehicleHeading(title, '', 'car', compact),
              SizedBox(height: Design.px(compact ? 12 : 22)),
              Expanded(
                  child: Column(children: [
                for (int row = 0; row < 2; row++) ...[
                  if (row > 0) ...[
                    SizedBox(height: Design.px(compact ? 10 : 18)),
                    Container(height: 1, color: s.edge),
                    SizedBox(height: Design.px(compact ? 10 : 18)),
                  ],
                  Expanded(
                      child: Row(children: [
                    for (int col = 0; col < 2; col++) ...[
                      if (col > 0) SizedBox(width: Design.px(24)),
                      Expanded(
                          child: _DrivingMetric(
                              reading: readings[row * 2 + col],
                              field: const [
                                'speed',
                                'odometer',
                                'range',
                                'maintenanceMileage'
                              ][row * 2 + col],
                              label: const [
                                '车速',
                                '总里程',
                                '续航',
                                '距保养'
                              ][row * 2 + col],
                              compact: compact)),
                    ]
                  ])),
                ]
              ])),
            ]);
      });
}

class _DrivingMetric extends StatelessWidget {
  final VehicleCardReading reading;
  final String field, label;
  final bool compact;
  const _DrivingMetric(
      {required this.reading,
      required this.field,
      required this.label,
      required this.compact});
  @override
  Widget build(BuildContext context) {
    final s = SurfaceStyle.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label,
          style: TextStyle(
              fontSize: Design.px(compact ? 16 : 18), color: s.muted)),
      SizedBox(height: Design.px(compact ? 3 : 7)),
      Expanded(
          child: Align(
              alignment: Alignment.centerLeft,
              child: _Value(reading,
                  field: field,
                  size: compact ? 30 : 40,
                  unit: reading.unit,
                  accent: field == 'speed'))),
    ]);
  }
}

class _Value extends StatelessWidget {
  final VehicleCardReading reading;
  final String field, unit;
  final double size;
  final bool accent;
  const _Value(this.reading,
      {required this.field,
      required this.size,
      this.unit = '',
      this.accent = false});
  @override
  Widget build(BuildContext context) {
    final s = SurfaceStyle.of(context);
    return Semantics(
        label:
            '${_fieldLabels[field] ?? field} ${reading.display}${reading.available ? ' $unit' : ''}，${reading.status}',
        child: ExcludeSemantics(
            child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text(reading.display,
                          key: ValueKey('vehicle-value-$field'),
                          style: TextStyle(
                              fontSize: Design.px(size),
                              height: 1,
                              fontWeight: FontWeight.w300,
                              fontFeatures: const [
                                FontFeature.tabularFigures()
                              ],
                              color: reading.available
                                  ? (accent ? s.accent : s.text)
                                  : s.muted)),
                      // Fixed canonical labels remain useful in missing-data states;
                      // unconfirmed driving units are deliberately absent.
                      if (unit.isNotEmpty) ...[
                        SizedBox(width: Design.px(8)),
                        Text(unit,
                            style: TextStyle(
                                fontSize: Design.px(size >= 50 ? 22 : 16),
                                color: s.muted,
                                height: 1)),
                      ],
                    ]))));
  }
}

const _fieldLabels = {
  'batteryPercent': '剩余电量',
  'pm25': '车内 PM2.5',
  'aqi': '车内 AQI',
  'speed': '车速',
  'odometer': '总里程',
  'range': '续航',
  'maintenanceMileage': '距保养',
};

class _VehicleHeading extends StatelessWidget {
  final String title, source, icon;
  final bool compact;
  const _VehicleHeading(this.title, this.source, this.icon, this.compact);
  @override
  Widget build(BuildContext context) {
    final s = SurfaceStyle.of(context);
    return Row(children: [
      UniIcon(icon, color: s.accent, size: Design.px(compact ? 23 : 27)),
      SizedBox(width: Design.px(10)),
      Expanded(
          child: Text(title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: Design.px(compact ? 21 : 25), height: 1.2))),
      if (!source.contains('原车') && !source.contains('官方'))
        SizedBox(width: Design.px(12)),
      if (!source.contains('原车') && !source.contains('官方'))
        Text(source, style: TextStyle(fontSize: Design.px(16), color: s.muted)),
    ]);
  }
}

class _Footer extends StatelessWidget {
  final String label, status;
  final Color? color;
  const _Footer(this.label, this.status, {this.color});
  @override
  Widget build(BuildContext context) {
    final s = SurfaceStyle.of(context);
    return Row(children: [
      Expanded(
          child: Text(label,
              style: TextStyle(fontSize: Design.px(16), color: s.muted))),
      Expanded(
          child: Text(status == '待同步' ? '—' : status,
              textAlign: TextAlign.end,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style:
                  TextStyle(fontSize: Design.px(16), color: color ?? s.muted))),
    ]);
  }
}

typedef _VehicleBuilder = Widget Function(
    BuildContext, List<VehicleCardReading>, bool);

/// Re-evaluate at each field's deadline even if the native stream goes quiet.
class _VehicleFrame extends StatefulWidget {
  final Map<String, dynamic> native;
  final List<String> fields;
  final VehicleCardClock? nowMs;
  final _VehicleBuilder builder;
  const _VehicleFrame(
      {required this.native,
      required this.fields,
      required this.builder,
      this.nowMs});
  @override
  State<_VehicleFrame> createState() => _VehicleFrameState();
}

class _VehicleFrameState extends State<_VehicleFrame> {
  Timer? timer;
  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final now = widget.nowMs?.call() ?? DateTime.now().millisecondsSinceEpoch;
    final readings = [
      for (final key in widget.fields)
        VehicleCardReading.fromNative(widget.native, key, nowMs: now)
    ];
    timer?.cancel();
    final vehicle = widget.native['vehicle'];
    final fields = vehicle is Map ? vehicle['fields'] : null;
    final statusDeadlines = fields is Map
        ? [
            for (final key in ['driveMode', 'energyFlow'])
              if (fields[key] is Map &&
                  fields[key]['valid'] == true &&
                  fields[key]['updatedAtMs'] is num &&
                  (fields[key]['updatedAtMs'] as num).isFinite)
                (fields[key]['updatedAtMs'] as num).toInt() + 5001 - now,
          ]
        : <int>[];
    final deadlines = [
      ...readings
          .where((r) => r.available)
          .map((r) => r.updatedAtMs + 5001 - now),
      ...statusDeadlines
    ].where((ms) => ms > 0);
    if (deadlines.isNotEmpty) {
      timer = Timer(Duration(milliseconds: deadlines.reduce(math.min)), () {
        if (mounted) setState(() {});
      });
    }
    return LayoutBuilder(builder: (context, box) {
      final compact =
          box.maxHeight < Design.px(300) || box.maxWidth < Design.px(370);
      final textScale =
          math.max(1.0, MediaQuery.textScalerOf(context).scale(20) / 20);
      final width = math.max(box.maxWidth, Design.px(300) * textScale);
      final height =
          math.max(box.maxHeight, Design.px(compact ? 205 : 300) * textScale);
      final content = Padding(
          padding: EdgeInsets.symmetric(
              horizontal: Design.px(compact ? 22 : 30),
              vertical: Design.px(compact ? 18 : 28)),
          child: widget.builder(context, readings, compact));
      if (width == box.maxWidth && height == box.maxHeight) return content;
      return FittedBox(
          fit: BoxFit.contain,
          child: SizedBox(width: width, height: height, child: content));
    });
  }
}
