import 'package:flutter/widgets.dart';

import 'plugin_registry.dart';
import 'plugin_runtime.dart';

/// Carries render-only plugin contributions through nested content.
///
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

/// The installed plugin graph available to extension widgets.
///
/// Core navigation continues to live in `ShellScope`; plugin-owned state is
/// resolved here through stable service keys so a feature does not need the
/// shell's entire public surface merely to reach its own controller.
class PluginScope extends InheritedWidget {
  PluginScope({
    super.key,
    required this.session,
    required this.registry,
    T Function<T extends Object>(PluginServiceKey<T> key)? resolveService,
    T? Function<T extends Object>(PluginServiceKey<T> key)? resolveMaybeService,
    required super.child,
  }) : _resolveService = resolveService ?? session.require,
       _resolveMaybeService = resolveMaybeService ?? session.maybeService;

  final PluginSession session;
  final PluginRegistry registry;
  final T Function<T extends Object>(PluginServiceKey<T> key) _resolveService;
  final T? Function<T extends Object>(PluginServiceKey<T> key)
  _resolveMaybeService;

  T service<T extends Object>(PluginServiceKey<T> key) =>
      _resolveService<T>(key);

  T? maybeService<T extends Object>(PluginServiceKey<T> key) =>
      _resolveMaybeService<T>(key);

  static PluginScope of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<PluginScope>();
    assert(scope != null, 'No PluginScope found above this widget');
    return scope!;
  }

  static PluginScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<PluginScope>();

  static T require<T extends Object>(
    BuildContext context,
    PluginServiceKey<T> key,
  ) => of(context).service(key);

  static T? optional<T extends Object>(
    BuildContext context,
    PluginServiceKey<T> key,
  ) => maybeOf(context)?.maybeService(key);

  @override
  bool updateShouldNotify(PluginScope oldWidget) =>
      !identical(session, oldWidget.session) ||
      !identical(registry, oldWidget.registry);
}

/// Rebuilds only when a selected value from one plugin service changes.
class PluginServiceSelector<S extends Listenable, T> extends StatefulWidget {
  const PluginServiceSelector({
    super.key,
    required this.service,
    required this.select,
    required this.builder,
    this.child,
  });

  final PluginServiceKey<S> service;
  final T Function(S value) select;
  final ValueWidgetBuilder<T> builder;
  final Widget? child;

  @override
  State<PluginServiceSelector<S, T>> createState() =>
      _PluginServiceSelectorState<S, T>();
}

class _PluginServiceSelectorState<S extends Listenable, T>
    extends State<PluginServiceSelector<S, T>> {
  S? _service;
  late T _value;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final service = PluginScope.require(context, widget.service);
    if (identical(service, _service)) return;

    _service?.removeListener(_select);
    _service = service..addListener(_select);
    _value = widget.select(service);
  }

  @override
  void didUpdateWidget(PluginServiceSelector<S, T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.service != widget.service) {
      _service?.removeListener(_select);
      _service = PluginScope.require(context, widget.service)
        ..addListener(_select);
    }
    _value = widget.select(_service!);
  }

  void _select() {
    final next = widget.select(_service!);
    if (next == _value) return;
    setState(() => _value = next);
  }

  @override
  Widget build(BuildContext context) =>
      widget.builder(context, _value, widget.child);

  @override
  void dispose() {
    _service?.removeListener(_select);
    super.dispose();
  }
}
