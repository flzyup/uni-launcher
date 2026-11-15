import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uni_launcher/controller/launcher_controller.dart';
import 'package:uni_launcher/launcher_app.dart';
import 'fake_gateway.dart';

/// 色球高光必须在四态（两套老皮肤 × 明/暗）下都是「上亮下暗」。
///
/// 这条用例来自一次真实翻车：`_PaletteDot` 的高光层一开始写成
/// `s.text.withValues(alpha: .32)`——暗色皮肤下 `text` 是白，看着没问题；
/// 浅色皮肤下 `text` 是深墨，于是「高光」变成一层灰影，六颗球全部呈现
/// 「上暗中亮」的双环。几何测试抓不到这种东西（尺寸一个都没变），
/// 只有看图或采样像素才发现。
///
/// 做法：把整棵树包一层 [RepaintBoundary]，`toImage()` 取像素，比较同一颗
/// 球「顶部高光带」与「球身中带」的平均亮度。高光反转时这条断言立刻失败。
void main() {
  const shotKey = ValueKey('palette-shot');

  Future<(Uint8List, int, int)> grab(WidgetTester t) async {
    final boundary =
        t.renderObject<RenderRepaintBoundary>(find.byKey(shotKey));
    late Uint8List bytes;
    late int w, h;
    await t.runAsync(() async {
      final image = await boundary.toImage();
      w = image.width;
      h = image.height;
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      bytes = data!.buffer.asUint8List();
      image.dispose();
    });
    return (bytes, w, h);
  }

  /// 取一块矩形里的平均亮度（0–255，按 Rec.601 近似）。
  double meanLuma(Uint8List px, int w, int h, Rect r) {
    var sum = 0.0, n = 0;
    for (var y = r.top.round(); y < r.bottom.round(); y++) {
      if (y < 0 || y >= h) continue;
      for (var x = r.left.round(); x < r.right.round(); x++) {
        if (x < 0 || x >= w) continue;
        final i = (y * w + x) * 4;
        sum += px[i] * .299 + px[i + 1] * .587 + px[i + 2] * .114;
        n++;
      }
    }
    return n == 0 ? 0 : sum / n;
  }

  Future<(LauncherController, FakeGateway)> launchWithShot(
      WidgetTester t) async {
    t.view.physicalSize = const Size(1920, 1080);
    t.view.devicePixelRatio = 1;
    final g = FakeGateway(), c = LauncherController(g);
    await c.initialize();
    await t.pumpWidget(RepaintBoundary(
        key: shotKey, child: LauncherApp(controller: c)));
    await t.pumpAndSettle();
    addTearDown(() async {
      await t.pumpWidget(const SizedBox.shrink());
      c.dispose();
      await g.dispose();
      t.view.resetPhysicalSize();
      t.view.resetDevicePixelRatio();
    });
    return (c, g);
  }

  for (final style in ['blueGlass', 'classic', 'nocturne']) {
    for (final mode in ['light', 'dark']) {
      // 暗夜恒暗，light 那一轮与 dark 等价，跳过以免重复。
      if (style == 'nocturne' && mode == 'light') continue;
      testWidgets('palette dot highlight stays bright on $style / $mode',
          (t) async {
        final (c, _) = await launchWithShot(t);
        c.setAppearance(
            c.appearance.copyWith(themeStyle: style, mode: mode),
            save: false);
        c.openSettings();
        await t.pumpAndSettle();

        // 用未选中的「冰川」球：选中那枚中间压着白勾，会污染采样。
        final dot = t.getRect(find.byKey(const ValueKey('dot-blue')));
        final (px, w, h) = await grab(t);

        // 高光带：球顶往下 4~9 px（球总高 38）；球身中带：18~26 px。
        final highlight = meanLuma(
            px, w, h, Rect.fromLTWH(dot.left + 8, dot.top + 4, dot.width - 16, 5));
        final body = meanLuma(
            px, w, h, Rect.fromLTWH(dot.left + 8, dot.top + 18, dot.width - 16, 8));
        expect(highlight, greaterThan(body),
            reason: '$style/$mode 的球顶比球身还暗——高光被画成了阴影');
        expect(highlight - body, greaterThan(6),
            reason: '$style/$mode 的高光太弱，球面又变平了');
        expect(t.takeException(), null);
      });
    }
  }
}
