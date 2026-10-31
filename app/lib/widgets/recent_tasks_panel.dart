import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../controller/launcher_controller.dart';
import '../theme/design_tokens.dart';
import '../theme/launcher_theme.dart';
import 'card_content.dart' show mapOf;
import 'glass_surface.dart';
import 'scene_background.dart';

class RecentTasksPanel extends StatelessWidget {
  final LauncherController controller;
  const RecentTasksPanel({super.key, required this.controller});

  @override
  Widget build(BuildContext context) =>
      ValueListenableBuilder<Map<String, dynamic>>(
          valueListenable: controller.native,
          builder: (context, state, _) {
            final tasks = state['recentTasks'] is List
                ? state['recentTasks'] as List
                : const [];
            final dock = mapOf(state['globalDock']);
            return SceneBackground(
                child: SizedBox.expand(
                    child: FittedBox(
                        fit: BoxFit.fill,
                        child: SizedBox(
                            width: Design.canvasWidth,
                            height: Design.px(984),
                            child: Padding(
                                padding: EdgeInsets.fromLTRB(
                                    Design.px(40),
                                    Design.px(30),
                                    Design.px(40),
                                    Design.px(24)),
                                child: Column(children: [
                                  _Header(
                                      controller: controller,
                                      count: tasks.length),
                                  SizedBox(height: Design.px(26)),
                                  Expanded(
                                      child: dock['recentsReady'] != true
                                          ? const Center(
                                              child:
                                                  CircularProgressIndicator())
                                          : tasks.isEmpty
                                              ? const _EmptyTasks()
                                              : _TaskStrip(
                                                  controller: controller,
                                                  tasks: tasks)),
                                  SizedBox(height: Design.px(18)),
                                  _Footer(
                                      controller: controller,
                                      state: state,
                                      enabled: dock['recentsClearSupported'] ==
                                              true &&
                                          tasks.isNotEmpty),
                                ]))))));
          });
}

class _Header extends StatelessWidget {
  final LauncherController controller;
  final int count;
  const _Header({required this.controller, required this.count});
  @override
  Widget build(BuildContext context) {
    final s = SurfaceStyle.of(context);
    return SizedBox(
        height: Design.px(60),
        child: Row(children: [
          Icon(Icons.check_box_outline_blank_rounded,
              size: Design.px(30), color: s.accent),
          SizedBox(width: Design.px(16)),
          Text('最近任务',
              style: TextStyle(
                  fontSize: Design.px(30), fontWeight: FontWeight.w500)),
          SizedBox(width: Design.px(16)),
          Text('$count 个应用',
              style: TextStyle(fontSize: Design.px(18), color: s.muted)),
          const Spacer(),
          IconAction(
              key: const ValueKey('recent-tasks-close'),
              icon: Icons.close,
              label: '关闭最近任务',
              size: Design.px(52),
              iconSize: Design.px(26),
              onTap: () => controller.command('dismiss-dock-panel')),
        ]));
  }
}

class _TaskStrip extends StatelessWidget {
  final LauncherController controller;
  final List tasks;
  const _TaskStrip({required this.controller, required this.tasks});
  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, box) {
        final width = tasks.length == 1
            ? Design.px(780)
            : tasks.length == 2
                ? Design.px(620)
                : Design.px(460);
        final height =
            (width * 9 / 16 + Design.px(88)).clamp(0.0, box.maxHeight);
        final total = tasks.length * width +
            (tasks.length - 1).clamp(0, tasks.length) * Design.px(24);
        final list = ListView.separated(
            key: const ValueKey('recent-task-list'),
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            itemCount: tasks.length,
            separatorBuilder: (_, __) => SizedBox(width: Design.px(24)),
            itemBuilder: (context, index) {
              final task = mapOf(tasks[index]);
              final id = (task['taskId'] as num?)?.toInt();
              final locked = task['locked'] == true;
              return Center(
                  child: SizedBox(
                      width: width,
                      height: height,
                      child: Dismissible(
                          key: ValueKey('recent-task-dismiss-$id'),
                          direction: DismissDirection.vertical,
                          dismissThresholds: const {
                            DismissDirection.up: .28,
                            DismissDirection.down: .28,
                          },
                          confirmDismiss: (_) async {
                                  if (id == null || locked) return false;
                                  await controller.command('remove-recent-task',
                                      value: '$id');
                                  // Native recent-task state owns removal. Keep
                                  // this frame until its refreshed snapshot
                                  // arrives so Dismissible is never orphaned.
                                  return false;
                                },
                          background: _DismissBackground(up: false, locked: locked),
                          secondaryBackground:
                              _DismissBackground(up: true, locked: locked),
                          child:
                              _TaskCard(controller: controller, task: task))));
            });
        return Center(
            child: SizedBox(
                width: total <= box.maxWidth ? total.toDouble() : box.maxWidth,
                height: height,
                child: list));
      });
}

class _DismissBackground extends StatelessWidget {
  final bool up;
  final bool locked;
  const _DismissBackground({required this.up, required this.locked});
  @override
  Widget build(BuildContext context) {
    final s = SurfaceStyle.of(context);
    return Align(
        alignment: up ? Alignment.bottomCenter : Alignment.topCenter,
        child: Padding(
            padding: EdgeInsets.symmetric(vertical: Design.px(24)),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(up ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                  size: Design.px(34), color: s.accent),
              Text(locked ? '已锁定' : '松开清除',
                  style: TextStyle(fontSize: Design.px(18), color: s.muted)),
            ])));
  }
}

