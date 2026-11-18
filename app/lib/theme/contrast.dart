import 'package:flutter/material.dart';

/// Contrast is measured after compositing translucent paint on its actual base.
double contrastRatio(Color foreground, Color background) {
  final bg = background.withValues(alpha: 1);
  final fg = Color.alphaBlend(foreground, bg);
  final a = fg.computeLuminance(), b = bg.computeLuminance();
  return a > b ? (a + .05) / (b + .05) : (b + .05) / (a + .05);
}

/// Keep the chosen hue as far as possible; only move towards ink/paper when
/// needed. Runs when building the theme, never samples the screen per frame.
Color readableColor(Color color, Iterable<Color> backgrounds,
    {double minimum = 4.5}) {
  final bases = backgrounds.toList(growable: false);
  double score(Color c) =>
      bases.map((b) => contrastRatio(c, b)).reduce((a, b) => a < b ? a : b);
  final opaque = color.withValues(alpha: 1);
  if (score(opaque) >= minimum) return opaque;
  final end =
      score(Colors.black) > score(Colors.white) ? Colors.black : Colors.white;
  var lo = 0.0, hi = 1.0;
  for (var i = 0; i < 16; i++) {
    final mid = (lo + hi) / 2;
    if (score(Color.lerp(opaque, end, mid)!) >= minimum) {
      hi = mid;
    } else {
      lo = mid;
    }
  }
  return Color.lerp(opaque, end, hi)!;
}

Color foregroundOn(Color background) =>
    contrastRatio(const Color(0xFF07111F), background) >=
            contrastRatio(Colors.white, background)
        ? const Color(0xFF07111F)
        : Colors.white;
