import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:liquid_glass_easy/liquid_glass_easy.dart';

import 'material_theme.dart';

/// Internal painting roles. This adds no targets, padding or gesture listeners.
enum DSurfaceDepth { raised, recessed, panel, menu, card, swatch }

/// The kit owns depth for both materials. Text and focus rings paint above it.
/// Large reading panels use thin fills, not an expensive full-panel lens.
class DMaterialSurface extends StatelessWidget {
  const DMaterialSurface({
    super.key,
    required this.child,
    required this.color,
    required this.radius,
    this.depth = DSurfaceDepth.raised,
    this.accented = false,
  });
  final Widget child;
  final Color color;
  final BorderRadius radius;
  final DSurfaceDepth depth;
  final bool accented;

  static bool active(BuildContext context) =>
      DMaterialTheme.of(context) != null;
  static Color fill(BuildContext context, Color color) =>
      active(context) ? Colors.transparent : color;

  @override
  Widget build(BuildContext context) {
    if (!active(context)) return child;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final glass = DMaterialTheme.glassOf(context);
    final recessed = depth == DSurfaceDepth.recessed;
    final menu = depth == DSurfaceDepth.menu;
    final panel = depth == DSurfaceDepth.panel;
    final solid = depth == DSurfaceDepth.swatch || depth == DSurfaceDepth.card;
    final lens = glass && color.a > 0 && !panel && !recessed && !solid;
    final alpha = accented
        ? 1.0
        : menu
        ? .88
        : dark
        ? .66
        : .72;
    final paintedColor = glass && !solid && !panel
        ? color.withValues(alpha: color.a * (recessed ? .42 : alpha))
        : color;
    final light = Colors.white.withValues(alpha: dark ? .08 : .8);
    Widget background;
    if (lens) {
      background = _GlassPaint(
        color: paintedColor,
        radius: radius,
        blur: menu ? 26 : 5,
        child: const SizedBox.expand(),
      );
    } else {
      background = DecoratedBox(
        decoration: BoxDecoration(color: paintedColor, borderRadius: radius),
        child: const SizedBox.expand(),
      );
    }
    background = CustomPaint(
      foregroundPainter: color.a == 0
          ? null
          : _DepthEdge(radius, light, dark, recessed, glass && !solid),
      child: background,
    );
    final surface = DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: recessed || color.a == 0
            ? const []
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: dark ? .24 : .09),
                  offset: Offset(
                    0,
                    menu
                        ? 18
                        : panel
                        ? 12
                        : 1,
                  ),
                  blurRadius: menu
                      ? 44
                      : panel
                      ? 40
                      : 3,
                ),
              ],
      ),
      child: Stack(
        fit: StackFit.passthrough,
        children: [
          Positioned.fill(
            child: IgnorePointer(child: ExcludeSemantics(child: background)),
          ),
          child,
        ],
      ),
    );
    // Popovers may overlap their parent controls; they must sample the live
    // painted stack instead of a card's earlier shared backdrop.
    return menu ? LiquidGlassBatch.exclude(child: surface) : surface;
  }
}

/// One shared read for the side-by-side controls inside a Native surface.
/// Nesting cards creates a new batch after each solid card has been painted.
class DMaterialBatch extends StatelessWidget {
  const DMaterialBatch({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => LiquidGlassBatch(
    enabled:
        DMaterialTheme.glassOf(context) &&
        ui.ImageFilter.isShaderFilterSupported,
    child: child,
  );
}

class _GlassPaint extends StatefulWidget {
  const _GlassPaint({
    required this.color,
    required this.radius,
    required this.blur,
    required this.child,
  });
  final Color color;
  final BorderRadius radius;
  final double blur;
  final Widget child;
  @override
  State<_GlassPaint> createState() => _GlassPaintState();
}

class _GlassPaintState extends State<_GlassPaint> {
  static Future<bool>? _programs;
  bool ready = false;
  static Future<bool> _load() async {
    try {
      await LiquidGlassShaders.ensureLoaded();
      return true;
    } catch (_) {
      // Unsupported engines keep a readable frost instead of failing startup.
      return false;
    }
  }

  @override
  void initState() {
    super.initState();
    unawaited(
      (_programs ??= _load()).then((value) {
        if (mounted && value) setState(() => ready = true);
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final shape = LiquidGlassShape.roundedRectangle(
      cornerRadius: widget.radius.topLeft.x,
      borderWidth: .5,
      lightIntensity: .25,
    );
    final Widget glass = !ready || !ui.ImageFilter.isShaderFilterSupported
        ? LiquidGlassLite(
            shape: shape,
            pickup: LiquidGlassLitePickup.surface,
            blur: LiquidGlassBlur(sigmaX: widget.blur, sigmaY: widget.blur),
            color: widget.color,
            child: const SizedBox.expand(),
          )
        : LiquidGlassLens(
            style: LiquidGlassStyle(
              shape: shape,
              appearance: LiquidGlassAppearance(
                color: widget.color,
                blur: LiquidGlassBlur(sigmaX: widget.blur, sigmaY: widget.blur),
                saturation: 1.85,
              ),
              refraction: const LiquidGlassRefraction(
                distortion: .08,
                distortionWidth: 10,
                chromaticAberration: 0,
              ),
            ),
            child: const SizedBox.expand(),
          );
    // Only paint the material here. The Native child is a stable sibling at
    // the outer surface, preserving focus and unsaved input on style changes.
    return ClipRRect(borderRadius: widget.radius, child: glass);
  }
}

class _DepthEdge extends CustomPainter {
  const _DepthEdge(
    this.radius,
    this.light,
    this.dark,
    this.recessed,
    this.sheen,
  );
  final BorderRadius radius;
  final Color light;
  final bool dark;
  final bool recessed;
  final bool sheen;
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final shape = radius.toRRect(rect).deflate(.5);
    canvas.drawRRect(
      shape,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = .5
        ..color = (dark ? Colors.white : Colors.black).withValues(alpha: .07),
    );
    canvas.save();
    canvas.clipRRect(shape);
    if (sheen && !recessed) {
      canvas.drawRect(
        rect,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              light.withValues(alpha: dark ? .05 : .12),
              Colors.transparent,
            ],
            stops: const [0, .6],
          ).createShader(rect),
      );
    }
    canvas.drawLine(
      const Offset(0, .5),
      Offset(size.width, .5),
      Paint()
        ..strokeWidth = 1
        ..color = recessed
            ? Colors.black.withValues(alpha: dark ? .3 : .12)
            : light,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_DepthEdge old) =>
      old.radius != radius ||
      old.light != light ||
      old.dark != dark ||
      old.recessed != recessed ||
      old.sheen != sheen;
}
