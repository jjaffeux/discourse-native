import 'dart:async';

import 'package:flutter/widgets.dart';

import 'mobile_place_order_controller.dart';
import 'shell_scope.dart';

/// Holds the current account's [MobilePlaceOrderController] for the shell
/// under it, replacing it as the account changes.
class MobilePlaceOrderHost extends StatefulWidget {
  const MobilePlaceOrderHost({super.key, required this.child});
  final Widget child;
  static MobilePlaceOrderController? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<_MobilePlaceOrderScope>()
      ?.controller;
  @override
  State<MobilePlaceOrderHost> createState() => _MobilePlaceOrderHostState();
}

class _MobilePlaceOrderHostState extends State<MobilePlaceOrderHost> {
  (String, String)? _account;
  MobilePlaceOrderController? _controller;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final shell = ShellScope.of(context);
    final instance = shell.currentInstance;
    final account = instance == null
        ? null
        : (instance.url, shell.currentAccountIdentity!);
    if (_account == account) return;
    _account = account;
    _controller?.dispose();
    _controller = account == null
        ? null
        : MobilePlaceOrderController(account.$1, account.$2);
    if (_controller case final controller?) unawaited(controller.load());
  }

  @override
  Widget build(BuildContext context) =>
      _MobilePlaceOrderScope(controller: _controller, child: widget.child);

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }
}

class _MobilePlaceOrderScope extends InheritedWidget {
  const _MobilePlaceOrderScope({
    required this.controller,
    required super.child,
  });
  final MobilePlaceOrderController? controller;
  @override
  bool updateShouldNotify(_MobilePlaceOrderScope oldWidget) =>
      controller != oldWidget.controller;
}
