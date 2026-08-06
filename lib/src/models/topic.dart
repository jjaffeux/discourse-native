import 'package:flutter/foundation.dart';

/// A row in a topic list.
///
/// Unread state rides along with the list rather than needing its own request:
/// the list endpoints are personalized once authenticated.
@immutable
class Topic {
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
      id: _int(json['id']),
      // `fancy_title` is HTML — "&ldquo;quoted&rdquo;" — which only renders in
      // a browser. `title` is the same text as plain unicode, which is what a
      // native Text widget wants.
      title: (json['title'] ?? json['fancy_title'] ?? '') as String,
      slug: (json['slug'] ?? '') as String,
      categoryId: json['category_id'] == null
          ? null
          : _int(json['category_id']),
      postsCount: _int(json['posts_count']),
      replyCount: _int(json['reply_count']),
      views: _int(json['views']),
      likeCount: _int(json['like_count']),
      bumpedAt: DateTime.tryParse((json['bumped_at'] ?? '') as String),
      pinned: json['pinned'] == true,
      closed: json['closed'] == true,
      unreadPosts: _int(json['unread_posts']),
      newPosts: _int(json['new_posts']),
      seen: json['unseen'] != true,
      posterAvatars: posters,
    );
  }

  static int _int(Object? value) => switch (value) {
    final num n => n.toInt(),
    final String s => int.tryParse(s) ?? 0,
    _ => 0,
  };

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
      avatars[Topic._int(map['id'])] = _avatar(
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

  static String? _avatar(String? template, String siteUrl) {
    if (template == null || template.isEmpty) return null;
    final sized = template.replaceAll('{size}', '90');
    if (sized.startsWith('//')) return 'https:$sized';
    if (sized.startsWith('http')) return sized;
    return '$siteUrl${sized.startsWith('/') ? '' : '/'}$sized';
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
class TopicCategory {
  const TopicCategory({
    required this.id,
    required this.name,
    required this.color,
    this.slug = '',
  });

  factory TopicCategory.fromJson(Map<String, dynamic> json) => TopicCategory(
    id: Topic._int(json['id']),
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
}
