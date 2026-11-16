// 本地主题预览入口（仅本机调试用；未跟踪，靠约定不提交）。
//
//   flutter run -d windows -t preview/main_preview.dart
//
// 为什么需要它：真机回路是「打包 APK → 装 → 重启桌面」，改一个色值要等好
// 几分钟；而主题改动 99% 是配色，Windows 桌面上热重载（保存即刷新）能把
// 这一圈压到 1 秒内。原生侧只负责供数据（bootstrap/events），预览用
// FakeGateway 顶上，Dart 侧渲染路径与车机完全一致。
//
// 画布固定 1600×900（= Design.dz 的 1:1 口径），用 FittedBox 等比缩放到窗口，
// 窗口拉多大都不改变布局——布局永远按车机尺寸算。
//
// 无头出图（脚本化比对用，不弹给别人看的窗口也一样能跑）：
//   UNI_PREVIEW_STYLE=nocturne UNI_PREVIEW_SHOT=D:/tmp/a.png \
//     build/windows/x64/runner/Debug/uni_launcher.exe
// 截图走 RepaintBoundary，输出恒为 1600×900，不受窗口边框/系统缩放影响。
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:uni_launcher/controller/launcher_controller.dart';
import 'package:uni_launcher/launcher_app.dart';
import 'package:uni_launcher/model/appearance.dart';
import 'package:uni_launcher/ota/update_controller.dart';
import 'package:uni_launcher/platform/cluster_lyrics.dart';
import 'package:uni_launcher/platform/ui_routes.dart';
import 'package:uni_launcher/platform/log_tools.dart';
import 'package:uni_launcher/widgets/music_app_picker.dart';
import 'package:uni_launcher/widgets/navigation_app_picker.dart';
import 'package:uni_launcher/widgets/bottom_dock.dart';
import 'package:uni_launcher/widgets/desktop_name_dialog.dart';
import 'package:uni_launcher/widgets/file_transfer_popup.dart';
import 'package:uni_launcher/screens/settings_screen.dart';
import 'package:uni_launcher/theme/launcher_theme.dart';
import 'package:uni_launcher/widgets/cluster_lyrics_settings.dart';
import 'package:uni_launcher/widgets/scene_background.dart';

import '../test/fake_gateway.dart';

/// 车机逻辑画布：1920×1080 @dpr1.2 = 1600×900。
const _canvas = Size(1600, 900);

/// 与各皮肤自己的 `defaultRadius` 对齐，切主题时才不会被上一套的圆角带偏。
const _radius = <String, double>{
  'classic': 30,
  'blueGlass': 30,
  'nocturne': 25,
  'summer': 26,
  'nebula': 26
};

/// 第二页那几张卡（车况与胎压 / 动力电池 / 车内空气 / 行车信息）只认 `vehicle`
/// 字段，而 `FakeGateway` 默认只给 `{'writable': false}`，四张卡会整片渲染成
/// 「—」。这里补一组合法读数，**数据只在预览进程里**，`test/fake_gateway.dart`
/// 一行不动（那是仓库文件，改了会影响测试）。
///
/// 每个字段都必须带 `valid` 和 5 秒内的时间戳：`VehicleField.fromNative` 会把
/// 过期读数判为失效，所以下面用 `Timer` 每 3 秒重推一次，长时间开着窗口也不会
/// 变成「等待更新」。
Map<String, dynamic> _demoVehicle() {
  final now = DateTime.now().millisecondsSinceEpoch;
  Map<String, dynamic> f(Object value, String unit,
          {bool unitVerified = true}) =>
      {
        'value': value,
        'unit': unit,
        'valid': true,
        'unitVerified': unitVerified,
        'source': 'preview',
        'updatedAtMs': now,
      };
  return {
    'connected': true,
    'writable': false,
    'fields': {
      // 车况与胎压：四轮读数（单位不参与校验，bar 即可）。
      'pressureFrontLeft': f(2.4, 'bar'),
      'pressureFrontRight': f(2.4, 'bar'),
      'pressureRearLeft': f(2.3, 'bar'),
      'pressureRearRight': f(2.3, 'bar'),
      // 动力电池。batteryPercent 只接受 %，且必须 unitVerified。
      'batteryPercent': f(78, '%'),
      'driveMode': {'value': 'COMFORT', 'valid': true, 'updatedAtMs': now},
      'energyFlow': {
        'value': 'ELECTRIC_DRIVE',
        'valid': true,
        'updatedAtMs': now
      },
      // 车内空气。pm25 的 µ 是 U+00B5，用 'μ'（希腊字母）会被判成单位待确认。
      'pm25': f(12, 'µg/m³'),
      'aqi': f(18, ''),
      // 行车信息：这四项是 driving 类，单位必须 unitVerified 才认。
      'speed': f(48, 'km/h'),
      'odometer': f(12864, 'km'),
      'range': f(486, 'km'),
      'maintenanceMileage': f(3520, 'km'),
    },
  };
}

