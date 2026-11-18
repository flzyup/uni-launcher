import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import '../model/appearance.dart';
import '../model/ambient_light.dart';
import '../model/card_layout.dart';
import '../model/card_reorder.dart';
import '../platform/native_gateway.dart';
import '../platform/ambient_light.dart';
import '../platform/ui_routes.dart';
import '../platform/uni_log.dart';

class LauncherController extends ChangeNotifier with WidgetsBindingObserver {
  final NativeGateway gateway;
  final native = ValueNotifier<Map<String, dynamic>>({});
  Appearance appearance = const Appearance();
  AmbientLightSettings ambientLight = const AmbientLightSettings();
  Map<String, String> appNames = {};
  List<LauncherCard> cards = defaultCards();
  LauncherCard? placementOrigin, placementTarget;
  List<LauncherCard>? placementPreview;
  bool placementResizing = false;
  bool get placementValid => placementPreview != null;
  bool get placing => placementOrigin != null;

  /// Preview coordinates never enter cards, serialization or edit backups.
  bool beginPlacement(String id, {bool resizing = false}) {
    if (!editing || placing) return false;
    placementOrigin = cards.where((c) => c.id == id).firstOrNull;
    if (placementOrigin == null) return false;
    placementResizing = resizing;
    placementTarget = placementOrigin;
    placementPreview = List.of(cards);
    notifyListeners();
    return true;
  }

  bool previewPlacement(LauncherCard target) {
    final origin = placementOrigin;
    // `pageCount` itself is the trailing scratch page (see _setPage and the
    // grid list in desktop.dart): a card dropped there becomes a real page on
    // finishEdit. Rejecting `page == pageCount` here broke placement and
    // resize for cards added through beginEditAtEnd, which land on exactly
    // that page while the trailing page is still empty.
    if (origin == null || origin.id != target.id || target.page > pageCount)
      return false;
    final previous = placementTarget;
    if (previous != null &&
        (previous.page, previous.x, previous.y, previous.w, previous.h) ==
            (target.page, target.x, target.y, target.w, target.h))
      return placementValid;
    placementTarget = target;
    placementPreview = reorderCards(cards, target);
    notifyListeners();
    return placementValid;
  }

  LauncherCard? finishPlacement({bool cancel = false}) {
    if (!placing) return null;
    final target = !cancel && placementValid ? placementTarget : null;
    if (target != null) cards = placementPreview!;
    placementOrigin = placementTarget = null;
    placementPreview = null;
    placementResizing = false;
    notifyListeners();
    return target;
  }

  /// 页数必须由卡片实际占用推出来。默认布局现在有三页（第 3 页是时钟 + 天气 +
  /// 日历），写死 2 会让首启的页点少一个、尾部草稿页错位。
  static int pagesOf(List<LauncherCard> list) =>
      list.fold<int>(1, (n, c) => max(n, c.page + 1)).clamp(1, 20);
  int page = 0, pageCount = pagesOf(defaultCards());
  final pageChanged = ValueNotifier<int>(0);

  /// 原生记着的「上次停在第几页」（走 `desktopPage` 这条轻量通道顺手落盘，
  /// 不写整份设计 JSON，也就不会在每次翻页时触发一次完整快照回灌）。
  int lastDesktopPage = 0;

  /// 开机页只结算一次：prelude 与 bootstrap 都会调 `_applyDesign`，而用户可能
  /// 在 bootstrap 到达之前就已经翻过页了，第二次不能再把页码拽回去。
  bool _bootPageSettled = false;

  /// 被点开铺满整页的那张卡（卡片 id，null = 正常网格）。
  ///
  /// 铺满不是另开一页：网格里只渲染这一张卡、铺到整块桌面区域，顶部栏与底栏
  /// 照常显示；退出就回到原来的页面，卡位一个都不动。
  final focusedCard = ValueNotifier<String?>(null);

  void focusCard(String id) {
    if (settings || editing) return;
    if (focusedCard.value == id) return;
    focusedCard.value = id;
  }

  void unfocusCard() {
    if (focusedCard.value == null) return;
    focusedCard.value = null;
  }

  /// 把音乐卡铺满（卡片被点、或底栏请桌面代开都走这里）。
  ///
  /// 卡片不在当前页时先翻过去：铺满层是画在那一页的网格里的，页不对就什么都看不到。
  /// 没有音乐卡时返回 false，调用方自己决定退到什么（桌面退到老的媒体面板）。
  ///
  /// [cardId] 必须是**被点的那一张**（2026-11-15 实车反馈）：以前这里固定取
  /// `cards` 里第一张音乐卡，桌面上有两张时点第 2 页那张会先把桌面翻回第 1 页
  /// 那张，收起后就停在第一屏 —— 用户说的「每次返回都回首页」。底栏没有具体卡片，
  /// 才按「当前页的音乐卡 → 第一张」兜底。
  bool focusMusicCard({String? cardId}) {
    final card = (cardId == null
            ? null
            : cards.where((item) => item.id == cardId).firstOrNull) ??
        cards
            .where((item) => item.type == 'music' && item.page == page)
            .firstOrNull ??
        cards.where((item) => item.type == 'music').firstOrNull;
    if (card == null) return false;
    if (card.page != page) {
      _setPage(card.page);
      notifyListeners();
    }
    focusCard(card.id);
    return true;
  }

