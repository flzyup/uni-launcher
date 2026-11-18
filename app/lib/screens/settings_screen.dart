import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../controller/launcher_controller.dart';
import '../model/appearance.dart';
import '../model/page_motion.dart';
import '../theme/design_tokens.dart';
import '../theme/launcher_type.dart';
import '../theme/launcher_theme.dart';
import '../theme/technical_frame.dart';
import '../widgets/glass_surface.dart';
import '../widgets/desktop.dart';
import '../widgets/bottom_dock.dart';
import '../widgets/embedded_navigation.dart';
import '../widgets/scene_background.dart';
import '../widgets/wallpaper_library_sheet.dart';
import '../widgets/uni_icon.dart';
import '../widgets/launcher_dialog.dart';
import '../widgets/system_settings.dart';
import '../widgets/setting_block.dart';
import '../widgets/dock_size_settings.dart';
import '../widgets/integration_settings.dart';
import '../widgets/vehicle_memory_settings.dart';
import '../widgets/spectrum_painter.dart';
import '../widgets/settings_cards.dart';
import '../widgets/choice_button.dart';
import '../ota/update_controller.dart';
import '../ota/update_ui.dart';
import '../widgets/ambient_light_settings.dart';
import '../widgets/cluster_lyrics_settings.dart';
import '../widgets/storage_cleaner_panel.dart';
import '../widgets/color_picker.dart';
import '../widgets/native_slice_builder.dart';
import '../platform/ambient_light.dart';

class SettingsScreen extends StatelessWidget {
  final LauncherController controller;
  final UpdateController? update;
  const SettingsScreen({super.key, required this.controller, this.update});
  @override
  Widget build(BuildContext context) {
    final c = controller;
    return SettingsControllerScope(
        controller: c,
        child: Padding(
            // sim `.ss-page`：左右 26.67、上 10、下 14（底栏由外壳单独占位）。
            padding: EdgeInsets.fromLTRB(Design.dz(26.67), Design.dz(10),
                Design.dz(26.67), Design.dz(14)),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // sim `.ss-head`：58 高，返回键 53.33 圆形 + 标题 30 / 副标题 16.67。
                  const SizedBox(height: 58, child: _SettingsHeader()),
                  SizedBox(height: Design.dz(14)),
                  Expanded(
                      child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                        const SizedBox(width: 271.67, child: _SettingsNav()),
                        SizedBox(width: Design.dz(18.33)),
                        Expanded(child: _SettingsMain(child: _page(c, update)))
                      ])),
                ])));
  }

  static Widget _page(LauncherController c, UpdateController? update) =>
      switch (c.settingsTab) {
        'appearance' => AppearanceSettings(controller: c),
        'dock' => DockSettings(controller: c),
        'connections' => const ConnectionSettings(),
        'motion' => PageMotionSettings(controller: c),
        'ambient' => AmbientLightSettingsTab(controller: c),
        'cluster' => const ClusterLyricsSettingsTab(),
        'memory' => VehicleMemorySettings(controller: c),
        'cleaner' => CleanerPanel(controller: c),
        'system' => SystemSettingsPanel(controller: c),
        'about' => update == null
            ? const Center(child: Text('更新服务暂不可用'))
            : AboutPanel(update: update),
        _ => SystemSettingsPanel(controller: c)
      };
}

/// 返回桌面：圆形描边按钮，只放一支箭头、垂直居中。
///
/// 图标用 `arrow_back_ios_new`，跟「全部应用」面板 `_header` 的返回是同一个
/// 字形；那边是 px(28.8)（1920 口径），换成稿子口径正好 dz(24)，比原来
/// dz(20) 的 `arrow_back` 看着大一圈也细一点，不会把 53.33 的圆塞满。
/// sim `.ss-back` 原本箭头下面还有一行 9.5 号「返回桌面」小字，实车上去掉了
/// ——53.33 的圆圈里塞两行字，箭头被顶到偏上，看着像没对齐。
class _SettingsHeader extends StatelessWidget {
  const _SettingsHeader();
  @override
  Widget build(BuildContext context) {
    final c = SettingsControllerScope.of(context), s = SurfaceStyle.of(context);
    return Row(children: [
      InkWell(
          key: const ValueKey('settings-back'),
          onTap: c.home,
          borderRadius: BorderRadius.circular(Design.dz(53.33) / 2),
          child: Container(
              width: Design.dz(53.33),
              height: Design.dz(53.33),
              decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: s.text.withValues(alpha: .04),
                  border: Border.all(color: s.text.withValues(alpha: .1))),
              child: Icon(Icons.arrow_back_ios_new,
                  size: Design.dz(24), color: s.text.withValues(alpha: .8)))),
      SizedBox(width: Design.dz(20)),
      // 58 高的头部里要装 30 + 3 + 16.67 两行：不同字体度量会把两行的
      // 向上取整量凑到 59，从而撑出 1px 溢出条（黄黑斜纹）。
      // 这里不再靠手调行高凑数，交给 FittedBox 在必要时等比缩 1%——
      // 正常字体下完全不缩放，任何字体下都不会溢出。
      Flexible(
          child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('桌面设置',
                        style: TextStyle(
                            fontSize: Design.dz(30),
                            height: 1.15,
                            fontWeight: FontWeight.w500,
                            letterSpacing: Design.dz(-.3))),
                    SizedBox(height: Design.dz(3)),
                    Text('按分类管理外观、应用、动画与车辆',
                        style: TextStyle(
                            fontSize: Design.dz(16.67),
                            height: 1.15,
                            color: s.text.withValues(alpha: .4)))
                  ]))),
      const Spacer()
    ]);
  }
}

/// 左导航：sim `.ss-nav`（271.67 宽、25 圆角、11.67 内边距、8.33 行距）。
class _SettingsNav extends StatelessWidget {
  const _SettingsNav();
  @override
  Widget build(BuildContext context) {
    final c = SettingsControllerScope.of(context), s = SurfaceStyle.of(context);
    const tabs = [
      ('appearance', Icons.palette_outlined, '外观与壁纸'),
      ('dock', Icons.dashboard_outlined, '应用与底栏'),
      ('connections', Icons.route_outlined, '导航与媒体'),
      ('motion', Icons.animation_outlined, '动画与频谱'),
      ('ambient', Icons.light_outlined, '氛围灯'),
      ('cluster', Icons.connected_tv_outlined, '仪表投屏'),
      ('memory', Icons.tune_outlined, '记忆配置'),
      ('cleaner', Icons.cleaning_services_outlined, '垃圾清理'),
      ('system', Icons.settings_suggest_outlined, '系统与调试'),
      ('about', Icons.info_outline, '关于与更新'),
    ];
    final list = SingleChildScrollView(
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      // 左导航在 `SettingsScreen` 里是 `const SizedBox(child: _SettingsNav())`：
      // 那块 SizedBox 是编译期常量，父级重建时 element 直接命中「同一个
      // widget」的短路，整棵子树根本不进 build。而 Scope 的
      // updateShouldNotify 只比 controller 引用，永远不会变——结果就是
      // 点别的分类时正文换了、左边高亮一直钉在第一项上。
      // 这里自己订阅一次 controller，重建与父级是否短路无关。
      ListenableBuilder(
          listenable: c,
          builder: (context, _) =>
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                for (final (index, tab) in tabs.indexed) ...[
                  if (index != 0) SizedBox(height: Design.dz(8.33)),
                  ChoiceButton(
                      key: ValueKey('tab-${tab.$1}'),
                      kind: ChoiceKind.nav,
                      height: 46.67,
                      radius: 14,
                      selected: c.settingsTab == tab.$1,
                      padding:
                          EdgeInsets.symmetric(horizontal: Design.dz(13.33)),
                      alignment: Alignment.centerLeft,
                      onPressed: () => c.tab(tab.$1),
                      child: Row(children: [
                        DesignIcon(tab.$2, size: Design.dz(20)),
                        SizedBox(width: Design.dz(11.67)),
                        Expanded(
                            child: Text(tab.$3,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                // 颜色取自 ChoiceButton 的同一套规则，不再各写一份。
                                style: TextStyle(
                                    fontSize: Design.dz(16),
                                    color: ChoiceButton.foregroundOf(
                                        s,
                                        ChoiceKind.nav,
                                        c.settingsTab == tab.$1))))
                      ]))
                ]
              ]))
    ]));
    final pad = EdgeInsets.all(Design.dz(11.67));
    if (!s.nocturne) {
      return GlassSurface(padding: pad, child: list);
    }
    return DecoratedBox(
        decoration: BoxDecoration(
            color: s.text.withValues(alpha: .035),
            borderRadius: BorderRadius.circular(Design.dz(25)),
            border: Border.all(color: s.text.withValues(alpha: .08))),
        child: Padding(padding: pad, child: list));
  }
}

