import 'package:flutter/material.dart';

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
    this.topicId,
    this.slug,
  });

  /// A specific topic, opened from a list.
  factory ContentRoute.topic({
    required int topicId,
    required String slug,
    required String title,
    String? subtitle,
    Color? color,
  }) {
    return ContentRoute(
      id: 'topic-$topicId',
      title: title,
      icon: Icons.article_outlined,
      subtitle: subtitle,
      color: color,
      topicId: topicId,
      slug: slug,
    );
  }

  /// The route a sidebar entry opens.
  ContentRoute.fromDestination(SidebarDestination destination)
    : id = destination.id,
      title = destination.label,
      icon = destination.icon,
      subtitle = null,
      color = destination.color,
      topicId = null,
      slug = null;

  final String id;
  final String title;
  final IconData icon;
  final String? subtitle;
  final Color? color;

  /// Set when this route is a topic rather than a list.
  final int? topicId;
  final String? slug;

  bool get isTopic => topicId != null;

  @override
  bool operator ==(Object other) =>
      other is ContentRoute && other.id == id && other.title == title;

  @override
  int get hashCode => Object.hash(id, title);
}
