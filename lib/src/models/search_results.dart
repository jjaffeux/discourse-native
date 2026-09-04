import 'package:flutter/foundation.dart';
import 'package:html/dom.dart';
import 'package:html/parser.dart' as html;

import 'found_group.dart';
import 'json.dart';
import 'topic_tag.dart';

@immutable
class SearchResults {
  const SearchResults({
    this.hits = const [],
    this.sections = const [],
    this.error,
    this.searchLogId,
  });

  static const int maximumResultsPerSection = 50;

  factory SearchResults.fromJson(Map<String, dynamic> json, String siteUrl) {
    final topics = <int, _SearchTopic>{};
    for (final value in jsonObjects(
      json['topics'],
    ).take(maximumResultsPerSection)) {
      final id = jsonIntOrNull(value['id']);
      if (id == null || id <= 0) continue;
      topics[id] = _SearchTopic(
        id: id,
        title: jsonTitle(value['title'], value['fancy_title']),
        slug: jsonString(value['slug']),
        categoryId: jsonIntOrNull(value['category_id']),
        tags: List.unmodifiable([
          for (final tag in jsonArray(value['tags'])) ?TopicTag.parse(tag),
        ]),
        pinned: value['pinned'] == true,
        unpinned: value['unpinned'] == true,
        closed: value['closed'] == true,
        archived: value['archived'] == true,
        privateMessage: value['archetype'] == 'private_message',
        bookmarked: value['bookmarked'] == true,
        warning: value['is_warning'] == true,
        invisible: value['visible'] == false,
      );
    }

    final hits = <SearchPostHit>[];
    for (final value in jsonObjects(
      json['posts'],
    ).take(maximumResultsPerSection)) {
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
          topicTitleExcerpt: SearchExcerpt.fromHtml(
            jsonString(value['topic_title_headline']),
          ),
          categoryId: topic.categoryId,
          tags: topic.tags,
          pinned: topic.pinned,
          unpinned: topic.unpinned,
          closed: topic.closed,
          archived: topic.archived,
          privateMessage: topic.privateMessage,
          bookmarked: topic.bookmarked,
          warning: topic.warning,
          invisible: topic.invisible,
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
        for (final value in jsonObjects(
          json[key],
        ).take(maximumResultsPerSection))
          ?parse(value),
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

    addSection(
      SearchResultKind.category,
      'categories',
      SearchCategoryHit.fromJson,
      moreKey: 'more_categories',
    );
    addSection(
      SearchResultKind.tag,
      'tags',
      SearchTagHit.fromJson,
      moreKey: 'more_tags',
    );
    addSection(
      SearchResultKind.user,
      'users',
      (value) => SearchUserHit.fromJson(value, siteUrl),
      moreKey: 'more_users',
    );
    addSection(
      SearchResultKind.group,
      'groups',
      (value) => SearchGroupHit.fromJson(value, siteUrl),
      moreKey: 'more_groups',
    );

    return SearchResults(
      hits: List.unmodifiable(hits),
      sections: List.unmodifiable(sections),
      error: jsonText(grouped['error']),
      searchLogId: jsonIntOrNull(grouped['search_log_id']),
    );
  }

  final List<SearchPostHit> hits;

  final List<SearchResultSection> sections;

  List<SearchResultSection> get effectiveSections => sections.isNotEmpty
      ? sections
      : hits.isEmpty
      ? const []
      : [SearchResultSection(kind: SearchResultKind.topic, results: hits)];

  List<SearchResult> get results => List.unmodifiable([
    for (final section in effectiveSections) ...section.results,
  ]);

  final String? error;

  final int? searchLogId;
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
    this.topicTitleExcerpt = const SearchExcerpt([]),
    this.categoryId,
    this.tags = const [],
    this.pinned = false,
    this.unpinned = false,
    this.closed = false,
    this.archived = false,
    this.privateMessage = false,
    this.bookmarked = false,
    this.warning = false,
    this.invisible = false,
    this.name,
    this.avatarUrl,
    this.createdAt,
  });

  final int postId;
  final int topicId;
  final int postNumber;
  final String topicTitle;
  final String topicSlug;
  final SearchExcerpt topicTitleExcerpt;
  final int? categoryId;
  final List<TopicTag> tags;
  final bool pinned;
  final bool unpinned;
  final bool closed;
  final bool archived;
  final bool privateMessage;
  final bool bookmarked;
  final bool warning;
  final bool invisible;
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
  String get path => [
    '/t',
    Uri.encodeComponent(topicSlug),
    topicId,
    if (postNumber > 1) postNumber,
  ].join('/');
}

@immutable
class SearchCategoryHit extends SearchResult {
  const SearchCategoryHit({
    required this.categoryId,
    required this.name,
    required this.slug,
    this.color = '888888',
    this.styleType = 'square',
    this.icon,
    this.emoji,
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
      styleType: jsonText(json['style_type']) ?? 'square',
      icon: jsonText(json['icon']),
      emoji: jsonText(json['emoji']),
    );
  }

  final int categoryId;
  final String name;
  final String slug;
  final String color;
  final String styleType;
  final String? icon;
  final String? emoji;