/// 右侧主面板：sim `.ss-main`（25 圆角、白 2.8% 底、白 8% 描边、25/28.33 内边距）。
class _SettingsMain extends StatelessWidget {
  final Widget child;
  const _SettingsMain({required this.child});
  @override
  Widget build(BuildContext context) {
    final s = SurfaceStyle.of(context);
    final pad = EdgeInsets.symmetric(
        horizontal: Design.dz(28.33), vertical: Design.dz(25));
    if (!s.nocturne) return GlassSurface(padding: pad, child: child);
    return DecoratedBox(
        decoration: BoxDecoration(
            color: s.text.withValues(alpha: .028),
            borderRadius: BorderRadius.circular(Design.dz(25)),
            border: Border.all(color: s.text.withValues(alpha: .08))),
        child: Padding(padding: pad, child: child));
  }
}

/// sim f10 · 应用与底栏。
///
/// 两栏：左边是「底栏长什么样」（样式 / 图标大小 / 音乐工具条），右边是
/// 「底栏接管了什么」（全局底栏、开机与 HOME 键）。以前是一列往下排，加了开机
/// 自启与 HOME 键两块之后要滚动才能看全；两栏 + 收紧块内留白后一屏放得下。
class DockSettings extends StatelessWidget {
  final LauncherController controller;
  const DockSettings({super.key, required this.controller});
  @override
  Widget build(BuildContext context) {
    final c = controller;
    final leftColumn = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // sim f10 · 底栏样式：ops 限宽 420，两个 47 高的实心选项。
        SettingBlock(
            title: '底栏样式',
            dense: true,
            child: Align(
                alignment: Alignment.centerLeft,
                child: SizedBox(
                    width: Design.dz(420),
                    child: Builder(builder: (context) {
                      final a = c.appearance;
                      return Row(children: [
                        for (final (index, layout) in [
                          ('floating', '悬浮'),
                          ('full', '铺满')
                        ].indexed) ...[
                          if (index > 0) SizedBox(width: Design.dz(11.67)),
                          Expanded(
                              child: ChoiceButton(
                                  key: ValueKey('dock-layout-${layout.$1}'),
                                  height: 47,
                                  selected: a.dockLayout == layout.$1,
                                  onPressed: () => c.setAppearance(
                                      a.copyWith(dockLayout: layout.$1)),
                                  child: Text(layout.$2,
                                      style:
                                          TextStyle(fontSize: Design.dz(16)))))
                        ]
                      ]);
                    })))),
        SizedBox(height: Design.dz(11.67)),
        DockSizeSettings(controller: c),
        SizedBox(height: Design.dz(11.67)),
        _musicToolbarBlock(context, c),
        SizedBox(height: Design.dz(11.67)),
        Expanded(child: SystemDefaultHomeBlock(controller: c)),
      ],
    );
    final rightColumn = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DockRuntimeSettings(controller: c),
        SizedBox(height: Design.dz(11.67)),
        // 右栏比左栏矮，让它吃掉剩下的高度，两栏的下沿才会齐在一条线上——
        // 之前右栏短一截，看着像右边漏了一块。
        // SizedBox.expand 不能省：SettingBlock 内部是 mainAxisSize.min 的
        // Column，拿到松约束就只报内容高度，Expanded 给的那截会变成下沿缺口。
        Expanded(
            child: SizedBox.expand(
                child: BootAndHomeSettings(controller: c))),
      ],
    );
    return SingleChildScrollView(
        key: const PageStorageKey('dock-settings-scroll'),
        padding: EdgeInsets.zero,
        child: IntrinsicHeight(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Expanded(flex: 25, child: leftColumn),
            SizedBox(width: Design.dz(12)),
            Expanded(flex: 27, child: rightColumn),
          ]),
        ));
  }

  /// 底部音乐工具条：字幕/频谱区域 + 进度条那层流体效果。
  ///
  /// 两颗开关说的是同一块区域的两层：一个是「要不要这块字幕/频谱」，
  /// 一个是「进度条画成什么」。分开摆，省得混成一句说明。
  Widget _musicToolbarBlock(BuildContext context, LauncherController c) {
    final a = c.appearance;
    // 流体那条 shader 只有暗夜色一套调色板（试过给浅色反推一版，出来是灰糊），
    // 所以浅色皮肤下不给这颗开关——留着也是个按了没反应的哑开关。
    final nocturne = SurfaceStyle.of(context).nocturne;
    return SettingBlock(
        title: '底部音乐工具条',
        note: '底栏右侧的音乐信息区域',
        dense: true,
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SettingRow(
              label: '字幕 / 频谱区域',
              note: '关闭后保留播放控制、封面、歌曲与歌手',
              height: 48,
              trailing: DesignSwitch(
                  key: const ValueKey('dock-music-visual-switch'),
                  value: a.dockMusicVisual,
                  onChanged: (value) =>
                      c.setAppearance(a.copyWith(dockMusicVisual: value)))),
          // 浅色皮肤下留着这一行但置灰：直接隐藏会让这页在三套皮肤下高度不一致
          // （three_skin_geometry 盯着这件事），而置灰还能说明「为什么点不了」。
          SettingRow(
              label: '进度条烟雾流体',
              // 文案三套皮肤必须一模一样：three_skin_geometry 会比文字盒宽度，
              // 换一句就会误报成「几何不一致」。
              note: '仅暗夜皮肤生效；关掉回落细渐变进度',
              height: 48,
              divider: false,
              trailing: DesignSwitch(
                  key: const ValueKey('dock-music-fluid-switch'),
                  value: nocturne && a.dockMusicFluid,
                  onChanged: nocturne
                      ? (value) =>
                          c.setAppearance(a.copyWith(dockMusicFluid: value))
                      : null)),
        ]));
  }
}

/// 开机与实体 HOME 键。
///
/// 上游 0.7.11 带进来时是 `Design.px` + `DesignSwitchTile` + `OutlinedButton`
/// 那一套老画法，塞进这页就明显比别的块小一圈、开关也不是同一颗。这里按设置
/// 页的统一控件重排：`.blk` + `.set-row` + 46×26 自绘开关 + `.opt` 档位按钮。
class BootAndHomeSettings extends StatelessWidget {
  final LauncherController controller;
  const BootAndHomeSettings({super.key, required this.controller});

