import 'package:discourse_native/src/diagnostics/diagnostics_controller.dart';
import 'package:discourse_native/src/plugins/resenha/resenha_diagnostics.dart';
import 'package:flutter/widgets.dart';

/// Makes the app-owned diagnostics controller available without subscribing
/// the surrounding shell to high-frequency event changes.
final class DiagnosticsScope extends InheritedWidget {
  const DiagnosticsScope({
    required this.controller,
    this.resenhaController,
    required super.child,
    super.key,
  });

  final DiagnosticsController controller;
  final ResenhaDiagnosticsController? resenhaController;

  static DiagnosticsController read(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<DiagnosticsScope>();
    assert(scope != null, 'No DiagnosticsScope found above this context.');
    return scope!.controller;
  }

  static DiagnosticsController? maybeRead(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<DiagnosticsScope>()
      ?.controller;

  static ResenhaDiagnosticsController? maybeReadResenha(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<DiagnosticsScope>()
          ?.resenhaController;

  @override
  bool updateShouldNotify(DiagnosticsScope oldWidget) =>
      !identical(controller, oldWidget.controller) ||
      !identical(resenhaController, oldWidget.resenhaController);
}
