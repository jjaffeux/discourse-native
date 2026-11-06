import 'dart:collection';
import 'dart:ui' show ViewFocusEvent;

import 'package:flutter/widgets.dart';

/// Forwards the binding events overlay triggers react to (app lifecycle,
/// view focus and metrics) through one [WidgetsBindingObserver].
///
/// A topic list mounts and unmounts dozens of tooltips, hover cards and
/// popovers per row. Registering each with [WidgetsBinding.addObserver] made
/// every unmount search the binding's list of observers, and every metrics
/// change call each of them. This set adds and removes in constant time.
final class DOverlayObservers with WidgetsBindingObserver {
  DOverlayObservers._();

  static final _instance = DOverlayObservers._();
  static bool _registered = false;
  static final _observers = LinkedHashSet<WidgetsBindingObserver>.identity();

  static void add(WidgetsBindingObserver observer) {
    if (!_registered) {
      _registered = true;
      WidgetsBinding.instance.addObserver(_instance);
    }
    _observers.add(observer);
  }

  static void remove(WidgetsBindingObserver observer) =>
      _observers.remove(observer);

  /// Calls [event] on each observer registered when the event arrived and
  /// still registered when its turn comes.
  static void _forward(void Function(WidgetsBindingObserver) event) {
    for (final observer in _observers.toList(growable: false)) {
      if (_observers.contains(observer)) event(observer);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) =>
      _forward((observer) => observer.didChangeAppLifecycleState(state));

  @override
  void didChangeViewFocus(ViewFocusEvent event) =>
      _forward((observer) => observer.didChangeViewFocus(event));

  @override
  void didChangeMetrics() =>
      _forward((observer) => observer.didChangeMetrics());
}
