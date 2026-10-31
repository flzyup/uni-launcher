import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../model/vehicle_data.dart';
import '../theme/design_tokens.dart';
import '../theme/launcher_theme.dart';

/// Optional opening-state contract used by vehicle visuals.
///
/// Native readers can publish any verified subset in `vehicle.fields`:
/// doorFrontLeft, doorFrontRight, doorRearLeft, doorRearRight, tailgateOpen and
/// hoodOpen. Each field uses the standard {valid, value, updatedAtMs} envelope.
@immutable
class VehicleDoorSnapshot {
  final bool? frontLeft;
  final bool? frontRight;
  final bool? rearLeft;
  final bool? rearRight;
  final bool? tailgate;
  final bool? hood;

  const VehicleDoorSnapshot({
    this.frontLeft,
    this.frontRight,
    this.rearLeft,
    this.rearRight,
    this.tailgate,
    this.hood,
  });

  factory VehicleDoorSnapshot.fromNative(Map<String, dynamic> native,
      {int? nowMs}) {
    final vehicle = native['vehicle'];
    final fields = vehicle is Map ? vehicle['fields'] : null;
    bool? read(String key) {
      if (vehicle is! Map || vehicle['connected'] != true || fields is! Map) {
        return null;
      }
      final field = fields[key];
      if (field is! Map || field['valid'] != true) return null;
      final updated = field['updatedAtMs'];
      final now = nowMs ?? DateTime.now().millisecondsSinceEpoch;
      if (updated is! num) return null;
      final age = now - updated.toInt();
      if (age < -1000 || age > 5000) return null;
      final value = field['value'];
      if (value is bool) return value;
      if (value is num && (value == 0 || value == 1)) return value == 1;
      final normalized = '$value'.trim().toUpperCase();
      if (const {'OPEN', 'OPENED', 'ON', 'TRUE'}.contains(normalized)) {
        return true;
      }
      if (const {'CLOSED', 'CLOSE', 'OFF', 'FALSE'}.contains(normalized)) {
        return false;
      }
      return null;
    }

    return VehicleDoorSnapshot(
      frontLeft: read('doorFrontLeft'),
      frontRight: read('doorFrontRight'),
      rearLeft: read('doorRearLeft'),
      rearRight: read('doorRearRight'),
      tailgate: read('tailgateOpen'),
      hood: read('hoodOpen'),
    );
  }

  bool get hasData =>
      frontLeft != null ||
      frontRight != null ||
      rearLeft != null ||
      rearRight != null ||
      tailgate != null ||
      hood != null;

  bool get anyOpen =>
      frontLeft == true ||
      frontRight == true ||
      rearLeft == true ||
      rearRight == true ||
      tailgate == true ||
      hood == true;

  String get statusLabel {
    if (!hasData) return '车门状态未接入';
    final open = <String>[
      if (frontLeft == true) '左前门',
      if (frontRight == true) '右前门',
      if (rearLeft == true) '左后门',
      if (rearRight == true) '右后门',
      if (tailgate == true) '尾门',
      if (hood == true) '机舱盖',
    ];
    if (open.isNotEmpty) return '${open.join('、')}开启';
    if ([frontLeft, frontRight, rearLeft, rearRight, tailgate, hood]
        .any((value) => value == null)) {
      return '部分车门状态未知';
    }
    return '车门均已关闭';
  }

  @override
  bool operator ==(Object other) =>
      other is VehicleDoorSnapshot &&
      other.frontLeft == frontLeft &&
      other.frontRight == frontRight &&
      other.rearLeft == rearLeft &&
      other.rearRight == rearRight &&
      other.tailgate == tailgate &&
      other.hood == hood;

  @override
  int get hashCode =>
      Object.hash(frontLeft, frontRight, rearLeft, rearRight, tailgate, hood);
}

/// Dedicated body card, using the same source artwork and opening overlays as TPMS.
class VehicleBodyDiagram extends StatelessWidget {
  final Map<String, dynamic> native;
  const VehicleBodyDiagram({super.key, this.native = const {}});

