import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../model/vehicle_data.dart';
import '../model/vehicle_card_data.dart';
import '../theme/design_tokens.dart';
import '../theme/launcher_theme.dart';
import 'vehicle_visuals.dart';
import 'card_glyph.dart';

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
  Widget build(BuildContext context) {
    // 纯燃油车没有电池，走燃油版（这一条原来在 BatteryCard 里，重写时漏了）。
    if (detectPowertrain(native, nowMs: nowMs?.call()) == PowertrainType.ice) {
      return FuelCard(native: native, title: title, nowMs: nowMs);
    }
    return _VehicleFrame(
        native: native,
        fields: const ['batteryPercent', 'range', 'odometer'],
        nowMs: nowMs,
        builder: (context, readings, compact) {
          final percent = readings[0], range = readings[1], odo = readings[2];
          final s = SurfaceStyle.of(context);
          final now = nowMs?.call();
          final percentValue = percent.value;
          final mode = vehicleStatusLabel(native, 'driveMode', nowMs: now);
          final energy = vehicleStatusLabel(native, 'energyFlow', nowMs: now);
          // 稿子 f2：左边 198 环形表（SOC），右列续航 / 能量流 / 驾驶模式 / 总里程。
          return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _VehicleHeading(title, '电量', 'battery', compact,
                    // 稿子副标题「插混 · 混动舒适」= 能量流 · 驾驶模式
                    sub: [if (energy != '待同步') energy, if (mode != '待同步') mode]
                        .join(' · ')),
                Expanded(child: LayoutBuilder(builder: (context, box) {
                  final side = math.min(
                      box.maxHeight, box.maxWidth * (compact ? .92 : .46));
                  return Row(children: [
                    CardRing(
                        fraction: (percentValue ?? 0) / 100,
                        // 传画布单位：CardRing 内部按 Design.px 换算
                        size: side / Design.px(1),
                        // 稿子 rc-mint：`#3BE2C0` 在 sim 的 migrateSvgColors 里被改写成
                        // `rgb(var(--acc))`，另一端 `#6FD3FF` 是固定青。所以这一环
                        // **一半固定、一半跟主题配色**：换「玫瑰」右段变粉、换「琥珀」变金，
                        // 左下那段青不动（对照用户给的设计稿两张截图）。
                        // 屏幕上的落位：起点（左下）是固定青，终点（右上）是 accent ——
                        // 跟稿子的梯度方向差 180°（圆的 rotate(135) 把 stop0 转到了右上）。
                        // **三套皮肤同款**：用户要的是这个渐变效果本身，不只是暗夜才有
                        // （2026-11-13 晚）。
                        color: CardTint.cyan,
                        colorEnd: s.accent,
                        center:
                            Column(mainAxisSize: MainAxisSize.min, children: [
                          _BigNumber(
                              text:
                                  percentValue == null ? '—' : percent.display,
                              unit: '%',
                              size: compact ? 34 : 56,
                              unitSize: compact ? 15 : 22,
                              valueKey: const ValueKey(
                                  'vehicle-value-batteryPercent')),
                          SizedBox(height: Design.px(6)),
                          Text('SOC',
                              style: TextStyle(
                                  fontSize: Design.px(15),
                                  letterSpacing: Design.px(1.9),
                                  color: s.muted)),
                        ])),
                    if (!compact) SizedBox(width: Design.px(22)),
                    if (!compact)
                      Flexible(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: SizedBox(
                            width: Design.px(compact ? 170 : 236),
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text('综合续航',
                                      style: TextStyle(
                                          fontSize: Design.px(13.8),
                                          letterSpacing: Design.px(1.9),
                                          color: s.muted)),
                                  SizedBox(height: Design.px(2)),
                                  _BigNumber(
                                      text: range.value == null
                                          ? '—'
                                          : range.display,
                                      unit: 'km',
                                      size: compact ? 34 : 56,
                                      unitSize: compact ? 14 : 16),
                                  SizedBox(height: Design.px(14)),
                                  Container(
                                      height: 1,
                                      color: s.accent.withValues(alpha: .18)),
                                  SizedBox(height: Design.px(12)),
                                  if (!compact) EnergyFlowStrip(label: energy),
                                  if (!compact) SizedBox(height: Design.px(12)),
                                  if (!compact) _CardRow('驾驶模式', mode),
                                  if (!compact)
                                    _CardRow(
                                        '总里程',
                                        odo.value == null
                                            ? '—'
                                            : '${odo.display} km'),
                                ]),
                          ),
                        ),
                      ),
                  ]);
                })),
              ]);
        });
  }
}

