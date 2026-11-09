import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';

/// A colour in Oklab, for the steps CSS takes along a colour's lightness in
/// Oklch: changing [lightness] alone keeps its chroma and hue, which mixing
/// towards black or white does not.
@immutable
class Oklab {
  const Oklab(this.lightness, this.a, this.b);

  factory Oklab.of(Color color) {
    double linear(double v) =>
        v <= .04045 ? v / 12.92 : math.pow((v + .055) / 1.055, 2.4).toDouble();
    double root(double v) => v.sign * math.pow(v.abs(), 1 / 3).toDouble();
    final r = linear(color.r), g = linear(color.g), b = linear(color.b);
    final l = root(.4122214708 * r + .5363325363 * g + .0514459929 * b);
    final m = root(.2119034982 * r + .6806995451 * g + .1073969566 * b);
    final s = root(.0883024619 * r + .2817188376 * g + .6299787005 * b);
    return Oklab(
      .2104542553 * l + .793617785 * m - .0040720468 * s,
      1.9779984951 * l - 2.428592205 * m + .4505937099 * s,
      .0259040371 * l + .7827717662 * m - .808675766 * s,
    );
  }

  final double lightness;
  final double a;
  final double b;

  Oklab withLightness(double lightness) => Oklab(lightness, a, b);

  /// The nearest sRGB colour; channels outside the gamut are clipped.
  Color toColor({double alpha = 1}) {
    double cube(double v) => v * v * v;
    double gamma(double v) =>
        (v <= .0031308 ? 12.92 * v : 1.055 * math.pow(v, 1 / 2.4) - .055)
            .clamp(0.0, 1.0)
            .toDouble();
    final l = cube(lightness + .3963377774 * a + .2158037573 * b);
    final m = cube(lightness - .1055613458 * a - .0638541728 * b);
    final s = cube(lightness - .0894841775 * a - 1.291485548 * b);
    return Color.from(
      alpha: alpha,
      red: gamma(4.0767416621 * l - 3.3077115913 * m + .2309699292 * s),
      green: gamma(-1.2684380046 * l + 2.6097574011 * m - .3413193965 * s),
      blue: gamma(-.0041960863 * l - .7034186147 * m + 1.707614701 * s),
    );
  }
}
