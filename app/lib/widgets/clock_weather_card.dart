import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../model/card_layout.dart';
import '../model/weather_condition.dart';
import '../theme/design_tokens.dart';
import '../theme/launcher_theme.dart';
import 'card_glyph.dart';
import 'uni_icon.dart';
import 'weather_icon.dart';

class ClockWeatherLayoutOption {
  final String id, label;
  const ClockWeatherLayoutOption(this.id, this.label);
}

const clockWeatherLayouts = <ClockWeatherLayoutOption>[
  ClockWeatherLayoutOption('combined', '左右组合'),
  ClockWeatherLayoutOption('stacked', '上下组合'),
  ClockWeatherLayoutOption('clock', '纯时钟'),
  ClockWeatherLayoutOption('weather', '纯天气'),
];

String clockWeatherLayoutId(String value) =>
    clockWeatherLayouts.any((option) => option.id == value)
        ? value
        : 'combined';

class ClockWeatherCard extends StatefulWidget {
  final LauncherCard card;
  final Map<String, dynamic> native;
  final bool editing;
  const ClockWeatherCard(
      {super.key,
      required this.card,
      required this.native,
      required this.editing});

  @override
  State<ClockWeatherCard> createState() => _ClockWeatherCardState();
}

class _ClockWeatherCardState extends State<ClockWeatherCard> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final id = clockWeatherLayoutId(widget.card.layout);
    return Semantics(
        label:
            '时钟与天气·${clockWeatherLayouts.firstWhere((e) => e.id == id).label}',
        child: LayoutBuilder(builder: (context, box) {
          final width = math.max(box.maxWidth, Design.px(340));
          final height = math.max(box.maxHeight, Design.px(230));
          return FittedBox(
              fit: BoxFit.contain,
              child: SizedBox(
                  width: width,
                  height: height,
                  child: Padding(
                      padding: EdgeInsets.symmetric(
                          horizontal: Design.px(30), vertical: Design.px(26)),
                      child: switch (id) {
                        'stacked' => _stacked(context),
                        'clock' => _clockOnly(context),
                        'weather' => _weatherOnly(context),
                        _ => _combined(context),
                      })));
        }));
  }

  /// 稿子 f2 的「时间天气」卡：左上两行头、左侧 104 的大时间 + 日期，
  /// 右下角太阳/云图标 + 温度 + 天气描述。原来是一分为二的「时钟 | 天气」，
  /// 中间还画了条竖线——那是另一套版式，不是稿子。
  Widget _combined(BuildContext context) {
    final s = SurfaceStyle.of(context);
    final weather = WeatherSnapshot.fromNative(widget.native);
    final d = DateTime.now();
    const weekdays = ['星期一', '星期二', '星期三', '星期四', '星期五', '星期六', '星期日'];
    return LayoutBuilder(builder: (context, box) {
      // 稿子的卡是 522×360，下面这些比例都按它换算，卡片缩放时版式不变。
      final h = box.maxHeight;
      return Stack(clipBehavior: Clip.none, children: [
        Positioned(
            left: 0,
            top: 0,
            right: 0,
            child: _ClockWeatherHeading(city: weather.city)),
        Positioned(
            left: 0,
            top: h * .30,
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                      '${d.hour.toString().padLeft(2, '0')}:'
                      '${d.minute.toString().padLeft(2, '0')}',
                      maxLines: 1,
                      style: TextStyle(
                          fontSize: h * .29,
                          height: .95,
                          fontWeight: FontWeight.w200,
                          letterSpacing: -h * .004,
                          color: s.text.withValues(alpha: .95))),
                  SizedBox(height: h * .038),
                  Text('${d.month}月${d.day}日  ${weekdays[d.weekday - 1]}',
                      maxLines: 1,
                      style: TextStyle(
                          fontSize: h * .042,
                          letterSpacing: h * .0075,
                          color: s.muted)),
                ])),
        if (!widget.editing)
          Positioned(
              right: 0,
              bottom: 0,
              child: Row(children: [
                WeatherIcon(
                    condition: weather.condition,
                    night: weather.night,
                    // 实车反馈「放太大了」，退回放大前的一档（h×.145）：这一块是
                    // 卡片的配角，温度数字也比大时间小一号，读起来才不抢。
                    size: h * .145,
                    color: s.accent),
                SizedBox(width: h * .038),
                Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('${weather.temperature ?? '—'}°',
                          maxLines: 1,
                          style: TextStyle(
                              fontSize: h * .072,
                              height: 1,
                              fontWeight: FontWeight.w300,
                              color: s.text.withValues(alpha: .92))),
                      SizedBox(height: h * .012),
                      Text(weather.description,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: h * .042, color: s.muted)),
                    ]),
              ])),
      ]);
    });
  }

  Widget _stacked(BuildContext context) {
    final s = SurfaceStyle.of(context);
    return Column(children: [
      Expanded(child: _ClockFace(title: widget.card.title, horizontal: true)),
      Container(height: 1, color: s.edge),
      Expanded(
          child: _WeatherFace(
              weather: WeatherSnapshot.fromNative(widget.native),
              editing: widget.editing,
              horizontal: true)),
    ]);
  }

  Widget _clockOnly(BuildContext context) =>
      _ClockFace(title: widget.card.title, large: true);

  Widget _weatherOnly(BuildContext context) => _WeatherFace(
      weather: WeatherSnapshot.fromNative(widget.native),
      editing: widget.editing,
      large: true);
}

