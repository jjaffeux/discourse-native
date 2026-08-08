import 'package:discourse_native/src/diagnostics/diagnostics_controller.dart';
import 'package:flutter/widgets.dart';

/// Makes the app-owned diagnostics controller available without subscribing
/// the surrounding shell to high-frequency event changes.
final class DiagnosticsScope extends InheritedWidget {
  const DiagnosticsScope({
    required this.controller,
    required super.child,
    super.key,
  });

  final DiagnosticsController controller;

  static DiagnosticsController read(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<DiagnosticsScope>();
    assert(scope != null, 'No DiagnosticsScope found above this context.');
    return scope!.controller;
  }

  static DiagnosticsController? maybeRead(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<DiagnosticsScope>()
      ?.controller;

  @override
  bool updateShouldNotify(DiagnosticsScope oldWidget) =>
      !identical(controller, oldWidget.controller);
}
