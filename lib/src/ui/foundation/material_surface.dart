import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:liquid_glass_easy/liquid_glass_easy.dart';

import 'joined_control.dart';
import 'material_theme.dart';
import 'tokens.dart';

/// Internal painting roles. This adds no targets, padding or gesture listeners.
enum DSurfaceDepth {
  raised,
  floatingDate,
  recessed,
  panel,
  menu,
  dialog,
  sheet,
  card,
  swatch,
  primaryCapsule,
  chromeSelection,
}

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
    this.glassTint,
    this.insetEdges = false,
  });
  final Widget child;
  final Color color;
  final BorderRadius radius;
  final DSurfaceDepth depth;
  final bool accented;

  /// Pre-tinted window wells retain their opacity in both appearance modes.
  final bool preserveColor;

  /// Explicit tint for raised glass. Null retains the stock glass material.
  final Color? glassTint;

  /// CSS-style inner shadow and bottom rim for inset action wells. This
  /// opt-in retains the existing edge painting of other recessed controls.
  final bool insetEdges;

  static bool active(BuildContext context) =>
      DMaterialTheme.of(context) != null;
  static Color fill(BuildContext context, Color color) =>
      active(context) ? Colors.transparent : color;

  @override
  Widget build(BuildContext context) {
    if (depth == DSurfaceDepth.primaryCapsule ||
        depth == DSurfaceDepth.chromeSelection) {
      final glass = DMaterialTheme.glassOf(context);
      final dark = Theme.of(context).brightness == Brightness.dark;
      final selected = depth == DSurfaceDepth.chromeSelection;
      final reduced = DMaterialTheme.reducedOf(context);
      final fill = selected || reduced
          ? color
          : color.withValues(alpha: color.a * .76);
      return CustomPaint(
        painter: glass
            ? null
            : _ChromeOuterShadow(
                radius,
                BoxShadow(
                  color: Colors.black.withValues(
                    alpha: selected ? .2 : (dark ? .2 : .08),
                  ),
                  offset: Offset(0, selected ? 1 : 4),
                  blurRadius: selected ? 2 : 14,
                ),
              ),
        child: Stack(
          fit: StackFit.passthrough,
          children: [
            Positioned.fill(
              child: IgnorePointer(
                child: ExcludeSemantics(
                  child: glass
                      ? _GlassPaint(radius: radius, depth: depth)
                      : CustomPaint(
                          painter: _ChromeFill(
                            radius,
                            fill,
                            dark,
                            !reduced,
                            selected,
                          ),
                          foregroundPainter: _ChromeRaisedEdges(
                            radius,
                            dark,
                            selected,
                          ),
                        ),
                ),
              ),
            ),
            _SurfaceContent(enabled: glass, child: child),
          ],
        ),
      );
    }
    if (!active(context)) return child;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final glass = DMaterialTheme.glassOf(context);
    final recessed = depth == DSurfaceDepth.recessed;
    final menu =
        depth == DSurfaceDepth.menu ||
        depth == DSurfaceDepth.dialog ||
        depth == DSurfaceDepth.sheet;
    final panel = depth == DSurfaceDepth.panel;
    final joined =
        depth == DSurfaceDepth.raised || depth == DSurfaceDepth.floatingDate
        ? DJoinedControlScope.maybeOf(context)
        : null;
    final solid = depth == DSurfaceDepth.swatch || depth == DSurfaceDepth.card;
    final lens = glass && color.a > 0 && !panel && !recessed && !solid;
    final alpha = accented
        ? 1.0
        : menu
        ? .68
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
        radius: radius,
        depth: depth,
        color: paintedColor,
        glassTint: depth == DSurfaceDepth.raised ? glassTint : null,
        joined: joined,
      );
    } else {
      background = DecoratedBox(
        decoration: BoxDecoration(color: paintedColor, borderRadius: radius),
        child: const SizedBox.expand(),
      );
    }
    background = CustomPaint(
      foregroundPainter: lens || color.a == 0
          ? null
          : menu
          ? null
          : insetEdges
          ? _InsetEdges(radius, dark)
          : panel && !DMaterialTheme.reducedOf(context)
          ? _PanelEdge(radius, dark)
          : _DepthEdge(radius, light, dark, recessed, glass && !solid),
      child: background,
    );
    final shadow = BoxShadow(
      color: Colors.black.withValues(
        alpha: menu
            ? .28
            : dark
            ? .24
            : .09,
      ),
      offset: Offset(0, menu ? 18 : 1),
      blurRadius: menu ? 44 : 3,
    );
    final castsShadow =
        !lens && !recessed && !panel && color.a > 0 && (!menu || glass);
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
            _SurfaceContent(enabled: lens, child: child),
          ],
        ),
      ),
    );
    // Popovers may overlap their parent controls; they must sample the live
    // painted stack instead of a card's earlier shared backdrop.
    return menu ? LiquidGlassBatch.exclude(child: surface) : surface;
  }
}