  @override
  Widget build(BuildContext context) {
    final doors = VehicleDoorSnapshot.fromNative(native);
    return Semantics(
        label: '领克05车身示意，${doors.statusLabel}',
        child: Center(
            child: AspectRatio(
                aspectRatio: 1826 / 833,
                child: _Lynk05TopView(
                    style: SurfaceStyle.of(context), doors: doors))));
  }
}

/// Vehicle status concept: the artwork is illustrative; the only indicators
/// painted over it are independently verified, fresh opening signals.
class VehicleStatusDiagram extends StatelessWidget {
  final Map<String, dynamic> native;
  final int? nowMs;
  const VehicleStatusDiagram({super.key, this.native = const {}, this.nowMs});

  @override
  Widget build(BuildContext context) {
    final doors = VehicleDoorSnapshot.fromNative(native, nowMs: nowMs);
    final surface = SurfaceStyle.of(context);
    return LayoutBuilder(builder: (context, box) {
      final compact = box.maxHeight < Design.px(250);
      final nodeWidth =
          math.min(Design.px(compact ? 78 : 95), box.maxWidth * .23);
      final nodeHeight =
          math.min(Design.px(compact ? 44 : 60), box.maxHeight * .3);
      Widget node(String label, String field) {
        final reading = VehicleField.fromNative(native, field, nowMs: nowMs);
        return _VehiclePressureLabel(
          key: ValueKey('tire-pressure-$field'),
          label: label,
          value: reading.display(decimals: 2),
          available: reading.valid,
          compact: compact,
        );
      }

      Widget place(String label, String field,
              {required double x, required bool top}) =>
          Positioned(
              left: (box.maxWidth * x - nodeWidth / 2)
                  .clamp(0.0, math.max(0.0, box.maxWidth - nodeWidth)),
              top: top ? 0 : math.max(0.0, box.maxHeight - nodeHeight),
              width: nodeWidth,
              height: nodeHeight,
              child: node(label, field));
      return Semantics(
          label: '车辆状态与胎压示意，${doors.statusLabel}',
          child: Stack(fit: StackFit.expand, children: [
            Positioned.fill(
                left: nodeWidth * .72,
                right: nodeWidth * .72,
                top: nodeHeight + Design.px(2),
                bottom: nodeHeight + Design.px(2),
                child: RepaintBoundary(
                    child: Center(
                        child: AspectRatio(
                            aspectRatio: 1.5,
                            child: LayoutBuilder(builder: (context, imageBox) {
                              Widget marker(String id, String label, double x,
                                      double y) =>
                                  Positioned(
                                      left: imageBox.maxWidth * x,
                                      top: imageBox.maxHeight * y,
                                      child: FractionalTranslation(
                                          translation: const Offset(-.5, -.5),
                                          child: _DoorMarker(
                                              key: ValueKey('vehicle-door-$id'),
                                              label: label,
                                              compact: compact)));
                              return Stack(fit: StackFit.expand, children: [
                                IgnorePointer(
                                    child: CustomPaint(
                                        painter: _VehicleAmbientPainter(
                                            color: surface.accent,
                                            dark: surface.dark))),
                                Image.asset(
                                    'assets/art/vehicle-status-front-left-transparent.png',
                                    key: const ValueKey(
                                        'vehicle-status-artwork'),
                                    fit: BoxFit.contain,
                                    filterQuality: FilterQuality.low,
                                    semanticLabel: '车辆立体示意图'),
                                if (doors.frontLeft == true)
                                  marker('front-left', '左前门', .60, .47),
                                if (doors.rearLeft == true)
                                  marker('rear-left', '左后门', .76, .31),
                                if (doors.frontRight == true)
                                  marker('front-right', '右前门', .32, .31),
                                if (doors.rearRight == true)
                                  marker('rear-right', '右后门', .53, .16),
                                if (doors.anyOpen)
                                  const SizedBox(
                                      key: ValueKey('vehicle-opening-alert')),
                              ]);
                            }))))),
            // Looking towards the front-left of the screen, the vehicle's
            // left side is the near side; the right wheels are occluded.
            place('右前', 'pressureFrontRight', x: .25, top: true),
            place('右后', 'pressureRearRight', x: .65, top: true),
            place('左前', 'pressureFrontLeft', x: .55, top: false),
            place('左后', 'pressureRearLeft', x: .82, top: false),
          ]));
    });
  }
}

