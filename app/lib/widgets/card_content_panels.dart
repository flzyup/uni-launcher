part of 'card_content.dart';

Future<void> showAppsPanel(BuildContext context, LauncherController c) async {
  if (await c.presentGlobalPanel('apps') || !context.mounted) return;
  final dock = DockWindowScope.of(context);
  final route = Navigator.of(context).push(PageRouteBuilder<void>(
      opaque: !SurfaceStyle.of(context).liquidGlass,
      pageBuilder: (_, __, ___) =>
          RepaintBoundary(child: _AppsPage(controller: c)),
      transitionDuration: const Duration(milliseconds: 150),
      reverseTransitionDuration: const Duration(milliseconds: 130),
      transitionsBuilder: (_, animation, __, child) => FadeTransition(
          opacity: CurvedAnimation(
              parent: animation,
              curve: Curves.easeOutCubic,
              reverseCurve: Curves.easeInCubic),
          child: child)));
  if (dock?.onPresented != null) {
    await WidgetsBinding.instance.endOfFrame;
    if (context.mounted) await dock!.onPresented!();
  }
  await route;
}

/// 卡片 / 底栏点进来：把这张音乐卡铺满整页（网格里只剩它一张，顶部栏与底栏照常
/// 显示，收起就回原页）。
///
/// [cardId] 是被点的那张卡（底栏没有具体卡片，留空）。桌面有两张音乐卡时必须
/// 传进来，否则会铺满 `cards` 里的第一张、顺带把桌面翻到那一页。
///
/// 这里**不再先转交全局底栏面板**（2026-11-13 实车反馈）：车机上底栏服务常态在跑，
/// `presentGlobalPanel('media')` 于是总是成立，点卡片出来的是另一套 1040 宽的旧弹层，
/// 而且它是压在桌面之上的独立 overlay —— 关掉后桌面还会僵住。桌面这一侧自己就能把
/// 卡片铺满，不需要那个窗口。
Future<void> showMusicPlayer(BuildContext context, LauncherController c,
    {String? cardId}) async {
  // 底栏窗口的引擎里没有桌面，只能请主窗口代开（原生死转发 focus-music-card）。
  if (c.isGlobalDock) {
    await c.command('focus-music-card');
    return;
  }
  if (c.focusMusicCard(cardId: cardId)) return;
  // 一张音乐卡都没有：退回老的媒体面板，至少还能换音源。
  if (!context.mounted) return;
  await showMediaPanel(context, c);
}

Future<void> showMediaPanel(BuildContext context, LauncherController c) async {
  if (await c.presentGlobalPanel('media') || !context.mounted) return;
  await showLauncherSheet<void>(context,
      title: '正在播放',
      titleWidget: MediaSourceBadge(controller: c, titleBar: true),
      closeLabel: '关闭音乐详情',
      width: Design.px(1040),
      glowType: 'music',
      // 稿子 f5 的 `.v2-src`：换音源在播放器里换，桌面卡片上不再放这颗键。
      actions: Builder(
          builder: (sheet) => IconAction(
              key: const ValueKey('media-app-picker'),
              icon: Icons.swap_horiz,
              label: '选择音乐应用',
              size: Design.px(54),
              iconSize: Design.px(25),
              soft: true,
              onTap: () => showMusicPicker(sheet, c))),
      builder: (context) => MediaPanel(controller: c));
}

class _AppsPage extends StatelessWidget {
  final LauncherController controller;
  const _AppsPage({required this.controller});
  @override
  Widget build(BuildContext context) {
    final s = SurfaceStyle.of(context);
    final content = AppPanel(controller: controller, fullPage: true);
    return Scaffold(
        // 玻璃必须能采样后面的场景；旧实色页面底板会抹掉壁纸细节。
        backgroundColor: s.liquidGlass ? Colors.transparent : s.strong,
        body: Padding(
            padding: EdgeInsets.all(Design.px(32)),
            child: s.liquidGlass
                ? GlassSurface(
                    key: const ValueKey('apps-page-material'),
                    sheet: true,
                    padding: EdgeInsets.zero,
                    child: content)
                : content));
  }
}

class AppPanel extends StatefulWidget {
  final LauncherController controller;
  final bool fullPage;
  const AppPanel({super.key, required this.controller, this.fullPage = false});
  @override
  State<AppPanel> createState() => _AppPanelState();
}

class _AppPanelState extends State<AppPanel> {
  bool enabled = true;
  bool showSystem = true;

