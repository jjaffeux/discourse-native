import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'app_settings_controller.dart';

typedef ContentReadingLaneBuilder =
    Widget Function(BuildContext context, ContentReadingLaneGeometry lane);

class ContentSettingsScope extends InheritedNotifier<AppSettingsController> {
  const ContentSettingsScope({
    super.key,
    required AppSettingsController controller,
    required super.child,
  }) : super(notifier: controller);

  static bool limitContentSizeOf(BuildContext context) {
    return _controllerOf(context)?.limitContentSize ?? false;
  }

  static double appTextScaleFactorOf(BuildContext context) =>
      _controllerOf(context)?.textScaleFactor ?? 1.0;

  static AppSettingsController? _controllerOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<ContentSettingsScope>()
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
/// empty space still reach it. When enabled, only its children are constrained
/// to [maxWidth], independently of text zoom.
class ContentReadingLane extends StatelessWidget {
  const ContentReadingLane({
    super.key,
    this.basePadding = EdgeInsets.zero,
    this.widthLimit = maxWidth,
    required this.builder,
  });

  /// Maximum content width when the size limit is enabled.
  static const double maxWidth = 825;

  final EdgeInsets basePadding;
  final double widthLimit;
  final ContentReadingLaneBuilder builder;

  static ContentReadingLaneGeometry geometryFor(
    BuildContext context, {
    required double availableWidth,
    EdgeInsets basePadding = EdgeInsets.zero,
    double widthLimit = maxWidth,
  }) {
    final reserved = _ReadingLaneInsets.of(context);
    final contentWidth = math.max(
      0.0,
      availableWidth - reserved.horizontal - basePadding.horizontal,
    );
    final constrained =
        ContentSettingsScope.limitContentSizeOf(context) &&
        contentWidth.isFinite;
    final width = constrained
        ? math.min(math.min(widthLimit, maxWidth), contentWidth)
        : contentWidth;
    final extra = constrained ? contentWidth - width : 0.0;
    final leftInset = extra / 2;
    final rightInset = extra / 2;
    const alignment = Alignment.center;
    return ContentReadingLaneGeometry(
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
      ? ContentSettingsScope.appTextScaleFactorOf(context)
      : 1.0;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final lane = geometryFor(
          context,
          availableWidth: constraints.maxWidth,
          basePadding: basePadding,
          widthLimit: widthLimit,
        );
        return _ReadingLaneInsets(
          padding: EdgeInsets.zero,
          child: Builder(builder: (context) => builder(context, lane)),
        );
      },
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

/// Keeps a fixed sidebar in the reading lane while the adjacent page viewport
/// extends to the trailing edge. Descendant reading lanes inset their content by
/// the remaining outer margin, preserving the column widths and alignment.
class ContentReadingLaneWithSidebar extends StatelessWidget {
  const ContentReadingLaneWithSidebar({
    super.key,
    required this.sidebar,
    required this.sidebarWidth,
    required this.child,
    this.padding = EdgeInsets.zero,
  });

  final Widget sidebar;
  final double sidebarWidth;
  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) => ContentReadingLane(
    basePadding: padding,
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
class ContentReadingLaneBox extends StatelessWidget {
  const ContentReadingLaneBox({
    super.key,
    this.padding = EdgeInsets.zero,
    this.widthLimit = ContentReadingLane.maxWidth,
    required this.child,
  });

  final EdgeInsets padding;
  final double widthLimit;
  final Widget child;

  @override
  Widget build(BuildContext context) => ContentReadingLane(
    basePadding: padding,
    widthLimit: widthLimit,
    builder: (context, lane) => Padding(
      padding: lane.padding,
      child: SizedBox(width: double.infinity, child: child),
    ),
  );
}
