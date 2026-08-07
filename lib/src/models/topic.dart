import 'package:flutter/foundation.dart';

import '../data/store.dart';
import 'json.dart';
import 'post.dart' show resolveAvatarUrl;

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
    this.posterAvatars = const [],
  });

  /// [siteUrl] resolves avatar templates, which are usually site-relative.
  factory Topic.fromJson(
    Map<String, dynamic> json,
    Map<int, String?> avatarsByUserId,
  ) {
    final posters = (json['posters'] as List<dynamic>? ?? const [])
        .map((p) => avatarsByUserId[(p as Map<String, dynamic>)['user_id']])
        .whereType<String>()
        .toList();

    return Topic(
      id: jsonInt(json['id']),
      title: jsonTitle(json['title'], json['fancy_title']),
      slug: (json['slug'] ?? '') as String,
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
  Topic merge(Topic incoming) => incoming.posterAvatars.isEmpty
      ? incoming.copyWith(posterAvatars: posterAvatars)
      : incoming;

  Topic copyWith({
    String? title,
    int? postsCount,
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
    posterAvatars: posterAvatars ?? this.posterAvatars,
  );
}

/// One page of a topic list, plus what the rows need to render.
@immutable
class TopicList {
  const TopicList({required this.topics, this.moreTopicsUrl});

  /// Avatar templates live in a separate `users` array keyed by id, so they are
  /// resolved into the topics here rather than left for the widgets.
  factory TopicList.fromJson(Map<String, dynamic> json, String siteUrl) {
    final avatars = <int, String?>{};
    for (final user in (json['users'] as List<dynamic>? ?? const [])) {
      final map = user as Map<String, dynamic>;
      avatars[jsonInt(map['id'])] = resolveAvatarUrl(
        map['avatar_template'] as String?,
        siteUrl,
      );
    }

    final list = json['topic_list'] as Map<String, dynamic>? ?? const {};
    return TopicList(
      topics: (list['topics'] as List<dynamic>? ?? const [])
          .map((t) => Topic.fromJson(t as Map<String, dynamic>, avatars))
          .toList(),
      moreTopicsUrl: list['more_topics_url'] as String?,
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
  });

  factory TopicCategory.fromJson(Map<String, dynamic> json) => TopicCategory(
    id: jsonInt(json['id']),
    name: (json['name'] ?? '') as String,
    color: (json['color'] ?? '888888') as String,
    slug: (json['slug'] ?? '') as String,
  );

  final int id;
  final String name;

  /// Six hex digits, no leading `#` — how Discourse stores it.
  final String color;
  final String slug;

  int get colorValue => int.tryParse('FF$color', radix: 16) ?? 0xFF888888;

  @override
  Object get storeId => id;
}
