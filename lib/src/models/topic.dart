import 'package:flutter/foundation.dart';

import '../data/store.dart';
import '../plugins/plugin_data.dart';
import 'json.dart';
import 'topic_filter.dart';
import 'topic_tag.dart';

export 'topic_tag.dart';

/// One participant in the topic map beneath the opening post.
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

/// One outbound link listed by the topic map.
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

/// A row in a topic list.
///
/// Unread state rides along with the list rather than needing its own request:
/// the list endpoints are personalized once authenticated.
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
    this.unreadPosts = 0,
    this.newPosts = 0,
    this.seen = true,
    this.isNestedView = false,
    this.hasNewReplies = false,
    this.lastReadPostNumber,
    this.highestPostNumber = 0,
    this.tags = const [],
    this.posterAvatars = const [],
    this.plugins = PluginData.none,
  });

  /// The topic-list row displays the first three resolved poster avatars.
  static const int maximumPosterAvatars = 3;

  /// [siteUrl] resolves avatar templates, which are usually site-relative.
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
      unreadPosts: jsonInt(json['unread_posts']),
      newPosts: jsonInt(json['new_posts']),
      seen: json['unseen'] != true,
      isNestedView: json['is_nested_view'] == true,
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

  /// Suggested-topic serializers embed each poster's user instead of sending
  /// the sibling `users` array used by ordinary topic lists.
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

  /// Posts the user has not read. Zero when signed out.
  final int unreadPosts;
  final int newPosts;

  /// False for a topic the user has never opened.
  final bool seen;

  /// Whether replies are presented as a nested conversation rather than a
  /// flat post stream. Core gives these rows a different unread treatment.
  final bool isNestedView;

  /// Core's single "new content" signal for a nested topic.
  ///
  /// Ordinary unread counts and the unseen/new-topic dot are deliberately
  /// suppressed for nested topics, even when those legacy fields are present.
  final bool hasNewReplies;

  /// The personalized reading position Discourse attaches to topic lists.
  final int? lastReadPostNumber;

  /// The last post number currently visible to this reader.
  final int highestPostNumber;

  /// Already filtered to what the current user may see, in server order.
  final List<TopicTag> tags;

  final List<String> posterAvatars;

  /// What optional features attached to this topic-list record.
  final PluginData plugins;

  /// The count core prints for a flat tracked topic.
  ///
  /// `new_posts` is a backwards-compatible mirror of `unread_posts`, not a
  /// second bucket. Adding them would commonly double the badge.
  int get unreadCount => unreadPosts > 0 ? unreadPosts : newPosts;

  bool get hasUnread => unreadCount > 0;

  /// Core calls this `visited`: the reader has reached the last visible post.
  /// It is independent from notification level, so a row can be bright without
  /// carrying a count when the topic is not tracked.
  bool get visited =>
      lastReadPostNumber != null && lastReadPostNumber! >= highestPostNumber;

  bool get showUnreadCount => !isNestedView && unreadCount > 0;
  bool get showNewTopicDot => !isNestedView && !seen;
  bool get showNewRepliesDot => isNestedView && hasNewReplies;

  /// Where Discourse's own topic-list links send the reader.
  ///
  /// An unread topic starts at its first unread post. A topic already read to
  /// the end starts at its last post, and a topic with no tracking data starts
  /// at the beginning. Zero means an older or partial payload did not carry
  /// enough information to choose a position.
  int? get lastUnreadPostNumber {
    // Nested topics route to the conversation root. A numbered URL would open
    // them through the flat post-stream semantics core explicitly avoids.
    if (isNestedView) return null;
    if (highestPostNumber <= 0) return null;
    final next = (lastReadPostNumber ?? 0) + 1;
    return next > highestPostNumber ? highestPostNumber : next;
  }

  /// Canonical path on the site.
  String get path => '/t/$slug/$id';

  @override
  Object get storeId => id;

  /// A later copy wins, except where it simply has less to say.
  ///
  /// The lists all serve the same shape, so this is nearly always a straight
  /// replacement. The exception is a topic asked for by id — `?topic_ids=` for
  /// the incoming banner — which comes back without the `users` array the
  /// avatars are resolved from. Taking that literally would blank the faces on
  /// a row that had them.
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
    pinned: pinned,
    closed: closed,
    unreadPosts: markRead ? 0 : unreadPosts,
    newPosts: markRead ? 0 : newPosts,
    seen: markRead ? true : seen,
    isNestedView: isNestedView,
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

  /// The topic with one complete optional-feature snapshot.
  ///
  /// Kept separate from [copyWith] so [PluginData.none] can deliberately clear
  /// stale feature state when a serializer stops mentioning it.
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
    unreadPosts: unreadPosts,
    newPosts: newPosts,
    seen: seen,
    isNestedView: isNestedView,
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
          other.unreadPosts == unreadPosts &&
          other.newPosts == newPosts &&
          other.seen == seen &&
          other.isNestedView == isNestedView &&
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
    unreadPosts,
    newPosts,
    seen,
    isNestedView,
    hasNewReplies,
    lastReadPostNumber,
    highestPostNumber,
    Object.hashAll(tags),
    Object.hashAll(posterAvatars),
    plugins,
  ]);
}

