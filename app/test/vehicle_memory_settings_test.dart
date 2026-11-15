import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uni_launcher/controller/launcher_controller.dart';
import 'package:uni_launcher/launcher_app.dart';
import 'fake_gateway.dart';

/// 记忆配置标签：驾驶模式与自动启停各自开关，命令只带用户明确选择的键，
/// 关掉的那一项不发送任何写入。
void main() {
  Future<(LauncherController, FakeGateway)> open(WidgetTester t,
      {bool connected = true}) async {
    t.view.physicalSize = const Size(1920, 1080);
    t.view.devicePixelRatio = 1;
    final g = FakeGateway();
    g.state['demo'] = false;
    g.state['vehicleMemory'] = {
      'driveModeEnabled': false,
      'driveMode': 'PURE',
      'startStopEnabled': false,
      'startStop': true,
      'driveModes': ['ECO', 'COMFORT', 'PURE', 'HYBRID'],
    };
    g.state['apps'] = [
      {
        'id': 'test.nav/.Main',
        'package': 'test.nav',
        'label': '测试导航',
        'enabled': true
      },
      {
        'id': 'test.music/.Main',
        'package': 'test.music',
        'label': '测试音乐',
        'enabled': true
      }
    ];
    g.state['vehicle'] = {      'connected': connected,
      'fields': {},
      'climate': {},
      'settings': {
        'driveMode': {
          'readable': connected,
          'current': connected ? 'PURE' : null,
          'supported': ['ECO', 'COMFORT', 'PURE', 'HYBRID'],
          'commandable': connected
        },
        'startStop': {
          'readable': connected,
          'current': connected ? true : null,
          'supported': [false, true],
          'commandable': connected
        }
      },
      'memory': {
        'driveMode': {'state': 'confirmed', 'reason': '目标状态已读回'},
        'startStop': {'state': 'unchanged', 'reason': '当前已是记忆值'}
      }
    };
    final c = LauncherController(g);
    await c.initialize();
    await t.pumpWidget(LauncherApp(controller: c));
    c.openSettings();
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('tab-memory')));
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

  testWidgets('memory tab lists both blocks with live state', (t) async {
    final (_, g) = await open(t);
    expect(find.text('记忆配置'), findsWidgets);
    expect(find.text('驾驶模式'), findsOneWidget);
    expect(find.text('自动启停'), findsOneWidget);
    expect(find.textContaining('当前：纯电'), findsOneWidget);
    expect(find.textContaining('当前：开启'), findsOneWidget);
    expect(find.textContaining('启动应用：已应用'), findsOneWidget);
    expect(find.byKey(const ValueKey('memory-mode-PURE')), findsOneWidget);
    expect(g.commands.where((c) => c['action'] == 'drive-mode'), isEmpty);
    expect(t.takeException(), isNull);
  });

  testWidgets('disabled items never send a value or an apply command',
      (t) async {
    final (_, g) = await open(t);
    await t.tap(find.byKey(const ValueKey('memory-mode-COMFORT')));
    await t.pumpAndSettle();
    expect(g.commands.last,
        containsPair('action', 'memory-drive-mode-target'));
    expect(g.commands.last, containsPair('value', 'COMFORT'));
    // 开关仍关闭时，「立即应用」不可点，也不会发出 drive-mode。
    await t.tap(find.byKey(const ValueKey('memory-apply-drive-mode')),
        warnIfMissed: false);
    await t.pumpAndSettle();
    expect(g.commands.where((c) => c['action'] == 'memory-apply-now'), isEmpty);
    expect(g.commands.where((c) => c['action'] == 'drive-mode'), isEmpty);
    expect(g.commands.where((c) => c['action'] == 'start-stop'), isEmpty);
  });

  testWidgets('each toggle is independent and applies only its own item',
      (t) async {
    final (_, g) = await open(t);
    await t.tap(find.byKey(const ValueKey('memory-start-stop-enabled')));
    await t.pumpAndSettle();
    expect(g.commands.last,
        containsPair('action', 'memory-start-stop-enabled'));
    expect(g.commands.last, containsPair('enabled', true));
    expect(g.commands.where((c) => c['action'] == 'memory-drive-mode-enabled'),
        isEmpty);
    expect(g.commands.where((c) => c['action'] == 'start-stop'), isEmpty);
  });

  testWidgets('disconnected vehicle still shows the stored target', (t) async {
    final (_, g) = await open(t, connected: false);
    // 两句说明都下沉到各卡副标题（f37 没有总说明块）：两张卡各来一条。
    expect(find.textContaining('当前值尚未读到'), findsNWidgets(2));
    expect(g.commands.where((c) => c['action'] == 'drive-mode'), isEmpty);
    expect(t.takeException(), isNull);
  });

  testWidgets('drive mode and start-stop sit side by side above boot items',
      (t) async {
    final (_, g) = await open(t);
    final drive = t.getRect(find.byKey(const ValueKey('memory-drive-mode-enabled')));
    final stop = t.getRect(find.byKey(const ValueKey('memory-start-stop-enabled')));
    expect(drive.top, closeTo(stop.top, 2));
    expect(drive.left, lessThan(stop.left));
    final boot = t.getRect(find.byKey(const ValueKey('boot-launch-enabled')));
    expect(boot.top, greaterThan(drive.bottom));
    expect(g.commands.where((c) => c['action'] == 'drive-mode'), isEmpty);
    expect(t.takeException(), isNull);
  });

  testWidgets('auto play music moved into the memory tab', (t) async {
    final (_, g) = await open(t);
    expect(find.byKey(const ValueKey('auto-play-music')), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('tab-connections')));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('auto-play-music')), findsNothing);
    expect(g.commands.where((c) => c['action'] == 'auto-play-music'), isEmpty);
    expect(t.takeException(), isNull);
  });

  group('开机自启动', () {
    Future<void> reveal(WidgetTester t, Finder finder) async {
      await t.scrollUntilVisible(finder, 240,
          scrollable: find
              .descendant(
                  of:
                      find.byKey(const PageStorageKey('vehicle-memory-scroll')),
                  matching: find.byType(Scrollable))
              .first);
      await t.pumpAndSettle();
    }
    Map<String, dynamic> plan(String id, int delay,
            {String state = '', bool installed = true}) =>
        {
          'key': '$id@$delay',
          'id': id,
          'package': id.split('/').first,
          'delay': delay,
          'installed': installed,
          if (state.isNotEmpty) 'state': state,
          if (state == 'failed') 'reason': '应用未安装或无法启动',
        };

    testWidgets('lists plans with boot timing and last result', (t) async {
      final (_, g) = await open(t);
      g.state['bootLaunch'] = {
        'enabled': true,
        'maxDelay': 600,
        'plans': [
          plan('test.nav/.Main', 0, state: 'launched'),
          plan('test.music/.Main', 5, state: 'failed'),
          plan('test.uninstalled/.Main', 8, installed: false),
        ],
      };
      g.stream.add(Map.of(g.state));
      await t.pumpAndSettle();
      // 计划卡上只留「时机 + 应用名」，上次的结果挂在卡的 tooltip 上。
      expect(find.text('开机立刻'), findsOneWidget);
      expect(find.text('开机后 5 秒'), findsOneWidget);
      expect(find.text('开机后 8 秒'), findsOneWidget);
      expect(
          find.byTooltip('开机立刻 · 已启动'), findsOneWidget);
      expect(
          find.byTooltip('开机后 5 秒 · 上次未启动 · 应用未安装或无法启动'),
          findsOneWidget);
      expect(t.takeException(), isNull);
    });

    testWidgets('run now and remove act on the exact plan key', (t) async {
      final (_, g) = await open(t);
      g.state['bootLaunch'] = {
        'enabled': true,
        'maxDelay': 600,
        'plans': [plan('test.nav/.Main', 8)],
      };
      g.stream.add(Map.of(g.state));
      await t.pumpAndSettle();
      await reveal(
          t, find.byKey(const ValueKey('boot-plan-run-test.nav/.Main@8')));
      await t.tap(
          find.byKey(const ValueKey('boot-plan-run-test.nav/.Main@8')));
      await t.pumpAndSettle();
      expect(g.commands.last, containsPair('action', 'boot-launch-run'));
      expect(g.commands.last, containsPair('value', 'test.nav/.Main@8'));
      await t.tap(
          find.byKey(const ValueKey('boot-plan-remove-test.nav/.Main@8')));
      await t.pumpAndSettle();
      expect(g.commands.last, containsPair('action', 'boot-launch-remove'));
      expect(g.commands.last, containsPair('value', 'test.nav/.Main@8'));
    });

    testWidgets('adding a plan sends app id and chosen seconds', (t) async {
      final (_, g) = await open(t);
      g.state['bootLaunch'] = {
        'enabled': true,
        'maxDelay': 600,
        'plans': <dynamic>[],
      };
      g.stream.add(Map.of(g.state));
      await t.pumpAndSettle();
      await reveal(t, find.byKey(const ValueKey('boot-launch-add')));
      await t.tap(find.byKey(const ValueKey('boot-launch-add')));
      await t.pumpAndSettle();
      expect(find.text('选择要自动启动的应用'), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('boot-app-test.nav/.Main')));
      await t.pumpAndSettle();
      expect(find.text('启动时机'), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('boot-delay-8')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('boot-delay-confirm')));
      await t.pumpAndSettle();
      expect(g.commands.last, containsPair('action', 'boot-launch-add'));
      expect(g.commands.last, containsPair('value', 'test.nav/.Main'));
      expect(g.commands.last, containsPair('zone', '8'));
      expect(t.takeException(), isNull);
    });

    testWidgets('master switch off still keeps the plans visible', (t) async {
      final (_, g) = await open(t);
      g.state['bootLaunch'] = {
        'enabled': false,
        'maxDelay': 600,
        'plans': [plan('test.nav/.Main', 3)],
      };
      g.stream.add(Map.of(g.state));
      await t.pumpAndSettle();
      expect(find.text('开机后 3 秒'), findsOneWidget);
      expect(find.byKey(const ValueKey('boot-launch-enabled')), findsOneWidget);
      await reveal(t, find.byKey(const ValueKey('boot-launch-enabled')));
      await t.tap(find.byKey(const ValueKey('boot-launch-enabled')));
      await t.pumpAndSettle();
      expect(g.commands.last, containsPair('action', 'boot-launch-enabled'));
      expect(g.commands.last, containsPair('enabled', true));
      expect(g.commands.where((c) => c['action'] == 'boot-launch-add'), isEmpty);
    });
  });

  group('开机自动启动无线 adb', () {
    Future<void> reveal(WidgetTester t, Finder finder) async {
      await t.scrollUntilVisible(finder, 240,
          scrollable: find
              .descendant(
                  of:
                      find.byKey(const PageStorageKey('vehicle-memory-scroll')),
                  matching: find.byType(Scrollable))
              .first);
      await t.pumpAndSettle();
    }

    testWidgets('ready state shows the adb connect address', (t) async {
      final (_, g) = await open(t);
      g.state['wirelessAdb'] = {
        'enabled': true,
        'port': 5555,
        'portProperty': '5555',
        'adbEnabled': true,
        'listening': true,
        'address': '192.168.22.18:5555',
        'state': 'ready',
        'reason': '',
        'attempt': 1,
      };
      g.stream.add(Map.of(g.state));
      await t.pumpAndSettle();
      expect(find.textContaining('已就绪'), findsOneWidget);
      expect(
          find.text('adbd 已在 5555 端口监听 · adb connect 192.168.22.18:5555'),
          findsOneWidget);
      expect(t.takeException(), isNull);
    });

    testWidgets('blocked state surfaces the system reason', (t) async {
      final (_, g) = await open(t);
      g.state['wirelessAdb'] = {
        'enabled': true,
        'state': 'blocked',
        'reason': '系统未允许设置调试端口，需要 USB 连接后执行一次 adb tcpip 5555',
        'attempt': 6,
        'address': '192.168.22.18:5555',
      };
      g.stream.add(Map.of(g.state));
      await t.pumpAndSettle();
      expect(find.textContaining('被系统拦下'), findsOneWidget);
      expect(find.textContaining('adb tcpip 5555'), findsOneWidget);
      expect(find.text('已尝试 6 次'), findsOneWidget);
      expect(t.takeException(), isNull);
    });

    testWidgets('toggle and manual run send the exact actions', (t) async {
      final (_, g) = await open(t);
      g.state['wirelessAdb'] = {'enabled': false, 'state': 'off'};
      g.stream.add(Map.of(g.state));
      await t.pumpAndSettle();
      await reveal(t, find.byKey(const ValueKey('wireless-adb-enabled')));
      await t.tap(find.byKey(const ValueKey('wireless-adb-enabled')));
      await t.pumpAndSettle();
      expect(g.commands.last, containsPair('action', 'wireless-adb-enabled'));
      expect(g.commands.last, containsPair('enabled', true));
      await t.tap(find.byKey(const ValueKey('wireless-adb-run')));
      await t.pumpAndSettle();
      expect(g.commands.last, containsPair('action', 'wireless-adb-run'));
      expect(t.takeException(), isNull);
    });
  });

  testWidgets('整页在一屏内放下（模式 + 计划 + adb 全满时）', (t) async {
    final (_, g) = await open(t);
    g.state['vehicleMemory'] = {
      'driveModeEnabled': true,
      'driveMode': 'PURE',
      'startStopEnabled': true,
      'startStop': true,
      'driveModes': ['ECO', 'COMFORT', 'PURE', 'HYBRID'],
    };
    g.state['bootLaunch'] = {
      'enabled': true,
      'maxDelay': 600,
      'plans': [
        {'key': 'a', 'id': 'test.nav/.Main', 'package': 'test.nav', 'delay': 0},
        {
          'key': 'b',
          'id': 'test.music/.Main',
          'package': 'test.music',
          'delay': 5
        },
        {
          'key': 'c',
          'id': 'test.zzz/.Main',
          'package': 'test.zzz',
          'delay': 8
        },
      ],
    };
    g.state['wirelessAdb'] = {
      'enabled': true,
      'state': 'ready',
      'port': 5555,
      'address': '192.168.4.23:5555'
    };
    g.stream.add(Map.of(g.state));
    await t.pumpAndSettle();
    final position = t
        .state<ScrollableState>(find
            .descendant(
                of:
                    find.byKey(const PageStorageKey('vehicle-memory-scroll')),
                matching: find.byType(Scrollable))
            .first)
        .position;
    // 这一页按设计稿是「一屏看完」的：真实数据全满（3 个驾驶模式、3 条开机
    // 计划、adb 已就绪）也不该需要滚动。之前三颗「立即应用…」用的是
    // TextButton，被主题的 minimumSize(60) 撑成三个 60 高的胶囊，
    // 把底部的「启动执行顺序」时间轴顶出屏幕。
    expect(position.maxScrollExtent, 0);
    expect(find.text('启动执行顺序'), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('只列三个主模式，自定义/陡坡缓降/地形不进列表', (t) async {
    final (_, g) = await open(t);
    // 原生把 CommandPolicy.DRIVE_MODES 全集当选项源发下来（12 个）。
    g.state['vehicleMemory']['driveModes'] = [
      'ECO', 'COMFORT', 'DYNAMIC', 'INDIVIDUAL', 'XC', 'HDC',
      'PURE', 'HYBRID', 'POWER', 'RACE', 'ECO_HEV_PHEV', 'COMFORT_HEV'
    ];
    g.state['vehicle']['settings']['driveMode']['supported'] = [
      'ECO', 'COMFORT', 'DYNAMIC', 'INDIVIDUAL', 'XC', 'HDC'
    ];
    // 记忆值落在一个主模式上，免得「补位」规则把 DYNAMIC 挤掉，混淆本用例。
    g.state['vehicleMemory']['driveMode'] = 'DYNAMIC';
    g.stream.add(Map.of(g.state));
    await t.pumpAndSettle();

    for (final mode in ['ECO', 'COMFORT', 'DYNAMIC']) {
      expect(find.byKey(ValueKey('memory-mode-$mode')), findsOneWidget,
          reason: '$mode 应该出现');
    }
    for (final mode in ['INDIVIDUAL', 'XC', 'HDC', 'PURE', 'HYBRID', 'POWER']) {
      expect(find.byKey(ValueKey('memory-mode-$mode')), findsNothing,
          reason: '$mode 不该出现在开机记忆里');
    }
    expect(t.takeException(), isNull);
  });

  testWidgets('记忆值不在前三颗时补进列表，选中态不丢', (t) async {
    final (_, g) = await open(t);
    g.state['vehicleMemory']['driveMode'] = 'HYBRID';
    g.state['vehicle']['settings']['driveMode']['supported'] = [
      'ECO', 'COMFORT', 'DYNAMIC', 'HYBRID'
    ];
    g.stream.add(Map.of(g.state));
    await t.pumpAndSettle();

    expect(find.byKey(const ValueKey('memory-mode-HYBRID')), findsOneWidget,
        reason: '记忆值必须看得见，否则像是没设置成功');
    // 仍然只有三个：补位会挤掉最后一颗，不会越加越多。
    final chips = find.byWidgetPredicate((w) =>
        w.key is ValueKey &&
        '${(w.key as ValueKey).value}'.startsWith('memory-mode-'));
    expect(chips, findsNWidgets(3));
    expect(t.takeException(), isNull);
  });
}
