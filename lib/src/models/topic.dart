import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/foundation.dart';

import '../data/store.dart';
import '../plugin_api/plugin_data.dart';
import '../plugin_api/topic_recommendation_source.dart';
import 'discourse_instance.dart';
import 'json.dart';
import 'topic_filter.dart';
import 'topic_tag.dart';

export '../plugin_api/topic_recommendation_source.dart';
export 'topic_tag.dart';

@immutable
class TopicParticipant {
  const TopicParticipant({
    required this.username,
    this.id,
    this.name,
    this.avatarUrl,
    this.postCount = 0,
  });

  static TopicParticipant? fromJson(Map<String, dynamic> json, String siteUrl) {
    final username = jsonText(json['username']);
    if (username == null) return null;
    return TopicParticipant(
      id: jsonIntOrNull(json['id']),
      username: username,
      name: jsonText(json['name']),
      avatarUrl: resolveAvatarUrl(jsonText(json['avatar_template']), siteUrl),
      postCount: jsonInt(json['post_count']),
    );
  }

  final int? id;
  final String username;
  final String? name;
  final String? avatarUrl;
  final int postCount;

  String get displayName => name ?? username;

  @override
  bool operator ==(Object other) =>
      other is TopicParticipant &&
      other.id == id &&
      other.username == username &&
      other.name == name &&
      other.avatarUrl == avatarUrl &&
      other.postCount == postCount;

  @override
  int get hashCode => Object.hash(id, username, name, avatarUrl, postCount);
}

@immutable
class TopicMapLink {
  const TopicMapLink({
    required this.url,
    this.title,
    this.rootDomain,
    this.clicks = 0,
    this.attachment = false,
  });

  static TopicMapLink? fromJson(Map<String, dynamic> json) {
    final url = jsonText(json['url']);
    if (url == null) return null;
    return TopicMapLink(
      url: url,
      title: jsonText(json['title']),
      rootDomain: jsonText(json['root_domain']),
      clicks: jsonInt(json['clicks']),
      attachment: json['attachment'] == true,
    );
  }

  final String url;
  final String? title;
  final String? rootDomain;
  final int clicks;
  final bool attachment;

  String get label => title ?? url;

  @override
  bool operator ==(Object other) =>
      other is TopicMapLink &&
      other.url == url &&
      other.title == title &&
      other.rootDomain == rootDomain &&
      other.clicks == clicks &&
      other.attachment == attachment;

  @override
  int get hashCode => Object.hash(url, title, rootDomain, clicks, attachment);
}

enum TopicNotificationLevel {
  muted(0),
  normal(1),
  tracking(2),
  watching(3);

  const TopicNotificationLevel(this.value);

  final int value;

  static TopicNotificationLevel fromJson(Object? value) =>
      switch (jsonIntOrNull(value)) {
        0 => muted,
        2 => tracking,
        3 => watching,
        _ => normal,
      };
}

enum CategoryNotificationLevel {
  muted(0),
  normal(1),
  tracking(2),
  watching(3),
  watchingFirstPost(4);

  const CategoryNotificationLevel(this.value);

  final int value;

  static CategoryNotificationLevel fromJson(Object? value) =>
      switch (jsonIntOrNull(value)) {
        0 => muted,
        2 => tracking,
        3 => watching,
        4 => watchingFirstPost,
        _ => normal,
      };
}

// Core's reply_count counts directed replies. Lists and topic summaries use
// posts_count minus the opening post; sparse records may only supply a count.
int topicReplyCount(int postsCount, {int fallback = 0}) =>
    postsCount > 0 ? postsCount - 1 : fallback;

/// An entry in the server's ordered topic poster summary.
@immutable
class TopicPoster {
  const TopicPoster({
    required this.userId,
    this.username,
    this.avatarUrl,
    this.description,
    this.latest = false,
    this.single = false,
  });

  final int userId;
  final String? username;
  final String? avatarUrl;
  final String? description;
  final bool latest;
  final bool single;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TopicPoster &&
          other.userId == userId &&
          other.username == username &&
          other.avatarUrl == avatarUrl &&
          other.description == description &&
          other.latest == latest &&
          other.single == single;

  @override
  int get hashCode =>
      Object.hash(userId, username, avatarUrl, description, latest, single);
}

