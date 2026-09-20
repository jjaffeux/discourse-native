import 'dart:math' as math;

import 'package:flutter/widgets.dart';

typedef DPageReadingLaneBuilder =
    Widget Function(BuildContext context, DPageReadingLaneGeometry lane);

@immutable
class DPageReadingLaneGeometry {
  const DPageReadingLaneGeometry({
    required this.width,
    required this.leftInset,
    required this.rightInset,
    required this.alignment,
    required this.padding,
  });

  /// The cross-axis width available to each item after [padding].
  final double width;

  /// Alignment space added outside the caller's base padding.
  final double leftInset;
  final double rightInset;

  /// Physical alignment for content with an existing limit below [width].
  final Alignment alignment;

  /// The caller's base padding plus the app-wide reading-lane insets.
  final EdgeInsets padding;
}

/// Computes the cross-axis padding for app content which scrolls beneath
/// full-width chrome.
///
/// The scroll viewport remains full width, so wheel and trackpad events in the
/// empty space still reach it. When enabled, only its children are constrained
/// to [maxWidth], independently of text zoom.
class DPageReadingLane extends StatelessWidget {
  const DPageReadingLane({
    super.key,
    this.basePadding = EdgeInsets.zero,
    this.widthLimit = maxWidth,
    this.limitContentSize,
    required this.builder,
  });

  /// Maximum content width when the size limit is enabled.
  static const double maxWidth = 825;

  final EdgeInsets basePadding;
  final double widthLimit;
  final bool? limitContentSize;
  final DPageReadingLaneBuilder builder;

  static DPageReadingLaneGeometry geometryFor(
    BuildContext context, {
    required double availableWidth,
    EdgeInsets basePadding = EdgeInsets.zero,
    double widthLimit = maxWidth,
    bool? limitContentSize,
  }) {
    final reserved = _ReadingLaneInsets.of(context);
    final contentWidth = math.max(
      0.0,
      availableWidth - reserved.horizontal - basePadding.horizontal,
    );
    final constrained =
        (limitContentSize ?? DPageContentSettings.limitOf(context)) &&
        contentWidth.isFinite;
    final width = constrained
        ? math.min(math.min(widthLimit, maxWidth), contentWidth)
        : contentWidth;
    final extra = constrained ? contentWidth - width : 0.0;
    final leftInset = extra / 2;
    final rightInset = extra / 2;
    const alignment = Alignment.center;
    return DPageReadingLaneGeometry(
      width: width,
      leftInset: leftInset + reserved.left,
      rightInset: rightInset + reserved.right,
      alignment: alignment,
      padding: basePadding.copyWith(
        left: basePadding.left + leftInset + reserved.left,
        right: basePadding.right + rightInset + reserved.right,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    ({double width, EdgeInsets reserved, bool limited})? previousInputs;
    Widget? child;
    return LayoutBuilder(
      builder: (context, constraints) {
        final inputs = (
          width: constraints.maxWidth,
          reserved: _ReadingLaneInsets.of(context),
          limited: limitContentSize ?? DPageContentSettings.limitOf(context),
        );
        // A retracting page header changes only the viewport height. Let the
        // child lay out again without replacing its scroll delegate each tick.
        // This cache is reset on widget updates; Builder retains the caller's
        // own inherited dependencies independently of the lane geometry.
        if (child != null && inputs == previousInputs) return child!;
        previousInputs = inputs;
        final lane = geometryFor(
          context,
          availableWidth: constraints.maxWidth,
          basePadding: basePadding,
          widthLimit: widthLimit,
          limitContentSize: limitContentSize,
        );
        return child = _ReadingLaneInsets(
          padding: EdgeInsets.zero,
          child: Builder(builder: (context) => builder(context, lane)),
        );
      },
    );
  }
}

/// Keeps a fixed sidebar in the reading lane while the adjacent page viewport
/// extends to the trailing edge. Descendant reading lanes inset their content by
/// the remaining outer margin, preserving the column widths and alignment.
class DPageReadingLaneWithSidebar extends StatelessWidget {
  const DPageReadingLaneWithSidebar({
    super.key,
    required this.sidebar,
    required this.sidebarWidth,
    required this.child,
    this.padding = EdgeInsets.zero,
    this.limitContentSize,
  });

  final Widget sidebar;
  final double sidebarWidth;
  final Widget child;
  final EdgeInsets padding;
  final bool? limitContentSize;

  @override
  Widget build(BuildContext context) => DPageReadingLane(
    basePadding: padding,
    limitContentSize: limitContentSize,
    builder: (context, lane) {
      final rtl = Directionality.of(context) == TextDirection.rtl;
      return Padding(
        padding: lane.padding.copyWith(
          left: rtl ? 0 : lane.padding.left,
          right: rtl ? lane.padding.right : 0,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(width: sidebarWidth, child: sidebar),
            Expanded(
              child: _ReadingLaneInsets(
                padding: EdgeInsets.only(
                  left: rtl ? lane.padding.left : 0,
                  right: rtl ? 0 : lane.padding.right,
                ),
                child: child,
              ),
            ),
          ],
        ),
      );
    },
  );
}

class _ReadingLaneInsets extends InheritedWidget {
  const _ReadingLaneInsets({required this.padding, required super.child});

  final EdgeInsets padding;

  static EdgeInsets of(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<_ReadingLaneInsets>()
          ?.padding ??
      EdgeInsets.zero;

  @override
  bool updateShouldNotify(_ReadingLaneInsets oldWidget) =>
      padding != oldWidget.padding;
}

/// Applies the same reading-lane geometry to a non-scrollable placeholder.
class DPageReadingLaneBox extends StatelessWidget {
  const DPageReadingLaneBox({
    super.key,
    this.padding = EdgeInsets.zero,
    this.limitContentSize,
    this.widthLimit = DPageReadingLane.maxWidth,
    required this.child,
  });

  final EdgeInsets padding;
  final double widthLimit;
  final bool? limitContentSize;
  final Widget child;

  @override
  Widget build(BuildContext context) => DPageReadingLane(
    basePadding: padding,
    limitContentSize: limitContentSize,
    widthLimit: widthLimit,
    builder: (context, lane) => Padding(
      padding: lane.padding,
      child: SizedBox(width: double.infinity, child: child),
    ),
  );
}

/// Width policy shared by a page and its reading lanes.
class DPageContentSettings extends InheritedWidget {
  const DPageContentSettings({
    super.key,
    required this.limitContentSize,
    required super.child,
  });
  final bool limitContentSize;
  static bool limitOf(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<DPageContentSettings>()
          ?.limitContentSize ??
      false;
  @override
  bool updateShouldNotify(DPageContentSettings oldWidget) =>
      limitContentSize != oldWidget.limitContentSize;
}
