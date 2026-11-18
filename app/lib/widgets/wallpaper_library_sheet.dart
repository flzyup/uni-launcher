import 'package:flutter/material.dart';

import '../controller/launcher_controller.dart';
import '../model/appearance.dart';
import '../platform/native_gateway.dart';
import '../theme/design_tokens.dart';
import '../theme/launcher_theme.dart';
import 'choice_button.dart';
import 'launcher_dialog.dart';
import 'scene_background.dart';
import 'uni_icon.dart';

/// 壁纸库（eclipse 设计稿 f28）：独立网格屏，替代「外观与壁纸」里那条内联横排。
///
/// 数据全部走源码既有链路：`Appearance.wallpaper` / `wallpaperPresets` /
/// `gateway.pickWallpaper()`，点一下就应用（与内联横排同一行为，不做二次确认）。
///
/// 设计稿里有、源码暂时接不上的三处，一律按「看得见但不假装能用」处理：
///   · 动态壁纸开关 —— 原车没有动态壁纸接口，置灰并写明原因；
///   · 「动态」分类 —— 0 张，空态提示；
///   · 长按删除本地图片 —— 无删除接口，不做手势，只在页脚注明。
Future<void> showWallpaperLibrary(
        BuildContext context, LauncherController controller) =>
    showLauncherSheet<void>(
      context,
      title: '壁纸库',
      subtitle: null,
      closeLabel: '关闭壁纸库',
      width: Design.px(1440),
      glowType: 'clockWeather',
      titleWidget: _LibraryHeader(controller: controller),
      builder: (context) => _WallpaperLibrary(controller: controller),
    );

class _LibraryHeader extends StatelessWidget {
  final LauncherController controller;
  const _LibraryHeader({required this.controller});

  @override
  Widget build(BuildContext context) {
    final a = controller.appearance, s = SurfaceStyle.of(context);
    final name = wallpaperPresets
        .firstWhere((p) => p.id == a.wallpaper,
            orElse: () => const WallpaperPreset('', '自定义图片'))
        .name;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('壁纸库',
          style:
              TextStyle(fontSize: Design.px(34), fontWeight: FontWeight.w500)),
      SizedBox(height: Design.px(12)),
      Text('${_allItems.length} 张 · 当前「$name」',
          style: TextStyle(fontSize: Design.px(20), color: s.muted)),
    ]);
  }
}

/// 壁纸库的条目清单：主题渐变 + 六个系统预设 + 本地图片入口。
List<_WallpaperItem> get _allItems => [
      for (final preset in wallpaperPresets)
        _WallpaperItem(
            id: preset.id,
            name: preset.name,
            category: preset.id == 'gradient'
                ? _Category.gradient
                : _Category.system),
      const _WallpaperItem(
          id: 'custom', name: '本地图片', category: _Category.local),
    ];

enum _Category { gradient, system, local, dynamic }

class _WallpaperItem {
  final String id, name;
  final _Category category;
  const _WallpaperItem(
      {required this.id, required this.name, required this.category});
}

class _WallpaperLibrary extends StatefulWidget {
  final LauncherController controller;
  const _WallpaperLibrary({required this.controller});
  @override
  State<_WallpaperLibrary> createState() => _WallpaperLibraryState();
}

class _WallpaperLibraryState extends State<_WallpaperLibrary> {
  _Category? _filter;

  static const _perPage = 8;

  List<_WallpaperItem> get _visible => _filter == null
      ? _allItems
      : _allItems.where((item) => item.category == _filter).toList();

  Future<void> _pickLocal() async {
    final c = widget.controller;
    PickedWallpaper? picked;
    try {
      picked = await c.gateway.pickWallpaper();
    } catch (_) {
      picked = null;
    }
    if (picked == null) {
      // 取消、没给存储权限、当前环境根本没有文件选择器（Windows 预览）都走
      // 这里。以前直接 return，点下去一点反馈都没有，看起来就是按键坏了。
      if (mounted) showLauncherToast(context, '没有选中图片：本地导入需要文件选择器与存储权限');
      return;
    }
    c.setAppearance(c.appearance.copyWith(
        wallpaper: 'custom',
        wallpaperPath: picked.path,
        wallpaperLuminance: picked.luminance,
        mode: 'smart'));
    if (mounted) setState(() => _filter = _Category.local);
  }

