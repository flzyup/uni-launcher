import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../controller/launcher_controller.dart';
import '../model/appearance.dart';
import '../model/page_motion.dart';
import '../theme/design_tokens.dart';
import '../theme/launcher_theme.dart';
import '../widgets/glass_surface.dart';
import '../widgets/desktop.dart';
import '../widgets/bottom_dock.dart';
import '../widgets/scene_background.dart';
import '../widgets/uni_icon.dart';
import '../widgets/launcher_dialog.dart';
import '../widgets/embedded_navigation.dart';
import '../widgets/system_settings.dart';
import '../widgets/setting_block.dart';
import '../widgets/spectrum_painter.dart';
import '../ota/update_controller.dart';
import '../ota/update_ui.dart';
import '../widgets/ambient_light_settings.dart';
import '../widgets/color_picker.dart';
import '../platform/ambient_light.dart';

class SettingsScreen extends StatelessWidget {
  final LauncherController controller;
  final UpdateController? update;
  const SettingsScreen({super.key, required this.controller, this.update});
  @override
  Widget build(BuildContext context) {
    final c = controller, s = SurfaceStyle.of(context);
    return SettingsControllerScope(
        controller: c,
        child: Padding(
            padding: EdgeInsets.fromLTRB(
                Design.px(32), Design.px(16), Design.px(32), Design.px(24)),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                      height: Design.px(78),
                      child: Row(children: [
                        IconAction(
                            icon: Icons.arrow_back,
                            label: '返回桌面',
                            onTap: c.home,
                            soft: true,
                            size: Design.px(64)),
                        SizedBox(width: Design.px(24)),
                        Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text('桌面设置',
                                  style: TextStyle(
                                      fontSize: Design.px(36),
                                      fontWeight: FontWeight.w500)),
                              SizedBox(height: Design.px(9)),
                              Text('外观、配色与系统设置',
                                  style: TextStyle(
                                      fontSize: Design.px(20), color: s.muted))
                            ]),
                        const Spacer()
                      ])),
                  SizedBox(height: Design.px(24)),
                  Container(
                      height: Design.px(60),
                      decoration: BoxDecoration(
                          border: Border(bottom: BorderSide(color: s.edge))),
                      child: Row(children: [
                        for (final tab in [
                          ('appearance', '外观主题'),
                          ('motion', '切换动效'),
                          ('ambient', '氛围灯'),
                          ('system', '系统设置'),
                          ('about', '关于')
                        ])
                          _SettingsTab(controller: c, id: tab.$1, label: tab.$2)
                      ])),
                  SizedBox(height: Design.px(24)),
                  Expanded(
                      child: switch (c.settingsTab) {
                    'appearance' => LayoutBuilder(
                        builder: (context, box) => SingleChildScrollView(
                            child: SizedBox(
                                height: box.maxHeight < Design.px(620)
                                    ? Design.px(620)
                                    : box.maxHeight,
                                child: AppearanceSettings(controller: c)))),
                    'motion' => PageMotionSettings(controller: c),
                    'ambient' => AmbientLightSettingsTab(controller: c),
                    'system' => SystemSettingsPanel(controller: c),
                    'about' => update == null
                        ? const Center(child: Text('更新服务暂不可用'))
                        : AboutPanel(update: update!),
                    _ => SystemSettingsPanel(controller: c)
                  }),
                ])));
  }
}

