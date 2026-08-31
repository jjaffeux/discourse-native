import 'package:flutter/foundation.dart';

import '../data/store.dart';
import '../plugin_api/plugin_data.dart';
import '../plugin_api/topic_recommendation_source.dart';
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

@immutable
class Topic with Storable<Topic> {
  const Topic({
    required this.id,
    required this.title,
    required this.slug,
    this.categoryId,
    this.postsCount = 0,
    this.replyCount = 0,
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
    this.plugins = PluginData.none,
  });

  static const int maximumPosterAvatars = 3;

  factory Topic.fromJson(
    Map<String, dynamic> json,
    Map<int, String?> avatarsByUserId,
    String siteUrl, {
    PluginDataDecoder extensions = const EmptyPluginDataDecoder(),
  }) {
    final resolvedPosters = <String>[];
    for (final poster in jsonObjects(json['posters'])) {
      final id =
          jsonIntOrNull(poster['user_id']) ??
          jsonIntOrNull(jsonObject(poster['user'])['id']);
      final avatar = id == null ? null : avatarsByUserId[id];
      if (avatar != null) {
        resolvedPosters.add(avatar);
        if (resolvedPosters.length == maximumPosterAvatars) break;
      }
    }
    final posters = List<String>.unmodifiable(resolvedPosters);

    return Topic(
      id: jsonInt(json['id']),
      title: jsonTitle(json['title'], json['fancy_title']),
      slug: jsonString(json['slug']),
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
      posterAvatars: posters,
      plugins: extensions.readTopic(json, siteUrl),
    );
  }

  factory Topic.fromRecommendationJson(
    Map<String, dynamic> json,
    String siteUrl, {
    PluginDataDecoder extensions = const EmptyPluginDataDecoder(),
  }) {
    final avatars = <int, String?>{};
    for (final poster in jsonObjects(json['posters'])) {
      final user = jsonObject(poster['user']);
      final id = jsonIntOrNull(user['id']);
      if (id == null) continue;
      avatars[id] = resolveAvatarUrl(
        jsonText(user['avatar_template']),
        siteUrl,
      );
    }
    return Topic.fromJson(json, avatars, siteUrl, extensions: extensions);
  }

  final int id;
  final String title;
  final String slug;
  final int? categoryId;
  final int postsCount;
  final int replyCount;
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
    final merged = incoming.posterAvatars.isEmpty
        ? incoming.copyWith(posterAvatars: posterAvatars)
        : incoming;
    return this == merged ? this : merged;
  }

  Topic copyWith({
    String? title,
    int? categoryId,
    bool clearCategory = false,
    int? postsCount,
    int? lastReadPostNumber,
    int? highestPostNumber,
    List<TopicTag>? tags,
    List<String>? posterAvatars,
    PluginData? plugins,
    bool? bookmarked,
    bool? pinned,
    bool? closed,
    bool? privateMessage,
    bool markRead = false,
  }) => Topic(
    id: id,
    title: title ?? this.title,
    slug: slug,
    categoryId: clearCategory ? null : (categoryId ?? this.categoryId),
    postsCount: postsCount ?? this.postsCount,
    replyCount: replyCount,
    views: views,
    likeCount: likeCount,
    bumpedAt: bumpedAt,
    pinned: pinned ?? this.pinned,
    closed: closed ?? this.closed,
    bookmarked: bookmarked ?? this.bookmarked,
    unreadPosts: markRead ? 0 : unreadPosts,
    newPosts: markRead ? 0 : newPosts,
    seen: markRead ? true : seen,
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
    plugins: plugins ?? this.plugins,
  );

  Topic withPlugins(PluginData next) => Topic(
    id: id,
    title: title,
    slug: slug,
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
    plugins: next,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Topic &&
          other.id == id &&
          other.title == title &&
          other.slug == slug &&
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
          other.plugins == plugins;

  @override
  int get hashCode => Object.hashAll([
    id,
    title,
    slug,
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

  const TopicList({
    required this.topics,
    this.categories = const [],
    this.moreTopicsUrl,
    this.canCreateTopic = false,
    this.filterOptions = const [],
  });

  factory TopicList.fromJson(
    Map<String, dynamic> json,
    String siteUrl, {
    PluginDataDecoder extensions = const EmptyPluginDataDecoder(),
  }) {
    final avatars = <int, String?>{};
    for (final value in jsonArray(json['users']).take(maximumUsersPerPage)) {
      if (value is! Map<String, dynamic>) continue;
      final user = value;
      final id = jsonIntOrNull(user['id']);
      if (id == null) continue;
      avatars[id] = resolveAvatarUrl(
        jsonText(user['avatar_template']),
        siteUrl,
      );
    }

    final list = jsonObject(json['topic_list']);
    return TopicList(
      topics: List.unmodifiable([
        for (final value in jsonArray(list['topics']).take(maximumPageSize))
          if (value is Map<String, dynamic>)
            Topic.fromJson(value, avatars, siteUrl, extensions: extensions),
      ]),
      categories: List.unmodifiable([
        for (final value in jsonObjects(
          list['categories'],
        ).take(maximumCategoriesPerPage))
          TopicCategory.fromJson(value),
      ]),
      moreTopicsUrl: jsonText(list['more_topics_url']),
      canCreateTopic: list['can_create_topic'] == true,
      filterOptions: List.unmodifiable([
        for (final value in jsonArray(list['filter_option_info']))
          ?TopicFilterOption.parse(value),
      ]),
    );
  }

  final List<Topic> topics;

  final List<TopicCategory> categories;

  final String? moreTopicsUrl;
  final bool canCreateTopic;
  final List<TopicFilterOption> filterOptions;

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
      );

  final int id;
  final String title;
  final String slug;
  final bool pinned;
  final bool closed;
  final bool archived;
  final int? lastReadPostNumber;
  final int highestPostNumber;

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
          other.highestPostNumber == highestPostNumber;

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
  );
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
    this.position,
    this.isUncategorized = false,
    this.notificationLevel = 1,
    this.featuredTopics = const [],
  });

  factory TopicCategory.fromJson(Map<String, dynamic> json) => TopicCategory(
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
    position: jsonIntOrNull(json['position']),
    isUncategorized: json['is_uncategorized'] == true,
    notificationLevel: jsonIntOrNull(json['notification_level']) ?? 1,
    featuredTopics: List.unmodifiable([
      for (final topic in jsonObjects(json['topics']))
        if (jsonIntOrNull(topic['id']) case final id? when id > 0)
          CategoryFeaturedTopic.fromJson(topic),
    ]),
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
  final int? position;

  final bool isUncategorized;

  final int notificationLevel;

  final List<CategoryFeaturedTopic> featuredTopics;

  bool get canCreateTopic => permission == 1;
  bool get isMuted => notificationLevel == 0;

  int get colorValue => categoryColorValue(color);

  @override
  Object get storeId => id;

  @override
  TopicCategory merge(TopicCategory incoming) =>
      this == incoming ? this : incoming;

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
          other.position == position &&
          other.isUncategorized == isUncategorized &&
          other.notificationLevel == notificationLevel &&
          listEquals(other.featuredTopics, featuredTopics);

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
    position,
    isUncategorized,
    notificationLevel,
    Object.hashAll(featuredTopics),
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
      if (name.length > maximum) return false;
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
      forbiddenMessage ?? (forbidden ? 'Tags are not allowed here.' : null);
}
