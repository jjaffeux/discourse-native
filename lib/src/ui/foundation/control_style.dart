import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

import '../../theme/discourse_typography.dart';
import 'tokens.dart';

/// General controls adapt to the platform. Application presets reproduce the
/// mockup artwork on every platform, with matching hit areas; a phone adds
/// the kit's `DTouchTarget` area round those drawn under 44.
enum DControlSize {
  small,
  regular,
  large,

  /// Page filters: 30px artwork and 12.5px text on desktop; 36px and
  /// 14px text/icons on phones, with kit-owned touch targets.
  filter,

  /// Search fields: 13px text, 7px vertical padding and 1px border.
  field,

  /// Preference fields: 13.5px text, 9px vertical padding and 1px border.
  preference,

  /// Compact calendar and topic actions.
  chip,

  /// Composer and desktop navigation actions.
  toolbar,

  /// View-switch segments: 26px on desktop, 32px on touch.
  segment,

  /// Window navigation: 15px artwork with 5px vertical and 7px side insets.
  chrome,

  /// Footer actions: 34px on desktop, 44px on mobile, with 12px artwork.
  action,

  /// Post reactions and actions: 30px artwork with a matching hit area.
  post,

  /// Desktop workspace document tab: 35px artwork and 13px label.
  documentTab,

  /// Desktop workspace new-tab actions.
  tabAction,

  /// The close action inside a workspace document tab.
  tabClose,
}

/// Shared geometry and outlined surfaces for action and selection controls.
abstract final class DControlStyle {
  static const smallHeight = 24.0;
  static const regularHeight = 30.0;
  static const largeHeight = 40.0;

  static const duration = Duration(milliseconds: 150);
  static const iconSize = 16.0;
  static const gap = 6.0;
  static const labelFontSize = DiscourseTypography.control;
  static const labelLineHeight =
      labelFontSize * DiscourseTypography.lineHeightSmall;
  static const rowHeight = 33.5;
  static const rowRadius = DRadius.menuItem;
  static const focusWidth = 1.0;
  static const focusOffset = 2.0;

  /// Text carets blink on and off every half period instead of fading.
  static const caretOpacityAnimates = false;
  static const caretBlinkHalfPeriod = Duration(milliseconds: 500);

  /// Flutter rounds a paragraph's layout height up to whole logical pixels.
  /// Balance that extra leading across the insets to retain the CSS row size.
  static double menuVerticalInset(BuildContext context) {
    final line =
        MediaQuery.textScalerOf(context).scale(labelFontSize) *
        DiscourseTypography.lineHeightSmall;
    return 7 - (line.ceilToDouble() - line) / 2;
  }

  static bool isTouch(BuildContext? context) =>
      context != null &&
      switch (Theme.of(context).platform) {
        TargetPlatform.iOS ||
        TargetPlatform.android ||
        TargetPlatform.fuchsia => true,
        _ => false,
      };

  static bool isApplicationSize(DControlSize size) => switch (size) {
    DControlSize.small || DControlSize.large => false,
    _ => true,
  };

  static double height(DControlSize size, {BuildContext? context}) =>
      switch (size) {
        DControlSize.small => isTouch(context) ? 40 : smallHeight,
        DControlSize.regular => regularHeight,
        DControlSize.large => isTouch(context) ? 48 : largeHeight,
        DControlSize.filter => isTouch(context) ? 36 : regularHeight,
        DControlSize.field => 35.5,
        DControlSize.preference => 40.25,
        DControlSize.chip => 24,
        DControlSize.toolbar => 34,
        DControlSize.segment => isTouch(context) ? 32 : 26,
        DControlSize.chrome => 25,
        DControlSize.action => isTouch(context) ? 44 : 34,
        DControlSize.post => 30,
        DControlSize.documentTab => 35,
        DControlSize.tabAction => 30,
        DControlSize.tabClose => 18,
      };
  static double fontSize(DControlSize size, {BuildContext? context}) =>
      switch (size) {
        DControlSize.filter =>
          isTouch(context) ? 14 : DiscourseTypography.preview,
        DControlSize.small ||
        DControlSize.regular ||
        DControlSize.chip => DiscourseTypography.preview,
        DControlSize.field ||
        DControlSize.toolbar ||
        DControlSize.chrome ||
        DControlSize.action => labelFontSize,
        DControlSize.segment => isTouch(context) ? 14 : 12.5,
        DControlSize.post => labelFontSize,
        DControlSize.documentTab ||
        DControlSize.tabAction ||
        DControlSize.tabClose => labelFontSize,
        DControlSize.large => DiscourseTypography.sm,
        DControlSize.preference => DiscourseTypography.compact,
      };
  static double lineHeight(DControlSize size, {BuildContext? context}) =>
      fontSize(size, context: context) * DiscourseTypography.lineHeightSmall;
  static double iconDimension(DControlSize size, {BuildContext? context}) =>
      switch (size) {
        DControlSize.filter => isTouch(context) ? 14 : 12,
        DControlSize.small ||
        DControlSize.regular ||
        DControlSize.chip ||
        DControlSize.action => 12,
        DControlSize.field || DControlSize.toolbar => 14,
        DControlSize.large => iconSize,
        DControlSize.preference || DControlSize.segment => 13,
        DControlSize.chrome => 15,
        DControlSize.post => 13,
        DControlSize.documentTab => 12,
        DControlSize.tabAction => 12,
        // The mockup's 11px Font Awesome 7 cross is 8px of ink; the bundled
        // Font Awesome 6 cross fills less of its box and needs 14 for that.
        DControlSize.tabClose => 14,
      };
  static double contentGap(DControlSize size) => size == DControlSize.preference
      ? 8
      : size == DControlSize.large || isApplicationSize(size)
      ? gap
      : 4;