  int _pageRequest = 0;
  bool editing = false, ready = false;

  bool _settings = false;

  /// 进设置页时把手上的铺满卡片先收回去，免得出设置回来还压着桌面。
  bool get settings => _settings;

  set settings(bool value) {
    if (value == _settings) return;
    _settings = value;
    if (value) unfocusCard();
  }

  /// 外观与布局已经读到（prelude 就算数）。根组件靠它决定是画兜底画布，
  /// 还是把真正的桌面挂上去。
  bool designReady = false;

  /// 引擎被新窗口接管（Activity 重建）的次数。平台视图归窗口所有，接到通知
  /// 后要按新的 epoch 重建，不能继续用一个已经关掉的原生句柄。
  int hostEpoch = 0;
  Future<void> Function()? beforeExternalLaunch;
  String _overlayDesign = '';
  bool get isGlobalDock =>
      {'global-dock', 'global-panel'}.contains(native.value['hostMode']);

  /// Route card and dock entry points to the same physical panel window.
  Future<bool> presentGlobalPanel(String panel) async {
    final dock = native.value['globalDock'];
    if (native.value['hostMode'] == 'global-panel' ||
        dock is! Map ||
        dock['running'] != true ||
        dock['visible'] == false ||
        dock['enabled'] != true) {
      return false;
    }
    await command('show-dock-panel', value: panel);
    return true;
  }

  String settingsTab = 'appearance', message = '';
  List<LauncherCard>? _backup, _undo;
  int _backupPages = 2;
  StreamSubscription<Map<String, dynamic>>? _subscription;
  Future<void> _saveTail = Future.value();
  // Budgets include both the UTF-16 source key and compressed image bytes.
  final _icons = _SnapshotImages(256, 4 * 1024 * 1024);
  final _recentImages = _SnapshotImages(48, 6 * 1024 * 1024);
  bool _observingMemory = false;
  bool _disposed = false;

  @visibleForTesting
  Map<String, int> get imageCacheStats => {
        'iconCount': _icons.count,
        'iconBytes': _icons.retainedBytes,
        'recentCount': _recentImages.count,
        'recentBytes': _recentImages.retainedBytes,
      };

  /// Releases reusable buffers without removing images from the visible state.
  /// Also safe for an entrypoint/native memory-pressure callback to invoke.
  void trimMemory() {
    if (_disposed) return;
    _icons.clear();
    _recentImages.clear();
    PaintingBinding.instance.imageCache.clear();
  }

  @override
  void didHaveMemoryPressure() => trimMemory();
  LauncherController(this.gateway);
  Future<void> initialize() async {
    await initializePrelude();
    await initializeRest();
  }

  /// 第一阶段：只把「第一帧需要的东西」准备好 —— 外观、布局、宿主回调。
  ///
  /// 拆出来是为了让 `main()` 能在 `runApp` 之前 await 它：首帧直接就是真桌面，
  /// 而不是「先一块启动底色的空画布，等 prelude 回来再跳成桌面」。prelude 只读
  /// 偏好、不碰适配器，往返一次几十毫秒；真的慢了由调用方超时兜底。
  Future<void> initializePrelude() async {
    // Every engine (launcher, dock and panel) initializes its own controller.
    if (_disposed) return;
    UniLog.enter(UniLogTags.app, 'launcher/bootstrap');
    if (!_observingMemory) {
      final imageCache = PaintingBinding.instance.imageCache;
      imageCache.maximumSize = 64;
      imageCache.maximumSizeBytes = 10 * 1024 * 1024;
      WidgetsBinding.instance.addObserver(this);
      _observingMemory = true;
    }
    gateway.onHome(home);
    gateway.onHomeFirst(homeFirst);
    if (gateway is AndroidGateway) {
      (gateway as AndroidGateway)
          .onOpenSettings((tab) => openSettings(tab: tab));
      (gateway as AndroidGateway).onHostRebound(_hostRebound);
      // 底栏引擎没有桌面，点音乐只能请这一侧代开：原生转一条 focus-music-card 过来。
      (gateway as AndroidGateway).onFocusMusicCard(focusMusicCard);
    }
    // 只要外观和布局。这一段只读偏好，不碰任何适配器，第一帧用的就是正确
    // 的主题；完整快照（车辆/媒体/天气/图标）随后补齐。
    await _applyPrelude();
  }

