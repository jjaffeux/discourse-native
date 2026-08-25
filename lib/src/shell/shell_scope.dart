import 'package:flutter/widgets.dart';

import '../plugins/plugin_scope.dart';
import 'shell_controller.dart';

/// Makes the [ShellController] available to the widgets below it.
///
/// Widgets normally use [read] for commands and [ShellSelector] for rendered
/// state. [of] remains available for the rare region that deliberately depends
/// on every shell change.
class ShellScope extends InheritedNotifier<ShellController> {
  ShellScope({
    super.key,
    required ShellController controller,
    required Widget child,
  }) : super(
         notifier: controller,
         child: PluginScope(
           session: controller.pluginSession,
           registry: controller.plugins.registry,
           resolveService: controller.pluginService,
           child: _ShellControllerIdentity(
             controller: controller,
             child: child,
           ),
         ),
       );

  static ShellController of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<ShellScope>();
    assert(scope != null, 'No ShellScope found above this widget');
    return scope!.notifier!;
  }

  /// The controller without subscribing [context] to its notifications.
  static ShellController read(BuildContext context) {
    final scope = context.getInheritedWidgetOfExactType<ShellScope>();
    assert(scope != null, 'No ShellScope found above this widget');
    return scope!.notifier!;
  }

  /// Subscribes only to controller replacement, not controller notifications.
  ///
  /// State owners whose callbacks capture a [ShellController] use this to
  /// replace those callbacks when the app replaces its dependency graph,
  /// without rebuilding for every ordinary shell state change.
  static ShellController identityOf(BuildContext context) =>
      _ShellControllerIdentity.of(context);

  /// The controller identity without subscribing to ordinary shell changes,
  /// or null for cooked fragments rendered outside the application shell.
  static ShellController? maybeIdentityOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<_ShellControllerIdentity>()
      ?.controller;

  /// The controller, or null where the shell is not an ancestor — widgets that
  /// also render outside it, such as a quote in a test.
  static ShellController? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ShellScope>()?.notifier;

  /// The controller without subscribing [context], or null outside the shell.
  static ShellController? maybeRead(BuildContext context) =>
      context.getInheritedWidgetOfExactType<ShellScope>()?.notifier;
}

/// Rebuilds only when the selected part of the shell changes.
///
/// Unlike [ShellScope.of], this listens to the controller directly and compares
/// the selected value before rebuilding. The private identity scope still
/// updates the subscription if an ancestor supplies a different controller.
class ShellSelector<T> extends StatefulWidget {
  const ShellSelector({
    super.key,
    required this.select,
    required this.builder,
    this.child,
  });

  final T Function(ShellController controller) select;
  final ValueWidgetBuilder<T> builder;
  final Widget? child;

  @override
  State<ShellSelector<T>> createState() => _ShellSelectorState<T>();
}

class _ShellSelectorState<T> extends State<ShellSelector<T>> {
  ShellController? _controller;
  late T _value;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final controller = _ShellControllerIdentity.of(context);
    if (identical(controller, _controller)) return;

    _controller?.removeListener(_select);
    _controller = controller..addListener(_select);
    _value = widget.select(controller);
  }

  @override
  void didUpdateWidget(ShellSelector<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    _value = widget.select(_controller!);
  }

  void _select() {
    final next = widget.select(_controller!);
    if (next == _value) return;
    setState(() => _value = next);
  }

  @override
  Widget build(BuildContext context) =>
      widget.builder(context, _value, widget.child);

  @override
  void dispose() {
    _controller?.removeListener(_select);
    super.dispose();
  }
}

class _ShellControllerIdentity extends InheritedWidget {
  const _ShellControllerIdentity({
    required this.controller,
    required super.child,
  });

  final ShellController controller;

  static ShellController of(BuildContext context) {
    final identity = context
        .dependOnInheritedWidgetOfExactType<_ShellControllerIdentity>();
    assert(identity != null, 'No ShellScope found above this widget');
    return identity!.controller;
  }

  @override
  bool updateShouldNotify(_ShellControllerIdentity oldWidget) =>
      !identical(controller, oldWidget.controller);
}
