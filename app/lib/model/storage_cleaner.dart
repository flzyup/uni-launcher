/// 垃圾清理的数据模型：只解析原生下发的快照，所有判定（哪些能清、能不能默认勾）
/// 都在 `StorageCleaner` + `CleanerRules` 里完成，界面不做第二套逻辑。
library;

/// 一个清理类目。`available == false` 表示权限或系统接口缺失，界面显示原因、不给勾。
class CleanerCategory {
  final String id, name, group, risk, note;
  final int bytes, count;
  final bool defaultSelected, verified, available;

  const CleanerCategory({
    required this.id,
    required this.name,
    this.group = 'junk',
    this.risk = 'safe',
    this.note = '',
    this.bytes = 0,
    this.count = 0,
    this.defaultSelected = false,
    this.verified = false,
    this.available = true,
  });

  static CleanerCategory? from(Object? raw) {
    if (raw is! Map) return null;
    final id = '${raw['id'] ?? ''}'.trim();
    if (id.isEmpty) return null;
    return CleanerCategory(
      id: id,
      name: '${raw['name'] ?? id}',
      group: '${raw['group'] ?? 'junk'}',
      risk: '${raw['risk'] ?? 'safe'}',
      note: '${raw['note'] ?? ''}',
      bytes: (raw['bytes'] as num?)?.toInt() ?? 0,
      count: (raw['count'] as num?)?.toInt() ?? 0,
      defaultSelected: raw['default'] == true,
      verified: raw['verified'] == true,
      available: raw['available'] != false,
    );
  }

  /// 只有 safe / low 才用常规色；review 类要显式提醒。
  bool get needsReview => risk == 'review' || risk == 'high';
}

/// 面板分组：按这个顺序渲染，未知分组并入「系统垃圾」。
const cleanerGroupOrder = ['cache', 'junk', 'leftover', 'large'];
const cleanerGroupLabels = {
  'cache': '缓存',
  'junk': '系统垃圾',
  'leftover': '残留与安装包',
  'large': '大文件',
};

/// 一次扫描/清理的完整状态。
class CleanerState {
  final bool running;
  final String phase, current, error, rulesIssue;
  final double progress;
  final int freeBytes, totalBytes, lastCleanBytes, lastCleanAt, rev;
  final bool storageGranted;
  final List<CleanerCategory> categories;
  /// 清理时按文件推进的进度；应用缓存类目没有文件粒度，`purgeTotal` 会是 0。
  final int purgeFiles, purgeTotal;
  /// 上次扫描覆盖的条目数与耗时。
  final int scanned, scanMs;

  const CleanerState({
    this.running = false,
    this.phase = 'idle',
    this.current = '',
    this.error = '',
    this.rulesIssue = '',
    this.progress = 0,
    this.freeBytes = 0,
    this.totalBytes = 0,
    this.lastCleanBytes = 0,
    this.lastCleanAt = 0,
    this.rev = 0,
    this.storageGranted = true,
    this.categories = const [],
    this.purgeFiles = 0,
    this.purgeTotal = 0,
    this.scanned = 0,
    this.scanMs = 0,
  });

  static const empty = CleanerState();

  factory CleanerState.fromNative(Map<String, dynamic> native) {
    final raw = native['cleaner'];
    if (raw is! Map) return empty;
    final list = <CleanerCategory>[];
    for (final item in raw['categories'] is List ? raw['categories'] as List : const []) {
      final category = CleanerCategory.from(item);
      if (category != null) list.add(category);
    }
    final last = raw['lastClean'] is Map ? raw['lastClean'] as Map : const {};
    return CleanerState(
      running: raw['running'] == true,
      phase: '${raw['phase'] ?? 'idle'}',
      current: '${raw['current'] ?? ''}',
      error: '${raw['error'] ?? ''}',
      rulesIssue: '${raw['rulesIssue'] ?? ''}',
      progress: (raw['progress'] as num?)?.toDouble().clamp(0, 1) ?? 0,
      freeBytes: (raw['free'] as num?)?.toInt() ?? 0,
      totalBytes: (raw['total'] as num?)?.toInt() ?? 0,
      lastCleanBytes: (last['bytes'] as num?)?.toInt() ?? 0,
      lastCleanAt: (last['at'] as num?)?.toInt() ?? 0,
      rev: (raw['rev'] as num?)?.toInt() ?? 0,
      storageGranted: raw['storageGranted'] != false,
      categories: list,
      purgeFiles: (raw['purgeFiles'] as num?)?.toInt() ?? 0,
      purgeTotal: (raw['purgeTotal'] as num?)?.toInt() ?? 0,
      scanned: (raw['scanned'] as num?)?.toInt() ?? 0,
      scanMs: (raw['scanMs'] as num?)?.toInt() ?? 0,
    );
  }

  bool get scanning => running && phase == 'scan';
  bool get cleaning => running && phase == 'clean';

  /// 可清总量：只统计可用类目，避免把「不可用」的 0 值也算成干净。
  int get cleanableBytes => categories
      .where((c) => c.available && c.bytes > 0)
      .fold(0, (sum, c) => sum + c.bytes);

  int get usedBytes => totalBytes - freeBytes;

  String get phaseLabel => switch (phase) {
        'scan' => '扫描中',
        'clean' => '清理中',
        'refresh' => '重新统计',
        _ => '',
      };

  /// 清理中的文件级进度；规则类目能数到文件，只清应用缓存时退化成类目百分比。
  String get purgeLabel {
    if (!cleaning) return '';
    if (purgeTotal <= 0) return '正在清理缓存…';
    // 应用缓存走系统接口、没有文件粒度，顺手把 current（「应用缓存 12/33」）接在数字后面。
    // 否则清 124 个系统应用那几分钟里数字一动不动，看着就是卡死。
    return current.isEmpty
        ? '正在清理 $purgeFiles / $purgeTotal 个文件'
        : '正在清理 $purgeFiles / $purgeTotal 个文件 · $current';
  }

  /// 扫完才有意义：交代这次到底看了多少条目、花了多久。
  String get scanLabel {
    if (running || scanned <= 0) return '';
    final seconds = scanMs / 1000;
    final took = seconds < 10
        ? '${seconds.toStringAsFixed(1)} 秒'
        : '${seconds.round()} 秒';
    return '扫描 $scanned 项 · $took';
  }
}

/// 车机上只报人看得懂的量级，B/KB 保留整数，大单位保留一位。
String formatBytes(int bytes) {
  if (bytes <= 0) return '0 B';
  if (bytes >= 1 << 30) return '${(bytes / (1 << 30)).toStringAsFixed(1)} GB';
  if (bytes >= 1 << 20) return '${(bytes / (1 << 20)).toStringAsFixed(1)} MB';
  if (bytes >= 1 << 10) return '${(bytes / (1 << 10)).toStringAsFixed(0)} KB';
  return '$bytes B';
}

/// 「上次清理」的时间标签；没有记录时返回空串，界面就不显示那一行。
String lastCleanLabel(int at) {
  if (at <= 0) return '';
  final time = DateTime.fromMillisecondsSinceEpoch(at);
  final now = DateTime.now();
  final sameDay = time.year == now.year && time.month == now.month && time.day == now.day;
  String two(int n) => n.toString().padLeft(2, '0');
  final clock = '${two(time.hour)}:${two(time.minute)}';
  return sameDay ? '今天 $clock' : '${two(time.month)}-${two(time.day)} $clock';
}