class _ClockFace extends StatelessWidget {
  final String title;
  final bool horizontal, large;
  const _ClockFace(
      {required this.title, this.horizontal = false, this.large = false});

  @override
  Widget build(BuildContext context) {
    final d = DateTime.now(), s = SurfaceStyle.of(context);
    const weekdays = ['星期一', '星期二', '星期三', '星期四', '星期五', '星期六', '星期日'];
    final time = Text.rich(
        TextSpan(children: [
          TextSpan(text: d.hour.toString().padLeft(2, '0')),
          TextSpan(text: ':', style: TextStyle(color: s.accent)),
          TextSpan(text: d.minute.toString().padLeft(2, '0')),
        ]),
        maxLines: 1,
        softWrap: false,
        style: TextStyle(
            fontSize: Design.px(large ? 80 : 60),
            height: 1,
            fontWeight: FontWeight.w300,
            letterSpacing: Design.px(3)));
    final date = Text('${d.month} 月 ${d.day} 日 · ${weekdays[d.weekday - 1]}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: Design.px(18), color: s.muted));
    if (horizontal) {
      return Row(children: [
        FittedBox(fit: BoxFit.scaleDown, child: time),
        SizedBox(width: Design.px(28)),
        Expanded(child: date),
      ]);
    }
    return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(children: [
            Expanded(
                child: Text(title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: Design.px(19), color: s.muted))),
            UniIcon('clock', size: Design.px(23), color: s.muted),
          ]),
          const Spacer(),
          FittedBox(fit: BoxFit.scaleDown, child: time),
          SizedBox(height: Design.px(10)),
          date,
          const Spacer(),
        ]);
  }
}

class _WeatherFace extends StatelessWidget {
  final WeatherSnapshot weather;
  final bool editing, horizontal, large;
  const _WeatherFace(
      {required this.weather,
      required this.editing,
      this.horizontal = false,
      this.large = false});

  @override
  Widget build(BuildContext context) {
    final s = SurfaceStyle.of(context);
    final icon = WeatherIcon(
        condition: weather.condition,
        night: weather.night,
        size: Design.px(large ? 104 : 64),
        color: s.accent);
    final temp = Text('${weather.temperature ?? '—'}°',
        maxLines: 1,
        style: TextStyle(
            fontSize: Design.px(large ? 62 : 40),
            height: 1,
            fontWeight: FontWeight.w300));
    final detail = Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(weather.city,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: Design.px(19), color: s.muted)),
          SizedBox(height: Design.px(5)),
          temp,
          SizedBox(height: Design.px(4)),
          Text(weather.description,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: Design.px(19), color: s.muted)),
        ]);
    if (horizontal) {
      return Row(children: [
        icon,
        SizedBox(width: Design.px(20)),
        temp,
        SizedBox(width: Design.px(22)),
        Expanded(
            child: Text('${weather.city} · ${weather.description}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: Design.px(18), color: s.muted))),
      ]);
    }
    if (large) {
      return Row(children: [
        Expanded(child: detail),
        SizedBox(width: Design.px(20)),
        icon,
      ]);
    }
    return Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      icon,
      SizedBox(height: Design.px(editing ? 2 : 8)),
      detail,
    ]);
  }
}

/// 稿子 `.card-hd`：虚线开口环（时间卡用紫）+ `.k-label` 时间天气 + `.k-sub` 城市。
class _ClockWeatherHeading extends StatelessWidget {
  final String city;
  const _ClockWeatherHeading({required this.city});
  @override
  Widget build(BuildContext context) {
    final s = SurfaceStyle.of(context);
    return Row(children: [
      CardGlyph('clock', symbol: 'clock', size: 52.8),
      SizedBox(width: Design.px(14.4)),
      Flexible(
          child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
            Text('时间天气',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: Design.px(13.8),
                    height: 1.2,
                    fontWeight: FontWeight.w600,
                    letterSpacing: Design.px(2.76),
                    color: s.muted)),
            SizedBox(height: Design.px(4.8)),
            Text(city,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: Design.px(15.6), color: s.muted)),
          ])),
    ]);
  }
}
