import 'package:flutter/material.dart';

import '../foundation/tokens.dart';

/// A visual or semantic boundary between adjacent content.
///
/// Mirrors the reference `shrink-0 bg-border` rule: a one-pixel line in the
/// live [DTokens.border] color whose box is exactly [thickness] across and
/// which fills the available length in [orientation]. A vertical line in a
/// [Row] fills the row's height (the reference `self-stretch`) whenever that
/// height is finite; wrap an unbounded row in [IntrinsicHeight] so the line
/// fits its siblings. In an unbounded axis with no [length], the line collapses
/// along its length rather than inventing a dimension.
///
/// Decorative lines are omitted from accessibility. A meaningful boundary uses
/// `decorative: false` and a caller-localized [semanticLabel]. Flutter has no
/// separator semantics role, so this is a static labeled boundary, never a
/// focusable control or adjustable resize handle. Pointer events pass through.
class DSeparator extends StatelessWidget {
  const DSeparator({
    super.key,
    this.orientation = Axis.horizontal,
    this.length,
    this.thickness = 1,
    this.space,
    this.indent = 0,
    this.endIndent = 0,
    this.color,
    this.radius,
    this.decorative = true,
    this.semanticLabel,
  }) : assert(length == null || (length >= 0 && length < double.infinity)),
       assert(thickness >= 0 && thickness < double.infinity),
       assert(space == null || (space >= thickness && space < double.infinity)),
       assert(indent >= 0 && indent < double.infinity),
       assert(endIndent >= 0 && endIndent < double.infinity),
       assert(
         thickness > 0 || radius == null,
         'A hairline separator (thickness 0) cannot have rounded ends.',
       ),
       assert(
         decorative
             ? semanticLabel == null
             : semanticLabel != null && semanticLabel != '',
       );

  final Axis orientation;

  /// Total length, including the end insets, subject to parent constraints.
  final double? length;

  /// Logical pixels. Zero draws Flutter's one-device-pixel hairline, which
  /// cannot be combined with [radius].
  final double thickness;

  /// Cross-axis extent, with the line centered inside it.
  ///
  /// Defaults to [thickness], or one logical pixel for a zero-width hairline.
  /// Must be at least [thickness]. External padding can add asymmetric space.
  final double? space;

  /// Leading inset: start in horizontal LTR/RTL layouts, top in vertical ones.
  final double indent;

  /// Trailing inset: end in horizontal LTR/RTL layouts, bottom in vertical ones.
  final double endIndent;

  /// Defaults to the live [DTokens.border] color.
  final Color? color;

  /// Optional rounded line ends; defaults to square ends.
  final BorderRadiusGeometry? radius;

  final bool decorative;

  /// A localized boundary description, required only when not [decorative].
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    assert(decorative || semanticLabel!.trim().isNotEmpty);
    final lineColor = color ?? DTokens.of(context).border;
    final lineSpace = space ?? (thickness == 0 ? 1.0 : thickness);
    final Widget line = switch (orientation) {
      Axis.horizontal => SizedBox(
        width: length,
        child: Divider(
          height: lineSpace,
          thickness: thickness,
          indent: indent,
          endIndent: endIndent,
          color: lineColor,
          radius: radius ?? BorderRadius.zero,
        ),
      ),
      Axis.vertical => SizedBox(
        height: length,
        child: VerticalDivider(
          width: lineSpace,
          thickness: thickness,
          indent: indent,
          endIndent: endIndent,
          color: lineColor,
          radius: radius ?? BorderRadius.zero,
        ),
      ),
    };
    final child = ExcludeSemantics(child: IgnorePointer(child: line));
    return decorative
        ? child
        : Semantics(
            container: true,
            label: semanticLabel,
            textDirection: Directionality.of(context),
            child: child,
          );
  }
}
