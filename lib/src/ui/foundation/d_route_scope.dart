import 'package:flutter/widgets.dart';

/// Gives a route's page the route it belongs to without rebuilding the page's
/// widgets when that route's status changes.
///
/// [ModalRoute.of] makes its caller depend on every status change of its
/// route, so a widget that only checks [ModalRoute.isCurrent] from a callback
/// is rebuilt, with everything it builds, each time a sheet covers or uncovers
/// its page. Below this scope [routeOf] answers with the route alone, and
/// [statusOf] announces each status change to listeners instead.
///
/// Place it at the root of a route's page. Route pages are siblings in their
/// navigator's overlay, so the nearest scope always belongs to the caller's
/// own route.
class DRouteScope extends StatefulWidget {
  const DRouteScope({super.key, required this.child});

  final Widget child;

  /// The route [context] belongs to. Under a [DRouteScope], [context] is
  /// rebuilt only if it moves to another route; elsewhere this is
  /// [ModalRoute.of].
  static ModalRoute<Object?>? routeOf(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<_DRouteScope>();
    return scope == null ? ModalRoute.of(context) : scope.route;
  }

  /// Notifies as the status of [routeOf]'s route changes, in the frame that
  /// [ModalRoute.of] would rebuild its dependents. Null outside a
  /// [DRouteScope], where [routeOf] rebuilds its caller instead.
  static Listenable? statusOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_DRouteScope>()?.status;

  @override
  State<DRouteScope> createState() => _DRouteScopeState();
}

class _DRouteScopeState extends State<DRouteScope> {
  final _status = _RouteStatus();
  ModalRoute<Object?>? _route;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (identical(route, _route)) {
      _status.changed();
    } else {
      _route = route;
    }
  }

  @override
  void dispose() {
    _status.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      _DRouteScope(route: _route, status: _status, child: widget.child);
}

class _RouteStatus extends ChangeNotifier {
  void changed() => notifyListeners();
}

class _DRouteScope extends InheritedWidget {
  const _DRouteScope({
    required this.route,
    required this.status,
    required super.child,
  });

  final ModalRoute<Object?>? route;
  final Listenable status;

  @override
  bool updateShouldNotify(_DRouteScope oldWidget) =>
      !identical(route, oldWidget.route);
}
