import 'package:flutter/foundation.dart';
import 'package:html/dom.dart';
import 'package:html/parser.dart' as html;

import 'json.dart';

/// The transient answer from Discourse's header-search endpoint.
///
/// Search topics are intentionally not [Topic]s. The search serializer is a
/// smaller shape than a topic list, and putting one in the identity store would
/// let its absent fields overwrite richer list state.
@immutable
class SearchResults {
  const SearchResults({
    this.hits = const [],
    this.sections = const [],
    this.error,
  });

  factory SearchResults.fromJson(Map<String, dynamic> json, String siteUrl) {
    final topics = <int, _SearchTopic>{};
    for (final value in jsonObjects(json['topics'])) {
      final id = jsonIntOrNull(value['id']);
      if (id == null || id <= 0) continue;
      topics[id] = _SearchTopic(
        id: id,
        title: jsonTitle(value['title'], value['fancy_title']),
        slug: jsonString(value['slug']),
      );
    }

    final hits = <SearchPostHit>[];
    for (final value in jsonObjects(json['posts'])) {
      final topicId = jsonIntOrNull(value['topic_id']);
      final postId = jsonIntOrNull(value['id']);
      final postNumber = jsonIntOrNull(value['post_number']);
      final topic = topicId == null ? null : topics[topicId];
      if (topic == null ||
          postId == null ||
          postId <= 0 ||
          postNumber == null ||
          postNumber <= 0) {
        continue;
      }

      hits.add(
        SearchPostHit(
          postId: postId,
          topicId: topic.id,
          postNumber: postNumber,
          topicTitle: topic.title,
          topicSlug: topic.slug,
          username: jsonString(value['username']),
          name: jsonText(value['name']),
          avatarUrl: resolveAvatarUrl(
            jsonText(value['avatar_template']),
            siteUrl,
          ),
          createdAt: jsonDate(value['created_at']),
          excerpt: SearchExcerpt.fromHtml(jsonString(value['blurb'])),
        ),
      );
    }

    final grouped = jsonObject(json['grouped_search_result']);
    final sections = <SearchResultSection>[
      if (hits.isNotEmpty)
        SearchResultSection(
          kind: SearchResultKind.topic,
          results: List.unmodifiable(hits),
          hasMore: grouped['more_posts'] == true,
        ),
    ];

    void addSection(
      SearchResultKind kind,
      String key,
      SearchResult? Function(Map<String, dynamic>) parse, {
      String? moreKey,
    }) {
      final results = <SearchResult>[
        for (final value in jsonObjects(json[key])) ?parse(value),
      ];
      if (results.isEmpty) return;
      sections.add(
        SearchResultSection(
          kind: kind,
          results: List.unmodifiable(results),
          hasMore: moreKey != null && grouped[moreKey] == true,
        ),
      );
    }

    // This is the same facet ordering as core's translateGroupedSearchResults:
    // topics, categories, tags, users, then groups.
    addSection(
      SearchResultKind.category,
      'categories',
      SearchCategoryHit.fromJson,
      moreKey: 'more_categories',
    );
    addSection(SearchResultKind.tag, 'tags', SearchTagHit.fromJson);
    addSection(
      SearchResultKind.user,
      'users',
      (value) => SearchUserHit.fromJson(value, siteUrl),
      moreKey: 'more_users',
    );
    addSection(SearchResultKind.group, 'groups', SearchGroupHit.fromJson);

    return SearchResults(
      hits: List.unmodifiable(hits),
      sections: List.unmodifiable(sections),
      error: jsonText(grouped['error']),
    );
  }

  final List<SearchPostHit> hits;

  /// Ranked facets in the same order as the web header search.
  ///
  /// [hits] remains available as the topic/post facet because callers that
  /// only care about opening posts should not have to downcast every result.
  final List<SearchResultSection> sections;

  /// A compatibility-aware view for manually constructed test answers.
  List<SearchResultSection> get effectiveSections => sections.isNotEmpty
      ? sections
      : hits.isEmpty
      ? const []
      : [SearchResultSection(kind: SearchResultKind.topic, results: hits)];