/// CSS outer shadows exclude the border box. Flutter's ordinary BoxShadow
/// also paints behind a translucent fill, which would darken its accent tint.
class _ChromeOuterShadow extends CustomPainter {
  const _ChromeOuterShadow(this.radius, this.shadow);

  final BorderRadius radius;
  final BoxShadow shadow;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final shape = radius.toRRect(rect).scaleRadii();
    canvas.save();
    canvas.clipPath(
      Path()
        ..fillType = PathFillType.evenOdd
        ..addRect(rect.inflate(shadow.blurSigma * 3 + shadow.offset.distance))
        ..addRRect(shape),
    );
    canvas.drawRRect(shape.shift(shadow.offset), shadow.toPaint());
    canvas.restore();
  }

  @override
  bool shouldRepaint(_ChromeOuterShadow old) =>
      old.radius != radius || old.shadow != shadow;
}

/// The mockup's writing capsule has no backdrop filter: it sits on the window
/// ground. Paint its tint and elliptical catch of light as one shared surface.
class _ChromeFill extends CustomPainter {
  const _ChromeFill(
    this.radius,
    this.color,
    this.dark,
    this.glass,
    this.selected,
  );

  final BorderRadius radius;
  final Color color;
  final bool dark;
  final bool glass;
  final bool selected;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.save();
    canvas.clipRRect(radius.toRRect(rect));
    canvas.drawRect(rect, Paint()..color = color);
    if (glass && !selected && !size.isEmpty) {
      canvas.translate(size.width * .35, size.height * -.25);
      canvas.scale(size.width * 1.2, size.height * 1.1);
      canvas.drawPaint(
        Paint()
          ..shader = ui.Gradient.radial(
            Offset.zero,
            1,
            [
              Colors.white.withValues(alpha: dark ? .12 : .55),
              Colors.white.withValues(alpha: 0),
            ],
            const [0, .62],
          ),
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_ChromeFill old) =>
      old.radius != radius ||
      old.color != color ||
      old.dark != dark ||
      old.glass != glass ||
      old.selected != selected;
}

class _ChromeRaisedEdges extends CustomPainter {
  const _ChromeRaisedEdges(this.radius, this.dark, this.selected);

  final BorderRadius radius;
  final bool dark;
  final bool selected;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final shape = radius.toRRect(rect).scaleRadii();
    Path outside(Offset offset) => Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(rect.inflate(8))
      ..addRRect(shape.shift(offset));