/// 预览专用网关：`FakeGateway` 只回了几种开关，记忆配置 / 开机自启 / 无线 adb
/// 这些「点下去由原生落盘再回执」的开关在预览里就永远弹回原值，看着像按键坏了。
/// 这里按 `LauncherRuntime` 的处理方式在本地复现一遍，保证预览里点得动。
class _PreviewGateway extends FakeGateway {
  @override
  Future<void> action(String action,
      {String? value, String? zone, bool? enabled}) async {
    Map<String, dynamic> sub(String key) => Map<String, dynamic>.from(
        state[key] is Map ? state[key] as Map : const {});
    void put(String key, Map<String, dynamic> next) {
      state = {...state, key: next};
    }

    switch (action) {
      case 'memory-drive-mode-enabled':
        put('vehicleMemory',
            {...sub('vehicleMemory'), 'driveModeEnabled': enabled == true});
      case 'memory-start-stop-enabled':
        put('vehicleMemory',
            {...sub('vehicleMemory'), 'startStopEnabled': enabled == true});
      case 'memory-drive-mode-target':
        put('vehicleMemory', {...sub('vehicleMemory'), 'driveMode': value});
      case 'memory-start-stop-target':
        put('vehicleMemory',
            {...sub('vehicleMemory'), 'startStop': value == 'on'});
      case 'auto-play-music':
        put('integrationPreferences',
            {...sub('integrationPreferences'), 'autoPlayMusic': enabled == true});
      case 'wireless-adb-enabled':
        put('wirelessAdb', {...sub('wirelessAdb'), 'enabled': enabled == true});
      case 'boot-launch-enabled':
        put('bootLaunch', {...sub('bootLaunch'), 'enabled': enabled == true});
      // 「导航与媒体」那几个开关已经在 FakeGateway 里回写了（和测试共用同一份
      // 原生行为模拟），这里不用再写一遍。
      //
      // 传文件：真机上 `transfer-start` 由原生拉起 HTTP 服务再回写
      // `transfer.running/url`，预览没有那个服务，开关就永远点不亮、二维码
      // 也出不来。这里按同样的形状伪造一份，让这块设计在预览里能看全。
      case 'transfer-start':
        put('transfer', {
          ...sub('transfer'),
          'running': true,
          'url': 'http://192.168.31.56:8080/',
        });
      case 'transfer-stop':
        put('transfer', {...sub('transfer'), 'running': false, 'url': ''});
    }
    await super.action(action, value: value, zone: zone, enabled: enabled);
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final env = Platform.environment;
  final gateway = _PreviewGateway();
  // 必须在 initialize() 之前塞进去，bootstrap() 返回的是 state 的副本。
  gateway.state = {...gateway.state, 'vehicle': _demoVehicle()};
  // UNI_PREVIEW_MEDIA=<起始秒数>：假数据本来没有播放时间轴，进度恒为 0，
  // 底栏流体进度就永远贴在左边缘。默认给 45 秒起点，让进度条一直在走；
  // 想从特定位置看形态再覆盖这个值。
  final double? mediaSec = double.tryParse(env['UNI_PREVIEW_MEDIA'] ?? '') ?? 45;
  // 假媒体时长（3:23），回绕时按它取模。
  const mediaDurationMs = 203000;
  if (mediaSec != null) {
    gateway.state = {
      ...gateway.state,
      'media': {
        ...Map<String, dynamic>.from(gateway.state['media'] as Map),
        'playing': true,
        'positionKnown': true,
        'durationMs': mediaDurationMs,
        'positionMs': (mediaSec * 1000).round(),
        'sampledAtMs': DateTime.now().millisecondsSinceEpoch,
        'speed': 1.0,
      },
    };
  }
  // UNI_PREVIEW_LYRICS=1：铺满播放器的歌词窗调版式时要看真实断行，预览默认
  // 没有歌词文档（假网关只给曲目名）。这里塞 20 句、每句 3 秒，配合
  // UNI_PREVIEW_MEDIA 可以把高亮行停在任意一行。
  if (env['UNI_PREVIEW_LYRICS'] == '1') {
    const texts = [
      '沿着环线一直往北开',
      '路灯把影子拉得很长很长',
      '风从窗缝里钻进来',
      '副驾的人已经睡着了',
      '仪表盘的光停在八十码',
      '远处的山脊压着夜色',
      '你说这条路没走过',
      '我说那就当是绕远一点',
      '收音机切到老歌那台',
      '前奏一响我们都笑了',
      '城市退成一排小灯',
      '后视镜里慢慢熄了',
      '握紧一点方向盘',
      '下一个出口还没到',
      '那就再唱一遍副歌',
      '让这条路再长一点',
      '长到够说完这些年',
      '长到够把话都讲完',
      '天亮之前都不用停',
      '天亮之前都算今晚',
    ];
    gateway.state = {
      ...gateway.state,
      'media': {
        ...Map<String, dynamic>.from(gateway.state['media'] as Map),
        'lyrics': texts.join('\n'),
        'lyricTimeline': jsonEncode({
          'v': 1,
          'lines': [
            for (var i = 0; i < texts.length; i++)
              {'t': i * 3000, 'd': 3000, 'x': texts[i]}
          ]
        }),
      },
    };
  }
  // UNI_PREVIEW_NAV_DEMO=1：预览的 apps 默认是空的，选择器弹层只剩一行
  // 「自动选择」，看不出稿子的层次（四行地图 + 使用中角标 + 其他已安装应用）。
  if (env['UNI_PREVIEW_NAV_DEMO'] == '1') {
    const maps = <List<String>>[
      ['com.autonavi.amapauto', '高德地图'],
      ['com.baidu.naviauto', '百度地图'],
      ['com.tencent.mapauto', '腾讯地图'],
      ['com.huawei.petalmap', 'Petal 地图'],
    ];
    const others = <List<String>>[
      ['com.tencent.qqmusic', 'QQ 音乐'],
      ['com.netease.cloudmusic', '网易云音乐'],
      ['com.android.gallery3d', '图库'],
    ];
    Map<String, dynamic> entry(List<String> a, {bool music = false}) => {
          'id': '${a[0]}/.Main',
          'package': a[0],
          'label': a[1],
          'enabled': true,
          if (music) 'isMusic': true,
        };
    gateway.state = {
      ...gateway.state,
      'apps': [
        for (final m in maps) entry(m),
        for (final o in others)
          entry(o, music: o[0].contains('music'))
      ],
      'navigation': {
        'package': maps.first[0],
        'preferredPackage': maps.first[0],
        'label': maps.first[1],
        'canEmbed': false,
        'options': [
          for (final m in maps) {'package': m[0], 'label': m[1]}
        ],
      },
    };
  }
  // UNI_PREVIEW_CLEANER=1：桌面预览没有安卓清理服务，往假网关里塞一份快照，
  // 好让「垃圾清理」页的版式（汇总卡 / 类目列表 / 底部操作栏）看得见内容。
  // =scan / =clean 塞「进行中」的那两态，用来验进度条与百分比大字。
  final cleanerMode = env['UNI_PREVIEW_CLEANER'];
  if (cleanerMode != null && cleanerMode.isNotEmpty) {
    gateway.state = {
      ...gateway.state,
      'cleaner': _fakeCleaner(
          phase: cleanerMode == 'clean'
              ? 'clean'
              : cleanerMode == 'scan'
                  ? 'scan'
                  : 'idle')
    };
  }
  // UNI_PREVIEW_CLUSTER=1：桌面预览没有安卓的副屏投射服务，`clusterLyrics*`
  // 三条通道无人应答，「仪表投屏」页就只剩一句「没有暴露任何副屏」。塞一个
  // 假客户端进来，屏幕选择、可拖预览、字形配色都看得见内容，也才能量
  // 「一屏放没放下」。
  if (env['UNI_PREVIEW_CLUSTER'] == '1') {
    ClusterLyricsSettingsTab.previewClient = _PreviewCluster();
  }
  final controller = LauncherController(gateway);
  await controller.initialize();
  final startedAt = DateTime.now();
  // 3 秒一推，把车辆读数的 5 秒新鲜度窗口一直续上。
  Timer.periodic(const Duration(seconds: 3), (_) {
    var next = {...gateway.state, 'vehicle': _demoVehicle()};
    if (mediaSec != null) {
      // 假媒体循环播放：走到结尾回绕到 0，进度条不会顶在头上一动不动，
      // 回绕那一下还能顺带看到弹簧和双拖影的回弹。
      final posMs = (mediaSec * 1000 +
              DateTime.now().difference(startedAt).inMilliseconds) %
          mediaDurationMs;
      next = {
        ...next,
        'media': {
          ...Map<String, dynamic>.from(next['media'] as Map),
          'playing': true,
          'positionKnown': true,
          'durationMs': mediaDurationMs,
          'positionMs': posMs.round(),
          'sampledAtMs': DateTime.now().millisecondsSinceEpoch,
          'speed': 1.0,
        },
      };
    }
    gateway.state = next;
    gateway.stream.add(Map.of(next));
  });

  // 允许脚本指定初始皮肤，省得每次手动按 F2。
  final style = env['UNI_PREVIEW_STYLE'];
  if (style != null && Appearance.themeStyles.contains(style)) {
    controller.setAppearance(
        controller.appearance
            .copyWith(themeStyle: style, radius: _radius[style]),
        save: false);
  }
  // 强调色也可以指定。深色皮肤配默认的「青屿」会得到薄荷强调，某些皮肤
  // （星蓝）的画面主色是蓝，用「冰川」才看得出设计意图。默认仍是青屿。
  final accent = env['UNI_PREVIEW_PALETTE'];
  if (accent != null && accentPresets.any((p) => p.id == accent)) {
    controller.setAppearance(
        controller.appearance.copyWith(palette: accent), save: false);
  }
  // UNI_PREVIEW_MODE=light|dark 钉死明暗，不看系统。
  //
  // 浅色态的问题（同一个控件在浅底上发灰、高光变阴影）在暗色截图里根本
  // 看不出来，而 Windows 预览机的系统主题又不一定是什么——必须能手动指定。
  final previewMode = env['UNI_PREVIEW_MODE'];
  if (previewMode == 'light' || previewMode == 'dark') {
    controller.setAppearance(
        controller.appearance.copyWith(mode: previewMode), save: false);
  }
  // UNI_PREVIEW_SCREEN=settings 直接把设置页当根页面：设置页的配色问题
  // （选中态前景、深色弹层）在桌面主界面上根本看不到，得单独拍。
  final settings = env['UNI_PREVIEW_SCREEN'] == 'settings';
  if (settings) {
    // Windows 上没有安卓的日志服务：`log:status` 无人应答，「系统与调试」页
    // 的占用、份数与落盘策略四行全是「—」，看不出渲染对不对。塞一份与
    // `FileLogSink` 常量一致的快照（512KB / 8 份 / 4MB / 剩余 16MB 停写）。
    LogTools.statusOverride = {
      'level': 'INFO',
      'bytes': 3 * 1024 * 1024 + 480 * 1024,
      'degraded': false,
      'anchors': 12,
      'initialized': true,
      'storageWritable': true,
      'storageReadable': true,
      'files': 3,
      'maxFileBytes': 512 * 1024,
      'maxFiles': 8,
      'maxTotalBytes': 4 * 1024 * 1024,
      'minFreeBytes': 16 * 1024 * 1024,
    };
    controller.tab(env['UNI_PREVIEW_TAB'] ?? 'appearance');
  }
  // UNI_PREVIEW_PAGE=1 直接落到第二页：第二页的卡片类型（车况/电池/时钟天气/
  // 快捷应用/行车信息/空气）跟首页完全不同，配色问题只在那边才暴露。
  // 必须在 runApp 之前切，否则首帧还是第一页，截到的图会是错的。
  final page = int.tryParse(env['UNI_PREVIEW_PAGE'] ?? '') ?? 0;
  if (page > 0 && !settings) await controller.switchPage(page);
  // UNI_PREVIEW_PANEL=navigation|music-picker：弹层的触发按钮挂在全局面板里，
  // 桌面上没有入口，靠 tap-key 点不到，只能直接开面板。
  runApp(_PreviewHost(
      controller: controller,
      shot: env['UNI_PREVIEW_SHOT'],
      panel: env['UNI_PREVIEW_PANEL'],
      settings: settings));
}

class _PreviewHost extends StatefulWidget {
  final LauncherController controller;
  final String? shot;
  final String? panel;
  final bool settings;
  const _PreviewHost(
      {required this.controller,
      this.shot,
      this.panel,
      this.settings = false});