  @override
  Widget build(BuildContext context) =>
      ValueListenableBuilder<Map<String, dynamic>>(
        valueListenable: controller.native,
        builder: (context, native, _) {
          final c = controller, s = SurfaceStyle.of(context);
          final prefs = native['integrationPreferences'] is Map
              ? Map<String, dynamic>.from(native['integrationPreferences'])
              : const <String, dynamic>{};
          final bootAutostart = prefs['bootAutostart'] != false;
          final rawApps = prefs['homeApps'] is List
              ? (prefs['homeApps'] as List).whereType<Map>().toList()
              : const <Map>[];
          final homeApps = <Map<String, dynamic>>[
            if (rawApps.isEmpty) ...[
              const {
                'package': 'xyz.i4o.uni.launcher',
                'label': 'UNI 桌面',
                'isUni': true
              },
              const {
                'package': 'ecarx.launcher3',
                'label': '原车系统桌面',
                'isUni': false
              },
            ] else
              for (final app in rawApps) Map<String, dynamic>.from(app),
          ];

          final currentTarget = '${prefs['homeKeyTarget'] ?? 'uni'}';
          final currentLabel = homeApps.firstWhere(
            (a) =>
                a['package'] == currentTarget ||
                (a['isUni'] == true &&
                    (currentTarget == 'uni' ||
                        currentTarget == 'xyz.i4o.uni.launcher')) ||
                (a['package'] == 'ecarx.launcher3' &&
                    (currentTarget == 'oem' ||
                        currentTarget == 'ecarx.launcher3')),
            orElse: () => {'label': currentTarget},
          )['label'] as String;

          // 命令只认 uni / oem 两个别名和真实包名，选项显示的却是应用名，
          // 所以 key 与选中判定都从这里算，别在按钮里各写一份。
          String targetOf(Map<String, dynamic> app) {
            final isUni = app['isUni'] == true ||
                app['package'] == 'xyz.i4o.uni.launcher';
            if (isUni) return 'uni';
            if (app['package'] == 'ecarx.launcher3') return 'oem';
            return '${app['package']}';
          }

          bool selectedOf(Map<String, dynamic> app) {
            final key = targetOf(app);
            if (currentTarget == key) return true;
            return currentTarget == '${app['package']}';
          }

          // 直接返回块本身、不再套一层 Column：外面靠 Expanded 把它拉到和左栏同高，
          // 套一层 Column 会让高度在上层就被吃掉，块底还是短一截。
          return SettingBlock(
              title: '开机与 HOME 键',
              dense: true,
              note: '通电后进哪个桌面 · 按圆键回哪个桌面',
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SettingRow(
                      key: const ValueKey('boot-autostart'),
                      label: '开机自启动 UNI 桌面',
                      note: '车机通电开机完成后自动进入 UNI 桌面；关闭后保留在原车系统桌面',
                      trailing: DesignSwitch(
                          key: const ValueKey('boot-autostart-switch'),
                          value: bootAutostart,
                          onChanged: (v) => c.setBootAutostart(v)),
                    ),
                    SizedBox(height: Design.dz(11)),
                    // 开机落在第几页。和上面那颗开关是同一件事的两半（进哪个
                    // 桌面 / 进哪一页），所以摆在一起。
                    // 它顺带管着「会不会把导航拉起来」：导航卡不在开机页上，
                    // 卡片就不会向原生发 create，导航应用也就不会被拉起来。
                    ListenableBuilder(
                        listenable: c,
                        builder: (context, _) {
                          final bootPage = c.appearance.bootPage;
                          return Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Text('开机进入',
                                    style: TextStyle(
                                        fontSize: Design.dz(13.5),
                                        color: s.text.withValues(alpha: .5))),
                                SizedBox(height: Design.dz(9)),
                                Wrap(
                                    spacing: Design.dz(9),
                                    runSpacing: Design.dz(9),
                                    children: [
                                      for (final (label, value) in [
                                        ('上次停留', -1),
                                        for (var i = 0; i < c.pageCount; i++)
                                          ('第 ${i + 1} 页', i),
                                      ])
                                        ChoiceButton(
                                            key: ValueKey(value < 0
                                                ? 'boot-page-last'
                                                : 'boot-page-$value'),
                                            kind: ChoiceKind.filled,
                                            height: 40,
                                            radius: 11,
                                            shrink: true,
                                            selected: bootPage == value,
                                            onPressed: () =>
                                                c.setBootPage(value),
                                            child: Text(label,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: TextStyle(
                                                    fontSize: Design.dz(13.5)))),
                                    ]),
                              ]);
                        }),
                    SizedBox(height: Design.dz(11)),
                    Text('实体 HOME 键打开的桌面',
                        style: TextStyle(
                            fontSize: Design.dz(13.5),
                            color: s.text.withValues(alpha: .5))),
                    SizedBox(height: Design.dz(9)),
                    Wrap(
                        spacing: Design.dz(9),
                        runSpacing: Design.dz(9),
                        children: [
                          for (final app in homeApps)
                            ChoiceButton(
                                key: ValueKey('home-target-${targetOf(app)}'),
                                kind: ChoiceKind.filled,
                                height: 40,
                                radius: 11,
                                shrink: true,
                                selected: selectedOf(app),
                                onPressed: () =>
                                    c.setHomeKeyTarget(targetOf(app)),
                                child: Text('${app['label']}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style:
                                        TextStyle(fontSize: Design.dz(13.5)))),
                        ]),
                    SizedBox(height: Design.dz(7)),
                    Text('当前：$currentLabel · 底栏 HOME 图标固定回 UNI 首页',
                        style: TextStyle(
                            fontSize: Design.dz(11),
                            height: LauncherType.lineLoose,
                            color: s.muted)),
                  ]));
        },
      );
}

/// 系统默认桌面：交给 Android 自己那套「默认应用」页面去改。
///
/// 单独一块而不是塞进「开机与 HOME 键」里：那块已经有三颗桌面档位，再加一句
/// 「去系统里改」会让人以为上面那三颗没生效。这一块归左栏，正好把两栏高度拉平。
class SystemDefaultHomeBlock extends StatelessWidget {
  final LauncherController controller;
  const SystemDefaultHomeBlock({super.key, required this.controller});
  @override
  Widget build(BuildContext context) => SettingBlock(
        title: '系统默认桌面',
        dense: true,
        note: '由 Android 管理，可切回官方默认桌面',
        child: Align(
            alignment: Alignment.centerLeft,
            child: DesignSmallAction('打开系统设置',
                key: const ValueKey('open-home-settings-button'),
                icon: Icons.settings_outlined,
                onPressed: controller.openHomeSettings)),
      );
}

class ConnectionSettings extends StatelessWidget {
  const ConnectionSettings({super.key});
  @override
  Widget build(BuildContext context) => NativeSliceBuilder(
      valueListenable: SettingsControllerScope.of(context).native,
      select: (native) => native,
      builder: (context, native) => IntegrationSettings(
          controller: SettingsControllerScope.of(context), native: native));
}