class _TaskCard extends StatelessWidget {
  final LauncherController controller;
  final Map<String, dynamic> task;
  const _TaskCard({required this.controller, required this.task});
  @override
  Widget build(BuildContext context) {
    final s = SurfaceStyle.of(context),
        id = (task['taskId'] as num?)?.toInt(),
        icon = task['iconBytes'],
        snapshot = task['snapshotBytes'],
        label = controller.appName(task),
        locked = task['locked'] == true;
    return GlassSurface(
        key: ValueKey('recent-task-$id'),
        padding: EdgeInsets.zero,
        tone: SurfaceTone.strong,
        child: InkWell(
            onTap: id == null
                ? null
                : () => controller.command('open-recent-task', value: '$id'),
            child: Column(children: [
              Expanded(
                  child: ClipRRect(
                      borderRadius:
                          BorderRadius.vertical(top: Radius.circular(s.radius)),
                      child: ColoredBox(
                          color: s.dark
                              ? const Color(0xFF090E12)
                              : const Color(0xFFD7E1DF),
                          child: snapshot is Uint8List
                              ? Image.memory(snapshot,
                                  width: double.infinity,
                                  height: double.infinity,
                                  fit: BoxFit.cover,
                                  gaplessPlayback: true,
                                  errorBuilder: (_, __, ___) =>
                                      _TaskPlaceholder(icon: icon))
                              : _TaskPlaceholder(icon: icon)))),
              SizedBox(
                  height: Design.px(88),
                  child: Padding(
                      padding: EdgeInsets.symmetric(horizontal: Design.px(20)),
                      child: Row(children: [
                        _TaskIcon(bytes: icon),
                        SizedBox(width: Design.px(14)),
                        Expanded(
                            child: Text(label,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: Design.px(23)))),
                        IconAction(
                            key: ValueKey('recent-task-lock-$id'),
                            icon: locked
                                ? Icons.lock_rounded
                                : Icons.lock_open_rounded,
                            label: locked ? '解锁最近任务' : '锁定最近任务',
                            size: Design.px(44),
                            iconSize: Design.px(25),
                            framed: false,
                            foregroundColor: locked ? s.accent : s.muted,
                            onTap: id == null
                                ? null
                                : () => controller.command('toggle-recent-lock',
                                    value: '$id')),
                      ])))
            ])));
  }
}

class _TaskIcon extends StatelessWidget {
  final Object? bytes;
  const _TaskIcon({required this.bytes});
  @override
  Widget build(BuildContext context) => SizedBox.square(
      dimension: Design.px(48),
      child: bytes is Uint8List
          ? Image.memory(bytes! as Uint8List, fit: BoxFit.contain)
          : Icon(Icons.apps_rounded, size: Design.px(34)));
}

class _TaskPlaceholder extends StatelessWidget {
  final Object? icon;
  const _TaskPlaceholder({required this.icon});
  @override
  Widget build(BuildContext context) {
    final s = SurfaceStyle.of(context);
    return Center(
        child: Opacity(
            opacity: .72,
            child: icon is Uint8List
                ? Image.memory(icon! as Uint8List,
                    width: Design.px(96), height: Design.px(96))
                : Icon(Icons.apps_rounded,
                    size: Design.px(82), color: s.muted)));
  }
}

class _Footer extends StatelessWidget {
  final LauncherController controller;
  final Map<String, dynamic> state;
  final bool enabled;
  const _Footer(
      {required this.controller, required this.state, required this.enabled});
  @override
  Widget build(BuildContext context) {
    final s = SurfaceStyle.of(context),
        memory = mapOf(mapOf(state['systemStatus'])['memory']),
        total = memory['totalBytes'] as num?,
        used = memory['usedBytes'] as num?;
    String gib(num bytes) => (bytes / (1024 * 1024 * 1024)).toStringAsFixed(2);
    return SizedBox(
        height: Design.px(64),
        child: Row(children: [
          TextButton.icon(
              key: const ValueKey('system-recents-clear'),
              onPressed: enabled
                  ? () => controller.command('clear-system-recents')
                  : null,
              icon: const Icon(Icons.cleaning_services_outlined),
              label: const Text('一键清理'),
              style: const ButtonStyle(
                  backgroundColor: WidgetStatePropertyAll(Colors.transparent))),
          const Spacer(),
          if (total != null && used != null)
            Text('已用 ${gib(used)} GB / ${gib(total)} GB',
                style: TextStyle(fontSize: Design.px(20), color: s.muted)),
        ]));
  }
}

class _EmptyTasks extends StatelessWidget {
  const _EmptyTasks();
  @override
  Widget build(BuildContext context) {
    final s = SurfaceStyle.of(context);
    return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
      Icon(Icons.check_circle_outline_rounded,
          size: Design.px(72), color: s.accent),
      SizedBox(height: Design.px(20)),
      Text('暂无最近任务', style: TextStyle(fontSize: Design.px(26), color: s.muted)),
    ]));
  }
}