  @override
  State<_PreviewHost> createState() => _PreviewHostState();
}

class _PreviewHostState extends State<_PreviewHost> {
  final _canvasKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    final shot = widget.shot;
    if (shot == null) return;
    // 等入场动画与底栏音乐进度走稳再拍，否则同一份代码两次出图会差几个像素。
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final ms = int.tryParse(Platform.environment['UNI_PREVIEW_DELAY'] ?? '') ??
          1500;
      await Future<void>.delayed(Duration(milliseconds: ms));
      final panel = widget.panel;
      if (panel != null) {
        // 走 app 的根 Navigator 直接开弹层：全局面板要 native 侧的 globalDock
        // 状态，假网关里没有，presentGlobalPanel 会直接返回 false。
        final ctx = _rootNavigatorContext();
        if (ctx == null) {
          debugPrint('UNI-Preview panel: no navigator');
        } else if (panel == 'navigation') {
          unawaited(showNavigationPicker(ctx, widget.controller));
        } else if (panel == 'music') {
          unawaited(showMusicPicker(ctx, widget.controller));
        }
        await Future<void>.delayed(const Duration(milliseconds: 900));
      }
      // UNI_PREVIEW_TAP=x,y（画布坐标，可多组用分号隔开）：用引擎真实的指针
      // 事件在指定位置点一下，用来验证命中测试/手势链路，比翻代码猜可靠。
      for (final pair in (Platform.environment['UNI_PREVIEW_TAP'] ?? '')
          .split(';')
          .where((s) => s.contains(','))) {
        final parts = pair.split(',').map(double.tryParse).toList();
        if (parts.length < 2 || parts[0] == null || parts[1] == null) continue;
        await _tapAt(Offset(parts[0]!, parts[1]!));
        await Future<void>.delayed(const Duration(milliseconds: 700));
      }
      // UNI_PREVIEW_TAP_KEY=some-key;other-key：按 key 找控件、点它的正中心。
      // 坐标手算差 7px 就会落到按钮外面，按 key 点不会错。
      for (final name in (Platform.environment['UNI_PREVIEW_TAP_KEY'] ?? '')
          .split(';')
          .where((s) => s.trim().isNotEmpty)) {
        final hit = _centerOfKey(name.trim());
        if (hit == null) {
          debugPrint('UNI-Preview tap-key miss: $name');
          continue;
        }
        debugPrint('UNI-Preview tap-key $name @ $hit');
        await _tapAtGlobal(hit);
        await Future<void>.delayed(const Duration(milliseconds: 700));
      }
      await capture(_canvasKey, shot);
      exit(0);
    });
  }

  /// 应用根 Navigator 的 context，用来在不依赖 native 状态的前提下直接开弹层。
  BuildContext? _rootNavigatorContext() {
    BuildContext? found;
    void visit(Element e) {
      if (found != null) return;
      if (e is StatefulElement && e.state is NavigatorState) {
        found = e;
        return;
      }
      e.visitChildren(visit);
    }

    final root = WidgetsBinding.instance.rootElement;
    if (root != null) visit(root);
    return found;
  }

  Offset? _centerOfKey(String name) {    Element? found;
    void visit(Element e) {
      if (found != null) return;
      if (e.widget.key == ValueKey(name)) {
        found = e;
        return;
      }
      e.visitChildren(visit);
    }

    final root = WidgetsBinding.instance.rootElement;
    if (root != null) visit(root);
    final box = found?.renderObject;
    if (box is! RenderBox || !box.hasSize) return null;
    return box.localToGlobal(box.size.center(Offset.zero));
  }

  Future<void> _tapAt(Offset local) async {
    final box = _canvasKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return;
    await _tapAtGlobal(box.localToGlobal(local));
  }

  Future<void> _tapAtGlobal(Offset at) async {
    const pointer = 77;
    GestureBinding.instance.handlePointerEvent(PointerDownEvent(
        pointer: pointer, position: at, kind: PointerDeviceKind.touch));
    await Future<void>.delayed(const Duration(milliseconds: 60));
    GestureBinding.instance.handlePointerEvent(PointerUpEvent(
        pointer: pointer, position: at, kind: PointerDeviceKind.touch));
  }

  @override
  Widget build(BuildContext context) => ColoredBox(
        color: const Color(0xFF202020),
        child: FittedBox(
          fit: BoxFit.contain,
          child: SizedBox.fromSize(
            size: _canvas,
            child: MediaQuery(
              // 固定 dpr=1：预览是给人眼看的，不必按系统的 1.25/1.5 倍率渲染。
              data: const MediaQueryData(
                  size: _canvas, devicePixelRatio: 1, padding: EdgeInsets.zero),
              child: RepaintBoundary(
                key: _canvasKey,
                // 预览关掉语义树：底栏歌词/进度/风扇每帧都在动，Windows 的 UIA
                // 桥每帧都算一遍 AXTree 更新，节点跟不上就刷
                // `accessibility_bridge.cc Failed to update ui::AXTree`（几十万行/小时），
                // 把 flutter run 的控制台输出堵死，热重载命令就排在后面读不到。
                // 预览是给人看的，不需要读屏，整棵裁掉最省事。
                child: ExcludeSemantics(
                  child: _PreviewShortcuts(
                      controller: widget.controller,
                      onShot: () => capture(
                          _canvasKey,
                          '${Directory.current.path}/preview_'
                          '${widget.controller.appearance.themeStyle}.png'),
                      child: _content()),
                ),
              ),
            ),
          ),
        ),
      );

  Widget _content() {
    final c = widget.controller;
    if (!widget.settings) return LauncherApp(controller: c);
    // 「关于与更新」页没有 UpdateController 就只显示一句「更新服务暂不可用」，
    // 截不到稿子里的版式。给一份假的版本信息，让这一页能出图。
    final update = _previewUpdate();
    // 设置页要自己的 MaterialApp（LauncherApp 的 home 写死成桌面 shell），
    // 主题仍用同一套 SurfaceStyle，配色才和桌面对得上。
    return AnimatedBuilder(
        animation: c,
        builder: (context, _) => MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: launcherTheme(SurfaceStyle.from(
                c.appearance, c.native.value['dark'] == true,
                adaptToWallpaper: true)),
            // 设置页自己不带 Scaffold / 背景：车上它盖在桌面之上，背景是
            // SceneBackground 画的。预览必须补上这两层，否则文字落到没有
            // Material 祖先的环境里，会渲染成红线加黄下划线的调试样式。
            home: SceneBackground(
                appearance: c.appearance,
                child: Scaffold(
                    backgroundColor: Colors.transparent,
                    body: SettingsScreen(controller: c, update: update)))));
  }
}

