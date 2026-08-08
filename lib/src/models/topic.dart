import 'package:flutter/foundation.dart';

import '../data/store.dart';
import 'json.dart';
import 'post.dart' show resolveAvatarUrl;

/// One tag attached to a topic-list row.
///
/// Current Discourse sites send an object so a client can build the canonical
/// `/tag/{slug}/{id}` link. Older sites sent only the name, which is why [id]
/// and [slug] are optional rather than guessed here.
@immutable
class TopicTag {
  const TopicTag({required this.name, this.id, this.slug});

  static TopicTag? parse(Object? value) {
    if (value is String) {
      final name = jsonText(value);
      return name == null ? null : TopicTag(name: name);
    }
    if (value is! Map<String, dynamic>) return null;

    final name = jsonText(value['name']);
    if (name == null) return null;
    return TopicTag(
      id: jsonIntOrNull(value['id']),
      name: name,
      slug: jsonText(value['slug']),
    );
  }

  final int? id;
  final String name;
  final String? slug;

  @override
  bool operator ==(Object other) =>
      other is TopicTag &&
      other.id == id &&
      other.name == name &&
      other.slug == slug;

  @override
  int get hashCode => Object.hash(id, name, slug);
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
    this.lastReadPostNumber,
    this.highestPostNumber = 0,
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
      lastReadPostNumber: jsonIntOrNull(json['last_read_post_number']),
      highestPostNumber: jsonInt(json['highest_post_number']),
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

  /// The personalized reading position Discourse attaches to topic lists.
  final int? lastReadPostNumber;

  /// The last post number currently visible to this reader.
  final int highestPostNumber;

  /// Already filtered to what the current user may see, in server order.
  final List<TopicTag> tags;

  final List<String> posterAvatars;

  bool get hasUnread => unreadPosts > 0 || newPosts > 0;

  /// Where Discourse's own topic-list links send the reader.
  ///
  /// An unread topic starts at its first unread post. A topic already read to
  /// the end starts at its last post, and a topic with no tracking data starts
  /// at the beginning. Zero means an older or partial payload did not carry
  /// enough information to choose a position.
  int? get lastUnreadPostNumber {
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
    int? postsCount,
    int? lastReadPostNumber,
    int? highestPostNumber,
    List<TopicTag>? tags,
    List<String>? posterAvatars,
    bool markRead = false,
  }) => Topic(
    id: id,
    title: title ?? this.title,
    slug: slug,
    categoryId: categoryId,
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
    lastReadPostNumber: markRead && this.highestPostNumber > 0
        ? this.highestPostNumber
        : lastReadPostNumber ?? this.lastReadPostNumber,
    highestPostNumber: highestPostNumber ?? this.highestPostNumber,
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
          other.lastReadPostNumber == lastReadPostNumber &&
          other.highestPostNumber == highestPostNumber &&
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
    lastReadPostNumber,
    highestPostNumber,
    Object.hashAll(tags),
    Object.hashAll(posterAvatars),
  ]);
}

/// One page of a topic list, plus what the rows need to render.
@immutable
class TopicList {
  const TopicList({required this.topics, this.moreTopicsUrl});

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
    );
  }

  final List<Topic> topics;

  /// Where the next page lives, as Discourse reports it, or null at the end.
  final String? moreTopicsUrl;

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
  });

  factory TopicCategory.fromJson(Map<String, dynamic> json) => TopicCategory(
    id: jsonInt(json['id']),
    name: jsonString(json['name']),
    color: jsonString(json['color'], fallback: '888888'),
    slug: jsonString(json['slug']),
    parentCategoryId: json['parent_category_id'] == null
        ? null
        : jsonInt(json['parent_category_id']),
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
          other.parentCategoryId == parentCategoryId;

  @override
  int get hashCode => Object.hash(id, name, color, slug, parentCategoryId);
}
