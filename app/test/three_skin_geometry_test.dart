import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uni_launcher/controller/launcher_controller.dart';
import 'package:uni_launcher/launcher_app.dart';
import 'package:uni_launcher/widgets/choice_button.dart';
import 'package:uni_launcher/widgets/setting_block.dart';
import 'fake_gateway.dart';

/// 设置页十屏的三皮肤结构一致性。
///
/// 计划书 §3.4 要的是「三皮肤 × 明暗五态 golden 图」。这里用**结构指纹**代替
/// 出图：采控件矩形与文本矩形，逐页断言另两套皮肤与暗夜逐像素相同。理由：
///
/// - golden 图依赖字体渲染，同一份代码在 Windows 预览机与 CI 上会差一两个
///   像素，维护成本高且容易「重新生成基线」把真问题盖掉；
/// - 而「换皮肤版式不该变」这件事本身就是几何命题，用矩形直接钉住更准，
///   报错时还能指出是哪个 key、差几像素。
///
/// 素材是 2026-11-08 那次体检的产物：外观页「主题风格 / 主题配色」两排按钮
/// 之前按皮肤分流（暗夜 42/76、玻璃与经典 47/86 画布），换主题时那两排一高
/// 一矮、下面几块跟着上下挪十几像素。当时是靠眼睛发现的，这个测试就是让这类
/// 差异以后自己冒出来。
void main() {
  /// 十页的 id，与 `_SettingsNav` 里那张表一一对应。
  const tabs = [
    'appearance',
    'dock',
    'connections',
    'motion',
    'ambient',
    'cluster',
    'memory',
    'cleaner',
    'system',
    'about',
  ];

  String keyOf(Element e) {
    final k = e.widget.key;
    if (k is ValueKey<String>) return k.value;
    if (k is PageStorageKey<String>) return k.value;
    return '';
  }

  /// 带 key 的控件：尺寸 + 全局位置。这些是「按钮大小」的直接证据。
  List<String> boxPrints(WidgetTester t) {
    final out = <String>[];
    void add(Type type, String kind) {
      for (final e in find.byType(type).evaluate()) {
        final r = e.renderObject;
        if (r is! RenderBox || !r.hasSize) continue;
        final k = keyOf(e);
        if (k.isEmpty) continue;
        final o = r.localToGlobal(Offset.zero);
        out.add('$kind:$k@${o.dx.toStringAsFixed(1)},'
            '${o.dy.toStringAsFixed(1)} '
            '${r.size.width.toStringAsFixed(1)}x'
            '${r.size.height.toStringAsFixed(1)}');
      }
    }

    add(ChoiceButton, 'choice');
    add(DesignSwitch, 'switch');
    add(SettingBlock, 'block');
    add(SettingRow, 'row');
    out.sort();
    return out;
  }

  /// 所有文本段的位置与尺寸。比 key 控件覆盖更广——不带 key 的块内文字、
  /// 段落换行都在这里。
  ///
  /// 只比 **纵向位置 + 宽高，不比横向位置**：选中项旁边那枚勾会让按钮内的
  /// 文字整体挪 10~12 px（同一页三皮肤各自选中不同的主题样式按钮），那是
  /// 选中态差异，不是布局差异；横向均分由上一条的 ChoiceButton 矩形负责。
  List<String> textPrints(WidgetTester t) {
    final out = <String>[];
    for (final e in find.byType(RichText).evaluate()) {
      final r = e.renderObject;
      if (r is! RenderBox || !r.hasSize) continue;
      final o = r.localToGlobal(Offset.zero);
      out.add('${o.dy.toStringAsFixed(1)} '
          '${r.size.width.toStringAsFixed(1)}x'
          '${r.size.height.toStringAsFixed(1)}');
    }
    out.sort();
    return out;
  }

  /// 每页有几个滚动区、各自溢出多少。某套皮肤下内容变长会在这里现形。
  List<String> scrollPrints(WidgetTester t) {
    final out = <String>[];
    for (final e in find.byType(Scrollable).evaluate()) {
      final st = (e as StatefulElement).state as ScrollableState;
      final r = e.renderObject;
      final dy = r is RenderBox ? r.localToGlobal(Offset.zero).dy : 0.0;
      out.add('${dy.toStringAsFixed(0)}:'
          '${st.position.maxScrollExtent.toStringAsFixed(1)}');
    }
    out.sort();
    return out;
  }

  testWidgets('settings pages keep one geometry across the three skins',
      (t) async {
    t.view.physicalSize = const Size(1920, 1080);
    t.view.devicePixelRatio = 1;
    final g = FakeGateway(), c = LauncherController(g);
    await c.initialize();
    await t.pumpWidget(LauncherApp(controller: c));
    await t.pumpAndSettle();
    c.openSettings();
    await t.pumpAndSettle();
    addTearDown(() async {
      await t.pumpWidget(const SizedBox.shrink());
      c.dispose();
      await g.dispose();
      t.view.resetPhysicalSize();
      t.view.resetDevicePixelRatio();
    });

    final base = <String, (List<String>, List<String>, List<String>)>{};
    final other = <String, Map<String, (List<String>, List<String>, List<String>)>>{
      'blueGlass': {},
      'classic': {},
    };

    for (final skin in ['nocturne', 'blueGlass', 'classic']) {
      c.setAppearance(c.appearance.copyWith(themeStyle: skin), save: false);
      await t.pumpAndSettle();
      for (final tab in tabs) {
        c.tab(tab);
        await t.pumpAndSettle();
        final prints = (boxPrints(t), textPrints(t), scrollPrints(t));
        if (skin == 'nocturne') {
          base[tab] = prints;
        } else {
          other[skin]![tab] = prints;
        }
        // 每次切页都清掉异常，避免某页溢出把后面的断言带偏。
        expect(t.takeException(), null, reason: '$skin · $tab 渲染异常');
        expect(find.text('外观与壁纸'), findsOneWidget);
      }
    }

    for (final skin in ['blueGlass', 'classic']) {
      for (final tab in tabs) {
        final (bBox, bText, bScroll) = base[tab]!;
        final (nBox, nText, nScroll) = other[skin]![tab]!;
        expect(nBox, bBox, reason: '$skin · $tab 控件尺寸/位置与暗夜不一致');
        expect(nText, bText, reason: '$skin · $tab 文本行位置与暗夜不一致');
        expect(nScroll, bScroll, reason: '$skin · $tab 滚动量与暗夜不一致');
      }
    }
  });
}