  /// 第二阶段：完整快照 + 事件流。首帧之后才需要，绝不能挡在第一帧前面。
  Future<void> initializeRest() async {
    if (_disposed) return;
    try {
      final state = await gateway.bootstrap();
      if (_disposed) return;
      _applyDesign(state['savedDesign'], state['appNames'],
          state['lastDesktopPage']);
      _receive(state);
      if (state['initialSettings'] == true) settings = true;
      _subscription = gateway.events.listen(_receive, onError: (Object e) {
        message = '原生连接暂不可用';
        UniLog.w(UniLogTags.app, '原生事件流中断', fields: {'error': '$e'});
        notifyListeners();
      });
      UniLog.done(UniLogTags.app, 'launcher/bootstrap',
          fields: {'cards': cards.length, 'pages': pageCount});
    } catch (e) {
      message = '等待 Android 接入';
      UniLog.fail(UniLogTags.app, 'launcher/bootstrap', fields: {'error': '$e'});
    }
    if (_disposed) return;
    ready = true;
    if (!designReady) designReady = true;
    _syncAmbientLight();
    notifyListeners();
  }

  /// 首帧通道：只有外观与布局，拿不到就当作没有（下面的 bootstrap 会补）。
  Future<void> _applyPrelude() async {
    try {
      final prelude = await gateway.prelude();
      if (_disposed || prelude == null) return;
      _applyDesign(prelude['savedDesign'], prelude['appNames'],
          prelude['lastDesktopPage']);
      // 从设置入口启动时这个标记只发一次（prelude 会消费掉），这里必须接住。
      if (prelude['initialSettings'] == true) settings = true;
      designReady = true;
      notifyListeners();
    } catch (_) {
      // 快通道失败不影响引导：完整快照那条路还在。
    }
  }

  /// 窗口重建、引擎被接管：平台视图跟着换一代，界面按新 epoch 重建它们。
  void _hostRebound() {
    if (_disposed) return;
    hostEpoch++;
    notifyListeners();
  }

  /// 解析 savedDesign：外观、氛围灯、显示名与卡片布局。
  ///
  /// prelude 与 bootstrap 带的是同一份字符串，所以这段只写一次；[names] 是
  /// 原生顺手带上的应用显示名，优先于布局里存的那一份。
  void _applyDesign(Object? raw, Object? names, [Object? lastPage]) {
    if (lastPage is num) {
      lastDesktopPage = lastPage.toInt().clamp(0, 19);
    }
    if (raw is! String || raw.isEmpty) return;
    try {
      final data = jsonDecode(raw) as Map<String, dynamic>;
      appearance = Appearance.fromJson(
          Map<String, dynamic>.from(data['preferences'] ?? {}));
      ambientLight = AmbientLightSettings.fromJson(
          Map<String, dynamic>.from(data['ambientLight'] ?? {}));
      appNames = _decodeAppNames(names ?? data['appNames']);
      final parsed = (data['cards'] as List)
          .map((c) => LauncherCard.fromJson(Map<String, dynamic>.from(c)))
          .toList();
      // 旧版本默认给过第 3 页（时钟 / 天气 / 日历）。那一页上如果只剩这三张
      // 默认卡，直接清掉：主屏默认只留两页，想要的人自己从「添加卡片」加。
      // 用户往里加过别的卡就整页保留，不碰他的布局。
      final restored = stripLegacyDefaultPage3(parsed);
      if (validLayout(restored)) {
        cards = restored;
        // Empty trailing pages are editor scratch space, not persistent
        // desktops. Keeping them made an empty-page prompt animate over
        // the last real page after restart.
        pageCount = cards.fold<int>(1, (n, c) => max(n, c.page + 1)).clamp(1, 20);
      }
    } catch (_) {
      message = '旧布局无法读取，已恢复默认卡片';
      UniLog.w(UniLogTags.app, '旧布局无法读取，已恢复默认卡片');
    }
    _settleBootPage();
  }

  /// 把手势之外的开机页落下去：`appearance.bootPage` 是用户明确选的，
  /// `-1` 则用原生记住的上次停留页。
  ///
  /// 只在 `pageCount` 与 `appearance` 都就绪之后调，所以要把请求 clamp 到真实
  /// 页数里——用户可能设了第 3 页，后来又把那页的卡删光，页数缩回 2。
  void _settleBootPage() {
    if (_bootPageSettled) return;
    _bootPageSettled = true;
    final wanted = appearance.bootPage >= 0
        ? appearance.bootPage
        : lastDesktopPage;
    final target = wanted.clamp(0, pageCount - 1);
    if (target == page) return;
    page = target;
    pageChanged.value = target;
    // 原生侧靠这一条决定「桌面内容要不要盖在地图上」（page == 0 才接管），
    // 启动时不同步会让它一直以为停在第 1 页。
    unawaited(gateway.setDesktopPage(target).catchError((Object _) {}));
  }

  /// 设置里的「开机进入」：`-1` = 上次停留，其余是 0 起的页索引。
  Future<void> setBootPage(int value) async {
    final next = value.clamp(-1, pageCount - 1);
    if (next == appearance.bootPage) return;
    appearance = appearance.copyWith(bootPage: next);
    notifyListeners();
    await persist();
  }

  /// Payloads that Android sends on bootstrap and on change, never with every
  /// telemetry tick. A partial packet omits them and the last copy is retained.
  static const _carriedKeys = [
    'apps',
    'recentTasks',
    'savedDesign',
    'appNames'
  ];
  static const _carriedMedia = [
    'artwork',
    'lyrics',
    'lyricTimeline',
    'lyricTimelineLabel',
    'lyricTimelineWords',
  ];

