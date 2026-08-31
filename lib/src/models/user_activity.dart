import 'package:flutter/foundation.dart';

import 'json.dart';
import 'topic.dart';

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

  bool get isUsable =>
      (isTopic || isReply) && topicId > 0 && postNumber > 0 && title.isNotEmpty;

  String get identity => '$topicId/$postNumber';
}

@immutable
class UserActivityPage {
  const UserActivityPage({
    this.items = const [],
    this.categories = const [],
    this.rawItemCount = 0,
  });

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

  final int rawItemCount;
}
