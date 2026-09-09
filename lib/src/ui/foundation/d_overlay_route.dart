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

  factory DOverlayEnvironment.capture(BuildContext context) =>
      DOverlayEnvironment(
        theme: Theme.of(context),
        mediaQuery: MediaQuery.of(context),
        directionality: Directionality.of(context),
      );

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

typedef DOverlayPageBuilder<T, Configuration extends Object> =
    Widget Function(
      BuildContext context,
      Configuration configuration,
      Animation<double> animation,
    );

/// Shared authorized-pop and live-environment route owner for modal surfaces.
///
/// Components retain their own visuals and interactions in [pageBuilder]. The
/// route prevents uncoordinated system pops, reports them through
/// [onPopBlocked], and remains mounted for its full reverse transition.
class DOverlayRoute<T, Configuration extends Object> extends PopupRoute<T> {
  DOverlayRoute({
    super.settings,
    super.requestFocus = true,
    super.traversalEdgeBehavior = TraversalEdgeBehavior.closedLoop,
    super.directionalTraversalEdgeBehavior = TraversalEdgeBehavior.closedLoop,
    required this.environment,
    required this.configuration,
    required this.pageBuilder,
    required this.barrierLabelOf,
    required this.onPopBlocked,
    required this.transitionDuration,
    required this.reverseTransitionDuration,
  });

  final ValueListenable<DOverlayEnvironment?> environment;
  final ValueListenable<Configuration?> configuration;
  final DOverlayPageBuilder<T, Configuration> pageBuilder;
  final String Function(Configuration configuration) barrierLabelOf;
  final VoidCallback onPopBlocked;

  @override
  final Duration transitionDuration;
  @override
  final Duration reverseTransitionDuration;

  bool _authorized = false;
  bool _wasCurrentWhenAuthorized = false;

  Configuration get currentConfiguration => configuration.value!;
  bool get wasCurrentWhenAuthorized => _wasCurrentWhenAuthorized;

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
