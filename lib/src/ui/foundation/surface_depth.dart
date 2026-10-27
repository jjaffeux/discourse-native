import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// How a solid surface stands off what is under it, as the mockup's look A
/// draws it: a 1px inset rim, a 1px catch of light along the top edge, and
/// the shadows it casts. There is no tint to see through and no blur layer.
enum DSurfaceDepth {
  /// Pages, panels, page sheets and the docked composer: `[data-panel]`,
  /// `.glass-sheet` and `.composer-panel`.
  panel,

  /// The phone drawer's sidebar: its rim alone, since a shadow there would be
  /// cut short by the rail over its edge and left as a band beside it.
  rim,

  /// Popovers, dropdowns and the phone's menu sheets: `.menu-surface`, the
  /// window's top layer, with a close shadow and a wide one.
  menu,

  /// What is layered inside a panel, a summary's boxes and its stat well
  /// (`.sum-box`, `.stat-well`): a rim in place of the border, a soft catch of
  /// light and a small shadow.
  block,

  /// A toast, or the composer's suggestions: a menu surface whose own
  /// shadow replaces the menus' pair and their catch of light.
  floating,

  /// The timeline's thumb, which stands off its track.
  thumb,

  /// A card that is a place to go, a category or a channel
  /// (`.home-box-place`): it stands up off the panel, with a catch of light
  /// and a close and a soft shadow but no rim.
  place,

  /// [place] under the pointer, raised a step further.
  placeHovered,

  /// A sheet that is something to write on (`.menu-sheet.is-full`): no rim
  /// or catch of light, only a shadow cast up over the page.
  fullSheet,
}

/// One CSS `box-shadow` cast outside a surface. [blur] is the CSS blur
/// length, twice the Gaussian's standard deviation.
@immutable
class DCastShadow {
  const DCastShadow(this.offset, this.blur, this.color);

  final Offset offset;
  final double blur;
  final Color color;

  double get sigma => blur / 2;

  @override
  bool operator ==(Object other) =>
      other is DCastShadow &&
      other.offset == offset &&
      other.blur == blur &&
      other.color == color;

  @override
  int get hashCode => Object.hash(offset, blur, color);

  @override
  String toString() => 'DCastShadow($offset, $blur, $color)';
}

/// The resolved edges of one [DSurfaceDepth] in one brightness, from the
/// mockup's `--glass-rim`, `--glass-hi` and `--glass-shade`.
@immutable
class DSurfaceEdges {
  const DSurfaceEdges({
    this.rim,
    this.highlight,
    this.highlightBlur = 0,
    this.shadows = const [],
  });

  factory DSurfaceEdges.of(DSurfaceDepth depth, Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final rim = (dark ? Colors.white : Colors.black).withValues(alpha: .07);
    final highlight = Colors.white.withValues(alpha: dark ? .07 : .8);
    Color black(double alpha) => Colors.black.withValues(alpha: alpha);
    return switch (depth) {
      DSurfaceDepth.panel => DSurfaceEdges(
        rim: rim,
        highlight: highlight,
        shadows: [
          DCastShadow(const Offset(0, 12), 40, black(dark ? .24 : .09)),
        ],
      ),
      DSurfaceDepth.rim => DSurfaceEdges(rim: rim),
      DSurfaceDepth.menu => DSurfaceEdges(
        highlight: highlight,
        shadows: [
          DCastShadow(const Offset(0, 2), 6, black(dark ? .2 : .08)),
          DCastShadow(const Offset(0, 18), 44, black(dark ? .38 : .16)),
        ],
      ),
      DSurfaceDepth.place => DSurfaceEdges(
        highlight: Colors.white.withValues(alpha: dark ? .06 : .9),
        shadows: [
          DCastShadow(const Offset(0, 1), 2, black(dark ? .14 : .06)),
          DCastShadow(const Offset(0, 4), 14, black(dark ? .12 : .06)),
        ],
      ),
      DSurfaceDepth.placeHovered => DSurfaceEdges(
        highlight: Colors.white.withValues(alpha: dark ? .09 : .9),
        shadows: [
          DCastShadow(const Offset(0, 2), 4, black(dark ? .16 : .07)),
          DCastShadow(const Offset(0, 10), 24, black(dark ? .18 : .1)),
        ],
      ),
      DSurfaceDepth.block => DSurfaceEdges(
        rim: rim,
        highlight: Colors.white.withValues(
          alpha: math.min(1, (dark ? .07 : .8) * 1.4),
        ),
        highlightBlur: 1,
        shadows: [DCastShadow(const Offset(0, 4), 16, black(.08))],
      ),
      DSurfaceDepth.floating => DSurfaceEdges(
        shadows: [DCastShadow(const Offset(0, 8), 24, black(.25))],
      ),
      DSurfaceDepth.thumb => DSurfaceEdges(
        shadows: [DCastShadow(const Offset(0, 2), 6, black(.3))],
      ),
      DSurfaceDepth.fullSheet => DSurfaceEdges(
        shadows: [DCastShadow(const Offset(0, -8), 32, black(.22))],
      ),
    };
  }