  /// Last observed media identity, so only real transitions are logged.
  /// Telemetry packets arrive up to 12 times a second; logging each one would
  /// bury everything else in the package.
  String? _lastMediaTitle;
  bool? _lastMediaPlaying;

  /// App list size last seen, to log a refresh only when it really changed.
  int? _lastAppCount;

  /// Whether the settings catalogue has already been delivered.
  bool _settingsCatalogSeen = false;

  static bool _shallowMediaSame(Object? a, Object? b) {
    if (identical(a, b)) return true;
    if (a is Map && b is Map) {
      if (a.length != b.length) return false;
      for (final key in a.keys) {
        if (!b.containsKey(key) || !_shallowMediaSame(a[key], b[key])) {
          return false;
        }
      }
      return true;
    }
    if (a is List && b is List) {
      if (a.length != b.length) return false;
      for (var i = 0; i < a.length; i++) {
        if (!_shallowMediaSame(a[i], b[i])) return false;
      }
      return true;
    }
    return a == b;
  }

  void _receive(Map<String, dynamic> incoming) {
    final previous = native.value;
    // A partial packet carries telemetry only: merge it over the last state so
    // omitted payloads keep their instance (the icon/artwork caches, and every
    // deep comparison in NativeSliceBuilder, depend on identical references).
    final partial = incoming['partial'] == true;
    Map<String, dynamic> state = incoming;
    if (partial) {
      state = <String, dynamic>{...incoming}..remove('partial');
      for (final key in _carriedKeys) {
        if (!state.containsKey(key) && previous.containsKey(key)) {
          state[key] = previous[key];
        }
      }
      final media = state['media'], previousMedia = previous['media'];
      if (media is Map && previousMedia is Map) {
        final sameTrack = media['title'] == previousMedia['title'] &&
            media['artist'] == previousMedia['artist'] &&
            media['source'] == previousMedia['source'];
        Map<String, dynamic>? merged;
        if (sameTrack) {
          for (final key in _carriedMedia) {
            if (!media.containsKey(key) && previousMedia.containsKey(key)) {
              merged ??= Map<String, dynamic>.from(media);
              merged[key] = previousMedia[key];
            }
          }
        }
        final candidate = merged ?? media;
        if (_shallowMediaSame(candidate, previousMedia)) {
          state['media'] = previousMedia;
        } else if (merged != null) {
          state['media'] = merged;
        }
      }
    }
    // The settings catalog can contain hundreds of entries. Android sends it
    // on bootstrap/explicit refresh, rather than with every telemetry event.
    if (!state.containsKey('systemSettings') &&
        previous.containsKey('systemSettings')) {
      state = {...state, 'systemSettings': previous['systemSettings']};
    }
    if (_disposed) return;
    // Bookkeeping only for payloads this packet actually carries; running it on
    // a packet that omits them would evict images that are still on screen.
    final keepIcons = !(partial && !incoming.containsKey('apps'));
    final keepRecents = !(partial && !incoming.containsKey('recentTasks'));
    if (keepIcons) _icons.begin(previous['apps'], const ['icon']);
    if (keepRecents) {
      _recentImages.begin(previous['recentTasks'], const ['icon', 'snapshot']);
    }
    final apps = state['apps'];
    if (keepIcons && apps is List) {
      state = {
        ...state,
        'apps': [
          for (final app in apps)
            if (app is Map) _decodeImages(app, const ['icon'], _icons) else app,
        ]
      };
    }
    final recentTasks = state['recentTasks'];
    final dock = state['globalDock'];
    // An explicit non-recents panel means its stale task payload is hidden.
    final recentsClosed =
        dock is Map && dock.containsKey('panel') && dock['panel'] != 'recents';
    if (keepRecents && recentTasks is List) {
      state = {
        ...state,
        'recentTasks': recentsClosed
            ? <dynamic>[]
            : [
                for (final task in recentTasks)
                  if (task is Map)
                    _decodeImages(
                        task, const ['icon', 'snapshot'], _recentImages)
                  else
                    task,
              ]
      };
    }
    if (keepIcons) _icons.finish();
    if (keepRecents) _recentImages.finish();
    bool overlayThemeChanged = false;
    if ({'global-dock', 'global-panel'}.contains(state['hostMode']) &&
        state['savedDesign'] is String &&
        state['savedDesign'] != _overlayDesign) {
      _overlayDesign = state['savedDesign'];
      try {
        appearance = Appearance.fromJson(Map<String, dynamic>.from(
            jsonDecode(_overlayDesign)['preferences']));
        if (state['appNames'] is! Map) {
          appNames = _decodeAppNames(jsonDecode(_overlayDesign)['appNames']);
        }
        overlayThemeChanged = true;
      } catch (_) {}
    }
    if (state['appNames'] is Map) {
      final nextNames = _decodeAppNames(state['appNames']);
      if (!mapEquals(appNames, nextNames)) {
        appNames = nextNames;
        overlayThemeChanged = true;
      }
    }
    final oldDark = native.value['dark'];
    final oldDemo = native.value['demo'];
    final oldSimulationMode = native.value['simulationMode'];
    final oldEmbed = (native.value['navigation'] as Map?)?['canEmbed'];
    final oldHeight = native.value['viewportHeightPx'];
    native.value = state;
    _logTransitions(state);
    if (state['message'] is String && (state['message'] as String).isNotEmpty) {
      message = state['message'];
      notifyListeners();
    }
    if (overlayThemeChanged ||
        (appearance.mode == 'system' && oldDark != state['dark']) ||
        oldDemo != state['demo'] ||
        oldSimulationMode != state['simulationMode'] ||
        oldHeight != state['viewportHeightPx'] ||
        oldEmbed != (state['navigation'] as Map?)?['canEmbed'])
      notifyListeners();
  }