  int get colorValue => categoryColorValue(color);

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
    this.flairUrl,
    this.flairColor,
    this.flairBackgroundColor,
  });

  static SearchGroupHit? fromJson(
    Map<String, dynamic> json, [
    String? siteUrl,
  ]) {
    final id = jsonIntOrNull(json['id']);
    final name = jsonText(json['name']);
    if (id == null || id <= 0 || name == null) return null;
    return SearchGroupHit(
      groupId: id,
      name: name,
      fullName: jsonText(json['full_name']) ?? jsonText(json['display_name']),
      flairUrl: siteUrl == null
          ? jsonText(json['flair_url'])
          : resolveFlairUrl(jsonText(json['flair_url']), siteUrl),
      flairColor: jsonText(json['flair_color']),
      flairBackgroundColor: jsonText(json['flair_bg_color']),
    );
  }

  final int groupId;
  final String name;
  final String? fullName;
  final String? flairUrl;
  final String? flairColor;
  final String? flairBackgroundColor;

  @override
  SearchResultKind get kind => SearchResultKind.group;

  @override
  Object get id => groupId;

  @override
  String get path => '/g/${Uri.encodeComponent(name)}';
}

@immutable
class SearchExcerpt {
  const SearchExcerpt(this.segments);

  static const int maxHtmlSourceCodeUnits = 8 * 1024;

  static final RegExp _whitespace = RegExp(r'\s');

  factory SearchExcerpt.fromHtml(String source) {
    if (source.isEmpty) return const SearchExcerpt([]);
    source = _boundedHtmlSource(source);

    final raw = <({StringBuffer text, bool highlighted})>[];
    void append(String text, bool highlighted) {
      if (text.isEmpty) return;
      if (raw.isNotEmpty && raw.last.highlighted == highlighted) {
        raw.last.text.write(text);
      } else {
        raw.add((text: StringBuffer(text), highlighted: highlighted));
      }
    }

    final roots = html.parseFragment(source).nodes;
    final pending = <({Node node, bool highlighted, bool exiting})>[];
    void pushNodes(List<Node> nodes, bool highlighted) {
      for (var index = nodes.length - 1; index >= 0; index--) {
        pending.add((
          node: nodes[index],
          highlighted: highlighted,
          exiting: false,
        ));
      }
    }

    pushNodes(roots, false);
    while (pending.isNotEmpty) {
      final frame = pending.removeLast();
      final node = frame.node;
      if (node is Text) {
        append(node.data, frame.highlighted);
        continue;
      }
      if (node is! Element) continue;
      if (frame.exiting) {
        if (const {'p', 'div', 'li'}.contains(node.localName)) {
          append(' ', frame.highlighted);
        }
        continue;
      }
      if (node.localName == 'br') {
        append(' ', frame.highlighted);
        continue;
      }
      final marked =
          frame.highlighted || node.classes.contains('search-highlight');
      pending.add((node: node, highlighted: marked, exiting: true));
      pushNodes(node.nodes, marked);
    }

    // Search excerpts can retain indentation and line breaks from cooked HTML.
    // Collapse them without losing which words Discourse highlighted.
    final normalized = <SearchExcerptSegment>[];
    StringBuffer? normalizedText;
    var normalizedHighlighted = false;

    void flushNormalized() {
      final text = normalizedText;
      if (text == null) return;
      normalized.add(
        SearchExcerptSegment(
          text.toString(),
          highlighted: normalizedHighlighted,
        ),
      );
      normalizedText = null;
    }

    void appendNormalized(String text, bool highlighted) {
      if (normalizedText == null || normalizedHighlighted != highlighted) {
        flushNormalized();
        normalizedText = StringBuffer();
        normalizedHighlighted = highlighted;
      }
      normalizedText!.write(text);
    }

    var pendingSpace = false;
    var pendingSegment = -1;
    for (var segmentIndex = 0; segmentIndex < raw.length; segmentIndex++) {
      final segment = raw[segmentIndex];
      for (final rune in segment.text.toString().runes) {
        final character = String.fromCharCode(rune);
        if (_whitespace.hasMatch(character)) {
          pendingSpace = normalized.isNotEmpty || normalizedText != null;
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
    flushNormalized();
    return SearchExcerpt(List.unmodifiable(normalized));
  }

  static String _boundedHtmlSource(String source) {
    if (source.length <= maxHtmlSourceCodeUnits) return source;

    var end = maxHtmlSourceCodeUnits;
    final lastIncluded = source.codeUnitAt(end - 1);
    final firstExcluded = source.codeUnitAt(end);
    if (_isHighSurrogate(lastIncluded) && _isLowSurrogate(firstExcluded)) {
      end--;
    }
    return source.substring(0, end);
  }

  static bool _isHighSurrogate(int codeUnit) =>
      codeUnit >= 0xD800 && codeUnit <= 0xDBFF;

  static bool _isLowSurrogate(int codeUnit) =>
      codeUnit >= 0xDC00 && codeUnit <= 0xDFFF;

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
    required this.categoryId,
    required this.tags,
    required this.pinned,
    required this.unpinned,
    required this.closed,
    required this.archived,
    required this.privateMessage,
    required this.bookmarked,
    required this.warning,
    required this.invisible,
  });

  final int id;
  final String title;
  final String slug;
  final int? categoryId;
  final List<TopicTag> tags;
  final bool pinned;
  final bool unpinned;
  final bool closed;
  final bool archived;
  final bool privateMessage;
  final bool bookmarked;
  final bool warning;
  final bool invisible;
}
