import 'package:flutter/widgets.dart';

import '../models/forum_workspace.dart';

class ForumTabScope extends InheritedWidget {
  const ForumTabScope({
    super.key,
    required this.tabId,
    required this.panel,
    required super.child,
  });

  final String? tabId;
  final ForumPanel panel;

  static String? idOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ForumTabScope>()?.tabId;

  static ForumPanel? panelOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ForumTabScope>()?.panel;

  @override
  bool updateShouldNotify(ForumTabScope oldWidget) =>
      tabId != oldWidget.tabId || panel != oldWidget.panel;
}