class SpectrumSettings extends StatelessWidget {
  final LauncherController controller;
  const SpectrumSettings({super.key, required this.controller});
  @override
  Widget build(BuildContext context) {
    final s = SurfaceStyle.of(context), c = controller;
    return SettingBlock(
        title: '音乐频谱',
        note: '卡片、音乐弹窗与底栏共用样式',
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          // sim f12 · 音乐频谱：四张 spcard 一行排开（flex:1）。
          IntrinsicHeight(
              child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                for (final (index, entry)
                    in spectrumStyleLabels.entries.toList().indexed) ...[
                  if (index > 0) SizedBox(width: Design.dz(11.67)),
                  Expanded(
                      child: SpectrumChoiceCard(
                          style: entry.key,
                          label: entry.value,
                          selected: c.appearance.spectrumStyle == entry.key,
                          onTap: () => c.setAppearance(
                              c.appearance.copyWith(spectrumStyle: entry.key))))
                ]
              ])),
          SizedBox(height: Design.dz(13.33)),
          Text('底栏右侧左右滑动可切换歌词和频谱；预览为静态示意。',
              style: TextStyle(
                  fontSize: Design.dz(13.5),
                  color: s.text.withValues(alpha: .42))),
          SizedBox(height: Design.dz(6)),
          SettingRow(
              label: '音乐进度动态背景',
              note: '背景长度同步播放进度，光晕向进度线左侧展开',
              divider: false,
              trailing: DesignSwitch(
                  key: const ValueKey('dock-music-progress-switch'),
                  value: c.appearance.dockMusicProgressBackground,
                  onChanged: (value) => c.setAppearance(c.appearance
                      .copyWith(dockMusicProgressBackground: value))))
        ]));
  }
}

class AmbientLightSettingsTab extends StatefulWidget {
  final LauncherController controller;
  const AmbientLightSettingsTab({super.key, required this.controller});
  @override
  State<AmbientLightSettingsTab> createState() =>
      _AmbientLightSettingsTabState();
}

class _AmbientLightSettingsTabState extends State<AmbientLightSettingsTab> {
  @override
  void initState() {
    super.initState();
    // The capability is read when the tab opens: the vehicle service may
    // have connected after the app started.
    AmbientLightService.shared.refreshStatus();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    return ListenableBuilder(
        listenable: AmbientLightService.shared,
        builder: (context, _) => ListView(
                key: const PageStorageKey('ambient-settings-scroll'),
                padding: EdgeInsets.zero,
                children: [
                  // 面板自己出 f13 的三块（音乐律动氛围灯 / 两列滑杆 / 分区编排）。
                  AmbientLightSettingsPanel(
                      settings: c.ambientLight,
                      service: AmbientLightService.shared,
                      onChanged: c.setAmbientLight),
                ]));
  }
}

/// sim f9：左栏五组（主题样式 / 主题风格 / 主题配色 / 桌面壁纸 / 卡片圆角），
/// 右栏 516.67 宽的实时预览。`#f9 .blk` 把块内边距收到 8/16/9、块间距 7。
class AppearanceSettings extends StatelessWidget {
  final LauncherController controller;
  const AppearanceSettings({super.key, required this.controller});

  /// f9 专属块内边距。
  ///
  /// 设计稿是 `padding:8px 16px 9px`、块间距 7——但那是按「没有底栏占位」的
  /// 整屏画的。实机可视高度只有 517 画布（见 `launcher_shell` 里 BottomDock
  /// 常驻），五块加起来多出 31，底部「卡片圆角」被切掉半行、右缘还挂一条
  /// 滚动条。这里把上下各收 2、块间距收 2，五块正好落在一屏里。
  static EdgeInsetsGeometry blockPadding() => EdgeInsets.fromLTRB(
      Design.dz(16), Design.dz(6), Design.dz(16), Design.dz(7));

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Expanded(child: LayoutBuilder(builder: (context, box) {
        // 五块加起来比可视高度短一点点（约 8 画布）。原来那点空隙全落在底部：
        // 上沿离边线 25 画布、下沿 33，而右栏「返回桌面查看」由 Spacer 推到
        // 底，又比左栏下沿低 8——三处互不齐。
        //
        // 这里给整列「正好一屏」的高度、余量由 spaceBetween 均分到块间距，
        // 于是上下留白都是 25，左栏下沿与右栏按钮下沿落在同一条线上。
        // 不用 `IntrinsicHeight` 把列缩到内容高：壁纸那块内部有 `LayoutBuilder`
        // （按可用宽反算缩略图宽度），整页求 intrinsic 会直接抛异常；也不必再
        // 套一层滚动——这页按设计就是一屏，真放不下时先由 `design_contract_test`
        // 的那条「one screen」用例拦下来。
        return SizedBox(
            height: box.maxHeight,
            key: const PageStorageKey('appearance-settings-scroll'),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                spacing: Design.dz(5),
                children: [
                  _ThemeStyleBlock(controller: c),
                  _ThemeModeBlock(controller: c),
                  _PaletteBlock(controller: c),
                  WallpaperSetting(controller: c),
                  RadiusSetting(controller: c),
                ]));
      })),
      SizedBox(width: Design.dz(20)),
      SizedBox(width: Design.dz(516.67), child: const DesktopPreview()),
    ]);
  }
}

/// 主题样式：`.tcar` 横排材质卡（36 高、11 圆角、左边一块 24×17 色板、
/// 选中挂 14 的圆勾），末尾是 86 宽的虚线「更多」。
///
/// 色板**不再画**：三套材质的色板都是 #101820→#04060A 这一档的近黑色块，
/// 摆在纯黑卡片上就是三颗看不出内容的小方块，反而像渲染出错。文字 + 选中
/// 勾已经足够表达「选的是哪套」。
class _ThemeStyleBlock extends StatelessWidget {
  final LauncherController controller;
  const _ThemeStyleBlock({required this.controller});

  @override
  Widget build(BuildContext context) {
    final s = SurfaceStyle.of(context), c = controller, a = c.appearance;
    const styles = [
      ('blueGlass', '玻璃'),
      ('nocturne', '暗夜'),
      ('classic', '经典'),
    ];
    return SettingBlock(
        title: '主题样式',
        note: '材质与控件外观',
        dense: true,
        padding: AppearanceSettings.blockPadding(),
        trailing: Text('已安装 3 套',
            style: TextStyle(
                fontSize: Design.dz(12.5),
                color: s.text.withValues(alpha: .32))),
        child: Row(children: [
          for (final (index, style) in styles.indexed) ...[
            if (index > 0) SizedBox(width: Design.dz(9)),
            Expanded(
                child: ChoiceButton(
                    key: ValueKey('theme-style-${style.$1}'),
                    kind: ChoiceKind.tinted,
                    height: 36,
                    radius: 11,
                    padding: EdgeInsets.symmetric(horizontal: Design.dz(13)),
                    selected: a.themeStyle == style.$1,
                    selectedBorder: s.accent.withValues(alpha: .7),
                    selectedFill: s.accent.withValues(alpha: .1),
                    fill: s.text.withValues(alpha: .05),
                    border: s.text.withValues(alpha: .16),
                    onPressed: () => c.setAppearance(a.copyWith(
                        themeStyle: style.$1,
                        radius: style.$1 == 'nocturne' && a.radius == 0
                            ? Nocturne.defaultRadius
                            : a.radius)),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Flexible(
                          child: Text(style.$2,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: Design.dz(14)))),
                      if (a.themeStyle == style.$1) ...[
                        SizedBox(width: Design.dz(6)),
                        Container(
                            width: Design.dz(14),
                            height: Design.dz(14),
                            decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: s.accent.withValues(alpha: .9)),
                            child: Icon(Icons.check,
                                size: Design.dz(10), color: s.accentText))
                      ]
                    ])))
          ],
          SizedBox(width: Design.dz(9)),
          const SizedBox(width: 86, child: _MoreStylesCard())
        ]));
  }
}

