import 'package:flutter/material.dart';
import '../controller/launcher_controller.dart';
import '../theme/design_tokens.dart';
import '../theme/launcher_theme.dart';
import 'glass_surface.dart';
import 'choice_button.dart';
import 'launcher_dialog.dart';
import 'setting_block.dart';
import 'navigation_options.dart';
import 'steering_key_sheet.dart';
import 'word_lyric_sheet.dart';

/// sim f11 · 导航与媒体。
///
/// 版式：左右两块 `.blk` 并排（导航与播放器 | 关联的音乐播放器），下面一块
/// 通栏的「媒体与导航联动」。三块里全是 `.set-row`（58 高、5.5% 白细线、
/// 右侧 46×26 开关），没有按钮式选项——这一页没有任何 `.opt`。
class IntegrationSettings extends StatelessWidget {
  final LauncherController controller;
  final Map<String, dynamic> native;
  const IntegrationSettings(
      {super.key, required this.controller, required this.native});
  Map<String, dynamic> map(Object? value) =>
      value is Map ? Map<String, dynamic>.from(value) : {};

  @override
  Widget build(BuildContext context) {
    final s = SurfaceStyle.of(context),
        nav = map(native['navigation']),
        media = map(native['media']),
        prefs = map(native['integrationPreferences']);
    // 逐字可用性由音源决定：原生解出带 w 的 LRC 才会置位，这里只读不写。
    final wordTimed = media['lyricTimelineWords'] == true;
    final apps = <String, String>{};
    for (final raw
        in native['apps'] is List ? native['apps'] as List : const []) {
      final app = map(raw),
          pkg =
              '${app['package'] ?? app['id']?.toString().split('/').first ?? ''}';
      if (pkg.isNotEmpty &&
          app['enabled'] != false &&
          app['launchable'] != false) {
        apps.putIfAbsent(pkg, () => controller.appName(app));
      }
    }
    return SingleChildScrollView(
        key: const PageStorageKey('connection-settings-scroll'),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          // 两块并排，等高。
          IntrinsicHeight(
              child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                Expanded(
                    child: SettingBlock(
                        title: '导航与播放器',
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              const DesignFieldLabel('导航应用'),
                              SizedBox(height: Design.dz(6)),
                              _picker(context, s,
                                  key: 'navigation-source',
                                  action: 'select-navigation',
                                  selected:
                                      '${nav['preferredPackage'] ?? 'auto'}',
                                  choices:
                                      navigationOptions(controller, native)),
                              SizedBox(height: Design.dz(6)),
                              Align(
                                  alignment: Alignment.centerRight,
                                  child: DesignTextAction('打开导航应用',
                                      onPressed: () => controller
                                          .command('launch-navigation'))),
                              SizedBox(height: Design.dz(4)),
                              SettingRow(
                                  label: '在地图卡片中显示导航',
                                  note:
                                      '${nav['reason'] ?? '需要 Android 9 与车机嵌入权限'}',
                                  trailing: DesignSwitch(
                                      key: const ValueKey('embed-navigation'),
                                      value: nav['enabled'] != false,
                                      onChanged: (v) => controller.command(
                                          'embed-navigation',
                                          enabled: v))),
                              SettingRow(
                                  label: '嵌入地图缩放（优化帧率 但会模糊）',
                                  note: '地图卡片降分辨率渲染，翻页更跟手，导航画面略软',
                                  trailing: DesignSwitch(
                                      key: const ValueKey('map-texture-scale'),
                                      value: prefs['mapTextureScale'] == true,
                                      onChanged: (v) => controller.command(
                                          'map-texture-scale',
                                          enabled: v))),
                              SettingRow(
                                  label: '隐藏导航卡片标题栏',
                                  note: '关闭后显示导航应用、切换和全屏按钮',
                                  divider: false,
                                  trailing: DesignSwitch(
                                      key: const ValueKey(
                                          'navigation-card-title-hidden'),
                                      value:
                                          prefs['navigationCardTitleHidden'] !=
                                              false,
                                      onChanged: (v) => controller.command(
                                          'navigation-card-title-hidden',
                                          enabled: v)))
                            ]))),
                SizedBox(width: Design.dz(11.67)),
                Expanded(
                    child: SettingBlock(
                        title: '关联的音乐播放器',
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              const DesignFieldLabel('关联的音乐播放器'),
                              SizedBox(height: Design.dz(6)),
                              _picker(context, s,
                                  key: 'media-source',
                                  action: 'select-player',
                                  selected:
                                      '${prefs['mediaPackage'] ?? 'auto'}',
                                  choices: apps),
                              SizedBox(height: Design.dz(6)),
                              Align(
                                  alignment: Alignment.centerRight,
                                  child: DesignTextAction('打开关联播放器',
                                      onPressed: () =>
                                          controller.command('launch-player'))),
                              SizedBox(height: Design.dz(4)),
                              SettingRow(
                                  label: '开机自动播放音乐',
                                  note:
                                      '选择网易云、QQ 音乐或原车音乐后，歌曲、封面、歌词和播放控制均跟随该应用。请先在播放器中播放一首歌曲并授权媒体访问。',
                                  noteLines: 3,
                                  divider: false,
                                  trailing: DesignSwitch(
                                      key: const ValueKey(
                                          'integration-auto-play'),
                                      value: prefs['autoPlayMusic'] == true,
                                      onChanged: (v) => controller.command(
                                          'auto-play-music',
                                          enabled: v))),
                            ])))
              ])),
          SizedBox(height: Design.dz(11.67)),
          // sim f11 第二块：媒体与导航联动。
          SettingBlock(
              title: '媒体与导航联动',
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SettingRow(
                        key: const ValueKey('nav-ducking'),
                        label: '导航播报时压低音乐',
                        note: '原车混音接口为空实现（setNaviVoiceMixMode 无效果），'
                            '暂不支持压低或暂停，等原车补语义再接',
                        noteLines: 2,
                        // 这一项不是「用户没点动」，是原车给不了：开关保持
                        // 置灰，点整行给一句原因，别让人以为是坏了。
                        onTap: () => showLauncherToast(
                            context, '原车混音接口是空实现，暂时压不低音乐；等原车补上混音语义就能开'),
                        trailing: const DesignSwitch(
                            key: ValueKey('nav-ducking-switch'), value: false),
                        divider: false),
                    SettingRow(
                        key: const ValueKey('word-lyric-fill'),
                        label: '词级歌词 · 逐字填充',
                        note: wordTimed
                            ? '当前音源带逐字时间轴 · 底栏、音乐卡与仪表投屏共用'
                            : '当前音源只有整句时间戳，逐字填充退回按句高亮',
                        onTap: () => showLauncherToast(
                            context,
                            wordTimed
                                ? '当前音源带逐字时间轴，这一项跟随音源自动点亮'
                                : '当前音源只有整句时间戳；换用带逐字时间轴的音源后自动可用'),
                        trailing:
                            Row(mainAxisSize: MainAxisSize.min, children: [
                          DesignTextAction('时间轴',
                              onPressed: () =>
                                  showWordLyricSheet(context, controller)),
                          SizedBox(width: Design.dz(10)),
                          DesignSwitch(
                              key: const ValueKey('word-lyric-switch'),
                              value: wordTimed)
                        ])),
                    SettingRow(
                        key: const ValueKey('steering-keys'),
                        label: '方向盘按键接管',
                        note: '切歌、音量与语音键交由本桌面处理；关掉后这些键交回原车',
                        trailing:
                            Row(mainAxisSize: MainAxisSize.min, children: [
                          DesignTextAction('接管明细',
                              onPressed: () =>
                                  showSteeringKeySheet(context, controller)),
                          SizedBox(width: Design.dz(10)),
                          DesignSwitch(
                              key: const ValueKey('steering-keys-switch'),
                              value: prefs['steeringKeysEnabled'] != false,
                              onChanged: (v) => controller
                                  .command('steering-keys', enabled: v))
                        ])),
                    SettingRow(
                        key: const ValueKey('instrument-sync'),
                        label: '仪表显示桌面音乐',
                        note: '把当前曲目、封面与进度同步到仪表；关掉后仪表跟回原车播放器',
                        trailing: DesignSwitch(
                            key: const ValueKey('instrument-sync-switch'),
                            value: prefs['instrumentSyncEnabled'] != false,
                            onChanged: (v) => controller
                                .command('instrument-sync', enabled: v))),
                    // 仪表自带的媒体控件是第三条链路：和原车媒体中心并行，所以单独一个开关。
                    SettingRow(
                        key: const ValueKey('dim-cluster'),
                        label: '仪表自带媒体控件',
                        note: '把播放状态同步到仪表原生媒体控件，仪表上按播放/上一首也会收回桌面；'
                            '仪表界面没反应或出现两套控件时保持关闭',
                        divider: false,
                        trailing: DesignSwitch(
                            key: const ValueKey('dim-cluster-switch'),
                            value: prefs['dimClusterEnabled'] == true,
                            onChanged: (v) =>
                                controller.command('dim-cluster', enabled: v)))
                  ])),
          // 这里原来有一行「当前为演示模式；关闭演示数据后…」的强调色提示。
          // 演示模式只在模拟器上默认开启，真机用户永远看不到；就算看到了也
          // 帮不上忙（没有开关可点），还把这一页的底边顶出去一截。删掉。
        ]));
  }

  /// sim `.dd`：46.67 高、12 圆角、白 12% 描边的下拉。
  Widget _picker(BuildContext context, SurfaceStyle s,
      {required String key,
      required String action,
      required String selected,
      required Map<String, String> choices}) {
    final entries = {'auto': '自动选择', ...choices};
    if (!entries.containsKey(selected)) entries[selected] = '所选应用不可用';
    final border = OutlineInputBorder(
        borderRadius: BorderRadius.circular(s.controlRadius),
        borderSide: BorderSide(color: s.text.withValues(alpha: .12)));
    return SizedBox(
        // 外面这层用稳定的 key：测试和其它页面定位这颗下拉都按它找。
        key: ValueKey(key),
        height: Design.dz(46.67),
        child: DropdownButtonFormField<String>(
            // 里面的 key 必须带上当前值：FormField 的 initialValue 只在 initState
            // 里读一次，之后原生回写的新值不会同步到这颗下拉——用户选完导航应用，
            // 框里还显示「自动选择」，看起来就是「选了没反应、选中态写死」。
            // 让 key 随值变化，等于换一颗新的 FormField，显示才跟得上状态。
            key: ValueKey('$key:$selected'),
            initialValue: selected,
            isExpanded: true,
            isDense: true,
            icon: Icon(Icons.keyboard_arrow_down,
                size: Design.dz(18), color: s.muted),
            style: TextStyle(fontSize: Design.dz(15.5), color: s.text),
            decoration: InputDecoration(
                isDense: true,
                filled: true,
                fillColor: s.text.withValues(alpha: .02),
                contentPadding: EdgeInsets.symmetric(
                    horizontal: Design.dz(14), vertical: Design.dz(12)),
                border: border,
                enabledBorder: border,
                focusedBorder: border.copyWith(
                    borderSide:
                        BorderSide(color: s.accent.withValues(alpha: .5)))),
            items: entries.entries
                .map((e) => DropdownMenuItem(
                    value: e.key,
                    child: Text(e.value,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: Design.dz(15.5), color: s.text))))
                .toList(),
            onChanged: (v) {
              if (v != null) controller.command(action, value: v);
            }));
  }
}

