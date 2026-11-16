import 'package:flutter/material.dart';
import '../controller/launcher_controller.dart';
import '../theme/design_tokens.dart';
import '../theme/launcher_theme.dart';
import 'launcher_dialog.dart';

/// 账号详情弹层（稿子 `#f25`）。
///
/// 稿子 817×542（1600 画布）= 源码 px 980×650（×5/6 那套换算），内边距 32/36。
/// 版式：头像行（圆角方块头像 + 姓名 + 徽章）→ 键值行（52 高、细线分隔）→
/// 底部「账号状态由原车账号服务同步」+ 进入账号中心。
Future<void> showAccountDetails(
    BuildContext context, LauncherController controller) async {
  await showLauncherSheet<void>(context,
      title: '账号详情',
      subtitle: '领克账号与登录状态',
      closeLabel: '关闭账号详情',
      width: Design.px(980),
      height: Design.px(650),
      padding: EdgeInsets.symmetric(
          horizontal: Design.px(43), vertical: Design.px(38)),
      glowType: 'member',
      builder: (_) => ValueListenableBuilder<Map<String, dynamic>>(
          valueListenable: controller.native,
          builder: (context, native, __) {
            final system = _mapOf(native['systemStatus']);
            return AccountDetailsContent(
                key: const ValueKey('account-profile-detail'),
                account: _mapOf(system['account']),
                demo: native['demo'] == true,
                onOpenCenter: () async {
                  Navigator.pop(context);
                  await controller.command('official-widget', value: 'member');
                });
          }));
}

/// 账号字段的**唯一**解释处：桌面卡片（`card_content_oem.dart`）与详情弹层都从
/// 这里取，免得两处对「已登录 / 会员等级 / 信息来源」给出不同口径。
///
/// 只翻译原生确实给到的字段（`known` / `loggedIn` / `name` / `memberLevel` /
/// `memberLevelName` / `avatarUrl` / `source`）。稿子里的「车主认证」徽章与
/// 「账号类型 · 领克汽车账号」在 `SystemStatusAdapter` 的账号快照里没有对应字段，
/// 按 2026-11-14 的口径**不显示**，不编。
class AccountSummary {
  final Map<String, dynamic> account;
  final bool demo;
  const AccountSummary(this.account, this.demo);

  bool get known => demo || account['known'] == true;
  bool get loggedIn => demo || account['loggedIn'] == true;

  String get name =>
      demo ? '演示账号' : (loggedIn ? _text(account['name'], '领克账号') : '领克账号');

  String get status => !known ? '—' : (loggedIn ? '已登录' : '未登录');

  String get level {
    final levelName = _text(account['memberLevelName'], '');
    if (levelName.isNotEmpty) return levelName;
    final value = (account['memberLevel'] as num?)?.toInt() ?? 0;
    return value > 0 ? 'Lv. $value' : '';
  }

  String get source => demo
      ? '演示数据'
      : switch (account['source']) {
          'member-provider' => '原车会员中心',
          'user-api' => '原车用户服务',
          _ => '原车用户服务',
        };
}

class AccountDetailsContent extends StatelessWidget {
  final Map<String, dynamic> account;
  final bool demo;
  final VoidCallback onOpenCenter;
  const AccountDetailsContent(
      {super.key,
      required this.account,
      required this.demo,
      required this.onOpenCenter});

  @override
  Widget build(BuildContext context) {
    final s = SurfaceStyle.of(context);
    final a = AccountSummary(account, demo);
    final rows = <(String, String)>[
      ('账号名称', a.name),
      ('登录状态', a.status),
      if (a.level.isNotEmpty) ('会员等级', a.level),
      ('信息来源', a.source),
    ];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        AccountAvatar(account: account, name: a.name, size: Design.px(127)),
        SizedBox(width: Design.px(29)),
        Expanded(
            child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
              Text(a.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: Design.px(36),
                      height: 1.15,
                      fontWeight: FontWeight.w500)),
              SizedBox(height: Design.px(16)),
              if (a.known)
                Row(children: [
                  AccountStatusChip(label: a.status, active: a.loggedIn)
                ]),
            ])),
      ]),
      SizedBox(height: Design.px(18)),
      for (final row in rows)
        AccountInfoRow(
            label: row.$1,
            value: row.$2,
            height: Design.px(58),
            divider: row != rows.last),
      const Spacer(),
      SizedBox(height: Design.px(12)),
      Row(children: [
        Expanded(
            child: Text(
                !a.known
                    ? '账号服务暂未返回状态，可进入账号中心查看或登录。'
                    : a.loggedIn
                        ? '账号状态由原车账号服务同步。'
                        : '当前未登录，进入账号中心可完成登录。',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: Design.px(15), color: s.muted))),
        SizedBox(width: Design.px(24)),
        SizedBox(
            height: Design.px(65),
            child: FilledButton.icon(
                key: const ValueKey('account-open-center'),
                onPressed: demo ? null : onOpenCenter,
                style: FilledButton.styleFrom(
                    padding: EdgeInsets.symmetric(horizontal: Design.px(41)),
                    textStyle: TextStyle(fontSize: Design.px(19))),
                icon: Icon(Icons.open_in_new, size: Design.px(21)),
                label: Text(a.loggedIn ? '进入账号中心' : '登录账号')))
      ])
    ]);
  }
}

/// 稿子 `#f24` / `#f25` 的账号头像：**圆角方块**（不是圆形），一层主题色渐变
/// + 左上高光，读不到 `avatarUrl` 时用姓名首字兜底。
///
/// 颜色全走 `s.accent` / `s.accentText`：三套皮肤、五种明暗态自动跟随，换配色
/// （青屿 / 琥珀 / 玫瑰）头像同步换色 —— 不必为每套皮肤再维护一组头像色值。
class AccountAvatar extends StatelessWidget {
  final Map<String, dynamic> account;
  final double size;

