import 'package:flutter/material.dart';
import '../controller/launcher_controller.dart';
import '../theme/design_tokens.dart';
import '../theme/launcher_theme.dart';
import 'card_content.dart';
import 'glass_surface.dart';
import 'launcher_dialog.dart';
import 'dock_music_visual.dart';
import 'dock_music_progress_background.dart';
import 'uni_app_icon.dart';
import 'file_transfer_popup.dart';
import 'uni_icon.dart';
import 'dock_climate_button.dart';
import 'media_artwork.dart';
import '../model/vehicle_data.dart';
import 'vehicle_readout.dart';
import 'climate_panel.dart';
import 'circulation_icon.dart';
export 'climate_panel.dart' show showClimatePanel;

double _dockContentScale(String size) => switch (size) {
      'medium' => 1.14,
      'large' => 1.3,
      _ => 1.0,
    };

class BottomDock extends StatelessWidget {
  final LauncherController controller;
  const BottomDock({super.key, required this.controller});
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
      animation: Listenable.merge([controller.native, controller.pageChanged]),
      builder: (context, _) {
        final native = controller.native.value,
            c = controller,
            s = SurfaceStyle.of(context),
            demo = native['demo'] == true,
            climate = mapOf(native['climate']),
            media = mapOf(native['media']),
            canPlay = demo || media['available'] == true,
            canToggle = demo || media['canToggle'] == true,
            playing = media['playing'] == true,
            dockScale = _dockContentScale(c.appearance.dockSize);
        Widget gap() => SizedBox(width: Design.px(12));
        Widget action(
                String key, IconData icon, String label, VoidCallback? tap,
                {bool active = false,
                bool framed = true,
                bool solid = false,
                bool soft = false,
                double width = 64}) =>
            IconAction(
                key: ValueKey(key),
                icon: icon,
                label: label,
                size: Design.px(width),
                iconSize: Design.px(29 * dockScale),
                onTap: tap,
                active: active,
                framed: framed,
                solid: solid,
                soft: soft);
        Widget climateGroup(Widget child) => s.technicalFrame
            ? SizedBox(
                height: Design.px(72),
                child: GlassSurface(
                    key: const ValueKey('dock-climate-frame'),
                    radius: s.controlRadius,
                    shadow: false,
                    tone: SurfaceTone.soft,
                    padding: EdgeInsets.symmetric(horizontal: Design.px(12)),
                    child: child))
            : child;
        bool? climateFlag(String id) {
          if (demo) return climate[id] is bool ? climate[id] as bool : null;
          final field = VehicleField.fromNative(native, id);
          return field.valid && field.value is bool
              ? field.value as bool
              : null;
        }

        Widget zone(String id, String label) => IconAction(
            key: ValueKey('dock-temperature-$id'),
            icon: Icons.device_thermostat,
            label: '$label温度',
            size: Design.px(72),
            framed: false,
            onTap: () => showClimatePanel(context, c),
            child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                    demo
                        ? '${(climate[id] as num? ?? 22.5).toStringAsFixed(1)}°'
                        : (VehicleField.fromNative(native, id).valid
                            ? VehicleField.fromNative(native, id).display()
                            : climate[id] is num
                                ? (climate[id] as num).toStringAsFixed(1)
                                : '—'),
                    maxLines: 1,
                    style: TextStyle(
                        fontSize: Design.px(30 * dockScale),
                        color: demo || VehicleField.fromNative(native, id).valid
                            ? s.text
                            : s.disabled))));
        final ac = climateFlag('ac'), recirc = climateFlag('recirc');
        Widget climateIndicator(
                String id, String mode, Widget child, String label) =>
            IconAction(
                key: ValueKey(id),
                icon: Icons.air,
                label: label,
                size: Design.px(72),
                framed: false,
                onTap: climateWritable(native, mode)
                    ? () => c.command('climate-mode', value: mode)
                    : null,
                child: FittedBox(fit: BoxFit.scaleDown, child: child));
        // 胶囊底栏：左右留边、四角半圆、底下离屏幕一条缝。外层 SizedBox
        // 的高度仍是 96，留白做在它里面，所以上面的卡片区尺寸不受影响。
        return SizedBox(
            key: const ValueKey('bottom-dock'),
            height: Design.px(96),
            child: Padding(
                padding: EdgeInsets.fromLTRB(
                    Design.px(16), 0, Design.px(16), Design.px(10)),
                child: GlassSurface(
                    dock: true,
                    // 胶囊的圆角吃「圆角」设置：暗夜默认 25，高度 72 的一半
                    // 是 36，看起来就是全圆角胶囊。滑到 0 时给一个兜底——
                    // 底栏已经是浮起的一条，纯方角会散开，所以退回首版的
                    // 43（≈半径 36）保持胶囊形状。
                    radius: s.radius == 0 ? Design.px(43) : s.radius,
                    shadow: true,
                    tone: SurfaceTone.strong,
                padding: EdgeInsets.symmetric(
                    horizontal: Design.px(14), vertical: Design.px(7)),
                    child: Row(children: [
                      SizedBox(
                          width: Design.px(352),
                          child: Row(children: [
                            action('system-back', Icons.arrow_back, '返回',
                                () => c.command('system-back')),
                            SizedBox(width: Design.px(6)),
                            IconAction(
                                key: const ValueKey('home'),
                                icon: Icons.home_outlined,
                                label: '首页，长按进入桌面设置',
                                size: Design.px(72),
                                iconSize: Design.px(29 * dockScale),
                                framed: false,
                                active: c.isGlobalDock
                                    ? native['desktopSelected'] == true &&
                                        mapOf(native['globalDock'])[
                                                'expanded'] !=
                                            true
                                    : !c.settings &&
                                        c.page == 0 &&
                                        (ModalRoute.of(context)?.isCurrent ??
                                            true),
                                soft: false,
                                onTap: c.home,
                                onLongPress: c.openSettings),
                            SizedBox(width: Design.px(6)),
                            action('all-apps', Icons.apps, '全部应用',
                                () => showAppsPanel(context, c)),
                            SizedBox(width: Design.px(6)),
                            action(
                                'recents',
                                Icons.check_box_outline_blank_rounded,
                                '最近任务',
                                () => c.command('show-recents')),
                            SizedBox(width: Design.px(6)),
                            action(
                                'camera',
                                Icons.surround_sound_outlined,
                                '360 影像',
                                () =>
                                    c.command('open-official', value: 'camera'))
                          ])),
                      gap(),
                      Expanded(
                          flex: 5,
                          child: climateGroup(Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                climateIndicator(
                                    'dock-ac-indicator',
                                    'ac',
                                    Text('A/C',
                                        maxLines: 1,
                                        style: TextStyle(
                                            fontSize: Design.px(17 * dockScale),
                                            fontWeight: FontWeight.w600,
                                            color:
                                                !climateWritable(native, 'ac')
                                                    ? s.disabled
                                                    : ac == true
                                                        ? s.accent
                                                        : s.muted)),
                                    ac == null
                                        ? '空调制冷状态未知'
                                        : (ac ? '空调制冷开启' : '空调制冷关闭')),
                                zone('left', '主驾'),
                                DockClimateButton(
                                    controller: c,
                                    native: native,
                                    scale: dockScale),
                                climateIndicator(
                                    'dock-circulation-indicator',
                                    'recirc',
                                    CirculationIcon(
                                        recirculating: recirc,
                                        color:
                                            !climateWritable(native, 'recirc')
                                                ? s.disabled
                                                : recirc == null
                                                    ? s.muted
                                                    : s.accent,
                                        size: Design.px(28 * dockScale)),
                                    recirc == null
                                        ? '空气循环状态未知'
                                        : (recirc ? '内循环' : '外循环')),
                                zone('right', '副驾'),
                                action(
                                    'climate-power',
                                    Icons.power_settings_new,
                                    '空调开关',
                                    climateWritable(native, 'power')
                                        ? () => c.command('climate-power')
                                        : null,
                                    active: climate['power'] == true,
                                    framed: false,
                                    width: 72)
                              ]))),
                      gap(),
                      Expanded(
                          flex: 8,
                          child: GlassSurface(
                              key: const ValueKey('dock-music-frame'),
                              radius: s.controlRadius,
                              shadow: false,
                              // 暗夜下这一块不画表面：胶囊已经是不透明背板，
                              // 再叠一层白玻璃会在胶囊里亮出一块方形。
                              flat: true,
                              tone: SurfaceTone.soft,
                              padding: EdgeInsets.zero,
                              child: DockMusicProgressBackground(
                                  enabled:
                                      c.appearance.dockMusicProgressBackground,
                                  media: media,
                                  child: Padding(
                                      padding: EdgeInsets.symmetric(
                                          horizontal: Design.px(12)),
                                      child: Row(children: [
                                        SizedBox(
                                            width: Design.px(194),
                                            child: Row(
                                                mainAxisAlignment:
                                                    MainAxisAlignment
                                                        .spaceBetween,
                                                children: [
                                                  action(
                                                      'previous',
                                                      Icons
                                                          .skip_previous_outlined,
                                                      '上一首',
                                                      canPlay &&
                                                              (demo ||
                                                                  media['canPrevious'] ==
                                                                      true)
                                                          ? () => c.command(
                                                              'previous')
                                                          : null,
                                                      width: 60),
                                                  IconAction(
                                                      key: const ValueKey(
                                                          'play-pause'),
                                                      icon: playing
                                                          ? Icons.pause
                                                          : Icons.play_arrow,
                                                      label:
                                                          playing ? '暂停' : '播放',
                                                      size: Design.px(58),
                                                      iconSize: Design.px(
                                                          29 * dockScale),
                                                      framed: false,
                                                      foregroundColor: s.accent,
                                                      onTap: media[
                                                                  'available'] ==
                                                              true
                                                          ? (canToggle
                                                              ? () => c.command(
                                                                  'toggle-play')
                                                              : null)
                                                          : () => c.command(
                                                              'toggle-play')),
                                                  action(
                                                      'next',
                                                      Icons.skip_next_outlined,
                                                      '下一首',
                                                      canPlay &&
                                                              (demo ||
                                                                  media['canNext'] ==
                                                                      true)
                                                          ? () =>
                                                              c.command('next')
                                                          : null,
                                                      width: 60)
                                                ])),
                                        SizedBox(width: Design.px(20)),
                                        Expanded(
                                            child: InkWell(
                                                key: const ValueKey(
                                                    'music-info'),
                                                onTap: () =>
                                                    showMediaPanel(context, c),
                                                child: Row(children: [
                                                  ClipRRect(
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                              s.radius * .5),
                                                      child: SizedBox(
                                                          width: Design.px(60),
                                                          height: Design.px(60),
                                                          child: MediaArtwork(
                                                              media: media,
                                                              demo: demo,
                                                              fallbackSize:
                                                                  Design.px(
                                                                      30)))),
                                                  SizedBox(
                                                      width: Design.px(16)),
                                                  Expanded(
                                                      flex: 5,
                                                      child: Column(
                                                          key: const ValueKey(
                                                              'dock-track-title'),
                                                          mainAxisAlignment:
                                                              MainAxisAlignment
                                                                  .center,
                                                          crossAxisAlignment:
                                                              CrossAxisAlignment
                                                                  .start,
                                                          children: [
                                                            Text(
                                                                '${media['title'] ?? '暂无播放'}',
                                                                style: TextStyle(
                                                                    fontSize: Design
                                                                        .px(23 *
                                                                            dockScale),
                                                                    fontWeight:
                                                                        FontWeight
                                                                            .w500),
                                                                maxLines: 1,
                                                                overflow:
                                                                    TextOverflow
                                                                        .ellipsis),
                                                            SizedBox(
                                                                height:
                                                                    Design.px(
                                                                        4)),
                                                            Text(
                                                                '${media['artist'] ?? '等待媒体会话'}',
                                                                style: TextStyle(
                                                                    fontSize: Design
                                                                        .px(16 *
                                                                            dockScale),
                                                                    color: s
                                                                        .muted),
                                                                maxLines: 1,
                                                                overflow:
                                                                    TextOverflow
                                                                        .ellipsis)
                                                          ])),
                                                  SizedBox(
                                                      width: Design.px(16)),
                                                  Expanded(
                                                      flex: 6,
                                                      child: DockMusicVisual(
                                                          media: media,
                                                          demo: demo))
                                                ])))
                                      ]))))),
                      gap(),
                      IconAction(
                          key: const ValueKey('uni-menu'),
                          icon: Icons.apps,
                          label: 'UNI菜单，包含车辆信息和UNI桌面设置',
                          size: Design.px(64),
                          framed: false,
                          onTap: () => showUniDockMenu(context, c),
                          child: UniAppIcon(size: Design.px(42 * dockScale)))
                    ]))));
      });
}

