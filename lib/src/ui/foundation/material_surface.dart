import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:liquid_glass_easy/liquid_glass_easy.dart';

import 'joined_control.dart';
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
    this.preserveColor = false,
    this.insetEdges = false,
  });
  final Widget child;
  final Color color;
  final BorderRadius radius;
  final DSurfaceDepth depth;
  final bool accented;

  /// Pre-tinted window wells retain their opacity in both appearance modes.
  final bool preserveColor;

  /// CSS-style inner shadow and bottom rim for inset action wells. This
  /// opt-in retains the existing edge painting of other recessed controls.
  final bool insetEdges;

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
    final joined = depth == DSurfaceDepth.raised
        ? DJoinedControlScope.maybeOf(context)
        : null;
    final solid = depth == DSurfaceDepth.swatch || depth == DSurfaceDepth.card;
    final lens = glass && color.a > 0 && !panel && !recessed && !solid;
    final alpha = accented
        ? 1.0
        : menu
        ? .88
        : dark
        ? .66
        : .72;
    final paintedColor = glass && !solid && !panel && !preserveColor
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
          : insetEdges
          ? _InsetEdges(radius, dark)
          : panel && !DMaterialTheme.reducedOf(context)
          ? _PanelEdge(radius, dark)
          : _DepthEdge(radius, light, dark, recessed, glass && !solid),
      child: background,
    );
    final shadow = BoxShadow(
      color: Colors.black.withValues(alpha: dark ? .24 : .09),
      offset: Offset(0, menu ? 18 : 1),
      blurRadius: menu ? 44 : 3,
    );
    final castsShadow = !recessed && !panel && color.a > 0;
    final surface = CustomPaint(
      painter: castsShadow && joined != null
          ? _JoinedSurfaceShadow(
              radius: radius,
              shadow: shadow,
              axis: joined.axis,
              first: joined.first,
              last: joined.last,
              direction: Directionality.of(context),
            )
          : null,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: radius,
          // Reading panels sit flush inside clipped workspace/viewports. An
          // outer shadow is cut to that rectangle, staining their rounded
          // corners and gutters. Their edge treatment supplies depth in-bounds.
          boxShadow: castsShadow && joined == null ? [shadow] : const [],
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
      ),
    );
    // Popovers may overlap their parent controls; they must sample the live
    // painted stack instead of a card's earlier shared backdrop.
    return menu ? LiquidGlassBatch.exclude(child: surface) : surface;
  }
}

/// Continue the shadow through joined edges without painting over a neighbor.
/// Each segment owns only its slice, including passive button-group text.
class _JoinedSurfaceShadow extends CustomPainter {
  const _JoinedSurfaceShadow({
    required this.radius,
    required this.shadow,
    required this.axis,
    required this.first,
    required this.last,
    required this.direction,
  });

