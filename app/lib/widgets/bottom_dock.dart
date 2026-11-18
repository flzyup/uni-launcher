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
import 'dock_nav_icons.dart';
import 'dock_window_scope.dart';
import 'native_slice_builder.dart';
import 'media_artwork.dart';
import 'marquee_text.dart';
import '../model/vehicle_data.dart';
import '../model/lyric_timeline.dart';
import '../model/lyrics.dart';
import 'vehicle_readout.dart';
import 'climate_panel.dart';
import 'circulation_icon.dart';
export 'climate_panel.dart' show showClimatePanel;

double _dockContentScale(String size) => switch (size) {
      'medium' => 1.14,
      'large' => 1.3,
      'extraLarge' => 1.45,
      _ => 1.0,
    };

/// 底栏当前一句歌词（非逐字）。
///
/// 三级取词：原生推送的 `lyricLine` 优先；其次按播放进度在逐字时间轴里取当前行；
/// 再次在 LRC 文本里取当前行；都没有则返回空串，由调用方回退显示歌手。
/// 不持有任何定时器——播放进度随原生推送的 media map 一并刷新，
/// 底栏本就监听 `controller.native` 重建，无需额外时钟。
String _dockCurrentLyric(Map<String, dynamic> media) {
  final live = media['lyricLine']?.toString().trim() ?? '';
  if (live.isNotEmpty) return live;
  final position = MediaTimeline.fromJson(media)
      .at(DateTime.now().millisecondsSinceEpoch);
  final timeline = LyricTimeline.parse(media['lyricTimeline']);
  if (timeline.lines.isNotEmpty) {
    final text = timeline.at(position).text.trim();
    if (text.isNotEmpty) return text;
  }
  final lyrics = Lyrics.parse(media['lyrics']);
  if (lyrics.timed && lyrics.lines.isNotEmpty) {
    final active = lyrics.activeAt(position);
    if (active >= 0) return lyrics.lines[active].text.trim();
  }
  return '';
}

