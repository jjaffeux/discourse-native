import 'package:flutter/widgets.dart';

/// Identifies the reading route even when focus is above its content scope.
class TopicSheetRouteSettings extends RouteSettings {
  const TopicSheetRouteSettings() : super(name: 'desktop-topic-sheet');
}

/// Identifies the retained background and the reading route of a topic sheet.
class TopicSheetScope extends InheritedWidget {
  const TopicSheetScope({
    super.key,
    required this.background,
    this.onClose,
    required super.child,
  });

  final bool background;
  final VoidCallback? onClose;

  static bool isBackground(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<TopicSheetScope>()
          ?.background ==
      true;

  static TopicSheetScope? readerOf(BuildContext context) {
    final scope = context.getInheritedWidgetOfExactType<TopicSheetScope>();
    return scope?.background == false ? scope : null;
  }

  @override
  bool updateShouldNotify(TopicSheetScope oldWidget) =>
      background != oldWidget.background || onClose != oldWidget.onClose;
}
