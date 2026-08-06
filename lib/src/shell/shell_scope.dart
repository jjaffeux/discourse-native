import 'package:flutter/widgets.dart';

import 'shell_controller.dart';

/// Makes the [ShellController] available to the widgets below it, rebuilding
/// dependents whenever it notifies.
class ShellScope extends InheritedNotifier<ShellController> {
  const ShellScope({
    super.key,
    required ShellController controller,
    required super.child,
  }) : super(notifier: controller);

  static ShellController of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<ShellScope>();
    assert(scope != null, 'No ShellScope found above this widget');
    return scope!.notifier!;
  }

  /// The controller, or null where the shell is not an ancestor — widgets that
  /// also render outside it, such as a quote in a test.
  static ShellController? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ShellScope>()?.notifier;
}
