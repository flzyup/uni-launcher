/// The reviewed artwork is 1920 px wide; the launcher lays out at 1600 units.
/// Keep every design measurement explicit instead of inheriting Material defaults.
abstract final class Design {
  static const canvasWidth = 1600.0;
  static const artworkWidth = 1920.0;
  static double px(num value) => value * canvasWidth / artworkWidth;

  /// The Nocturne design board (`design/desktop-lynk05.html`) is authored on a
  /// 1600×900 canvas — exactly the launcher canvas on a 1920×1080 unit, so its
  /// measurements are used 1:1 ([dz] = "design zone", no conversion). Classic
  /// and blue-glass keep the 1920-artwork [px] convention.
  static double dz(num value) => value.toDouble();
}