@immutable
class Topic with Storable<Topic> {
  const Topic({
    required this.id,
    required this.title,
    required this.slug,
    this.categoryId,
    this.excerpt,
    this.lastPosterUsername,
    this.lastPosterAvatarUrl,
    this.postsCount = 0,
    int replyCount = 0,
    this.views = 0,
    this.likeCount = 0,
    this.bumpedAt,
    this.pinned = false,
    this.closed = false,
    this.bookmarked = false,
    this.unreadPosts = 0,
    this.newPosts = 0,
    this.seen = true,
    this.isNestedView = false,
    this.privateMessage = false,
    this.hasNewReplies = false,
    this.lastReadPostNumber,
    this.highestPostNumber = 0,
    this.tags = const [],
    this.posterAvatars = const [],
    this.posters = const [],
    this.muted = false,
    this.plugins = PluginData.none,
  }) : _fallbackReplyCount = replyCount;

  static const int maximumPosterAvatars = 5;

  factory Topic.fromJson(
    Map<String, dynamic> json,
    Map<int, String?> avatarsByUserId,
    String siteUrl, {
    Map<String, String?> avatarsByUsername = const {},
    Map<int, String> usernamesByUserId = const {},
    PluginDataDecoder extensions = const EmptyPluginDataDecoder(),
  }) {
    final posters = <TopicPoster>[];
    final seenIds = <int>{};
    for (final poster in jsonObjects(json['posters'])) {
      final user = jsonObject(poster['user']);
      final id = jsonIntOrNull(poster['user_id']) ?? jsonIntOrNull(user['id']);
      if (id == null || !seenIds.add(id)) continue;
      final username = usernamesByUserId[id] ?? jsonText(user['username']);
      final avatarUrl =
          avatarsByUserId[id] ??
          resolveAvatarUrl(jsonText(user['avatar_template']), siteUrl);
      if (username == null && avatarUrl == null) continue;
      final extras = jsonString(poster['extras']).split(' ');
      posters.add(
        TopicPoster(
          userId: id,
          username: username,
          avatarUrl: avatarUrl,
          description: jsonText(poster['description']),
          latest: extras.contains('latest'),
          single: extras.contains('single'),
        ),
      );
      if (posters.length == maximumPosterAvatars) break;
    }

    return Topic(
      id: jsonInt(json['id']),
      title: jsonTitle(json['title'], json['fancy_title']),
      slug: jsonString(json['slug']),
      excerpt: jsonHtmlText(json['excerpt']),
      lastPosterUsername: jsonText(json['last_poster_username']),
      lastPosterAvatarUrl:
          avatarsByUsername[jsonText(
            json['last_poster_username'],
          )?.toLowerCase()],
      categoryId: json['category_id'] == null
          ? null
          : jsonInt(json['category_id']),
      postsCount: jsonInt(json['posts_count']),
      replyCount: jsonInt(json['reply_count']),
      views: jsonInt(json['views']),
      likeCount: jsonInt(json['like_count']),
      bumpedAt: jsonDate(json['bumped_at']),
      pinned: json['pinned'] == true,
      closed: json['closed'] == true,
      bookmarked: json['bookmarked'] == true,
      unreadPosts: jsonInt(json['unread_posts']),
      newPosts: jsonInt(json['new_posts']),
      seen: json['unseen'] != true,
      isNestedView: json['is_nested_view'] == true,
      privateMessage: json['archetype'] == 'private_message',
      hasNewReplies: json['has_new_replies'] == true,
      lastReadPostNumber: jsonIntOrNull(json['last_read_post_number']),
      highestPostNumber: jsonInt(json['highest_post_number']),
      tags: List.unmodifiable(
        jsonArray(json['tags']).map(TopicTag.parse).whereType<TopicTag>(),
      ),
      posterAvatars: List.unmodifiable(
        posters.map((p) => p.avatarUrl).whereType<String>(),
      ),
      posters: List.unmodifiable(posters),
      muted:
          json['muted'] == true ||
          jsonIntOrNull(json['notification_level']) == 0,
      plugins: extensions.readTopic(json, siteUrl),
    );
  }

  factory Topic.fromRecommendationJson(
    Map<String, dynamic> json,
    String siteUrl, {
    PluginDataDecoder extensions = const EmptyPluginDataDecoder(),
  }) {
    final avatars = <int, String?>{};
    final avatarsByUsername = <String, String?>{};
    final usernamesByUserId = <int, String>{};
    for (final poster in jsonObjects(json['posters'])) {
      final user = jsonObject(poster['user']);
      final id = jsonIntOrNull(user['id']);
      if (id == null) continue;
      avatars[id] = resolveAvatarUrl(
        jsonText(user['avatar_template']),
        siteUrl,
      );
      final username = jsonText(user['username']);
      if (username != null) {
        avatarsByUsername[username.toLowerCase()] = avatars[id];
        usernamesByUserId[id] = username;
      }
    }
    return Topic.fromJson(
      json,
      avatars,
      siteUrl,
      avatarsByUsername: avatarsByUsername,
      usernamesByUserId: usernamesByUserId,
      extensions: extensions,
    );
  }