/// `.tadd`：设计稿的虚线「更多」入口。Flutter 没有虚线描边，这里用实线
/// 弱描边代替（唯一一处有意为之的差异，见计划书）。
class _MoreStylesCard extends StatelessWidget {
  const _MoreStylesCard();
  @override
  Widget build(BuildContext context) {
    final s = SurfaceStyle.of(context);
    final color = s.text.withValues(alpha: .46);
    return InkWell(
        borderRadius: BorderRadius.circular(Design.dz(11)),
        onTap: () => showLauncherToast(context, '更多外观样式随固件更新提供'),
        child: Container(
            height: Design.dz(36),
            decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(Design.dz(11)),
                color: s.text.withValues(alpha: .02),
                border: Border.all(color: s.text.withValues(alpha: .2))),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(Icons.add, size: Design.dz(15), color: color),
              SizedBox(width: Design.dz(6)),
              Text('更多',
                  style: TextStyle(fontSize: Design.dz(13), color: color))
            ])));
  }
}

/// 主题风格：`.opt` 四个等宽实心选项（f9 高 42）。
class _ThemeModeBlock extends StatelessWidget {
  final LauncherController controller;
  const _ThemeModeBlock({required this.controller});
  @override
  Widget build(BuildContext context) {
    final c = controller, a = c.appearance;
    final modes = [
      ('smart', Icons.auto_awesome_outlined, '智能调色'),
      ('system', Icons.brightness_auto_outlined, '跟随系统'),
      ('light', Icons.light_mode_outlined, '浅色'),
      ('dark', Icons.dark_mode_outlined, '深色'),
    ];
    return SettingBlock(
        title: '主题风格',
        note: a.themeStyle == 'nocturne' ? '暗夜固定深色，不跟随明暗' : '智能调色会匹配壁纸明暗',
        dense: true,
        padding: AppearanceSettings.blockPadding(),
        child: Row(children: [
          for (final (index, mode) in modes.indexed) ...[
            if (index > 0) SizedBox(width: Design.dz(11.67)),
            Expanded(
                child: ChoiceButton(
                    key: ValueKey('mode-${mode.$1}'),
                    // sim f9 的 `.opt` 是 47，暗夜为塞进一屏收紧到 42。
                    // 三套皮肤**必须同一高度**：换主题时这一排会跟着变高变矮，
                    // 下面的块一起上下挪，看着像换了另一套版式。统一取暗夜的
                    // 42——它是最紧的那个，另两套只会更松，不会切到内容。
                    height: 42,
                    onPressed: () => c.setAppearance(a.copyWith(mode: mode.$1)),
                    selected: a.mode == mode.$1,
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      DesignIcon(mode.$2, size: Design.dz(19)),
                      SizedBox(width: Design.dz(9)),
                      Text(mode.$3, style: TextStyle(fontSize: Design.dz(16)))
                    ])))
          ]
        ]));
  }
}

/// 主题配色：`.pcol` 圆角方块（f9 收到 38 大小的 13 圆角色块）。
class _PaletteBlock extends StatelessWidget {
  final LauncherController controller;
  const _PaletteBlock({required this.controller});
  @override
  Widget build(BuildContext context) {
    final s = SurfaceStyle.of(context), c = controller, a = c.appearance;
    final items = <(String, String, Color)>[
      for (final p in accentPresets) (p.id, p.name, p.seed),
      (
        'custom',
        '自定义',
        Color(0xFF000000 | int.parse(a.custom.substring(1), radix: 16))
      )
    ];
    return SettingBlock(
        title: '主题配色',
        note: '同步改变强调色与背景氛围',
        dense: true,
        padding: AppearanceSettings.blockPadding(),
        child: Row(children: [
          for (final (index, item) in items.indexed) ...[
            if (index > 0) SizedBox(width: Design.dz(11.67)),
            Expanded(
                child: ChoiceButton(
                    key: ValueKey(item.$1 == 'custom'
                        ? 'custom-color'
                        : 'palette-${item.$1}'),
                    kind: ChoiceKind.tinted,
                    // 同上：sim f9 的 `.pcol` 是 86，统一取暗夜的 76。
                    height: 76,
                    radius: 14,
                    padding: EdgeInsets.symmetric(vertical: Design.dz(6)),
                    selected: a.palette == item.$1,
                    selectedBorder: s.accent.withValues(alpha: .85),
                    selectedFill: s.accent.withValues(alpha: .05),
                    border: s.text.withValues(alpha: .1),
                    onPressed: () => item.$1 == 'custom'
                        ? editCustomColor(context, c)
                        : c.setAppearance(a.copyWith(palette: item.$1)),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      _PaletteDot(
                        key: ValueKey('dot-${item.$1}'),
                        id: item.$1,
                        seed: item.$3,
                        selected: a.palette == item.$1,
                      ),
                      SizedBox(height: Design.dz(8)),
                      Text(item.$2,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: Design.dz(14),
                              color: a.palette == item.$1
                                  ? s.text
                                  : s.text.withValues(alpha: .6)))
                    ])))
          ]
        ]));
  }
}

/// 「主题配色」里那颗 38×38 的色球。
///
/// 照 sim board 09 的 `.pcol .dot` 一比一画：
/// - 三段竖直渐变 `180deg, top, seed 55%, bottom`，三段是设计稿逐色标定的
///   字面值（见 `AccentPreset.dotTop`），不是从 seed 往白/黑插值；
/// - 顶上那层 `::before` 高光：左右内缩 3、从 top 2 起、占 45% 高，白 32%
///   到全透明——没有它球面是平的，六颗球看着像六个纯色方块；
/// - 选中时压一枚 20 号白勾（稿子就是 20，不是 16；16 在 38 的球上显得空）；
/// - 「自定义」球是 `conic-gradient(from 210deg)`，色标顺序粉→琥珀→当前强调
///   色→青→紫→粉；Flutter 的 SweepGradient 从正右起算，所以起始角要转
///   210 − 90 = 120 度。
///
/// **两处不能跟着皮肤走**：
/// 1. 高光恒用白色。稿子写的是 `rgba(var(--ink),.32)`，而浅色态 `--ink` 会翻
///    成深墨——照抄的结果是六颗球顶上都糊了一层灰，球面变成「上暗中亮」的
///    双环。球面是固定彩色，它的高光不会因为界面切成浅色就变成阴影。
/// 2. 投影在浅底上要收回一半。`0 6px 14px -6px rgba(0,0,0,.55)` 是给近黑
///    画布配的，原样压在浅底上就是球下面一圈黑晕。
class _PaletteDot extends StatelessWidget {
  final String id;
  final Color seed;
  final bool selected;
  const _PaletteDot(
      {super.key,
      required this.id,
      required this.seed,
      required this.selected});