class _VehiclePressureLabel extends StatelessWidget {
  final String label, value;
  final bool available, compact;
  const _VehiclePressureLabel(
      {super.key,
      required this.label,
      required this.value,
      required this.available,
      required this.compact});

  @override
  Widget build(BuildContext context) {
    final s = SurfaceStyle.of(context);
    return Semantics(
        label: '$label胎压 ${available ? '$value bar' : '无数据'}',
        child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(label,
                  style: TextStyle(
                      color: s.muted,
                      fontSize: Design.px(compact ? 11 : 13),
                      height: 1.1)),
              SizedBox(height: Design.px(3)),
              FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Row(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Text(value,
                            style: TextStyle(
                                color: available ? s.text : s.muted,
                                fontSize: Design.px(compact ? 20 : 25),
                                height: 1,
                                fontFeatures: const [
                                  FontFeature.tabularFigures()
                                ])),
                        SizedBox(width: Design.px(4)),
                        Text('bar',
                            style: TextStyle(
                                color: s.muted,
                                fontSize: Design.px(compact ? 10 : 11))),
                      ])),
            ]));
  }
}

/// A static, low-opacity pool of light under the transparent car gives it
/// depth without a live blur, animation, or an opaque image background.
class _VehicleAmbientPainter extends CustomPainter {
  final Color color;
  final bool dark;
  const _VehicleAmbientPainter({required this.color, required this.dark});

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final center = Offset(size.width * .52, size.height * .52);
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.scale(size.width * .62, size.height * .54);
    final light = Paint()
      ..shader = RadialGradient(colors: [
        color.withValues(alpha: dark ? .33 : .19),
        color.withValues(alpha: dark ? .19 : .10),
        color.withValues(alpha: 0),
      ], stops: const [
        0,
        .45,
        1
      ]).createShader(Rect.fromCircle(center: Offset.zero, radius: 1));
    canvas.drawCircle(Offset.zero, 1, light);
    canvas.restore();
    canvas.save();
    canvas.translate(size.width * .53, size.height * .83);
    canvas.scale(size.width * .37, size.height * .11);
    final shadow = Paint()
      ..shader = RadialGradient(colors: [
        Colors.black.withValues(alpha: dark ? .28 : .16),
        Colors.black.withValues(alpha: 0),
      ]).createShader(Rect.fromCircle(center: Offset.zero, radius: 1));
    canvas.drawCircle(Offset.zero, 1, shadow);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _VehicleAmbientPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.dark != dark;
}

class _DoorMarker extends StatelessWidget {
  final String label;
  final bool compact;
  const _DoorMarker({super.key, required this.label, required this.compact});

  @override
  Widget build(BuildContext context) => Semantics(
      label: '$label开启',
      child: Container(
          padding: EdgeInsets.symmetric(
              horizontal: Design.px(compact ? 5 : 7),
              vertical: Design.px(compact ? 3 : 4)),
          decoration: BoxDecoration(
              color: const Color(0xeb392b29),
              border: Border.all(color: const Color(0xffe5a575)),
              borderRadius: BorderRadius.circular(Design.px(3))),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Container(
                width: Design.px(5),
                height: Design.px(5),
                decoration: const BoxDecoration(
                    color: Color(0xffffb983), shape: BoxShape.circle)),
            SizedBox(width: Design.px(4)),
            Text(label,
                style: TextStyle(
                    color: const Color(0xffffd8bc),
                    fontSize: Design.px(compact ? 10 : 12),
                    height: 1.1)),
          ])));
}

/// Horizontal TPMS visual traced from the supplied Lynk & Co 05 top view.
/// The vehicle stays in its own center lane. Each reading is anchored outside
/// the artwork beside its matching wheel, so no label can cover the trace.
class TireDiagram extends StatelessWidget {
  static const _vehicleAspect = 1826 / 833;
  final Map<String, dynamic> native;
  final int? nowMs;
  const TireDiagram({super.key, this.native = const {}, this.nowMs});

