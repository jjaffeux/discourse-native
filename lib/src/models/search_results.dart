import 'package:flutter/foundation.dart';
import 'package:html/dom.dart';
import 'package:html/parser.dart' as html;

import 'json.dart';
import 'post.dart' show resolveAvatarUrl;

/// The transient answer from Discourse's header-search endpoint.
///
/// Search topics are intentionally not [Topic]s. The search serializer is a
/// smaller shape than a topic list, and putting one in the identity store would
/// let its absent fields overwrite richer list state.
@immutable
class SearchResults {
  const SearchResults({this.hits = const [], this.error});

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

    return SearchResults(
      hits: List.unmodifiable(hits),
      error: jsonText(jsonObject(json['grouped_search_result'])['error']),
    );
  }

  final List<SearchPostHit> hits;

  /// A successful response can still carry a refusal, such as overloaded
  /// search. This is the site's reader-facing explanation.
  final String? error;
}

@immutable
class SearchPostHit {
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
