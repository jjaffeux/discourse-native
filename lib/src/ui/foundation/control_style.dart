import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

import '../../theme/discourse_typography.dart';
import 'tokens.dart';

/// Control artwork uses 24/34/40px on desktop and 40/44/48px on touch.
/// Typography is shared; touch targets remain at least 48px.
enum DControlSize { small, regular, large }

/// Shared geometry and outlined surfaces for action and selection controls.
abstract final class DControlStyle {
  static const smallHeight = 24.0;
  static const regularHeight = 34.0;
  static const largeHeight = 40.0;

  static const duration = Duration(milliseconds: 150);
  static const iconSize = 16.0;
  static const gap = 6.0;
  static const labelFontSize = DiscourseTypography.control;
  static const labelLineHeight =
      labelFontSize * DiscourseTypography.lineHeightSmall;
  static const rowHeight = 34.0;
  static const rowRadius = DRadius.menuItem;
  static const focusWidth = 1.0;
  static const focusOffset = 2.0;
  static bool isTouch(BuildContext? context) =>
      context != null &&
      switch (Theme.of(context).platform) {
        TargetPlatform.iOS ||
        TargetPlatform.android ||
        TargetPlatform.fuchsia => true,
        _ => false,
      };

  static double height(DControlSize size, {BuildContext? context}) =>
      isTouch(context)
      ? switch (size) {
          DControlSize.small => 40,
          DControlSize.regular => 44,
          DControlSize.large => 48,
        }
      : switch (size) {
          DControlSize.small => smallHeight,
          DControlSize.regular => regularHeight,
          DControlSize.large => largeHeight,
        };
  static double fontSize(DControlSize size, {BuildContext? context}) =>
      switch (size) {
        DControlSize.small => DiscourseTypography.preview,
        DControlSize.regular => labelFontSize,
        DControlSize.large => DiscourseTypography.sm,
      };
  static double lineHeight(DControlSize size, {BuildContext? context}) =>
      fontSize(size) * DiscourseTypography.lineHeightSmall;
  static double iconDimension(DControlSize size, {BuildContext? context}) =>
      switch (size) {
        DControlSize.small => 12,
        DControlSize.regular => 14,
        DControlSize.large => iconSize,
      };
  static double contentGap(DControlSize size) =>
      size == DControlSize.large ? gap : 4;

  /// Text scaling expands every control consistently, including icon buttons.
  static double scaledHeight(
    DControlSize size,
    TextScaler scaler, {
    BuildContext? context,
  }) => math.max(
    height(size, context: context),
    (scaler.scale(fontSize(size, context: context)) *
                lineHeight(size, context: context) /
                fontSize(size, context: context))
            .ceilToDouble() +
        2,
  );

  static double radius(DTokens tokens, DControlSize size) =>
      tokens.controlRadius;
  static Color shadow(DTokens tokens) => Colors.black.withValues(
    alpha: tokens.colors.brightness == Brightness.dark ? .30 : .06,
  );
  static Color rowHover(DTokens tokens) => Color.lerp(
    tokens.surface,
    tokens.foreground,
    tokens.colors.brightness == Brightness.dark ? .085 : .05,
  )!;
  static Color alpha(Color color, double factor) =>
      color.withValues(alpha: color.a * factor);
  static Color outlineFill(
    DTokens tokens, {
    required bool dark,
    bool hovered = false,
    bool field = false,
  }) {
    return hovered
        ? tokens.controlTheme.outline.hover
        : tokens.controlTheme.outline.background;
  }

  static Color outlineBorder(
    DTokens tokens, {
    required bool dark,
    bool field = false,
    bool hovered = false,
  }) => hovered
      ? tokens.controlTheme.outline.hoverBorder
      : tokens.controlTheme.outline.border;

  static Color fieldFill(
    DTokens tokens, {
    required bool dark,
    bool enabled = true,
  }) {
    if (tokens.controls case final controls?) {
      return controls.outline.background;
    }
    final input = tokens.colors.outlineVariant;
    return dark
        ? alpha(input, enabled ? .3 : .8)
        : enabled
        ? Colors.transparent
        : alpha(input, .5);
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
    this.ringOffset = 0,
    this.shadowColor = const Color(0x00000000),
    this.joinedAxis,
    this.strokeWidth = borderWidth,
  }) : assert(ringWidth >= 0),
       assert(strokeWidth >= 0);

  static const double borderWidth = .5;

  final Color color;
  final Color borderColor;
  final BorderRadius borderRadius;
  final Color ringColor;
  final double ringWidth;
  final double ringOffset;
  final Color shadowColor;
  final Axis? joinedAxis;

  /// Buttons use 1px; existing editable controls retain their 0.5px frame.
  final double strokeWidth;

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
          ringOffset: lerpDouble(a.ringOffset, ringOffset, t)!,
          shadowColor: Color.lerp(a.shadowColor, shadowColor, t)!,
          joinedAxis: t < .5 ? a.joinedAxis : joinedAxis,
          strokeWidth: lerpDouble(a.strokeWidth, strokeWidth, t)!,
        )
      : super.lerpFrom(a, t);

  @override
  Decoration? lerpTo(Decoration? b, double t) =>
      b is DControlDecoration ? b.lerpFrom(this, t) : super.lerpTo(b, t);

  @override
  bool operator ==(Object other) =>
      other is DControlDecoration &&
      other.strokeWidth == strokeWidth &&
      other.color == color &&
      other.borderColor == borderColor &&
      other.borderRadius == borderRadius &&
      other.ringColor == ringColor &&
      other.ringWidth == ringWidth &&
      other.ringOffset == ringOffset &&
      other.shadowColor == shadowColor &&
      other.joinedAxis == joinedAxis;

  @override
  int get hashCode => Object.hash(
    strokeWidth,
    color,
    borderColor,
    borderRadius,
    ringColor,
    ringWidth,
    ringOffset,
    shadowColor,
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
    if (decoration.shadowColor.a > 0 && decoration.joinedAxis == null) {
      const offset = Offset(0, .5);
      final shadow = BoxShadow(
        color: decoration.shadowColor,
        blurRadius: 1,
        spreadRadius: 1,
        offset: offset,
      );
      canvas.drawRRect(outer.shift(offset).inflate(1), shadow.toPaint());
    }
    final direction = configuration.textDirection ?? TextDirection.ltr;
    final axis = decoration.joinedAxis;
    final width = decoration.strokeWidth;
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
        outer.inflate(decoration.ringWidth + decoration.ringOffset),
        outer.inflate(decoration.ringOffset),
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
      canvas.drawRRect(
        decoration.borderColor.a == 0 ? outer : inner,
        Paint()..color = decoration.color,
      );
    }
  }

  static Radius _shrink(Radius radius, double by) =>
      Radius.elliptical(math.max(0, radius.x - by), math.max(0, radius.y - by));
}
