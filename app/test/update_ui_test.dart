import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uni_launcher/model/appearance.dart';
import 'package:uni_launcher/ota/update_controller.dart';
import 'package:uni_launcher/ota/update_ui.dart';
import 'package:uni_launcher/theme/launcher_theme.dart';

void main() {
  testWidgets(
      'about shows bundled contributors and update dialog distinguishes versions',
      (t) async {
    final u = UpdateController();
    u.info = {'versionName': '0.6.19', 'versionCode': 2033, 'sdk': 28};
    u.state = 'found';
    u.release = {
      'version_name': '0.6.20',
      'notes': '更新说明',
      'artifact': {'size_bytes': 1024}
    };
    final style = SurfaceStyle.from(
        const Appearance(
            mode: 'dark', palette: 'blue', themeStyle: 'blueGlass', radius: 0),
        true);
    await t.pumpWidget(MaterialApp(
        theme: launcherTheme(style),
        home: Scaffold(
            body: Builder(
                builder: (c) => Column(children: [
                      TextButton(
                          onPressed: () => showUpdateDialog(c, u),
                          child: const Text('打开')),
                      Expanded(child: AboutPanel(update: u))
                    ])))));
    expect(find.text('卢AI玩'), findsOneWidget);
    expect(find.text('Felix'), findsOneWidget);
    expect(find.text('十一'), findsOneWidget);
    expect(find.text('ChainStrong'), findsOneWidget);
    await t.tap(find.text('打开'));
    await t.pumpAndSettle();
    expect(find.text('当前  0.6.19'), findsOneWidget);
    expect(find.text('新版本  0.6.20'), findsOneWidget);
    expect(find.textContaining('下载更新'), findsOneWidget);
    await t.pumpWidget(const SizedBox.shrink());
    u.dispose();
  });
}