  @override
  Widget build(BuildContext context) {
    final s = SurfaceStyle.of(context);
    final isCustom = id == 'custom';
    final preset = accentPresets.where((p) => p.id == id).firstOrNull;
    final size = Design.dz(38);
    final radius = BorderRadius.circular(Design.dz(13));
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
          borderRadius: radius,
          border: Border.all(color: s.text.withValues(alpha: .12)),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: s.dark ? .55 : .22),
                offset: Offset(0, Design.dz(6)),
                blurRadius: Design.dz(14),
                spreadRadius: -Design.dz(6))
          ],
          gradient: isCustom
              ? SweepGradient(
                  transform: const GradientRotation(120 * math.pi / 180),
                  colors: customDotColors(s.accent))
              : LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  stops: const [
                      0,
                      .55,
                      1
                    ],
                  colors: [
                      preset?.dotTop ?? seed,
                      seed,
                      preset?.dotBottom ?? seed,
                    ])),
      child: ClipRRect(
          borderRadius: radius,
          child: Stack(children: [
            Positioned(
                left: Design.dz(3),
                right: Design.dz(3),
                top: Design.dz(2),
                height: size * .45,
                child: DecoratedBox(
                    decoration: BoxDecoration(
                        borderRadius: BorderRadius.vertical(
                            top: Radius.circular(Design.dz(12)),
                            bottom: Radius.circular(Design.dz(10))),
                        gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.white.withValues(alpha: .32),
                              Colors.white.withValues(alpha: 0)
                            ])))),
            if (selected)
              Center(
                  child: Icon(Icons.check_rounded,
                      size: Design.dz(19), color: Colors.white))
          ])),
    );
  }
}

/// 桌面壁纸：`.wallrail` 横排 160×90 缩略图，标题行右侧是「查看全部」和
/// 叠加开关（设计稿只有链接，开关是本项目已有能力，保留）。
class WallpaperSetting extends StatelessWidget {
  final LauncherController controller;
  const WallpaperSetting({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    final c = controller, a = c.appearance, s = SurfaceStyle.of(context);
    final items = wallpaperPresets.length + 1;
    return SettingBlock(
        title: '桌面壁纸',
        note: '共 $items 张 · 与主题渐变叠加显示',
        dense: true,
        padding: AppearanceSettings.blockPadding(),
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          Text('叠加主题渐变',
              style: TextStyle(
                  fontSize: Design.dz(12.5),
                  color: a.wallpaper == 'gradient'
                      ? s.text.withValues(alpha: .3)
                      : s.text.withValues(alpha: .8))),
          SizedBox(width: Design.dz(6)),
          // 用设计稿的开关，不用 Material Switch：后者是 52×32、滑块带描边，
          // 摆在这一行里比右边的文字按钮还重，而且和下面各行里的开关长得不一样。
          DesignSwitch(
              key: const ValueKey('wallpaper-overlay'),
              value: a.wallpaper == 'gradient' ? true : a.wallpaperOverlay,
              onChanged: a.wallpaper == 'gradient'
                  ? null
                  : (value) =>
                      c.setAppearance(a.copyWith(wallpaperOverlay: value))),
          SizedBox(width: Design.dz(10)),
          DesignTextAction('查看全部',
              onPressed: () => showWallpaperLibrary(context, c))
        ]),
        child: LayoutBuilder(builder: (context, box) {
          // 设计稿 `.wpt` 是 160×90 的固定缩略图，横排可滑。但 160×4 + 9×3 =
          // 667 比这块内容区（约 631）宽出一截，第四张就会被切掉一角。这里按
          // 「一行正好四张」反算宽度：(可用宽 - 3 道间距) / 4，封顶仍是 160；
          // 高度按 16:9 跟着走，缩略图不会被拉扁。窗口更宽时四张仍是完整的
          // 第一屏，多出来的滑出去。
          const gap = 9.0;
          final tileWidth =
              ((box.maxWidth - gap * 3) / 4).clamp(96.0, 160.0).floorToDouble();
          Widget tileAt(int index) {
            if (index == wallpaperPresets.length) {
              return _WallpaperRailTile(
                  width: tileWidth,
                  id: 'custom',
                  name: '本地图片',
                  appearance: a,
                  selected: a.wallpaper == 'custom',
                  placeholder: Icon(Icons.image_outlined, size: Design.dz(24)),
                  onTap: () async {
                    try {
                      final picked = await c.gateway.pickWallpaper();
                      if (picked != null) {
                        c.setAppearance(c.appearance.copyWith(
                            wallpaper: 'custom',
                            wallpaperPath: picked.path,
                            wallpaperLuminance: picked.luminance,
                            mode: 'smart'));
                      } else if (context.mounted) {
                        // 取消 / 无权限 / 没有文件选择器：必须回一句话，
                        // 否则这一格按下去毫无反应，看着就是坏了。
                        showLauncherToast(context, '没有选中图片：本地导入需要文件选择器与存储权限');
                      }
                    } catch (_) {
                      if (context.mounted) {
                        showLauncherToast(context, '无法读取这张图片，请选择 JPG 或 PNG');
                      }
                    }
                  });
            }
            final preset = wallpaperPresets[index];
            return _WallpaperRailTile(
                width: tileWidth,
                id: preset.id,
                name: preset.name,
                appearance: a.copyWith(wallpaper: preset.id),
                selected: a.wallpaper == preset.id,
                onTap: () => c.setAppearance(
                    a.copyWith(wallpaper: preset.id, mode: 'smart')));
          }

          // 只有五张图，虚拟化没有意义：用 SingleChildScrollView + Row，
          // 既保留横滑，也让这一排的高度由外面那层 SizedBox 定死，不必再
          // 由 viewport 自己推。
          return SizedBox(
              height: tileWidth * 9 / 16,
              child: SingleChildScrollView(
                  key: const ValueKey('wallpaper-rail'),
                  scrollDirection: Axis.horizontal,
                  padding: EdgeInsets.zero,
                  child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (var i = 0; i < items; i++) ...[
                          if (i > 0) const SizedBox(width: gap),
                          tileAt(i),
                        ]
                      ])));
        }));
  }
}

class _WallpaperRailTile extends StatelessWidget {
  final String id, name;
  final double width;
  final Appearance appearance;
  final bool selected;
  final VoidCallback onTap;
  final Widget? placeholder;
  const _WallpaperRailTile(
      {required this.id,
      required this.name,
      required this.width,
      required this.appearance,
      required this.selected,
      required this.onTap,
      this.placeholder});

  @override
  Widget build(BuildContext context) {
    final s = SurfaceStyle.of(context);
    final radius = BorderRadius.circular(Design.dz(12));
    // 壁纸缩略图要裁剪，只能用 Material 的 shape；但蓝玻璃的选中态必须是
    // 四角短弧——和其他可选控件同一套框，否则「所有选中态一致」就破了。
    final side = BorderSide(
        color: selected
            ? (s.technicalFrame
                ? s.controlSide(true).color
                : s.accent.withValues(alpha: .55))
            : s.text.withValues(alpha: .1),
        width: selected ? Design.dz(1.5) : 1);
    final OutlinedBorder shape = s.technicalFrame
        ? TechnicalFrameBorder(
            radius: Design.dz(12),
            cornerLength: Design.px(10),
            cornerColor: selected ? s.accent : s.corner,
            side: side)
        : RoundedRectangleBorder(borderRadius: radius, side: side);
    return SizedBox(
        width: width,
        child: Material(
            color: s.text.withValues(alpha: .03),
            clipBehavior: Clip.antiAlias,
            shape: shape,
            child: InkWell(
                key: ValueKey('wallpaper-$id'),
                onTap: onTap,
                child: Stack(fit: StackFit.expand, children: [
                  if (id != 'custom' || appearance.wallpaperPath.isNotEmpty)
                    SceneBackground(
                        key: ValueKey('wallpaper-preview-$id'),
                        wallpaperCacheWidth: 360,
                        appearance: id == 'custom'
                            ? appearance.copyWith(wallpaper: 'custom')
                            : appearance,
                        child: const SizedBox.expand())
                  else
                    Center(child: placeholder),
                  Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: Container(
                          padding: EdgeInsets.fromLTRB(Design.dz(8),
                              Design.dz(16), Design.dz(8), Design.dz(7)),
                          decoration: const BoxDecoration(
                              gradient: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [
                                Color(0x00000000),
                                Color(0xC7000000)
                              ])),
                          child: Text(name,
                              textAlign: TextAlign.center,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontSize: Design.dz(12.5),
                                  color: Colors.white.withValues(alpha: .86)))))
                ]))));
  }
}