  List<SearchResult> get results => List.unmodifiable([
    for (final section in effectiveSections) ...section.results,
  ]);

  /// A successful response can still carry a refusal, such as overloaded
  /// search. This is the site's reader-facing explanation.
  final String? error;
}

enum SearchResultKind {
  topic('Topics'),
  category('Categories'),
  tag('Tags'),
  user('Users'),
  group('Groups');

  const SearchResultKind(this.label);

  final String label;
}

@immutable
class SearchResultSection {
  const SearchResultSection({
    required this.kind,
    required this.results,
    this.hasMore = false,
  });

  final SearchResultKind kind;
  final List<SearchResult> results;
  final bool hasMore;
}

sealed class SearchResult {
  const SearchResult();

  SearchResultKind get kind;
  Object get id;
  String get path;
}

@immutable
class SearchPostHit extends SearchResult {
  const SearchPostHit({
    required this.postId,
    required this.topicId,
    required this.postNumber,
    required this.topicTitle,
    required this.topicSlug,
    required this.username,
    required this.excerpt,
    this.name,
    this.avatarUrl,
    this.createdAt,
  });

  final int postId;
  final int topicId;
  final int postNumber;
  final String topicTitle;
  final String topicSlug;
  final String username;
  final String? name;
  final String? avatarUrl;
  final DateTime? createdAt;
  final SearchExcerpt excerpt;

  String get displayName => name ?? username;

  @override
  SearchResultKind get kind => SearchResultKind.topic;

  @override
  Object get id => postId;

  @override
  String get path =>
      ['/t', Uri.encodeComponent(topicSlug), topicId, postNumber].join('/');
}

@immutable
class SearchCategoryHit extends SearchResult {
  const SearchCategoryHit({
    required this.categoryId,
    required this.name,
    required this.slug,
    this.color = '888888',
  });

  static SearchCategoryHit? fromJson(Map<String, dynamic> json) {
    final id = jsonIntOrNull(json['id']);
    final name = jsonText(json['name']);
    if (id == null || id <= 0 || name == null) return null;
    return SearchCategoryHit(
      categoryId: id,
      name: name,
      slug: jsonText(json['slug']) ?? '',
      color: jsonText(json['color']) ?? '888888',
    );
  }

  final int categoryId;
  final String name;
  final String slug;
  final String color;

  int get colorValue => int.tryParse('FF$color', radix: 16) ?? 0xFF888888;

  @override
  SearchResultKind get kind => SearchResultKind.category;

  @override
  Object get id => categoryId;

  @override
  String get path => slug.isEmpty
      ? '/c/$categoryId'
      : '/c/${Uri.encodeComponent(slug)}/$categoryId';
}

@immutable
class SearchTagHit extends SearchResult {
  const SearchTagHit({required this.tagId, required this.name, this.slug});

  static SearchTagHit? fromJson(Map<String, dynamic> json) {
    final name = jsonText(json['name']);
    if (name == null) return null;
    return SearchTagHit(
      tagId: jsonIntOrNull(json['id']),
      name: name,
      slug: jsonText(json['slug']),
    );
  }

  final int? tagId;
  final String name;
  final String? slug;

  @override
  SearchResultKind get kind => SearchResultKind.tag;

  @override
  Object get id => tagId ?? name;

  @override
  String get path {
    final encoded = Uri.encodeComponent(slug ?? name);
    return tagId == null || tagId! <= 0
        ? '/tag/$encoded'
        : '/tag/$encoded/$tagId';
  }
}

@immutable
class SearchUserHit extends SearchResult {
  const SearchUserHit({
    required this.userId,
    required this.username,
    this.name,
    this.avatarUrl,
  });

  static SearchUserHit? fromJson(Map<String, dynamic> json, String siteUrl) {
    final username = jsonText(json['username']);
    if (username == null) return null;
    return SearchUserHit(
      userId: jsonIntOrNull(json['id']),
      username: username,
      name: jsonText(json['name']),
      avatarUrl: resolveAvatarUrl(jsonText(json['avatar_template']), siteUrl),
    );
  }

  final int? userId;
  final String username;
  final String? name;
  final String? avatarUrl;