  final int id;
  final String title;
  final String slug;
  final int? categoryId;
  final String? excerpt;
  final String? lastPosterUsername;
  final String? lastPosterAvatarUrl;
  final int postsCount;
  final int _fallbackReplyCount;

  int get replyCount =>
      topicReplyCount(postsCount, fallback: _fallbackReplyCount);

  final int views;
  final int likeCount;
  final DateTime? bumpedAt;
  final bool pinned;
  final bool closed;
  final bool bookmarked;

  final int unreadPosts;
  final int newPosts;

  final bool seen;

  final bool isNestedView;

  final bool privateMessage;

  final bool hasNewReplies;

  final int? lastReadPostNumber;

  final int highestPostNumber;

  final List<TopicTag> tags;

  final List<String> posterAvatars;
  final List<TopicPoster> posters;
  final bool muted;

  final PluginData plugins;

  int get unreadCount => unreadPosts > 0 ? unreadPosts : newPosts;

  bool get hasUnread => unreadCount > 0;

  bool get visited =>
      lastReadPostNumber != null && lastReadPostNumber! >= highestPostNumber;

  bool get showUnreadCount => !isNestedView && unreadCount > 0;
  bool get showNewTopicDot => !isNestedView && !seen;
  bool get showNewRepliesDot => isNestedView && hasNewReplies;

  bool get hasUnseenActivity =>
      !seen || (isNestedView ? hasNewReplies : hasUnread);

  int? get lastUnreadPostNumber {
    // Nested topics route to the conversation root. A numbered URL would open
    // them through the flat post-stream semantics core explicitly avoids.
    if (isNestedView) return null;
    if (highestPostNumber <= 0) return null;
    final next = (lastReadPostNumber ?? 0) + 1;
    return next > highestPostNumber ? highestPostNumber : next;
  }

  String get path => '/t/$slug/$id';

  @override
  Object get storeId => id;

  @override
  Topic merge(Topic incoming) {
    final merged = incoming.copyWith(
      posterAvatars: incoming.posterAvatars.isEmpty ? posterAvatars : null,
      posters: incoming.posters.isEmpty ? posters : null,
    );
    return this == merged ? this : merged;
  }

  Topic copyWith({
    String? title,
    int? categoryId,
    bool clearCategory = false,
    int? postsCount,
    int? likeCount,
    int? lastReadPostNumber,
    int? highestPostNumber,
    List<TopicTag>? tags,
    List<String>? posterAvatars,
    List<TopicPoster>? posters,
    PluginData? plugins,
    bool? bookmarked,
    bool? pinned,
    bool? closed,
    bool? privateMessage,
    int? unreadPosts,
    int? newPosts,
    bool? seen,
    bool markRead = false,
  }) => Topic(
    id: id,
    title: title ?? this.title,
    slug: slug,
    excerpt: excerpt,
    lastPosterUsername: lastPosterUsername,
    lastPosterAvatarUrl: lastPosterAvatarUrl,
    categoryId: clearCategory ? null : (categoryId ?? this.categoryId),
    postsCount: postsCount ?? this.postsCount,
    replyCount: replyCount,
    views: views,
    likeCount: likeCount ?? this.likeCount,
    bumpedAt: bumpedAt,
    pinned: pinned ?? this.pinned,
    closed: closed ?? this.closed,
    bookmarked: bookmarked ?? this.bookmarked,
    unreadPosts: markRead ? 0 : unreadPosts ?? this.unreadPosts,
    newPosts: markRead ? 0 : newPosts ?? this.newPosts,
    seen: markRead ? true : seen ?? this.seen,
    isNestedView: isNestedView,
    privateMessage: privateMessage ?? this.privateMessage,
    hasNewReplies: markRead ? false : hasNewReplies,
    lastReadPostNumber: markRead && this.highestPostNumber > 0
        ? this.highestPostNumber
        : lastReadPostNumber ?? this.lastReadPostNumber,
    highestPostNumber: highestPostNumber ?? this.highestPostNumber,
    tags: tags == null ? this.tags : List.unmodifiable(tags),
    posterAvatars: posterAvatars == null
        ? this.posterAvatars
        : List.unmodifiable(posterAvatars),
    posters: posters == null ? this.posters : List.unmodifiable(posters),
    muted: muted,
    plugins: plugins ?? this.plugins,
  );

