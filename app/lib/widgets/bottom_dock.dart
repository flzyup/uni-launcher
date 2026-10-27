import 'package:flutter/material.dart';
import '../controller/launcher_controller.dart';
import '../theme/design_tokens.dart';
import '../theme/launcher_theme.dart';
import 'card_content.dart';
import 'glass_surface.dart';
import 'launcher_dialog.dart';
import 'dock_music_visual.dart';
import 'dock_climate_button.dart';
import 'media_artwork.dart';
import '../model/vehicle_data.dart';
import 'vehicle_readout.dart';
import 'climate_panel.dart';
import 'circulation_icon.dart';
export 'climate_panel.dart' show showClimatePanel;

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
            playing = media['playing'] == true;
        Widget gap() => SizedBox(width: Design.px(20));
        Widget separator() => SizedBox(
            height: Design.px(34),
            width: Design.px(1),
            child: ColoredBox(color: s.edge));
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
                iconSize: Design.px(29),
                onTap: tap,
                active: active,
                framed: framed,
                solid: solid,
                soft: soft);
        Widget climateGroup(Widget child) => s.technicalFrame
            ? GlassSurface(
                radius: s.controlRadius,
                shadow: false,
                tone: SurfaceTone.soft,
                padding: EdgeInsets.symmetric(horizontal: Design.px(12)),
                child: child)
            : child;
        bool? climateFlag(String id) {
          if (demo) return climate[id] is bool ? climate[id] as bool : null;
          final field = VehicleField.fromNative(native, id);
          return field.valid && field.value is bool
              ? field.value as bool
              : null;
        }

        Widget zone(String id, String label) => SizedBox(
            width: Design.px(82),
            height: Design.px(64),
            child: InkWell(
                key: ValueKey('dock-temperature-$id'),
                onTap: () => showClimatePanel(context, c),
                child: Center(
                    child: Text(
                        demo
                            ? '${(climate[id] as num? ?? 22.5).toStringAsFixed(1)}°'
                            : '${VehicleField.fromNative(native, id).display()}°',
                        maxLines: 1,
                        style: TextStyle(fontSize: Design.px(30))))));
        final ac = climateFlag('ac'), recirc = climateFlag('recirc');
        Widget climateIndicator(
                String id, String mode, Widget child, String label) =>
            IconAction(
                key: ValueKey(id),
                icon: Icons.air,
                label: label,
                size: Design.px(46),
                framed: false,
                onTap: climateWritable(native, mode)
                    ? () => c.command('climate-mode', value: mode)
                    : null,
                child: child);
        return SizedBox(
            key: const ValueKey('bottom-dock'),
            height: Design.px(96),
            child: GlassSurface(
                dock: true,
                radius: 0,
                shadow: false,
                tone: SurfaceTone.strong,
                padding: EdgeInsets.symmetric(
                    horizontal: Design.px(28), vertical: Design.px(12)),
                child: Row(children: [
                  SizedBox(
                      width: Design.px(376),
                      child: Row(children: [
                        action('system-back', Icons.arrow_back, '返回',
                            () => c.command('system-back')),
                        SizedBox(width: Design.px(14)),
                        IconAction(
                            key: const ValueKey('home'),
                            icon: Icons.home_outlined,
                            label: '首页，长按进入桌面设置',
                            size: Design.px(64),
                            iconSize: Design.px(29),
                            active: c.isGlobalDock
                                ? native['desktopSelected'] == true &&
                                    mapOf(native['globalDock'])['expanded'] !=
                                        true
                                : !c.settings &&
                                    c.page == 0 &&
                                    (ModalRoute.of(context)?.isCurrent ?? true),
                            soft: c.isGlobalDock
                                ? native['desktopSelected'] == true &&
                                    mapOf(native['globalDock'])['expanded'] !=
                                        true
                                : !c.settings &&
                                    c.page == 0 &&
                                    (ModalRoute.of(context)?.isCurrent ?? true),
                            onTap: c.home,
                            onLongPress: c.openSettings),
                        SizedBox(width: Design.px(14)),
                        action('all-apps', Icons.apps, '全部应用',
                            () => showAppsPanel(context, c)),
                        SizedBox(width: Design.px(14)),
                        action('recents', Icons.check_box_outline_blank_rounded,
                            '最近任务', () => c.command('show-recents')),
                        SizedBox(width: Design.px(14)),
                        action(
                            'camera',
                            Icons.surround_sound_outlined,
                            '360 影像',
                            () => c.command('open-official', value: 'camera'))
                      ])),
                  gap(),
                  separator(),
                  gap(),
                  SizedBox(
                      width: Design.px(480),
                      child: climateGroup(Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            climateIndicator(
                                'dock-ac-indicator',
                                'ac',
                                Text('A/C',
                                    maxLines: 1,
                                    style: TextStyle(
                                        fontSize: Design.px(17),
                                        fontWeight: FontWeight.w600,
                                        color:
                                            ac == true ? s.accent : s.muted)),
                                ac == null
                                    ? '空调制冷状态未知'
                                    : (ac ? '空调制冷开启' : '空调制冷关闭')),
                            zone('left', '主驾'),
                            DockClimateButton(controller: c, native: native),
                            climateIndicator(
                                'dock-circulation-indicator',
                                'recirc',
                                CirculationIcon(
                                    recirculating: recirc,
                                    color: recirc == null ? s.muted : s.accent,
                                    size: Design.px(28)),
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
                                framed: !s.technicalFrame,
                                width: 56)
                          ]))),
                  gap(),
                  separator(),
                  gap(),
                  SizedBox(
                      width: Design.px(194),
                      child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            action(
                                'previous',
                                Icons.skip_previous_outlined,
                                '上一首',
                                canPlay &&
                                        (demo || media['canPrevious'] == true)
                                    ? () => c.command('previous')
                                    : null,
                                width: 60),
                            action(
                                'play-pause',
                                playing ? Icons.pause : Icons.play_arrow,
                                playing ? '暂停' : '播放',
                                canPlay && (demo || media['canToggle'] == true)
                                    ? () => c.command('toggle-play')
                                    : null,
                                solid: true,
                                width: 58),
                            action(
                                'next',
                                Icons.skip_next_outlined,
                                '下一首',
                                canPlay && (demo || media['canNext'] == true)
                                    ? () => c.command('next')
                                    : null,
                                width: 60)
                          ])),
                  gap(),
                  Expanded(
                      child: InkWell(
                          key: const ValueKey('music-info'),
                          onTap: () => showMediaPanel(context, c),
                          child: Row(children: [
                            ClipRRect(
                                borderRadius:
                                    BorderRadius.circular(s.radius * .5),
                                child: SizedBox(
                                    width: Design.px(60),
                                    height: Design.px(60),
                                    child: MediaArtwork(
                                        media: media,
                                        demo: demo,
                                        fallbackSize: Design.px(30)))),
                            SizedBox(width: Design.px(16)),
                            Expanded(
                                flex: 5,
                                child: Column(
                                    key: const ValueKey('dock-track-title'),
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text('${media['title'] ?? '暂无播放'}',
                                          style: TextStyle(
                                              fontSize: Design.px(23),
                                              fontWeight: FontWeight.w500),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis),
                                      SizedBox(height: Design.px(4)),
                                      Text('${media['artist'] ?? '等待媒体会话'}',
                                          style: TextStyle(
                                              fontSize: Design.px(16),
                                              color: s.muted),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis)
                                    ])),
                            SizedBox(width: Design.px(16)),
                            Expanded(
                                flex: 6,
                                child:
                                    DockMusicVisual(media: media, demo: demo))
                          ]))),
                  gap(),
                  separator(),
                  gap(),
                  action('vehicle', Icons.directions_car_outlined, '车辆信息',
                      () => showVehiclePanel(context, c))
                ])));
      });
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
      builder: (context) => ValueListenableBuilder<Map<String, dynamic>>(
          valueListenable: c.native,
          builder: (context, n, _) =>
              VehicleReadout(controller: c, native: n)));
}
