import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uni_launcher/model/appearance.dart';
import 'package:uni_launcher/theme/launcher_theme.dart';
import 'package:uni_launcher/widgets/choice_button.dart';
import 'package:uni_launcher/widgets/diagnostics_settings.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('xyz.i4o.uni.launcher/log');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  final calls = <String, Object?>{};

  /// 模拟「原生 status 是否已报落盘策略那五个字段」。
  ///
  /// 2026-11-08 之前 `LogBridge.status()` 只报七个基础字段，界面那四行只能
  /// 显示「—」；补上之后两组断言都要留着——老固件（没补）与新固件（补了）
  /// 都得能正确渲染，不能因为新字段缺失就崩或显示 0。
  var policy = false;

  void mockLogChannel() {
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls[call.method] = call.arguments;
      switch (call.method) {
        case 'status':
          return {
            'level': 'INFO',
            'bytes': 2048,
            'degraded': false,
            'anchors': 7,
            'initialized': true,
            'storageWritable': true,
            'storageReadable': true,
            if (policy) ...{
              'files': 3,
              'maxFileBytes': 512 * 1024,
              'maxFiles': 8,
              'maxTotalBytes': 4 * 1024 * 1024,
              'minFreeBytes': 16 * 1024 * 1024,
            },
          };
        case 'ensurePermission':
          return true;
        case 'export':
          return {
            'ok': true,
            'path': '/storage/emulated/0/Download/UNI/uni-logs-20261103-204012.zip',
            'files': 3,
            'bytes': 4096,
            'reason': '',
            'message':
                '诊断包已导出：/storage/emulated/0/Download/UNI/uni-logs-20261103-204012.zip',
          };
        case 'exportAndShare':
          return {
            'ok': true,
            'path': '/storage/emulated/0/Download/UNI/uni-logs-20261103-204012.zip',
            'files': 3,
            'bytes': 4096,
            'reason': '',
            'message': '',
          };
        case 'clear':
          return '日志已清空';
        case 'preview':
          return '11-03 20:04:12.345 I UNI/App : 启动完成';
        case 'level':
          return 'DEBUG';
        default:
          return null;
      }
    });
  }

  setUp(() {
    calls.clear();
    policy = false;
    mockLogChannel();
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
  });

  Future<void> pumpPanel(WidgetTester tester) async {
    // The panel reads the SurfaceStyle theme extension, so it has to be
    // pumped under the app theme like it is on the device.
    final style = SurfaceStyle.from(const Appearance(), false);
    await tester.pumpWidget(MaterialApp(
        theme: launcherTheme(style),
        home: const Scaffold(
            body: SingleChildScrollView(child: DiagnosticsSettings()))));
    await tester.pumpAndSettle();
  }

  testWidgets('shows the log system state', (tester) async {
    await pumpPanel(tester);

    expect(find.text('诊断日志'), findsOneWidget);
    expect(find.textContaining('Download/UNI/'), findsOneWidget);
    // 设计稿把三列统计拆成「小标题 / 大字 / 单位」三层，所以逐层断言。
    expect(find.text('已落盘占用'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    expect(find.text('锚点节点'), findsOneWidget);
    expect(find.text('7'), findsOneWidget);
    expect(find.text('日志文件'), findsOneWidget);
  });

  /// 原生补了落盘策略五个字段之后，四行与顶部的份数都要变实值。
  ///
  /// 值取自 `FileLogSink` 的常量（512KB / 8 份 / 4MB / 16MB），界面只负责
  /// 换算与排版，所以这里连「KB / MB 的写法」一起钉住——单位算错比显示「—」
  /// 更容易骗过人。
  testWidgets('落盘策略与份数来自原生 status', (tester) async {
    policy = true;
    await pumpPanel(tester);

    expect(find.text('3'), findsOneWidget, reason: '顶部「日志文件 N 份」');
    expect(find.text('512 KB · 8 份'), findsOneWidget);
    expect(find.text('4 MB'), findsOneWidget);
    expect(find.text('剩余 < 16 MB 停写'), findsOneWidget);
    expect(find.text('—'), findsNothing, reason: '有真值就不该再有破折号');
  });

  /// 老固件不报这五个字段时，四行仍是「—」，且不能拿 0 冒充。
  testWidgets('原生没报策略字段时四行显示破折号', (tester) async {
    await pumpPanel(tester);

    expect(find.text('— · —'), findsOneWidget);
    // 总字节上限、余量保护、顶部份数各一个破折号。
    expect(find.text('—'), findsNWidgets(3));
    expect(find.text('0 份'), findsNothing);
    expect(find.text('0 KB · 0 份'), findsNothing);
  });

  testWidgets('offers export, share, preview and clear', (tester) async {
    await pumpPanel(tester);

    expect(find.text('导出诊断包'), findsOneWidget);
    expect(find.text('导出并分享'), findsOneWidget);
    expect(find.text('预览最近日志'), findsOneWidget);
    expect(find.text('清空日志'), findsOneWidget);
  });

  testWidgets('export asks the native side for a package', (tester) async {
    await pumpPanel(tester);

    await tester.tap(find.text('导出诊断包'));
    await tester.pumpAndSettle();

    expect(calls.containsKey('export'), isTrue);
    // The result toast auto-dismisses after 2s; let the clock run past it so
    // the test does not end with a pending timer.
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
  });

  testWidgets('preview shows the tail of the log', (tester) async {
    await pumpPanel(tester);

    await tester.tap(find.text('预览最近日志'));
    await tester.pumpAndSettle();

    expect(calls.containsKey('preview'), isTrue);
    expect(find.textContaining('启动完成'), findsOneWidget);
  });

  testWidgets('the level picker changes the persistence threshold',
      (tester) async {
    await pumpPanel(tester);

    // 设计稿的四段是 `.seg` 单选：调试 / 信息 / 警告 / 仅错误。
    await tester.tap(find.byKey(const ValueKey('log-level-DEBUG')));
    await tester.pumpAndSettle();

    expect(calls['level'], 'DEBUG');
  });

  testWidgets('a degraded sink is called out', (tester) async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls[call.method] = call.arguments;
      if (call.method == 'status') {
        return {'level': 'INFO', 'bytes': 0, 'degraded': true, 'anchors': 0};
      }
      return null;
    });

    await pumpPanel(tester);

    expect(find.textContaining('日志落盘已降级'), findsOneWidget);
  });

  // Android 9 及以下导出诊断包要写公共目录，没有写权限会直接失败。
  // 面板必须先要权限，而不是让用户对着一句报错发呆。
  void mockWithoutStorage({required bool granted}) {
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls[call.method] = call.arguments;
      switch (call.method) {
        case 'status':
          return {
            'level': 'INFO',
            'bytes': 2048,
            'degraded': false,
            'anchors': 7,
            'initialized': true,
            'storageWritable': false,
            'storageReadable': false,
          };
        case 'ensurePermission':
          return granted;
        case 'export':
          return {
            'ok': true,
            'path': '/storage/emulated/0/Download/UNI/uni-logs.zip',
            'files': 1,
            'bytes': 4096,
            'reason': '',
            'message': '',
          };
        default:
          return null;
      }
    });
  }

  testWidgets('没有存储权限时先申请再导出', (tester) async {
    mockWithoutStorage(granted: true);
    await pumpPanel(tester);

    // 面板要能一眼看出「没权限」。
    expect(find.textContaining('存储权限未授予'), findsOneWidget);
    expect(find.text('申请存储权限'), findsOneWidget);

    await tester.tap(find.text('导出诊断包'));
    await tester.pumpAndSettle();

    expect(calls.containsKey('ensurePermission'), isTrue);
    expect(calls.containsKey('export'), isTrue);
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
  });

  testWidgets('存储权限被拒时不再导出', (tester) async {
    mockWithoutStorage(granted: false);
    await pumpPanel(tester);

    await tester.tap(find.text('导出诊断包'));
    await tester.pumpAndSettle();

    expect(calls.containsKey('ensurePermission'), isTrue);
    expect(calls.containsKey('export'), isFalse);
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
  });

  // 落盘级别是「写进原生 → 再读 status 回填」的链路。原生暂时没回执（或
  // 根本没有原生插件的预览环境）时，读回来的还是旧值，选中态就会在点下去
  // 的下一帧弹回去——用户看到的就是「按钮点了不切换」。
  testWidgets('点过的级别在原生回执之前一直是选中态', (tester) async {
    // status 恒为 INFO，模拟原生还没把新级别写进状态。
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls[call.method] = call.arguments;
      if (call.method == 'status') return {'level': 'INFO', 'bytes': 0};
      if (call.method == 'level') return 'WARN';
      return null;
    });

    await pumpPanel(tester);
    await tester.tap(find.byKey(const ValueKey('log-level-WARN')));
    await tester.pumpAndSettle();

    final warn = tester.widget<ChoiceButton>(
        find.byKey(const ValueKey('log-level-WARN')));
    final info = tester.widget<ChoiceButton>(
        find.byKey(const ValueKey('log-level-INFO')));
    expect(warn.selected, isTrue);
    expect(info.selected, isFalse);
  });
}