class FuelCard extends StatelessWidget {
  final Map<String, dynamic> native;
  final String title;
  final VehicleCardClock? nowMs;
  const FuelCard(
      {super.key, required this.native, this.title = '剩余油量', this.nowMs});
  @override
  Widget build(BuildContext context) => _VehicleFrame(
      native: native,
      fields: const ['fuelPercent', 'fuelLiters', 'range', 'odometer'],
      nowMs: nowMs,
      builder: (context, readings, compact) {
        final percent = readings[0],
            liters = readings[1],
            range = readings[2],
            odo = readings[3];
        final s = SurfaceStyle.of(context);
        final now = nowMs?.call();
        final vehicle =
            native['vehicle'] is Map ? native['vehicle'] as Map : const {};
        final capacity = vehicle['fuelCapacity'];
        final capacityText = capacity is num && capacity > 0
            ? '${capacity.toStringAsFixed(0)} L'
            : '待同步';
        final mode = vehicleStatusLabel(native, 'driveMode', nowMs: now);
        final percentValue = percent.value;
        // 燃油模式这一版按用户给的截图：左环形表（油量 %）+ 右列续航与三行明细。
        return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _VehicleHeading(title, '油量', 'fuel', compact,
                  sub: ['燃油模式', if (mode != '待同步') mode].join(' · ')),
              Expanded(child: LayoutBuilder(builder: (context, box) {
                final side = math.min(
                    box.maxHeight, box.maxWidth * (compact ? .92 : .46));
                return Row(children: [
                  CardRing(
                      fraction: (percentValue ?? 0) / 100,
                      size: side / Design.px(1),
                      // 稿子 rc-fuel：琥珀 → 浅金。两端都是固定暖色（不跟主题配色），
                      // 同样三套皮肤通用 —— 油量在任何配色下都该是暖色系。
                      color: const Color(0xFFF09A3C),
                      colorEnd: const Color(0xFFFFD79A),
                      center: Column(mainAxisSize: MainAxisSize.min, children: [
                        _BigNumber(
                            text: percentValue == null ? '—' : percent.display,
                            unit: '%',
                            size: compact ? 34 : 60,
                            unitSize: compact ? 15 : 24,
                            valueKey:
                                const ValueKey('vehicle-value-fuelPercent')),
                        SizedBox(height: Design.px(6)),
                        Text('油量',
                            style: TextStyle(
                                fontSize: Design.px(15), color: s.muted)),
                      ])),
                  if (!compact) SizedBox(width: Design.px(22)),
                  if (!compact)
                    Flexible(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: SizedBox(
                          width: Design.px(compact ? 170 : 236),
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text('燃油续航',
                                    style: TextStyle(
                                        fontSize: Design.px(13.8),
                                        letterSpacing: Design.px(1.9),
                                        color: s.muted)),
                                SizedBox(height: Design.px(2)),
                                _BigNumber(
                                    text: range.value == null
                                        ? '—'
                                        : range.display,
                                    unit: 'km',
                                    size: compact ? 34 : 56,
                                    unitSize: compact ? 14 : 16),
                                SizedBox(height: Design.px(14)),
                                Container(
                                    height: 1,
                                    color: s.accent.withValues(alpha: .18)),
                                SizedBox(height: Design.px(8)),
                                // 剩余油量是这张卡的第二主信息，紧凑档也留着
                                _CardRow(
                                    '剩余油量',
                                    liters.value == null
                                        ? '待同步'
                                        : liters.display,
                                    unit: 'L'),
                                if (!compact) _CardRow('油箱容积', capacityText),
                                if (!compact)
                                  _CardRow(
                                      '总里程',
                                      odo.value == null
                                          ? '待同步'
                                          : '${odo.display} km'),
                              ]),
                        ),
                      ),
                    ),
                ]);
              })),
            ]);
      });
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
      fields: const ['aqi', 'pm25'],
      nowMs: nowMs,
      builder: (context, readings, compact) {
        final aqi = readings[0], pm = readings[1];
        final s = SurfaceStyle.of(context);
        final level = aqi.value == null ? '' : _aqiLevel(aqi.value!);
        final temp =
            VehicleField.fromNative(native, 'left', nowMs: nowMs?.call());
        final climate =
            native['climate'] is Map ? native['climate'] as Map : const {};
        final vehicle =
            native['vehicle'] is Map ? native['vehicle'] as Map : const {};
        final fields =
            vehicle['fields'] is Map ? vehicle['fields'] as Map : const {};
        final autoVal = climate['auto'] == true ||
            (fields['auto'] is Map && (fields['auto'] as Map)['value'] == true);
        final acVal = climate['ac'] == true ||
            (fields['ac'] is Map && (fields['ac'] as Map)['value'] == true);
        final powerVal = climate['power'] == true ||
            (fields['power'] is Map && (fields['power'] as Map)['value'] == true);
        final isPurifying = powerVal || autoVal || acVal;
        return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _VehicleHeading(title, '车内', 'air', compact,
                  sub: level.isEmpty ? '' : '$level · 可深呼吸'),
              Expanded(child: LayoutBuilder(builder: (context, box) {
                final side = math.min(
                    box.maxHeight, box.maxWidth * (compact ? .92 : .46));
                return Row(children: [
                  CardRing(
                      fraction: (aqi.value ?? 0) / 100,
                      size: side / Design.px(1),
                      // 稿子 rc-cyan 是 rc-mint 的反向（青→薄荷），落到屏幕上就是
                      // 「起点 accent、终点固定青」—— 跟电池环正好互为镜像，同样三套皮肤通用。
                      color: s.accent,
                      colorEnd: CardTint.cyan,
                      center: Column(mainAxisSize: MainAxisSize.min, children: [
                        _BigNumber(
                            text: aqi.value == null ? '—' : aqi.display,
                            size: compact ? 30 : 48,
                            unitSize: 14),
                        SizedBox(height: Design.px(4)),
                        Text('AQC',
                            style: TextStyle(
                                fontSize: Design.px(15),
                                letterSpacing: Design.px(1.9),
                                color: s.muted)),
                      ])),
                  if (!compact) SizedBox(width: Design.px(20)),
                  if (!compact)
                    Flexible(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: SizedBox(
                          width: Design.px(compact ? 150 : 200),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _CardRow('PM2.5', pm.display,
                                  unit: 'µg/m³',
                                  valueKey:
                                      const ValueKey('vehicle-value-pm25')),
                              if (!compact) ...[
                                _CardRow('温度', temp.valid ? temp.display() : '—',
                                    unit: temp.valid ? '°C' : '',
                                    valueKey:
                                        const ValueKey('vehicle-value-cabin-temp')),
                                _CardRow('净化', isPurifying ? '已开启' : '未开启',
                                    valueKey:
                                        const ValueKey('vehicle-value-air-purifier')),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                ]);
              })),
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
      // 稿子里「距保养」在车况卡里；按用户要求挪到这张卡，和总里程、续航同列。
      fields: const ['speed', 'odometer', 'range', 'maintenanceMileage'],
      nowMs: nowMs,
      builder: (context, readings, compact) {
        final speed = readings[0],
            odo = readings[1],
            range = readings[2],
            maintenance = readings[3];
        final s = SurfaceStyle.of(context);
        // 稿子 f2：88 的大车速 + 下面两行；原车没有小计里程与能耗，
        // 就用现有的总里程 / 续航 / 距保养补位。
        return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _VehicleHeading(title, '', 'car', compact,
                  sub: '本次行程', kind: 'gauge'),
              // 大车速：整块（数字 + 单位 + 下面那行「当前车速」）在
              // 「卡头」和「下方三行数据」之间垂直居中——Expanded + Center，
              // 不再用一个固定空档把数字顶在标题下面。
              // 字号按用户反馈放大一档（88 → 112 画布）；卡片被压小的紧凑档
              // 同步往上提一档（44 → 52），FittedBox 兜住极端情况。
              Expanded(
                  // 水平居中：这张卡下面三行是「标签贴左、数值贴右」，中间本来
                  // 就空；速度再贴左就只剩右侧一大片黑。整块居中后卡面才平衡。
                  child: Center(
                      child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Column(
                              mainAxisSize: MainAxisSize.min,
                              // 副标题跟着数字居中，否则居中的块下面挂一行贴左的字。
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                _BigNumber(
                                    text: speed.value == null
                                        ? '—'
                                        : speed.display,
                                    unit: 'km/h',
                                    size: compact ? 52 : 112,
                                    unitSize: compact ? 16 : 28),
                                if (!compact) ...[
                                  SizedBox(height: Design.px(14)),
                                  Text('当前车速',
                                      style: TextStyle(
                                          fontSize: Design.px(17),
                                          color: s.muted)),
                                ],
                              ])))),
              if (!compact) ...[
                _CardRow(
                    '总里程', odo.value == null ? '待同步' : '${odo.display} km'),
                _CardRow(
                    '续航', range.value == null ? '待同步' : '${range.display} km'),
                _CardRow(
                    '距保养',
                    maintenance.value == null
                        ? '待同步'
                        : '${maintenance.display} km'),
              ],
            ]);
      });
}