/// The optional topic lists attached to the end of a topic.
@immutable
class TopicRecommendations {
  const TopicRecommendations({
    this.suggested = const [],
    this.related = const [],
  });

  /// Null means neither field was present, which is how Discourse says the
  /// reader has not reached the final post window yet.
  static TopicRecommendations? fromJson(
    Map<String, dynamic> json,
    String siteUrl, {
    PluginDataDecoder extensions = const EmptyPluginDataDecoder(),
  }) {
    if (!json.containsKey('suggested_topics') &&
        !json.containsKey('related_topics')) {
      return null;
    }
    return TopicRecommendations(
      suggested: List.unmodifiable([
        for (final topic in jsonObjects(json['suggested_topics']))
          Topic.fromRecommendationJson(topic, siteUrl, extensions: extensions),
      ]),
      related: List.unmodifiable([
        for (final topic in jsonObjects(json['related_topics']))
          Topic.fromRecommendationJson(topic, siteUrl, extensions: extensions),
      ]),
    );
  }

  final List<Topic> suggested;
  final List<Topic> related;

  bool get isNotEmpty => suggested.isNotEmpty || related.isNotEmpty;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TopicRecommendations &&
          listEquals(other.suggested, suggested) &&
          listEquals(other.related, related);

  @override
  int get hashCode =>
      Object.hash(Object.hashAll(suggested), Object.hashAll(related));
}

/// One page of a topic list, plus what the rows need to render.
@immutable
class TopicList {
  /// Discourse validates `per_page` in the inclusive range 1–100. Applying
  /// that server contract before constructing topic models bounds a broken or
  /// hostile page without changing any conforming response.
  static const int maximumPageSize = 100;

  /// Core's topic poster summary contains at most five users per topic.
  static const int maximumUsersPerPage = maximumPageSize * 5;

  const TopicList({
    required this.topics,
    this.moreTopicsUrl,
    this.canCreateTopic = false,
    this.filterOptions = const [],
  });

  /// Avatar templates live in a separate `users` array keyed by id, so they are
  /// resolved into the topics here rather than left for the widgets.
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
      moreTopicsUrl: jsonText(list['more_topics_url']),
      canCreateTopic: list['can_create_topic'] == true,
      filterOptions: List.unmodifiable([
        for (final value in jsonArray(list['filter_option_info']))
          ?TopicFilterOption.parse(value),
      ]),
    );
  }

  final List<Topic> topics;

  /// Where the next page lives, as Discourse reports it, or null at the end.
  final String? moreTopicsUrl;
  final bool canCreateTopic;
  final List<TopicFilterOption> filterOptions;

  /// [moreTopicsUrl] arrives without an extension — `/latest?page=1` — and that
  /// route serves HTML. The JSON page is `/latest.json?page=1`.
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

/// The small topic shape embedded in a category-list response.
///
/// These rows deliberately do not enter the topic identity store. Discourse's
/// category endpoint serves only enough topic data to draw and open a featured
/// link, while the full topic-list model has substantially more state.
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

  /// The post number used by the web category page's featured-topic links.
  ///
  /// An unread topic opens one post after the last read position. A topic read
  /// to the end stays on its final post, and an untracked topic starts at post
  /// one. Null leaves navigation at the topic root when the partial payload
  /// did not carry a usable highest post number.
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

/// Just enough of a category to draw its badge and category-list card.
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

  /// Three or six hex digits, usually without a leading `#`.
  final String color;
  final String slug;

  /// The category this one sits under, or null for a top-level one.
  ///
  /// Kept for the hashtag square, which Discourse splits down the middle for a
  /// subcategory — parent on the left, child on the right — and which
  /// therefore needs a second colour to look up.
  final int? parentCategoryId;

  /// `1` is Discourse's full permission: topics may be created here.
  final int? permission;
  final int minimumRequiredTags;

  /// `square`, `icon` or `emoji`, as configured by the category owner.
  final String styleType;
  final String? icon;
  final String? emoji;

  /// Whether reading this category is limited to specific groups.
  final bool readRestricted;
  final int topicCount;
  final int? position;

  /// Identified from site.json's `uncategorized_category_id`. Category list
  /// rows do not carry this bit themselves.
  final bool isUncategorized;

  /// The personalized category notification level. Core uses zero for muted.
  final int notificationLevel;

  /// Featured rows supplied by `include_topics=true`, in server rank order.
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

/// Session-scoped answers used by the topic composer.
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

  /// The largest suggestion page the composer will retain and render.
  ///
  /// The request sends the same (or a smaller) value, but this parser boundary
  /// prevents a nonconforming response from constructing an arbitrary model
  /// list for an eager autocomplete popup.
  static const int maximumResults = 20;

  final List<TopicTag> tags;
  final bool forbidden;
  final String? forbiddenMessage;

  List<TopicTag> get results => tags;
  bool get isForbidden => forbidden;
  String? get explanation =>
      forbiddenMessage ?? (forbidden ? 'Tags are not allowed here.' : null);
}
