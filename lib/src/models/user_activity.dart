import 'package:flutter/foundation.dart';

import 'json.dart';
import 'topic.dart';

/// One topic or reply in the default user Activity stream.
///
/// Core's `userActivity.index` deliberately filters `/user_actions.json` to
/// action types 4 and 5. It is therefore a contribution stream, not the
/// account summary and not a history of likes, reads, bookmarks, or drafts.
@immutable
class UserActivityItem {
  const UserActivityItem({
    required this.actionType,
    required this.topicId,
    required this.postNumber,
    required this.title,
    required this.slug,
    required this.username,
    required this.excerpt,
    this.postId,
    this.createdAt,
    this.avatarUrl,
    this.categoryId,
    this.closed = false,
    this.archived = false,
    this.deleted = false,
    this.hidden = false,
  });

  static const int topicActionType = 4;
  static const int replyActionType = 5;

  factory UserActivityItem.fromJson(
    Map<String, dynamic> json,
    String siteUrl,
  ) => UserActivityItem(
    actionType: jsonInt(json['action_type']),
    topicId: jsonInt(json['topic_id']),
    postNumber: jsonInt(json['post_number']),
    postId: jsonIntOrNull(json['post_id']),
    title: jsonString(json['title']),
    slug: jsonString(json['slug']),
    username: jsonString(json['username']),
    excerpt: jsonString(json['excerpt']),
    createdAt: jsonDate(json['created_at']),
    avatarUrl: resolveAvatarUrl(jsonText(json['avatar_template']), siteUrl),
    categoryId: jsonIntOrNull(json['category_id']),
    closed: json['closed'] == true,
    archived: json['archived'] == true,
    deleted: json['deleted'] == true,
    hidden: json['hidden'] == true,
  );

  final int actionType;
  final int topicId;
  final int postNumber;
  final int? postId;
  final String title;
  final String slug;
  final String username;

  /// The server-cooked, permission-filtered 300-character post excerpt.
  final String excerpt;

  final DateTime? createdAt;
  final String? avatarUrl;
  final int? categoryId;
  final bool closed;
  final bool archived;
  final bool deleted;
  final bool hidden;

  String get plainExcerpt => jsonHtmlText(excerpt) ?? '';

  bool get isTopic => actionType == topicActionType;
  bool get isReply => actionType == replyActionType;

  /// Broken or unexpected rows are skipped without rejecting the page.
  bool get isUsable =>
      (isTopic || isReply) && topicId > 0 && postNumber > 0 && title.isNotEmpty;

  /// The serializer does not expose the user-action id. A post is the stable
  /// identity core itself uses when collapsing adjacent stream entries.
  String get identity => '$topicId/$postNumber';
}

/// One raw page from `/user_actions.json` plus its category side-load.
@immutable
class UserActivityPage {
  const UserActivityPage({
    this.items = const [],
    this.categories = const [],
    this.rawItemCount = 0,
  });

  /// Core caps this endpoint at 100; native ordinarily asks for 30.
  static const int maximumItems = 100;

  factory UserActivityPage.fromJson(
    Map<String, dynamic> json,
    String siteUrl, {
    int limit = 30,
  }) {
    final boundedLimit = limit < 1
        ? 1
        : limit > maximumItems
        ? maximumItems
        : limit;
    final rawItems = jsonObjects(
      json['user_actions'],
    ).take(boundedLimit).toList(growable: false);
    return UserActivityPage(
      rawItemCount: rawItems.length,
      items: List.unmodifiable([
        for (final entry in rawItems)
          if (UserActivityItem.fromJson(entry, siteUrl) case final item
              when item.isUsable)
            item,
      ]),
      // At most one category can be referenced by each row. The generous
      // endpoint cap is also a sufficient bound for this sibling collection.
      categories: List.unmodifiable([
        for (final entry in jsonObjects(json['categories']).take(maximumItems))
          if (TopicCategory.fromJson(entry) case final category
              when category.id > 0 && category.name.isNotEmpty)
            category,
      ]),
    );
  }

  final List<UserActivityItem> items;
  final List<TopicCategory> categories;

  /// Offset advances by server rows, not retained rows. A malformed entry or
  /// duplicate must not make the next request overlap this page forever.
  final int rawItemCount;
}
