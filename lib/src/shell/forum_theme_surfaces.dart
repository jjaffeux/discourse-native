import 'dart:math' as math;

import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';

import '../models/forum_background.dart';
import '../theme/app_theme.dart';
import 'decorative_cadence.dart';
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
      isContinuous(context) || hasMobileSurface(context)
      ? Colors.transparent
      : fallback;

  static bool hasMobileSurface(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_MobileSurfaceScope>() != null;

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
    return tokens.panelBackground.withValues(
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

class _ForumWindowBackgroundState extends State<ForumWindowBackground> {
  final _motion = DecorativeCadence();

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
    _motion.setActive(animate);
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
    final panelMaterial = DMaterialTheme.of(context) != null;
    final transparency = DMaterialTheme.reducedOf(context)
        ? 0.0
        : background?.transparency ?? 0;
    return _ForumCanvas(
      continuous: background != null || panelMaterial,
      transparency: transparency,
      child: DecoratedBox(
        key: const ValueKey('forum-window-canvas'),
        decoration: BoxDecoration(
          // Every host window is opaque, so nothing sits behind this canvas.
          color: _plainWindowColor(tokens),
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
                child: RepaintBoundary(
                  child: ForumTexture(
                    background:
                        background ?? const ForumBackground.appearance(),
                    accent: tokens.primary,
                  ),
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
  final DecorativeCadence motion;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    final phase =
        (motion.sampleElapsed().inMicroseconds % 24000000) /
        24000000 *
        math.pi *
        2;
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
      // Past its last stop a pool is transparent. Filling only the circle
      // inside that stop draws the same pixels; covering the window instead
      // blended each pool across the whole multisampled frame.
      canvas.drawCircle(
        center,
        rect.width / 2 * .7,
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

/// Phone pages paint the mockup's panel below the floating window chrome.
/// Pages keep 22px top corners and match the dock below; the inset sidebar
/// uses the Native panel radius.
class ForumMobileSurface extends StatefulWidget {
  const ForumMobileSurface({
    super.key,
    required this.child,
    this.coveredBySheet = false,
  }) : _sidebar = false;

  /// The mockup's mobile SideNav is a rounded sheet on the window ground.
  const ForumMobileSurface.sidebar({super.key, required this.child})
    : _sidebar = true,
      coveredBySheet = false;

  final bool _sidebar;
  final bool coveredBySheet;
  final Widget child;
  @override
  State<ForumMobileSurface> createState() => _ForumMobileSurfaceState();
}

class _ForumMobileSurfaceState extends State<ForumMobileSurface> {
  final _content = GlobalKey();
  @override
  Widget build(BuildContext context) => DPageSurface(
    // The reference's [data-glass] [data-panel] rule overrides the inline
    // background:none on phone roots. They still own a fill and inset rim.
    framed: true,
    border: false,
    borderRadius: widget._sidebar
        ? BorderRadius.circular(DRadius.panel)
        : DMobilePageGeometry.borderRadiusOf(context),
    backgroundColor: widget.coveredBySheet
        ? Colors.transparent
        : ForumWindowBackground.panelColor(context),
    child: _MobileSurfaceScope(key: _content, child: widget.child),
  );
}

class _MobileSurfaceScope extends InheritedWidget {
  const _MobileSurfaceScope({super.key, required super.child});
  @override
  bool updateShouldNotify(_MobileSurfaceScope oldWidget) => false;
}