class _SettingsTab extends StatelessWidget {
  final LauncherController controller;
  final String id, label;
  const _SettingsTab(
      {required this.controller, required this.id, required this.label});
  @override
  Widget build(BuildContext context) {
    final s = SurfaceStyle.of(context), selected = controller.settingsTab == id;
    return Padding(
        padding: EdgeInsets.only(right: Design.px(12)),
        child: InkWell(
            key: ValueKey('tab-$id'),
            onTap: () => controller.tab(id),
            child: Padding(
                padding: EdgeInsets.symmetric(horizontal: Design.px(30)),
                child: Container(
                    key: ValueKey('tab-indicator-$id'),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                        border: Border(
                            bottom: BorderSide(
                                width: Design.px(3),
                                color:
                                    selected ? s.accent : Colors.transparent))),
                    child: Text(label,
                        style: TextStyle(
                            fontSize: Design.px(24),
                            color: selected ? s.accent : s.muted))))));
  }
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
          LayoutBuilder(
              builder: (context, box) => Wrap(
                      spacing: Design.px(14),
                      runSpacing: Design.px(14),
                      children: [
                        for (final entry in spectrumStyleLabels.entries)
                          SizedBox(
                              width: (box.maxWidth - Design.px(14)) / 2,
                              child: OutlinedButton(
                                  key: ValueKey('spectrum-style-${entry.key}'),
                                  style: s.selectionStyle(
                                      c.appearance.spectrumStyle == entry.key),
                                  onPressed: () => c.setAppearance(c.appearance
                                      .copyWith(spectrumStyle: entry.key)),
                                  child: Padding(
                                      padding: EdgeInsets.symmetric(
                                          vertical: Design.px(16)),
                                      child: Column(children: [
                                        SizedBox(
                                            height: Design.px(38),
                                            width: double.infinity,
                                            child: SpectrumStylePreview(
                                                style: entry.key,
                                                accent: s.accent,
                                                edge: s.edge)),
                                        SizedBox(height: Design.px(12)),
                                        Text(entry.value),
                                      ]))))
                      ])),
          SizedBox(height: Design.px(16)),
          Text('底栏右侧左右滑动可切换歌词和频谱；预览为静态示意。',
              style: TextStyle(fontSize: Design.px(18), color: s.muted)),
          SizedBox(height: Design.px(14)),
          DesignSwitchTile(
              key: const ValueKey('dock-music-progress-switch'),
              contentPadding: EdgeInsets.zero,
              title: const Text('音乐进度动态背景'),
              subtitle: const Text('背景长度同步播放进度，光晕向进度线左侧展开'),
              value: c.appearance.dockMusicProgressBackground,
              onChanged: (value) => c.setAppearance(
                  c.appearance.copyWith(dockMusicProgressBackground: value))),
        ]));
  }
}

/// The ambient light tab. It listens to the shared service so the capability
/// line stays current, but the live colour is delivered through its own
/// notifier and never rebuilds this page.
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
                  SettingBlock(
                      title: '音乐律动氛围灯',
                      note: '按正在播放的音乐频谱换算颜色与亮度',
                      child: AmbientLightSettingsPanel(
                          settings: c.ambientLight,
                          service: AmbientLightService.shared,
                          onChanged: c.setAmbientLight)),
                ]));
  }
}

