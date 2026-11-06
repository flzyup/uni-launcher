import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uni_launcher/controller/launcher_controller.dart';
import 'package:uni_launcher/launcher_app.dart';
import 'package:uni_launcher/widgets/storage_cleaner_panel.dart';

import 'fake_gateway.dart';

/// 垃圾清理面板：分组、默认勾选、风险标签、二次确认、权限自动申请。
/// 判定逻辑本身在原生 `CleanerRules`（见 tools/test_cleaner_rules.py），
/// 这里只验证界面照原样呈现、命令按选择下发。
void main() {
  Map<String, dynamic> category(
          String id, String name, int bytes,
          {String group = 'junk',
          String risk = 'safe',
          bool defaultSelected = true,
          bool verified = true,
          bool available = true,
          String note = '',
          int count = 1}) =>
      {
        'id': id,
        'name': name,
        'group': group,
        'risk': risk,
        'default': defaultSelected,
        'verified': verified,
        'bytes': bytes,
        'count': count,
        'note': note,
        'available': available,
      };

  Map<String, dynamic> cleanerPacket(List<dynamic> categories,
          {bool running = false,
          String phase = 'idle',
          double progress = 0,
          String current = '',
          String error = '',
          String rulesIssue = '',
          bool storageGranted = true,
          int lastCleanBytes = 0,
          int purgeFiles = 0,
          int purgeTotal = 0,
          int scanned = 0,
          int scanMs = 0}) =>
      {
        'running': running,
        'phase': phase,
        'progress': progress,
        'current': current,
        'rev': 7,
        'free': 20 << 30,
        'total': 64 << 30,
        'storageGranted': storageGranted,
        'categories': categories,
        'lastClean': {'bytes': lastCleanBytes, 'at': 1793000000000, 'ids': []},
        'error': error,
        'rulesIssue': rulesIssue,
        'purgeFiles': purgeFiles,
        'purgeTotal': purgeTotal,
        'scanned': scanned,
        'scanMs': scanMs,
      };

  Future<(LauncherController, FakeGateway)> openPanel(WidgetTester t,
      Map<String, dynamic> cleaner) async {
    t.view.physicalSize = const Size(1920, 1080);
    t.view.devicePixelRatio = 1;
    final g = FakeGateway();
    g.state = {...g.state, 'cleaner': cleaner};
    final c = LauncherController(g);
    await c.initialize();
    await t.pumpWidget(LauncherApp(controller: c));
    await t.pumpAndSettle();
    // 真实入口是 UNI 菜单第四项，这里直接推同一张面板。
    unawaited(
        showCleanerPanel(t.element(find.byKey(const ValueKey('home'))), c));
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

  testWidgets('打开就扫描，按分组列出全机垃圾并勾上默认项', (t) async {
    final (_, g) = await openPanel(
        t,
        cleanerPacket([
          category('app-cache', '应用缓存', 1 << 20,
              group: 'cache', risk: 'low', note: '6 个应用'),
          category('external-cache', '应用外部缓存', 4 << 20,
              group: 'cache', note: '应用存在公共存储里的缓存，会自动重建'),
          category('thumbnails', '缩略图缓存', 512 << 10, note: '相册缩略图'),
          category('log', '日志与临时文件', 1024, risk: 'low', note: '只清 3 天前的日志'),
          category('orphan-data', '卸载残留', 3 << 20,
              group: 'leftover', risk: 'review', defaultSelected: false),
          category('apk-leftover', '安装包', 60 << 20,
              group: 'leftover', risk: 'review', defaultSelected: false),
          category('large-unused', '长期未动的大文件', 800 << 20,
              group: 'large', risk: 'review', defaultSelected: false),
        ]));

    // 三个分组标题都在，一眼能看出层次。
    expect(find.text('缓存'), findsOneWidget);
    expect(find.text('系统垃圾'), findsOneWidget);
    expect(find.text('残留与安装包'), findsOneWidget);
    // 默认勾选的是缓存与系统垃圾：1 + 4 + 0.5 MB + 1KB ≈ 5.5 MB。
    // 大字是全部可清量（含未勾选的 review 类），已选金额在底部状态行。
    expect(find.textContaining('已选 4 项'), findsOneWidget);
    expect(find.textContaining('5.5 MB'), findsWidgets);
    expect(find.byKey(const ValueKey('cleaner-item-external-cache')),
        findsOneWidget);
    // review 类只标记不默认勾；「大文件」在列表底部，滚下去才渲染。
    final largeRow = find.byKey(const ValueKey('cleaner-item-large-unused'));
    await t.dragUntilVisible(
        largeRow, find.byType(ListView), const Offset(0, -140));
    await t.pumpAndSettle();
    expect(find.text('大文件'), findsOneWidget);
    expect(largeRow, findsOneWidget);
    expect(find.descendant(of: largeRow, matching: find.text('需确认')),
        findsOneWidget);
    expect(
        g.commands,
        contains(predicate((Map<String, dynamic> m) =>
            m['action'] == 'cleaner-scan')),
        reason: '面板打开应当触发一次扫描');
  });

  testWidgets('取消勾选会改金额，清理必须再过一次确认', (t) async {
    final (_, g) = await openPanel(
        t,
        cleanerPacket([
          category('self-cache', '桌面缓存', 2 << 20, group: 'cache'),
          category('apk-leftover', '安装包', 8 << 20,
              group: 'leftover', risk: 'review', defaultSelected: false),
        ]));

    expect(find.text('清理 2.0 MB'), findsOneWidget);

    await t.tap(find.byKey(const ValueKey('cleaner-item-apk-leftover')));
    await t.pumpAndSettle();
    expect(find.text('清理 10.0 MB'), findsOneWidget);

    // 第一次点击只是进入确认态，不发命令。
    await t.tap(find.text('清理 10.0 MB'));
    await t.pumpAndSettle();
    expect(find.text('确认清理 10.0 MB'), findsOneWidget);
    expect(
        g.commands,
        isNot(contains(predicate((Map<String, dynamic> m) =>
            m['action'] == 'cleaner-clean'))));

    await t.tap(find.text('确认清理 10.0 MB'));
    await t.pumpAndSettle();
    final clean = g.commands.firstWhere(
        (m) => m['action'] == 'cleaner-clean',
        orElse: () => <String, dynamic>{});
    expect('${clean['value']}', 'self-cache,apk-leftover');
  });

  testWidgets('取消确认不会下发命令', (t) async {
    final (_, g) = await openPanel(
        t,
        cleanerPacket(
            [category('self-cache', '桌面缓存', 2 << 20, group: 'cache')]));
    await t.tap(find.text('清理 2.0 MB'));
    await t.pumpAndSettle();
    await t.tap(find.text('取消'));
    await t.pumpAndSettle();
    expect(find.text('清理 2.0 MB'), findsOneWidget);
    expect(
        g.commands,
        isNot(contains(predicate(
            (Map<String, dynamic> m) => m['action'] == 'cleaner-clean'))));
  });

  testWidgets('扫描中显示进度并允许停止', (t) async {
    final (_, g) = await openPanel(
        t,
        cleanerPacket([
          category('self-cache', '桌面缓存', 2 << 20,
              group: 'cache', available: false, note: ''),
        ],
            running: true,
            phase: 'scan',
            progress: 0.4,
            current: '日志与临时文件'));

    expect(find.text('扫描中 40%'), findsWidgets);
    expect(find.textContaining('日志与临时文件'), findsWidgets);
    await t.tap(find.text('停止'));
    await t.pumpAndSettle();
    expect(
        g.commands,
        contains(predicate(
            (Map<String, dynamic> m) => m['action'] == 'cleaner-cancel')));
  });

  testWidgets('没有存储权限时自动申请，不跳设置页也不重复扫描', (t) async {
    final (_, g) = await openPanel(
        t,
        cleanerPacket([
          category('log', '日志与临时文件', 0,
              available: false, note: '正在获取存储权限…'),
        ], storageGranted: false));

    // 打开面板直接发授权命令（原生会弹系统框），不发 scan。
    expect(
        g.commands,
        contains(predicate(
            (Map<String, dynamic> m) => m['action'] == 'cleaner-grant')));
    expect(
        g.commands,
        isNot(contains(predicate(
            (Map<String, dynamic> m) => m['action'] == 'cleaner-scan'))));
    expect(find.text('正在获取存储权限…'), findsWidgets);
    expect(find.text('等待存储权限'), findsOneWidget);
    // 不再有「去授权」跳应用信息页的路径。
    expect(find.text('去授权'), findsNothing);
    expect(
        g.commands,
        isNot(contains(predicate((Map<String, dynamic> m) =>
            m['action'] == 'app-info'))));

    await t.tap(find.text('重试授权'));
    await t.pumpAndSettle();
    expect(
        g.commands
            .where((m) => m['action'] == 'cleaner-grant')
            .length,
        greaterThanOrEqualTo(2));
  });

  testWidgets('出错与上次清理结果都写在底部说明里', (t) async {
    await openPanel(
        t,
        cleanerPacket([
          category('self-cache', '桌面缓存', 0,
              group: 'cache', defaultSelected: false)
        ],
            error: '2 个应用的缓存未能清理（系统拒绝）', lastCleanBytes: 3 << 20));
    expect(find.byKey(const ValueKey('cleaner-note')), findsOneWidget);
    expect(find.textContaining('2 个应用的缓存未能清理'), findsOneWidget);
    expect(find.textContaining('释放 3.0 MB'), findsOneWidget);
    expect(find.text('暂无可清理内容'), findsOneWidget);
  });

  testWidgets('清理上万张缩略图时按文件数推进，而不是只跳类目', (t) async {
    final (_, g) = await openPanel(
        t,
        cleanerPacket([
          category('thumbnails', '缩略图缓存', 188 << 20,
              note: '相册缩略图', count: 13762),
        ],
            running: true,
            phase: 'clean',
            progress: 0.3,
            current: '缩略图缓存',
            purgeFiles: 3200,
            purgeTotal: 13762));

    expect(find.textContaining('正在清理 3200 / 13762 个文件'), findsWidgets);
    await t.tap(find.text('停止'));
    await t.pumpAndSettle();
    expect(
        g.commands,
        contains(predicate(
            (Map<String, dynamic> m) => m['action'] == 'cleaner-cancel')));
  });

  testWidgets('扫完在底部交代扫描了多少项、花了多久', (t) async {
    await openPanel(
        t,
        cleanerPacket([
          category('thumbnails', '缩略图缓存', 188 << 20,
              note: '相册缩略图', count: 13762),
        ], scanned: 460, scanMs: 1240));

    expect(find.textContaining('扫描 460 项'), findsOneWidget);
    expect(find.textContaining('1.2 秒'), findsOneWidget);
  });
}