  @override
  Widget build(BuildContext context) {
    final s = SurfaceStyle.of(context);
    final doors = VehicleDoorSnapshot.fromNative(native, nowMs: nowMs);
    return LayoutBuilder(builder: (context, box) {
      final compact =
          box.maxHeight < Design.px(250) || box.maxWidth < Design.px(430);
      final nodeWidth =
          math.min(Design.px(compact ? 88 : 98), box.maxWidth * .3);
      final nodeHeight = math.min(
          Design.px(compact ? 45 : 64), math.max(0.0, box.maxHeight * .28));
      final laneGap = Design.px(compact ? 5 : 9);
      final laneHeight =
          math.max(0.0, box.maxHeight - (nodeHeight + laneGap) * 2);
      final carWidth =
          math.min(box.maxWidth * .76, laneHeight * _vehicleAspect);
      final carHeight = carWidth / _vehicleAspect;
      final carLeft = (box.maxWidth - carWidth) / 2;
      final carTop = (box.maxHeight - carHeight) / 2;
      // The supplied trace points right: rear axle at 23%, front axle at 74%.
      final rearX = carLeft + carWidth * .23;
      final frontX = carLeft + carWidth * .74;

      Widget node(String label, String field) {
        final reading = VehicleField.fromNative(native, field,
            nowMs: nowMs ?? DateTime.now().millisecondsSinceEpoch);
        return _PressureNode(
            key: ValueKey('tire-pressure-$field'),
            label: label,
            value: reading.display(decimals: 2),
            available: reading.valid,
            compact: compact,
            width: nodeWidth,
            height: nodeHeight);
      }

      Widget positionedNode(
              String label, String field, double centerX, bool top) =>
          Positioned(
              left: (centerX - nodeWidth / 2)
                  .clamp(0.0, math.max(0.0, box.maxWidth - nodeWidth)),
              top: top ? 0 : math.max(0.0, box.maxHeight - nodeHeight),
              width: nodeWidth,
              height: nodeHeight,
              child: node(label, field));

      return Semantics(
          label: '领克05胎压示意，${doors.statusLabel}',
          child: Stack(fit: StackFit.expand, children: [
            Positioned(
                left: carLeft,
                width: carWidth,
                top: carTop,
                height: carHeight,
                child: RepaintBoundary(
                    child: _Lynk05TopView(
                        key: const ValueKey('lynk-05-horizontal-vehicle'),
                        style: s,
                        doors: doors))),
            positionedNode('左后', 'pressureRearLeft', rearX, true),
            positionedNode('左前', 'pressureFrontLeft', frontX, true),
            positionedNode('右后', 'pressureRearRight', rearX, false),
            positionedNode('右前', 'pressureFrontRight', frontX, false),
            if (doors.anyOpen)
              Align(
                  alignment: Alignment.center,
                  child: Container(
                      key: const ValueKey('vehicle-opening-alert'),
                      padding: EdgeInsets.symmetric(
                          horizontal: Design.px(10), vertical: Design.px(5)),
                      decoration: BoxDecoration(
                          color: const Color(0xffffb45c).withValues(alpha: .14),
                          borderRadius: BorderRadius.circular(Design.px(20)),
                          border: Border.all(
                              color: const Color(0xffffb45c)
                                  .withValues(alpha: .65))),
                      child: Text('车门开启',
                          style: TextStyle(
                              fontSize: Design.px(compact ? 12 : 14),
                              color: const Color(0xffffb45c))))),
          ]));
    });
  }
}

class _PressureNode extends StatelessWidget {
  final String label, value;
  final bool available, compact;
  final double width, height;
  const _PressureNode(
      {super.key,
      required this.label,
      required this.value,
      required this.available,
      required this.compact,
      required this.width,
      required this.height});