class AppearanceSettings extends StatelessWidget {
  final LauncherController controller;
  const AppearanceSettings({super.key, required this.controller});
  @override
  Widget build(BuildContext context) {
    final c = controller, a = c.appearance, s = SurfaceStyle.of(context);
    return Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Expanded(
          child: LayoutBuilder(
              builder: (context, box) => SingleChildScrollView(
                  key: const PageStorageKey('appearance-settings-scroll'),
                  child: Column(children: [
                    SettingBlock(
                        title: '主题样式',
                        note: '材质与控件外观',
                        child: Row(children: [
                          for (final style in [
                            ('blueGlass', '深蓝玻璃'),
                            ('classic', '经典')
                          ])
                            Expanded(
                                child: Padding(
                                    padding: EdgeInsets.only(
                                        right: style.$1 == 'blueGlass'
                                            ? Design.px(14)
                                            : 0),
                                    child: OutlinedButton(
                                        key:
                                            ValueKey('theme-style-${style.$1}'),
                                        style: OutlinedButton.styleFrom(
                                            shape: s.controlShape(
                                                selected:
                                                    a.themeStyle == style.$1),
                                            foregroundColor: a.themeStyle == style.$1
                                                ? s.accent
                                                : s.text,
                                            backgroundColor:
                                                a.themeStyle == style.$1
                                                    ? s.accent
                                                        .withValues(alpha: .11)
                                                    : s.soft,
                                            side: s.controlSide(
                                                a.themeStyle == style.$1)),
                                        onPressed: () => c.setAppearance(a.copyWith(themeStyle: style.$1)),
                                        child: Text(style.$2))))
                        ])),
                    SizedBox(height: Design.px(16)),
                    SettingBlock(
                        compact: box.maxHeight < Design.px(650),
                        title: '主题风格',
                        note: '智能调色会匹配壁纸明暗',
                        child: Row(children: [
                          for (final mode in [
                            ('smart', Icons.auto_awesome_outlined, '智能调色'),
                            ('system', Icons.brightness_auto_outlined, '跟随系统'),
                            ('light', Icons.light_mode_outlined, '浅色'),
                            ('dark', Icons.dark_mode_outlined, '深色')
                          ])
                            Expanded(
                                child: Padding(
                                    padding: EdgeInsets.only(
                                        right: mode.$1 == 'dark'
                                            ? 0
                                            : Design.px(14)),
                                    child: SizedBox(
                                        height: Design.px(66),
                                        child: OutlinedButton(
                                            key: ValueKey('mode-${mode.$1}'),
                                            onPressed: () => c.setAppearance(
                                                a.copyWith(mode: mode.$1)),
                                            style: s.selectionStyle(
                                                a.mode == mode.$1),
                                            child: Stack(
                                                alignment: Alignment.center,
                                                children: [
                                                  Row(
                                                      mainAxisAlignment:
                                                          MainAxisAlignment
                                                              .center,
                                                      children: [
                                                        DesignIcon(mode.$2,
                                                            size:
                                                                Design.px(26)),
                                                        SizedBox(
                                                            width:
                                                                Design.px(14)),
                                                        Text(mode.$3,
                                                            style: TextStyle(
                                                                fontSize:
                                                                    Design.px(
                                                                        22)))
                                                      ]),
                                                  if (a.mode == mode.$1)
                                                    Align(
                                                        alignment: Alignment
                                                            .centerRight,
                                                        child: UniIcon('check',
                                                            size:
                                                                Design.px(20)))
                                                ])))))
                        ])),
                    SizedBox(height: Design.px(16)),
                    SettingBlock(
                        compact: box.maxHeight < Design.px(650),
                        title: '主题配色',
                        note: '同步改变强调色与背景氛围',
                        child: Row(children: [
                          for (final item in [
                            ...accentPresets.map((p) => (p.id, p.name, p.seed)),
                            (
                              'custom',
                              '自定义',
                              Color(0xFF000000 |
                                  int.parse(a.custom.substring(1), radix: 16))
                            )
                          ])
                            Expanded(
                                child: Padding(
                                    padding: EdgeInsets.only(
                                        right: item.$1 == 'custom'
                                            ? 0
                                            : Design.px(14)),
                                    child: SizedBox(
                                        height: Design.px(138),
                                        child: OutlinedButton(
                                            key: ValueKey(item.$1 == 'custom'
                                                ? 'custom-color'
                                                : 'palette-${item.$1}'),
                                            onPressed: () => item.$1 == 'custom'
                                                ? editCustomColor(context, c)
                                                : c.setAppearance(a.copyWith(
                                                    palette: item.$1)),
                                            style: s
                                                .selectionStyle(
                                                    a.palette == item.$1)
                                                .copyWith(
                                                    padding: WidgetStatePropertyAll(
                                                        EdgeInsets.symmetric(
                                                            vertical:
                                                                Design.px(12),
                                                            horizontal:
                                                                Design.px(5)))),
                                            child:
                                                Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                                              Container(
                                                  width: Design.px(59),
                                                  height: Design.px(59),
                                                  decoration: BoxDecoration(
                                                      shape: BoxShape.circle,
                                                      color: item.$3),
                                                  child: a.palette == item.$1
                                                      ? const Center(
                                                          child: UniIcon(
                                                              'check',
                                                              size: 22,
                                                              color:
                                                                  Colors.white))
                                                      : null),
                                              SizedBox(height: Design.px(14)),
                                              Text(item.$2,
                                                  maxLines: 1,
                                                  style: TextStyle(
                                                      fontSize: Design.px(21)))
                                            ]))))),
                        ])),
                    SizedBox(height: Design.px(16)),
                    WallpaperSetting(controller: c),
                    SizedBox(height: Design.px(16)),
                    RadiusSetting(controller: c),
                    SizedBox(height: Design.px(16)),
                  ])))),
      SizedBox(width: Design.px(24)),
      SizedBox(
          width: Design.px(620),
          child: GlassSurface(
              padding: EdgeInsets.all(Design.px(30)),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(children: [
                      Text('实时预览',
                          style: TextStyle(
                              fontSize: Design.px(26),
                              fontWeight: FontWeight.w500)),
                      const Spacer(),
                      Text(
                          '${s.dark ? '深色' : '浅色'} · ${a.palette == 'custom' ? '自定义' : accentPresets.firstWhere((p) => p.id == a.palette).name}',
                          style: TextStyle(
                              fontSize: Design.px(18), color: s.muted))
                    ]),
                    SizedBox(height: Design.px(22)),
                    const Flexible(child: DesktopPreview()),
                    SizedBox(height: Design.px(22)),
                    Row(children: [
                      Container(
                          width: Design.px(52),
                          height: Design.px(52),
                          decoration: BoxDecoration(
                              color: s.accent,
                              borderRadius:
                                  BorderRadius.circular(s.radius * .61))),
                      SizedBox(width: Design.px(20)),
                      Expanded(
                          child: Text('路线、播放按钮与选中状态\n使用同一组主题色',
                              style: TextStyle(
                                  fontSize: Design.px(18),
                                  height: 1.5,
                                  color: s.muted)))
                    ]),
                    SizedBox(height: Design.px(16)),
                    DesignSwitchTile(
                        key: const ValueKey('glass-switch'),
                        contentPadding: EdgeInsets.zero,
                        title: Text(s.technicalFrame ? '玻璃质感' : '毛玻璃'),
                        subtitle: Text(
                            s.technicalFrame ? '静态反光，无实时模糊' : '关闭后保留半透明材质'),
                        value: a.glass,
                        onChanged: (v) =>
                            c.setAppearance(a.copyWith(glass: v))),
                    SizedBox(height: Design.px(18)),
                    OutlinedButton.icon(
                        onPressed: c.home,
                        icon: const UniIcon('home'),
                        label: const Text('返回桌面查看'))
                  ]))),
    ]);
  }
}