/// 预览用的更新服务：只给版本信息，不联网检查（截图时网络请求会挂住）。
UpdateController _previewUpdate() => UpdateController()
  ..info = {'versionName': '0.7.6', 'versionCode': 2076, 'sdk': 28};

/// 出图倍率：车机 1920×1080 物理像素 ÷ 1600 逻辑画布宽 = 1.2。
/// 画布像素比固定为 1，乘这个倍率后 PNG 就是**真机原始像素尺寸
/// 1920×1080**，可与真机截图/设计稿逐像素比对。
const _shotRatio = 1920 / 1600;

/// 把 1600×900 画布按真机像素尺寸（1920×1080）写成 PNG。
Future<void> capture(GlobalKey key, String path) async {
  final boundary = key.currentContext?.findRenderObject();
  if (boundary is! RenderRepaintBoundary) return;
  final image = await boundary.toImage(pixelRatio: _shotRatio);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  final file = File(path);
  await file.parent.create(recursive: true);
  await file.writeAsBytes(bytes!.buffer.asUint8List());
  debugPrint('UNI-Preview shot=$path (${image.width}x${image.height})');
}

/// F2 = 循环切风格（按 `Appearance.themeStyles` 顺序：classic → blueGlass →
/// nocturne → summer），F3 = 存一张 PNG。
///
/// 车上比对两套配色要「设置 → 外观 → 风格」来回点，预览里一个键就够了；
/// 想连设置页一起看，点桌面右上角的入口（走 LauncherShell 自己的路由，这里
/// 不能包 Navigator，否则会和 MaterialApp 抢）。
class _PreviewShortcuts extends StatefulWidget {
  final LauncherController controller;
  final VoidCallback onShot;
  final Widget child;
  const _PreviewShortcuts(
      {required this.controller, required this.onShot, required this.child});