class BottomDock extends StatelessWidget {
  final LauncherController controller;
  const BottomDock({super.key, required this.controller});
  @override
  Widget build(BuildContext context) => ListenableBuilder(
      listenable: controller.pageChanged,
      builder: (context, _) => NativeSliceBuilder(
          valueListenable: controller.native,
          select: (n) => [
                n['demo'],
                n['climate'],
                mapOf(n['vehicle'])['climate'],
                mapOf(n['vehicle'])['fields'],
                mapOf(n['vehicle'])['writable'],
                n['media'],
                n['desktopSelected'],
                mapOf(n['globalDock'])['expanded'],
              ],
          builder: (context, native) {
        final c = controller,
            s = SurfaceStyle.of(context),
            demo = native['demo'] == true,
            climate = mapOf(native['climate']),
            media = mapOf(native['media']),
            panelExpanded = mapOf(native['globalDock'])['expanded'] == true,
            canPlay = demo || media['available'] == true,
            canToggle = demo || media['canToggle'] == true,
            playing = media['playing'] == true,
            dockScale = _dockContentScale(c.appearance.dockSize),
            showMusicVisual = c.appearance.dockMusicVisual,
            lyric = _dockCurrentLyric(media);
        Widget gap() => SizedBox(width: Design.px(12));
        // 导航键不带外框（用户口径：悬停/常态都不要框），选中态仅靠
        // IconAction 的 active 高亮（accent 图标色 + 悬停浅底）。
        final navFg = s.text.withValues(alpha: .8);
        Widget navBtn(String key, Widget icon, String label, VoidCallback? tap,
                {bool active = false, VoidCallback? longPress}) =>
            IconAction(
                key: ValueKey(key),
                icon: Icons.circle,
                label: label,
                size: Design.px(64),
                iconSize: Design.px(31 * dockScale),
                framed: false,
                active: active,
                onTap: tap,
                onLongPress: longPress,
                child: Center(child: icon));
        // 设计稿 .dk-sep：1×32 画布，左 margin 4、右 margin 13（画布值）。
        // 右边留得比左边宽是**有意的**：空调胶囊收紧后，分隔线贴着胶囊会显得
        // 挤在导航和胶囊中间（2026-11-15 用户口径：「放到之前两根的左边一根」）。
        Widget sep() => Container(
            key: const ValueKey('dock-sep'),
            width: Design.px(1),
            height: Design.px(38),
            margin:
                EdgeInsets.only(left: Design.px(5), right: Design.px(16)),
            color: s.edge);
        Widget action(
                String key, IconData icon, String label, VoidCallback? tap,
                {bool active = false,
                bool framed = true,
                bool solid = false,
                bool soft = false,
                double width = 64,
                double iconScale = 29}) =>
            IconAction(
                key: ValueKey(key),
                icon: icon,
                label: label,
                size: Design.px(width),
                iconSize: Design.px(iconScale * dockScale),
                onTap: tap,
                active: active,
                framed: framed,
                solid: solid,
                soft: soft);
        // 空调胶囊：三套皮肤同结构，只有面与描边按材质表取色。
        // blueGlass 原来的技术框保留（那是它自己的装饰，不改）。
        // 左右留白 20（1920 口径）= 画布 17，六格在中间平分。
        Widget climateGroup(Widget child) => s.technicalFrame
            ? SizedBox(
                height: Design.px(72),
                child: GlassSurface(
                    key: const ValueKey('dock-climate-frame'),
                    radius: s.controlRadius,
                    shadow: false,
                    tone: SurfaceTone.soft,
                    padding:
                        EdgeInsets.symmetric(horizontal: Design.px(20)),
                    child: child))
            : SizedBox(
                height: Design.px(72),
                child: DecoratedBox(
                    key: const ValueKey('dock-climate-capsule'),
                    decoration: BoxDecoration(
                        color: s.material.capsule,
                        borderRadius: BorderRadius.circular(s.controlRadius),
                        border:
                            Border.all(color: s.material.capsuleEdge)),
                    child: Padding(
                        padding:
                            EdgeInsets.symmetric(horizontal: Design.px(20)),
                        child: child)));
        bool? climateFlag(String id) {
          if (demo) return climate[id] is bool ? climate[id] as bool : null;
          final field = VehicleField.fromNative(native, id);
          return field.valid && field.value is bool
              ? field.value as bool
              : null;
        }

        // 温度块：设计稿是「主驾 / 22.5°」两行，实车上去掉了「主驾 / 副驾」
        // 两个中文字——两边都只剩温度，靠左右位置区分。宽度由字号撑开
        // （不再塞进 72 方格），所以 `22.5°` 的度数不会再被格子裁掉。
        // 外套一层 scaleDown 上限：字体异常宽（或换成更宽的字形）时缩字，
        // 绝不把胶囊撑破——胶囊是定宽的。
        // 触摸提示里仍带「主驾温度 / 副驾温度」，无障碍读屏不受影响。
        Widget temperatureText(String id) => ConstrainedBox(
            constraints: BoxConstraints(maxWidth: Design.dz(66)),
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
                    softWrap: false,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: Design.px(26 * dockScale),
                        fontWeight: FontWeight.w500,
                        height: 1.05,
                        color: demo || VehicleField.fromNative(native, id).valid
                            ? s.text.withValues(alpha: .55)
                            : s.disabled))));
        final ac = climateFlag('ac'), recirc = climateFlag('recirc');
        // 胶囊里的一格：**宽度由内容撑开**，高度撑满胶囊。
        // 六格交给 `Row(spaceBetween)` 平分剩余空间，视觉间距因此完全相同；
        // 命中区取整格高度（72 = 画布 60），宽度跟内容走。
        Widget capsuleItem(
                String key, String label, VoidCallback? onTap, Widget child) =>
            Tooltip(
                message: label,
                child: Semantics(
                    button: true,
                    label: label,
                    enabled: onTap != null,
                    child: SizedBox(
                        key: ValueKey(key),
                        height: Design.px(72),
                        child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                                borderRadius:
                                    BorderRadius.circular(s.controlRadius),
                                onTap: onTap,
                                hoverColor: s.accent.withValues(alpha: .08),
                                focusColor: s.accent.withValues(alpha: .16),
                                highlightColor: s.accent.withValues(alpha: .24),
                                splashColor: s.accent.withValues(alpha: .16),
                                overlayColor: WidgetStateProperty.resolveWith(
                                    (states) => s.accent.withValues(
                                        alpha: states
                                                .contains(WidgetState.pressed)
                                            ? .24
                                            : .08)),
                                child: Center(child: child))))));
        // 风扇格：**永远是「四瓣花 + 七根柱」**。
        // 原来自动空调时这里会换成一颗 AUTO 胶囊，等于七项挤在六格的位置上，
        // A/C 被顶到贴边框、电源右边空一大截（2026-11-15 用户口径：AUTO 多余）。
        // AUTO 开关挪回空调面板里，底栏这一格只负责「看风量 / 进面板」。
        final Widget fanSlot =
            DockFanCluster(controller: c, native: native, scale: dockScale);
        final Widget trackMetadata = Column(
            key: const ValueKey('dock-track-title'),
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              MarqueeText(
                  key: const ValueKey('dock-track-marquee'),
                  data: '${media['title'] ?? '暂无播放'}',
                  style: TextStyle(
                      fontSize: Design.px(23 * dockScale),
                      fontWeight: FontWeight.w500)),
              SizedBox(height: Design.px(4)),
              // 有歌词时第二行显示当前一句歌词（非逐字），无歌词回退歌手。
              MarqueeText(
                  key: const ValueKey('dock-artist-marquee'),
                  data: lyric.isNotEmpty
                      ? lyric
                      : '${media['artist'] ?? '等待媒体会话'}',
                  style: TextStyle(
                      fontSize: Design.px(14 * dockScale),
                      color: lyric.isNotEmpty
                          ? s.accent.withValues(alpha: .62)
                          : s.muted))
            ]);
        final Widget musicInfo = InkWell(
            key: const ValueKey('music-info'),
            onTap: () => showMusicPlayer(context, c),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              ClipRRect(
                  borderRadius: BorderRadius.circular(Design.px(16)),
                  child: SizedBox(
                      width: Design.px(55),
                      height: Design.px(55),
                      child: MediaArtwork(media: media, demo: demo))),
              SizedBox(width: Design.px(16)),
              showMusicVisual
                  ? Expanded(child: trackMetadata)
                  : ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: Design.px(320)),
                      child: trackMetadata),
              if (showMusicVisual) ...[
                SizedBox(width: Design.px(16)),
                Expanded(child: DockMusicVisual(media: media, demo: demo))
              ]
            ]));
        final floating = c.appearance.dockLayout == 'floating';
        // The reserved strip stays the same height in both modes.
        return SizedBox(
            key: const ValueKey('bottom-dock'),
            height: Design.px(96),
            child: Padding(
                padding: floating
                    ? EdgeInsets.symmetric(
                        horizontal: Design.px(16), vertical: Design.px(5))
                    : EdgeInsets.zero,
                child: GlassSurface(
                    key: const ValueKey('dock-surface'),
                    dock: true,
                    dockFramed: floating,
                    radius: floating ? s.radius : 0,
                    shadow: floating,
                    tone: SurfaceTone.strong,
                    padding: EdgeInsets.symmetric(
                        horizontal: Design.px(14), vertical: Design.px(7)),
                    child: Row(children: [
                      // 设计稿 .dk-b：5 个 64 方格键，间距 12，后接分隔线。
                      Row(mainAxisSize: MainAxisSize.min, children: [
                        navBtn(
                            'system-back',
                            NavChevronIcon(
                                size: Design.px(31 * dockScale),
                                color: navFg),
                            '返回', () => c.command('system-back')),
                        SizedBox(width: Design.px(12)),
                        Builder(builder: (context) {
                          final homeActive = c.isGlobalDock
                              ? native['desktopSelected'] == true &&
                                  mapOf(native['globalDock'])['expanded'] !=
                                      true
                              : !c.settings &&
                                  c.page == 0 &&
                                  (ModalRoute.of(context)?.isCurrent ?? true);
                          return navBtn(
                              'home',
                              NavHomeIcon(
                                  size: Design.px(31 * dockScale),
                                  color:
                                      homeActive ? s.accent : navFg),
                              '首页，长按进入桌面设置', c.home,
                              active: homeActive, longPress: c.openSettings);
                        }),
                        SizedBox(width: Design.px(12)),
                        navBtn(
                            'all-apps',
                            NavAppsDotsIcon(
                                size: Design.px(31 * dockScale),
                                color: navFg),
                            '全部应用', () => showAppsPanel(context, c)),
                        SizedBox(width: Design.px(12)),
                        navBtn(
                            'recents',
                            NavRecentsIcon(
                                size: Design.px(31 * dockScale),
                                color: navFg),
                            '最近任务', () => c.command('show-recents')),
                        SizedBox(width: Design.px(12)),
                        navBtn(
                            'camera',
                            NavCamera360Icon(
                                size: Design.px(31 * dockScale),
                                color: navFg),
                            '360 影像',
                            () => c.command('open-official', value: 'camera')),
                        sep()
                      ]),
                      // 空调胶囊**定宽** 551（= 画布 459，即上游 flex 5:8 分出来的
                      // 那一半），内部六格 spaceBetween 平分：稿面实测左右留白 17、
                      // 相邻间距 38（画布口径），视觉完全等距。
                      // 媒体胶囊吃掉剩余宽度（flex 8）。
                      climateGroup(SizedBox(
                          // 551 是含留白的外宽，这里减掉 climateGroup 的 20×2。
                          width: Design.px(551 - 20 * 2),
                          child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                capsuleItem(
                                    'dock-ac-indicator',
                                    ac == null
                                        ? '空调制冷状态未知'
                                        : (ac ? '空调制冷开启' : '空调制冷关闭'),
                                    climateWritable(native, 'ac')
                                        ? () => c.command('climate-mode',
                                            value: 'ac')
                                        : null,
                                    ConstrainedBox(
                                        constraints:
                                            BoxConstraints(maxWidth: Design.dz(44)),
                                        child: FittedBox(
                                            fit: BoxFit.scaleDown,
                                            child: Text('A/C',
                                                maxLines: 1,
                                                softWrap: false,
                                                style: TextStyle(
                                                    fontSize: Design.px(
                                                        17 * dockScale),
                                                    fontWeight:
                                                        FontWeight.w700,
                                                    letterSpacing:
                                                        Design.px(1.02),
                                                    color: !climateWritable(
                                                            native, 'ac')
                                                        ? s.disabled
                                                        : ac == true
                                                            ? s.accent
                                                            : s.muted))))),
                                capsuleItem('dock-temperature-left', '主驾温度',
                                    () => showClimatePanel(context, c),
                                    temperatureText('left')),
                                fanSlot,
                                capsuleItem(
                                    'dock-circulation-indicator',
                                    recirc == null
                                        ? '空气循环状态未知'
                                        : (recirc ? '内循环' : '外循环'),
                                    climateWritable(native, 'recirc')
                                        ? () => c.command('climate-mode',
                                            value: 'recirc')
                                        : null,
                                    CirculationIcon(
                                        recirculating: recirc,
                                        color:
                                            !climateWritable(native, 'recirc')
                                                ? s.disabled
                                                : recirc == null
                                                    ? s.muted
                                                    : s.accent,
                                        // 稿面 37.3×23.3（1.6 : 1），
                                        // 所以 size 给高度 23.3 画布口径。
                                        size: Design.px(28 * dockScale))),
                                capsuleItem('dock-temperature-right', '副驾温度',
                                    () => showClimatePanel(context, c),
                                    temperatureText('right')),
                                capsuleItem(
                                    'climate-power',
                                    '空调开关',
                                    climateWritable(native, 'power')
                                        ? () => c.command('climate-power')
                                        : null,
                                    DesignIcon(Icons.power_settings_new,
                                        size: Design.px(31.2 * dockScale),
                                        color: !climateWritable(
                                                native, 'power')
                                            ? s.disabled
                                            : climate['power'] == true
                                                ? s.accent
                                                : s.text))
                              ]))),
                      gap(),
                      _DockMusicRegion(
                          child: TickerMode(
                              enabled: !panelExpanded,
                              child: Center(
                              child: SizedBox(
                                  height: Design.px(72),
                                  width: double.infinity,
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
                                          enabled: c.appearance
                                              .dockMusicProgressBackground,
                                          fluid:
                                              c.appearance.dockMusicFluid,
                                          media: media,
                                          child: Padding(
                                              padding: EdgeInsets.symmetric(
                                                  horizontal: Design.px(12)),
                                              child: Row(children: [
                                                // 设计稿 .dk-mb/.dk-play：62 高方格命中区，图标 26/24。
                                                Row(
                                                    mainAxisSize:
                                                        MainAxisSize.min,
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
                                                              ? () => c
                                                                  .command(
                                                                      'previous')
                                                              : null,
                                                          width: 62,
                                                          iconScale: 26),
                                                      SizedBox(
                                                          width:
                                                              Design.px(16)),
                                                      IconAction(
                                                          key: const ValueKey(
                                                              'play-pause'),
                                                          icon: playing
                                                              ? Icons.pause
                                                              : Icons
                                                                  .play_arrow,
                                                          label: playing
                                                              ? '暂停'
                                                              : '播放',
                                                          size:
                                                              Design.px(62),
                                                          iconSize:
                                                              Design.px(24 *
                                                                  dockScale),
                                                          framed: false,
                                                          foregroundColor: s
                                                              .accent,
                                                          onTap: media[
                                                                      'available'] ==
                                                                  true
                                                              ? (canToggle
                                                                  ? () => c
                                                                      .command(
                                                                          'toggle-play')
                                                                  : null)
                                                              : () => c
                                                                  .command(
                                                                      'toggle-play')),
                                                      SizedBox(
                                                          width:
                                                              Design.px(16)),
                                                      action(
                                                          'next',
                                                          Icons
                                                              .skip_next_outlined,
                                                          '下一首',
                                                          canPlay &&
                                                                  (demo ||
                                                                      media['canNext'] ==
                                                                          true)
                                                              ? () => c
                                                                  .command(
                                                                      'next')
                                                              : null,
                                                          width: 62,
                                                          iconScale: 26)
                                                    ]),
                                                SizedBox(
                                                    width: Design.px(16)),
                                                showMusicVisual
                                                    ? Expanded(child: musicInfo)
                                                    : Flexible(
                                                        fit: FlexFit.loose,
                                                        child: musicInfo)
                                              ])))))))),
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
      }));
}