  Topic withPlugins(PluginData next) => Topic(
    id: id,
    title: title,
    slug: slug,
    excerpt: excerpt,
    lastPosterUsername: lastPosterUsername,
    lastPosterAvatarUrl: lastPosterAvatarUrl,
    categoryId: categoryId,
    postsCount: postsCount,
    replyCount: replyCount,
    views: views,
    likeCount: likeCount,
    bumpedAt: bumpedAt,
    pinned: pinned,
    closed: closed,
    bookmarked: bookmarked,
    unreadPosts: unreadPosts,
    newPosts: newPosts,
    seen: seen,
    isNestedView: isNestedView,
    privateMessage: privateMessage,
    hasNewReplies: hasNewReplies,
    lastReadPostNumber: lastReadPostNumber,
    highestPostNumber: highestPostNumber,
    tags: tags,
    posterAvatars: posterAvatars,
    posters: posters,
    muted: muted,
    plugins: next,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Topic &&
          other.id == id &&
          other.title == title &&
          other.slug == slug &&
          other.excerpt == excerpt &&
          other.lastPosterUsername == lastPosterUsername &&
          other.lastPosterAvatarUrl == lastPosterAvatarUrl &&
          other.categoryId == categoryId &&
          other.postsCount == postsCount &&
          other.replyCount == replyCount &&
          other.views == views &&
          other.likeCount == likeCount &&
          other.bumpedAt == bumpedAt &&
          other.pinned == pinned &&
          other.closed == closed &&
          other.bookmarked == bookmarked &&
          other.unreadPosts == unreadPosts &&
          other.newPosts == newPosts &&
          other.seen == seen &&
          other.isNestedView == isNestedView &&
          other.privateMessage == privateMessage &&
          other.hasNewReplies == hasNewReplies &&
          other.lastReadPostNumber == lastReadPostNumber &&
          other.highestPostNumber == highestPostNumber &&
          listEquals(other.tags, tags) &&
          listEquals(other.posterAvatars, posterAvatars) &&
          listEquals(other.posters, posters) &&
          other.muted == muted &&
          other.plugins == plugins;

  @override
  int get hashCode => Object.hashAll([
    id,
    title,
    slug,
    excerpt,
    lastPosterUsername,
    lastPosterAvatarUrl,
    categoryId,
    postsCount,
    replyCount,
    views,
    likeCount,
    bumpedAt,
    pinned,
    closed,
    bookmarked,
    unreadPosts,
    newPosts,
    seen,
    isNestedView,
    privateMessage,
    hasNewReplies,
    lastReadPostNumber,
    highestPostNumber,
    Object.hashAll(tags),
    Object.hashAll(posterAvatars),
    Object.hashAll(posters),
    muted,
    plugins,
  ]);
}

@immutable
class TopicRecommendationSource {
  const TopicRecommendationSource({
    required this.definition,
    this.topics = const [],
  });

  final TopicRecommendationSourceDefinition definition;
  final List<Topic> topics;

  TopicRecommendationSourceId get id => definition.id;
  String get label => definition.label;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TopicRecommendationSource &&
          other.definition == definition &&
          listEquals(other.topics, topics);

  @override
  int get hashCode => Object.hash(definition, Object.hashAll(topics));
}

@immutable
class TopicRecommendations {
  const TopicRecommendations({this.sources = const []});

  static TopicRecommendations? fromJson(
    Map<String, dynamic> json,
    String siteUrl, {
    PluginDataDecoder extensions = const EmptyPluginDataDecoder(),
    TopicRecommendationSourceDecoder recommendationSources =
        const EmptyTopicRecommendationSourceDecoder(),
  }) {
    final decoded = <TopicRecommendationSourcePayload>[
      if (json.containsKey('suggested_topics'))
        TopicRecommendationSourcePayload(
          definition: coreSuggestedTopicRecommendationSource,
          topicRows: List.unmodifiable(jsonObjects(json['suggested_topics'])),
        ),
      ...recommendationSources.readTopicRecommendationSources(json),
    ];
    if (decoded.isEmpty) return null;
    return TopicRecommendations(
      sources: List.unmodifiable([
        for (final payload in decoded)
          TopicRecommendationSource(
            definition: payload.definition,
            topics: List.unmodifiable([
              for (final topic in payload.topicRows)
                Topic.fromRecommendationJson(
                  topic,
                  siteUrl,
                  extensions: extensions,
                ),
            ]),
          ),
      ]),
    );
  }

  final List<TopicRecommendationSource> sources;

  bool get isNotEmpty => sources.any((source) => source.topics.isNotEmpty);

  TopicRecommendationSource? source(TopicRecommendationSourceId id) {
    for (final source in sources) {
      if (source.id == id) return source;
    }
    return null;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TopicRecommendations && listEquals(other.sources, sources);

  @override
  int get hashCode => Object.hashAll(sources);
}

@immutable
class TopicList {
  static const int maximumPageSize = 100;

  static const int maximumUsersPerPage = maximumPageSize * 5;

  static const int maximumCategoriesPerPage = maximumPageSize * 2;

  static const int maximumTagsPerPage = 100;

