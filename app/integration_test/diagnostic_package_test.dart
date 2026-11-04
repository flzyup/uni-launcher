import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:uni_launcher/main.dart' as app;
import 'package:uni_launcher/platform/log_tools.dart';
import 'package:uni_launcher/platform/uni_log.dart';

/// End to end check of the diagnostic package export.
///
/// The export is the only way to get evidence off a head unit that has no
/// debugger attached, so it has to be proven on a real device: the package
/// must land in the public Download folder, and it must carry both the
/// runtime snapshot and the log files.
///
/// The zip itself is inspected from the host side after the test, because
/// scoped storage does not let the app read the public folder back on
/// Android 10 and later.
///
/// Note on pumping: the home page keeps a continuous animation running, so
/// `pumpAndSettle` never reaches a quiet frame and would wait forever. Every
/// wait here is therefore an explicit duration.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // The launcher talks to the vehicle bus, the media controller and the OTA
  // service; on an emulator most of them answer late or not at all. The
  // budget below is generous on purpose — the point is to fail loudly
  // instead of hanging the whole suite.
  const budget = Timeout(Duration(minutes: 4));

  testWidgets('导出诊断包把 zip 落到公共目录', (tester) async {
    await app.main();
    await tester.pump(const Duration(seconds: 2));

    // 日志要先写进去，否则包里只有一个空壳。
    UniLog.i(UniLogTags.app, '诊断包导出验证');
    UniLog.enter(UniLogTags.vehicle, 'vehicle/verify');
    UniLog.done(UniLogTags.vehicle, 'vehicle/verify', fields: {'ok': true});
    await UniLog.flush();

    final result = await LogTools.export()
        .timeout(const Duration(seconds: 90), onTimeout: () {
      debugPrint('UNI_DIAG_EXPORT timeout');
      return const LogExportResult(
          ok: false,
          path: '',
          files: 0,
          bytes: 0,
          reason: 'timeout',
          message: '导出超时');
    });

    expect(result.ok, true, reason: '导出失败：${result.reason}');
    expect(result.path, contains('uni-logs-'));
    // 落在公共 Download 目录里。子目录能不能建出来取决于 App 有没有公共目录的
    // 写权限：系统应用落在 Download/UNI/，普通应用只能落在 Download/ 根下。
    expect(result.path, contains('Download/'),
        reason: '导出目录不对：${result.path}');
    expect(result.bytes, greaterThan(0));

    // 把落点写到 logcat，方便主机侧用 adb 找到这个文件。
    debugPrint('UNI_DIAG_EXPORT path=${result.path} bytes=${result.bytes} '
        'files=${result.files}');

    // 状态接口也要能答上来：占用、级别、锚点数。
    final status = await LogTools.status()
        .timeout(const Duration(seconds: 20));
    expect(status['initialized'], true);
    expect(status['bytes'], greaterThan(0));
    expect(status['anchors'], greaterThan(0),
        reason: '锚点账本应有本次运行记录到的节点');
  }, timeout: budget);

  testWidgets('预览最近日志能读到刚写的锚点', (tester) async {
    // 复用第一个用例已经起来的 App，不再跑一遍 main()。
    await tester.pump(const Duration(milliseconds: 500));

    UniLog.enter(UniLogTags.app, 'preview/verify');
    await UniLog.flush();

    final preview = await LogTools.preview(lines: 80)
        .timeout(const Duration(seconds: 20));
    expect(preview, isNot(contains('(暂无日志)')));
    expect(preview, contains('preview/verify'));
  }, timeout: budget);

  testWidgets('清空日志会把落盘文件清掉', (tester) async {
    await tester.pump(const Duration(milliseconds: 300));

    // 先保证盘上有东西。
    UniLog.i(UniLogTags.app, '清空前写入');
    await UniLog.flush();
    final before = await LogTools.status().timeout(const Duration(seconds: 20));
    expect(before['bytes'], greaterThan(0));

    final message = await LogTools.clear().timeout(const Duration(seconds: 30));
    expect(message, isNotEmpty);

    // 桌面自己还在不停打日志（车辆轮询、锚点），所以不能断言「恰好是 0」——
    // 那样会随机挂。要断言的是**清空确实把累积抹掉了**：
    // 清之前攒了几十 KB、几十个锚点，清之后只剩清空后新产生的那么一点。
    final after = await LogTools.status().timeout(const Duration(seconds: 20));
    expect(after['bytes'], lessThan((before['bytes'] as num).toInt()),
        reason: '清空后占用应变小，清空前 ${before['bytes']}，清空后 ${after['bytes']}');
    // 锚点账本也要一起清，否则诊断包里的计数会和日志文件对不上。
    expect(after['anchors'], lessThan((before['anchors'] as num).toInt()),
        reason: '清空日志应同时清掉锚点账本');
  }, timeout: budget);

  testWidgets('导出并分享也回结构化结果', (tester) async {
    await tester.pump(const Duration(milliseconds: 300));

    // 原生侧分享和导出是同一件事，只是多弹一个面板：
    // 两条路必须回同一份结构化结果，否则界面会把成功显示成失败。
    final result = await LogTools.exportAndShare()
        .timeout(const Duration(seconds: 90));
    expect(result.ok, true, reason: '导出并分享失败：${result.reason}');
    expect(result.path, contains('uni-logs-'));
    expect(result.bytes, greaterThan(0));
  }, timeout: budget);

  testWidgets('公共目录里最多保留三份诊断包', (tester) async {
    await tester.pump(const Duration(milliseconds: 300));

    // 连导四份：保留策略必须把最早的一份挤掉，且不能误删别人的文件。
    for (var i = 0; i < 4; i++) {
      UniLog.i(UniLogTags.app, '第 $i 份');
      await UniLog.flush();
      final result = await LogTools.export()
          .timeout(const Duration(seconds: 90));
      expect(result.ok, true, reason: '第 $i 份导出失败：${result.reason}');
      // 名字里的时间戳是秒级，四份连着导可能撞名，等一下再导下一份。
      await tester.pump(const Duration(seconds: 1));
    }
    debugPrint('UNI_DIAG_EXPORT prune-check done');
  }, timeout: budget);
}