  @override
  Widget build(BuildContext context) => NativeSliceBuilder(
      valueListenable: widget.controller.native,
      select: (state) => [state['apps'], state['appNames']],
      builder: (context, state) {
        final s = SurfaceStyle.of(context);
        // 「显示系统应用」与「可启动」先落一层底表，两颗胶囊的计数和网格用同一份，
        // 数字才对得上格子。
        final base = (state['apps'] is List ? state['apps'] as List : const [])
            .whereType<Map>()
            .where((app) => showSystem || app['isSystem'] != true)
            .where((app) => app['launchable'] != false)
            .toList();
        final enabledApps =
            base.where((app) => app['enabled'] != false).toList();
        final disabledApps =
            base.where((app) => app['enabled'] == false).toList();
        final apps = enabled ? enabledApps : disabledApps;

        final panel = GlassSurface(
            key: const ValueKey('apps-panel'),
            sheet: s.liquidGlass,
            // 稿子 `.ap-panel`：20.83 圆角、20/30/30 内边距——筛选和网格同住一张卡，
            // 不再有左侧那条独立筛选列。
            radius: s.radius,
            padding: EdgeInsets.fromLTRB(
                Design.px(36), Design.px(24), Design.px(36), Design.px(36)),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(children: [
                    _FilterPills(
                        enabled: enabled,
                        enabledCount: enabledApps.length,
                        disabledCount: disabledApps.length,
                        onPick: (value) => setState(() => enabled = value)),
                    const Spacer(),
                    // `.ap-tools .tip`
                    Text('长按图标可编辑',
                        style: TextStyle(
                            fontSize: Design.px(15.6),
                            letterSpacing: Design.px(.24),
                            color: s.muted)),
                  ]),
                  SizedBox(height: Design.px(24)),
                  Expanded(
                      child: apps.isEmpty
                          ? Center(
                              child: Text(enabled ? '暂无已启用应用' : '暂无已禁用应用',
                                  style: TextStyle(
                                      color: s.muted, fontSize: Design.px(24))))
                          : LayoutBuilder(builder: (context, box) {
                              if (box.maxWidth <= 1) {
                                return const SizedBox.shrink();
                              }
                              return GridView.builder(
                                  key: ValueKey(enabled
                                      ? 'apps-enabled-grid'
                                      : 'apps-disabled-grid'),
                                  padding: EdgeInsets.zero,
                                  itemCount: apps.length,
                                  // 稿子 `.ap-grid`：7 列，行距 20 / 列距 8。
                                  gridDelegate:
                                      SliverGridDelegateWithFixedCrossAxisCount(
                                          crossAxisCount: 7,
                                          mainAxisSpacing: Design.px(24),
                                          crossAxisSpacing: Design.px(9.6),
                                          mainAxisExtent: Design.px(148)),
                                  itemBuilder: (_, i) => _AppTile(
                                      app: mapOf(apps[i]),
                                      controller: widget.controller,
                                      index: i));
                            })),
                ]));

        if (!widget.fullPage) return panel;
        return Column(children: [
          _header(context, s),
          SizedBox(height: Design.px(32)),
          Expanded(child: panel),
        ]);
      });

  /// `.ap-hd`：53.33 的返回方框 + 30 标题 + 右侧「显示系统应用」与开关。
  ///
  /// 原来用 IconButton + Material 默认内边距，命中区和图标位置都跟稿子对不上，
  /// 这里按 `.ap-hd .back` 的 53.33 / 圆角 16 / 5% 底 + 9% 描边自绘。
  Widget _header(BuildContext context, SurfaceStyle s) => SizedBox(
      height: Design.px(64),
      child: Row(children: [
        Semantics(
            button: true,
            label: '返回',
            child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => Navigator.pop(context),
                child: Container(
                    width: Design.px(64),
                    height: Design.px(64),
                    decoration: BoxDecoration(
                        color: s.text.withValues(alpha: .05),
                        border:
                            Border.all(color: s.text.withValues(alpha: .09)),
                        borderRadius: BorderRadius.circular(Design.px(19.2))),
                    child: Center(
                        child: Icon(Icons.arrow_back_ios_new,
                            size: Design.px(28.8),
                            color: s.text.withValues(alpha: .92)))))),
        SizedBox(width: Design.px(19.2)),
        Text('全部应用',
            style: TextStyle(
                fontSize: Design.px(36),
                fontWeight: FontWeight.w500,
                letterSpacing: Design.px(.36))),
        const Spacer(),
        Text('显示系统应用',
            style: TextStyle(fontSize: Design.px(20), color: s.muted)),
        SizedBox(width: Design.px(16)),
        KeyedSubtree(
            key: const ValueKey('apps-show-system'),
            child: DesignToggle(
                label: '显示系统应用',
                value: showSystem,
                onChanged: (value) => setState(() => showSystem = value))),
      ]));
}

