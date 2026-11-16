import 'dart:ui';

/// 极简 SVG 路径解析：稿子里这些图形只用 M/L/H/V/C/S/A/Z 及其相对写法，
/// 弧线用 [Path.arcToPoint] 直接对应（rx == ry、无 x 轴旋转，正好对得上）。
///
/// 用法上都是「24 或 44 视口」的原始坐标，画的时候再整体缩放。
Path svgPath(String d) {
  final path = Path();
  final tokens = RegExp(r'[MmLlHhVvCcSsAaZz]|-?\d*\.?\d+(?:[eE][-+]?\d+)?')
      .allMatches(d)
      .map((m) => m.group(0)!)
      .toList();
  var i = 0;
  var cmd = 'M';
  var cur = Offset.zero, start = Offset.zero;
  Offset? ctrl;
  // 路径抄错（少一个参数）时宁可画歪也不要抛异常把整卡打死：build 里抛异常
  // 会顶掉整页。真出错时上面的分词测试会先报出来。
  double next() => i < tokens.length ? double.parse(tokens[i++]) : 0;
  bool isCommand(String t) => RegExp(r'^[A-Za-z]$').hasMatch(t);

  while (i < tokens.length) {
    if (isCommand(tokens[i])) {
      cmd = tokens[i++];
      if (cmd == 'Z' || cmd == 'z') {
        path.close();
        cur = start;
        continue;
      }
    }
    final rel = cmd == cmd.toLowerCase();
    Offset abs(double x, double y) => rel ? cur + Offset(x, y) : Offset(x, y);
    switch (cmd.toUpperCase()) {
      case 'M':
        final p = abs(next(), next());
        path.moveTo(p.dx, p.dy);
        cur = start = p;
        // 后续隐式坐标对按 lineto 处理。
        cmd = rel ? 'l' : 'L';
        ctrl = null;
        break;
      case 'L':
        final p = abs(next(), next());
        path.lineTo(p.dx, p.dy);
        cur = p;
        ctrl = null;
        break;
      case 'H':
        final x = next();
        cur = Offset(rel ? cur.dx + x : x, cur.dy);
        path.lineTo(cur.dx, cur.dy);
        ctrl = null;
        break;
      case 'V':
        final y = next();
        cur = Offset(cur.dx, rel ? cur.dy + y : y);
        path.lineTo(cur.dx, cur.dy);
        ctrl = null;
        break;
      case 'C':
        final c1 = abs(next(), next());
        final c2 = abs(next(), next());
        final end = abs(next(), next());
        path.cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, end.dx, end.dy);
        cur = end;
        ctrl = c2;
        break;
      case 'S':
        final c2 = abs(next(), next());
        final end = abs(next(), next());
        final c1 = ctrl == null ? cur : cur * 2 - ctrl;
        path.cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, end.dx, end.dy);
        cur = end;
        ctrl = c2;
        break;
      case 'A':
        final rx = next(), ry = next();
        next(); // x 轴旋转，稿子里都是 0
        final large = next() != 0, sweep = next() != 0;
        final end = abs(next(), next());
        path.arcToPoint(end,
            radius: Radius.elliptical(rx, ry),
            largeArc: large,
            clockwise: sweep);
        cur = end;
        ctrl = null;
        break;
      default:
        i++;
    }
  }
  return path;
}
