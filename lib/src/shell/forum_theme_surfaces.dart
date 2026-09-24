import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';

import '../models/forum_background.dart';
import '../theme/app_theme.dart';
import 'forum_texture.dart';

Color _plainWindowColor(ThemeData theme, DTokens tokens) {
  final scaffold = theme.scaffoldBackgroundColor;
  if (scaffold != tokens.background) return scaffold;
  // Some forums use their reading color for the header too. In that case the
  // workspace gutters need a separate fill to reveal the framed panels.
  return Color.lerp(
    tokens.background,
    Colors.black,
    theme.brightness == Brightness.dark ? .20 : .06,
  )!;
}

/// Paints one shared canvas behind the entire forum workspace.
class ForumWindowBackground extends StatefulWidget {
  const ForumWindowBackground({super.key, required this.child});

  final Widget child;

  /// A custom canvas sits behind translucent framed panels. Inner page chrome
  /// lets it show through; controls and overlays retain their opaque tokens.
  static bool isContinuous(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_ForumCanvas>()?.continuous ??
      false;

  static Color surfaceColor(BuildContext context, Color fallback) =>
      isContinuous(context) ? Colors.transparent : fallback;

  /// Window chrome shares the plain workspace canvas behind framed panels.
  /// Custom backgrounds still use [surfaceColor] to expose their effect.
  static Color chromeColor(BuildContext context, Color fallback) {
    final canvas = context.dependOnInheritedWidgetOfExactType<_ForumCanvas>();
    return canvas != null && !canvas.continuous
        ? _plainWindowColor(Theme.of(context), DTokens.of(context))
        : fallback;
  }

  /// Paint once at each panel boundary, without restarting the window effect.
  /// The slight foreground tint keeps flat backgrounds visibly framed too.
  static Color? panelColor(BuildContext context) {
    final canvas = context.dependOnInheritedWidgetOfExactType<_ForumCanvas>();
    if (canvas == null || !canvas.continuous) return null;
    final tokens = DTokens.of(context);
    return Color.lerp(
      tokens.background,
      tokens.foreground,
      canvas.reference ? .03 : .05,
    )!.withValues(
      alpha:
          1 -
          (canvas.reference
              ? (canvas.transparency * 100).round() / 100
              : canvas.transparency),
    );
  }

  /// Footers retain a stronger surface so their fixed actions remain distinct.
  static Color footerColor(BuildContext context, Color fallback) {
    final canvas = context.dependOnInheritedWidgetOfExactType<_ForumCanvas>();
    return canvas != null && canvas.continuous
        ? fallback.withValues(
            alpha: canvas.reference ? 1 : 1 - canvas.transparency * .25,
          )
        : fallback;
  }

  @override
  State<ForumWindowBackground> createState() => _ForumWindowBackgroundState();
}

class _ForumWindowBackgroundState extends State<ForumWindowBackground>
    with SingleTickerProviderStateMixin {
  _GrainTexture? _grain;
  late final _motion = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 24),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final background = Theme.of(
      context,
    ).extension<ForumThemeEffects>()?.background;
    final ownsCanvas =
        context.dependOnInheritedWidgetOfExactType<_ForumCanvas>() == null;
    if (ownsCanvas &&
        background?.useAccentTint != true &&
        background?.effect == ForumBackgroundEffect.noise &&
        background!.noiseIntensity > 0) {
      _grain ??= _GrainTexture();
    }
    final gradient = background?.effect == ForumBackgroundEffect.gradient;
    final animate =
        ownsCanvas &&
        (gradient ||
            (background?.useAccentTint != true &&
                background?.effect == ForumBackgroundEffect.lava)) &&
        (background!.useAccentTint
                ? background.noiseIntensity
                : background.strength) >
            0 &&
        !MediaQuery.disableAnimationsOf(context) &&
        TickerMode.valuesOf(context).enabled;
    if (animate && !_motion.isAnimating) {
      _motion.repeat();
    } else if (!animate) {
      _motion.stop();
    }
  }

  @override
  void dispose() {
    _motion.dispose();
    _grain?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Mobile and boundary shells can nest this owner. Never restart the effect
    // or its coordinate space at an inner page boundary.
    if (context.dependOnInheritedWidgetOfExactType<_ForumCanvas>() != null) {
      return widget.child;
    }
    final theme = Theme.of(context);
    final effects = theme.extension<ForumThemeEffects>();
    final background = effects?.background;
    final reference = background?.useAccentTint == true;
    final gradient =
        reference && background?.effect == ForumBackgroundEffect.gradient;
    final tokens = DTokens.of(context);
    final paintEffect = switch (background?.effect) {
      ForumBackgroundEffect.noise =>
        background!.strength > 0 || background.noiseIntensity > 0,
      ForumBackgroundEffect.lava ||
      ForumBackgroundEffect.gradient => background!.strength > 0,
      _ => false,
    };
    return _ForumCanvas(
      continuous: background != null,
      reference: reference,
      transparency: background?.transparency ?? 0,
      child: DecoratedBox(
        key: const ValueKey('forum-window-canvas'),
        decoration: BoxDecoration(
          color: reference
              ? Color.lerp(tokens.background, Colors.black, .14)!.withValues(
                  alpha: 1 - (background!.transparency / .3 * 38).round() / 100,
                )
              : background == null
              ? _plainWindowColor(theme, tokens)
              : theme.shell.content,
          gradient: background == null ? effects?.windowGradient : null,
        ),
        child: Stack(
          fit: StackFit.passthrough,
          children: [
            Positioned.fill(
              child: IgnorePointer(
                child: !reference && paintEffect
                    ? RepaintBoundary(
                        child: CustomPaint(
                          key: const ValueKey('forum-window-effect'),
                          painter: _BackgroundPainter(
                            background!,
                            _motion,
                            _grain?.shader,
                          ),
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
            ),
            if (gradient)
              Positioned.fill(
                child: IgnorePointer(
                  child: RepaintBoundary(
                    child: CustomPaint(
                      key: const ValueKey('forum-gradient-texture'),
                      painter: _BackgroundPainter(
                        background!.copyWith(
                          color: tokens.primary,
                          strength: background.noiseIntensity,
                        ),
                        _motion,
                        null,
                      ),
                    ),
                  ),
                ),
              ),
            // Keep moving gradients behind text, icons and reading surfaces.
            // Blending above them modulates glyph edges every animation frame.
            widget.child,
            if (!gradient)
              Positioned.fill(
                child: ForumTexture(
                  background: reference
                      ? background!
                      : const ForumBackground.appearance(),
                  accent: tokens.primary,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ForumCanvas extends InheritedWidget {
  const _ForumCanvas({
    required this.continuous,
    this.transparency = 0,
    this.reference = false,
    required super.child,
  });

  final bool continuous;
  final double transparency;
  final bool reference;

  @override
  bool updateShouldNotify(_ForumCanvas oldWidget) =>
      continuous != oldWidget.continuous ||
      reference != oldWidget.reference ||
      transparency != oldWidget.transparency;
}

class _BackgroundPainter extends CustomPainter {
  _BackgroundPainter(this.background, this.motion, this.grain)
    : super(repaint: motion);
  final ForumBackground background;
  final Animation<double> motion;
  final ui.ImageShader? grain;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    if (background.effect == ForumBackgroundEffect.noise) {
      _paintNoise(canvas, size);
    } else {
      final phase = motion.value * math.pi * 2;
      final base = HSLColor.fromColor(background.color);
      for (var i = 0; i < 4; i++) {
        final angle = phase + i * math.pi / 2;
        final center = Offset(
          size.width * (.5 + .4 * math.sin(angle)),
          size.height * (.5 + .4 * math.cos(angle + i)),
        );
        final radius = size.longestSide * (.38 + .06 * math.sin(angle));
        final tint = base.withHue((base.hue + i * 22) % 360).toColor();
        final rect = Rect.fromCircle(center: center, radius: radius);
        canvas.drawCircle(
          center,
          radius,
          Paint()
            ..blendMode = background.useAccentTint
                ? BlendMode.overlay
                : BlendMode.srcOver
            ..shader = RadialGradient(
              colors: [
                tint.withValues(alpha: background.strength * .55),
                tint.withValues(alpha: 0),
              ],
            ).createShader(rect),
        );
      }
    }
    canvas.restore();
  }

  void _paintNoise(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final base = HSLColor.fromColor(background.color);
    Color shade(double lightness) => base
        .withLightness(lightness.clamp(0, 1))
        .toColor()
        .withValues(alpha: background.strength * .75);
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            shade(base.lightness + .18),
            shade(base.lightness),
            shade(base.lightness - .22),
          ],
        ).createShader(rect),
    );

    if (background.noiseIntensity == 0 || grain == null) return;

    // Like https://css-tricks.com/grainy-gradients/: contrast-boosted fractal
    // noise, a gradient mask, and blending restricted to the background. Using
    // monochrome grain keeps the selected hue instead of adding RGB confetti.
    canvas.saveLayer(
      rect,
      Paint()
        ..blendMode = BlendMode.softLight
        ..color = Colors.white.withValues(
          alpha: background.noiseIntensity * .85,
        ),
    );
    canvas.drawRect(rect, Paint()..shader = grain);
    canvas.drawRect(
      rect,
      Paint()
        ..blendMode = BlendMode.dstIn
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0x60ffffff), Colors.white, Color(0xa0ffffff)],
        ).createShader(rect),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_BackgroundPainter oldDelegate) =>
      oldDelegate.background != background ||
      oldDelegate.motion != motion ||
      oldDelegate.grain != grain;
}

/// A fixed-size, seamless three-octave Perlin tile, created once per canvas.
/// The image shader repeats in logical pixels so resizing never redistributes
/// the grain or makes it sparser. Repaints only composite this cached texture.
class _GrainTexture {
  _GrainTexture() {
    const size = 256;
    final permutation = List<int>.generate(256, (i) => i)
      ..shuffle(math.Random(73));
    final points = List.generate(256, (_) => <double>[]);
    for (var y = 0; y < size; y++) {
      for (var x = 0; x < size; x++) {
        var noise = 0.0;
        var amplitude = 1.0;
        // 168 / 256 approximates the reference's .65 base frequency. Integer
        // periods make every octave wrap at the same tile boundary.
        for (var octave = 0; octave < 3; octave++) {
          final period = 168 << octave;
          noise +=
              _perlin(
                (x + .5) * period / size,
                (y + .5) * period / size,
                period,
                permutation,
              ) *
              amplitude;
          amplitude *= .5;
        }
        final value = ((.5 + noise * 1.7) * 255).round().clamp(0, 255);
        points[value].addAll([x + .5, y + .5]);
      }
    }
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final paint = Paint()
      ..isAntiAlias = false
      ..strokeWidth = 1;
    for (var value = 0; value < points.length; value++) {
      if (points[value].isEmpty) continue;
      paint.color = Color.fromARGB(255, value, value, value);
      canvas.drawRawPoints(
        ui.PointMode.points,
        Float32List.fromList(points[value]),
        paint,
      );
    }
    final picture = recorder.endRecording();
    _image = picture.toImageSync(size, size);
    picture.dispose();
    shader = ui.ImageShader(
      _image,
      TileMode.repeated,
      TileMode.repeated,
      Matrix4.identity().storage,
      filterQuality: FilterQuality.none,
    );
  }

  late final ui.Image _image;
  late final ui.ImageShader shader;

  void dispose() {
    shader.dispose();
    _image.dispose();
  }

  static double _perlin(double x, double y, int period, List<int> permutation) {
    final left = x.floor();
    final top = y.floor();
    final dx = x - left;
    final dy = y - top;
    double dot(int column, int row, double x, double y) {
      final hash =
          permutation[(permutation[(column % period) & 255] + row % period) &
              255];
      return switch (hash & 7) {
        0 => x,
        1 => -x,
        2 => y,
        3 => -y,
        4 => (x + y) * .707106781,
        5 => (x - y) * .707106781,
        6 => (-x + y) * .707106781,
        _ => (-x - y) * .707106781,
      };
    }

    double fade(double t) => t * t * t * (t * (t * 6 - 15) + 10);
    double mix(double a, double b, double t) => a + (b - a) * t;
    return mix(
      mix(dot(left, top, dx, dy), dot(left + 1, top, dx - 1, dy), fade(dx)),
      mix(
        dot(left, top + 1, dx, dy - 1),
        dot(left + 1, top + 1, dx - 1, dy - 1),
        fade(dx),
      ),
      fade(dy),
    );
  }
}

/// Applies navigation colors through the Native kit's existing theme boundary.
class ForumSidebarTheme extends StatelessWidget {
  const ForumSidebarTheme({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sidebar = theme.extension<ForumThemeEffects>()?.sidebarTheme;
    if (sidebar == null) return child;
    return Theme(
      data: sidebar.copyWith(platform: theme.platform),
      // Dark navigation needs its own opaque surface over a custom canvas.
      child: _ForumCanvas(continuous: false, child: child),
    );
  }
}
