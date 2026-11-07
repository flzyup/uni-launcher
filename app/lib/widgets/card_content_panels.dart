part of 'card_content.dart';

Future<void> showAppsPanel(BuildContext context, LauncherController c) async {
  if (await c.presentGlobalPanel('apps') || !context.mounted) return;
  final dock = DockWindowScope.of(context);
  final route = Navigator.of(context).push(PageRouteBuilder<void>(
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

Future<void> showMediaPanel(BuildContext context, LauncherController c) async {
  if (await c.presentGlobalPanel('media') || !context.mounted) return;
  await showLauncherSheet<void>(context,
      title: '正在播放',
      titleWidget: MediaSourceBadge(controller: c, titleBar: true),
      closeLabel: '关闭音乐详情',
      width: Design.px(1040),
      glowType: 'music',
      builder: (context) => MediaPanel(controller: c));
}

class _AppsPage extends StatelessWidget {
  final LauncherController controller;
  const _AppsPage({required this.controller});
  @override
  Widget build(BuildContext context) => Scaffold(
      backgroundColor: SurfaceStyle.of(context).strong,
      body: Padding(
          padding: EdgeInsets.all(Design.px(32)),
          child: AppPanel(controller: controller, fullPage: true)));
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
  bool showSystem = false;
  @override
  Widget build(BuildContext context) => NativeSliceBuilder(
      valueListenable: widget.controller.native,
      select: (state) => [state['apps'], state['appNames']],
      builder: (context, state) {
        final s = SurfaceStyle.of(context);
        final apps = (state['apps'] is List ? state['apps'] as List : const [])
            .whereType<Map>()
            .where((app) => (app['enabled'] != false) == enabled)
            .where((app) => showSystem || app['isSystem'] != true)
            .where((app) => app['launchable'] != false)
            .toList();
        final content =
            Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SizedBox(
              width: Design.px(300),
              child: Center(
                  child: GlassSurface(
                      key: const ValueKey('apps-sidebar'),
                      padding: EdgeInsets.all(Design.px(14)),
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        for (final entry in [(true, '已启用'), (false, '已禁用')])
                          Padding(
                              padding: EdgeInsets.only(bottom: Design.px(10)),
                              child: SizedBox(
                                  width: double.infinity,
                                  height: Design.px(68),
                                  child: OutlinedButton(
                                      key: ValueKey(entry.$1
                                          ? 'apps-enabled'
                                          : 'apps-disabled'),
                                      style:
                                          s.selectionStyle(enabled == entry.$1),
                                      onPressed: () =>
                                          setState(() => enabled = entry.$1),
                                      child: Text(entry.$2)))),
                      ])))),
          SizedBox(width: Design.px(22)),
          Expanded(
              child: apps.isEmpty
                  ? Center(
                      child: Text(enabled ? '暂无已启用应用' : '暂无已禁用应用',
                          style: TextStyle(
                              color: s.muted, fontSize: Design.px(24))))
                  : LayoutBuilder(builder: (context, box) {
                      if (box.maxWidth <= 1) return const SizedBox.shrink();
                      return GridView.builder(
                          key: ValueKey(enabled
                              ? 'apps-enabled-grid'
                              : 'apps-disabled-grid'),
                          padding:
                              EdgeInsets.symmetric(vertical: Design.px(32)),
                          itemCount: apps.length,
                          gridDelegate:
                              SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: 7,
                                  mainAxisSpacing: Design.px(40),
                                  crossAxisSpacing: Design.px(12),
                                  mainAxisExtent: Design.px(156)),
                          itemBuilder: (_, i) => _AppTile(
                              app: mapOf(apps[i]),
                              controller: widget.controller,
                              index: i));
                    })),
        ]);
        if (!widget.fullPage) return content;
        return Column(children: [
          Row(children: [
            IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.arrow_back),
                tooltip: '返回'),
            SizedBox(width: Design.px(20)),
            Text('全部应用', style: TextStyle(fontSize: Design.px(36))),
            const Spacer(),
            Text('显示系统应用', style: TextStyle(fontSize: Design.px(20))),
            SizedBox(width: Design.px(16)),
            KeyedSubtree(
                key: const ValueKey('apps-show-system'),
                child: s.technicalFrame
                    ? DesignToggle(
                        label: '显示系统应用',
                        value: showSystem,
                        onChanged: (value) =>
                            setState(() => showSystem = value))
                    : Switch(
                        value: showSystem,
                        onChanged: (value) =>
                            setState(() => showSystem = value))),
          ]),
          SizedBox(height: Design.px(20)),
          Expanded(child: content),
        ]);
      });
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
                side: BorderSide(color: s.edge), borderRadius: radius),
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
                  dimension: Design.px(104),
                  child: Material(
                      key: ValueKey('app-icon-frame-$keyId'),
                      color: s.soft,
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
                                      width: Design.px(66),
                                      height: Design.px(66),
                                      gaplessPlayback: true,
                                      filterQuality: FilterQuality.low,
                                      errorBuilder: (context, error, stack) =>
                                          UniIcon('apps',
                                              size: Design.px(45),
                                              color: s.accent))
                                  : UniIcon('apps',
                                      size: Design.px(45),
                                      color: s.accent))))))),
      SizedBox(height: Design.px(18)),
      GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: tap,
          onLongPress: () => showAppMenu(context, controller, app),
          child: Text(label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: Design.px(23), height: 1.2))),
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