class _DockMusicRegion extends StatelessWidget {
  /// 音乐区**定宽**：字幕/频谱开关只决定里面画不画歌词与频谱，不改这一块的宽度。
  ///
  /// 以前关掉开关会换成一个 680 的固定宽（`compactWidth`），于是音乐条当着用户的面
  /// 缩短一截、右边还空出一段（2026-11-13 用户反馈：长度要跟打开时一样）。
  final Widget child;
  const _DockMusicRegion({required this.child});

  @override
  Widget build(BuildContext context) => Expanded(flex: 8, child: child);
}

Future<void> showUniDockMenu(BuildContext context, LauncherController c) async {
  if (await c.presentGlobalPanel('uni-menu') || !context.mounted) return;
  final selection = await _showUniDockPopup(context, c);
  if (!context.mounted) return;
  if (selection == 'vehicle') {
    await showVehiclePanel(context, c);
  } else if (selection == 'transfer') {
    await showFileTransferPopup(context, c);
  } else if (selection == 'cleaner') {
    // 直接落到设置里的「垃圾清理」一栏，不再弹独立窗口：
    // 那个窗口和设置页里的是同一份逻辑，两个入口两套壳，用起来像两个功能。
    await c.openSettings(tab: 'cleaner');
  } else if (selection == 'settings') {
    await c.openSettings();
  }
}

