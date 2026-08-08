import 'package:flutter/material.dart';

import '../theme/d_icon.dart';
import '../theme/d_icons.dart';
import 'list_link.dart';
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
    this.postNumber,
    this.feedPath,
  });

  /// A filtered topic list — a category or a tag — opened from a hashtag.
  ///
  /// Unlike a sidebar destination this route brings its own [feedPath], because
  /// nothing in the app knows the list exists until a post mentions it. The id
  /// is derived from that path so the same category opened twice is the same
  /// route, and so its feed is cached under a key nothing else can collide
  /// with.
  factory ContentRoute.list(ListLink link, {String? title, Color? color}) {
    return ContentRoute(
      id: 'list-${link.feedPath}',
      title: title ?? link.placeholderTitle,
      icon: link.kind == ListKind.category ? DIcons.folder : DIcons.tag,
      color: color,
      feedPath: link.feedPath,
    );
  }

  /// A specific topic, opened from a list.
  factory ContentRoute.topic({
    required int topicId,
    required String slug,
    required String title,
    String? subtitle,
    Color? color,
    int? postNumber,
  }) {
    return ContentRoute(
      id: 'topic-$topicId',
      title: title,
      icon: DIcons.comments,
      subtitle: subtitle,
      color: color,
      topicId: topicId,
      slug: slug,
      postNumber: postNumber,
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
      slug = null,
      postNumber = null,
      feedPath = null;

  final String id;
  final String title;
  final DIconData icon;
  final String? subtitle;
  final Color? color;

  /// Set when this route is a topic rather than a list.
  final int? topicId;
  final String? slug;

  /// The post this topic route should initially reveal, when it names one.
  final int? postNumber;

  /// Where this route's topic list lives, for a route that carries its own —
  /// see [ContentRoute.list]. Null for everything the sidebar opens, whose
  /// feeds `ShellController` already knows the address of.
  final String? feedPath;

  bool get isTopic => topicId != null;

  @override
  bool operator ==(Object other) =>
      other is ContentRoute && other.id == id && other.title == title;

  @override
  int get hashCode => Object.hash(id, title);
}
