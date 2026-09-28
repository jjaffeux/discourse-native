import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Live inherited values shared by route-owned components.
@immutable
class DOverlayEnvironment {
  const DOverlayEnvironment({
    required this.theme,
    required this.mediaQuery,
    required this.directionality,
  });

  factory DOverlayEnvironment.capture(BuildContext context) {
    final media = MediaQuery.of(context);
    final keyboard = context
        .dependOnInheritedWidgetOfExactType<DOverlayKeyboardMetrics>();
    return DOverlayEnvironment(
      theme: Theme.of(context),
      mediaQuery: keyboard == null
          ? media
          : media.copyWith(
              viewInsets: keyboard.viewInsets,
              padding: keyboard.padding,
            ),
      directionality: Directionality.of(context),
    );
  }

  final ThemeData theme;
  final MediaQueryData mediaQuery;
  final TextDirection directionality;

  Widget wrap(Widget child) => Theme(
    data: theme,
    child: MediaQuery(
      data: mediaQuery,
      child: Directionality(textDirection: directionality, child: child),
    ),
  );

  @override
  bool operator ==(Object other) =>
      other is DOverlayEnvironment &&
      other.theme == theme &&
      other.mediaQuery == mediaQuery &&
      other.directionality == directionality;

  @override
  int get hashCode => Object.hash(theme, mediaQuery, directionality);
}

/// Live keyboard metrics for overlays opened from a retained surface.
class DOverlayKeyboardMetrics extends InheritedWidget {
  const DOverlayKeyboardMetrics({
    super.key,
    required this.viewInsets,
    required this.padding,
    required super.child,
  });

  final EdgeInsets viewInsets;
  final EdgeInsets padding;

  @override
  bool updateShouldNotify(DOverlayKeyboardMetrics oldWidget) =>
      viewInsets != oldWidget.viewInsets || padding != oldWidget.padding;
}

typedef DOverlayPageBuilder<T, Configuration extends Object> =
    Widget Function(
      BuildContext context,
      Configuration configuration,
      Animation<double> animation,
    );

/// Shared authorized-pop and live-environment route owner for overlays.
///
/// Components retain their own visuals and interactions in [pageBuilder]. The
/// route prevents uncoordinated system pops, reports them through
/// [onPopBlocked], and remains mounted for its full reverse transition.
class DOverlayRoute<T, Configuration extends Object> extends PopupRoute<T> {
  static final _modalCoverCounts = Expando<ValueNotifier<int>>();

  /// Modal overlays covering this route, including their closing transitions.
  static ValueListenable<int> modalCoverCountOf(BuildContext context) {
    final route = ModalRoute.of(context);
    if (route == null) return const AlwaysStoppedAnimation(0);
    return _modalCoverCounts[route] ??= ValueNotifier(0);
  }

  DOverlayRoute({
    super.settings,
    super.requestFocus = true,
    super.traversalEdgeBehavior = TraversalEdgeBehavior.closedLoop,
    super.directionalTraversalEdgeBehavior = TraversalEdgeBehavior.closedLoop,
    required this.environment,
    required this.configuration,
    required this.pageBuilder,
    required this.barrierLabelOf,
    this.modalOf,
    required this.onPopBlocked,
    required this.transitionDuration,
    required this.reverseTransitionDuration,
  });

  final ValueListenable<DOverlayEnvironment?> environment;
  final ValueListenable<Configuration?> configuration;
  final DOverlayPageBuilder<T, Configuration> pageBuilder;
  final String Function(Configuration configuration) barrierLabelOf;
  final bool Function(Configuration configuration)? modalOf;
  final VoidCallback onPopBlocked;

  @override
  final Duration transitionDuration;
  @override
  final Duration reverseTransitionDuration;

  /// Optional gesture physics for the next authorized closing transition.
  /// Setting this does not request or authorize dismissal.
  Simulation? Function()? reverseSimulationBuilder;

  @override
  Simulation? createSimulation({required bool forward}) =>
      (!forward ? reverseSimulationBuilder?.call() : null) ??
      super.createSimulation(forward: forward);

  bool _authorized = false;
  bool _wasCurrentWhenAuthorized = false;
  Route<dynamic>? _previousRoute;
  ValueNotifier<int>? _coverCount;

  void _syncCoverage() {
    final previous = _previousRoute;
    final next = previous != null && configuration.value != null && modal
        ? (_modalCoverCounts[previous] ??= ValueNotifier(0))
        : null;
    if (identical(next, _coverCount)) return;
    _coverCount?.value--;
    _coverCount = next;
    _coverCount?.value++;
  }

  @override
  void install() {
    super.install();
    configuration.addListener(_syncCoverage);
  }

  @override
  void didChangePrevious(Route<dynamic>? previousRoute) {
    super.didChangePrevious(previousRoute);
    _previousRoute = previousRoute;
    _syncCoverage();
  }

  @override
  void dispose() {
    configuration.removeListener(_syncCoverage);
    _coverCount?.value--;
    _coverCount = null;
    super.dispose();
  }

  Configuration get currentConfiguration => configuration.value!;
  bool get wasCurrentWhenAuthorized => _wasCurrentWhenAuthorized;

  bool get modal => modalOf?.call(currentConfiguration) ?? true;

  @override
  Widget buildModalBarrier() => ValueListenableBuilder<Configuration?>(
    valueListenable: configuration,
    builder: (context, config, _) =>
        modal ? super.buildModalBarrier() : const SizedBox.shrink(),
  );

  @override
  String get barrierLabel => barrierLabelOf(currentConfiguration);

  @override
  Color? get barrierColor => Colors.transparent;

  @override
  bool get barrierDismissible => false;

  @override
  RoutePopDisposition get popDisposition =>
      _authorized ? RoutePopDisposition.pop : RoutePopDisposition.doNotPop;

  void authorizePop([T? result]) {
    if (_authorized || !isActive) return;
    _authorized = true;
    _wasCurrentWhenAuthorized = isCurrent;
    if (isCurrent) {
      navigator?.pop<T>(result);
    } else {
      navigator?.removeRoute(this, result);
    }
  }

  @override
  void onPopInvokedWithResult(bool didPop, T? result) {
    super.onPopInvokedWithResult(didPop, result);
    if (!didPop) onPopBlocked();
  }

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) => ValueListenableBuilder<Configuration?>(
    valueListenable: configuration,
    builder: (context, config, _) =>
        ValueListenableBuilder<DOverlayEnvironment?>(
          valueListenable: environment,
          builder: (context, value, _) =>
              (value ?? DOverlayEnvironment.capture(context)).wrap(
                pageBuilder(context, config!, animation),
              ),
        ),
  );

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) => child;
}
