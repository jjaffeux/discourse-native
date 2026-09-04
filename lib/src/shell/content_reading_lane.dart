import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../models/app_settings.dart';
import 'app_settings_controller.dart';

typedef ContentReadingLaneBuilder =
    Widget Function(BuildContext context, ContentReadingLaneGeometry lane);

class ContentAlignmentScope extends InheritedNotifier<AppSettingsController> {
  const ContentAlignmentScope({
    super.key,
    required AppSettingsController controller,
    required super.child,
  }) : super(notifier: controller);

  static ContentAlignment of(BuildContext context) {
    return _controllerOf(context)?.contentAlignment ?? ContentAlignment.center;
  }

  static double appTextScaleFactorOf(BuildContext context) =>
      _controllerOf(context)?.textScaleFactor ?? 1.0;

  static AppSettingsController? _controllerOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<ContentAlignmentScope>()
      ?.notifier;
}

@immutable
class ContentReadingLaneGeometry {
  const ContentReadingLaneGeometry({
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
/// empty space still reach it. Only its children are constrained to the
/// text-zoom-adjusted [maxWidth].
class ContentReadingLane extends StatelessWidget {
  const ContentReadingLane({
    super.key,
    this.basePadding = EdgeInsets.zero,
    required this.builder,
  });

  /// Reading-lane width at 100% app text zoom.
  static const double maxWidth = 825;

  final EdgeInsets basePadding;
  final ContentReadingLaneBuilder builder;

  static ContentReadingLaneGeometry geometryFor(
    BuildContext context, {
    required double availableWidth,
    EdgeInsets basePadding = EdgeInsets.zero,
  }) {
    final contentWidth = math.max(0.0, availableWidth - basePadding.horizontal);
    final constrained = _usesDesktopLane && contentWidth.isFinite;
    final appTextScaleFactor = constrained
        ? ContentAlignmentScope.appTextScaleFactorOf(context)
        : 1.0;
    final width = constrained
        ? math.min(maxWidth * appTextScaleFactor, contentWidth)
        : contentWidth;
    final extra = constrained ? contentWidth - width : 0.0;
    final (leftInset, rightInset, alignment) = constrained
        ? switch (ContentAlignmentScope.of(context)) {
            ContentAlignment.left => (0.0, extra, Alignment.centerLeft),
            ContentAlignment.center => (extra / 2, extra / 2, Alignment.center),
            ContentAlignment.right => (extra, 0.0, Alignment.centerRight),
          }
        : (0.0, 0.0, Alignment.center);
    return ContentReadingLaneGeometry(
      width: width,
      leftInset: leftInset,
      rightInset: rightInset,
      alignment: alignment,
      padding: basePadding.copyWith(
        left: basePadding.left + leftInset,
        right: basePadding.right + rightInset,
      ),
    );
  }

  /// Converts a physical width governing reading-lane content to its
  /// 100%-text-size equivalent for responsive breakpoint decisions.
  ///
  /// The width is unchanged on mobile, web, and for unbounded constraints.
  static double breakpointWidthOf(BuildContext context, double width) {
    return width / _desktopAppTextScaleFactorOf(context, width);
  }

  static double _desktopAppTextScaleFactorOf(
    BuildContext context,
    double width,
  ) => _usesDesktopLane && width.isFinite
      ? ContentAlignmentScope.appTextScaleFactorOf(context)
      : 1.0;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => builder(
        context,
        geometryFor(
          context,
          availableWidth: constraints.maxWidth,
          basePadding: basePadding,
        ),
      ),
    );
  }

  static bool get _usesDesktopLane =>
      !kIsWeb &&
      switch (defaultTargetPlatform) {
        TargetPlatform.macOS ||
        TargetPlatform.linux ||
        TargetPlatform.windows => true,
        TargetPlatform.android ||
        TargetPlatform.fuchsia ||
        TargetPlatform.iOS => false,
      };
}

/// Applies the same reading-lane geometry to a non-scrollable placeholder.
class ContentReadingLaneBox extends StatelessWidget {
  const ContentReadingLaneBox({
    super.key,
    this.padding = EdgeInsets.zero,
    required this.child,
  });

  final EdgeInsets padding;
  final Widget child;

  @override
  Widget build(BuildContext context) => ContentReadingLane(
    basePadding: padding,
    builder: (context, lane) => Padding(
      padding: lane.padding,
      child: SizedBox(width: double.infinity, child: child),
    ),
  );
}
