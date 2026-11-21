import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../controller/launcher_controller.dart';
import '../theme/design_tokens.dart';
import '../theme/launcher_theme.dart';
import 'canvas_scope.dart';
import 'choice_button.dart';
import 'glass_surface.dart';
import 'quark_panel.dart';
import 'dock_window_scope.dart';

/// 设计稿 `#f30`（`theme-styles/eclipse/simulator.html`）里的轻浮层：
/// 贴在底栏右上方的 533.33×716.67 面板（源 640×860 ×5/6），圆角 22.5，
/// 内边距 20·20·15；右侧带一层渐变遮罩而不是整屏压暗。
Future<void> showFileTransferPopup(
    BuildContext context, LauncherController c) async {
  if (await c.presentGlobalPanel('transfer') || !context.mounted) return;
  final scope = DockWindowScope.of(context);
  final closed = Navigator.of(context).push(_TransferRoute(c));
  if (scope?.onPresented != null) {
    await WidgetsBinding.instance.endOfFrame;
    if (context.mounted) await scope!.onPresented!();
  }
  await closed;
}

class _TransferRoute extends PopupRoute<void> {
  final LauncherController launcherController;
  _TransferRoute(this.launcherController);
  @override
  Color? get barrierColor => null;
  @override
  bool get barrierDismissible => true;
  @override
  String get barrierLabel => '关闭传文件';
  @override
  Duration get transitionDuration => const Duration(milliseconds: 180);
  @override
  Widget buildPage(BuildContext context, Animation<double> animation,
      Animation<double> secondaryAnimation) {
    final panel = launcherController.native.value['hostMode'] == 'global-panel';
    // 浮层挂在 root overlay 上，不吃桌面那层 FittedBox；先归到 1600 画布坐标系，
    // 否则在「逻辑宽度 ≠ 1600」的屏上会按 1:1 像素落地、顶部被切掉。
    return CanvasScope(child: Builder(builder: (context) {
      final canvas = CanvasScopeInfo.of(context);
      final s = SurfaceStyle.of(context);
      final bottom = Design.dz(panel ? 14 : 91.67);
      // 稿子 716.67 高是给 900 高画布的；画布更矮（超宽屏 / 小窗）时按可用高度
      // 收，内容本身有 Expanded 与 ListView，收矮了也只是滚动，不会被裁。
      final height = math.min(Design.dz(716.67),
          math.max(Design.dz(240), canvas.height - bottom - Design.dz(12)));
      final width = math.min(Design.dz(533.33), canvas.width - Design.dz(24));
      return Stack(children: [
        // 稿子只给右半边压一层渐隐，左半边保持桌面亮度。
        //
        // 这层原来写死成近黑（0x75020304），浅色暗夜下右侧会被糊成一块黑。
        // 深色保持原值；浅色换成同形状的白雾，作用一样（把桌面的细节压下去
        // 让面板浮出来），但不会带进任何黑色。
        Positioned.fill(
            child: IgnorePointer(
                child: DecoratedBox(
                    decoration: BoxDecoration(
                        gradient: LinearGradient(
                            begin: Alignment.centerLeft,
                            end: Alignment.centerRight,
                            colors: s.dark
                                ? const [
                                    Color(0x00020304),
                                    Color(0x00020304),
                                    Color(0x75020304)
                                  ]
                                : const [
                                    Color(0x00FFFFFF),
                                    Color(0x00FFFFFF),
                                    Color(0x8CFFFFFF)
                                  ],
                            stops: const [
              0,
              .38,
              1
            ]))))),
        Positioned(
            right: Design.dz(11.67),
            bottom: bottom,
            child: SizedBox(
                width: width,
                height: height,
                child: GlassSurface(
                    key: const ValueKey('transfer-popup'),
                    sheet: true,
                    // 不写死圆角：跟其它弹层一样吃「卡片圆角」设置（默认 25），
                    // 否则用户调圆角时只有这个窗口四个角不动。
                    padding: EdgeInsets.fromLTRB(Design.dz(20), Design.dz(20),
                        Design.dz(20), Design.dz(15)),
                    child: _TransferPanel(controller: launcherController))))
      ]);
    }));
  }