  /// Logs only the transitions worth recording.
  ///
  /// Telemetry packets arrive up to 12 times a second, so logging every one
  /// of them would bury the rest of the package. What matters on a head unit
  /// is "the app list changed", "the song changed", "the play state flipped",
  /// "the settings catalogue arrived".
  void _logTransitions(Map<String, dynamic> state) {
    final apps = state['apps'];
    if (apps is List) {
      final count = apps.length;
      if (count != _lastAppCount) {
        _lastAppCount = count;
        UniLog.i(UniLogTags.apps, '应用列表刷新', fields: {'count': count});
      }
    }
    final media = state['media'];
    if (media is Map) {
      final title = media['title']?.toString();
      final playing = media['playing'] == true;
      if (title != _lastMediaTitle) {
        _lastMediaTitle = title;
        UniLog.i(UniLogTags.media, '媒体曲目变化',
            fields: {'title': title ?? '(无)', 'artist': media['artist']});
      }
      if (playing != _lastMediaPlaying) {
        _lastMediaPlaying = playing;
        UniLog.i(UniLogTags.media, '播放状态变化', fields: {'playing': playing});
      }
    }
    if (!_settingsCatalogSeen && state['systemSettings'] is Map) {
      _settingsCatalogSeen = true;
      final entries = (state['systemSettings'] as Map)['entries'];
      UniLog.done(UniLogTags.setting, 'settings/catalog',
          fields: {'entries': entries is List ? entries.length : 0});
    }
  }

  Map<String, dynamic> _decodeImages(
      Map source, List<String> fields, _SnapshotImages cache) {    final result = Map<String, dynamic>.from(source);
    for (final field in fields) {
      result.remove('${field}Bytes');
      final raw = source[field];
      if (raw is String && raw.isNotEmpty) {
        final bytes = cache.decode(raw);
        if (bytes != null) result['${field}Bytes'] = bytes;
      }
    }
    return result;
  }

  Future<void> command(String action,
      {String? value, String? zone, bool? enabled}) async {
    // Every user action funnels through here, so this is the one place that
    // can say "the tap never reached the native side" versus "the native side
    // rejected it".
    UniLog.event(UniLogTags.ui, '命令下发',
        fields: {
          'action': action,
          if (value != null) 'value': value,
          if (zone != null) 'zone': zone,
          if (enabled != null) 'enabled': enabled,
        });
    try {
      if (isGlobalDock &&
          {
            'launch-app',
            'app-info',
            'request-uninstall',
            'launch-navigation',
            'launch-player',
            'open-official',
            'official-widget',
            'open-system-setting',
            'show-home',
            'show-desktop-settings',
            'show-recents'
          }.contains(action)) {
        await beforeExternalLaunch?.call();
      }
      await gateway.action(action, value: value, zone: zone, enabled: enabled);
    } catch (e) {
      message = '操作暂不可用';
      UniLog.w(UniLogTags.ui, '命令下发失败',
          fields: {'action': action, 'error': '$e'});
      notifyListeners();
    }
  }

  String serialize() => jsonEncode({
        'version': 6,
        'preferences': appearance.toJson(),
        'ambientLight': ambientLight.toJson(),
        'cards': cards.map((c) => c.toJson()).toList(),
        'pageCount': pageCount,
        'appNames': appNames
      });

  static Map<String, String> _decodeAppNames(Object? raw) {
    if (raw is! Map) return {};
    final result = <String, String>{};
    for (final entry in raw.entries) {
      final package = entry.key.toString().trim();
      final name = _normalizeAppName(entry.value);
      if (package.isNotEmpty && name.isNotEmpty) result[package] = name;
    }
    return result;
  }

  static String _normalizeAppName(Object? value) {
    final text =
        value is String ? value.replaceAll(RegExp(r'[\r\n]'), ' ').trim() : '';
    return String.fromCharCodes(text.runes.take(24));
  }

  String appName(Map<String, dynamic> app) {
    final package = app['package']?.toString();
    return (package == null ? null : appNames[package]) ??
        '${app['label'] ?? package ?? '应用'}';
  }

  Future<void> renameApp(String package, String name) async {
    package = package.trim();
    if (package.isEmpty) return;
    final normalized = _normalizeAppName(name);
    appNames = Map.of(appNames);
    if (normalized.isEmpty) {
      appNames.remove(package);
    } else {
      appNames[package] = normalized;
    }
    native.value = Map.of(native.value);
    notifyListeners();
    try {
      await gateway.action('rename-app', zone: package, value: normalized);
    } catch (_) {
      message = '应用名称保存失败，请重试';
      notifyListeners();
    }
    await persist();
  }

