import 'package:discourse_native/src/diagnostics/diagnostics_controller.dart';
import 'package:discourse_native/src/plugin_api/site_plugin_api.dart';
import 'package:flutter/widgets.dart';

/// Makes the app-owned diagnostics controller available without subscribing
/// the surrounding shell to high-frequency event changes.
final class DiagnosticsScope extends InheritedWidget {
  const DiagnosticsScope({
    required this.controller,
    this.plugins = const [],
    required super.child,
    super.key,
  });

  final DiagnosticsController controller;
  final List<DiagnosticsPlugin> plugins;

  static DiagnosticsController read(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<DiagnosticsScope>();
    assert(scope != null, 'No DiagnosticsScope found above this context.');
    return scope!.controller;
  }

  static DiagnosticsController? maybeRead(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<DiagnosticsScope>()
      ?.controller;

  static List<DiagnosticsPlugin> pluginsOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<DiagnosticsScope>()?.plugins ??
      const [];

  @override
  bool updateShouldNotify(DiagnosticsScope oldWidget) =>
      !identical(controller, oldWidget.controller) ||
      !identical(plugins, oldWidget.plugins);
}