/// `.apf`：已启用 / 已禁用两颗胶囊，选中态是强调色渐变实底，后面跟计数。
///
/// 原来是左侧一列 300 宽的选择卡；稿子把筛选收进面板顶部一行，网格才能吃满宽度。
class _FilterPills extends StatelessWidget {
  final bool enabled;
  final int enabledCount, disabledCount;
  final ValueChanged<bool> onPick;
  const _FilterPills(
      {required this.enabled,
      required this.enabledCount,
      required this.disabledCount,
      required this.onPick});

  @override
  Widget build(BuildContext context) {
    final s = SurfaceStyle.of(context);
    return Container(
        padding: EdgeInsets.all(Design.px(4.8)),
        decoration: BoxDecoration(
            color: s.text.withValues(alpha: .05),
            border: Border.all(color: s.text.withValues(alpha: .075)),
            borderRadius: BorderRadius.circular(Design.px(18))),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          _pill(s, 'apps-enabled', '已启用', enabledCount, enabled, true),
          _pill(s, 'apps-disabled', '已禁用', disabledCount, !enabled, false),
        ]));
  }

  Widget _pill(SurfaceStyle s, String key, String label, int count, bool on,
      bool pickEnabled) {
    return GestureDetector(
        key: ValueKey(key),
        behavior: HitTestBehavior.opaque,
        onTap: () => onPick(pickEnabled),
        child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            height: Design.px(48),
            padding: EdgeInsets.symmetric(horizontal: Design.px(26.4)),
            decoration: BoxDecoration(
                gradient: on ? s.accentFill : null,
                borderRadius: BorderRadius.circular(Design.px(13.8)),
                boxShadow: on
                    ? [
                        BoxShadow(
                            color: s.accent.withValues(alpha: .40),
                            offset: Offset(0, Design.px(8)),
                            blurRadius: Design.px(20),
                            spreadRadius: -Design.px(10))
                      ]
                    : null),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Text(label,
                  style: TextStyle(
                      fontSize: Design.px(18.6),
                      fontWeight: on ? FontWeight.w600 : FontWeight.w400,
                      color: on ? s.accentText : s.muted)),
              SizedBox(width: Design.px(10.8)),
              Text('$count',
                  style: TextStyle(
                      fontSize: Design.px(15),
                      fontWeight: FontWeight.w500,
                      color: (on ? s.accentText : s.text)
                          .withValues(alpha: on ? .6 : .45))),
            ])));
  }
}

/// Keeps the pressed material, clipping path and visible icon frame on the
/// same bounds. Previously the InkWell filled the complete grid cell while
/// the frame was only 104px, which made the highlight visibly jump in size.
class _AppTile extends StatelessWidget {
  final Map<String, dynamic> app;
  final LauncherController controller;
  final int index;
  const _AppTile(
      {required this.app, required this.controller, required this.index});

  @override
  Widget build(BuildContext context) {
    final s = SurfaceStyle.of(context),
        bytes = app['iconBytes'],
        label = controller.appName(app),
        id = app['id']?.toString(),
        keyId = app['package']?.toString() ?? id ?? 'index-$index',
        radius = BorderRadius.circular(s.controlRadius),
        frameShape = s.technicalFrame
            ? s.controlShape().copyWith(side: s.controlSide(false))
            : RoundedRectangleBorder(
                // 稿子 `.ap-tile .fr`：10% 墨色描边，不是主题 edge 色
                side: BorderSide(color: s.text.withValues(alpha: .10)),
                borderRadius: radius),
        settingsEntry = id != null &&
            (id.endsWith('/.DesktopSettings') ||
                id.endsWith('/xyz.i4o.uni.launcher.DesktopSettings')),
        tap =
            id == null || app['enabled'] == false || app['launchable'] == false
                ? null
                : settingsEntry
                    ? () {
                        if (!controller.isGlobalDock)
                          Navigator.of(context).pop();
                        controller.openSettings();
                      }
                    : () => controller.command('launch-app', value: id);
    return RepaintBoundary(
        child: Column(children: [
      Semantics(
          button: true,
          label: label,
          enabled: tap != null,
          child: Tooltip(
              message: label,
              child: SizedBox.square(
                  // 稿子 `.ap-tile .fr` 是 96 画布（原来 104 / 1.2 ≈ 86.7，偏小）
                  dimension: Design.px(115.2),
                  child: Material(
                      key: ValueKey('app-icon-frame-$keyId'),
                      color: s.text.withValues(alpha: .05),
                      shape: frameShape,
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                          key: ValueKey('app-icon-ink-$keyId'),
                          borderRadius: radius,
                          onLongPress: () =>
                              showAppMenu(context, controller, app),
                          onTap: tap,
                          child: Center(
                              child: bytes is Uint8List
                                  ? Image.memory(bytes,
                                      width: Design.px(54),
                                      height: Design.px(54),
                                      gaplessPlayback: true,
                                      filterQuality: FilterQuality.low,
                                      errorBuilder: (context, error, stack) =>
                                          UniIcon('apps',
                                              size: Design.px(54),
                                              color: s.accent))
                                  : UniIcon('apps',
                                      size: Design.px(54),
                                      color: s.accent))))))),
      SizedBox(height: Design.px(10.8)),
      GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: tap,
          onLongPress: () => showAppMenu(context, controller, app),
          child: Text(label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: Design.px(18), height: 1.2, color: s.muted))),
    ]));
  }
}

