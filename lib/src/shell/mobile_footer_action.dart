import 'package:flutter/widgets.dart';

import '../theme/d_icon.dart';

/// An action supplied by the visible page for the persistent mobile bar.
@immutable
class MobileFooterAction {
  const MobileFooterAction({
    this.key,
    required this.label,
    required this.icon,
    required this.onPressed,
    this.loading = false,
  });

  final Key? key;
  final String label;
  final DIconData icon;
  final VoidCallback? onPressed;
  final bool loading;

  @override
  bool operator ==(Object other) =>
      other is MobileFooterAction &&
      other.key == key &&
      other.label == label &&
      other.icon == icon &&
      other.onPressed == onPressed &&
      other.loading == loading;

  @override
  int get hashCode => Object.hash(key, label, icon, onPressed, loading);
}

class MobileFooterActionController extends ChangeNotifier {
  Object? _owner;
  MobileFooterAction? _action;
  bool _disposed = false;

  MobileFooterAction? get action => _action;

  void publish(Object owner, MobileFooterAction action) {
    if (_disposed) return;
    if (identical(_owner, owner) && _action == action) return;
    _owner = owner;
    _action = action;
    notifyListeners();
  }

  void clear(Object owner) {
    if (_disposed) return;
    if (!identical(_owner, owner)) return;
    _owner = null;
    _action = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

class MobileFooterActionScope extends InheritedWidget {
  const MobileFooterActionScope({
    super.key,
    required this.controller,
    required super.child,
  });

  final MobileFooterActionController controller;

  static MobileFooterActionController? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<MobileFooterActionScope>()
      ?.controller;

  @override
  bool updateShouldNotify(MobileFooterActionScope oldWidget) =>
      !identical(controller, oldWidget.controller);
}