/// 卡片圆角：`.sld` 细轨 + 15×26 的竖胶囊滑块，两端 0 / 40 标尺。
class RadiusSetting extends StatelessWidget {
  final LauncherController controller;
  const RadiusSetting({super.key, required this.controller});
  @override
  Widget build(BuildContext context) {
    final c = controller, a = c.appearance, s = SurfaceStyle.of(context);
    return SettingBlock(
        title: '卡片圆角',
        note: '0 为直角 · 默认 28px · Nocturne 25',
        dense: true,
        padding: AppearanceSettings.blockPadding(),
        child: Row(children: [
          Text('0',
              style: TextStyle(
                  fontSize: Design.dz(13.5),
                  color: s.text.withValues(alpha: .4))),
          SizedBox(width: Design.dz(12)),
          Expanded(
              child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                      trackHeight: Design.dz(6),
                      activeTrackColor: s.accent,
                      inactiveTrackColor: s.text.withValues(alpha: .12),
                      thumbColor: s.text,
                      overlayShape: SliderComponentShape.noOverlay,
                      thumbShape: const _PillThumbShape(),
                      trackShape: const RoundedRectSliderTrackShape()),
                  child: Slider(
                      key: const ValueKey('radius-slider'),
                      value: a.radius,
                      min: 0,
                      max: 40,
                      divisions: 40,
                      onChanged: (v) =>
                          c.setAppearance(a.copyWith(radius: v), save: false),
                      onChangeEnd: (_) => c.persist()))),
          SizedBox(width: Design.dz(12)),
          Text('40',
              style: TextStyle(
                  fontSize: Design.dz(13.5),
                  color: s.text.withValues(alpha: .4))),
          SizedBox(width: Design.dz(16)),
          // 设计稿只有滑杆；数字输入是本项目原有能力，收成右下角 15 号的
          // 无边框小字段，不占视觉重心。
          SizedBox(
              width: Design.dz(56),
              child: TextFormField(
                  key: ValueKey('radius-number-${a.radius.round()}'),
                  initialValue: '${a.radius.round()}',
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.right,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(3)
                  ],
                  style: TextStyle(fontSize: Design.dz(15), color: s.accent),
                  decoration: const InputDecoration(
                      isDense: true,
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      suffixText: 'px',
                      contentPadding: EdgeInsets.zero),
                  onFieldSubmitted: (v) => c.setAppearance(a.copyWith(
                      radius: (double.tryParse(v) ?? a.radius).clamp(0, 40)))))
        ]));
  }
}

/// 竖胶囊滑块（设计稿 `.sld b`：15×26、8 圆角）。
class _PillThumbShape extends SliderComponentShape {
  const _PillThumbShape();
  @override
  Size getPreferredSize(bool isEnabled, bool isDiscrete) =>
      Size(Design.dz(15), Design.dz(26));
  @override
  void paint(PaintingContext context, Offset center,
      {required Animation<double> activationAnimation,
      required Animation<double> enableAnimation,
      required bool isDiscrete,
      required TextPainter labelPainter,
      required RenderBox parentBox,
      required SliderThemeData sliderTheme,
      required TextDirection textDirection,
      required double value,
      required double textScaleFactor,
      required Size sizeWithOverflow}) {
    final canvas = context.canvas;
    final rect = Rect.fromCenter(
        center: center, width: Design.dz(15), height: Design.dz(26));
    final paint = Paint()
      ..color = sliderTheme.thumbColor ?? Colors.white
      ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.white, Color(0xFFE2EAE6)]).createShader(rect);
    canvas.drawRRect(
        RRect.fromRectAndRadius(rect, Radius.circular(Design.dz(8))), paint);
  }
}

/// sim f9 右栏：实时预览 / 主题色说明 / 玻璃质感 / 返回桌面查看。
///
/// 预览框里放的是**真桌面**（顶栏 + 桌面 + 底栏），和源码同一条路径：
/// 1600×900 画布整体等比缩进 16:9 的框，`Theme` 换成按当前 `appearance`
/// 推出的预览主题，`EmbeddedContentPolicy(enabled: false)` 掐掉会启动第二份
/// 地图的原生嵌入，`IgnorePointer` 让它只读。主题样式 / 明暗 / 配色 / 圆角 /
/// 壁纸 / 毛玻璃任何一项一动，这里同一帧就跟着变，不用另写同步逻辑。
class DesktopPreview extends StatelessWidget {
  const DesktopPreview({super.key});
  @override
  Widget build(BuildContext context) {
    final s = SurfaceStyle.of(context),
        c = SettingsControllerScope.of(context),
        a = c.appearance;
    final palette = a.palette == 'custom'
        ? '自定义'
        : accentPresets
            .firstWhere((p) => p.id == a.palette,
                orElse: () => accentPresets.first)
            .name;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        Text('实时预览',
            style: TextStyle(
                fontSize: Design.dz(21.67), fontWeight: FontWeight.w500)),
        const Spacer(),
        Text('${s.dark ? '深色' : '浅色'} · $palette',
            style: TextStyle(
                fontSize: Design.dz(15), color: s.text.withValues(alpha: .4)))
      ]),
      SizedBox(height: Design.dz(18.33)),
      _LiveDesktopPreview(controller: c),
      SizedBox(height: Design.dz(16.67)),
      Row(children: [
        Container(
            width: Design.dz(43.33),
            height: Design.dz(43.33),
            decoration: BoxDecoration(
                color: s.accent,
                borderRadius: BorderRadius.circular(Design.dz(14)),
                boxShadow: [
                  BoxShadow(
                      color: s.accent.withValues(alpha: .35),
                      blurRadius: Design.dz(18))
                ])),
        SizedBox(width: Design.dz(16.67)),
        Expanded(
            child: Text('路线、播放按钮与选中状态\n使用同一组主题色',
                style: TextStyle(
                    fontSize: Design.dz(15),
                    height: 1.5,
                    color: s.text.withValues(alpha: .45))))
      ]),
      SizedBox(height: Design.dz(10)),
      Container(
          height: Design.dz(58),
          decoration: BoxDecoration(
              border: Border(
                  bottom: BorderSide(color: s.text.withValues(alpha: .055)))),
          child: Row(children: [
            Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('玻璃质感',
                      style: TextStyle(
                          fontSize: Design.dz(15),
                          color: s.text.withValues(alpha: .82))),
                  SizedBox(height: Design.dz(3)),
                  Text('静态反光，无实时模糊',
                      style: TextStyle(
                          fontSize: Design.dz(12),
                          color: s.text.withValues(alpha: .42)))
                ]),
            const Spacer(),
            DesignSwitch(
                key: const ValueKey('glass-switch'),
                value: a.glass,
                onChanged: (v) => c.setAppearance(a.copyWith(glass: v)))
          ])),
      const Spacer(),
      SizedBox(
          height: Design.dz(50),
          child: Material(
              color: Colors.transparent,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(Design.dz(14)),
                  side: BorderSide(color: s.accent.withValues(alpha: .35))),
              child: InkWell(
                  key: const ValueKey('back-to-desktop'),
                  onTap: c.home,
                  child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.home_outlined,
                            size: Design.dz(18), color: s.accent),
                        SizedBox(width: Design.dz(9)),
                        Text('返回桌面查看',
                            style: TextStyle(
                                fontSize: Design.dz(16), color: s.accent))
                      ]))))
    ]);
  }
}