  static DSurfaceEdges resolve(BuildContext context, DSurfaceDepth depth) =>
      DSurfaceEdges.of(depth, Theme.of(context).brightness);

  /// Eases between two depths of one surface, as CSS transitions a
  /// `box-shadow` whose lists match shadow for shadow.
  static DSurfaceEdges lerp(DSurfaceEdges a, DSurfaceEdges b, double t) {
    assert(a.shadows.length == b.shadows.length);
    return DSurfaceEdges(
      rim: Color.lerp(a.rim, b.rim, t),
      highlight: Color.lerp(a.highlight, b.highlight, t),
      highlightBlur: lerpDouble(a.highlightBlur, b.highlightBlur, t)!,
      shadows: [
        for (var i = 0; i < a.shadows.length; i++)
          DCastShadow(
            Offset.lerp(a.shadows[i].offset, b.shadows[i].offset, t)!,
            lerpDouble(a.shadows[i].blur, b.shadows[i].blur, t)!,
            Color.lerp(a.shadows[i].color, b.shadows[i].color, t)!,
          ),
      ],
    );
  }

  final Color? rim;
  final Color? highlight;

  /// The catch of light's CSS blur length; zero draws a crisp line.
  final double highlightBlur;

  /// Listed as CSS lists them: the first is drawn on top.
  final List<DCastShadow> shadows;

  /// Paints [shadows] outside [radius]'s shape, never under the surface, so a
  /// translucent fill does not darken. Use as a [CustomPaint.painter] around
  /// the whole surface; it draws past the child's bounds.
  CustomPainter? castPainter(BorderRadius radius) =>
      shadows.isEmpty ? null : _CastShadowPainter(radius, shadows);

  /// Paints the rim and the catch of light inside [radius]'s shape. Use as a
  /// [CustomPaint.painter] between the surface's fill and its content, where
  /// CSS paints an inset shadow. A surface with a border passes its widths as
  /// [border]: CSS lays an inset shadow inside the border, not under it.
  CustomPainter? insetPainter(
    BorderRadius radius, {
    EdgeInsets border = EdgeInsets.zero,
  }) => rim == null && highlight == null
      ? null
      : _InsetEdgePainter(radius, border, rim, highlight, highlightBlur);
}

class _CastShadowPainter extends CustomPainter {
  const _CastShadowPainter(this.radius, this.shadows);

  final BorderRadius radius;
  final List<DCastShadow> shadows;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final shape = radius.toRRect(rect).scaleRadii();
    var reach = 0.0;
    for (final shadow in shadows) {
      final extent = shadow.sigma * 3 + shadow.offset.distance;
      if (extent > reach) reach = extent;
    }
    canvas.save();
    canvas.clipPath(
      Path()
        ..fillType = PathFillType.evenOdd
        ..addRect(rect.inflate(reach))
        ..addRRect(shape),
    );
    // A solid-colour rounded rectangle under a normal blur is the renderer's
    // analytic fast path: one draw, no offscreen layer.
    for (final shadow in shadows.reversed) {
      canvas.drawRRect(
        shape.shift(shadow.offset),
        Paint()
          ..color = shadow.color
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, shadow.sigma),
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_CastShadowPainter old) =>
      old.radius != radius || !listEquals(old.shadows, shadows);
}