  final BorderRadius radius;
  final BoxShadow shadow;
  final Axis axis;
  final bool first;
  final bool last;
  final TextDirection direction;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final extent = shadow.blurSigma * 3 + shadow.offset.distance;
    final bounds = rect.inflate(extent);
    final horizontal = axis == Axis.horizontal;
    final joinsLeft =
        horizontal && !(direction == TextDirection.ltr ? first : last);
    final joinsRight =
        horizontal && !(direction == TextDirection.ltr ? last : first);
    final joinsTop = !horizontal && !first;
    final joinsBottom = !horizontal && !last;
    final shape = RRect.fromRectAndCorners(
      Rect.fromLTRB(
        joinsLeft ? bounds.left : rect.left,
        joinsTop ? bounds.top : rect.top,
        joinsRight ? bounds.right : rect.right,
        joinsBottom ? bounds.bottom : rect.bottom,
      ),
      topLeft: radius.topLeft,
      topRight: radius.topRight,
      bottomLeft: radius.bottomLeft,
      bottomRight: radius.bottomRight,
    );
    canvas.save();
    canvas.clipRect(
      Rect.fromLTRB(
        joinsLeft ? rect.left : bounds.left,
        joinsTop ? rect.top : bounds.top,
        joinsRight ? rect.right : bounds.right,
        joinsBottom ? rect.bottom : bounds.bottom,
      ),
    );
    canvas.drawRRect(shape.shift(shadow.offset), shadow.toPaint());
    canvas.restore();
  }

  @override
  bool shouldRepaint(_JoinedSurfaceShadow old) =>
      old.radius != radius ||
      old.shadow != shadow ||
      old.axis != axis ||
      old.first != first ||
      old.last != last ||
      old.direction != direction;
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
    );
    // Version 5 expresses rim thickness in logical pixels and separates it
    // from the outline. Keep the subdued rim using the migration's scale.
    const specular = LiquidGlassLight.specular(
      thickness: 2.7,
      sharpness: 0,
      intensity: .25,
      angle: 0,
      spread: .5,
    );
    const glow = LiquidGlassLight.glow(thickness: 14.7, angle: 90);
    final Widget glass = !ready || !ui.ImageFilter.isShaderFilterSupported
        ? LiquidGlassLite(
            shape: shape,
            specular: specular,
            glow: glow,
            blur: widget.blur,
            color: widget.color,
            child: const SizedBox.expand(),
          )
        : LiquidGlassLens(
            style: LiquidGlassStyle(
              shape: shape,
              specular: specular,
              glow: glow,
              color: widget.color,
              blur: widget.blur,
              saturation: 1.85,
              refractionIndex: 1.02,
              refractionWidth: 10,
              dispersion: 0,
            ),
            child: const SizedBox.expand(),
          );
    // Only paint the material here. The Native child is a stable sibling at
    // the outer surface, preserving focus and unsaved input on style changes.
    return ClipRRect(borderRadius: widget.radius, child: glass);
  }
}

class _InsetEdges extends CustomPainter {
  const _InsetEdges(this.radius, this.dark);

  final BorderRadius radius;
  final bool dark;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final shape = radius.toRRect(rect);
    Path outside(Offset offset) => Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(rect.inflate(8))
      ..addRRect(shape.shift(offset));

    canvas.save();
    canvas.clipRRect(shape);
    // inset 0 1px 2px black: draw the blurred outside of the shifted shape
    // through the original shape's clip, so nothing casts an outer shadow.
    canvas.drawPath(
      outside(const Offset(0, 1)),
      Paint()
        ..color = Colors.black.withValues(alpha: dark ? .32 : .12)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1),
    );
    canvas.drawRRect(
      shape.deflate(.5),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = (dark ? Colors.white : Colors.black).withValues(
          alpha: dark ? .07 : .06,
        ),
    );
    // inset 0 -1px 0 white: the light catches only the bottom of the well.
    canvas.drawPath(
      outside(const Offset(0, -1)),
      Paint()..color = Colors.white.withValues(alpha: dark ? .08 : .8),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_InsetEdges old) =>
      old.radius != radius || old.dark != dark;
}

/// The panel's catch of light has a fixed 140px falloff, independent of the
/// window height. Paint inside the clip so no shadow stains its corner gutters.
class _PanelEdge extends CustomPainter {
  const _PanelEdge(this.radius, this.dark);
  final BorderRadius radius;
  final bool dark;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.save();
    canvas.clipRRect(radius.toRRect(rect));
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.white.withValues(alpha: dark ? .12 * .55 : .5),
            Colors.white.withValues(alpha: 0),
          ],
        ).createShader(Rect.fromLTWH(0, 0, size.width, 140)),
    );
    canvas.drawRRect(
      radius.toRRect(rect).deflate(.5),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = Colors.white.withValues(alpha: dark ? .14 : .75),
    );
    canvas.drawLine(
      const Offset(0, .5),
      Offset(size.width, .5),
      Paint()
        ..strokeWidth = 1
        ..color = Colors.white.withValues(alpha: (dark ? .12 : .55) * 1.6),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_PanelEdge old) =>
      old.radius != radius || old.dark != dark;
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
