import 'package:flutter/material.dart';
import '../controller/launcher_controller.dart';
import '../theme/design_tokens.dart';
import '../theme/launcher_theme.dart';
import 'glass_surface.dart';
import 'launcher_dialog.dart';
import 'uni_icon.dart';

Future<void> showAccountDetails(
    BuildContext context, LauncherController controller) async {
  await showLauncherSheet<void>(context,
      title: '账号详情',
      subtitle: '领克账号与登录状态',
      closeLabel: '关闭账号详情',
      width: Design.px(980),
      height: Design.px(650),
      builder: (_) => ValueListenableBuilder<Map<String, dynamic>>(
          valueListenable: controller.native,
          builder: (context, native, __) {
            final system = _mapOf(native['systemStatus']);
            return AccountDetailsContent(
                account: _mapOf(system['account']),
                demo: native['demo'] == true,
                onOpenCenter: () async {
                  Navigator.pop(context);
                  await controller.command('official-widget', value: 'member');
                });
          }));
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

  bool get _known => demo || account['known'] == true;
  bool get _loggedIn => demo || account['loggedIn'] == true;
  String get _name => demo
      ? '演示账号'
      : _loggedIn
          ? _text(account['name'], '领克账号')
          : '领克账号';

  String get _status => !_known
      ? '—'
      : _loggedIn
          ? '已登录'
          : '未登录';

  String get _source => switch (account['source']) {
        'member-provider' => '原车会员中心',
        'user-api' => '原车用户服务',
        _ => '原车用户服务',
      };

  String get _level {
    final name = _text(account['memberLevelName'], '');
    if (name.isNotEmpty) return name;
    final level = (account['memberLevel'] as num?)?.toInt();
    return level != null && level > 0 ? 'Lv. $level' : '';
  }

  @override
  Widget build(BuildContext context) {
    final s = SurfaceStyle.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Expanded(
          child: GlassSurface(
              key: const ValueKey('account-profile-detail'),
              tone: SurfaceTone.soft,
              shadow: false,
              padding: EdgeInsets.all(Design.px(32)),
              child: Row(children: [
                AccountAvatar(account: account, size: Design.px(176)),
                SizedBox(width: Design.px(36)),
                Expanded(
                    child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Text(_name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: Design.px(38),
                              height: 1.15,
                              fontWeight: FontWeight.w500)),
                      SizedBox(height: Design.px(16)),
                      _AccountStatusChip(
                          label: _status, active: _known && _loggedIn),
                      SizedBox(height: Design.px(30)),
                      _AccountInfoRow(label: '账号名称', value: _name),
                      SizedBox(height: Design.px(15)),
                      _AccountInfoRow(label: '登录状态', value: _status),
                      if (_level.isNotEmpty) ...[
                        SizedBox(height: Design.px(15)),
                        _AccountInfoRow(label: '会员等级', value: _level),
                      ],
                      SizedBox(height: Design.px(15)),
                      _AccountInfoRow(
                          label: '信息来源', value: demo ? '演示数据' : _source),
                    ]))
              ]))),
      SizedBox(height: Design.px(24)),
      Row(children: [
        Expanded(
            child: Text(
                !_known
                    ? '账号服务暂未返回状态，可进入账号中心查看或登录。'
                    : _loggedIn
                        ? '账号状态由原车账号服务同步。'
                        : '当前未登录，进入账号中心可完成登录。',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: Design.px(18), color: s.muted))),
        SizedBox(width: Design.px(30)),
        FilledButton.icon(
            key: const ValueKey('account-open-center'),
            onPressed: demo ? null : onOpenCenter,
            icon: const Icon(Icons.open_in_new),
            label: Text(_loggedIn ? '进入账号中心' : '登录账号'))
      ])
    ]);
  }
}

class AccountAvatar extends StatelessWidget {
  final Map<String, dynamic> account;
  final double size;
  const AccountAvatar({super.key, required this.account, required this.size});

  @override
  Widget build(BuildContext context) {
    final s = SurfaceStyle.of(context);
    final value = _text(account['avatarUrl'], '');
    final uri = Uri.tryParse(value);
    final networkAvatar = uri != null &&
        (uri.scheme == 'https' || uri.scheme == 'http') &&
        uri.host.isNotEmpty;
    final fallback =
        Center(child: UniIcon('user', size: size * .5, color: s.accent));
    return Container(
        width: size,
        height: size,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: s.accent.withValues(alpha: .12),
            border: Border.all(
                color: s.accent.withValues(alpha: .38), width: Design.px(2))),
        child: networkAvatar
            ? Image.network(value,
                fit: BoxFit.cover,
                filterQuality: FilterQuality.medium,
                errorBuilder: (_, __, ___) => fallback)
            : fallback);
  }
}

class _AccountStatusChip extends StatelessWidget {
  final String label;
  final bool active;
  const _AccountStatusChip({required this.label, required this.active});
  @override
  Widget build(BuildContext context) {
    final s = SurfaceStyle.of(context);
    return Container(
        padding: EdgeInsets.symmetric(
            horizontal: Design.px(15), vertical: Design.px(8)),
        decoration: BoxDecoration(
            color: active
                ? s.accent.withValues(alpha: .15)
                : s.text.withValues(alpha: .06),
            borderRadius: BorderRadius.circular(s.controlRadius),
            border: Border.all(
                color: active ? s.accent.withValues(alpha: .45) : s.edge)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Container(
              width: Design.px(8),
              height: Design.px(8),
              decoration: BoxDecoration(
                  shape: BoxShape.circle, color: active ? s.accent : s.muted)),
          SizedBox(width: Design.px(9)),
          Text(label,
              style: TextStyle(
                  color: active ? s.accent : s.muted, fontSize: Design.px(18)))
        ]));
  }
}

class _AccountInfoRow extends StatelessWidget {
  final String label, value;
  const _AccountInfoRow({required this.label, required this.value});
  @override
  Widget build(BuildContext context) {
    final s = SurfaceStyle.of(context);
    return Row(children: [
      SizedBox(
          width: Design.px(110),
          child: Text(label,
              style: TextStyle(fontSize: Design.px(18), color: s.muted))),
      Expanded(
          child: Text(value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: Design.px(20))))
    ]);
  }
}

Map<String, dynamic> _mapOf(dynamic value) =>
    value is Map ? Map<String, dynamic>.from(value) : {};

String _text(dynamic value, String fallback) {
  final text = '${value ?? ''}'.trim();
  return text.isEmpty ? fallback : text;
}
