part of 'd_sheet.dart';

typedef _DSheetSwipeExitGeometry = ({
  double origin,
  double curve,
  _DSheetDismissSimulation simulation,
});

typedef _DSheetMenuExitGeometry = ({
  double origin,
  double curve,
  double animationOrigin,
  double keyboard,
  double safeBottom,
  double heightOffset,
});

class _DSheetExitLifecycle<Geometry> {
  Geometry? geometry;
  DOverlayRoute<dynamic, Object>? _route;
  Simulation? Function()? _builder;

  DOverlayRoute<dynamic, Object>? get route => _route;

  void attach(
    DOverlayRoute<dynamic, Object>? route,
    Simulation? Function() builder,
  ) {
    detach();
    _route = route;
    _builder = builder;
    route?.reverseSimulationBuilder = builder;
  }

  void detach() {
    if (_route?.reverseSimulationBuilder == _builder) {
      _route?.reverseSimulationBuilder = null;
    }
    _builder = null;
    _route = null;
  }

  void releaseAfterRestore(TickerFuture restoration) {
    final pending = _builder;
    restoration.whenCompleteOrCancel(() {
      if (geometry == null && _builder == pending) detach();
    });
  }
}

mixin _DSheetKeyboardCoverRefresh<T extends StatefulWidget> on State<T> {
  ValueListenable<int>? _keyboardCover;
  bool _wasKeyboardCovered = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final cover = DOverlayRoute.modalCoverCountOf(context);
    if (!identical(cover, _keyboardCover)) {
      _keyboardCover?.removeListener(_keyboardCoverChanged);
      _keyboardCover = cover..addListener(_keyboardCoverChanged);
    }
    _keyboardCoverChanged();
  }

  void _keyboardCoverChanged() {
    if (!mounted || ModalRoute.of(context)?.isActive == false) return;
    if ((_keyboardCover?.value ?? 0) > 0 ||
        ModalRoute.of(context)?.isCurrent == false) {
      _wasKeyboardCovered = true;
    } else if (_wasKeyboardCovered) {
      _wasKeyboardCovered = false;
      // Child routes can change the keyboard while this sheet is covered.
      unawaited(_DSheetKeyboardTransitions.refresh());
    }
  }

  @override
  void dispose() {
    _keyboardCover?.removeListener(_keyboardCoverChanged);
    super.dispose();
  }
}