  @override
  SearchResultKind get kind => SearchResultKind.user;

  @override
  Object get id => userId ?? username;

  @override
  String get path => '/u/${Uri.encodeComponent(username)}';
}

@immutable
class SearchGroupHit extends SearchResult {
  const SearchGroupHit({
    required this.groupId,
    required this.name,
    this.fullName,
  });

  static SearchGroupHit? fromJson(Map<String, dynamic> json) {
    final id = jsonIntOrNull(json['id']);
    final name = jsonText(json['name']);
    if (id == null || id <= 0 || name == null) return null;
    return SearchGroupHit(
      groupId: id,
      name: name,
      fullName: jsonText(json['full_name']) ?? jsonText(json['display_name']),
    );
  }

  final int groupId;
  final String name;
  final String? fullName;

  @override
  SearchResultKind get kind => SearchResultKind.group;

  @override
  Object get id => groupId;

  @override
  String get path => '/g/${Uri.encodeComponent(name)}';
}

/// Plain, safe text plus the ranges the server marked as search matches.
@immutable
class SearchExcerpt {
  const SearchExcerpt(this.segments);

  factory SearchExcerpt.fromHtml(String source) {
    if (source.isEmpty) return const SearchExcerpt([]);

    final raw = <SearchExcerptSegment>[];
    void append(String text, bool highlighted) {
      if (text.isEmpty) return;
      if (raw.isNotEmpty && raw.last.highlighted == highlighted) {
        final previous = raw.removeLast();
        raw.add(
          SearchExcerptSegment(
            '${previous.text}$text',
            highlighted: highlighted,
          ),
        );
      } else {
        raw.add(SearchExcerptSegment(text, highlighted: highlighted));
      }
    }

    void visit(Node node, bool highlighted) {
      if (node is Text) {
        append(node.data, highlighted);
        return;
      }
      if (node is! Element) return;
      if (node.localName == 'br') {
        append(' ', highlighted);
        return;
      }
      final marked = highlighted || node.classes.contains('search-highlight');
      for (final child in node.nodes) {
        visit(child, marked);
      }
      if (const {'p', 'div', 'li'}.contains(node.localName)) {
        append(' ', highlighted);
      }
    }

    for (final node in html.parseFragment(source).nodes) {
      visit(node, false);
    }

    // Search excerpts can retain indentation and line breaks from cooked HTML.
    // Collapse them without losing which words Discourse highlighted.
    final normalized = <SearchExcerptSegment>[];
    void appendNormalized(String text, bool highlighted) {
      if (normalized.isNotEmpty && normalized.last.highlighted == highlighted) {
        final previous = normalized.removeLast();
        normalized.add(
          SearchExcerptSegment(
            '${previous.text}$text',
            highlighted: highlighted,
          ),
        );
      } else {
        normalized.add(SearchExcerptSegment(text, highlighted: highlighted));
      }
    }

    var pendingSpace = false;
    var pendingSegment = -1;
    for (var segmentIndex = 0; segmentIndex < raw.length; segmentIndex++) {
      final segment = raw[segmentIndex];
      for (final rune in segment.text.runes) {
        final character = String.fromCharCode(rune);
        if (RegExp(r'\s').hasMatch(character)) {
          pendingSpace = normalized.isNotEmpty;
          pendingSegment = segmentIndex;
          continue;
        }
        if (pendingSpace) {
          appendNormalized(
            ' ',
            pendingSegment == segmentIndex && segment.highlighted,
          );
        }
        pendingSpace = false;
        appendNormalized(character, segment.highlighted);
      }
    }
    return SearchExcerpt(List.unmodifiable(normalized));
  }

  final List<SearchExcerptSegment> segments;

  String get plainText => segments.map((segment) => segment.text).join();
}

@immutable
class SearchExcerptSegment {
  const SearchExcerptSegment(this.text, {this.highlighted = false});

  final String text;
  final bool highlighted;
}

@immutable
class _SearchTopic {
  const _SearchTopic({
    required this.id,
    required this.title,
    required this.slug,
  });

  final int id;
  final String title;
  final String slug;
}
