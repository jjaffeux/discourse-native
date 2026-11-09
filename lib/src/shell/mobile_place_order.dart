import 'dart:async';

import 'package:flutter/widgets.dart';

import 'mobile_place_order_controller.dart';

/// Holds the current account's [MobilePlaceOrderController] for the shell
/// under it, replacing it as the account changes.
class MobilePlaceOrderHost extends StatefulWidget {
  const MobilePlaceOrderHost({
    super.key,
    required this.account,
    required this.child,
  });

  /// The site and account identity whose order this holds, while signed in.
  final (String, String)? account;
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
  void initState() {
    super.initState();
    _syncAccount();
  }

  @override
  void didUpdateWidget(MobilePlaceOrderHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncAccount();
  }

  void _syncAccount() {
    final account = widget.account;
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