    canvas.save();
    canvas.clipRRect(shape);
    if (!selected) {
      canvas.drawRRect(
        shape.deflate(.5),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = Colors.white.withValues(alpha: dark ? .14 : .75),
      );
    }
    canvas.drawPath(
      outside(const Offset(0, 1)),
      Paint()
        ..color = Colors.white.withValues(
          alpha: selected ? .22 : (dark ? .216 : .99),
        )
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, .5),
    );
    if (!selected) {
      canvas.drawPath(
        outside(const Offset(0, -1)),
        Paint()
          ..color = Colors.black.withValues(alpha: .1)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1),
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_ChromeRaisedEdges old) =>
      old.radius != radius || old.dark != dark || old.selected != selected;
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
    // Keep the shadow outside the joined silhouette. A translucent glass fill
    // otherwise reads its own shadow as a rectangular backing at the joins.
    canvas.clipPath(
      Path()
        ..fillType = PathFillType.evenOdd
        ..addRect(bounds)
        ..addRRect(shape),
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
/// Disable for page panels, whose lenses overlap other painted content.
class DMaterialBatch extends StatelessWidget {
  const DMaterialBatch({super.key, required this.child, this.enabled = true});
  final Widget child;
  final bool enabled;
  @override
  Widget build(BuildContext context) => LiquidGlassBatch(
    enabled:
        enabled &&
        DMaterialTheme.glassOf(context) &&
        ui.ImageFilter.isShaderFilterSupported,
    child: child,
  );
}

class _SurfaceContent extends StatelessWidget {
  const _SurfaceContent({required this.enabled, required this.child});

  final bool enabled;
  final Widget child;

  @override
  Widget build(BuildContext context) => LiquidGlassAdaptiveContent(
    adaptivity: const LiquidGlassAdaptivity(),
    builder: (context, color, _) => IconTheme.merge(
      data: IconThemeData(color: enabled ? color : null),
      child: DefaultTextStyle.merge(
        style: TextStyle(color: enabled ? color : null),
        child: child,
      ),
    ),
  );
}

class _GlassPaint extends StatelessWidget {
  const _GlassPaint({
    required this.radius,
    required this.depth,
    this.color,
    this.glassTint,
    this.joined,
  });

  final BorderRadius radius;
  final DSurfaceDepth depth;
  final Color? color;
  final Color? glassTint;
  final DJoinedControlScope? joined;

  @override
  Widget build(BuildContext context) {
    final cornerRadius = [
      radius.topLeft.x,
      radius.topRight.x,
      radius.bottomLeft.x,
      radius.bottomRight.x,
    ].reduce((a, b) => a > b ? a : b);
    final preset = switch (depth) {
      DSurfaceDepth.menu ||
      DSurfaceDepth.dialog => LiquidGlassDialog.defaultStyle,
      DSurfaceDepth.sheet => LiquidGlassSheet.defaultStyle,
      _ => LiquidGlassButton.defaultStyle,
    };
    final date = depth == DSurfaceDepth.floatingDate;
    final floating =
        date ||
        depth == DSurfaceDepth.menu ||
        depth == DSurfaceDepth.dialog ||
        depth == DSurfaceDepth.sheet;
    final explicitTint = glassTint?.withValues(alpha: glassTint!.a * .76);
    final tint = date
        ? DTokens.of(context).surface.withValues(alpha: .68)
        : explicitTint ?? color;
    final style = (floating || explicitTint != null) && tint != null
        ? preset.copyWith(
            color: tint,
            blur: floating ? 16 : preset.blur,
            saturation: date ? 1.85 : preset.saturation,
            adaptivity: LiquidGlassAdaptivity(
              glassColorOnDark: tint,
              glassColorOnLight: tint,
            ),
          )
        : preset;
    Widget glass = LiquidGlassLens(
      style: style.copyWith(
        shape: LiquidGlassShape.roundedRectangle(cornerRadius: cornerRadius),
      ),
      child: const SizedBox.expand(),
    );
    if (joined case final joined?) {
      final extent = cornerRadius;
      final horizontal = joined.axis == Axis.horizontal;
      final ltr = Directionality.of(context) == TextDirection.ltr;
      glass = Stack(
        children: [
          Positioned.fill(
            left: horizontal && !(ltr ? joined.first : joined.last)
                ? -extent
                : 0,
            right: horizontal && !(ltr ? joined.last : joined.first)
                ? -extent
                : 0,
            top: !horizontal && !joined.first ? -extent : 0,
            bottom: !horizontal && !joined.last ? -extent : 0,
            child: glass,
          ),
        ],
      );
    }
    return ClipRRect(borderRadius: radius, child: glass);
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
    final bottom = Path.combine(
      PathOperation.difference,
      Path()..addRRect(shape),
      Path()..addRRect(shape.shift(const Offset(0, -1))),
    );
    canvas.drawPath(
      bottom,
      Paint()..color = Colors.white.withValues(alpha: dark ? .08 : .8),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_InsetEdges old) =>
      old.radius != radius || old.dark != dark;
}

/// The panel's catch of light has a fixed 140px falloff, independent of the
/// window height. Its constant inset rim and soft top edge follow the corners.
/// Paint inside the clip so no shadow stains its corner gutters.
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
        // The mockup's inset 1px --glass-rim stays constant down the panel.
        // Only the broad catch of light above it fades within 140px.
        ..color = Colors.white.withValues(alpha: dark ? .14 : .75),
    );
    // CSS inset 0 1px 1px white: light from the shifted shape's outside is
    // blurred through the panel clip, following rounded sheet corners too.
    canvas.drawPath(
      Path()
        ..fillType = PathFillType.evenOdd
        ..addRect(rect.inflate(8))
        ..addRRect(radius.toRRect(rect).shift(const Offset(0, 1))),
      Paint()
        ..color = Colors.white.withValues(alpha: (dark ? .12 : .55) * 1.6)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, .5),
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