Future<void> showAppMenu(BuildContext context, LauncherController c,
    Map<String, dynamic> app) async {
  final action = await showLauncherSheet<String>(context,
      title: c.appName(app),
      closeLabel: '关闭应用菜单',
      width: Design.px(520),
      height: Design.px(480),
      glowType: 'shortcuts',
      builder: (context) => Column(mainAxisSize: MainAxisSize.min, children: [
            ListTile(
                key: const ValueKey('app-menu-rename'),
                leading: const Icon(Icons.edit_outlined),
                title: const Text('重命名'),
                onTap: () => Navigator.pop(context, 'rename')),
            ListTile(
                key: const ValueKey('app-menu-info'),
                leading: const Icon(Icons.info_outline),
                title: const Text('应用信息'),
                onTap: () => Navigator.pop(context, 'app-info')),
            ListTile(
                key: const ValueKey('app-menu-toggle-enabled'),
                leading: Icon(app['enabled'] == false
                    ? Icons.check_circle_outline
                    : Icons.block),
                title: Text(app['enabled'] == false ? '启用' : '禁用'),
                enabled: app['canChangeEnabled'] != false,
                onTap: app['canChangeEnabled'] == false
                    ? null
                    : () => Navigator.pop(
                        context,
                        app['enabled'] == false
                            ? 'app-enable'
                            : 'app-disable')),
            ListTile(
                key: const ValueKey('app-menu-uninstall'),
                leading: const Icon(Icons.delete_outline),
                title: const Text('卸载'),
                enabled: app['canUninstall'] == true,
                onTap: app['canUninstall'] == true
                    ? () => Navigator.pop(context, 'request-uninstall')
                    : null),
          ]));
  if (action == 'rename' && context.mounted) {
    final name = await showLauncherSheet<String>(context,
        title: '重命名应用',
        subtitle: '${app['label'] ?? app['package'] ?? ''}',
        closeLabel: '关闭应用重命名',
        width: Design.px(680),
        height: Design.px(390),
        glowType: 'shortcuts',
        builder: (_) => _AppNameEditor(initial: c.appName(app)));
    if (name != null && app['package'] != null) {
      await c.renameApp('${app['package']}', name);
    }
  } else if (action != null) {
    await c.command(action, value: '${app['package']}');
  }
}

class _AppNameEditor extends StatefulWidget {
  final String initial;
  const _AppNameEditor({required this.initial});
  @override
  State<_AppNameEditor> createState() => _AppNameEditorState();
}

class _AppNameEditorState extends State<_AppNameEditor> {
  late final input = TextEditingController(text: widget.initial);
  @override
  void dispose() {
    input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        TextField(
            key: const ValueKey('app-name-input'),
            autofocus: true,
            controller: input,
            maxLength: 24,
            maxLines: 1,
            decoration: const InputDecoration(labelText: '桌面显示名称'),
            onSubmitted: (value) => Navigator.pop(context, value)),
        SizedBox(height: Design.px(24)),
        Row(mainAxisAlignment: MainAxisAlignment.end, children: [
          TextButton(
              key: const ValueKey('app-name-reset'),
              onPressed: () => Navigator.pop(context, ''),
              child: const Text('恢复系统名称')),
          SizedBox(width: Design.px(16)),
          FilledButton(
              key: const ValueKey('app-name-save'),
              onPressed: () => Navigator.pop(context, input.text),
              child: const Text('保存')),
        ])
      ]));
}
