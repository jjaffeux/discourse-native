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
    this.messageGroupName,
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

  /// The connected account's native preferences editor.
  ///
  /// Preference values stay server-owned and are hydrated by the page. The
  /// route therefore carries presentation identity only, which makes it safe
  /// to persist beside the rest of a forum workspace without caching account
  /// data in the tab document.
  factory ContentRoute.preferences() => const ContentRoute(
    id: 'preferences',
    title: 'Preferences',
    icon: DIcons.gear,
  );

  /// The connected account's contribution stream from its profile menu.
  factory ContentRoute.userActivity() =>
      const ContentRoute(id: 'activity', title: 'Activity', icon: DIcons.list);

  /// One private-message inbox belonging to the connected account.
  ///
  /// Personal and group inboxes use distinct route ids so their topic feeds,
  /// pagination cursors, and scroll positions never overwrite one another.
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

  /// The route a sidebar entry opens.
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
      messageGroupName = null;

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
  /// see [ContentRoute.list]. Runtime sidebar routes such as categories carry
  /// one too; static routes leave it null because `ShellController` already
  /// knows their address.
  final String? feedPath;

  /// The group whose PM inbox this route shows, or null for personal messages
  /// and every non-message route.
  final String? messageGroupName;

  /// Largest site-relative feed path restored from presentation state.
  ///
  /// Ordinary category paths are tiny. Keeping the same generous boundary as
  /// remote pagination cursors prevents a corrupt preference from becoming an
  /// oversized URI on startup.
  static const int maximumFeedPathLength = 2048;

  /// Core group names are much shorter; this defensive persistence boundary
  /// also keeps their percent-encoded request segment comfortably bounded.
  static const int maximumMessageGroupNameLength = 255;

  bool get isTopic => topicId != null;

  bool get isPreferences => !isTopic && id == 'preferences';

  bool get isMessages =>
      !isTopic && (id == 'messages' || messageGroupName != null);

  /// A durable, presentation-only snapshot of this route.
  ///
  /// The payload deliberately contains no fetched content or credentials. Icon
  /// names are the stable names Discourse itself serializes, so an older tab can
  /// still be restored after the generated SVG data changes.
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
    return ContentRoute(
      id: id,
      title: title,
      icon: DIcons.byName[iconName] ?? DIcons.comments,
      subtitle: json['subtitle'] is String ? json['subtitle'] as String : null,
      color: colorValue is int ? Color(colorValue) : null,
      topicId: topicId as int?,
      slug: json['slug'] is String ? json['slug'] as String : null,
      postNumber: postNumber as int?,
      feedPath: feedPath as String?,
      messageGroupName: messageGroupName as String?,
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
