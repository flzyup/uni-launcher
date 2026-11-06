import 'package:flutter_test/flutter_test.dart';
import 'package:uni_launcher/model/cluster_layout.dart';

/// The placement maths the preview and the native panel share.
///
/// These numbers are pinned on both sides: `ClusterPanelGeometryTest` in the Android source
/// set asserts the same values, so a change that only lands here fails the Java test and
/// vice versa. That is the only thing keeping "drag it where I want it" honest.
void main() {
  test('width clamps to the floor and the display itself', () {
    expect(ClusterLayout.widthRatio(0.01), ClusterLayout.minWidthRatio);
    expect(ClusterLayout.widthRatio(4), 1.0);
    expect(ClusterLayout.panelWidth(1920, 0.94), 1805);
    expect(ClusterLayout.panelWidth(1920, 0.5), 960);
    expect(ClusterLayout.panelWidth(1920, 99), 1920);
  });

  test('height grows with rows and font size', () {
    expect(ClusterLayout.panelHeight(80, 1), 130);
    expect(ClusterLayout.panelHeight(80, 3), 389);
    expect(ClusterLayout.rows(9), 3);
    expect(ClusterLayout.rows(0), 1);
  });

  test('the stored ratio is the block centre, not its corner', () {
    final origin = ClusterLayout.origin(
      displayWidth: 1920,
      displayHeight: 720,
      panelWidthPx: 960,
      panelHeightPx: 260,
      xRatio: 0.5,
      yRatio: 0.5,
    );
    expect(origin.x, 480); // 960 - 480
    expect(origin.y, 230); // 360 - 130
  });

  test('a panel cannot be pushed off the display', () {
    final left = ClusterLayout.origin(
      displayWidth: 1920,
      displayHeight: 720,
      panelWidthPx: 960,
      panelHeightPx: 260,
      xRatio: 0,
      yRatio: 0,
    );
    expect(left.x, 0);
    expect(left.y, 0);
    final right = ClusterLayout.origin(
      displayWidth: 1920,
      displayHeight: 720,
      panelWidthPx: 960,
      panelHeightPx: 260,
      xRatio: 1,
      yRatio: 1,
    );
    expect(right.x, 960);
    expect(right.y, 460);
  });

  test('a drag produces the ratio the origin helper will read back', () {
    final ratios = ClusterLayout.ratiosForCentre(
      centreX: 480,
      centreY: 360,
      displayWidth: 1920,
      displayHeight: 720,
    );
    expect(ratios.xRatio, closeTo(0.25, 1e-9));
    expect(ratios.yRatio, closeTo(0.5, 1e-9));
    final origin = ClusterLayout.origin(
      displayWidth: 1920,
      displayHeight: 720,
      panelWidthPx: 960,
      panelHeightPx: 260,
      xRatio: ratios.xRatio,
      yRatio: ratios.yRatio,
    );
    expect(origin.x, 0);
    expect(origin.y, 230);
  });

  test('preview block scales the real font by the real density', () {
    final small = ClusterLayout.previewBlock(
      previewWidth: 480,
      previewHeight: 180,
      displayWidth: 1920,
      displayHeight: 720,
      densityDpi: 240,
      fontSp: 24,
      rowsValue: 3,
      widthRatioValue: 0.94,
      xRatio: 0.5,
      yRatio: 0.62,
    );
    final large = ClusterLayout.previewBlock(
      previewWidth: 480,
      previewHeight: 180,
      displayWidth: 1920,
      displayHeight: 720,
      densityDpi: 240,
      fontSp: 48,
      rowsValue: 3,
      widthRatioValue: 0.94,
      xRatio: 0.5,
      yRatio: 0.62,
    );
    expect(large.height, closeTo(small.height * 2, 1e-6));
    expect(small.width, closeTo(480 * 0.94, 1e-6));
    // Centre follows the ratio: 0.62 of the mock height.
    expect(small.left + small.width / 2, closeTo(240, 0.5));
    expect(small.top + small.height / 2, closeTo(180 * 0.62, 0.5));
  });

  test('a NaN or out-of-range ratio falls back instead of corrupting the layout', () {
    expect(ClusterLayout.clampRatio(double.nan), ClusterLayout.defaultX);
    expect(ClusterLayout.clampRatio(-3), 0);
    expect(ClusterLayout.clampRatio(7), 1);
    expect(ClusterLayout.widthRatio(double.nan), ClusterLayout.defaultWidth);
  });
}
