import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../controller/launcher_controller.dart';
import '../theme/design_tokens.dart';
import '../theme/launcher_theme.dart';

/// A compact source identity that doubles as the player's launch target.
class MediaSourceBadge extends StatelessWidget {
  final LauncherController controller;
  final bool titleBar;
  final bool compact;
  const MediaSourceBadge(
      {super.key,
      required this.controller,
      this.titleBar = false,
      this.compact = false});
  @override
  Widget build(BuildContext context) =>
      ValueListenableBuilder<Map<String, dynamic>>(
          valueListenable: controller.native,
          builder: (context, state, _) {
            final s = SurfaceStyle.of(context);
            final preferences = state['integrationPreferences'] as Map? ?? {};
            final media = state['media'] as Map? ?? {};
            final preferred = preferences['mediaPackage'];
            final package =
                preferred != null && preferred != 'auto' && preferred != ''
                    ? preferred
                    : media['source'];
            final apps = state['apps'] as List? ?? [];
            final app = apps
                .whereType<Map>()
                .where((a) => a['package'] == package)
                .firstOrNull;
            final icon = app?['iconBytes'] is Uint8List
                ? app!['iconBytes'] as Uint8List
                : null;
            // Order: a user rename, then the label Android resolved for the media
            // session itself, then the package. A car player can publish a session
            // with no launcher entry, and during start-up the app grid may still be
            // empty, so neither case may degrade to a raw package name.
            final sourceLabel = media['sourceLabel'];
            final name = app != null
                ? controller.appName(Map<String, dynamic>.from(app))
                : controller.appNames[package] ??
                    (sourceLabel is String && sourceLabel.isNotEmpty
                        ? sourceLabel
                        : '${package ?? '音乐播放器'}');
            return Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                    key: const ValueKey('media-source-entry'),
                    onPressed: () => controller.command('launch-player'),
                    style: TextButton.styleFrom(
                        foregroundColor: titleBar ? s.text : s.muted,
                        minimumSize: compact ? Size.zero : null,
                        tapTargetSize: compact
                            ? MaterialTapTargetSize.shrinkWrap
                            : MaterialTapTargetSize.padded,
                        padding: EdgeInsets.symmetric(
                            horizontal: Design.px(titleBar ? 4 : 12),
                            vertical: Design.px(compact ? 4 : 8)),
                        backgroundColor:
                            titleBar ? Colors.transparent : s.soft),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      ClipRRect(
                          borderRadius:
                              BorderRadius.circular(s.controlRadius * .5),
                          child: SizedBox(
                              width: Design.px(compact
                                  ? 28
                                  : titleBar
                                      ? 38
                                      : 28),
                              height: Design.px(compact
                                  ? 28
                                  : titleBar
                                      ? 38
                                      : 28),
                              child: icon != null
                                  ? Image.memory(icon,
                                      errorBuilder: (_, __, ___) =>
                                          const Icon(Icons.music_note_outlined))
                                  : const Icon(Icons.music_note_outlined))),
                      SizedBox(width: Design.px(10)),
                      Flexible(
                          child: Text(name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontSize: Design.px(compact
                                      ? 20
                                      : titleBar
                                          ? 28
                                          : 19),
                                  fontWeight: titleBar
                                      ? FontWeight.w500
                                      : FontWeight.normal))),
                      if (!titleBar) SizedBox(width: Design.px(10)),
                      if (titleBar) ...[
                        SizedBox(width: Design.px(16)),
                        Text(media['cached'] == true ? '上次播放' : '正在播放',
                            style: TextStyle(
                                fontSize: Design.px(compact ? 18 : 26),
                                color: s.muted)),
                      ],
                      if (!titleBar)
                        Icon(Icons.open_in_new,
                            size: Design.px(compact ? 15 : 17), color: s.muted)
                    ])));
          });
}