  Future<void> persist() {
    final payload = serialize();
    _saveTail = _saveTail
        .catchError((_) {})
        .then((_) => gateway.save(payload))
        .catchError((Object e) {
      message = '保存失败，请重试';
      notifyListeners();
    });
    return _saveTail;
  }

  void setAppearance(Appearance next, {bool save = true}) {
    appearance = next;
    notifyListeners();
    if (save) persist();
  }

  /// Only the desktop engine drives the ambient strip. The global dock and
  /// the global panel run in their own isolates, and a second writer would
  /// race the first one for the same colour.
  bool get drivesAmbientLight => !isGlobalDock;

  /// Stores the ambient light settings and hands them to the head unit.
  void setAmbientLight(AmbientLightSettings next) {
    if (next == ambientLight) return;
    ambientLight = next;
    notifyListeners();
    persist();
    if (drivesAmbientLight) {
      unawaited(AmbientLightService.shared.applySettings(next));
    }
  }

  /// Pushes the stored settings to the head unit channel and reads its
  /// capability back.
  void _syncAmbientLight() {
    if (!drivesAmbientLight) return;
    final service = AmbientLightService.shared;
    unawaited(service.applySettings(ambientLight));
    unawaited(service.refreshStatus());
  }

  bool get bootAutostart =>
      (native.value['integrationPreferences'] is Map &&
          native.value['integrationPreferences']['bootAutostart'] != null)
          ? native.value['integrationPreferences']['bootAutostart'] == true
          : true;

  String get homeKeyTarget =>
      (native.value['integrationPreferences'] is Map &&
          native.value['integrationPreferences']['homeKeyTarget'] != null)
          ? '${native.value['integrationPreferences']['homeKeyTarget']}'
          : 'uni';

  void setBootAutostart(bool enabled) {
    command('boot-autostart', enabled: enabled);
  }

  void setHomeKeyTarget(String target) {
    command('home-key-target', value: target);
  }

  void openHomeSettings() {
    command('open-home-settings');
  }

  /// 外部回桌面（HOME intent、桌面入口、全局底栏）。
  ///
  /// [resetPage] 默认 false：Android 桌面的语义是「回到你离开时的那一页」。
  /// 以前这里无条件 `_setPage(0)`，于是从第三方应用按 home 回来时，桌面会当着
  /// 用户的面翻回第一页 —— 那一段翻页动画正是「返回不够流畅」里最直接的观感
  /// 来源（画面在动，而不是稳稳地就在那儿）。
  void home({bool resetPage = false}) {
    // 诊断锚点：这条走 Dart → logcat（flutter tag）的直连路径，不经过原生主线程，
    // 所以它和紧接着的平台通道日志之间的差值，就是「原生主线程还在忙」的时长。
    // 排查返回桌面耗时只看这一对时间戳。
    debugPrint('[UNI-RESUME] home ${DateTime.now().millisecondsSinceEpoch}');
    UniLog.event(UniLogTags.ui, '返回桌面',
        fields: {'from': settingsTab, 'resetPage': resetPage});
    if (isGlobalDock) {
      command('show-home');
      return;
    }
    // 以前编辑态直接 return，于是按 HOME 在编辑模式里毫无反应。HOME 是明确的用户
    // 指令：先把编辑收尾（已提交的布局保留），再回桌面。
    if (editing) finishEdit();
    settings = false;
    // 铺满的音乐卡也是压在桌面上的一层：HOME 是「回桌面」，它必须一起收掉，
    // 否则回到第一屏还盖着那张卡（`settings` 的 setter 只在进设置时清）。
    unfocusCard();
    if (resetPage) {
      // 全部应用页、最近任务、媒体/空调这类面板是压在桌面上的路由或全局底栏的
      // 独立窗口。HOME 是「回桌面」的明确指令，两层都要收：路由栈退回根，
      // 底栏面板窗口一并收起（底栏没在跑时这条是空操作）。
      popToLauncherRoot();
      unawaited(command('dismiss-dock-panel'));
      _setPage(0);
    } else {
      // 保留用户离开时那一页，但**必须取消在途的切页请求**：延迟返回的平台
      // 回复不允许在回桌面之后再改一次页码。只递增请求号，不额外下发
      // setDesktopPage —— 与原行为一致，不引入新的平台往返。
      _pageRequest++;
    }
    notifyListeners();
  }