/// 稿子 `.k-num` + 单位：大数字用 200 字重、紧字距，单位小一号跟在基线。
class _BigNumber extends StatelessWidget {
  final String text, unit;
  final double size, unitSize;
  final Key? valueKey;
  const _BigNumber(
      {required this.text,
      this.unit = '',
      required this.size,
      required this.unitSize,
      this.valueKey});
  @override
  Widget build(BuildContext context) {
    final s = SurfaceStyle.of(context);
    return FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(text,
                  key: valueKey,
                  style: TextStyle(
                      // 设计稿 px 值 × 1.2 再交 Design.px 才是 1:1（与 `.k-num`
                      // 56 / 48 对齐）；少这一档会整体小 17%。
                      fontSize: Design.px(size * 1.2),
                      height: 0.95,
                      fontWeight: FontWeight.w200,
                      letterSpacing: Design.px(-1),
                      color: s.text.withValues(alpha: .95))),
              if (unit.isNotEmpty) ...[
                SizedBox(width: Design.px(6)),
                Text(unit,
                    style: TextStyle(
                        fontSize: Design.px(unitSize * 1.2),
                        height: 1,
                        fontWeight: FontWeight.w300,
                        color: s.muted)),
              ],
            ]));
  }
}

/// 稿子 f2 的能量流示意：电池 →（虚线）→ 车轮，右侧一行状态字。
///
/// 原来这里是一张「活」的示意图：发动机 / 电驱 / 车轮三节点加走光，1.3s 一轮
/// 动画，播放时这张卡八成时间都在 60fps 重绘。稿子只要一条 150×28 的静态线稿，
/// 按稿子重画之后 raster 成本归零，画面也干净了。
class EnergyFlowStrip extends StatelessWidget {
  final String label;
  const EnergyFlowStrip({super.key, required this.label});

