import 'dart:math' as math;
import 'dart:ui';

/// What WCAG asks of text, 4.5 to 1, and of body text where a palette
/// reaches it, 7 to 1.
const textContrast = 4.5;
const bodyContrast = 7.0;

/// Aimed a little past each need, so rounding a derived colour to whole
/// 8-bit steps cannot take it back under.
const contrastMargin = .05;

double contrastRatio(Color a, Color b) {
  final x = a.computeLuminance();
  final y = b.computeLuminance();
  return (math.max(x, y) + .05) / (math.min(x, y) + .05);
}

/// [share] of [color] mixed into [base].
Color mixInto(Color base, Color color, double share) =>
    Color.lerp(base, color, share)!;

/// The least share of [ink] mixed into [base], from [from] up, that stands
/// out from every one of [on] by [need]; all of it when even that falls
/// short.
double shareFor(
  Color ink,
  Color base,
  Iterable<Color> on,
  double need,
  double from,
) {
  bool passes(double share) {
    final mixed = mixInto(base, ink, share);
    return on.every((under) => contrastRatio(mixed, under) >= need);
  }

  if (passes(from)) return from;
  if (!passes(1)) return 1;
  var (low, high) = (from, 1.0);
  for (var i = 0; i < 20; i++) {
    final middle = (low + high) / 2;
    if (passes(middle)) {
      high = middle;
    } else {
      low = middle;
    }
  }
  return high;
}

/// [color] moved toward black or white, whichever leaves it standing out
/// from [against] the more, only as far as it takes to read on it.
Color standOut(Color color, Color against) {
  if (contrastRatio(color, against) >= textContrast) return color;
  const black = Color(0xff000000);
  const white = Color(0xffffffff);
  final pole = contrastRatio(black, against) > contrastRatio(white, against)
      ? black
      : white;
  final share = shareFor(
    pole,
    color,
    [against],
    textContrast + contrastMargin,
    0,
  );
  return _byte(mixInto(color, pole, share));
}

/// The ground and text of a palette's other half, for one published only as
/// light or only as dark. They keep the palette's own hue at the far ends of
/// lightness: its ground's, or its text's where the ground is all but grey.
({Color ground, Color text}) counterpartBase({
  required Color background,
  required Color text,
  required Brightness target,
}) {
  final ground = _Oklch.of(background);
  final ink = _Oklch.of(text);
  final hued = ground.c >= .02 ? ground : ink;
  final dark = target == Brightness.dark;
  return (
    ground: _Oklch(
      dark ? .24 : .975,
      math.min(hued.c, dark ? .03 : .02),
      hued.h,
    ).shown,
    text: _Oklch(
      dark ? .93 : .27,
      math.min(hued.c, dark ? .02 : .04),
      hued.h,
    ).shown,
  );
}

/// [color] with its hue and strength kept, moved in lightness only as far as
/// it takes to read on [ground] in the [target] mode.
Color readableIn(Color color, Color ground, Brightness target) {
  final dark = target == Brightness.dark;
  final source = _Oklch.of(color);
  for (var step = 0.0; step <= 1; step += .005) {
    final lightness = dark
        ? math.min(1.0, source.l + step)
        : math.max(0.0, source.l - step);
    final shown = _Oklch(lightness, source.c, source.h).shown;
    if (contrastRatio(shown, ground) >= textContrast + contrastMargin) {
      return shown;
    }
  }
  return _Oklch(dark ? 1 : 0, 0, source.h).shown;
}

Color _byte(Color color) => Color.fromARGB(
  255,
  (color.r * 255).round(),
  (color.g * 255).round(),
  (color.b * 255).round(),
);

double _linear(double v) =>
    v <= .04045 ? v / 12.92 : math.pow((v + .055) / 1.055, 2.4).toDouble();

double _gamma(double v) =>
    v <= .0031308 ? v * 12.92 : 1.055 * math.pow(v, 1 / 2.4) - .055;

double _cbrt(double v) =>
    v < 0 ? -math.pow(-v, 1 / 3).toDouble() : math.pow(v, 1 / 3).toDouble();

final class _Oklch {
  const _Oklch(this.l, this.c, this.h);

  factory _Oklch.of(Color color) {
    final r = _linear(color.r);
    final g = _linear(color.g);
    final b = _linear(color.b);
    final l = _cbrt(.4122214708 * r + .5363325363 * g + .0514459929 * b);
    final m = _cbrt(.2119034982 * r + .6806995451 * g + .1073969566 * b);
    final s = _cbrt(.0883024619 * r + .2817188376 * g + .6299787005 * b);
    final a = 1.9779984951 * l - 2.428592205 * m + .4505937099 * s;
    final bb = .0259040371 * l + .7827717662 * m - .808675766 * s;
    return _Oklch(
      .2104542553 * l + .793617785 * m - .0040720468 * s,
      math.sqrt(a * a + bb * bb),
      math.atan2(bb, a),
    );
  }

  final double l;
  final double c;
  final double h;

  /// As near this colour as a screen shows: as strong as it can be at this
  /// lightness and hue.
  Color get shown {
    for (var chroma = c; chroma > 0; chroma -= .002) {
      final color = _Oklch(l, chroma, h)._inGamut;
      if (color != null) return color;
    }
    return _Oklch(l, 0, h)._inGamut!;
  }

  Color? get _inGamut {
    final a = c * math.cos(h);
    final b = c * math.sin(h);
    final l3 = math.pow(l + .3963377774 * a + .2158037573 * b, 3);
    final m3 = math.pow(l - .1055613458 * a - .0638541728 * b, 3);
    final s3 = math.pow(l - .0894841775 * a - 1.291485548 * b, 3);
    final rgb = [
      4.0767416621 * l3 - 3.3077115913 * m3 + .2309699292 * s3,
      -1.2684380046 * l3 + 2.6097574011 * m3 - .3413193965 * s3,
      -.0041960863 * l3 - .7034186147 * m3 + 1.707614701 * s3,
    ];
    if (rgb.any((v) => v < -.0005 || v > 1.0005)) return null;
    int channel(double v) => (_gamma(v.clamp(0, 1)) * 255).round();
    return Color.fromARGB(
      255,
      channel(rgb[0]),
      channel(rgb[1]),
      channel(rgb[2]),
    );
  }
}