  @override
  Widget buildTransitions(BuildContext context, Animation<double> animation,
          Animation<double> secondaryAnimation, Widget child) =>
      FadeTransition(opacity: animation, child: child);
}

class _TransferPanel extends StatefulWidget {
  final LauncherController controller;
  const _TransferPanel({required this.controller});

  @override
  State<_TransferPanel> createState() => _TransferPanelState();
}

class _TransferPanelState extends State<_TransferPanel> {
  /// 0 = 手机上传（默认，保持旧行为），1 = 夸克网盘。
  int _tab = 0;

  /// 刚复制过的那条文本 id；1.6 秒后回到「复制」，给一个不需要弹窗的反馈。
  String? _copiedId;
  Timer? _copiedTimer;

  LauncherController get controller => widget.controller;

  @override
  void dispose() {
    _copiedTimer?.cancel();
    super.dispose();
  }

  /// 车机上点一下就进系统剪贴板，用户可以粘到导航搜索、聊天或别处。
  void _copyText(String id, String text) {
    Clipboard.setData(ClipboardData(text: text));
    _copiedTimer?.cancel();
    setState(() => _copiedId = id);
    _copiedTimer = Timer(const Duration(milliseconds: 1600), () {
      if (!mounted) return;
      setState(() => _copiedId = null);
    });
  }

  /// 待下载任务的状态文案；失败时带原因，避免只看到一个红字。
  static String _linkStatus(Map link) {
    final status = '${link['status'] ?? 'queued'}';
    final error = '${link['error'] ?? ''}'.trim();
    return switch (status) {
      'downloading' => '下载中…',
      'failed' => error.isEmpty ? '下载失败' : '失败：$error',
      _ => '待下载',
    };
  }

  /// `.ft-src`：10.5px、圆角 5.5、最大 118 宽的小标签。
  Widget _sourceTag(String label, SurfaceStyle s) => ConstrainedBox(
      constraints: BoxConstraints(maxWidth: Design.dz(118)),
      child: Container(
          padding: EdgeInsets.symmetric(
              horizontal: Design.dz(7), vertical: Design.dz(2)),
          decoration: BoxDecoration(
              border: Border.all(color: s.text.withValues(alpha: .13)),
              borderRadius: BorderRadius.circular(Design.dz(5.5))),
          child: Text(label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              softWrap: false,
              style: TextStyle(fontSize: Design.dz(10.5), color: s.muted))));

  /// `.ft-b`：13px 纯文字按钮，没有底和描边；dim 版本是删除。
  ///
  /// 视觉上是纯文字，但仍用 [TextButton]：读屏能念出按钮角色，禁用态也有
  /// `onPressed == null` 这个明确的语义（测试与无障碍都靠它）。
  Widget _button(String label, VoidCallback? onTap, {bool dim = false}) {
    final s = SurfaceStyle.of(context);
    final color = dim
        ? s.text.withValues(alpha: enabledAlpha(onTap, .42))
        : s.accent.withValues(alpha: enabledAlpha(onTap, .85));
    return TextButton(
        onPressed: onTap,
        style: TextButton.styleFrom(
            minimumSize: Size.zero,
            padding: EdgeInsets.symmetric(
                horizontal: Design.dz(5), vertical: Design.dz(4)),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            foregroundColor: color,
            disabledForegroundColor: color),
        child: Text(label,
            style: TextStyle(
                fontSize: Design.dz(13), letterSpacing: Design.dz(.26))));
  }

  static double enabledAlpha(VoidCallback? onTap, double alpha) =>
      onTap == null ? alpha * .5 : alpha;

