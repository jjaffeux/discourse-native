import 'package:flutter/widgets.dart';

import 'sidebar.dart';

/// One entry in the main content stack.
///
/// The stack exists because the main region is sometimes replaced rather than
/// overlaid — opening a topic from a topic list swaps what fills the region,
/// on both desktop and mobile, and needs a way back.
@immutable
class ContentRoute {
  const ContentRoute({
    required this.id,
    required this.title,
    required this.icon,
    this.subtitle,
    this.color,
  });

  /// The route a sidebar entry opens.
  ContentRoute.fromDestination(SidebarDestination destination)
    : id = destination.id,
      title = destination.label,
      icon = destination.icon,
      subtitle = null,
      color = destination.color;

  final String id;
  final String title;
  final IconData icon;
  final String? subtitle;
  final Color? color;

  @override
  bool operator ==(Object other) =>
      other is ContentRoute && other.id == id && other.title == title;

  @override
  int get hashCode => Object.hash(id, title);
}
