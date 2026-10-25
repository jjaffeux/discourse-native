import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/widgets.dart';

class AccountMenuScope extends StatefulWidget {
  const AccountMenuScope({super.key, required this.child});

  final Widget child;

  static void activate(BuildContext context, DPopoverController controller) {
    context
        .getInheritedWidgetOfExactType<_AccountMenuScope>()
        ?.owner
        .activateMenu(controller);
  }

  @override
  State<AccountMenuScope> createState() => _AccountMenuScopeState();
}

class _AccountMenuScopeState extends State<AccountMenuScope> {
  DPopoverController? _active;

  void activateMenu(DPopoverController controller) {
    if (!identical(_active, controller)) _active?.close();
    _active = controller;
  }

  @override
  Widget build(BuildContext context) =>
      _AccountMenuScope(owner: this, child: widget.child);
}

class _AccountMenuScope extends InheritedWidget {
  const _AccountMenuScope({required this.owner, required super.child});

  final _AccountMenuScopeState owner;

  @override
  bool updateShouldNotify(_AccountMenuScope oldWidget) =>
      owner != oldWidget.owner;
}
