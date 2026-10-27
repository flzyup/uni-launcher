import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import '../model/appearance.dart';
import '../model/card_layout.dart';
import '../model/card_reorder.dart';
import '../platform/native_gateway.dart';

class LauncherController extends ChangeNotifier with WidgetsBindingObserver {
  final NativeGateway gateway;
  final native = ValueNotifier<Map<String, dynamic>>({});
  Appearance appearance = const Appearance();
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
    if (origin == null || origin.id != target.id || target.page >= pageCount)
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

  int page = 0, pageCount = 2;
  final pageChanged = ValueNotifier<int>(0);
  int _pageRequest = 0;
  bool settings = false, editing = false, ready = false;
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
  final _recentImages = _SnapshotImages(48, 12 * 1024 * 1024);
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
    // Every engine (launcher, dock and panel) initializes its own controller.
    if (_disposed) return;
    if (!_observingMemory) {
      final imageCache = PaintingBinding.instance.imageCache;
      imageCache.maximumSize = 128;
      imageCache.maximumSizeBytes = 24 * 1024 * 1024;
      WidgetsBinding.instance.addObserver(this);
      _observingMemory = true;
    }
    gateway.onHome(home);
    if (gateway is AndroidGateway)
      (gateway as AndroidGateway).onOpenSettings(openSettings);
    try {
      final state = await gateway.bootstrap();
      if (_disposed) return;
      final raw = state['savedDesign'];
      if (raw is String && raw.isNotEmpty) {
        try {
          final data = jsonDecode(raw) as Map<String, dynamic>;
          appearance = Appearance.fromJson(
              Map<String, dynamic>.from(data['preferences'] ?? {}));
          appNames = _decodeAppNames(state['appNames'] ?? data['appNames']);
          final parsed = (data['cards'] as List)
              .map((c) => LauncherCard.fromJson(Map<String, dynamic>.from(c)))
              .toList();
          if (validLayout(parsed)) {
            cards = parsed;
            // Empty trailing pages are editor scratch space, not persistent
            // desktops. Keeping them made an empty-page prompt animate over
            // the last real page after restart.
            pageCount =
                cards.fold<int>(1, (n, c) => max(n, c.page + 1)).clamp(1, 20);
          }
        } catch (_) {
          message = '旧布局无法读取，已恢复默认卡片';
        }
      }
      _receive(state);
      if (state['initialSettings'] == true) settings = true;
      _subscription = gateway.events.listen(_receive, onError: (Object e) {
        message = '原生连接暂不可用';
        notifyListeners();
      });
    } catch (_) {
      message = '等待 Android 接入';
    }
    if (_disposed) return;
    ready = true;
    notifyListeners();
  }

  void _receive(Map<String, dynamic> state) {
    // The settings catalog can contain hundreds of entries. Android sends it
    // on bootstrap/explicit refresh, rather than with every telemetry event.
    if (!state.containsKey('systemSettings') &&
        native.value.containsKey('systemSettings')) {
      state = {...state, 'systemSettings': native.value['systemSettings']};
    }
    if (_disposed) return;
    _icons.begin(native.value['apps'], const ['icon']);
    _recentImages
        .begin(native.value['recentTasks'], const ['icon', 'snapshot']);
    final apps = state['apps'];
    if (apps is List) {
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
    if (recentTasks is List) {
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
    _icons.finish();
    _recentImages.finish();
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
    final oldEmbed = (native.value['navigation'] as Map?)?['canEmbed'];
    final oldHeight = native.value['viewportHeightPx'];
    native.value = state;
    if (state['message'] is String && (state['message'] as String).isNotEmpty) {
      message = state['message'];
      notifyListeners();
    }
    if (overlayThemeChanged ||
        (appearance.mode == 'system' && oldDark != state['dark']) ||
        oldDemo != state['demo'] ||
        oldHeight != state['viewportHeightPx'] ||
        oldEmbed != (state['navigation'] as Map?)?['canEmbed'])
      notifyListeners();
  }

  Map<String, dynamic> _decodeImages(
      Map source, List<String> fields, _SnapshotImages cache) {
    final result = Map<String, dynamic>.from(source);
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
    } catch (_) {
      message = '操作暂不可用';
      notifyListeners();
    }
  }

  String serialize() => jsonEncode({
        'version': 6,
        'preferences': appearance.toJson(),
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

  void home() {
    if (isGlobalDock) {
      command('show-home');
      return;
    }
    if (editing) return;
    settings = false;
    _setPage(0);
    notifyListeners();
  }

  void openSettings() {
    if (isGlobalDock) {
      command('show-desktop-settings');
      return;
    }
    if (editing) return;
    settings = true;
    notifyListeners();
  }

  void back() {
    if (editing) {
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
    final target = value.clamp(0, pageCount - 1), request = ++_pageRequest;
    if (target == page) return;
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
    _backup = List.of(cards);
    _backupPages = pageCount;
    editing = true;
    settings = false;
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
    pageCount = 2;
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
