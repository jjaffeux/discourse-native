import 'package:flutter/widgets.dart';

/// Whether a phone bar's panel of places is out. The bar tells the root it
/// is in as the panel comes and goes; the shell reads it as a system back
/// arrives and leaves that back to the panel, which closes on it, rather
/// than navigating under it. Nothing rebuilds on it.
class MobileDockPanelScope extends InheritedWidget {
  const MobileDockPanelScope({
    super.key,
    required this.out,
    required super.child,
  });

  final ValueNotifier<bool> out;

  static ValueNotifier<bool>? of(BuildContext context) =>
      context.getInheritedWidgetOfExactType<MobileDockPanelScope>()?.out;

  @override
  bool updateShouldNotify(MobileDockPanelScope oldWidget) =>
      !identical(out, oldWidget.out);
}
