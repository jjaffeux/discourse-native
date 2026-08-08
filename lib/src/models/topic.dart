import 'package:flutter/foundation.dart';

import '../data/store.dart';
import 'json.dart';
import 'post.dart' show resolveAvatarUrl;
import 'topic_tag.dart';

export 'topic_tag.dart';

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
    this.tags = const [],
    this.posterAvatars = const [],
  });

  /// [siteUrl] resolves avatar templates, which are usually site-relative.
  factory Topic.fromJson(
    Map<String, dynamic> json,
    Map<int, String?> avatarsByUserId,
  ) {
    final resolvedPosters = <String>[];
    for (final poster in jsonObjects(json['posters'])) {
      final id = jsonIntOrNull(poster['user_id']);
      final avatar = id == null ? null : avatarsByUserId[id];
      if (avatar != null) resolvedPosters.add(avatar);
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
      tags: List.unmodifiable(
        jsonArray(json['tags']).map(TopicTag.parse).whereType<TopicTag>(),
      ),
      posterAvatars: posters,
    );
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

  /// Already filtered to what the current user may see, in server order.
  final List<TopicTag> tags;

  final List<String> posterAvatars;

  bool get hasUnread => unreadPosts > 0 || newPosts > 0;

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
    List<TopicTag>? tags,
    List<String>? posterAvatars,
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
    tags: tags == null ? this.tags : List.unmodifiable(tags),
    posterAvatars: posterAvatars == null
        ? this.posterAvatars
        : List.unmodifiable(posterAvatars),
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
          listEquals(other.tags, tags) &&
          listEquals(other.posterAvatars, posterAvatars);

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
    Object.hashAll(tags),
    Object.hashAll(posterAvatars),
  ]);
}

/// One page of a topic list, plus what the rows need to render.
@immutable
class TopicList {
  const TopicList({
    required this.topics,
    this.moreTopicsUrl,
    this.canCreateTopic = false,
  });

  /// Avatar templates live in a separate `users` array keyed by id, so they are
  /// resolved into the topics here rather than left for the widgets.
  factory TopicList.fromJson(Map<String, dynamic> json, String siteUrl) {
    final avatars = <int, String?>{};
    for (final user in jsonObjects(json['users'])) {
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
        for (final topic in jsonObjects(list['topics']))
          Topic.fromJson(topic, avatars),
      ]),
      moreTopicsUrl: jsonText(list['more_topics_url']),
      canCreateTopic: list['can_create_topic'] == true,
    );
  }

  final List<Topic> topics;

  /// Where the next page lives, as Discourse reports it, or null at the end.
  final String? moreTopicsUrl;
  final bool canCreateTopic;

  /// [moreTopicsUrl] arrives without an extension — `/latest?page=1` — and that
  /// route serves HTML. The JSON page is `/latest.json?page=1`.
  String? get nextPagePath => asJsonPath(moreTopicsUrl);

  static String? asJsonPath(String? url) {
    if (url == null || url.isEmpty) return null;
    final uri = Uri.parse(url);
    if (uri.path.endsWith('.json')) return url;
    return uri.replace(path: '${uri.path}.json').toString();
  }
}

/// Just enough of a category to draw its badge.
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
  );

  final int id;
  final String name;

  /// Six hex digits, no leading `#` — how Discourse stores it.
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

  bool get canCreateTopic => permission == 1;

  int get colorValue => int.tryParse('FF$color', radix: 16) ?? 0xFF888888;

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
          other.minimumRequiredTags == minimumRequiredTags;

  @override
  int get hashCode => Object.hash(
    id,
    name,
    color,
    slug,
    parentCategoryId,
    permission,
    minimumRequiredTags,
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

  factory TopicTagSearch.fromJson(Map<String, dynamic> json) => TopicTagSearch(
    tags: List.unmodifiable([
      for (final item in jsonObjects(json['results']))
        if (jsonText(item['name']) case final name?)
          TopicTag(
            id: jsonIntOrNull(item['id']),
            name: name,
            slug: jsonText(item['slug']),
            count: jsonInt(item['count']),
            disabled: item['disabled'] == true,
            disabledReason: jsonText(item['title']),
          ),
    ]),
    forbidden:
        json['forbidden'] == true ||
        (json['forbidden'] is List && (json['forbidden'] as List).isNotEmpty) ||
        (jsonText(json['forbidden'])?.isNotEmpty ?? false),
    forbiddenMessage:
        jsonText(json['forbidden_message']) ?? jsonText(json['forbidden']),
  );

  final List<TopicTag> tags;
  final bool forbidden;
  final String? forbiddenMessage;

  List<TopicTag> get results => tags;
  bool get isForbidden => forbidden;
  String? get explanation =>
      forbiddenMessage ?? (forbidden ? 'Tags are not allowed here.' : null);
}
