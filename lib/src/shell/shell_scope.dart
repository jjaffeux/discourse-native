import 'package:flutter/widgets.dart';

import '../models/forum_workspace.dart';
import '../plugin_api/plugin_scope.dart';
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
             child: child,
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
  String? _tabId;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final controller = _ShellControllerIdentity.of(context);
    final tabId = ForumTabScope.idOf(context);
    if (identical(controller, _controller) && tabId == _tabId) return;
    _tabId = tabId;

    _controller?.removeListener(_select);
    _controller = controller..addListener(_select);
    _value = controller.readTab(_tabId, () => widget.select(controller));
  }

  @override
  void didUpdateWidget(ShellSelector<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    _value = _controller!.readTab(_tabId, () => widget.select(_controller!));
  }

  void _select() {
    final next = _controller!.readTab(
      _tabId,
      () => widget.select(_controller!),
    );
    if (next == _value) return;
    setState(() => _value = next);
  }

  @override
  Widget build(BuildContext context) => _controller!.readTab(
    _tabId,
    () => widget.builder(context, _value, widget.child),
  );

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

  static T read<T>(BuildContext context, T Function(ShellController) select) {
    final shell = ShellScope.read(context);
    return shell.readTab(idOf(context), () => select(shell));
  }

  @override
  bool updateShouldNotify(ForumTabScope oldWidget) =>
      tabId != oldWidget.tabId || panel != oldWidget.panel;
}

/// Layout callbacks run after their parent builds, so resolve the tab again.
class ForumTabLayoutBuilder extends StatelessWidget {
  const ForumTabLayoutBuilder({super.key, required this.builder});
  final Widget Function(BuildContext context, BoxConstraints constraints)
  builder;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) =>
        ForumTabScope.read(context, (_) => builder(context, constraints)),
  );
}

class ForumTabListenableBuilder extends StatelessWidget {
  const ForumTabListenableBuilder({
    super.key,
    required this.listenable,
    required this.builder,
    this.child,
  });
  final Listenable listenable;
  final TransitionBuilder builder;
  final Widget? child;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: listenable,
    child: child,
    builder: (context, child) =>
        ForumTabScope.read(context, (_) => builder(context, child)),
  );
}
