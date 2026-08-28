import 'package:flutter/foundation.dart';

import 'json.dart';

/// The complete, bounded payload behind a user's Summary page.
///
/// Core side-loads topics and badge definitions, then refers to them from the
/// `user_summary` envelope. Joining those references here leaves widgets with
/// ordinary immutable records and one source of wire-shape knowledge.
@immutable
final class UserSummary {
  const UserSummary({
    this.canSeeSummaryStats = false,
    this.canSeeUserActions = false,
    this.likesGiven = 0,
    this.likesReceived = 0,
    this.topicsEntered = 0,
    this.postsReadCount = 0,
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

  /// `UserSummary::MAX_SUMMARY_RESULTS` and `UserSummary::MAX_BADGES` in core.
  static const int maximumResults = 6;

  /// Topics can be referenced independently by topics, replies, and links.
  static const int maximumReferencedTopics = maximumResults * 3;

  factory UserSummary.fromJson(Map<String, dynamic> json, String siteUrl) {
    final summary = jsonObject(json['user_summary']);
    final topicById = <int, UserSummaryTopic>{};
    for (final value in jsonObjects(
      json['topics'],
    ).take(maximumReferencedTopics)) {
      final topic = UserSummaryTopic._fromJson(value);
      if (topic.id > 0) topicById[topic.id] = topic;
    }

    final topics = <UserSummaryTopic>[];
    for (final value in jsonArray(summary['topic_ids']).take(maximumResults)) {
      final topic = topicById[jsonInt(value)];
      if (topic != null) topics.add(topic);
    }

    final replies = <UserSummaryReply>[];
    for (final value in jsonObjects(summary['replies']).take(maximumResults)) {
      final topic = topicById[jsonInt(value['topic_id'])];
      if (topic == null) continue;
      replies.add(
        UserSummaryReply(
          topic: topic,
          postNumber: jsonInt(value['post_number']),
          likeCount: jsonInt(value['like_count']),
          createdAt: jsonDate(value['created_at']),
        ),
      );
    }

    final links = <UserSummaryLink>[];
    for (final value in jsonObjects(summary['links']).take(maximumResults)) {
      final topic = topicById[jsonInt(value['topic_id'])];
      final url = jsonText(value['url']);
      if (topic == null || url == null) continue;
      links.add(
        UserSummaryLink(
          topic: topic,
          url: url,
          title: jsonText(value['title']),
          clicks: jsonInt(value['clicks']),
          postNumber: jsonInt(value['post_number']),
        ),
      );
    }

    List<UserSummaryUser> users(Object? value) => List.unmodifiable([
      for (final row in jsonObjects(value).take(maximumResults))
        if (UserSummaryUser._fromJson(row, siteUrl) case final user?
            when user.id > 0 && user.username.isNotEmpty)
          user,
    ]);

    final badgeById = <int, Map<String, dynamic>>{};
    for (final badge in jsonObjects(json['badges']).take(maximumResults)) {
      final id = jsonInt(badge['id']);
      if (id > 0) badgeById[id] = badge;
    }
    final badges = <UserSummaryBadge>[];
    for (final grant in jsonObjects(summary['badges']).take(maximumResults)) {
      final definition = badgeById[jsonInt(grant['badge_id'])];
      if (definition == null) continue;
      final name = jsonText(definition['name']);
      if (name == null) continue;
      badges.add(
        UserSummaryBadge(
          id: jsonInt(definition['id']),
          name: name,
          description: jsonHtmlText(definition['description']),
          icon: jsonText(definition['icon']),
          count: jsonInt(grant['count']).clamp(1, 1 << 31),
        ),
      );
    }

    return UserSummary(
      canSeeSummaryStats: summary['can_see_summary_stats'] == true,
      canSeeUserActions: summary['can_see_user_actions'] == true,
      likesGiven: jsonInt(summary['likes_given']),
      likesReceived: jsonInt(summary['likes_received']),
      topicsEntered: jsonInt(summary['topics_entered']),
      postsReadCount: jsonInt(summary['posts_read_count']),
      daysVisited: jsonInt(summary['days_visited']),
      topicCount: jsonInt(summary['topic_count']),
      postCount: jsonInt(summary['post_count']),
      timeRead: jsonInt(summary['time_read']),
      recentTimeRead: jsonInt(summary['recent_time_read']),
      bookmarkCount: jsonInt(summary['bookmark_count']),
      topics: List.unmodifiable(topics),
      replies: List.unmodifiable(replies),
      links: List.unmodifiable(links),
      mostRepliedToUsers: users(summary['most_replied_to_users']),
      mostLikedByUsers: users(summary['most_liked_by_users']),
      mostLikedUsers: users(summary['most_liked_users']),
      topCategories: List.unmodifiable([
        for (final row in jsonObjects(
          summary['top_categories'],
        ).take(maximumResults))
          if (UserSummaryCategory._fromJson(row) case final category?
              when category.id > 0 && category.name.isNotEmpty)
            category,
      ]),
      badges: List.unmodifiable(badges),
    );
  }

  final bool canSeeSummaryStats;
  final bool canSeeUserActions;
  final int likesGiven;
  final int likesReceived;
  final int topicsEntered;
  final int postsReadCount;
  final int daysVisited;
  final int topicCount;
  final int postCount;

  /// Seconds, matching `UserStat#time_read` and `User#recent_time_read`.
  final int timeRead;
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
}

@immutable
final class UserSummaryTopic {
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
        likeCount: jsonInt(json['like_count']),
        createdAt: jsonDate(json['created_at']),
      );

  final int id;
  final String title;
  final String slug;
  final int? categoryId;
  final int likeCount;
  final DateTime? createdAt;
}

@immutable
final class UserSummaryReply {
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
final class UserSummaryLink {
  const UserSummaryLink({
    required this.topic,
    required this.url,
    this.title,
    this.clicks = 0,
    this.postNumber = 0,
  });