  /// 车机 HOME 键 / 桌面入口 HOME intent：落回第一屏。
  ///
  /// 和 `home()` 默认行为的区别就是 [resetPage]：默认那条服务于「窗口被复用」
  /// （从第三方应用切回来，停在原页更稳），这条服务于「用户明确按了 HOME」。
  void homeFirst() => home(resetPage: true);
  /// 打开桌面设置。[tab] 为要直接落到的一栏（见 `settings_screen.dart` 的分类表）；
  /// 全局底栏那条路要绕一趟原生 Activity，所以 tab 走命令参数传过去。
  Future<void> openSettings({String? tab}) async {
    UniLog.event(UniLogTags.ui, '打开桌面设置', fields: {if (tab != null) 'tab': tab});
    if (isGlobalDock) {
      // 必须等命令发完：全局面板在调用返回后会立刻补一条 dismiss-dock-panel，
      // 不等的话顺序会反过来，先收面板再开设置，设置窗口就被自己收掉了。
      await command('show-desktop-settings', value: tab);
      return;
    }
    if (editing) return;
    settings = true;
    if (tab != null) settingsTab = tab == 'sources' ? 'system' : tab;
    notifyListeners();
  }

  /// 返回键：一层一层往上收。
  ///
  /// 铺满的音乐卡最先收（用户 2026-11-15 反馈「只能点右上角箭头才退得出来」）：
  /// 它压在桌面上，是视觉上最外的一层。
  void back() {
    if (focusedCard.value != null) {
      unfocusCard();
      notifyListeners();
    } else if (editing) {
      cancelEdit();
    } else if (settings) {
      settings = false;
      notifyListeners();
    }
  }

  void tab(String value) {
    settingsTab = value == 'sources' ? 'system' : value;
    notifyListeners();
    if (settingsTab == 'system') command('refresh-system-settings');
  }

  Future<void> switchPage(int value) async {
    // pageCount itself is the transient trailing library page. It is not part
    // of pageCount until a card is actually placed there —— 而且**只有编辑态**
    // 才挂着它（普通浏览时那页不存在，见 desktop.dart 的 _gridsFor）。
    final last = editing ? pageCount : (pageCount - 1).clamp(0, 20);
    final target = value.clamp(0, last).toInt(), request = ++_pageRequest;
    if (target == page) return;
    unfocusCard();
    // Page selection is intentionally a small one-way platform call. Sending
    // it through the general action channel publishes a complete vehicle
    // snapshot and rebuilds every telemetry/media card during a swipe.
    // Hide Android's independent map Surface BEFORE changing the Flutter
    // workspace. A post-frame hide can briefly put that Surface over page two.
    try {
      await gateway.setDesktopPage(target);
    } catch (_) {}
    if (request == _pageRequest) _setPage(target);
  }

  void cancelPendingPageSwitch() {
    _pageRequest++;
    // A late edge-switch reply must not leave the native page signal ahead of
    // the committed Flutter workspace. This is a lightweight one-way signal.
    unawaited(gateway.setDesktopPage(page).catchError((Object _) {}));
  }

  void _setPage(int value) {
    _pageRequest++;
    page = value;
    if (pageChanged.value != value) pageChanged.value = value;
  }

  void beginEdit() {
    if (editing) return;
    unfocusCard();
    _backup = List.of(cards);
    _backupPages = pageCount;
    editing = true;
    settings = false;
    notifyListeners();
  }

  void beginEditAtEnd() {
    beginEdit();
    _setPage(pageCount);
    notifyListeners();
  }

  void finishEdit() {
    finishPlacement(cancel: true);
    pageCount = cards.fold<int>(1, (n, c) => max(n, c.page + 1));
    _setPage(page.clamp(0, pageCount - 1));
    editing = false;
    _backup = null;
    persist();
    notifyListeners();
  }

  void cancelEdit() {
    finishPlacement(cancel: true);
    cards = _backup ?? cards;
    pageCount = _backupPages;
    _setPage(page.clamp(0, pageCount - 1));
    editing = false;
    _backup = null;
    notifyListeners();
  }

  void remove(String id) {
    finishPlacement(cancel: true);
    _undo = List.of(cards);
    cards = cards.where((c) => c.id != id).toList();
    notifyListeners();
  }

  void undoRemove() {
    if (_undo != null) {
      cards = _undo!;
      _undo = null;
      notifyListeners();
    }
  }

  bool transform(LauncherCard next) {
    if (!next.inBounds || cards.any((c) => c.id != next.id && c.overlaps(next)))
      return false;
    cards = cards.map((c) => c.id == next.id ? next : c).toList();
    notifyListeners();
    return true;
  }

  Future<void> setShortcutApps(String id, List<String> apps) async {
    if (editing || !cards.any((c) => c.id == id && c.type == 'shortcuts'))
      return;
    final selected = apps
        .where((id) => id.isNotEmpty && id.length <= 512)
        .toSet()
        .take(12)
        .toList();
    cards = cards
        .map((c) => c.id == id ? c.copyWith(shortcutApps: selected) : c)
        .toList();
    notifyListeners();
    await persist();
  }

