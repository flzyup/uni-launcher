import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uni_launcher/controller/launcher_controller.dart';
import 'package:uni_launcher/model/appearance.dart';
import 'package:uni_launcher/model/card_layout.dart';
import 'package:uni_launcher/theme/design_tokens.dart';
import 'package:uni_launcher/theme/launcher_theme.dart';
import 'package:uni_launcher/widgets/account_details_sheet.dart';
import 'package:uni_launcher/widgets/card_content.dart';
import 'package:uni_launcher/widgets/glass_surface.dart';
import 'fake_gateway.dart';

/// 账号卡（稿子 `#f24` 4×6）与账号详情（`#f25`）。
///
/// 口径（用户 2026-11-14）：版式按稿子，颜色跟其他卡片/弹窗一样走主题；
/// **稿子上源码读不到的信息不画**——「账号类型 · 领克汽车账号」与「车主认证」
/// 在 `SystemStatusAdapter` 的账号快照里没有字段，这里断言它们不会出现。
void main() {
  Map<String, dynamic> accountPayload({
    bool known = true,
    bool loggedIn = true,
    String? name = 'LYNK 车主',
    String? levelName = '银卡会员',
    num? level,
    String source = 'member-provider',
    String? avatarUrl,
  }) =>
      {
        'known': known,
        'loggedIn': loggedIn,
        if (name != null) 'name': name,
        if (levelName != null) 'memberLevelName': levelName,
        if (level != null) 'memberLevel': level,
        'source': source,
        if (avatarUrl != null) 'avatarUrl': avatarUrl,
      };

  Future<(LauncherController, FakeGateway)> boot(
      Map<String, dynamic> account) async {
    final g = FakeGateway()
      ..state['demo'] = false
      ..state['systemStatus'] = {'account': account};
    final c = LauncherController(g);
    await c.initialize();
    return (c, g);
  }

  Future<void> pumpCard(
      WidgetTester t, LauncherController c, Appearance look,
      {Size size = const Size(1920, 1080)}) async {
    t.view.physicalSize = size;
    t.view.devicePixelRatio = 1;
    final s = SurfaceStyle.from(look, look.mode != 'light');
    await t.pumpWidget(MaterialApp(
        theme: launcherTheme(s),
        home: Scaffold(
            backgroundColor: s.background,
            body: Center(
                child: SizedBox(
                    width: Design.px(602),
                    height: Design.px(880),
                    child: GlassSurface(
                        card: true,
                        padding: EdgeInsets.zero,
                        child: CardContent(
                            card: const LauncherCard(
                                'acc', 'member', '账号', 0, 0, 4, 6, 0),
                            controller: c)))))));
    await t.pumpAndSettle();
  }

  testWidgets('卡片只画原生给到的字段：4 行键值 + 状态徽章 + 主按钮', (t) async {
    final (c, g) = await boot(accountPayload());
    await pumpCard(t, c, const Appearance(mode: 'dark', themeStyle: 'nocturne'));
    for (final label in ['账号名称', '会员等级', '登录状态', '信息来源']) {
      expect(find.text(label), findsOneWidget, reason: label);
    }
    expect(find.text('原车会员中心'), findsOneWidget);
    expect(find.text('进入账号中心'), findsOneWidget);
    expect(find.text('已登录'), findsNWidgets(2)); // 徽章 + 登录状态行
    // 稿子里这两项没有数据来源，不该被画出来。
    expect(find.text('车主认证'), findsNothing);
    expect(find.text('账号类型'), findsNothing);
    expect(find.text('领克汽车账号'), findsNothing);
    expect(t.takeException(), isNull);
    c.dispose();
    await g.dispose();
    t.view.resetPhysicalSize();
    t.view.resetDevicePixelRatio();
  });

  testWidgets('没有会员等级 / 未登录时，对应行与徽章跟着数据走', (t) async {
    final (c, g) = await boot(accountPayload(
        loggedIn: false, levelName: null, level: null, name: '领克账号'));
    await pumpCard(t, c, const Appearance(mode: 'dark', themeStyle: 'nocturne'));
    expect(find.text('会员等级'), findsNothing);
    expect(find.text('未登录'), findsNWidgets(2)); // 徽章 + 登录状态行
    expect(find.text('已登录'), findsNothing);
    expect(t.takeException(), isNull);
    c.dispose();
    await g.dispose();
    t.view.resetPhysicalSize();
    t.view.resetDevicePixelRatio();
  });

  testWidgets('读不到封面时头像用姓名首字兜底', (t) async {
    final (c, g) = await boot(accountPayload(name: 'LYNK 车主'));
    await pumpCard(t, c, const Appearance(mode: 'dark', themeStyle: 'nocturne'));
    expect(find.text('L'), findsOneWidget);
    final avatar = t.widget<AccountAvatar>(find.byType(AccountAvatar));
    expect(avatar.size, Design.px(144));
    c.dispose();
    await g.dispose();
    t.view.resetPhysicalSize();
    t.view.resetDevicePixelRatio();
  });

  testWidgets('三套皮肤都排得下，不溢出', (t) async {
    for (final look in const [
      Appearance(mode: 'dark', themeStyle: 'nocturne'),
      Appearance(mode: 'light', themeStyle: 'classic'),
      Appearance(mode: 'dark', themeStyle: 'classic'),
      Appearance(mode: 'dark', themeStyle: 'blueGlass'),
    ]) {
      final (c, g) = await boot(accountPayload());
      await pumpCard(t, c, look);
      expect(t.takeException(), isNull, reason: look.themeStyle);
      c.dispose();
      await g.dispose();
    }
    t.view.resetPhysicalSize();
    t.view.resetDevicePixelRatio();
  });

  testWidgets('详情弹层按稿子排：头像行 + 键值行 + 底部主按钮', (t) async {
    t.view.physicalSize = const Size(1600, 900);
    t.view.devicePixelRatio = 1;
    final (c, g) = await boot(accountPayload());
    final s = SurfaceStyle.from(const Appearance(mode: 'dark', themeStyle: 'nocturne'), true);
    await t.pumpWidget(MaterialApp(
        theme: launcherTheme(s),
        home: Scaffold(
            backgroundColor: s.background,
            body: Builder(builder: (ctx) {
              WidgetsBinding.instance
                  .addPostFrameCallback((_) => showAccountDetails(ctx, c));
              return const SizedBox.expand();
            }))));
    await t.pumpAndSettle();
    final sheet = find.byKey(const ValueKey('account-profile-detail'));
    expect(sheet, findsOneWidget);
    expect(find.descendant(of: sheet, matching: find.text('账号名称')),
        findsOneWidget);
    expect(
        find.descendant(of: sheet, matching: find.text('账号状态由原车账号服务同步。')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('account-open-center')), findsOneWidget);
    expect(find.text('车主认证'), findsNothing);
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox.shrink());
    c.dispose();
    await g.dispose();
    t.view.resetPhysicalSize();
    t.view.resetDevicePixelRatio();
  });
}