  /// `.ft-row`：来源标签 + 名称/副标题 + 右侧两个文字按钮。
  Widget _row(SurfaceStyle s,
          {Key? key,
          required String source,
          required String title,
          String? note,
          List<Widget> actions = const []}) =>
      Padding(
          key: key,
          padding: EdgeInsets.symmetric(vertical: Design.dz(5.5)),
          child: Row(children: [
            _sourceTag(source, s),
            SizedBox(width: Design.dz(8)),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: Design.dz(14),
                          color: s.text.withValues(alpha: .88))),
                  if (note != null && note.isNotEmpty) ...[
                    SizedBox(height: Design.dz(2)),
                    Text(note,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style:
                            TextStyle(fontSize: Design.dz(11), color: s.muted)),
                  ],
                ])),
            ...actions,
          ]));

  Widget _linkRow(SurfaceStyle s, Map link) {
    final id = '${link['id'] ?? ''}';
    final host = '${link['host'] ?? ''}';
    final status = '${link['status'] ?? 'queued'}';
    final busy = status == 'downloading';
    final name = '${link['name'] ?? ''}'.trim();
    return _row(s,
        key: ValueKey('transfer-link-$id'),
        source: host,
        title: name.isEmpty ? host : name,
        note: _linkStatus(link),
        actions: [
          // 手机只能入队；真正开始下载必须由车机点这一下触发。
          _button(
              busy ? '下载中' : '下载',
              busy
                  ? null
                  : () =>
                      controller.command('transfer-link-download', value: id)),
          _button(
              '删除', () => controller.command('transfer-link-remove', value: id),
              dim: true),
        ]);
  }

  /// `.ft-tx`：手机发来的一条文本，整块可点（复制），右侧还有复制/删除。
  Widget _textRow(SurfaceStyle s, Map note) {
    final id = '${note['id'] ?? ''}';
    final text = '${note['text'] ?? ''}';
    final copied = _copiedId == id;
    return Padding(
        key: ValueKey('transfer-text-$id'),
        padding: EdgeInsets.only(top: Design.dz(2), bottom: Design.dz(4)),
        child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _copyText(id, text),
            child: Container(
                padding: EdgeInsets.fromLTRB(
                    Design.dz(9), Design.dz(6), Design.dz(9), Design.dz(7)),
                decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(Design.dz(9)),
                    border: Border.all(
                        color: copied
                            ? s.accent.withValues(alpha: .5)
                            : s.text.withValues(alpha: .13))),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        _sourceTag('手机文本', s),
                        SizedBox(width: Design.dz(7)),
                        Expanded(
                            child: Text(copied ? '已复制 ✓' : '点击复制',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    fontSize: Design.dz(10.5),
                                    color: copied ? s.accent : s.muted))),
                        _button(
                            copied ? '已复制' : '复制', () => _copyText(id, text)),
                        _button(
                            '删除',
                            () => controller.command('transfer-text-remove',
                                value: id),
                            dim: true),
                      ]),
                      SizedBox(height: Design.dz(5)),
                      Text(text,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: Design.dz(13),
                              color: s.text.withValues(alpha: .84))),
                    ]))));
  }

  Widget _fileRow(SurfaceStyle s, Map file, String? host) {
    final name = '${file['name'] ?? ''}';
    return _row(s,
        key: ValueKey('transfer-file-$name'),
        source: (host == null || host.isEmpty) ? '手机上传' : host,
        title: name,
        actions: [
          _button(
              '安装', () => controller.command('transfer-install', value: name)),
          _button(
              '删除', () => controller.command('transfer-delete', value: name),
              dim: true),
        ]);
  }

  /// `.ft-tab`：32 高、圆角 8.33、15px；选中是强调色 13% 底 + 44% 描边。
  Widget _tabs(SurfaceStyle s) {
    Widget item(String label, int index, String keyName) {
      final active = _tab == index;
      return Expanded(
          child: GestureDetector(
              key: ValueKey(keyName),
              behavior: HitTestBehavior.opaque,
              onTap: () => setState(() => _tab = index),
              child: Container(
                  height: Design.dz(32),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                      color: active
                          ? s.accent.withValues(alpha: .13)
                          : s.text.withValues(alpha: .015),
                      border: Border.all(
                          color: active
                              ? s.accent.withValues(alpha: .44)
                              : s.text.withValues(alpha: .105)),
                      borderRadius: BorderRadius.circular(Design.dz(8.33))),
                  child: Text(label,
                      style: TextStyle(
                          fontSize: Design.dz(15),
                          fontWeight:
                              active ? FontWeight.w500 : FontWeight.w400,
                          color: active ? s.accent : s.muted)))));
    }

    return Padding(
        padding: EdgeInsets.only(top: Design.dz(11)),
        child: Row(children: [
          item('手机扫码', 0, 'transfer-tab-phone'),
          SizedBox(width: Design.dz(6.67)),
          item('夸克网盘', 1, 'transfer-tab-quark'),
        ]));
  }

  /// `.ft-sw`：50 高的一行开关，下沿一根 6% 分隔线。
  Widget _switchRow(SurfaceStyle s, bool running) => GestureDetector(
      key: const ValueKey('transfer-switch'),
      behavior: HitTestBehavior.opaque,
      onTap: () =>
          controller.command(running ? 'transfer-stop' : 'transfer-start'),
      child: Container(
          height: Design.dz(50),
          decoration: BoxDecoration(
              border: Border(
                  bottom: BorderSide(color: s.text.withValues(alpha: .06)))),
          child: Row(children: [
            Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('开启传文件',
                      style: TextStyle(
                          fontSize: Design.dz(15.5),
                          color: s.text.withValues(alpha: .88))),
                  SizedBox(height: Design.dz(3)),
                  Text(running ? '手机与车机连接同一网络' : '开启后扫码上传文件',
                      style: TextStyle(fontSize: Design.dz(12), color: s.muted))
                ]),
            const Spacer(),
            DesignSwitch(
                value: running,
                semanticLabel: '开启传文件',
                onChanged: (v) =>
                    controller.command(v ? 'transfer-start' : 'transfer-stop'))
          ])));

  Widget _closeButton(SurfaceStyle s) => Tooltip(
      message: '关闭传文件',
      child: Semantics(
          button: true,
          label: '关闭传文件',
          child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => Navigator.pop(context),
              child: Container(
                  width: Design.dz(36),
                  height: Design.dz(36),
                  decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: s.text.withValues(alpha: .06),
                      border: Border.all(color: s.text.withValues(alpha: .09))),
                  child: Center(
                      child: Icon(Icons.close,
                          size: Design.dz(15),
                          color: s.text.withValues(alpha: .70)))))));

  /// `.ft-qr`：204 见方的浅色码箱（内衬 8）→ 188 的码，下面地址与说明。
  Widget _qrBlock(SurfaceStyle s, String url) => Padding(
      padding: EdgeInsets.only(top: Design.dz(10), bottom: Design.dz(6)),
      child: Column(children: [
        Container(
            width: Design.dz(204),
            height: Design.dz(204),
            padding: EdgeInsets.all(Design.dz(8)),
            // 二维码底板固定白、模块固定近黑：扫码只认高对比，不能跟皮肤走。
            // 原来底板取 s.text —— 暗色下是白（正常），浅色下 s.text 是深墨色，
            // 底板和模块一起变黑，整块糊成一个黑方块。
            decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(Design.dz(9))),
            child: QrImageView(
                data: url,
                size: Design.dz(188),
                padding: EdgeInsets.zero,
                backgroundColor: Colors.transparent,
                eyeStyle: const QrEyeStyle(
                    eyeShape: QrEyeShape.square, color: Color(0xFF0A0C0E)),
                dataModuleStyle: const QrDataModuleStyle(
                    dataModuleShape: QrDataModuleShape.square,
                    color: Color(0xFF0A0C0E)))),
        SizedBox(height: Design.dz(9)),
        SelectableText(url,
            key: const ValueKey('transfer-url'),
            textAlign: TextAlign.center,
            style: TextStyle(
                fontSize: Design.dz(15.5),
                color: s.accent,
                letterSpacing: Design.dz(.31),
                fontFeatures: const [FontFeature.tabularFigures()])),
        SizedBox(height: Design.dz(5)),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Container(
              width: Design.dz(4),
              height: Design.dz(4),
              decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: s.accent.withValues(alpha: .8))),
          SizedBox(width: Design.dz(6)),
          Text('WiFi 局域网 · 手机扫码后浏览器打开上传页',
              style: TextStyle(fontSize: Design.dz(11.5), color: s.muted))
        ])
      ]));

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<
          Map<String, dynamic>>(
      valueListenable: controller.native,
      builder: (context, native, _) {
        final s = SurfaceStyle.of(context);
        final data = native['transfer'] is Map
            ? Map<String, dynamic>.from(native['transfer'] as Map)
            : <String, dynamic>{};
        final running = data['running'] == true;
        final url = '${data['url'] ?? ''}';
        final files = data['files'] is List ? data['files'] as List : [];
        final texts = data['texts'] is List ? data['texts'] as List : [];
        final allLinks = data['links'] is List ? data['links'] as List : [];
        final links = [
          for (final link in allLinks)
            if (link is Map && '${link['status']}' != 'done') link
        ];
        // 下载完成的链接已经落到文件里，用主机名给那一行当来源标，避免重复列一行。
        final sources = <String, String>{
          for (final link in allLinks)
            if (link is Map && '${link['status']}' == 'done')
              '${link['name'] ?? ''}': '${link['host'] ?? ''}'
        };
        final rows = <Widget>[
          for (final note in texts) _textRow(s, note is Map ? note : const {}),
          for (final link in links) _linkRow(s, link),
          for (final file in files)
            _fileRow(s, file is Map ? file : const {},
                sources['${(file is Map ? file : const {})['name'] ?? ''}']),
        ];
        final received = texts.length + links.length + files.length;
        return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                  height: Design.dz(36),
                  child: Row(children: [
                    Text('传文件',
                        style: TextStyle(
                            fontSize: Design.dz(21.67),
                            fontWeight: FontWeight.w500,
                            letterSpacing: Design.dz(.43),
                            color: s.text.withValues(alpha: .96))),
                    const Spacer(),
                    _closeButton(s)
                  ])),
              _tabs(s),
              if (_tab == 0) ...[
                _switchRow(s, running),
                if (running && url.isNotEmpty)
                  _qrBlock(s, url)
                else
                  Padding(
                      padding: EdgeInsets.symmetric(vertical: Design.dz(26)),
                      child: Text(running ? '未检测到可用网络地址' : '开启后显示二维码与访问地址',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              fontSize: Design.dz(12), color: s.muted))),
                // `.ft-lh`：左「已接收 N」，右「清空文本」。
                Container(
                    padding: EdgeInsets.only(
                        top: Design.dz(11), bottom: Design.dz(7)),
                    decoration: BoxDecoration(
                        border: Border(
                            top: BorderSide(
                                color: s.text.withValues(alpha: .07)))),
                    child: Row(children: [
                      Text('已接收 $received',
                          style: TextStyle(
                              fontSize: Design.dz(11.5),
                              letterSpacing: Design.dz(1.15),
                              color: s.muted)),
                      const Spacer(),
                      if (texts.isNotEmpty)
                        GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () =>
                                controller.command('transfer-text-clear'),
                            child: Text('清空文本',
                                style: TextStyle(
                                    fontSize: Design.dz(11.5), color: s.muted)))
                    ]))
              ] else
                SizedBox(
                    height: Design.dz(430),
                    child: QuarkBrowser(
                        controller: controller,
                        onShowPhone: () => setState(() => _tab = 0))),
              Expanded(
                  child: rows.isEmpty
                      ? Align(
                          alignment: Alignment.topCenter,
                          child: Padding(
                              padding: EdgeInsets.only(top: Design.dz(16)),
                              child: Text('还没有文件，扫码上传或让手机发送链接/文本',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                      fontSize: Design.dz(12),
                                      color: s.muted))))
                      : ListView(padding: EdgeInsets.zero, children: rows)),
              if (_tab == 0)
                Container(
                    padding: EdgeInsets.only(top: Design.dz(9)),
                    decoration: BoxDecoration(
                        border: Border(
                            top: BorderSide(
                                color: s.text.withValues(alpha: .06)))),
                    child: Row(children: [
                      Container(
                          width: Design.dz(4),
                          height: Design.dz(4),
                          decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: s.text.withValues(alpha: .28))),
                      SizedBox(width: Design.dz(7)),
                      Expanded(
                          child: Text('APK 上传后可直接安装 · 链接任务需在车机点「下载」',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontSize: Design.dz(10.5),
                                  color: s.text.withValues(alpha: .28))))
                    ]))
            ]);
      });
}
