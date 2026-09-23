import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'app_settings_controller.dart';
import 'shell_scope.dart';

typedef ContentReadingLaneBuilder = DPageReadingLaneBuilder;
typedef ContentReadingLaneGeometry = DPageReadingLaneGeometry;

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

/// Connects the app's width preference to the Native page reading lane.
class ContentReadingLane extends StatelessWidget {
  const ContentReadingLane({
    super.key,
    this.basePadding = EdgeInsets.zero,
    this.widthLimit = maxWidth,
    required this.builder,
  });
  static const double maxWidth = DPageReadingLane.maxWidth;
  final EdgeInsets basePadding;
  final double widthLimit;
  final ContentReadingLaneBuilder builder;

  static ContentReadingLaneGeometry geometryFor(
    BuildContext context, {
    required double availableWidth,
    EdgeInsets basePadding = EdgeInsets.zero,
    double widthLimit = maxWidth,
  }) => DPageReadingLane.geometryFor(
    context,
    availableWidth: availableWidth,
    basePadding: basePadding,
    widthLimit: widthLimit,
    limitContentSize: ContentSettingsScope.limitContentSizeOf(context),
  );

  @override
  Widget build(BuildContext context) => DPageReadingLane(
    basePadding: basePadding,
    widthLimit: widthLimit,
    builder: (context, lane) => ForumTabScope.idOf(context) == null
        ? builder(context, lane)
        : ForumTabScope.read(context, (_) => builder(context, lane)),
    limitContentSize: ContentSettingsScope.limitContentSizeOf(context),
  );

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

class ContentReadingLaneWithSidebar extends StatelessWidget {
  const ContentReadingLaneWithSidebar({
    super.key,
    required this.sidebar,
    required this.sidebarWidth,
    required this.child,
    this.padding = EdgeInsets.zero,
  });
  final Widget child;
  final EdgeInsets padding;
  final Widget sidebar;
  final double sidebarWidth;
  @override
  Widget build(BuildContext context) => DPageReadingLaneWithSidebar(
    sidebar: sidebar,
    sidebarWidth: sidebarWidth,
    padding: padding,
    limitContentSize: ContentSettingsScope.limitContentSizeOf(context),
    child: child,
  );
}

class ContentReadingLaneBox extends StatelessWidget {
  const ContentReadingLaneBox({
    super.key,
    required this.child,
    this.padding = EdgeInsets.zero,
    this.widthLimit = ContentReadingLane.maxWidth,
  });
  final Widget child;
  final EdgeInsets padding;
  final double widthLimit;
  @override
  Widget build(BuildContext context) => DPageReadingLaneBox(
    padding: padding,
    widthLimit: widthLimit,
    limitContentSize: ContentSettingsScope.limitContentSizeOf(context),
    child: child,
  );
}
