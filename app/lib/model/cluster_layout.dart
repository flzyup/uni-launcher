import 'dart:math' as math;

/// Placement maths for the lyric panel that is painted on another display.
///
/// This is the Flutter twin of `ClusterPanelGeometry.java`. Both exist on purpose: the
/// native service turns the stored ratios into window pixels, and the preview in settings
/// turns the same ratios into a block on a mock screen. If the two ever computed placement
/// differently, the user would drop the lyrics on the cluster's left edge and see them
/// appear somewhere else — so any change here has to be made there too, and the unit tests
/// on both sides pin the same numbers.
class ClusterLayout {
  const ClusterLayout._();

  /// Narrower than a fifth of the display is not a lyric panel any more.
  static const double minWidthRatio = 0.2;
  static const double maxWidthRatio = 1.0;

  /// Row pitch in multiples of the text size. Same constant as the native view.
  static const double rowSpacing = 1.62;

  static const int minRows = 1;
  static const int maxRows = 3;

  static const double defaultX = 0.5;
  static const double defaultY = 0.62;
  static const double defaultWidth = 0.94;
  static const int defaultRowsCount = 3;

  /// Text size range in sp. Below 18 the panel stops being readable at arm's length in a car;
  /// above 72 a three-row panel no longer fits a 720p cluster.
  static const double minFontSp = 18;
  static const double maxFontSp = 72;
  static const double defaultFontSp = 34;

  /// Effects mode names, shared with `ClusterPanelGeometry` on the native side.
  ///
  /// [motionNone] is the default on purpose: the cast window sits on a head unit that is already
  /// driving a map, so with effects off it repaints when the line changes instead of 25 times a
  /// second. [motionWords] turns on the karaoke sweep *and* the slide-plus-fade between lines.
  static const String motionNone = 'none';
  static const String motionWords = 'words';
  static const String defaultMotion = motionNone;

  static double fontSp(double value) {
    if (value.isNaN) return defaultFontSp;
    return value.clamp(minFontSp, maxFontSp).toDouble();
  }

  /// Normalises a stored motion name; anything unrecognised is the cheap default.
  static String motion(String? value) => value == motionWords ? motionWords : motionNone;

  static bool motionEnabled(String? value) => motion(value) == motionWords;

  static String motionLabel(String? value) =>
      motionEnabled(value) ? '逐次+动效' : '无';

  static double clampRatio(double value) {
    if (value.isNaN) return defaultX;
    return value.clamp(0.0, 1.0).toDouble();
  }

  static double widthRatio(double value) {
    if (value.isNaN) return defaultWidth;
    return value.clamp(minWidthRatio, maxWidthRatio).toDouble();
  }

  static int rows(int value) => value.clamp(minRows, maxRows).toInt();

  /// Panel width in display pixels.
  static int panelWidth(int displayWidth, double widthRatioValue) {
    final available = math.max(1, displayWidth);
    final width = (available * ClusterLayout.widthRatio(widthRatioValue)).round();
    return width.clamp(1, available).toInt();
  }

  /// Panel height in display pixels: [rows] rows of [rowSpacing] × [fontPx].
  static int panelHeight(double fontPx, int rowsValue) {
    final size = math.max(8.0, fontPx);
    return math.max(1, (size * rowSpacing * rows(rowsValue)).round());
  }

  /// Top-left corner of the panel, clamped inside the display.
  ///
  /// [xRatio] and [yRatio] are the **centre** of the panel as a fraction of the display,
  /// which is what the drag produces: the block follows the finger, not its top-left corner.
  static ({int x, int y}) origin({
    required int displayWidth,
    required int displayHeight,
    required int panelWidthPx,
    required int panelHeightPx,
    required double xRatio,
    required double yRatio,
  }) {
    final screenW = math.max(1, displayWidth);
    final screenH = math.max(1, displayHeight);
    final w = panelWidthPx.clamp(1, screenW).toInt();
    final h = panelHeightPx.clamp(1, screenH).toInt();
    final centreX = (screenW * clampRatio(xRatio)).round();
    final centreY = (screenH * clampRatio(yRatio)).round();
    final x = (centreX - w ~/ 2).clamp(0, screenW - w).toInt();
    final y = (centreY - h ~/ 2).clamp(0, screenH - h).toInt();
    return (x: x, y: y);
  }

  /// Ratios for a dragged centre, in the same space as [origin].
  ///
  /// A drag cannot push the panel past the display edge, and the ratios it returns are the
  /// ones to persist: they survive a resolution change, a different cluster revision, and a
  /// reboot, whereas pixels do not.
  static ({double xRatio, double yRatio}) ratiosForCentre({
    required double centreX,
    required double centreY,
    required int displayWidth,
    required int displayHeight,
  }) {
    final screenW = math.max(1, displayWidth);
    final screenH = math.max(1, displayHeight);
    return (
      xRatio: clampRatio(centreX / screenW),
      yRatio: clampRatio(centreY / screenH),
    );
  }

  /// Where the preview should draw the block, in the preview's own pixel space.
  ///
  /// [fontSp] and the selected display's density decide the block height, so a bigger font
  /// genuinely looks bigger in the preview instead of only on the cluster.
  static ({double left, double top, double width, double height}) previewBlock({
    required double previewWidth,
    required double previewHeight,
    required int displayWidth,
    required int displayHeight,
    required int densityDpi,
    required double fontSp,
    required int rowsValue,
    required double widthRatioValue,
    required double xRatio,
    required double yRatio,
  }) {
    final scale = displayWidth <= 0 ? 1.0 : previewWidth / displayWidth;
    final density = densityDpi <= 0 ? 2.0 : densityDpi / 160.0;
    final fontPx = math.max(8.0, fontSp * density) * scale;
    final width = math.max(1.0, previewWidth * widthRatio(widthRatioValue));
    final height = math.max(1.0, fontPx * rowSpacing * rows(rowsValue));
    final centreX = previewWidth * clampRatio(xRatio);
    final centreY = previewHeight * clampRatio(yRatio);
    final left = (centreX - width / 2).clamp(0.0, math.max(0.0, previewWidth - width));
    final top = (centreY - height / 2).clamp(0.0, math.max(0.0, previewHeight - height));
    return (left: left.toDouble(), top: top.toDouble(), width: width, height: height);
  }
}