Future<void> showUniDockMenu(BuildContext context, LauncherController c) async {
  if (await c.presentGlobalPanel('uni-menu') || !context.mounted) return;
  final selection = await _showUniDockPopup(context, c);
  if (!context.mounted) return;
  if (selection == 'vehicle') {
    await showVehiclePanel(context, c);
  } else if (selection == 'transfer') {
    await showFileTransferPopup(context, c);
  } else if (selection == 'settings') {
    if (c.isGlobalDock) {
      await c.command('show-desktop-settings');
    } else {
      c.openSettings();
    }
  }
}

/// Anchored popup that expands above the UNI dock button.
Future<String?> _showUniDockPopup(BuildContext context, LauncherController c) {
  return Navigator.of(context).push(_UniDockPopupRoute(
      panelWindow: c.native.value['hostMode'] == 'global-panel',
      scale: _dockContentScale(c.appearance.dockSize)));
}

class _UniDockPopupRoute extends PopupRoute<String> {
  final bool panelWindow;
  final double scale;
  _UniDockPopupRoute({required this.panelWindow, required this.scale});
  @override
  Color? get barrierColor => null;
  @override
  bool get barrierDismissible => true;
  @override
  String? get barrierLabel => '关闭UNI菜单';
  @override
  Duration get transitionDuration => const Duration(milliseconds: 180);
  @override
  Duration get reverseTransitionDuration => const Duration(milliseconds: 140);
  @override
  Widget buildPage(BuildContext context, Animation<double> animation,
      Animation<double> secondaryAnimation) {
    final s = SurfaceStyle.of(context);
    return Stack(children: [
      Positioned(
        right: Design.px(14),
        bottom: Design.px(panelWindow ? 14 : 110),
        child: SizedBox(
            width: Design.px(340),
            child: GlassSurface(
                key: const ValueKey('uni-popup-panel'),
                radius: s.controlRadius,
                shadow: true,
                padding: EdgeInsets.all(Design.px(10)),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  _UniPopupItem(
                      key: const ValueKey('uni-menu-vehicle'),
                      icon: UniIcon('car', size: Design.px(29 * scale)),
                      title: '车辆信息',
                      scale: scale,
                      onTap: () => Navigator.pop(context, 'vehicle')),
                  SizedBox(height: Design.px(8)),
                  _UniPopupItem(
                      key: const ValueKey('uni-menu-transfer'),
                      icon:
                          Icon(Icons.upload_file, size: Design.px(29 * scale)),
                      title: '传文件',
                      scale: scale,
                      onTap: () => Navigator.pop(context, 'transfer')),
                  SizedBox(height: Design.px(8)),
                  _UniPopupItem(
                      key: const ValueKey('uni-menu-settings'),
                      icon: UniAppIcon(size: Design.px(29 * scale)),
                      title: 'UNI桌面设置',
                      scale: scale,
                      onTap: () => Navigator.pop(context, 'settings')),
                ]))),
      ),
    ]);
  }

  @override
  Widget buildTransitions(BuildContext context, Animation<double> animation,
      Animation<double> secondaryAnimation, Widget child) {
    final t = Curves.easeOutCubic.transform(animation.value);
    return FadeTransition(
        opacity: animation,
        child: Transform.translate(
            offset: Offset(0, (1 - t) * Design.px(14)),
            child: Transform.scale(
                alignment: Alignment.bottomRight,
                scale: .94 + .06 * t,
                child: child)));
  }
}

