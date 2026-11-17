import 'package:flutter/widgets.dart';

/// Whether the phone shell's bar has its panel of places [out], kept as the
/// sidebar takes the bar and gives it back: the bar tells the root it is in
/// as the panel comes and goes; the shell reads it as a system back arrives
/// and leaves that back to the panel, which closes on it, rather than
/// navigating under it. Nothing rebuilds on it.
class MobileDockPanelScope extends InheritedWidget {
  const MobileDockPanelScope({
    super.key,
    required this.out,
    required super.child,
  });

  final ValueNotifier<bool> out;

  static MobileDockPanelScope? of(BuildContext context) =>
      context.getInheritedWidgetOfExactType<MobileDockPanelScope>();

  @override
  bool updateShouldNotify(MobileDockPanelScope oldWidget) =>
      !identical(out, oldWidget.out);
}