  @override
  State<_PreviewShortcuts> createState() => _PreviewShortcutsState();
}

class _PreviewShortcutsState extends State<_PreviewShortcuts> {
  @override
  Widget build(BuildContext context) => Focus(
        autofocus: true,
        onKeyEvent: (node, event) {
          if (event is! KeyDownEvent) return KeyEventResult.ignored;
          final c = widget.controller;
          if (event.logicalKey == LogicalKeyboardKey.f2) {
            final styles = Appearance.themeStyles;
            final next =
                styles[(styles.indexOf(c.appearance.themeStyle) + 1) % styles.length];
            c.setAppearance(
                c.appearance.copyWith(themeStyle: next, radius: _radius[next]),
                save: false);
            return KeyEventResult.handled;
          }
          if (event.logicalKey == LogicalKeyboardKey.f3) {
            widget.onShot();
            return KeyEventResult.handled;
          }
          // F5~F8：直接打开四个浮层，省掉「长按/点菜单」的定位成本。
          // 顺序对应设计稿：F5 f20 桌面命名、F6 f30 传文件、
          // F7 f7 空调与座椅、F8 f29 车辆信息。
          //
          // 这里在 MaterialApp **之上**（见 F2 注释），自身 context 没有
          // Navigator，必须借 LauncherApp 的那个 key。
          final routeContext = launcherNavigatorKey.currentContext;
          if (event.logicalKey == LogicalKeyboardKey.f5 &&
              routeContext != null) {
            showDesktopNameDialog(routeContext, c);
            return KeyEventResult.handled;
          }
          if (event.logicalKey == LogicalKeyboardKey.f6 &&
              routeContext != null) {
            showFileTransferPopup(routeContext, c);
            return KeyEventResult.handled;
          }
          if (event.logicalKey == LogicalKeyboardKey.f7 &&
              routeContext != null) {
            showClimatePanel(routeContext, c);
            return KeyEventResult.handled;
          }
          if (event.logicalKey == LogicalKeyboardKey.f8 &&
              routeContext != null) {
            showVehiclePanel(routeContext, c);
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: widget.child,
      );
}

/// 假快照：类目、体积、分组都照 sim f34 的样子配。
Map<String, dynamic> _fakeCleaner({String phase = 'idle'}) => {      'running': phase != 'idle',
      'phase': phase,
      'progress': phase == 'scan'
          ? 0.62
          : phase == 'clean'
              ? 0.31
              : 1.0,
      'current': phase == 'clean' ? '缩略图缓存' : '',
      'purgeFiles': phase == 'clean' ? 4268 : 0,
      'purgeTotal': phase == 'clean' ? 13762 : 0,
      'free': 32400000000,
      'total': 137400000000,
      'scanned': 12860,
      'scanMs': 12400,
      'storageGranted': true,
      'lastClean': {'at': 1730851200000, 'bytes': 1760000000},
      'categories': [
        {
          'id': 'self-cache',
          'name': '桌面缓存',
          'group': 'cache',
          'bytes': 90000000,
          'note': '图标与图片缓存，会自动重建',
          'default': true,
          'verified': true
        },
        {
          'id': 'app-cache',
          'name': '应用缓存',
          'group': 'cache',
          'bytes': 536000000,
          'risk': 'low',
          'note': '14 个应用 · 系统缓存统计',
          'default': true,
          'verified': true
        },
        {
          'id': 'system-cache',
          'name': '系统应用缓存',
          'group': 'cache',
          'bytes': 0,
          'risk': 'review',
          'available': false,
          'note': '系统未开放存储统计（PACKAGE_USAGE_STATS）'
        },
        {
          'id': 'external-cache',
          'name': '应用外部缓存',
          'group': 'cache',
          'bytes': 903000000,
          'note': '应用存在公共存储里的缓存，会自动重建',
          'default': true,
          'verified': true
        },
        {
          'id': 'thumbnails',
          'name': '缩略图缓存',
          'group': 'cache',
          'bytes': 224000000,
          'note': '相册缩略图，系统会重新生成',
          'default': true,
          'verified': true
        },
        {
          'id': 'ad-cache',
          'name': '广告与分析缓存',
          'group': 'junk',
          'bytes': 509000000,
          'risk': 'low',
          'note': '穿山甲 / 优量汇 / 广点通 / 快手联盟 留下的目录',
          'verified': true
        },
        {
          'id': 'log',
          'name': '日志与临时文件',
          'group': 'junk',
          'bytes': 134000000,
          'risk': 'low',
          'note': '只清 3 天前的日志，滚动日志一并算进来',
          'default': true,
          'verified': true
        },
        {
          'id': 'empty-dir',
          'name': '空文件夹',
          'group': 'junk',
          'bytes': 6000000,
          'risk': 'low',
          'note': '只删完全空的目录',
          'verified': true
        },
        {
          'id': 'orphan-data',
          'name': '卸载残留',
          'group': 'leftover',
          'bytes': 390000000,
          'risk': 'review',
          'note': '应用已卸载但数据目录还在',
          'verified': true
        },
        {
          'id': 'apk-leftover',
          'name': '安装包',
          'group': 'leftover',
          'bytes': 264000000,
          'note': 'Download 里的旧 apk',
          'verified': true
        },
        {
          'id': 'large-unused',
          'name': '长期未动的大文件',
          'group': 'large',
          'bytes': 1150000000,
          'risk': 'low',
          'note': '90 天没打开过的离线包',
          'verified': true
        }
      ]
    };

/// Windows 上没有安卓的副屏投射服务：三块屏照一台真车的配置给，
/// 并且已经开启投射到「仪表」——这样「仪表投屏」页的每个控件都有内容可看。
class _PreviewCluster extends ClusterLyrics {
  _PreviewCluster();

  static const _displays = [
    ClusterDisplay(
        id: 0,
        name: '中控屏',
        label: 'Display 0',
        width: 1920,
        height: 1080,
        densityDpi: 240),
    ClusterDisplay(
        id: 2,
        name: '仪表',
        label: '副屏 · Display 2',
        presentation: true,
        width: 1920,
        height: 720,
        densityDpi: 240),
    ClusterDisplay(
        id: 3,
        name: '副驾屏',
        label: 'Display 3',
        presentation: true,
        width: 1920,
        height: 1200,
        densityDpi: 240),
  ];

  ClusterCastStatus _status = const ClusterCastStatus(
    enabled: true,
    displayId: 2,
    displayName: '仪表',
    fontSp: 34,
    xRatio: 0.5,
    yRatio: 0.62,
    widthRatio: 0.94,
    rows: 3,
    accent: 0xFF7FE3D4,
    style: 'pill',
    report: '已连接 · 窗口已添加到仪表',
    lyricLines: 3,
  );

  @override
  Future<List<ClusterDisplay>> displays() async => _displays;

  @override
  Future<ClusterCastStatus> status() async => _status;

  @override
  Future<ClusterCastStatus> apply({
    ClusterDisplay? display,
    double fontSp = 34,
    bool solidBackground = true,
    double xRatio = 0.5,
    double yRatio = 0.62,
    double widthRatio = 0.94,
    int rows = 3,
    int accent = 0xFF7FE3D4,
    String style = 'pill',
    String motion = 'none',
  }) async {
    _status = _status.copyWith(
      enabled: display != null || _status.enabled,
      displayId: display?.id ?? _status.displayId,
      displayName: display?.name ?? _status.displayName,
      fontSp: fontSp,
      solidBackground: solidBackground,
      xRatio: xRatio,
      yRatio: yRatio,
      widthRatio: widthRatio,
      rows: rows,
      accent: accent,
      style: style,
      motion: motion,
    );
    return _status;
  }
}