/// 真桌面缩略：和桌面用同一套组件（[Header] / [Desktop] / [BottomDock]），
/// 只把主题换成「按预览值算出来的那套」，所以预览和自己手改的桌面永远一致。
class _LiveDesktopPreview extends StatelessWidget {
  final LauncherController controller;
  const _LiveDesktopPreview({required this.controller});

  @override
  Widget build(BuildContext context) {
    final s = SurfaceStyle.of(context);
    // 系统明暗取原生上报值（与 [LauncherApp] 同一入参），壁纸/配色/圆角/
    // 材质全部来自当前 appearance——设置一动，下一次 build 就是新结果。
    final previewStyle = SurfaceStyle.from(
        controller.appearance, controller.native.value['dark'] == true,
        adaptToWallpaper: true);
    return AspectRatio(
        key: const ValueKey('live-preview'),
        aspectRatio: 16 / 9,
        child: Container(
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(Design.dz(16))),
            // 描边画在前景，否则会被铺满的桌面盖住。
            foregroundDecoration: BoxDecoration(
                borderRadius: BorderRadius.circular(Design.dz(16)),
                border: Border.all(color: s.text.withValues(alpha: .08))),
            child: Theme(
                data: launcherTheme(previewStyle),
                child: IgnorePointer(
                    child: EmbeddedContentPolicy(
                        enabled: false,
                        child: FittedBox(
                            fit: BoxFit.contain,
                            child: SizedBox(
                                width: Design.canvasWidth,
                                height: 900,
                                child: SceneBackground(
                                    appearance: controller.appearance,
                                    wallpaperCacheWidth: 640,
                                    child: Column(children: [
                                      Header(controller: controller),
                                      Expanded(
                                          child:
                                              Desktop(controller: controller)),
                                      Padding(
                                          padding: EdgeInsets.fromLTRB(
                                              Design.dz(32),
                                              0,
                                              Design.dz(32),
                                              Design.dz(16)),
                                          child: BottomDock(
                                              controller: controller))
                                    ])))))))));
  }
}

class SettingsControllerScope extends InheritedWidget {
  final LauncherController controller;
  const SettingsControllerScope(
      {super.key, required this.controller, required super.child});
  static LauncherController of(BuildContext c) => c
      .dependOnInheritedWidgetOfExactType<SettingsControllerScope>()!
      .controller;
  @override
  bool updateShouldNotify(SettingsControllerScope old) =>
      old.controller != controller;
}

class CustomColorRow extends StatefulWidget {
  final LauncherController controller;
  const CustomColorRow({super.key, required this.controller});
  @override
  State<CustomColorRow> createState() => _CustomColorRowState();
}

class _CustomColorRowState extends State<CustomColorRow> {
  late final TextEditingController input;
  String? error;
  @override
  void initState() {
    super.initState();
    input = TextEditingController(text: widget.controller.appearance.custom);
  }

  @override
  void didUpdateWidget(CustomColorRow old) {
    super.didUpdateWidget(old);
    if (old.controller.appearance.custom != input.text &&
        !input.selection.isValid)
      input.text = widget.controller.appearance.custom;
  }

  @override
  void dispose() {
    input.dispose();
    super.dispose();
  }

  void apply() {
    if (!RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch(input.text)) {
      setState(() => error = '使用 #RRGGBB');
      return;
    }
    setState(() => error = null);
    widget.controller.setAppearance(widget.controller.appearance
        .copyWith(palette: 'custom', custom: input.text.toUpperCase()));
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller, s = SurfaceStyle.of(context);
    return Row(children: [
      Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('自定义颜色', style: TextStyle(fontSize: Design.px(22))),
        SizedBox(height: Design.px(10)),
        Text('从取色器选择，或输入 HEX 色值',
            style: TextStyle(fontSize: Design.px(17), color: s.muted))
      ])),
      InkWell(
          key: const ValueKey('custom-color'),
          onTap: () async {
            final value = await editCustomColor(context, c);
            if (value != null) input.text = value;
          },
          child: GlassSurface(
              tone: SurfaceTone.soft,
              radius: s.radius * .61,
              padding: EdgeInsets.all(Design.px(8)),
              shadow: false,
              child: Container(
                  width: Design.px(34),
                  height: Design.px(34),
                  decoration: BoxDecoration(
                      color: Color(0xFF000000 |
                          int.parse(c.appearance.custom.substring(1),
                              radix: 16)),
                      borderRadius: BorderRadius.circular(s.radius * .29))))),
      SizedBox(width: Design.px(12)),
      SizedBox(
          width: Design.px(138),
          child: TextField(
              key: const ValueKey('hex-field'),
              controller: input,
              maxLength: 7,
              style:
                  TextStyle(fontSize: Design.px(20), fontFamily: 'monospace'),
              decoration: InputDecoration(
                  counterText: '', errorText: error, isDense: true),
              onSubmitted: (_) => apply())),
      TextButton(onPressed: apply, child: const Text('应用'))
    ]);
  }
}

Future<String?> editCustomColor(
    BuildContext context, LauncherController c) async {
  final result = await showCustomColorPicker(context,
      title: '自定义主题色',
      subtitle: '从完整色域取色，或选择常用颜色',
      initial: Color(
          0xFF000000 | int.parse(c.appearance.custom.substring(1), radix: 16)),
      presets: [
        ...accentPresets.map((item) => item.seed),
        ...standardPickerColors
      ]);
  if (result != null) {
    c.setAppearance(c.appearance.copyWith(palette: 'custom', custom: result));
  }
  return result;
}

class PageMotionSettings extends StatelessWidget {
  final LauncherController controller;
  const PageMotionSettings({super.key, required this.controller});
  @override
  Widget build(BuildContext context) {
    final s = SurfaceStyle.of(context), c = controller;
    return SingleChildScrollView(
        key: const PageStorageKey('motion-settings-scroll'),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          // sim f12 · 桌面翻屏：五张 fxcard 一行排开（flex:1，等高）。
          SettingBlock(
              title: '桌面翻屏',
              note: '页面与指示条跟随手势，底栏保持固定',
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    IntrinsicHeight(
                        child: Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                          for (final (index, option)
                              in pageEffects.indexed) ...[
                            if (index > 0) SizedBox(width: Design.dz(11.67)),
                            Expanded(
                                child: SettingsChoiceCard(
                                    key: ValueKey('transition-${option.id}'),
                                    title: option.name,
                                    detail: option.detail,
                                    selected: c.appearance.pageTransition ==
                                        option.id,
                                    onTap: () => c.setAppearance(c.appearance
                                        .copyWith(pageTransition: option.id)),
                                    preview:
                                        PageEffectPreview(effect: option.id)))
                          ]
                        ])),
                    SizedBox(height: Design.dz(13.33)),
                    Text(
                        '左右拖动桌面，松手后自动吸附；也可点击页码切换。平移只移动页面图层，适合车机使用。系统要求减少动态效果时暂停动画。',
                        style: TextStyle(
                            fontSize: Design.dz(13.5),
                            height: LauncherType.lineLoose,
                            color: s.text.withValues(alpha: .42))),
                  ])),
          SizedBox(height: Design.dz(11.67)),
          SpectrumSettings(controller: c),
        ]));
  }
}
