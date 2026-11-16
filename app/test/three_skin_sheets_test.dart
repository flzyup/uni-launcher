import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uni_launcher/controller/launcher_controller.dart';
import 'package:uni_launcher/model/appearance.dart';
import 'package:uni_launcher/theme/launcher_theme.dart';
import 'package:uni_launcher/widgets/choice_button.dart';
import 'package:uni_launcher/widgets/steering_key_sheet.dart';
import 'package:uni_launcher/widgets/word_lyric_sheet.dart';

import 'fake_gateway.dart';

/// 方控接管（f39）与词级歌词（f40）在三套皮肤下都要能开、能显示真实数据。
/// 两页都只吃 SurfaceStyle 令牌，任何一套皮肤下丢元素，这里先炸。
void main() {
  Future<(LauncherController, BuildContext, FakeGateway)> boot(
      WidgetTester t, String style,
      {bool withWords = true, Map<String, dynamic>? mediaExtra}) async {
    t.view.physicalSize = const Size(1920, 1080);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    final gateway = FakeGateway();
    if (withWords) {
      gateway.state['media'] = {
        ...Map<String, dynamic>.from(gateway.state['media'] as Map),
        'positionMs': 102860,
        'durationMs': 238000,
        'sampledAtMs': DateTime.now().millisecondsSinceEpoch,
        'positionKnown': true,
        'lyricTimeline': jsonEncode({
          'v': 1,
          'lines': [
            {
              't': 102860,
              'd': 3300,
              'x': '后视镜里城市在退潮',
              'w': [
                [102860, 140, '后'],
                [103000, 180, '视'],
                [103180, 180, '镜'],
                [103360, 260, '里'],
                [103620, 500, '城市'],
                [104120, 300, '在'],
                [104420, 340, '退'],
                [104760, 300, '潮'],
              ]
            },
            {'t': 107000, 'd': 2600, 'x': '我把夜色折成一条桥'}
          ]
        })
      };
    }
    if (mediaExtra != null) {
      gateway.state['media'] = {
        ...Map<String, dynamic>.from(gateway.state['media'] as Map),
        ...mediaExtra,
      };
    }
    final controller = LauncherController(gateway);
    await controller.initialize();
    controller.setAppearance(
        controller.appearance.copyWith(themeStyle: style), save: false);
    late BuildContext context;
    await t.pumpWidget(MaterialApp(
        theme: launcherTheme(SurfaceStyle.from(controller.appearance, true)),
        home: Scaffold(
            body: Builder(builder: (ctx) {
          context = ctx;
          return const SizedBox.shrink();
        }))));
    addTearDown(controller.dispose);
    return (controller, context, gateway);
  }

  for (final style in Appearance.themeStyles) {
    testWidgets('$style 皮肤下方控接管页显示映射表并能开关', (t) async {
      final (c, context, gateway) = await boot(t, style);
      showSteeringKeySheet(context, c);
      await t.pumpAndSettle();
      expect(find.text('方控接管'), findsWidgets);
      // 三颗被接管的键 + 三组不接管的键，全部来自 SteeringKeyPolicy。
      expect(find.text('上一首'), findsOneWidget);
      expect(find.text('播放 / 暂停'), findsOneWidget);
      expect(find.text('下一首'), findsOneWidget);
      expect(find.text('已接管'), findsNWidgets(3));
      // 演示态没有 media.steeringKeys，四格统计都只能是「待接入」，不许编数字。
      expect(find.text('待接入'), findsNWidgets(4));
      expect(
          find.text('当前没有诊断数据：演示模式或原车方控未接入时 media.steeringKeys 为空。'),
          findsOneWidget);

      // 开关统一成设计稿那颗 46×26 的自绘开关（不再是 Material Switch）。
      final toggle = t.widget<DesignSwitch>(
          find.byKey(const ValueKey('steering-keys-switch')));
      expect(toggle.value, isTrue);
      toggle.onChanged!(false);
      await t.pumpAndSettle();
      expect(
          gateway.commands.any((cmd) =>
              cmd['action'] == 'steering-keys' && cmd['enabled'] == false),
          isTrue);
      expect(t.takeException(), isNull);
    });

    testWidgets('$style 皮肤下词级歌词页显示逐字时间轴', (t) async {
      final (c, context, gateway) = await boot(t, style);
      showWordLyricSheet(context, c);
      await t.pumpAndSettle();
      expect(find.text('词级歌词 · 时间轴'), findsWidgets);
      expect(find.text('当前句时间轴'), findsOneWidget);
      expect(find.text('8 词'), findsOneWidget);
      expect(find.text('填充规则'), findsOneWidget);
      expect(find.byKey(const ValueKey('lyric-progress')), findsOneWidget);
      expect(t.takeException(), isNull);
    });
  }

  testWidgets('方控诊断数据真实存在时显示计数与按键诊断', (t) async {
    final (c, context, _) = await boot(t, 'nocturne', withWords: false, mediaExtra: {
      // 这两块就是 MediaAdapter.snapshot() 里已经在传的字段。
      'steeringKeys': {
        'installed': true,
        'mode': 'adaptapi',
        'reason': '已接入原车方控输入（3 个键）',
        'accepted': 3,
        'events': 27,
        'lastCode': 200087,
        'seen': {'200088': 9, '200085': 12, '200087': 6},
      },
      'steeringInject': {
        'mode': 'input 命令',
        'injected': 21,
        'executed': 21,
        'failed': 0,
        'lastKey': 126,
      },
    });
    showSteeringKeySheet(context, c);
    await t.pumpAndSettle();
    expect(find.text('已接管 3 个键 · 接入方式 adaptapi'), findsOneWidget);
    expect(find.text('21'), findsOneWidget); // 按键注入
    expect(find.text('27'), findsOneWidget); // 收到按键
    expect(find.text('按键诊断 · 实车按下过的键码'), findsOneWidget);
    expect(find.text('200088 × 9'), findsOneWidget);
    expect(find.text('当前没有诊断数据：演示模式或原车方控未接入时 media.steeringKeys 为空。'),
        findsNothing);
    // 响应延迟原生仍无计时，这一格必须继续是待接入。
    expect(find.text('待接入'), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('没有逐字时间戳时明确说明，不假装对齐', (t) async {
    final (c, context, _) = await boot(t, 'nocturne', withWords: false);
    showWordLyricSheet(context, c);
    await t.pumpAndSettle();
    expect(find.text('无逐字数据'), findsOneWidget);
    expect(t.takeException(), isNull);
  });
}
