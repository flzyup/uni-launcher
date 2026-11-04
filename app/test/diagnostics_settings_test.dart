import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uni_launcher/model/appearance.dart';
import 'package:uni_launcher/theme/launcher_theme.dart';
import 'package:uni_launcher/widgets/diagnostics_settings.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('xyz.i4o.uni.launcher/log');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  final calls = <String, Object?>{};

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
    expect(find.textContaining('2 KB'), findsOneWidget);
    expect(find.textContaining('锚点节点 7'), findsOneWidget);
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

    await tester.tap(find.byType(DropdownButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('调试').last);
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
}