/// Dock ownership and the replacement relationship with SystemUI.
///
/// sim f10：一块 `.blk`，两条 58 高的 `.set-row`（各自一枚 46×26 开关），
/// 末尾并排两个 30 高的小胶囊按钮。
class DockRuntimeSettings extends StatelessWidget {
  final LauncherController controller;
  const DockRuntimeSettings({super.key, required this.controller});
  @override
  Widget build(BuildContext context) =>
      ValueListenableBuilder<Map<String, dynamic>>(
          valueListenable: controller.native,
          builder: (context, n, _) {
            final c = controller;
            Map<String, dynamic> mapOf(Object? value) =>
                value is Map ? Map<String, dynamic>.from(value) : {};
            return SettingBlock(
                title: '全局底栏与系统导航',
                dense: true,
                note: '${mapOf(n['vehicle'])['reason'] ?? '未连接原车服务'}',
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SettingRow(
                          label: '全局底栏',
                          note: mapOf(n['globalDock'])['allowed'] == true
                              ? '在其他应用中使用相同的首页、空调和音乐控制'
                              : '开启后需允许悬浮显示',
                          trailing: DesignSwitch(
                              key: const ValueKey('global-dock'),
                              value: mapOf(n['globalDock'])['enabled'] == true,
                              onChanged: (v) =>
                                  c.command('global-dock', enabled: v))),
                      SettingRow(
                          label: '隐藏系统原有导航栏',
                          note: n['systemNavigationGranted'] == true
                              ? '关闭后恢复原有显示；与全局底栏分别设置'
                              : '需要系统授予导航栏管理权限',
                          divider: false,
                          trailing: DesignSwitch(
                              key: const ValueKey('system-navigation-hidden'),
                              value: n['systemNavigationHidden'] == true,
                              onChanged: n['systemNavigationGranted'] == true
                                  ? (v) => c.command('system-navigation-hidden',
                                      enabled: v)
                                  : null)),
                      SizedBox(height: Design.dz(12)),
                      Row(children: [
                        DesignSmallAction('刷新连接',
                            icon: Icons.refresh,
                            onPressed: () => c.command('refresh')),
                        SizedBox(width: Design.dz(11.67)),
                        DesignSmallAction('授权媒体访问',
                            onPressed: () => c.command('media-access'))
                      ])
                    ]));
          });
}