  /// 用来取首字的名字；不传就退回 `account['name']`。
  final String? name;
  const AccountAvatar(
      {super.key, required this.account, required this.size, this.name});

  @override
  Widget build(BuildContext context) {
    final s = SurfaceStyle.of(context);
    final value = _text(account['avatarUrl'], '');
    final uri = Uri.tryParse(value);
    final networkAvatar = uri != null &&
        (uri.scheme == 'https' || uri.scheme == 'http') &&
        uri.host.isNotEmpty;
    final radius = BorderRadius.circular(size * .26);
    final fallback = DecoratedBox(
        decoration: BoxDecoration(
            borderRadius: radius,
            gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color.lerp(s.accent, Colors.white, s.dark ? .26 : .18)!,
                  s.accent
                ]),
            // 稿子：同色外发光 + 1px 描边。发光在浅色皮肤上收一半，否则白卡上
            // 会糊出一团光。
            boxShadow: [
              BoxShadow(
                  color: s.accent.withValues(alpha: s.dark ? .42 : .22),
                  offset: Offset(0, size * .14),
                  blurRadius: size * .34,
                  spreadRadius: -size * .08),
            ]),
        child: Stack(fit: StackFit.expand, children: [
          // 左上高光（稿子 `radial-gradient(120% 120% at 24% 14%, …)`）。
          DecoratedBox(
              decoration: BoxDecoration(
                  borderRadius: radius,
                  gradient: RadialGradient(
                      center: const Alignment(-.52, -.72),
                      radius: .95,
                      colors: [
                        Colors.white.withValues(alpha: .30),
                        Colors.white.withValues(alpha: 0)
                      ],
                      stops: const [0, .48]))),
          Center(
              child: Text(_initial(name ?? _text(account['name'], '')),
                  style: TextStyle(
                      fontSize: size * .4,
                      fontWeight: FontWeight.w300,
                      color: s.accentText)))
        ]));
    return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
            borderRadius: radius,
            border: Border.all(
                color: s.text.withValues(alpha: .14),
                width: Design.px(1.4) * .9)),
        clipBehavior: Clip.antiAlias,
        child: networkAvatar
            ? Image.network(value,
                fit: BoxFit.cover,
                filterQuality: FilterQuality.medium,
                errorBuilder: (_, __, ___) => fallback)
            : fallback);
  }
}

/// 稿子 `.acc-chip`：高 30、圆角 10、描边 + 12.5 号字；选中态是主题色描边 +
/// 主题色底 + 一颗发光圆点。
class AccountStatusChip extends StatelessWidget {
  final String label;
  final bool active;
  const AccountStatusChip(
      {super.key, required this.label, required this.active});
  @override
  Widget build(BuildContext context) {
    final s = SurfaceStyle.of(context);
    return Container(
        height: Design.px(36),
        padding: EdgeInsets.symmetric(horizontal: Design.px(15)),
        decoration: BoxDecoration(
            color: active
                ? s.accent.withValues(alpha: .11)
                : s.text.withValues(alpha: .055),
            borderRadius: BorderRadius.circular(Design.px(12)),
            border: Border.all(
                color: active
                    ? s.accent.withValues(alpha: .42)
                    : s.text.withValues(alpha: .16))),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Container(
              width: Design.px(7),
              height: Design.px(7),
              decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: active ? s.accent : s.muted,
                  boxShadow: active
                      ? [
                          BoxShadow(
                              color: s.accent.withValues(alpha: .75),
                              blurRadius: Design.px(9))
                        ]
                      : null)),
          SizedBox(width: Design.px(9)),
          Text(label,
              style: TextStyle(
                  fontSize: Design.px(15),
                  color: active ? s.accent : s.muted))
        ]));
  }
}

/// 稿子 `.kv .r`：左标签（13.5 号、次要色）、右值（15 号、92% 墨色），行间一条
/// 5.5% 墨色细线。卡片与详情弹层共用这一个组件，行高由 [height] 给。
class AccountInfoRow extends StatelessWidget {
  final String label, value;
  final double? height;
  final bool divider;
  const AccountInfoRow(
      {super.key,
      required this.label,
      required this.value,
      this.height,
      this.divider = true});
  @override
  Widget build(BuildContext context) {
    final s = SurfaceStyle.of(context);
    return Container(
        height: height,
        alignment: Alignment.center,
        decoration: divider
            ? BoxDecoration(
                border: Border(
                    bottom: BorderSide(
                        color: s.text.withValues(alpha: .055),
                        width: Design.px(1.4) * .9)))
            : null,
        child: Row(children: [
          Text(label,
              style: TextStyle(fontSize: Design.px(16), color: s.muted)),
          const Spacer(),
          Flexible(
              child: Text(value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.right,
                  style: TextStyle(
                      fontSize: Design.px(18),
                      color: s.text.withValues(alpha: .92))))
        ]));
  }
}

/// 姓名首字；空串退回 `L`（稿子里那颗字就是账号标识的首字母）。
String _initial(String name) {
  final trimmed = name.trim();
  if (trimmed.isEmpty) return 'L';
  return String.fromCharCode(trimmed.runes.first).toUpperCase();
}

Map<String, dynamic> _mapOf(dynamic value) =>
    value is Map ? Map<String, dynamic>.from(value) : {};

String _text(dynamic value, String fallback) {
  final text = '${value ?? ''}'.trim();
  return text.isEmpty ? fallback : text;
}
