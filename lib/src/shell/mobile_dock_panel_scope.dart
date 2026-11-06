import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/widgets.dart';

/// What the phone shell keeps of its bar's panel of places past any one
/// bar, as the sidebar takes the bar and gives it back. Whether the panel is
/// [out]: the bar tells the root it is in as the panel comes and goes; the
/// shell reads it as a system back arrives and leaves that back to the
/// panel, which closes on it, rather than navigating under it. And the
/// session's one [peek] at the panel, which the first bar that can grow
/// takes. Nothing rebuilds on either.
class MobileDockPanelScope extends InheritedWidget {
  const MobileDockPanelScope({
    super.key,
    required this.out,
    required this.peek,
    required super.child,
  });

  final ValueNotifier<bool> out;
  final DMobileDockPeek peek;

  static MobileDockPanelScope? of(BuildContext context) =>
      context.getInheritedWidgetOfExactType<MobileDockPanelScope>();

  @override
  bool updateShouldNotify(MobileDockPanelScope oldWidget) =>
      !identical(out, oldWidget.out) || !identical(peek, oldWidget.peek);
}