  @override
  Widget build(BuildContext context) {
    final s = SurfaceStyle.of(context);
    // 稿子（simulator.html:4597）这条是 `rgba(var(--acc),.9)` —— **跟主题配色**，
    // 不是写死的薄荷。以前暗夜单独固定成 CardTint.mint，换「玫瑰/琥珀」时环变了、
    // 这条不动，同一张卡上两套色系（用户 2026-11-13 晚确认要改）。
    final tint = s.accent;
    return Row(children: [
      Flexible(
          child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: SizedBox(
                  width: Design.px(153.6),
                  height: Design.px(28.8),
                  child: CustomPaint(painter: _EnergyFlowStripPainter(tint))))),
      SizedBox(width: Design.px(14.4)),
      Text(label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
              fontSize: Design.px(24),
              height: 1.1,
              fontWeight: FontWeight.w300,
              color: s.text.withValues(alpha: .9))),
    ]);
  }
}

/// 稿子那枚 150×28 的线稿：电池壳 + 正极 + 虚线 + 箭头 + 车轮（含十字刻线）。
class _EnergyFlowStripPainter extends CustomPainter {
  final Color tint;
  const _EnergyFlowStripPainter(this.tint);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 150);
    Paint stroke(double alpha, double width) => Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = width
      ..color = tint.withValues(alpha: alpha)
      ..isAntiAlias = true;

    // 电池
    canvas.drawRRect(
        RRect.fromRectAndRadius(
            const Rect.fromLTWH(1, 6.5, 19, 15), const Radius.circular(3.2)),
        stroke(.55, 1.3));
    canvas.drawPath(
        Path()
          ..moveTo(20, 11.5)
          ..lineTo(22.4, 11.5)
          ..lineTo(22.4, 16.5)
          ..lineTo(20, 16.5),
        stroke(.55, 1.3));
    // 虚线：稿子 dasharray 3 / 3.5
    final dash = stroke(.38, 1.2);
    var x = 29.0;
    while (x < 104) {
      canvas.drawLine(Offset(x, 14), Offset(math.min(x + 3, 104), 14), dash);
      x += 6.5;
    }
    // 箭头
    canvas.drawPath(
        Path()
          ..moveTo(110, 10.2)
          ..lineTo(114.4, 14)
          ..lineTo(110, 17.8),
        stroke(.8, 1.3)..strokeJoin = StrokeJoin.round);
    // 车轮
    canvas.drawCircle(const Offset(134, 14), 8.2, stroke(.55, 1.3));
    canvas.drawCircle(
        const Offset(134, 14),
        2.3,
        Paint()
          ..color = tint.withValues(alpha: .45)
          ..isAntiAlias = true);
    final tick = stroke(.32, 1.1)..strokeCap = StrokeCap.round;
    canvas.drawLine(const Offset(134, 5.9), const Offset(134, 8.5), tick);
    canvas.drawLine(const Offset(134, 19.5), const Offset(134, 22.1), tick);
    canvas.drawLine(const Offset(125.9, 14), const Offset(128.5, 14), tick);
    canvas.drawLine(const Offset(139.5, 14), const Offset(142.1, 14), tick);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _EnergyFlowStripPainter old) => old.tint != tint;
}