  const TopicList({
    required this.topics,
    this.categories = const [],
    this.moreTopicsUrl,
    this.canCreateTopic = false,
    this.filterOptions = const [],
    this.filter,
    this.tagIds = const [],
  });

  factory TopicList.fromJson(
    Map<String, dynamic> json,
    String siteUrl, {
    PluginDataDecoder extensions = const EmptyPluginDataDecoder(),
  }) {
    final avatars = <int, String?>{};
    final avatarsByUsername = <String, String?>{};
    final usernamesByUserId = <int, String>{};
    for (final value in jsonArray(json['users']).take(maximumUsersPerPage)) {
      if (value is! Map<String, dynamic>) continue;
      final user = value;
      final id = jsonIntOrNull(user['id']);
      if (id == null) continue;
      avatars[id] = resolveAvatarUrl(
        jsonText(user['avatar_template']),
        siteUrl,
      );
      final username = jsonText(user['username']);
      if (username != null) {
        avatarsByUsername[username.toLowerCase()] = avatars[id];
        usernamesByUserId[id] = username;
      }
    }

    final list = jsonObject(json['topic_list']);
    return TopicList(
      topics: List.unmodifiable([
        for (final value in jsonArray(list['topics']).take(maximumPageSize))
          if (value is Map<String, dynamic>)
            Topic.fromJson(
              value,
              avatars,
              siteUrl,
              avatarsByUsername: avatarsByUsername,
              usernamesByUserId: usernamesByUserId,
              extensions: extensions,
            ),
      ]),
      categories: List.unmodifiable([
        for (final value in jsonObjects(
          list['categories'],
        ).take(maximumCategoriesPerPage))
          TopicCategory.fromJson(value),
      ]),
      moreTopicsUrl: DiscourseInstance.pathAndQueryWithinUrl(
        siteUrl,
        jsonText(list['more_topics_url']),
      ),
      canCreateTopic: list['can_create_topic'] == true,
      filterOptions: List.unmodifiable([
        for (final value in jsonArray(list['filter_option_info']))
          ?TopicFilterOption.parse(value),
      ]),
      filter: jsonText(list['filter']),
      tagIds: List.unmodifiable({
        for (final tag in jsonObjects(list['tags']).take(maximumTagsPerPage))
          if (jsonIntOrNull(tag['id']) case final id? when id > 0) id,
      }),
    );
  }

  final List<Topic> topics;

  final List<TopicCategory> categories;

  /// The next page's address below the forum's subfolder, so that every
  /// request appends it to the site URL the way it appends its own paths.
  final String? moreTopicsUrl;
  final bool canCreateTopic;
  final List<TopicFilterOption> filterOptions;

  /// The list the server resolved the request to, such as a category's
  /// default view. Older sites leave it out.
  final String? filter;

  /// The tags the server filtered the list by, synonyms resolved to the tag
  /// they stand for. Empty unless tagging is enabled.
  final List<int> tagIds;

  String? get nextPagePath => asJsonPath(moreTopicsUrl);

  static const int _maximumPagePathLength = 2048;

  static String? asJsonPath(String? url) {
    if (url == null || url.isEmpty || url.length > _maximumPagePathLength) {
      return null;
    }
    final uri = Uri.tryParse(url);
    if (uri == null ||
        uri.hasScheme ||
        uri.hasAuthority ||
        uri.userInfo.isNotEmpty ||
        uri.hasFragment ||
        uri.path.isEmpty ||
        !uri.path.startsWith('/')) {
      return null;
    }
    if (uri.path.endsWith('.json')) return uri.toString();
    return uri.replace(path: '${uri.path}.json').toString();
  }
}

@immutable
class CategoryFeaturedTopic {
  const CategoryFeaturedTopic({
    required this.id,
    required this.title,
    required this.slug,
    this.pinned = false,
    this.closed = false,
    this.archived = false,
    this.lastReadPostNumber,
    this.highestPostNumber = 0,
    this.activityAt,
  });

  factory CategoryFeaturedTopic.fromJson(Map<String, dynamic> json) =>
      CategoryFeaturedTopic(
        id: jsonInt(json['id']),
        title: jsonTitle(json['title'], json['fancy_title']),
        slug: jsonString(json['slug']),
        pinned: json['pinned'] == true,
        closed: json['closed'] == true,
        archived: json['archived'] == true,
        lastReadPostNumber: jsonIntOrNull(json['last_read_post_number']),
        highestPostNumber: jsonInt(json['highest_post_number']),
        activityAt:
            jsonDate(json['bumped_at']) ??
            jsonDate(json['last_posted_at']) ??
            jsonDate(json['created_at']),
      );

