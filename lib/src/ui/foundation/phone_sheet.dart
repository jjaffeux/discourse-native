import 'package:flutter/widgets.dart';

import 'app_text_scaler.dart';

/// Supplies phone sizing to the choices and fields of a partial sheet.
/// Widgets lay out at their painted size and keep the user's text scaling.
class DPhoneSheet extends StatelessWidget {
  const DPhoneSheet({super.key, required this.child})
    : _active = true,
      _actions = false;

  /// Supplies the choice sheet's button metrics within an action footer.
  const DPhoneSheet.actions({super.key, required this.child})
    : _active = true,
      _actions = true;

  /// Leaves a sheet's header or an embedded page on its own sizing.
  const DPhoneSheet.page({super.key, required this.child})
    : _active = false,
      _actions = false;

  final Widget child;
  final bool _active;
  final bool _actions;

  static bool contains(BuildContext? context) =>
      context?.dependOnInheritedWidgetOfExactType<_PhoneSheetScope>()?.active ??
      false;

  static bool actionsOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_PhoneSheetScope>()?.actions ??
      false;

  @override
  Widget build(BuildContext context) {
    if (_actions) {
      return contains(context)
          ? _PhoneSheetScope(active: true, actions: true, child: child)
          : child;
    }
    if (_active) {
      return _PhoneSheetScope(
        active: true,
        child: DReferenceTextScale(
          child: DefaultTextStyle.merge(
            style: const TextStyle(fontSize: 21, height: 1.5),
            child: child,
          ),
        ),
      );
    }
    if (!contains(context)) return child;
    return _PhoneSheetScope(
      active: false,
      child: MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: DReferenceTextScale.readingScalerOf(context)),
        child: child,
      ),
    );
  }
}

class _PhoneSheetScope extends InheritedWidget {
  const _PhoneSheetScope({
    required this.active,
    required super.child,
    this.actions = false,
  });

  final bool active;
  final bool actions;

  @override
  bool updateShouldNotify(_PhoneSheetScope oldWidget) =>
      active != oldWidget.active || actions != oldWidget.actions;
}