/// Anchored popup that expands above the UNI dock button.
Future<String?> _showUniDockPopup(
    BuildContext context, LauncherController c) async {
  final dock = DockWindowScope.of(context);
  final route = Navigator.of(context).push(_UniDockPopupRoute(
      panelWindow: c.native.value['hostMode'] == 'global-panel'));
  if (dock?.onPresented != null) {
    await WidgetsBinding.instance.endOfFrame;
    if (context.mounted) await dock!.onPresented!();
  }
  return await route;
}

/// sim `.uni-m`：283.33 宽、25 圆角、8.33 内边距，四项行高 58.5。
///
/// **尺寸不跟 dock 档位缩放**。以前这里乘了 `_dockContentScale`，把「超大」
/// 档的 dock 图标比例带进菜单，结果同一份设计稿在 four 档里排出四种字号——
/// 稿子给的是绝对尺寸（17.6 / 10.1 / 58.5），与底栏大小无关。
class _UniDockPopupRoute extends PopupRoute<String> {
  final bool panelWindow;
  _UniDockPopupRoute({required this.panelWindow});
  @override
  Color? get barrierColor =>
      // sim 的遮罩是 rgba(2,3,4,.42)。独立面板窗口（global-panel）里再压一层
      // 黑会把后面那块桌面也一起压掉，所以只在桌面内弹时加。
      panelWindow ? null : const Color(0x6B020304);
  @override
  bool get barrierDismissible => true;
  @override
  String? get barrierLabel => '关闭UNI菜单';
  @override
  Duration get transitionDuration => const Duration(milliseconds: 140);
  @override
  Duration get reverseTransitionDuration => const Duration(milliseconds: 120);
  @override
  Widget buildPage(BuildContext context, Animation<double> animation,
      Animation<double> secondaryAnimation) {
    final s = SurfaceStyle.of(context);
    return Stack(children: [
      Positioned(
        right: Design.dz(11.67),
        bottom: panelWindow ? Design.px(14) : Design.dz(91.67),
        child: SizedBox(
            width: Design.dz(283.33),
            child: GlassSurface(
                key: const ValueKey('uni-popup-panel'),
                sheet: true,
                // 稿子给 25。用 `s.radius` 而不是写死：暗夜默认半径正是 25，
                // 同时保留「统一圆角」设置生效（设为 0 时菜单要跟着变直角）。
                radius: s.radius,
                shadow: true,
                padding: const EdgeInsets.all(8.33),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  _UniPopupItem(
                      key: const ValueKey('uni-menu-vehicle'),
                      icon: UniIcon('uni-vehicle',
                          size: 28,
                          color: s.accent.withValues(alpha: .9)),
                      title: '车辆信息',
                      onTap: () => Navigator.pop(context, 'vehicle')),
                  const SizedBox(height: 5.2),
                  _UniPopupItem(
                      key: const ValueKey('uni-menu-transfer'),
                      icon: UniIcon('uni-transfer',
                          size: 28,
                          color: s.accent.withValues(alpha: .9)),
                      title: '传文件 / 通网盘',
                      onTap: () => Navigator.pop(context, 'transfer')),
                  const SizedBox(height: 5.2),
                  _UniPopupItem(
                      key: const ValueKey('uni-menu-cleaner'),
                      icon: UniIcon('uni-trash',
                          size: 28,
                          color: s.accent.withValues(alpha: .9)),
                      title: '垃圾清理',
                      onTap: () => Navigator.pop(context, 'cleaner')),
                  const SizedBox(height: 5.2),
                  _UniPopupItem(
                      key: const ValueKey('uni-menu-settings'),
                      icon: UniIcon('uni-slider',
                          size: 28,
                          color: s.accent.withValues(alpha: .9)),
                      title: 'UNI 桌面设置',
                      onTap: () => Navigator.pop(context, 'settings')),
                ]))),
      ),
    ]);
  }

  @override
  Widget buildTransitions(BuildContext context, Animation<double> animation,
      Animation<double> secondaryAnimation, Widget child) {
    // sim 的 `uniIn`：opacity 0→1 同时 translateY 6px→0。
    final t = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic);
    return AnimatedBuilder(
        animation: t,
        builder: (context, inner) => FadeTransition(
            opacity: t,
            child: Transform.translate(
                offset: Offset(0, Design.dz(6) * (1 - t.value)),
                child: RepaintBoundary(child: inner))),
        child: child);
  }
}

