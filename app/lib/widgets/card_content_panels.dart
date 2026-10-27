part of 'card_content.dart';

Future<void> showAppsPanel(BuildContext context, LauncherController c) async {
  if (await c.presentGlobalPanel('apps') || !context.mounted) return;
  await showLauncherSheet<void>(context,
      title: '全部应用',
      subtitle: '已安装的应用',
      closeLabel: '关闭应用列表',
      width: Design.px(1560),
      height: Design.px(760),
      builder: (context) => AppPanel(controller: c));
}

Future<void> showMediaPanel(BuildContext context, LauncherController c) async {
  if (await c.presentGlobalPanel('media') || !context.mounted) return;
  await showLauncherSheet<void>(context,
      title: '正在播放',
      titleWidget: MediaSourceBadge(controller: c, titleBar: true),
      closeLabel: '关闭音乐详情',
      width: Design.px(1040),
      builder: (context) => MediaPanel(controller: c));
}

class AppPanel extends StatelessWidget {
  final LauncherController controller;
  const AppPanel({super.key, required this.controller});
  @override
  Widget build(BuildContext context) =>
      ValueListenableBuilder<Map<String, dynamic>>(
          valueListenable: controller.native,
          builder: (context, state, _) {
            final s = SurfaceStyle.of(context);
            final apps =
                state['apps'] is List ? state['apps'] as List : const [];
            if (apps.isEmpty)
              return Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                UniIcon('apps', size: Design.px(60), color: s.accent),
                SizedBox(height: Design.px(24)),
                Text('等待应用列表',
                    style: TextStyle(fontSize: Design.px(25), color: s.muted)),
              ]));
            return GridView.builder(
                padding: EdgeInsets.symmetric(vertical: Design.px(32)),
                itemCount: apps.length,
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 7,
                    mainAxisSpacing: Design.px(40),
                    crossAxisSpacing: Design.px(12),
                    mainAxisExtent: Design.px(156)),
                itemBuilder: (context, i) {
                  return _AppTile(
                      app: mapOf(apps[i]), controller: controller, index: i);
                });
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
        settingsEntry = id != null &&
            (id.endsWith('/.DesktopSettings') ||
                id.endsWith('/xyz.i4o.uni.launcher.DesktopSettings')),
        tap = id == null
            ? null
            : settingsEntry
                ? () {
                    if (!controller.isGlobalDock) Navigator.of(context).pop();
                    controller.openSettings();
                  }
                : () => controller.command('launch-app', value: id);
    return Column(children: [
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
                      shape: RoundedRectangleBorder(
                          side: BorderSide(color: s.edge),
                          borderRadius: radius),
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
    ]);
  }
}

Future<void> showAppMenu(BuildContext context, LauncherController c,
    Map<String, dynamic> app) async {
  final action = await showLauncherSheet<String>(context,
      title: c.appName(app),
      closeLabel: '关闭应用菜单',
      width: Design.px(520),
      height: Design.px(400),
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
