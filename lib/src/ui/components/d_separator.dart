import 'package:flutter/material.dart';

import '../foundation/tokens.dart';

/// A visual or semantic boundary between adjacent content.
///
/// Fills the available length in [orientation]. In an unbounded axis, supply
/// [length] or constrain the parent. For a vertical line beside wrapping text,
/// use an [IntrinsicHeight] row with [CrossAxisAlignment.stretch]. Without a
/// length or finite constraint, the line collapses along its length.
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
         decorative
             ? semanticLabel == null
             : semanticLabel != null && semanticLabel != '',
       );

  final Axis orientation;

  /// Total length, including the end insets, subject to parent constraints.
  final double? length;

  /// Logical pixels. Zero draws Flutter's one-device-pixel hairline.
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
