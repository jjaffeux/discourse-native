import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

import '../../theme/discourse_typography.dart';
import 'tokens.dart';

enum DControlSize { extraSmall, small, regular, large }

/// Shared geometry and outlined surfaces for action and selection controls.
abstract final class DControlStyle {
  static const extraSmallHeight = 24.0;
  static const smallHeight = 28.0;
  static const regularHeight = 32.0;
  static const largeHeight = 36.0;

  static const duration = Duration(milliseconds: 150);
  static const iconSize = 16.0;
  static const gap = 6.0;
  static double height(DControlSize size) => switch (size) {
    DControlSize.extraSmall => extraSmallHeight,
    DControlSize.small => smallHeight,
    DControlSize.regular => regularHeight,
    DControlSize.large => largeHeight,
  };
  static double fontSize(DControlSize size) => switch (size) {
    DControlSize.extraSmall => DiscourseTypography.xs,
    DControlSize.small => DiscourseTypography.base * .8,
    _ => DiscourseTypography.sm,
  };
  static double lineHeight(DControlSize size) => switch (size) {
    DControlSize.extraSmall => 16,
    DControlSize.small => 22.4,
    _ => 20,
  };
  static double iconDimension(DControlSize size) => switch (size) {
    DControlSize.extraSmall || DControlSize.small => 14,
    _ => 16,
  };

  /// Text scaling expands every control consistently, including icon buttons.
  static double scaledHeight(DControlSize size, TextScaler scaler) => math.max(
    height(size),
    (scaler.scale(fontSize(size)) * lineHeight(size) / fontSize(size))
            .ceilToDouble() +
        2,
  );

  static double radius(DTokens tokens, DControlSize size) => switch (size) {
    DControlSize.extraSmall => (tokens.radius * .8).clamp(0, 10),
    DControlSize.small => (tokens.radius * .8).clamp(0, 12),
    _ => tokens.radius,
  };
  static Color alpha(Color color, double factor) =>
      color.withValues(alpha: color.a * factor);
  static Color outlineFill(
    DTokens tokens, {
    required bool dark,
    bool hovered = false,
    bool field = false,
  }) {
    final input = tokens.colors.outlineVariant;
    if (dark) return alpha(input, hovered ? .5 : .3);
    if (field) return hovered ? alpha(input, .5) : Colors.transparent;
    return hovered ? tokens.muted : tokens.background;
  }
}

/// One painter owns control borders, joined edges and exterior focus rings.
@immutable
class DControlDecoration extends Decoration {
  const DControlDecoration({
    required this.color,
    required this.borderColor,
    required this.borderRadius,
    this.ringColor = const Color(0x00000000),
    this.ringWidth = 0,
    this.joinedAxis,
  }) : assert(ringWidth >= 0);

  static const double borderWidth = 1;

  final Color color;
  final Color borderColor;
  final BorderRadius borderRadius;
  final Color ringColor;
  final double ringWidth;
  final Axis? joinedAxis;

  @override
  BoxPainter createBoxPainter([VoidCallback? onChanged]) =>
      _DControlPainter(this);

  @override
  Decoration? lerpFrom(Decoration? a, double t) => a is DControlDecoration
      ? DControlDecoration(
          color: Color.lerp(a.color, color, t)!,
          borderColor: Color.lerp(a.borderColor, borderColor, t)!,
          borderRadius: BorderRadius.lerp(a.borderRadius, borderRadius, t)!,
          ringColor: Color.lerp(a.ringColor, ringColor, t)!,
          ringWidth: lerpDouble(a.ringWidth, ringWidth, t)!,
          joinedAxis: t < .5 ? a.joinedAxis : joinedAxis,
        )
      : super.lerpFrom(a, t);

  @override
  Decoration? lerpTo(Decoration? b, double t) =>
      b is DControlDecoration ? b.lerpFrom(this, t) : super.lerpTo(b, t);

  @override
  bool operator ==(Object other) =>
      other is DControlDecoration &&
      other.color == color &&
      other.borderColor == borderColor &&
      other.borderRadius == borderRadius &&
      other.ringColor == ringColor &&
      other.ringWidth == ringWidth &&
      other.joinedAxis == joinedAxis;

  @override
  int get hashCode => Object.hash(
    color,
    borderColor,
    borderRadius,
    ringColor,
    ringWidth,
    joinedAxis,
  );
}

class _DControlPainter extends BoxPainter {
  const _DControlPainter(this.decoration);

  final DControlDecoration decoration;

  @override
  void paint(Canvas canvas, Offset offset, ImageConfiguration configuration) {
    final rect = offset & configuration.size!;
    final outer = decoration.borderRadius.toRRect(rect);
    final direction = configuration.textDirection ?? TextDirection.ltr;
    final axis = decoration.joinedAxis;
    const width = DControlDecoration.borderWidth;
    final sharesStart = axis == Axis.horizontal;
    final inner = RRect.fromRectAndCorners(
      Rect.fromLTRB(
        rect.left + (sharesStart && direction == TextDirection.ltr ? 0 : width),
        rect.top + (axis == Axis.vertical ? 0 : width),
        rect.right -
            (sharesStart && direction == TextDirection.rtl ? 0 : width),
        rect.bottom - width,
      ),
      topLeft: _shrink(outer.tlRadius, width),
      topRight: _shrink(outer.trRadius, width),
      bottomLeft: _shrink(outer.blRadius, width),
      bottomRight: _shrink(outer.brRadius, width),
    );
    if (decoration.ringWidth > 0 && decoration.ringColor.a > 0) {
      canvas.drawDRRect(
        outer.inflate(decoration.ringWidth),
        outer,
        Paint()..color = decoration.ringColor,
      );
    }
    if (decoration.borderColor.a > 0) {
      // The shared edge leaves the inner and outer paths touching, which an
      // even-odd path difference handles where drawDRRect is undefined.
      canvas.drawPath(
        Path()
          ..fillType = PathFillType.evenOdd
          ..addRRect(outer)
          ..addRRect(inner),
        Paint()..color = decoration.borderColor,
      );
    }
    if (decoration.color.a > 0) {
      canvas.drawRRect(inner, Paint()..color = decoration.color);
    }
  }

  static Radius _shrink(Radius radius, double by) =>
      Radius.elliptical(math.max(0, radius.x - by), math.max(0, radius.y - by));
}