/// The preview reuses the actual desktop renderer rather than a separate icon sketch.
class DesktopPreview extends StatelessWidget {
  const DesktopPreview({super.key});
  @override
  Widget build(BuildContext context) {
    final c = SettingsControllerScope.of(context),
        s = SurfaceStyle.of(context),
        previewStyle = SurfaceStyle.from(
            c.appearance, c.native.value['dark'] == true,
            adaptToWallpaper: true);
    return Theme(
        data: launcherTheme(previewStyle),
        child: AspectRatio(
            aspectRatio: 16 / 9,
            child: ClipRRect(
                borderRadius: BorderRadius.circular(s.radius * .64),
                child: IgnorePointer(
                    child: EmbeddedContentPolicy(
                        enabled: false,
                        child: FittedBox(
                            fit: BoxFit.contain,
                            child: SizedBox(
                                width: Design.canvasWidth,
                                height: 900,
                                child: SceneBackground(
                                    appearance: c.appearance,
                                    child: Column(children: [
                                      Header(controller: c),
                                      Expanded(child: Desktop(controller: c)),
                                      Padding(
                                          padding: EdgeInsets.fromLTRB(
                                              Design.px(32),
                                              0,
                                              Design.px(32),
                                              Design.px(16)),
                                          child: BottomDock(controller: c))
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

class WallpaperSetting extends StatelessWidget {
  final LauncherController controller;
  const WallpaperSetting({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    final c = controller, a = c.appearance, s = SurfaceStyle.of(context);
    return SettingBlock(
        title: '桌面壁纸',
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          Text('叠加主题渐变',
              style: TextStyle(
                  color: a.wallpaper == 'gradient' ? s.muted : null,
                  fontSize: Design.px(18))),
          SizedBox(width: Design.px(10)),
          Switch(
              key: const ValueKey('wallpaper-overlay'),
              value: a.wallpaper == 'gradient' ? true : a.wallpaperOverlay,
              onChanged: a.wallpaper == 'gradient'
                  ? null
                  : (value) =>
                      c.setAppearance(a.copyWith(wallpaperOverlay: value)))
        ]),
        child: LayoutBuilder(builder: (context, box) {
          final width = (box.maxWidth - Design.px(36)) / 4;
          return Wrap(
              spacing: Design.px(12),
              runSpacing: Design.px(12),
              children: [
                for (final preset in wallpaperPresets)
                  SizedBox(
                      width: width,
                      child: _WallpaperTile(
                          id: preset.id,
                          name: preset.name,
                          appearance: a.copyWith(wallpaper: preset.id),
                          selected: a.wallpaper == preset.id,
                          onTap: () => c.setAppearance(a.copyWith(
                              wallpaper: preset.id, mode: 'smart')))),
                SizedBox(
                    width: width,
                    child: _WallpaperTile(
                        id: 'custom',
                        name: '本地图片',
                        appearance: a,
                        selected: a.wallpaper == 'custom',
                        placeholder: Icon(Icons.image_outlined,
                            size: Design.px(31), color: s.muted),
                        onTap: () async {
                          try {
                            final picked = await c.gateway.pickWallpaper();
                            if (picked != null) {
                              c.setAppearance(c.appearance.copyWith(
                                  wallpaper: 'custom',
                                  wallpaperPath: picked.path,
                                  wallpaperLuminance: picked.luminance,
                                  mode: 'smart'));
                            }
                          } catch (_) {
                            if (context.mounted) {
                              showLauncherToast(
                                  context, '无法读取这张图片，请选择 JPG 或 PNG');
                            }
                          }
                        }))
              ]);
        }));
  }
}

class _WallpaperTile extends StatelessWidget {
  final String id, name;
  final Appearance appearance;
  final bool selected;
  final VoidCallback onTap;
  final Widget? placeholder;
  const _WallpaperTile(
      {required this.id,
      required this.name,
      required this.appearance,
      required this.selected,
      required this.onTap,
      this.placeholder});

  @override
  Widget build(BuildContext context) {
    final s = SurfaceStyle.of(context);
    return Material(
        color: selected
            ? Color.alphaBlend(s.accent.withValues(alpha: .11), s.soft)
            : s.soft,
        clipBehavior: Clip.antiAlias,
        shape: s.controlShape(selected: selected).copyWith(
            side: s.technicalFrame
                ? s.controlSide(selected)
                : BorderSide(
                    color: selected ? s.accent : s.edge,
                    width: selected ? Design.px(2) : 1)),
        child: InkWell(
            key: ValueKey('wallpaper-$id'),
            onTap: onTap,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              AspectRatio(
                  key: ValueKey('wallpaper-preview-$id'),
                  aspectRatio: 16 / 9,
                  child: Stack(fit: StackFit.expand, children: [
                    if (id != 'custom' || appearance.wallpaperPath.isNotEmpty)
                      SceneBackground(
                          wallpaperCacheWidth: 360,
                          appearance: id == 'custom'
                              ? appearance.copyWith(wallpaper: 'custom')
                              : appearance,
                          child: const SizedBox.expand())
                    else
                      Center(child: placeholder),
                    if (selected)
                      Align(
                          alignment: Alignment.topRight,
                          child: Padding(
                              padding: EdgeInsets.all(Design.px(7)),
                              child: Container(
                                  width: Design.px(25),
                                  height: Design.px(25),
                                  decoration: BoxDecoration(
                                      color: s.accent, shape: BoxShape.circle),
                                  child: Center(
                                      child: UniIcon('check',
                                          size: Design.px(15),
                                          color: s.accentText)))))
                  ])),
              SizedBox(
                  height: Design.px(38),
                  child: Center(
                      child: Text(name,
                          maxLines: 1,
                          style: TextStyle(fontSize: Design.px(16)))))
            ])));
  }
}

class RadiusSetting extends StatelessWidget {
  final LauncherController controller;
  const RadiusSetting({super.key, required this.controller});
  @override
  Widget build(BuildContext context) {
    final c = controller, a = c.appearance, s = SurfaceStyle.of(context);
    return GlassSurface(
        padding: EdgeInsets.symmetric(
            horizontal: Design.px(30), vertical: Design.px(22)),
        child: Row(children: [
          SizedBox(
              width: Design.px(228),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('卡片圆角', style: TextStyle(fontSize: Design.px(23))),
                    SizedBox(height: Design.px(10)),
                    Text('0 为直角 · 默认 28px',
                        style:
                            TextStyle(fontSize: Design.px(17), color: s.muted))
                  ])),
          Text('0', style: TextStyle(color: s.muted)),
          Expanded(
              child: Slider(
                  key: const ValueKey('radius-slider'),
                  value: a.radius,
                  min: 0,
                  max: 40,
                  divisions: 40,
                  onChanged: (v) =>
                      c.setAppearance(a.copyWith(radius: v), save: false),
                  onChangeEnd: (_) => c.persist())),
          Text('40', style: TextStyle(color: s.muted)),
          SizedBox(width: Design.px(18)),
          SizedBox(
              width: Design.px(122),
              child: TextFormField(
                  key: ValueKey('radius-number-${a.radius.round()}'),
                  initialValue: '${a.radius.round()}',
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(3)
                  ],
                  style: TextStyle(fontSize: Design.px(24)),
                  decoration: const InputDecoration(suffixText: 'px'),
                  onFieldSubmitted: (v) => c.setAppearance(a.copyWith(
                      radius: (double.tryParse(v) ?? a.radius).clamp(0, 40)))))
        ]));
  }
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
        child: Column(children: [
      SettingBlock(
          title: '桌面翻屏',
          note: '页面与指示条跟随手势，底栏保持固定',
          child: LayoutBuilder(
              builder: (context, box) => Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Wrap(
                            spacing: Design.px(18),
                            runSpacing: Design.px(18),
                            children: [
                              for (final option in pageEffects)
                                SizedBox(
                                    width: (box.maxWidth - Design.px(36)) / 3,
                                    child: OutlinedButton(
                                        key:
                                            ValueKey('transition-${option.id}'),
                                        style: s.selectionStyle(
                                            c.appearance.pageTransition ==
                                                option.id),
                                        onPressed: () => c.setAppearance(
                                            c.appearance.copyWith(
                                                pageTransition: option.id)),
                                        child: Padding(
                                            padding: EdgeInsets.symmetric(
                                                vertical: Design.px(24)),
                                            child: Column(children: [
                                              Text(option.name,
                                                  style: TextStyle(
                                                      fontSize: Design.px(26))),
                                              SizedBox(height: Design.px(10)),
                                              Text(option.detail,
                                                  style: TextStyle(
                                                      fontSize: Design.px(18),
                                                      color: s.muted)),
                                              SizedBox(height: Design.px(12)),
                                              UniIcon('check',
                                                  size: Design.px(24),
                                                  color: c.appearance
                                                              .pageTransition ==
                                                          option.id
                                                      ? s.accent
                                                      : Colors.transparent)
                                            ])))),
                            ]),
                        SizedBox(height: Design.px(26)),
                        Text(
                            '左右拖动桌面，松手后自动吸附；也可点击页码切换。平移只移动页面图层，适合车机使用。系统要求减少动态效果时暂停动画。',
                            style: TextStyle(
                                fontSize: Design.px(21),
                                color: s.muted,
                                height: 1.6)),
                      ]))),
      SizedBox(height: Design.px(16)),
      SpectrumSettings(controller: c),
    ]));
  }
}