  /// Insets include the CSS border, which Native paints inside the surface.
  static double horizontalInset(DControlSize size) => switch (size) {
    DControlSize.filter || DControlSize.regular || DControlSize.chip => 10,
    DControlSize.field => 11,
    DControlSize.preference => 12,
    DControlSize.chrome => 7,
    DControlSize.action => 14,
    DControlSize.post => 12,
    // The document surface supplies its border/inset pixel. The trailing
    // button inset is the mockup's 7px gap plus 2px close-action margin.
    DControlSize.documentTab => 9,
    DControlSize.tabAction || DControlSize.tabClose => 0,
    _ => 10,
  };

  static double chevronDimension(DControlSize size) => switch (size) {
    DControlSize.filter || DControlSize.regular || DControlSize.chip => 10,
    DControlSize.preference => 11,
    _ => iconDimension(size),
  };

  /// Text scaling expands every control consistently, including icon buttons.
  static double scaledHeight(
    DControlSize size,
    TextScaler scaler, {
    BuildContext? context,
  }) => isApplicationSize(size)
      ? height(size, context: context) +
            math.max(
                  0,
                  scaler.scale(fontSize(size, context: context)) -
                      fontSize(size, context: context),
                ) *
                DiscourseTypography.lineHeightSmall
      : math.max(
          height(size, context: context),
          (scaler.scale(fontSize(size, context: context)) *
                      lineHeight(size, context: context) /
                      fontSize(size, context: context))
                  .ceilToDouble() +
              2,
        );

  static double radius(DTokens tokens, DControlSize size) =>
      tokens.controlRadius;
  static Color rowHover(DTokens tokens) => Color.lerp(
    tokens.surface,
    tokens.foreground,
    tokens.colors.brightness == Brightness.dark ? .085 : .05,
  )!;
  static Color alpha(Color color, double factor) =>
      color.withValues(alpha: color.a * factor);

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
    this.joinedAxis,
    this.strokeWidth = borderWidth,
    this.dashed = false,
  }) : assert(ringWidth >= 0),
       assert(strokeWidth >= 0);

  static const double borderWidth = .5;

  final Color color;
  final Color borderColor;
  final BorderRadius borderRadius;
  final Color ringColor;
  final double ringWidth;
  final double ringOffset;
  final Axis? joinedAxis;

  /// Buttons use 1px; existing editable controls retain their 0.5px frame.
  final double strokeWidth;
  final bool dashed;

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
          joinedAxis: t < .5 ? a.joinedAxis : joinedAxis,
          strokeWidth: lerpDouble(a.strokeWidth, strokeWidth, t)!,
          dashed: t < .5 ? a.dashed : dashed,
        )
      : super.lerpFrom(a, t);

  @override
  Decoration? lerpTo(Decoration? b, double t) =>
      b is DControlDecoration ? b.lerpFrom(this, t) : super.lerpTo(b, t);

  @override
  bool operator ==(Object other) =>
      other is DControlDecoration &&
      other.strokeWidth == strokeWidth &&
      other.dashed == dashed &&
      other.color == color &&
      other.borderColor == borderColor &&
      other.borderRadius == borderRadius &&
      other.ringColor == ringColor &&
      other.ringWidth == ringWidth &&
      other.ringOffset == ringOffset &&
      other.joinedAxis == joinedAxis;

  @override
  int get hashCode => Object.hash(
    strokeWidth,
    dashed,
    color,
    borderColor,
    borderRadius,
    ringColor,
    ringWidth,
    ringOffset,
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
      if (decoration.dashed) {
        final outline = Path()..addRRect(outer.deflate(width / 2));
        final paint = Paint()
          ..color = decoration.borderColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = width;
        for (final metric in outline.computeMetrics()) {
          for (double distance = 0; distance < metric.length; distance += 6) {
            canvas.drawPath(
              metric.extractPath(
                distance,
                math.min(distance + 3, metric.length),
              ),
              paint,
            );
          }
        }
      } else {
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