/// 稿子 `.row`：38 高、下沿 5% 细线，左侧标签 13.5、右侧值 15.5 + 小号单位。
class _CardRow extends StatelessWidget {
  final String label, value;
  final String unit;
  final Key? valueKey;
  const _CardRow(this.label, this.value, {this.unit = '', this.valueKey});
  @override
  Widget build(BuildContext context) {
    final s = SurfaceStyle.of(context);
    return SizedBox(
        height: Design.px(45.6),
        child: Row(children: [
          Expanded(
              child: Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: Design.px(16.2), color: s.muted))),
          Text(value,
              key: valueKey,
              maxLines: 1,
              style: TextStyle(
                  fontSize: Design.px(18.6),
                  color: s.text.withValues(alpha: .88),
                  fontFeatures: const [FontFeature.tabularFigures()])),
          if (unit.isNotEmpty) ...[
            SizedBox(width: Design.px(4)),
            Text(unit,
                style: TextStyle(fontSize: Design.px(13.8), color: s.muted)),
          ],
        ]));
  }
}

/// AQI 等级字（稿子「优 · 可深呼吸」里的前半句）。国内口径：50/100/150/200 分档。
String _aqiLevel(double value) {
  if (value <= 50) return '优';
  if (value <= 100) return '良';
  if (value <= 150) return '轻度污染';
  if (value <= 200) return '中度污染';
  return '重度污染';
}

class _VehicleHeading extends StatelessWidget {
  final String title, source, icon;
  final bool compact;

  /// 稿子 `.card-hd` 的第二行；不传就用 [source]。
  final String? sub;

  /// 稿子卡片头图形名；不传按 [icon] 推（行车信息用 car.svg，但稿子画的是
  /// 仪表盘，所以那张要显式传 'gauge'）。
  final String? kind;
  const _VehicleHeading(this.title, this.source, this.icon, this.compact,
      {this.sub, this.kind});

  @override
  Widget build(BuildContext context) {
    final s = SurfaceStyle.of(context);
    final fallback =
        !source.contains('原车') && !source.contains('官方') ? source : '';
    // 紧凑档（卡片被编辑态压小、或 2 行高）不放副标题：两行头会顶破内容区，
    // 实测在 2 行卡片上溢出 8.8 画布。
    final secondary = compact ? '' : (sub ?? fallback).trim();
    // 与 card_content.dart 的 _Heading 同一套 `.card-hd` 规格：这张卡原来也是
    // 「图标 + 一行标题」，与同一页其它卡的头不一致。
    return Row(children: [
      // 高度取 34 画布 = 两行文字的实际高度（11.5×1.2 + 4 + 13×1.2 ≈ 33.4）；
      // 再高就把编辑态的内容区顶破（52.8 实测溢 8.8，36 还差 0.8）。
      // 紧凑档按需求只留一行标题，压到 24。
      CardGlyph(kind ?? glyphKindForSymbol(icon),
          symbol: icon, size: compact ? 46 : 48),
      SizedBox(width: Design.px(compact ? 11 : 14.4)),
      Expanded(
          child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
            Text(title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: Design.px(compact ? 13.2 : 13.8),
                    height: 1.2,
                    fontWeight: FontWeight.w600,
                    letterSpacing: Design.px(compact ? 2.2 : 2.76),
                    color: s.muted)),
            if (secondary.isNotEmpty) ...[
              SizedBox(height: Design.px(compact ? 3.6 : 4.8)),
              Text(secondary,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: Design.px(compact ? 13.2 : 15.6),
                      height: 1.2,
                      color: s.muted)),
            ],
          ])),
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
