import 'package:flutter/widgets.dart';

/// Internal bridge between an input-group surface and its native editor.
///
/// DInput and DTextarea keep ownership of editing, Form state, focus, IME and
/// selection. The group only consumes their visual state and suppresses their
/// standalone surface so there is exactly one border and focus ring.
class DInputGroupControlScope extends InheritedWidget {
  const DInputGroupControlScope({
    super.key,
    required this.report,
    required this.remove,
    required this.requestControlFocus,
    required this.inputPadding,
    required super.child,
  });

  final void Function(FocusNode focusNode, bool enabled, bool invalid) report;
  final ValueChanged<FocusNode> remove;
  final VoidCallback requestControlFocus;
  final EdgeInsetsGeometry inputPadding;

  static DInputGroupControlScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<DInputGroupControlScope>();

  @override
  bool updateShouldNotify(DInputGroupControlScope oldWidget) =>
      report != oldWidget.report ||
      remove != oldWidget.remove ||
      requestControlFocus != oldWidget.requestControlFocus ||
      inputPadding != oldWidget.inputPadding;
}