  final int id;
  final String title;
  final String slug;
  final bool pinned;
  final bool closed;
  final bool archived;
  final int? lastReadPostNumber;
  final int highestPostNumber;
  final DateTime? activityAt;

  int? get firstUnreadPostNumber {
    if (highestPostNumber <= 0) return null;
    final next = (lastReadPostNumber ?? 0) + 1;
    if (next <= 1) return 1;
    return next > highestPostNumber ? highestPostNumber : next;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CategoryFeaturedTopic &&
          other.id == id &&
          other.title == title &&
          other.slug == slug &&
          other.pinned == pinned &&
          other.closed == closed &&
          other.archived == archived &&
          other.lastReadPostNumber == lastReadPostNumber &&
          other.highestPostNumber == highestPostNumber &&
          other.activityAt == activityAt;

  @override
  int get hashCode => Object.hash(
    id,
    title,
    slug,
    pinned,
    closed,
    archived,
    lastReadPostNumber,
    highestPostNumber,
    activityAt,
  );
}

/// A category detail that only some category payloads carry. A topic list on
/// a site that lazy-loads categories embeds its categories at badge level
/// (core's `CategoryBadgeSerializer`), which carries none of them, and only
/// the category list reports featured topics or which category is
/// Uncategorized. A payload that leaves one out says nothing about it.
enum _CategoryDetail {
  permission('permission'),
  minimumRequiredTags('minimum_required_tags'),
  topicCount('topic_count'),
  descriptionExcerpt('description_excerpt', 'description_text'),
  position('position'),
  isUncategorized('is_uncategorized'),
  notificationLevel('notification_level'),
  featuredTopics('topics'),
  topicTemplate('topic_template');

  const _CategoryDetail(this.key, [this.alternateKey]);

  final String key;
  final String? alternateKey;

  bool isReportedBy(Map<String, dynamic> json) =>
      json.containsKey(key) ||
      (alternateKey != null && json.containsKey(alternateKey));
}

@immutable
class TopicCategory with Storable<TopicCategory> {
  const TopicCategory({
    required this.id,
    required this.name,
    required this.color,
    this.slug = '',
    this.parentCategoryId,
    this.permission,
    this.minimumRequiredTags = 0,
    this.styleType = 'square',
    this.icon,
    this.emoji,
    this.readRestricted = false,
    this.topicCount = 0,
    this.descriptionExcerpt,
    this.position,
    this.isUncategorized = false,
    this.notificationLevel = CategoryNotificationLevel.normal,
    this.featuredTopics = const [],
    this.topicTemplate,
  }) : _unreported = const {};

  const TopicCategory._({
    required this.id,
    required this.name,
    required this.color,
    required this.slug,
    required this.parentCategoryId,
    required this.permission,
    required this.minimumRequiredTags,
    required this.styleType,
    required this.icon,
    required this.emoji,
    required this.readRestricted,
    required this.topicCount,
    required this.descriptionExcerpt,
    required this.position,
    required this.isUncategorized,
    required this.notificationLevel,
    required this.featuredTopics,
    required this.topicTemplate,
    required this._unreported,
  });

  factory TopicCategory.fromJson(Map<String, dynamic> json) => TopicCategory._(
    id: jsonInt(json['id']),
    name: jsonString(json['name']),
    color: jsonString(json['color'], fallback: '888888'),
    slug: jsonString(json['slug']),
    parentCategoryId: json['parent_category_id'] == null
        ? null
        : jsonInt(json['parent_category_id']),
    permission: jsonIntOrNull(json['permission']),
    minimumRequiredTags: jsonInt(json['minimum_required_tags']),
    styleType: jsonText(json['style_type']) ?? 'square',
    icon: jsonText(json['icon']),
    emoji: jsonText(json['emoji']),
    readRestricted: json['read_restricted'] == true,
    topicCount: jsonInt(json['topic_count']),
    descriptionExcerpt:
        jsonText(json['description_excerpt']) ??
        jsonText(json['description_text']),
    position: jsonIntOrNull(json['position']),
    isUncategorized: json['is_uncategorized'] == true,
    notificationLevel: CategoryNotificationLevel.fromJson(
      json['notification_level'],
    ),
    featuredTopics: List.unmodifiable([
      for (final topic in jsonObjects(json['topics']))
        if (jsonIntOrNull(topic['id']) case final id? when id > 0)
          CategoryFeaturedTopic.fromJson(topic),
    ]),
    // Kept exactly as the site holds it: core inserts it verbatim and compares
    // the body with it to tell an untouched template from an edited one.
    topicTemplate: switch (json['topic_template']) {
      final String template when template.trim().isNotEmpty => template,
      _ => null,
    },
    unreported: {
      for (final detail in _CategoryDetail.values)
        if (!detail.isReportedBy(json)) detail,
    },
  );