  @override
  Widget build(BuildContext context) {
    final s = SurfaceStyle.of(context);
    final color = available ? s.accent : s.muted;
    return SizedBox(
        width: width,
        height: height,
        child: DecoratedBox(
            decoration: BoxDecoration(
                gradient: LinearGradient(
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                    colors: [
                      color.withValues(alpha: .13),
                      color.withValues(alpha: .025)
                    ]),
                borderRadius: BorderRadius.circular(Design.px(10)),
                border: Border.all(color: color.withValues(alpha: .22))),
            child: Padding(
                padding: EdgeInsets.symmetric(
                    horizontal: Design.px(compact ? 7 : 9),
                    vertical: Design.px(compact ? 4 : 7)),
                child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: SizedBox(
                        width:
                            math.max(0, width - Design.px(compact ? 14 : 18)),
                        child:
                            Column(mainAxisSize: MainAxisSize.min, children: [
                          Row(children: [
                            Container(
                                width: Design.px(4),
                                height: Design.px(4),
                                decoration: BoxDecoration(
                                    shape: BoxShape.circle, color: color)),
                            SizedBox(width: Design.px(6)),
                            Text(label,
                                style: TextStyle(
                                    fontSize: Design.px(compact ? 12 : 14),
                                    height: 1,
                                    color: s.muted)),
                          ]),
                          SizedBox(height: Design.px(compact ? 3 : 6)),
                          FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Row(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.baseline,
                                  textBaseline: TextBaseline.alphabetic,
                                  children: [
                                    Text(value,
                                        style: TextStyle(
                                            fontSize:
                                                Design.px(compact ? 24 : 31),
                                            height: 1,
                                            fontWeight: FontWeight.w300,
                                            fontFeatures: const [
                                              FontFeature.tabularFigures()
                                            ],
                                            color:
                                                available ? s.text : s.muted)),
                                    SizedBox(width: Design.px(6)),
                                    Text('bar',
                                        style: TextStyle(
                                            fontSize:
                                                Design.px(compact ? 11 : 13),
                                            height: 1,
                                            color: s.muted)),
                                  ])),
                        ]))))));
  }
}

class _Lynk05TopView extends StatelessWidget {
  final SurfaceStyle style;
  final VehicleDoorSnapshot doors;
  const _Lynk05TopView({
    super.key,
    required this.style,
    required this.doors,
  });

  @override
  Widget build(BuildContext context) {
    final trace = Image.asset(
      'assets/art/lynk-05-top-line.png',
      fit: BoxFit.contain,
      filterQuality: FilterQuality.high,
      isAntiAlias: true,
      gaplessPlayback: true,
      color: style.accent.withValues(alpha: style.dark ? .86 : .76),
      colorBlendMode: BlendMode.srcIn,
      semanticLabel: '领克05原图等比俯视线稿，车头向右',
    );
    return Stack(fit: StackFit.expand, children: [
      trace,
      if (doors.anyOpen)
        CustomPaint(painter: _VehicleOpeningPainter(doors: doors)),
    ]);
  }
}

/// Opening-state marks intentionally remain a separate overlay. With unknown or
/// closed values the supplied top-view trace is shown without additional lines.
class _VehicleOpeningPainter extends CustomPainter {
  final VehicleDoorSnapshot doors;
  const _VehicleOpeningPainter({required this.doors});

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty || !doors.anyOpen) return;
    final w = size.width, h = size.height;
    final warning = Paint()
      ..color = const Color(0xffffb45c)
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = Design.px(2.4);

    void door(bool? open, Offset hinge, Offset openEnd) {
      if (open != true) return;
      canvas.drawLine(hinge, openEnd, warning);
      canvas.drawCircle(
          openEnd, Design.px(2.6), Paint()..color = const Color(0xffffb45c));
    }

    // The displayed trace points right. Vehicle-left doors are on the top edge.
    door(doors.frontLeft, Offset(w * .58, h * .16), Offset(w * .62, 0));
    door(doors.rearLeft, Offset(w * .36, h * .16), Offset(w * .39, 0));
    door(doors.frontRight, Offset(w * .58, h * .84), Offset(w * .62, h));
    door(doors.rearRight, Offset(w * .36, h * .84), Offset(w * .39, h));
    if (doors.tailgate == true) {
      canvas.drawLine(Offset(w * .07, h * .30), Offset(0, h * .18), warning);
      canvas.drawLine(Offset(w * .07, h * .70), Offset(0, h * .82), warning);
    }
    if (doors.hood == true) {
      canvas.drawLine(
          Offset(w * .76, h * .26), Offset(w * .92, h * .11), warning);
      canvas.drawLine(
          Offset(w * .76, h * .74), Offset(w * .92, h * .89), warning);
    }
  }

  @override
  bool shouldRepaint(covariant _VehicleOpeningPainter oldDelegate) =>
      oldDelegate.doors != doors;
}