class _UniPopupItem extends StatelessWidget {
  final Widget icon;
  final String title;
  final double scale;
  final VoidCallback onTap;
  const _UniPopupItem(
      {super.key,
      required this.icon,
      required this.title,
      required this.scale,
      required this.onTap});
  @override
  Widget build(BuildContext context) {
    final s = SurfaceStyle.of(context);
    return Material(
        color: Colors.transparent,
        child: InkWell(
            borderRadius: BorderRadius.circular(s.controlRadius),
            onTap: onTap,
            child: Padding(
                padding: EdgeInsets.symmetric(
                    horizontal: Design.px(14), vertical: Design.px(10)),
                child: Row(children: [
                  SizedBox(
                      width: Design.px(42 * scale),
                      height: Design.px(42 * scale),
                      child: Center(child: icon)),
                  SizedBox(width: Design.px(12)),
                  Expanded(
                      child: Text(title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: Design.px(23 * scale),
                              fontWeight: FontWeight.w500)))
                ]))));
  }
}

Future<void> showVehiclePanel(
    BuildContext context, LauncherController c) async {
  if (await c.presentGlobalPanel('vehicle') || !context.mounted) return;
  await showLauncherSheet<void>(context,
      title: '车辆信息',
      subtitle: '车辆数据 · 只读',
      closeLabel: '关闭车辆信息',
      width: Design.px(900),
      height: Design.px(780),
      glowType: 'vehicle',
      builder: (context) => ValueListenableBuilder<Map<String, dynamic>>(
          valueListenable: c.native,
          builder: (context, n, _) =>
              VehicleReadout(controller: c, native: n)));
}
