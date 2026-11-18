import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uni_launcher/controller/launcher_controller.dart';
import 'package:uni_launcher/launcher_app.dart';
import 'package:uni_launcher/model/seat_control.dart';
import 'package:uni_launcher/platform/native_gateway.dart';
import 'package:uni_launcher/screens/settings_screen.dart';
import 'package:uni_launcher/theme/launcher_theme.dart';
import 'package:uni_launcher/widgets/bottom_dock.dart';
import 'package:uni_launcher/widgets/choice_button.dart';
import 'package:uni_launcher/widgets/desktop.dart';
import 'package:uni_launcher/widgets/launcher_dialog.dart';
import 'package:uni_launcher/widgets/seat_controls.dart';
import 'package:uni_launcher/widgets/scene_background.dart';
import 'package:uni_launcher/widgets/setting_block.dart';
import 'fake_gateway.dart';

void main() {
  Future<(LauncherController, FakeGateway)> launch(WidgetTester t) async {
    t.view.physicalSize = const Size(1920, 1080);
    t.view.devicePixelRatio = 1;
    final g = FakeGateway(), c = LauncherController(g);
    await c.initialize();
    await t.pumpWidget(LauncherApp(controller: c));
    await t.pumpAndSettle();
    addTearDown(() async {
      await t.pumpWidget(const SizedBox.shrink());
      c.dispose();
      await g.dispose();
      t.view.resetPhysicalSize();
      t.view.resetDevicePixelRatio();
    });
    return (c, g);
  }

  testWidgets('返回桌面按钮使用主题形状并随圆角变化', (t) async {
    final (c, _) = await launch(t);
    c.openSettings();
    for (final skin in ['classic', 'blueGlass', 'nocturne']) {
      for (final radius in [0.0, 40.0]) {
        c.setAppearance(c.appearance.copyWith(themeStyle: skin, radius: radius),
            save: false);
        await t.pumpAndSettle();
        final button = t.widget<OutlinedButton>(
            find.byKey(const ValueKey('back-to-desktop')));
        final shape = button.style!.shape!.resolve({})!;
        final style = SurfaceStyle.from(
            c.appearance, c.native.value['dark'] == true,
            adaptToWallpaper: true);
        expect(shape, isA<RoundedRectangleBorder>());
        expect(
            (shape as RoundedRectangleBorder)
                .borderRadius
                .resolve(TextDirection.ltr)
                .topLeft
                .x,
            style.controlRadius);
      }
    }
    await t.tap(find.byKey(const ValueKey('back-to-desktop')));
    await t.pumpAndSettle();
    expect(c.settings, isFalse);
  });

  testWidgets(
      'reviewed palette uses rectangular corners, modes and palette have separate heights',
      (t) async {
    final (c, _) = await launch(t);
    c.setAppearance(c.appearance.copyWith(themeStyle: 'classic', radius: 28),
        save: false);
    c.openSettings();
    await t.pumpAndSettle();
    final palette = find.byKey(const ValueKey('palette-mint'));
    final material = t.widget<Material>(
        find.descendant(of: palette, matching: find.byType(Material)).first);
    expect(material.shape, isA<RoundedRectangleBorder>());
    final shape = material.shape! as RoundedRectangleBorder;
    expect(shape.borderRadius.resolve(TextDirection.ltr).topLeft.x,
        closeTo(14.9333, .02));
    // 锚点取暗夜（sim f9 的 .pcol 86 / .opt 47 是另一套皮肤下的值，暗夜为塞进
    // 一屏各收 10 / 5）。三套皮肤现在共用这一组数——同一页换主题不该换版式。
    // 1920 屏上画布整体放大 1.2，所以量到的像素是画布值 × 1.2。
    expect(t.getRect(palette).height, closeTo(76 * 1.2, .1));
    expect(t.getRect(find.byKey(const ValueKey('mode-system'))).height,
        closeTo(44 * 1.2, .1));
    expect(find.byType(DesktopPreview), findsOneWidget);
    final category = t.getRect(find.byKey(const ValueKey('tab-appearance')));
    // 左导航行高按 sim .ss-nav .tb：46.67 画布 = 56 px（x1.2）。
    expect(category.height, closeTo(46.67 * 1.2, .1));
    expect(category.width, greaterThan(200));
    await t.ensureVisible(find.byKey(const ValueKey('radius-number-28')));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('radius-number-28')).hitTestable(),
        findsOneWidget);
    expect(t.takeException(), null);
  });
  testWidgets(
      'zero radius reaches palette and input controls while color chips stay circular',
      (t) async {
    final (c, _) = await launch(t);
    c.setAppearance(c.appearance.copyWith(themeStyle: 'classic'), save: false);
    c.openSettings();
    c.setAppearance(c.appearance.copyWith(radius: 0));
    await t.pumpAndSettle();
    for (final name in ['palette-mint', 'mode-system']) {
      final m = t.widget<Material>(find
          .descendant(
              of: find.byKey(ValueKey(name)), matching: find.byType(Material))
          .first);
      expect(
          (m.shape! as RoundedRectangleBorder)
              .borderRadius
              .resolve(TextDirection.ltr),
          BorderRadius.zero);
    }
    await t.ensureVisible(find.byKey(const ValueKey('custom-color')));
    await t.tap(find.byKey(const ValueKey('custom-color')));
    await t.pumpAndSettle();
    final field =
        t.widget<TextField>(find.byKey(const ValueKey('color-picker-hex')));
    final border = field.decoration?.border ??
        Theme.of(t.element(find.byType(DesktopPreview)))
            .inputDecorationTheme
            .border;
    expect((border! as OutlineInputBorder).borderRadius, BorderRadius.zero);
    expect(t.takeException(), null);
  });
  testWidgets('smart wallpaper styling stays consistent in settings',
      (t) async {
    final (c, _) = await launch(t);
    c.setAppearance(
        c.appearance.copyWith(mode: 'smart', wallpaper: 'precision'));
    c.openSettings();
    await t.pumpAndSettle();
    expect(
        SurfaceStyle.of(t.element(find.byKey(const ValueKey('tab-system'))))
            .dark,
        isFalse);
    expect(t.takeException(), isNull);
  });

  testWidgets('navigation page switches follow the command round trip',
      (t) async {
    final (c, _) = await launch(t);
    c.openSettings();
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('tab-connections')));
    await t.pumpAndSettle();
    bool valueOf(String key) =>
        t.widget<DesignSwitch>(find.byKey(ValueKey(key))).value;
    // 初始全关：点一下必须变成开，而不是下一帧被快照弹回去。
    expect(valueOf('map-texture-scale'), isFalse);
    await t.tap(find.byKey(const ValueKey('map-texture-scale')));
    await t.pumpAndSettle();
    expect(valueOf('map-texture-scale'), isTrue);
    await t.tap(find.byKey(const ValueKey('embed-navigation')));
    await t.pumpAndSettle();
    expect(valueOf('embed-navigation'), isFalse);
  });

  testWidgets('left nav highlight follows the selected tab', (t) async {
    final (c, _) = await launch(t);
    c.openSettings();
    await t.pumpAndSettle();
    bool selected(String id) =>
        t.widget<ChoiceButton>(find.byKey(ValueKey('tab-$id'))).selected;
    expect(selected('appearance'), isTrue);
    await t.tap(find.byKey(const ValueKey('tab-memory')));
    await t.pumpAndSettle();
    // 左导航在 SettingsScreen 里是 `const SizedBox(child: _SettingsNav())`：
    // 那块 SizedBox 是编译期常量，父级重建会命中「同一个 widget」的短路，
    // 整棵子树不进 build，高亮就一直钉在第一项上。导航自己订阅 controller
    // 之后才跟得上。
    expect(selected('memory'), isTrue);
    expect(selected('appearance'), isFalse);
    await t.tap(find.byKey(const ValueKey('tab-system')));
    await t.pumpAndSettle();
    expect(selected('system'), isTrue);
    expect(selected('memory'), isFalse);
  });

  testWidgets('inline text actions use the accent color', (t) async {
    final (c, _) = await launch(t);
    c.openSettings();
    await t.pumpAndSettle();
    final element = t.element(find.byKey(const ValueKey('tab-system')));
    // 设计稿 `.tbtn` 是 accent 纯文字；挂在 muted（白 40%）上时，
    // 暗夜底下的「立即开启无线 adb」几乎看不见。
    expect(
        Theme.of(element).textButtonTheme.style!.foregroundColor!.resolve({}),
        SurfaceStyle.of(element).accent);
  });

  testWidgets('switches the car cannot drive explain themselves on tap',
      (t) async {
    final (c, _) = await launch(t);
    c.openSettings();
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('tab-connections')));
    await t.pumpAndSettle();
    // 导航播报压音乐：原车混音接口是空实现，开关必须置灰，但点它得给原因，
    // 不然看起来就是「坏了、点不动」。
    await t.tap(find.byKey(const ValueKey('nav-ducking')));
    await t.pumpAndSettle();
    expect(find.textContaining('原车混音接口是空实现'), findsOneWidget);
    expect(
        t
            .widget<DesignSwitch>(
                find.byKey(const ValueKey('nav-ducking-switch')))
            .value,
        isFalse);
    await t.pump(const Duration(seconds: 4));
    await t.pumpAndSettle();
  });

  testWidgets('live preview renders the real desktop and follows appearance',
      (t) async {
    final (c, _) = await launch(t);
    c.openSettings();
    await t.pumpAndSettle();
    final preview = find.byKey(const ValueKey('live-preview'));
    expect(preview, findsOneWidget);
    // 预览是「真桌面」缩略，不是另画的示意图：顶栏 / 桌面 / 底栏都得在。
    expect(find.descendant(of: preview, matching: find.byType(Header)),
        findsOneWidget);
    expect(find.descendant(of: preview, matching: find.byType(Desktop)),
        findsOneWidget);
    expect(find.descendant(of: preview, matching: find.byType(BottomDock)),
        findsOneWidget);
    // 16:9，和桌面的画布比例一致，不会被拉变形。
    final size = t.getSize(preview);
    expect(size.width / size.height, closeTo(16 / 9, .01));
    // 取桌面那一层的样式：它在预览自己的 Theme 下面，改配色必须立刻跟上。
    int accentOf() => SurfaceStyle.of(t.element(
            find.descendant(of: preview, matching: find.byType(Desktop))))
        .accent
        .toARGB32();
    final before = accentOf();
    c.setAppearance(c.appearance.copyWith(palette: 'rose'));
    await t.pumpAndSettle();
    expect(accentOf(), isNot(before));
    expect(
        accentOf(),
        SurfaceStyle.from(c.appearance, c.native.value['dark'] == true,
                adaptToWallpaper: true)
            .accent
            .toARGB32());
    expect(t.takeException(), null);
  });
  testWidgets('wallpaper presets update the persisted appearance', (t) async {
    final (c, g) = await launch(t);
    c.openSettings();
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('wallpaper-overlay')), findsOneWidget);
    expect(find.text('叠加主题渐变'), findsOneWidget);
    expect(find.text('更改自动保存'), findsNothing);
    final dawn = find.byKey(const ValueKey('wallpaper-dawn'));
    await t.ensureVisible(dawn);
    await t.pumpAndSettle();
    await t.tap(dawn);
    await t.pumpAndSettle();
    expect(c.appearance.wallpaper, 'dawn');
    expect(c.appearance.mode, 'smart');
    expect(c.appearance.wallpaperOverlay, isFalse);
    expect(jsonDecode(g.saved!)['preferences']['wallpaperOverlay'], false);
    await t.tap(find.byKey(const ValueKey('wallpaper-overlay')));
    await t.pumpAndSettle();
    expect(c.appearance.wallpaperOverlay, isTrue);
    expect(jsonDecode(g.saved!)['preferences']['wallpaperOverlay'], true);
    expect(jsonDecode(g.saved!)['preferences']['wallpaper'], 'dawn');
    expect(jsonDecode(g.saved!)['preferences'], contains('wallpaperOverlay'));
    expect(find.byKey(const ValueKey('wallpaper-neon')), findsOneWidget);
    expect(find.byKey(const ValueKey('wallpaper-precision')), findsOneWidget);
    expect(find.byKey(const ValueKey('wallpaper-terrain')), findsOneWidget);
    final preview =
        t.getSize(find.byKey(const ValueKey('wallpaper-preview-dawn')));
    expect(preview.width / preview.height, closeTo(16 / 9, .01));
    expect(find.byType(WallpaperImage), findsWidgets);
    expect(t.takeException(), null);
  });
  testWidgets('desktop text contrast follows built-in and custom wallpapers',
      (t) async {
    final (c, g) = await launch(t);
    c.setAppearance(c.appearance.copyWith(mode: 'smart', wallpaper: 'neon'));
    await t.pumpAndSettle();
    expect(
        SurfaceStyle.of(t.element(find.byKey(const ValueKey('desktop-name'))))
            .dark,
        true);
    c.setAppearance(
        c.appearance.copyWith(mode: 'smart', wallpaper: 'precision'));
    await t.pumpAndSettle();
    expect(
        SurfaceStyle.of(t.element(find.byKey(const ValueKey('desktop-name'))))
            .dark,
        false);
    c.setAppearance(c.appearance.copyWith(mode: 'dark'));
    await t.pumpAndSettle();
    // Bare header ink follows this bright wallpaper; card mode stays dark.
    expect(
        SurfaceStyle.of(t.element(find.byKey(const ValueKey('desktop-name'))))
            .dark,
        false);
    expect(SurfaceStyle.of(t.element(find.byType(Desktop))).dark, true);
    c.openSettings();
    g.wallpaper = const PickedWallpaper('/tmp/dark-wallpaper.jpg', .16);
    await t.pumpAndSettle();
    final custom = find.byKey(const ValueKey('wallpaper-custom'));
    // 壁纸条是横向懒加载列表，最后一格（本地图片）在视口外，得先滚过去。
    await t.scrollUntilVisible(custom, 240,
        scrollable: find
            .descendant(
                of: find.byKey(const ValueKey('wallpaper-rail')),
                matching: find.byType(Scrollable))
            .first);
    await t.pumpAndSettle();
    await t.tap(custom);
    await t.pumpAndSettle();
    expect(c.appearance.wallpaper, 'custom');
    expect(c.appearance.mode, 'smart');
    expect(c.appearance.wallpaperLuminance, .16);
    c.home();
    await t.pumpAndSettle();
    expect(
        SurfaceStyle.of(t.element(find.byKey(const ValueKey('desktop-name'))))
            .dark,
        true);
    expect(t.takeException(), null);
  });
  testWidgets(
      'standard theme color picker exposes swatches and full color field',
      (t) async {
    final (c, _) = await launch(t);
    c.openSettings();
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('custom-color')));
    await t.pumpAndSettle();
    expect(
        find.byKey(const ValueKey('saturation-value-field')), findsOneWidget);
    expect(find.byKey(const ValueKey('hue-field')), findsOneWidget);
    expect(find.byKey(const ValueKey('color-picker-hex')), findsOneWidget);
    expect(
        find.byKey(const ValueKey('standard-color-#F44336')), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('standard-color-#F44336')));
    await t.pump();
    await t.tap(find.text('应用颜色'));
    await t.pumpAndSettle();
    expect(c.appearance.palette, 'custom');
    expect(c.appearance.custom, '#F44336');
    expect(t.takeException(), null);
  });
  test('general HVAC permission never grants seat read or write access', () {
    final n = <String, dynamic>{
      'demo': false,
      'vehicle': {'writable': true},
      'climate': {'driverHeat': 3}
    };
    final state = SeatControlState.fromNative(n, 'driverHeat');
    expect(state.writable, false);
    expect(state.level, null);
    n['vehicle'] = {
      'writable': true,
      'seatCapabilities': {
        'driverHeat': {'supported': true, 'readable': true, 'writable': false}
      }
    };
    final read = SeatControlState.fromNative(n, 'driverHeat');
    expect(read.writable, false);
    expect(read.level, 3);
    expect(SeatControlState.fromNative(n, 'passengerHeat').writable, false);
  });
  testWidgets(
      'three seat selectors route explicit levels with correct zones and match sheet width',
      (t) async {
    final (c, g) = await launch(t);
    showClimatePanel(t.element(find.byKey(const ValueKey('climate'))), c);
    await t.pumpAndSettle();
    expect(find.byType(LauncherSheet), findsOneWidget);
    expect(find.byType(SeatControls), findsOneWidget);
    for (final item in [
      ('driverHeat', 'seat-heat', 'left', 2),
      ('driverVent', 'seat-vent', 'left', 3),
      ('passengerHeat', 'seat-heat', 'right', 1)
    ]) {
      await t.ensureVisible(find.byKey(ValueKey('seat-${item.$1}-${item.$4}')));
      await t.tap(find.byKey(ValueKey('seat-${item.$1}-${item.$4}')));
      await t.pumpAndSettle();
      expect(g.commands.last, containsPair('action', item.$2));
      expect(g.commands.last, containsPair('zone', item.$3));
      expect(g.commands.last, containsPair('value', '${item.$4}'));
    }
    expect(find.text('副驾通风'), findsNothing);
    final sheet = t.widget<LauncherSheet>(find.byType(LauncherSheet));
    expect(sheet.width, closeTo(1200, .01));
    expect(t.takeException(), null);
  });
  testWidgets(
      'live unavailable seats show unknown and cannot send commands despite HVAC writable',
      (t) async {
    final (c, g) = await launch(t);
    g.state['demo'] = false;
    g.state['vehicle'] = {'writable': true};
    g.stream.add(Map.of(g.state));
    await t.pumpAndSettle();
    showClimatePanel(t.element(find.byKey(const ValueKey('climate'))), c);
    await t.pumpAndSettle();
    // 档位键在暗夜是自绘的 OutlinedButton，经典/蓝玻璃走统一的 ChoiceButton，
    // 两者都通过 `onPressed == null` 表达禁用，这里按「有没有回调」判断。
    bool disabled(String key) {
      final widget = t.widget(find.byKey(ValueKey(key)));
      final onPressed = switch (widget) {
        OutlinedButton(:final onPressed) => onPressed,
        ChoiceButton(:final onPressed) => onPressed,
        _ => fail('档位键既不是 OutlinedButton 也不是 ChoiceButton：$widget'),
      };
      return onPressed == null;
    }

    for (final key in ['driverHeat', 'driverVent', 'passengerHeat']) {
      expect(find.byKey(ValueKey('seat-unknown-$key')), findsOneWidget);
      for (int level = 1; level <= 3; level++)
        expect(disabled('seat-$key-$level'), isTrue);
    }
    expect(disabled('seat-driver-off'), isTrue);
    expect(disabled('seat-passengerHeat-0'), isTrue);
    expect(t.takeException(), null);
  });

  /// 设置页里有两页是「一屏看完」的版式：外观与壁纸（f9）、仪表投屏（f38）。
  /// 它们的块都按「刚好占满一屏」排的，而实机底部常驻多媒体底栏，可视高度只有
  /// 517 画布——块间距/内边距多一点，底部就会切掉半行并挂出滚动条。
  /// 这里把「不该滚」钉死，以后再往里塞东西时会先失败。
  ScrollPosition scrollByKey(WidgetTester t, Key key) => t
      .state<ScrollableState>(find
          .descendant(of: find.byKey(key), matching: find.byType(Scrollable))
          .first)
      .position;

  testWidgets('dock page fits one screen without scrolling', (t) async {
    final (c, _) = await launch(t);
    c.openSettings();
    await t.pumpAndSettle();
    c.tab('dock');
    await t.pumpAndSettle();
    // 这页现在是两栏：左边「底栏长什么样」（样式/图标大小/音乐工具条/系统默认桌面），
    // 右边「底栏接管了什么」（全局底栏、开机与 HOME 键）。一列排下来加了开机自启和
    // HOME 键两块之后要滚动，两栏是为了不用滚。
    expect(
        scrollByKey(t, const PageStorageKey('dock-settings-scroll'))
            .maxScrollExtent,
        0,
        reason: '应用与底栏页需要滚动：两栏没排平，或者有说明又长回去了');
    expect(find.text('底栏样式'), findsOneWidget);
    expect(find.text('底部音乐工具条'), findsOneWidget);
    // 流体只属于暗夜皮肤：浅色下这行还在（保证三皮肤同高），但开关是置灰的。
    expect(find.text('进度条烟雾流体'), findsOneWidget);
    expect(
        t
            .widget<DesignSwitch>(
                find.byKey(const ValueKey('dock-music-fluid-switch')))
            .onChanged,
        isNull);
    expect(find.text('开机与 HOME 键'), findsOneWidget);
    expect(find.text('系统默认桌面'), findsOneWidget);
    // 两栏下沿必须齐在一条线上：右栏那块吃掉剩余高度，不然它比左栏短一截，
    // 看着像右边漏画了一块。
    final leftBottom = t.getRect(find.byType(SystemDefaultHomeBlock)).bottom;
    final rightBottom = t
        .getRect(find.descendant(
            of: find.byType(BootAndHomeSettings),
            matching: find.byType(SettingBlock)))
        .bottom;
    expect(rightBottom, closeTo(leftBottom, .5), reason: '应用与底栏页两栏下沿没对齐');

    // 暗夜皮肤下才有那颗开关（流体只属于暗夜），换皮肤后两栏仍要对齐。
    c.setAppearance(c.appearance.copyWith(themeStyle: 'nocturne'), save: false);
    await t.pumpAndSettle();
    expect(
        t
            .widget<DesignSwitch>(
                find.byKey(const ValueKey('dock-music-fluid-switch')))
            .onChanged,
        isNotNull);
    expect(
        t
            .getRect(find.descendant(
                of: find.byType(BootAndHomeSettings),
                matching: find.byType(SettingBlock)))
            .bottom,
        closeTo(t.getRect(find.byType(SystemDefaultHomeBlock)).bottom, .5),
        reason: '换皮肤后两栏下沿又错开了');
    expect(t.takeException(), null);
  });

  testWidgets(
      'appearance and cluster lyrics each fit one screen without scrolling',
      (t) async {
    final (c, _) = await launch(t);
    c.openSettings();
    await t.pumpAndSettle();
    // 外观页不是滚动页：五块由 spaceBetween 撑满一屏。要盯的是两端留白
    // 一致、以及左栏下沿与右栏「返回桌面查看」落在同一条线上——之前左边
    // 比按钮高 8、比上沿多空 8，看着就是不齐。
    final left = t.getRect(
        find.byKey(const PageStorageKey('appearance-settings-scroll')));
    final lastBlock = t.getRect(find.byType(RadiusSetting));
    final backButton = t.getRect(find.byKey(const ValueKey('back-to-desktop')));
    expect(lastBlock.bottom, closeTo(left.bottom, .5));
    expect(lastBlock.bottom, closeTo(backButton.bottom, .5));
    expect(find.text('卡片圆角'), findsOneWidget);

    c.tab('cluster');
    await t.pumpAndSettle();
    for (final column in ['cluster-settings-left', 'cluster-settings-right']) {
      expect(scrollByKey(t, PageStorageKey(column)).maxScrollExtent, 0,
          reason: '$column 需要滚动');
    }
    expect(find.text('实现方式'), findsOneWidget);
    expect(find.text('字形与配色'), findsOneWidget);
    expect(t.takeException(), null);
  });

  /// 同一页换皮肤不该换版式。
  ///
  /// 「主题风格」和「主题配色」两排按钮原先按皮肤分流（暗夜 42/76、玻璃与
  /// 经典 47/86 画布），结果换主题时这两排一高一矮，下面几块跟着上下挪
  /// 十几像素，看着像另一套页面。现在三套共用暗夜那组值，这里把五块的
  /// 矩形和两个代表按钮的高度一起钉死。
  testWidgets('appearance blocks keep one geometry across the three skins',
      (t) async {
    final (c, _) = await launch(t);
    c.openSettings();
    await t.pumpAndSettle();

    List<Rect> blocks() {
      final f = find.byType(SettingBlock);
      return [
        for (var i = 0; i < f.evaluate().length; i++)
          if (t.getRect(f.at(i)).width > 500) t.getRect(f.at(i))
      ];
    }

    c.setAppearance(c.appearance.copyWith(themeStyle: 'nocturne'), save: false);
    await t.pumpAndSettle();
    final base = blocks();
    final baseMode = t.getRect(find.byKey(const ValueKey('mode-system')));
    final basePalette = t.getRect(find.byKey(const ValueKey('palette-mint')));
    expect(base.length, 5);

    for (final style in ['blueGlass', 'classic']) {
      c.setAppearance(c.appearance.copyWith(themeStyle: style), save: false);
      await t.pumpAndSettle();
      final now = blocks();
      expect(now.length, base.length, reason: '$style 块数不同');
      for (var i = 0; i < base.length; i++) {
        expect(now[i], base[i], reason: '$style 第 $i 块与暗夜不一致');
      }
      expect(t.getRect(find.byKey(const ValueKey('mode-system'))), baseMode,
          reason: '$style 主题风格按钮高度/位置与暗夜不一致');
      expect(t.getRect(find.byKey(const ValueKey('palette-mint'))), basePalette,
          reason: '$style 配色块与暗夜不一致');
      expect(t.takeException(), null);
    }
  });

  /// 「主题配色」六颗球：五套预设 + 自定义。选中态是压在球上的一枚白勾，
  /// 换色板之后勾必须跟着走，不能钉在第一颗上。
  ///
  /// 这套球按 sim board 09 的 `.pcol` 画：38×38 / 13 圆角 / 三段渐变 + 顶部
  /// 高光。高光层不单独断言（纯装饰），但「六颗球 + 唯一勾」是契约。
  testWidgets(
      'palette block shows six dots and only the current one carries a check',
      (t) async {
    final (c, _) = await launch(t);
    c.openSettings();
    await t.pumpAndSettle();

    for (final id in ['mint', 'blue', 'violet', 'amber', 'rose']) {
      expect(find.byKey(ValueKey('palette-$id')), findsOneWidget,
          reason: '$id 那颗球不见了');
    }
    expect(find.byKey(const ValueKey('custom-color')), findsOneWidget);

    Finder checkOn(String id) => find.descendant(
        of: find.byKey(ValueKey('palette-$id')),
        matching: find.byIcon(Icons.check_rounded));

    expect(checkOn('mint'), findsOneWidget);
    for (final id in ['blue', 'violet', 'amber', 'rose']) {
      expect(checkOn(id), findsNothing, reason: '$id 不是当前色板却带了勾');
    }

    await t.tap(find.byKey(const ValueKey('palette-amber')));
    await t.pumpAndSettle();
    expect(c.appearance.palette, 'amber');
    expect(checkOn('amber'), findsOneWidget);
    expect(checkOn('mint'), findsNothing);
    expect(t.takeException(), null);
  });
}