  final int id;
  final String name;

  final String color;
  final String slug;

  final int? parentCategoryId;

  final int? permission;
  final int minimumRequiredTags;

  final String styleType;
  final String? icon;
  final String? emoji;

  final bool readRestricted;
  final int topicCount;
  final String? descriptionExcerpt;
  final int? position;

  final bool isUncategorized;

  final CategoryNotificationLevel notificationLevel;

  final List<CategoryFeaturedTopic> featuredTopics;

  /// The body a new topic in this category starts from, or null when it has
  /// none.
  final String? topicTemplate;

  /// The details this category's payload left out, which read as their
  /// defaults here. A merge must not mistake them for the site clearing what
  /// a fuller payload reported. Equality compares values: an unreported
  /// detail and its default merge alike.
  final Set<_CategoryDetail> _unreported;

  bool get canCreateTopic => permission == 1;
  bool get isMuted => notificationLevel == CategoryNotificationLevel.muted;

  TopicCategory withNotificationLevel(CategoryNotificationLevel level) =>
      TopicCategory._(
        id: id,
        name: name,
        color: color,
        slug: slug,
        parentCategoryId: parentCategoryId,
        permission: permission,
        minimumRequiredTags: minimumRequiredTags,
        styleType: styleType,
        icon: icon,
        emoji: emoji,
        readRestricted: readRestricted,
        topicCount: topicCount,
        descriptionExcerpt: descriptionExcerpt,
        position: position,
        isUncategorized: isUncategorized,
        notificationLevel: level,
        featuredTopics: featuredTopics,
        topicTemplate: topicTemplate,
        unreported: _unreported.difference(const {
          _CategoryDetail.notificationLevel,
        }),
      );

  int get colorValue => categoryColorValue(color);

  @override
  Object get storeId => id;

  /// A badge-level category still updates what it carries, such as the name,
  /// color, parent and whether the category is restricted, while the
  /// template, create permission and required tags held from a fuller payload
  /// stay. A payload that reports a detail as empty clears it.
  @override
  TopicCategory merge(TopicCategory incoming) {
    final merged = incoming._unreported.isEmpty
        ? incoming
        : incoming._completedBy(this);
    return this == merged ? this : merged;
  }

