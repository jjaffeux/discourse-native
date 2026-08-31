import 'package:flutter/material.dart';

import '../theme/d_icon.dart';
import '../theme/d_icons.dart';
import '../theme/d_native_icons.dart';
import 'group_route.dart';
import 'list_link.dart';
import 'sidebar.dart';

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
    this.messageGroupName,
    this.groupRoute,
  });

  factory ContentRoute.list(ListLink link, {String? title, Color? color}) {
    return ContentRoute(
      id: 'list-${link.feedPath}',
      title: title ?? link.placeholderTitle,
      icon: link.kind == ListKind.category ? DIcons.folder : DIcons.tag,
      color: color,
      feedPath: link.feedPath,
    );
  }

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
      icon: DNativeIcons.topic,
      subtitle: subtitle,
      color: color,
      topicId: topicId,
      slug: slug,
      postNumber: postNumber,
    );
  }

  factory ContentRoute.preferences() => const ContentRoute(
    id: 'preferences',
    title: 'Preferences',
    icon: DIcons.gear,
  );

  factory ContentRoute.group(
    GroupRoute route, {
    String? title,
    String? feedPath,
  }) => ContentRoute(
    id: route.id,
    title: title ?? route.groupName ?? 'Groups',
    icon: DIcons.users,
    feedPath: feedPath,
    groupRoute: route,
  );

  factory ContentRoute.userActivity() =>
      const ContentRoute(id: 'activity', title: 'Activity', icon: DIcons.list);

  factory ContentRoute.messages({String? groupName}) {
    final group = groupName?.trim();
    if (group != null &&
        (group.isEmpty || group.length > maximumMessageGroupNameLength)) {
      throw ArgumentError.value(groupName, 'groupName', 'Invalid group name.');
    }
    return ContentRoute(
      id: group == null
          ? 'messages'
          : 'messages-group-${Uri.encodeComponent(group)}',
      title: 'Messages',
      icon: DIcons.inbox,
      messageGroupName: group,
    );
  }

  ContentRoute.fromDestination(SidebarDestination destination)
    : id = destination.id,
      title = destination.label,
      icon = destination.icon,
      subtitle = null,
      color = destination.routeColor ?? destination.color,
      topicId = null,
      slug = null,
      postNumber = null,
      feedPath = destination.feedPath,
      messageGroupName = null,
      groupRoute = null;

  final String id;
  final String title;
  final DIconData icon;
  final String? subtitle;
  final Color? color;

  final int? topicId;
  final String? slug;

  final int? postNumber;

  final String? feedPath;

  final String? messageGroupName;

  final GroupRoute? groupRoute;

  /// Prevents corrupted persisted state from producing an oversized URI.
  static const int maximumFeedPathLength = 2048;

  static const int maximumMessageGroupNameLength = 255;

  bool get isTopic => topicId != null;

  bool get isPreferences => !isTopic && id == 'preferences';

  bool get isMessages =>
      !isTopic && (id == 'messages' || messageGroupName != null);

  bool get isGroups => !isTopic && groupRoute?.isDirectory == true;

  bool get isGroup => !isTopic && groupRoute?.isDetail == true;

  /// Contains presentation only, never fetched content or credentials.
  Map<String, Object?> toJson() => {
    'id': id,
    'title': title,
    'icon': icon.name,
    if (subtitle != null) 'subtitle': subtitle,
    if (color != null) 'color': color!.toARGB32(),
    if (topicId != null) 'topic_id': topicId,
    if (slug != null) 'slug': slug,
    if (postNumber != null) 'post_number': postNumber,
    if (feedPath != null) 'feed_path': feedPath,
    if (messageGroupName != null) 'message_group_name': messageGroupName,
    if (groupRoute != null) 'group_route': groupRoute!.toJson(),
  };

  factory ContentRoute.fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final title = json['title'];
    final iconName = json['icon'];
    if (id is! String ||
        id.isEmpty ||
        title is! String ||
        iconName is! String) {
      throw const FormatException('Invalid content route');
    }

    final colorValue = json['color'];
    final topicId = json['topic_id'];
    final postNumber = json['post_number'];
    final feedPath = json['feed_path'];
    final messageGroupName = json['message_group_name'];
    final rawGroupRoute = json['group_route'];
    if (topicId != null && (topicId is! int || topicId <= 0)) {
      throw const FormatException('Invalid content route topic id');
    }
    if (postNumber != null && (postNumber is! int || postNumber <= 0)) {
      throw const FormatException('Invalid content route post number');
    }
    if (feedPath != null && !_isSafeFeedPath(feedPath)) {
      throw const FormatException('Invalid content route feed path');
    }
    if (messageGroupName != null &&
        (messageGroupName is! String ||
            messageGroupName.trim().isEmpty ||
            messageGroupName != messageGroupName.trim() ||
            messageGroupName.length > maximumMessageGroupNameLength ||
            topicId != null ||
            id != 'messages-group-${Uri.encodeComponent(messageGroupName)}')) {
      throw const FormatException('Invalid content route message group');
    }
    final GroupRoute? groupRoute;
    if (rawGroupRoute == null) {
      groupRoute = null;
    } else if (rawGroupRoute is Map) {
      groupRoute = GroupRoute.fromJson(
        Map<String, dynamic>.from(rawGroupRoute),
      );
      if (topicId != null || messageGroupName != null || id != groupRoute.id) {
        throw const FormatException('Invalid content group route');
      }
    } else {
      throw const FormatException('Invalid content group route');
    }
    return ContentRoute(
      id: id,
      title: title,
      // Upgrade the speech bubble saved by older topic tabs without changing
      // the durable icon of routes that deliberately chose another glyph.
      icon:
          DNativeIcons.byName[iconName] ??
          (topicId != null && iconName == DIcons.comments.name
              ? DNativeIcons.topic
              : DIcons.byName[iconName] ?? DIcons.comments),
      subtitle: json['subtitle'] is String ? json['subtitle'] as String : null,
      color: colorValue is int ? Color(colorValue) : null,
      topicId: topicId as int?,
      slug: json['slug'] is String ? json['slug'] as String : null,
      postNumber: postNumber as int?,
      feedPath: feedPath as String?,
      messageGroupName: messageGroupName as String?,
      groupRoute: groupRoute,
    );
  }

  static bool _isSafeFeedPath(Object? value) {
    if (value is! String ||
        value.isEmpty ||
        value.length > maximumFeedPathLength) {
      return false;
    }
    final uri = Uri.tryParse(value);
    return uri != null &&
        value.startsWith('/') &&
        !value.startsWith('//') &&
        uri.path.isNotEmpty &&
        uri.path.endsWith('.json') &&
        !uri.hasScheme &&
        !uri.hasAuthority &&
        uri.userInfo.isEmpty &&
        !uri.hasFragment;
  }

  @override
  bool operator ==(Object other) =>
      other is ContentRoute && other.id == id && other.title == title;

  @override
  int get hashCode => Object.hash(id, title);
}
