import 'dart:ui' as ui;

/// Regular material adjusts the sampled background's dynamic range instead of
/// replacing it with opaque white/black paint. This is a GPU color filter on
/// the existing blur pass, with no screenshots, sampling timers or readback.
class LiquidBackdrop {
  final double saturation, gain, lift;
  const LiquidBackdrop._(this.saturation, this.gain, this.lift);
  static const light = LiquidBackdrop._(1.75, .40, .53);
  static const dark = LiquidBackdrop._(1.45, .25, .015);
  static LiquidBackdrop of(bool darkMode) => darkMode ? dark : light;

  List<double> get matrix {
    const weights = [.2126, .7152, .0722];
    return [
      for (var row = 0; row < 3; row++) ...[
        for (var column = 0; column < 3; column++)
          gain *
              ((row == column ? saturation : 0) +
                  (1 - saturation) * weights[column]),
        0,
        lift * 255,
      ],
      0,
      0,
      0,
      1,
      0,
    ];
  }

  ui.ColorFilter get filter => ui.ColorFilter.matrix(matrix);

  /// Same transfer function for contrast validation at theme construction.
  ui.Color apply(ui.Color color) {
    final luminance = color.r * .2126 + color.g * .7152 + color.b * .0722;
    double channel(double value) =>
        (lift + gain * (luminance + (value - luminance) * saturation))
            .clamp(0.0, 1.0);
    return ui.Color.from(
        alpha: color.a,
        red: channel(color.r),
        green: channel(color.g),
        blue: channel(color.b));
  }
}