  TopicCategory _completedBy(TopicCategory held) {
    T reported<T>(_CategoryDetail detail, T incoming, T kept) =>
        _unreported.contains(detail) ? kept : incoming;
    return TopicCategory._(
      id: id,
      name: name,
      color: color,
      slug: slug,
      parentCategoryId: parentCategoryId,
      permission: reported(
        _CategoryDetail.permission,
        permission,
        held.permission,
      ),
      minimumRequiredTags: reported(
        _CategoryDetail.minimumRequiredTags,
        minimumRequiredTags,
        held.minimumRequiredTags,
      ),
      styleType: styleType,
      icon: icon,
      emoji: emoji,
      readRestricted: readRestricted,
      topicCount: reported(
        _CategoryDetail.topicCount,
        topicCount,
        held.topicCount,
      ),
      descriptionExcerpt: reported(
        _CategoryDetail.descriptionExcerpt,
        descriptionExcerpt,
        held.descriptionExcerpt,
      ),
      position: reported(_CategoryDetail.position, position, held.position),
      isUncategorized: reported(
        _CategoryDetail.isUncategorized,
        isUncategorized,
        held.isUncategorized,
      ),
      notificationLevel: reported(
        _CategoryDetail.notificationLevel,
        notificationLevel,
        held.notificationLevel,
      ),
      featuredTopics: reported(
        _CategoryDetail.featuredTopics,
        featuredTopics,
        held.featuredTopics,
      ),
      topicTemplate: reported(
        _CategoryDetail.topicTemplate,
        topicTemplate,
        held.topicTemplate,
      ),
      unreported: _unreported.intersection(held._unreported),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TopicCategory &&
          other.id == id &&
          other.name == name &&
          other.color == color &&
          other.slug == slug &&
          other.parentCategoryId == parentCategoryId &&
          other.permission == permission &&
          other.minimumRequiredTags == minimumRequiredTags &&
          other.styleType == styleType &&
          other.icon == icon &&
          other.emoji == emoji &&
          other.readRestricted == readRestricted &&
          other.topicCount == topicCount &&
          other.descriptionExcerpt == descriptionExcerpt &&
          other.position == position &&
          other.isUncategorized == isUncategorized &&
          other.notificationLevel == notificationLevel &&
          listEquals(other.featuredTopics, featuredTopics) &&
          other.topicTemplate == topicTemplate;

  @override
  int get hashCode => Object.hash(
    id,
    name,
    color,
    slug,
    parentCategoryId,
    permission,
    minimumRequiredTags,
    styleType,
    icon,
    emoji,
    readRestricted,
    topicCount,
    descriptionExcerpt,
    position,
    isUncategorized,
    notificationLevel,
    Object.hashAll(featuredTopics),
    topicTemplate,
  );
}

@immutable
class TopicComposerCapabilities {
  const TopicComposerCapabilities({
    this.canTagTopics = false,
    this.canCreateTag = false,
    this.tagsFilterRegexp,
    this.uncategorizedCategoryId,
    this.maxTagLength,
    this.maxTagsPerTopic,
  });

  factory TopicComposerCapabilities.fromJson(Map<String, dynamic> json) =>
      TopicComposerCapabilities(
        canTagTopics: json['can_tag_topics'] == true,
        canCreateTag: json['can_create_tag'] == true,
        tagsFilterRegexp: jsonText(json['tags_filter_regexp']),
        uncategorizedCategoryId: jsonIntOrNull(
          json['uncategorized_category_id'],
        ),
        maxTagLength: jsonIntOrNull(json['max_tag_length']),
        maxTagsPerTopic: jsonIntOrNull(json['max_tags_per_topic']),
      );

  final bool canTagTopics;
  final bool canCreateTag;
  final String? tagsFilterRegexp;
  final int? uncategorizedCategoryId;
  final int? maxTagLength;
  final int? maxTagsPerTopic;

  bool canCreateTagNamed(String name) {
    if (!canCreateTag || name.isEmpty) return false;
    if (maxTagLength case final maximum?) {
      if (name.runes.length > maximum) return false;
    }
    final source = tagsFilterRegexp;
    if (source == null || source.isEmpty) return true;
    try {
      var pattern = source;
      if (pattern.startsWith('/') && pattern.lastIndexOf('/') > 0) {
        pattern = pattern.substring(1, pattern.lastIndexOf('/'));
      }
      return !RegExp(pattern).hasMatch(name);
    } catch (_) {
      return false;
    }
  }
}

/// What `PUT /t/{id}.json` answers once a metadata write is applied.
///
/// The site cleans a title as it stores it, and the next write's
/// `original_title` is checked against the stored spelling, so a client that
/// keeps the typed one has its next metadata write rejected as a conflict.
@immutable
class TopicUpdate {
  const TopicUpdate({this.title, this.tags});

  factory TopicUpdate.fromJson(Map<String, dynamic> json) {
    final topic = jsonObject(json['basic_topic']);
    return TopicUpdate(
      // Compared verbatim by the next write, so it is kept exactly as sent.
      title: switch (topic['title']) {
        final String title when title.trim().isNotEmpty => title,
        _ => null,
      },
      // Present only when the write carried tags.
      tags: json['tags'] is List<dynamic>
          ? List.unmodifiable(
              jsonArray(json['tags']).map(TopicTag.parse).whereType<TopicTag>(),
            )
          : null,
    );
  }

  /// Null when the answer does not carry one; the title sent stands then.
  final String? title;

  /// The visible tags the site stored, or null when the answer has none.
  final List<TopicTag>? tags;
}

@immutable
class TopicTagSearch {
  const TopicTagSearch({
    this.tags = const [],
    this.forbidden = false,
    this.forbiddenMessage,
  });

  factory TopicTagSearch.fromJson(
    Map<String, dynamic> json, {
    int limit = maximumResults,
  }) {
    final boundedLimit = limit.clamp(0, maximumResults).toInt();
    return TopicTagSearch(
      tags: List.unmodifiable([
        for (final entry in jsonArray(json['results']).take(boundedLimit))
          if (entry is Map<String, dynamic>)
            if (jsonText(entry['name']) case final name?)
              TopicTag(
                id: jsonIntOrNull(entry['id']),
                name: name,
                slug: jsonText(entry['slug']),
                count: jsonInt(entry['count']),
                disabled: entry['disabled'] == true,
                disabledReason: jsonText(entry['title']),
              ),
      ]),
      forbidden:
          json['forbidden'] == true ||
          (json['forbidden'] is List &&
              (json['forbidden'] as List).isNotEmpty) ||
          (jsonText(json['forbidden'])?.isNotEmpty ?? false),
      forbiddenMessage:
          jsonText(json['forbidden_message']) ?? jsonText(json['forbidden']),
    );
  }

  static const int maximumResults = 20;

  final List<TopicTag> tags;
  final bool forbidden;
  final String? forbiddenMessage;

  List<TopicTag> get results => tags;
  bool get isForbidden => forbidden;
  String? get explanation =>
      forbiddenMessage ?? (forbidden ? appL10n.tagsAreNotAllowedHere : null);
}