class _InsetEdgePainter extends CustomPainter {
  const _InsetEdgePainter(
    this.radius,
    this.border,
    this.rim,
    this.highlight,
    this.blur,
  );

  final BorderRadius radius;
  final EdgeInsets border;
  final Color? rim;
  final Color? highlight;
  final double blur;

  @override
  void paint(Canvas canvas, Size size) {
    final outer = radius.toRRect(Offset.zero & size).scaleRadii();
    final shape = border == EdgeInsets.zero
        ? outer
        : _paddingBox(outer, border);
    canvas.save();
    canvas.clipRRect(shape);
    // CSS `inset 0 1px 0`: the shape less itself moved down a pixel, a line
    // along the top that thins out round the corners.
    if (highlight case final highlight? when blur == 0) {
      canvas.drawPath(
        Path()
          ..fillType = PathFillType.evenOdd
          ..addRRect(shape)
          ..addRRect(shape.shift(const Offset(0, 1))),
        Paint()..color = highlight,
      );
    } else if (highlight case final highlight?) {
      _paintSoftHighlight(canvas, shape, highlight);
    }
    // The rim is listed first, so it is drawn over the catch of light.
    if (rim case final rim?) {
      canvas.drawRRect(
        shape.deflate(.5),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = rim,
      );
    }
    canvas.restore();
  }

  /// CSS `inset 0 1px <blur>`: the light outside the shape moved down a
  /// pixel, blurred in through the shape's edge. A mask blur reruns over its
  /// path's bounds every frame, so the outside is drawn as bands along the
  /// edges rather than as one path the size of the surface.
  void _paintSoftHighlight(Canvas canvas, RRect shape, Color highlight) {
    final reach = blur * 1.5 + 1;
    final shifted = Path()..addRRect(shape.shift(const Offset(0, 1)));
    final top = math.min(
      shape.bottom,
      shape.top + math.max(shape.tlRadiusY, shape.trRadiusY) + reach,
    );
    final bottom = math.max(
      top,
      shape.bottom - math.max(shape.blRadiusY, shape.brRadiusY) - reach,
    );
    final outside = shape.outerRect.inflate(reach);
    final light = Paint()
      ..color = highlight
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, blur / 2);
    for (final band in [
      Rect.fromLTRB(outside.left, outside.top, outside.right, top),
      Rect.fromLTRB(outside.left, bottom, outside.right, outside.bottom),
      Rect.fromLTRB(outside.left, top, shape.left + reach, bottom),
      Rect.fromLTRB(shape.right - reach, top, outside.right, bottom),
    ]) {
      if (band.isEmpty) continue;
      canvas.drawPath(
        Path.combine(PathOperation.difference, Path()..addRect(band), shifted),
        light,
      );
    }
  }

  @override
  bool shouldRepaint(_InsetEdgePainter old) =>
      old.blur != blur ||
      old.radius != radius ||
      old.border != border ||
      old.rim != rim ||
      old.highlight != highlight;
}

/// CSS's padding box: the border box less its border, each corner's curve
/// less the border widths that meet there.
RRect _paddingBox(RRect outer, EdgeInsets border) {
  Radius less(Radius corner, double x, double y) =>
      Radius.elliptical(math.max(0, corner.x - x), math.max(0, corner.y - y));
  return RRect.fromLTRBAndCorners(
    outer.left + border.left,
    outer.top + border.top,
    outer.right - border.right,
    outer.bottom - border.bottom,
    topLeft: less(outer.tlRadius, border.left, border.top),
    topRight: less(outer.trRadius, border.right, border.top),
    bottomRight: less(outer.brRadius, border.right, border.bottom),
    bottomLeft: less(outer.blRadius, border.left, border.bottom),
  );
}
