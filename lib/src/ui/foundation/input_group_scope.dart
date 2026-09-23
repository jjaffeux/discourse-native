import 'package:flutter/widgets.dart';

import 'control_style.dart';

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
    required this.enabled,
    this.size = DControlSize.regular,
    required super.child,
  }) : _boundary = false;

  /// An adapted editor owns its descendants after consuming the group insets.
  DInputGroupControlScope.boundary({
    super.key,
    required DInputGroupControlScope parent,
    required super.child,
  }) : report = parent.report,
       remove = parent.remove,
       requestControlFocus = parent.requestControlFocus,
       inputPadding = parent.inputPadding,
       enabled = parent.enabled,
       size = parent.size,
       _boundary = true;

  final void Function(FocusNode focusNode, bool enabled, bool invalid) report;
  final ValueChanged<FocusNode> remove;
  final VoidCallback requestControlFocus;
  final EdgeInsetsGeometry inputPadding;
  final bool enabled;
  final DControlSize size;
  final bool _boundary;

  static DInputGroupControlScope? maybeOf(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<DInputGroupControlScope>();
    return scope?._boundary == true ? null : scope;
  }

  @override
  bool updateShouldNotify(DInputGroupControlScope oldWidget) =>
      report != oldWidget.report ||
      remove != oldWidget.remove ||
      requestControlFocus != oldWidget.requestControlFocus ||
      inputPadding != oldWidget.inputPadding ||
      enabled != oldWidget.enabled ||
      size != oldWidget.size ||
      _boundary != oldWidget._boundary;
}