  /// Move a card to another desktop and select the nearest free cell to the
  /// pointer's original grid position. This is used by edge dragging while the
  /// editor is open, so a card never lands on top of another card.
  bool moveToPage(String id, int targetPage,
      {int? preferredX, int? preferredY}) {
    if (targetPage < 0 || targetPage >= pageCount) return false;
    final index = cards.indexWhere((card) => card.id == id);
    if (index < 0) return false;
    final card = cards[index],
        px = preferredX ?? card.x,
        py = preferredY ?? card.y;
    final cells = <(int, int)>[
      for (int y = 0; y <= 6 - card.h; y++)
        for (int x = 0; x <= 12 - card.w; x++) (x, y)
    ]..sort((a, b) {
        final ad = (a.$1 - px).abs() + (a.$2 - py).abs();
        final bd = (b.$1 - px).abs() + (b.$2 - py).abs();
        return ad == bd
            ? (a.$2 * 12 + a.$1).compareTo(b.$2 * 12 + b.$1)
            : ad.compareTo(bd);
      });
    for (final cell in cells) {
      final next = card.copyWith(page: targetPage, x: cell.$1, y: cell.$2);
      if (!cards.any((other) => other.id != id && other.overlaps(next))) {
        cards = [
          for (final item in cards)
            if (item.id == id) next else item
        ];
        _setPage(targetPage);
        notifyListeners();
        return true;
      }
    }
    return false;
  }

  bool add(String type) {
    final spec = specFor(type);
    LauncherCard? next;
    for (int y = 0; y <= 6 - spec.h; y++) {
      for (int x = 0; x <= 12 - spec.w; x++) {
        final c = LauncherCard('card-${DateTime.now().microsecondsSinceEpoch}',
            type, spec.label, x, y, spec.w, spec.h, page);
        if (!cards.any((old) => old.overlaps(c))) {
          next = c;
          break;
        }
      }
      if (next != null) break;
    }
    if (next == null) {
      if (pageCount >= 20) return false;
      _setPage(pageCount++);
      next = LauncherCard('card-${DateTime.now().microsecondsSinceEpoch}', type,
          spec.label, 0, 0, spec.w, spec.h, page);
    }
    cards = [...cards, next];
    notifyListeners();
    return true;
  }

  void newPage() {
    if (pageCount < 20) {
      _setPage(pageCount++);
      notifyListeners();
    }
  }

  void resetLayout() {
    cards = defaultCards();
    pageCount = pagesOf(cards);
    _setPage(0);
    persist();
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    if (_observingMemory) WidgetsBinding.instance.removeObserver(this);
    _icons.clear();
    _recentImages.clear();
    native.value = {};
    _pageRequest++;
    _subscription?.cancel();
    pageChanged.dispose();
    focusedCard.dispose();
    native.dispose();
    super.dispose();
  }
}

/// Retains only admitted images from the latest snapshot. Never decodes an
/// oversized source, and never evicts a current entry to admit a later one.
class _SnapshotImages {
  final int maxEntries, maxBytes;
  Map<String, Uint8List> _current = {}, _previous = {};
  int retainedBytes = 0;
  _SnapshotImages(this.maxEntries, this.maxBytes);
  int get count => _current.length;

  void begin(Object? visible, List<String> fields) {
    // trimMemory drops cache ownership, but the visible snapshot still owns
    // its buffers. Borrow those references on the next event to avoid decoding
    // unchanged images into new MemoryImage identities after memory pressure.
    if (_current.isEmpty && visible is List) {
      var restoredBytes = 0;
      for (final item in visible) {
        if (item is! Map) continue;
        for (final field in fields) {
          final raw = item[field], bytes = item['${field}Bytes'];
          if (raw is! String ||
              bytes is! Uint8List ||
              _current.containsKey(raw)) {
            continue;
          }
          final cost = raw.length * 2 + bytes.lengthInBytes;
          if (_current.length < maxEntries &&
              restoredBytes + cost <= maxBytes) {
            _current[raw] = bytes;
            restoredBytes += cost;
          }
        }
      }
    }
    _previous = _current;
    _current = {};
    retainedBytes = 0;
  }

  Uint8List? decode(String raw) {
    final existing = _current[raw];
    if (existing != null) return existing;
    final remaining = maxBytes - retainedBytes;
    if (count >= maxEntries || raw.length * 2 > remaining) return null;
    try {
      final payload = raw.substring(raw.lastIndexOf(',') + 1);
      // Upper bound on decoded size; check before allocating the buffer.
      if (raw.length * 2 + ((payload.length + 3) ~/ 4) * 3 > remaining) {
        return null;
      }
      final bytes = _previous[raw] ?? base64Decode(payload);
      if (bytes.isEmpty) return null;
      _current[raw] = bytes;
      retainedBytes += raw.length * 2 + bytes.lengthInBytes;
      return bytes;
    } catch (_) {
      return null;
    }
  }

  void finish() {
    for (final entry in _previous.entries) {
      if (!_current.containsKey(entry.key)) _evict(entry.value);
    }
    _previous = {};
  }

  void clear() {
    for (final bytes in {..._previous, ..._current}.values) {
      _evict(bytes);
    }
    _previous = {};
    _current = {};
    retainedBytes = 0;
  }

  void _evict(Uint8List bytes) {
    // Keep an on-screen ImageStream alive, but remove pending/keepAlive cache
    // retention. These widgets use unresized MemoryImage providers.
    PaintingBinding.instance.imageCache
        .evict(MemoryImage(bytes), includeLive: false);
  }
}
