import 'package:flutter/foundation.dart';

import 'json.dart';
import 'topic.dart';

/// The connected account's activity overview from
/// `/u/{username}/summary.json`.
///
/// Core ranks every collection server-side and caps it at six rows. There is
/// no summary-page cursor: the links web places after a full section lead to
/// separate activity pages rather than another summary response.
@immutable
class UserSummary {
  const UserSummary({
    this.canSeeSummaryStats = false,
    this.canSeeUserActions = false,
    this.likesGiven = 0,
    this.likesReceived = 0,
    this.topicsEntered = 0,
    this.postsRead = 0,
    this.daysVisited = 0,
    this.topicCount = 0,
    this.postCount = 0,
    this.timeRead = 0,
    this.recentTimeRead = 0,
    this.bookmarkCount = 0,
    this.topics = const [],
    this.replies = const [],
    this.links = const [],
    this.mostRepliedToUsers = const [],
    this.mostLikedByUsers = const [],
    this.mostLikedUsers = const [],
    this.topCategories = const [],
    this.badges = const [],
  });

  static const int maximumResults = 6;
  static const int maximumReferencedTopics = maximumResults * 3;

  /// [json] is the complete response envelope. Topics and badge definitions
  /// live beside `user_summary`; the summary's rows refer to them by id.
  factory UserSummary.fromJson(Map<String, dynamic> json, String siteUrl) {
    final body = jsonObject(json['user_summary']);

    final topicsById = <int, UserSummaryTopic>{};
    for (final value in jsonObjects(
      json['topics'],
    ).take(maximumReferencedTopics)) {
      final topic = UserSummaryTopic._fromJson(value);
      if (topic.id > 0) topicsById[topic.id] = topic;
    }

    final topics = <UserSummaryTopic>[];
    for (final idValue in jsonArray(body['topic_ids']).take(maximumResults)) {
      final topic = topicsById[jsonInt(idValue)];
      if (topic != null) topics.add(topic);
    }

    final replies = <UserSummaryReply>[];
    for (final value in jsonObjects(body['replies']).take(maximumResults)) {
      final topic = topicsById[jsonInt(value['topic_id'])];
      final postNumber = jsonInt(value['post_number']);
      if (topic == null || postNumber <= 0) continue;
      replies.add(
        UserSummaryReply(
          topic: topic,
          postNumber: postNumber,
          likeCount: _count(value['like_count']),
          createdAt: jsonDate(value['created_at']),
        ),
      );
    }

    final links = <UserSummaryLink>[];
    for (final value in jsonObjects(body['links']).take(maximumResults)) {
      final topic = topicsById[jsonInt(value['topic_id'])];
      final url = jsonText(value['url']);
      final postNumber = jsonInt(value['post_number']);
      if (topic == null || url == null || postNumber <= 0) continue;
      links.add(
        UserSummaryLink(
          topic: topic,
          url: url,
          title: jsonText(value['title']),
          clicks: _count(value['clicks']),
          postNumber: postNumber,
        ),
      );
    }

    final badgeDefinitions = <int, Map<String, dynamic>>{};
    for (final value in jsonObjects(json['badges']).take(maximumResults)) {
      final id = jsonInt(value['id']);
      if (id > 0) badgeDefinitions[id] = value;
    }
    final badges = <UserSummaryBadge>[];
    for (final value in jsonObjects(body['badges']).take(maximumResults)) {
      final id = jsonInt(value['badge_id']);
      final definition = badgeDefinitions[id];
      if (id <= 0 || definition == null) continue;
      badges.add(
        UserSummaryBadge(
          id: id,
          name: jsonText(definition['name']) ?? 'Badge',
          description: jsonHtmlText(definition['description']),
          icon: jsonText(definition['icon']),
          imageUrl: jsonText(definition['image_url']),
          count: _count(value['count']),
        ),
      );
    }

    return UserSummary(
      canSeeSummaryStats: body['can_see_summary_stats'] == true,
      canSeeUserActions: body['can_see_user_actions'] == true,
      likesGiven: _count(body['likes_given']),
      likesReceived: _count(body['likes_received']),
      topicsEntered: _count(body['topics_entered']),
      postsRead: _count(body['posts_read_count']),
      daysVisited: _count(body['days_visited']),
      topicCount: _count(body['topic_count']),
      postCount: _count(body['post_count']),
      timeRead: _count(body['time_read']),
      recentTimeRead: _count(body['recent_time_read']),
      bookmarkCount: _count(body['bookmark_count']),
      topics: List.unmodifiable(topics),
      replies: List.unmodifiable(replies),
      links: List.unmodifiable(links),
      mostRepliedToUsers: _users(body['most_replied_to_users'], siteUrl),
      mostLikedByUsers: _users(body['most_liked_by_users'], siteUrl),
      mostLikedUsers: _users(body['most_liked_users'], siteUrl),
      topCategories: List.unmodifiable([
        for (final value in jsonObjects(
          body['top_categories'],
        ).take(maximumResults))
          if (jsonInt(value['id']) > 0) UserSummaryCategory._fromJson(value),
      ]),
      badges: List.unmodifiable(badges),
    );
  }

  final bool canSeeSummaryStats;
  final bool canSeeUserActions;
  final int likesGiven;
  final int likesReceived;
  final int topicsEntered;
  final int postsRead;
  final int daysVisited;
  final int topicCount;
  final int postCount;

  /// Seconds, matching `UserStat#time_read` on the wire.
  final int timeRead;

