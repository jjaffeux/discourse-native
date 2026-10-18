import 'package:flutter/widgets.dart';

import '../models/forum_workspace.dart';
import '../plugin_api/plugin_scope.dart';
import 'header_preferences.dart';
import 'shell_controller.dart';

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
           child: _ShellControllerIdentity(
             controller: controller,
             child: HeaderPreferencesHost(child: child),
           ),
         ),
       );

  static ShellController of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<ShellScope>();
    assert(scope != null, 'No ShellScope found above this widget');
    return scope!.notifier!;
  }

  static ShellController read(BuildContext context) {
    final scope = context.getInheritedWidgetOfExactType<ShellScope>();
    assert(scope != null, 'No ShellScope found above this widget');
    return scope!.notifier!;
  }

  static ShellController identityOf(BuildContext context) =>
      _ShellControllerIdentity.of(context);

  static ShellController? maybeIdentityOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<_ShellControllerIdentity>()
      ?.controller;

  static ShellController? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ShellScope>()?.notifier;

  static ShellController? maybeRead(BuildContext context) =>
      context.getInheritedWidgetOfExactType<ShellScope>()?.notifier;
}

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

/// The visible document, independent of which panel currently has input focus.
class ForumTabScope extends InheritedWidget {
  const ForumTabScope({
    super.key,
    required this.tabId,
    required this.panel,
    required super.child,
  });

  final String? tabId;
  final ForumPanel panel;

  static String? idOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ForumTabScope>()?.tabId;

  static ForumPanel? panelOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ForumTabScope>()?.panel;

  static ShellTabContext tabOf(BuildContext context) {
    final shell = ShellScope.read(context);
    final scope = context.dependOnInheritedWidgetOfExactType<ForumTabScope>();
    return scope == null
        ? shell.focusedTabContext
        : shell.tabContext(scope.tabId);
  }

  @override
  bool updateShouldNotify(ForumTabScope oldWidget) =>
      tabId != oldWidget.tabId || panel != oldWidget.panel;
}

class ForumTabSelector<T> extends StatefulWidget {
  const ForumTabSelector({
    super.key,
    required this.select,
    required this.builder,
    this.child,
  });

  final T Function(ShellController shell, ShellTabContext tab) select;
  final ValueWidgetBuilder<T> builder;
  final Widget? child;

  @override
  State<ForumTabSelector<T>> createState() => _ForumTabSelectorState<T>();
}

class _ForumTabSelectorState<T> extends State<ForumTabSelector<T>> {
  ShellController? _shell;
  String? _tabId;
  bool _scoped = false;
  late T _value;

  ShellTabContext _resolve() =>
      _scoped ? _shell!.tabContext(_tabId) : _shell!.focusedTabContext;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final shell = ShellScope.identityOf(context);
    final scope = context.dependOnInheritedWidgetOfExactType<ForumTabScope>();
    _scoped = scope != null;
    _tabId = scope?.tabId;
    if (!identical(shell, _shell)) {
      _shell?.removeListener(_select);
      _shell = shell..addListener(_select);
    }
    _value = widget.select(shell, _resolve());
  }

  @override
  void didUpdateWidget(ForumTabSelector<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    _value = widget.select(_shell!, _resolve());
  }

  void _select() {
    final next = widget.select(_shell!, _resolve());
    if (next == _value) return;
    setState(() => _value = next);
  }

  @override
  Widget build(BuildContext context) =>
      widget.builder(context, _value, widget.child);

  @override
  void dispose() {
    _shell?.removeListener(_select);
    super.dispose();
  }
}