/// UNI 菜单用的字族。
///
/// 必须显式指定，不能靠系统默认回退：同一段 `TextStyle(fontWeight: w500)`
/// 下，`车辆信息 / 传文件` 与 `垃圾清理 / UNI 桌面设置` 会被 Skia 分派到不同
/// 的中文字体（前者细骨架、后者明显更粗），四行看起来像两种字重——这不是
/// 字重写错，是回退链按字符选 face 的结果（2026-11-09 实测确认：把第 3 行
/// 文字换成「车辆信息」后笔画立刻与第 1 行完全一致）。
///
/// 钉死一族之后，Windows 用雅黑、车机落到 Noto CJK，四行始终同一款字。
const _uniMenuFont = 'Microsoft YaHei';
const _uniMenuFontFallback = ['Noto Sans CJK SC', 'Noto Sans SC', 'sans-serif'];

class _UniPopupItem extends StatelessWidget {
  final Widget icon;
  final String title;
  final VoidCallback onTap;
  const _UniPopupItem(
      {super.key,
      required this.icon,
      required this.title,
      required this.onTap});
  @override
  Widget build(BuildContext context) {
    final s = SurfaceStyle.of(context);
    return Material(
        color: Colors.transparent,
        child: InkWell(
            // 行比面板小一档：稿子 17 / 25 ≈ .68；上限 17，避免把圆角调到
            // 40 时行被磨成胶囊。
            borderRadius:
                BorderRadius.circular((s.radius * .68).clamp(0, Design.dz(17))),
            onTap: onTap,
            child: SizedBox(
                height: Design.dz(58.5),
                // 稿子 `.uni-mi{padding:0 10.4px 0 11.2px}`——左右不等，
                // 因为右侧要留出 chevron 的视觉边距。
                child: Padding(
                    padding: const EdgeInsets.only(left: 11.2, right: 10.4),
                    child: Row(children: [
                      SizedBox(
                          width: Design.dz(37),
                          height: Design.dz(37),
                          child: Center(child: icon)),
                      const SizedBox(width: 9.6),
                      Expanded(
                          // 设计稿每行是「标题 + 10.1 的说明」两行；实车菜单只有
                          // 四项、不需要说明，说明整行去掉，标题因此从 17.6 抬到
                          // 20。行高仍是稿子的 58.5（触控区不变），单行垂直居中。
                          child: Text(title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontSize: Design.dz(20),
                                  fontWeight: FontWeight.w500,
                                  height: 1.06,
                                  fontFamily: _uniMenuFont,
                                  fontFamilyFallback: _uniMenuFontFallback,
                                  letterSpacing: Design.dz(.21),
                                  color: s.text.withValues(alpha: .9)))),
                      const SizedBox(width: 9),
                      DesignIcon(Icons.chevron_right,
                          size: Design.dz(15),
                          color: s.text.withValues(alpha: .3)),
                    ])))));
  }
}

Future<void> showVehiclePanel(
    BuildContext context, LauncherController c) async {
  if (await c.presentGlobalPanel('vehicle') || !context.mounted) return;
  await showLauncherSheet<void>(context,
      title: '车辆信息',
      closeLabel: '关闭车辆信息',
      width: Design.dz(1466),
      // 稿子是 760：那在 900 高的画布上居中后底边正好贴着常驻底栏，
      // 实机看着像被压住。收到 700，居中的上下留白各 100，离底栏还有 30 空隙。
      height: Design.dz(700),
      showHeader: false,
      padding: EdgeInsets.zero,
      builder: (context) => NativeSliceBuilder(
          valueListenable: c.native,
          select: (n) => [n['demo'], n['vehicle'], n['climate']],
          builder: (context, n) => VehicleReadout(controller: c, native: n)));
}