  /// Seconds read in core's recent sixty-day window.
  final int recentTimeRead;
  final int bookmarkCount;
  final List<UserSummaryTopic> topics;
  final List<UserSummaryReply> replies;
  final List<UserSummaryLink> links;
  final List<UserSummaryUser> mostRepliedToUsers;
  final List<UserSummaryUser> mostLikedByUsers;
  final List<UserSummaryUser> mostLikedUsers;
  final List<UserSummaryCategory> topCategories;
  final List<UserSummaryBadge> badges;

  bool get showRecentTimeRead =>
      recentTimeRead > 0 && recentTimeRead != timeRead;

  static List<UserSummaryUser> _users(Object? value, String siteUrl) =>
      List.unmodifiable([
        for (final user in jsonObjects(value).take(maximumResults))
          if (jsonText(user['username']) case final username?)
            UserSummaryUser(
              id: jsonIntOrNull(user['id']),
              username: username,
              name: jsonText(user['name']),
              avatarUrl: resolveAvatarUrl(
                jsonText(user['avatar_template']),
                siteUrl,
              ),
              count: _count(user['count']),
              isStaff: user['admin'] == true || user['moderator'] == true,
              primaryGroupName: jsonText(user['primary_group_name']),
              flairName: jsonText(user['flair_name']),
              flairUrl: jsonText(user['flair_url']),
            ),
      ]);
}

@immutable
class UserSummaryTopic {
  const UserSummaryTopic({
    required this.id,
    required this.title,
    required this.slug,
    this.categoryId,
    this.likeCount = 0,
    this.createdAt,
  });

  factory UserSummaryTopic._fromJson(Map<String, dynamic> json) =>
      UserSummaryTopic(
        id: jsonInt(json['id']),
        title: jsonTitle(json['title'], json['fancy_title']),
        slug: jsonString(json['slug']),
        categoryId: jsonIntOrNull(json['category_id']),
        likeCount: _count(json['like_count']),
        createdAt: jsonDate(json['created_at']),
      );

  final int id;
  final String title;
  final String slug;
  final int? categoryId;
  final int likeCount;
  final DateTime? createdAt;

  Topic get topic => Topic(
    id: id,
    title: title,
    slug: slug,
    categoryId: categoryId,
    likeCount: likeCount,
    bumpedAt: createdAt,
  );
}

@immutable
class UserSummaryReply {
  const UserSummaryReply({
    required this.topic,
    required this.postNumber,
    this.likeCount = 0,
    this.createdAt,
  });

  final UserSummaryTopic topic;
  final int postNumber;
  final int likeCount;
  final DateTime? createdAt;
}

@immutable
class UserSummaryLink {
  const UserSummaryLink({
    required this.topic,
    required this.url,
    required this.postNumber,
    this.title,
    this.clicks = 0,
  });

  final UserSummaryTopic topic;
  final String url;
  final String? title;
  final int clicks;
  final int postNumber;
}

@immutable
class UserSummaryUser {
  const UserSummaryUser({
    required this.username,
    this.id,
    this.name,
    this.avatarUrl,
    this.count = 0,
    this.isStaff = false,
    this.primaryGroupName,
    this.flairName,
    this.flairUrl,
  });

  final int? id;
  final String username;
  final String? name;
  final String? avatarUrl;
  final int count;
  final bool isStaff;
  final String? primaryGroupName;
  final String? flairName;
  final String? flairUrl;

  String get displayName => name ?? username;
}

@immutable
class UserSummaryCategory {
  const UserSummaryCategory({
    required this.id,
    required this.name,
    required this.color,
    required this.slug,
    this.parentCategoryId,
    this.styleType = 'square',
    this.icon,
    this.emoji,
    this.readRestricted = false,
    this.topicCount = 0,
    this.postCount = 0,
  });

  factory UserSummaryCategory._fromJson(Map<String, dynamic> json) =>
      UserSummaryCategory(
        id: jsonInt(json['id']),
        name: jsonString(json['name']),
        color: jsonString(json['color'], fallback: '888888'),
        slug: jsonString(json['slug']),
        parentCategoryId: jsonIntOrNull(json['parent_category_id']),
        styleType: jsonText(json['style_type']) ?? 'square',
        icon: jsonText(json['icon']),
        emoji: jsonText(json['emoji']),
        readRestricted: json['read_restricted'] == true,
        topicCount: _count(json['topic_count']),
        postCount: _count(json['post_count']),
      );

  final int id;
  final String name;
  final String color;
  final String slug;
  final int? parentCategoryId;
  final String styleType;
  final String? icon;
  final String? emoji;
  final bool readRestricted;
  final int topicCount;
  final int postCount;

  TopicCategory get category => TopicCategory(
    id: id,
    name: name,
    color: color,
    slug: slug,
    parentCategoryId: parentCategoryId,
    styleType: styleType,
    icon: icon,
    emoji: emoji,
    readRestricted: readRestricted,
    topicCount: topicCount,
  );
}

@immutable
class UserSummaryBadge {
  const UserSummaryBadge({
    required this.id,
    required this.name,
    this.description,
    this.icon,
    this.imageUrl,
    this.count = 0,
  });

  final int id;
  final String name;
  final String? description;
  final String? icon;
  final String? imageUrl;
  final int count;
}

int _count(Object? value) {
  final parsed = jsonInt(value);
  return parsed < 0 ? 0 : parsed;
}
