import 'package:flutter/widgets.dart';

import '../foundation/icons/d_icon_data.dart';
import '../models/notification.dart';
import 'notification_types.dart';
import 'plugin_registry.dart';
import 'plugin_runtime.dart';
import 'plugin_ui_scope.dart';

/// A full application uses [PluginScope]. Standalone cooked fragments can use
/// this narrower scope without fabricating a plugin session merely to make a
/// nested quote inherit the same renderers.
class PluginRegistryScope extends InheritedWidget {
  const PluginRegistryScope({
    super.key,
    required this.registry,
    required super.child,
  });

  final PluginRegistry registry;

  static PluginRegistry? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<PluginRegistryScope>()
      ?.registry;

  @override
  bool updateShouldNotify(PluginRegistryScope oldWidget) =>
      !identical(registry, oldWidget.registry);
}

/// Core keeps the complete runtime graph private; plugin-owned UI state is
/// projected through [PluginUiScope] so a feature never receives the shell's
/// public surface merely to reach its own controller.
class PluginScope extends InheritedWidget {
  PluginScope({
    super.key,
    required PluginSession session,
    required this.registry,
    required Widget child,
    // Keep the public constructor name `session` while the capability-bearing
    // value itself remains inaccessible to descendants.
    // ignore: prefer_initializing_formals
  }) : _session = session,
       super(
         child: PluginServicesScope(directory: session, child: child),
       );

  final PluginSession _session;
  final PluginRegistry registry;

  ResolvedNotification resolveNotification(
    String siteUrl,
    DiscourseNotification notification,
  ) => _session.resolveNotification(registry, siteUrl, notification);

  static PluginScope of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<PluginScope>();
    assert(scope != null, 'No PluginScope found above this widget');
    return scope!;
  }

  static PluginScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<PluginScope>();

  @override
  bool updateShouldNotify(PluginScope oldWidget) =>
      !identical(_session, oldWidget._session) ||
      !identical(registry, oldWidget.registry);
}

/// Resolves server and contributor icon names through the installed catalog.
DIconData? pluginIconNamed(BuildContext context, String? name) =>
    (PluginRegistryScope.maybeOf(context) ??
            PluginScope.maybeOf(context)?.registry ??
            PluginRegistry.empty)
        .findIconNamed(name);
