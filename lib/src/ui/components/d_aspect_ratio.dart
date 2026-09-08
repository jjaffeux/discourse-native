import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Sizes [child] to a preferred width-to-height [ratio].
///
/// A ratio of `16 / 9` produces a landscape box; `1` is square and `9 / 16`
/// is portrait. Any finite positive ratio is supported, not just these examples.
///
/// Flutter's [RenderAspectRatio] owns layout:
/// * With a bounded width it starts at the maximum width and derives the height.
/// * With only a bounded height it derives the width from that height.
/// * It adjusts to the parent's minimum and maximum constraints. Constraints
///   take precedence when the ratio cannot fit, including a tight [SizedBox].
/// * At least one axis must be bounded. Inside an [UnconstrainedBox] or a
///   [FittedBox], supply a finite width or height with a [SizedBox].
///
/// The child receives tight constraints for the resulting size. Content does
/// not change the ratio, so put captions outside this box and provide scrolling
/// for content that can grow with text scaling.
///
/// This widget has no paint, clipping, semantics, input or animation of its own.
/// Compose [ClipRRect], [ColoredBox], images with a caller-chosen fit, or a
/// [Stack] as needed. Children keep their native semantics, focus and state
/// across ratio, theme and direction updates. Media, controllers and focus
/// nodes remain owned and disposed by their callers or descendants.
class DAspectRatio extends SingleChildRenderObjectWidget {
  const DAspectRatio({super.key, required this.ratio, super.child})
    : assert(ratio > 0 && ratio < double.infinity);

  /// The preferred width divided by height; must be finite and greater than 0.
  ///
  /// Invalid values fail the constructor assertion in debug mode and throw
  /// [ArgumentError] when mounted or updated in release mode. Normalize remote
  /// media metadata at the application boundary before passing it here.
  final double ratio;

  double _validatedRatio() {
    if (!ratio.isFinite || ratio <= 0) {
      throw ArgumentError.value(ratio, 'ratio', 'must be finite and positive');
    }
    return ratio;
  }

  @override
  RenderAspectRatio createRenderObject(BuildContext context) =>
      RenderAspectRatio(aspectRatio: _validatedRatio());

  @override
  void updateRenderObject(
    BuildContext context,
    RenderAspectRatio renderObject,
  ) {
    renderObject.aspectRatio = _validatedRatio();
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(DoubleProperty('ratio', ratio));
  }
}
