import 'dart:async';
import 'dart:math' as math;

import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/forum_background.dart';
import '../theme/app_theme.dart';
import 'forum_texture.dart';

Color _plainWindowColor(DTokens tokens) {
  // The mockup ground mixes the palette background with 14% black in both
  // brightness modes, independently of the sidebar fill.
  return Color.lerp(tokens.background, Colors.black, .14)!;
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
        ? _plainWindowColor(DTokens.of(context))
        : fallback;
  }

  /// Paint once at each panel boundary, without restarting the window effect.
  /// The slight foreground tint keeps flat backgrounds visibly framed too.
  static Color? panelColor(BuildContext context) {
    final canvas = context.dependOnInheritedWidgetOfExactType<_ForumCanvas>();
    if (canvas == null) return null;
    final tokens = DTokens.of(context);
    return Color.lerp(tokens.background, tokens.foreground, .03)!.withValues(
      // The current reference shares its panel treatment across materials.
      alpha: 1 - (canvas.transparency / .3 * 40).round() / 100,
    );
  }

  /// Footers stay opaque so their fixed actions remain distinct.
  static Color footerColor(BuildContext context, Color fallback) {
    final canvas = context.dependOnInheritedWidgetOfExactType<_ForumCanvas>();
    return canvas != null && canvas.continuous
        ? fallback.withValues(alpha: 1)
        : fallback;
  }

  @override
  State<ForumWindowBackground> createState() => _ForumWindowBackgroundState();
}

class _ForumWindowBackgroundState extends State<ForumWindowBackground>
    with SingleTickerProviderStateMixin {
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
    final animate =
        context.dependOnInheritedWidgetOfExactType<_ForumCanvas>() == null &&
        background?.effect == ForumBackgroundEffect.gradient &&
        background!.noiseIntensity > 0 &&
        !MediaQuery.disableAnimationsOf(context) &&
        TickerMode.valuesOf(context).enabled;
    if (animate && !_motion.isAnimating) {
      _motion.repeat();
    } else if (!animate) {
      _motion.stop();
    }
  }

  String? _nativeMaterial;
  void _syncNativeMaterial(bool glass) {
    if (Theme.of(context).platform != TargetPlatform.macOS) return;
    final material = glass ? 'liquidGlass' : 'standard';
    if (_nativeMaterial == material) return;
    _nativeMaterial = material;
    unawaited(_setNativeMaterial(material));
  }

  Future<void> _setNativeMaterial(String material) async {
    try {
      await const MethodChannel(
        'org.discourse.native/window',
      ).invokeMethod<void>('setMaterial', material);
    } on MissingPluginException {
      // Embedded/preview shells have no native window.
    } on PlatformException {
      // The readable Flutter material remains available without AppKit.
    }
  }

  @override
  void dispose() {
    _motion.dispose();
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
    final gradient = background?.effect == ForumBackgroundEffect.gradient;
    final tokens = DTokens.of(context);
    final glass = DMaterialTheme.glassOf(context);
    final panelMaterial = DMaterialTheme.of(context) != null;
    final transparency = DMaterialTheme.reducedOf(context)
        ? 0.0
        : background?.transparency ?? 0;
    _syncNativeMaterial(glass);
    return _ForumCanvas(
      continuous: background != null || panelMaterial,
      transparency: transparency,
      child: DecoratedBox(
        key: const ValueKey('forum-window-canvas'),
        decoration: BoxDecoration(
          color: _plainWindowColor(tokens).withValues(
            alpha: glass ? 1 - (transparency / .3 * 65).round() / 100 : 1,
          ),
          gradient: background == null ? effects?.windowGradient : null,
        ),
        child: Stack(
          fit: StackFit.passthrough,
          children: [
            if (panelMaterial && !DMaterialTheme.reducedOf(context))
              Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(
                    painter: _PalettePools(
                      tokens.primary,
                      theme.colorScheme.secondary,
                    ),
                  ),
                ),
              ),
            if (background?.effect == ForumBackgroundEffect.hatch)
              Positioned.fill(
                child: ForumTexture(
                  background: background!,
                  accent: tokens.foreground,
                ),
              ),
            if (gradient)
              Positioned.fill(
                child: IgnorePointer(
                  child: RepaintBoundary(
                    child: CustomPaint(
                      key: const ValueKey('forum-gradient-texture'),
                      painter: _GradientPainter(
                        tokens.primary,
                        background!.noiseIntensity,
                        _motion,
                      ),
                    ),
                  ),
                ),
              ),
            // Keep moving gradients behind text, icons and reading surfaces.
            // Blending above them modulates glyph edges every animation frame.
            KeyedSubtree(
              key: const ValueKey('forum-window-content'),
              child: widget.child,
            ),
            if (!gradient && background?.effect != ForumBackgroundEffect.hatch)
              Positioned.fill(
                child: ForumTexture(
                  background: background ?? const ForumBackground.appearance(),
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
    required super.child,
  });

  final bool continuous;
  final double transparency;

  @override
  bool updateShouldNotify(_ForumCanvas oldWidget) =>
      continuous != oldWidget.continuous ||
      transparency != oldWidget.transparency;
}

/// Four slowly orbiting glows around the accent hue, overlaid on the canvas.
class _GradientPainter extends CustomPainter {
  _GradientPainter(this.accent, this.intensity, this.motion)
    : super(repaint: motion);
  final Color accent;
  final double intensity;
  final Animation<double> motion;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    final phase = motion.value * math.pi * 2;
    final base = HSLColor.fromColor(accent);
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
          ..shader = RadialGradient(
            colors: [
              tint.withValues(alpha: intensity * .55),
              tint.withValues(alpha: 0),
            ],
          ).createShader(rect),
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_GradientPainter oldDelegate) =>
      oldDelegate.accent != accent ||
      oldDelegate.intensity != intensity ||
      oldDelegate.motion != motion;
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
      data: DMaterialTheme.apply(
        sidebar.copyWith(platform: theme.platform),
        DMaterialTheme.of(context)?.material ?? DAppearanceMaterial.standard,
      ),
      // Dark navigation needs its own opaque surface over a custom canvas.
      child: _ForumCanvas(
        continuous: DMaterialTheme.glassOf(context),
        child: child,
      ),
    );
  }
}

class _PalettePools extends CustomPainter {
  const _PalettePools(this.accent, this.secondary);
  final Color accent;
  final Color secondary;
  @override
  void paint(Canvas canvas, Size size) {
    for (final (x, y, radius, color, alpha) in [
      (.1, .06, .6, accent, .30),
      (.92, .94, .6, secondary, .24),
      (.8, .14, .4, accent, .16),
    ]) {
      final center = Offset(size.width * x, size.height * y);
      final rect = Rect.fromCircle(
        center: center,
        radius: size.longestSide * radius,
      );
      canvas.drawRect(
        Offset.zero & size,
        Paint()
          ..shader = RadialGradient(
            center: Alignment.center,
            colors: [
              color.withValues(alpha: alpha),
              color.withValues(alpha: 0),
            ],
            stops: const [0, .7],
          ).createShader(rect),
      );
    }
  }

  @override
  bool shouldRepaint(_PalettePools old) =>
      old.accent != accent || old.secondary != secondary;
}