  @override
  Widget build(BuildContext context) {
    final s = SurfaceStyle.of(context);
    final items = _visible;
    return SingleChildScrollView(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _dynamicRow(s),
      SizedBox(height: Design.px(20)),
      _tabs(s),
      SizedBox(height: Design.px(20)),
      if (items.isEmpty)
        _emptyState(s)
      else
        LayoutBuilder(builder: (context, box) {
          // 四列等宽：容器宽度减三档间距再除以四，跟着弹层实际宽度走。
          final width = (box.maxWidth - Design.px(14) * 3) / 4;
          return Wrap(
              spacing: Design.px(14),
              runSpacing: Design.px(14),
              children: [
                for (final item in items.take(_perPage))
                  SizedBox(width: width, child: _tile(item, s))
              ]);
        }),
      if (items.length > _perPage) ...[
        SizedBox(height: Design.px(14)),
        Text('第 1 / ${(items.length / _perPage).ceil()} 屏 · 每屏 $_perPage 张',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: Design.px(16), color: s.muted)),
      ],
      SizedBox(height: Design.px(22)),
      _footer(s),
    ]));
  }

  Widget _dynamicRow(SurfaceStyle s) => Row(children: [
        Text('动态壁纸',
            style: TextStyle(fontSize: Design.px(20), color: s.text)),
        SizedBox(width: Design.px(14)),
        // 原车没有动态壁纸订阅接口，开关置灰但不隐藏：让人知道这一版没有。
        DesignSwitch(
            key: const ValueKey('wallpaper-dynamic-switch'),
            value: false,
            onChanged: null),
        SizedBox(width: Design.px(10)),
        Expanded(
            child: Text('待接入 · 原车未提供动态壁纸接口（设计稿的「行车时自动定格首帧」需要视频壁纸解码）',
                style: TextStyle(fontSize: Design.px(16), color: s.muted))),
      ]);

  Widget _tabs(SurfaceStyle s) {
    Widget tab(String label, _Category? filter, int count) {
      final selected = _filter == filter;
      return Material(
          color: selected ? s.accent.withValues(alpha: .11) : s.soft,
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(s.controlRadius),
              side: BorderSide(
                  color: selected ? s.accent.withValues(alpha: .55) : s.edge)),
          child: InkWell(
              key: ValueKey('wallpaper-tab-${filter?.name ?? 'all'}'),
              onTap: () => setState(() => _filter = filter),
              child: Padding(
                  padding: EdgeInsets.symmetric(
                      horizontal: Design.px(22), vertical: Design.px(11)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Text(label,
                        style: TextStyle(
                            fontSize: Design.px(19),
                            color: selected ? s.accent : s.text)),
                    SizedBox(width: Design.px(8)),
                    Text('$count',
                        style: TextStyle(
                            fontSize: Design.px(16), color: s.muted)),
                  ]))));
    }

    int countOf(_Category? filter) => filter == null
        ? _allItems.length
        : _allItems.where((i) => i.category == filter).length;
    return Wrap(spacing: Design.px(10), runSpacing: Design.px(10), children: [
      tab('全部', null, countOf(null)),
      tab('系统', _Category.system, countOf(_Category.system)),
      tab('我的图片', _Category.local, countOf(_Category.local)),
      // 动态壁纸暂无数据源，入口保留但计数为 0。
      tab('动态', _Category.dynamic, 0),
    ]);
  }

  Widget _emptyState(SurfaceStyle s) => Container(
      height: Design.px(240),
      alignment: Alignment.center,
      decoration: BoxDecoration(
          color: s.soft,
          borderRadius: BorderRadius.circular(s.controlRadius * .8)),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        UniIcon('camera', size: Design.px(38), color: s.muted),
        SizedBox(height: Design.px(14)),
        Text('动态壁纸待接入', style: TextStyle(fontSize: Design.px(20), color: s.text)),
        SizedBox(height: Design.px(8)),
        Text('原车没有动态壁纸数据源，这一分类暂时为空',
            style: TextStyle(fontSize: Design.px(16), color: s.muted)),
      ]));

  Widget _tile(_WallpaperItem item, SurfaceStyle s) {
    final a = widget.controller.appearance;
    final isCustom = item.id == 'custom';
    final hasCustom = a.wallpaperPath.isNotEmpty;
    final selected = a.wallpaper == item.id;
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
            key: ValueKey('library-wallpaper-${item.id}'),
            onTap: isCustom && !hasCustom
                ? _pickLocal
                : () => widget.controller.setAppearance(
                    a.copyWith(wallpaper: item.id, mode: 'smart')),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              AspectRatio(
                  aspectRatio: 16 / 9,
                  child: Stack(fit: StackFit.expand, children: [
                    if (!isCustom || hasCustom)
                      SceneBackground(
                          wallpaperCacheWidth: 360,
                          appearance: isCustom
                              ? a.copyWith(wallpaper: 'custom')
                              : a.copyWith(wallpaper: item.id),
                          child: const SizedBox.expand())
                    else
                      Center(
                          child: UniIcon('camera',
                              size: Design.px(31), color: s.muted)),
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
                      child: Text(item.name,
                          maxLines: 1,
                          style: TextStyle(fontSize: Design.px(16))))),
            ])));
  }

  Widget _footer(SurfaceStyle s) => Row(children: [
        OutlinedButton.icon(
            key: const ValueKey('wallpaper-import'),
            onPressed: _pickLocal,
            icon: UniIcon('plus', size: Design.px(20), color: s.text),
            label: Text('导入本地图片',
                style: TextStyle(fontSize: Design.px(19)))),
        SizedBox(width: Design.px(16)),
        Expanded(
            child: Text(
                '每屏 $_perPage 张 · 缩略图按需加载 · 长按删除本地图片待接入（无删除接口）',
                style: TextStyle(fontSize: Design.px(16), color: s.muted))),
      ]);
}