  final UserSummaryTopic topic;
  final String url;
  final String? title;
  final int clicks;
  final int postNumber;
}

@immutable
final class UserSummaryUser {
  const UserSummaryUser({
    required this.id,
    required this.username,
    this.name,
    this.avatarUrl,
    this.count = 0,
    this.admin = false,
    this.moderator = false,
    this.trustLevel = 0,
  });

  static UserSummaryUser? _fromJson(Map<String, dynamic> json, String siteUrl) {
    final username = jsonText(json['username']);
    if (username == null) return null;
    return UserSummaryUser(
      id: jsonInt(json['id']),
      username: username,
      name: jsonText(json['name']),
      avatarUrl: resolveAvatarUrl(jsonText(json['avatar_template']), siteUrl),
      count: jsonInt(json['count']),
      admin: json['admin'] == true,
      moderator: json['moderator'] == true,
      trustLevel: jsonInt(json['trust_level']),
    );
  }

  final int id;
  final String username;
  final String? name;
  final String? avatarUrl;
  final int count;
  final bool admin;
  final bool moderator;
  final int trustLevel;

  String get displayName => name ?? username;
}

@immutable
final class UserSummaryCategory {
  const UserSummaryCategory({
    required this.id,
    required this.name,
    required this.slug,
    required this.color,
    this.parentCategoryId,
    this.readRestricted = false,
    this.topicCount = 0,
    this.postCount = 0,
  });

  static UserSummaryCategory? _fromJson(Map<String, dynamic> json) {
    final name = jsonText(json['name']);
    if (name == null) return null;
    return UserSummaryCategory(
      id: jsonInt(json['id']),
      name: name,
      slug: jsonString(json['slug']),
      color: jsonString(json['color'], fallback: '888888'),
      parentCategoryId: jsonIntOrNull(json['parent_category_id']),
      readRestricted: json['read_restricted'] == true,
      topicCount: jsonInt(json['topic_count']),
      postCount: jsonInt(json['post_count']),
    );
  }

  final int id;
  final String name;
  final String slug;
  final String color;
  final int? parentCategoryId;
  final bool readRestricted;
  final int topicCount;
  final int postCount;

  int get colorValue => categoryColorValue(color);
}

@immutable
final class UserSummaryBadge {
  const UserSummaryBadge({
    required this.id,
    required this.name,
    this.description,
    this.icon,
    this.count = 1,
  });

  final int id;
  final String name;
  final String? description;
  final String? icon;
  final int count;
}