/// Operational preferences formerly grouped under the removed 功能接入 tab.
class RuntimeSettings extends StatelessWidget {
  final LauncherController controller;
  const RuntimeSettings({super.key, required this.controller});
  @override
  Widget build(BuildContext context) =>
      ValueListenableBuilder<Map<String, dynamic>>(
          valueListenable: controller.native,
          builder: (context, n, _) {
            final c = controller, s = SurfaceStyle.of(context);
            Map<String, dynamic> mapOf(Object? v) =>
                v is Map ? Map<String, dynamic>.from(v) : {};
            return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  IntegrationSettings(controller: c, native: n),
                  SizedBox(height: Design.px(16)),
                  GlassSurface(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                        Row(children: [
                          Expanded(
                              child: Text(
                                  '${mapOf(n['vehicle'])['reason'] ?? '未连接原车服务'}',
                                  style: TextStyle(
                                      fontSize: Design.px(20),
                                      color: s.muted))),
                          // 设计稿这里的次要操作是 accent 纯文字（`.tbtn`），
                          // 不再是灰底灰字的 TextButton 胶囊——那样对比度太低，
                          // 暗夜底下基本看不清。
                          DesignTextAction('刷新连接',
                              chevron: false,
                              onPressed: () => c.command('refresh')),
                          SizedBox(width: Design.dz(4)),
                          DesignTextAction('授权媒体访问',
                              chevron: false,
                              onPressed: () => c.command('media-access'))
                        ]),
                        DesignSwitchTile(
                            key: const ValueKey('global-dock'),
                            title: const Text('全局底栏'),
                            subtitle: Text(
                                mapOf(n['globalDock'])['allowed'] == true
                                    ? '在其他应用中使用相同的首页、空调和音乐控制'
                                    : '开启后需允许悬浮显示'),
                            value: mapOf(n['globalDock'])['enabled'] == true,
                            onChanged: (v) =>
                                c.command('global-dock', enabled: v)),
                        DesignSwitchTile(
                            key: const ValueKey('system-navigation-hidden'),
                            title: const Text('隐藏系统原有导航栏'),
                            subtitle: Text(n['systemNavigationGranted'] == true
                                ? '关闭后恢复原有显示；与全局底栏分别设置'
                                : '需要系统授予导航栏管理权限'),
                            value: n['systemNavigationHidden'] == true,
                            onChanged: n['systemNavigationGranted'] == true
                                ? (v) => c.command('system-navigation-hidden',
                                    enabled: v)
                                : null),
                      ]))
                ]);
          });
}
