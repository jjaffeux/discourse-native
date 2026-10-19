import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;

import '../foundation/bounded_lru_cache.dart';

/// Words belong to one page in one tab, never to the global search editor.
class SearchWords extends InheritedWidget {
  const SearchWords({super.key, required this.query, required super.child});
  final String query;
  static String of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<SearchWords>()?.query ?? '';
  @override
  bool updateShouldNotify(SearchWords oldWidget) => oldWidget.query != query;
}

List<String> searchWords(String query) =>
    query
        .replaceAll('"', '')
        .split(RegExp(r'\s+'))
        .where(
          (word) =>
              word.isNotEmpty && !word.contains(':') && !word.startsWith('@'),
        )
        .toSet()
        .toList()
      ..sort((a, b) => b.length.compareTo(a.length));

RegExp? searchWordPattern(String query) {
  final words = searchWords(query);
  return words.isEmpty
      ? null
      : RegExp(words.map(RegExp.escape).join('|'), caseSensitive: false);
}

bool searchWordsMatch(String query, Iterable<String> fields) =>
    searchWords(query).every(
      (word) => fields.any(
        (field) => field.toLowerCase().contains(word.toLowerCase()),
      ),
    );

String searchSnippet(String text, String query) {
  final match = searchWordPattern(query)?.firstMatch(text);
  return match == null || match.start < 60
      ? text
      : '…${text.substring(match.start - 40)}';
}

TextStyle searchHitStyle(BuildContext context) => TextStyle(
  color: DTokens.of(context).primary,
  backgroundColor: DTokens.of(context).primary.withValues(alpha: .13),
);

List<TextSpan> searchTextSpans(String text, String query, TextStyle style) {
  final pattern = searchWordPattern(query);
  if (pattern == null) return [TextSpan(text: text)];
  final spans = <TextSpan>[];
  var cursor = 0;
  for (final match in pattern.allMatches(text)) {
    if (match.start > cursor) {
      spans.add(TextSpan(text: text.substring(cursor, match.start)));
    }
    spans.add(TextSpan(text: match.group(0), style: style));
    cursor = match.end;
  }
  if (cursor < text.length) spans.add(TextSpan(text: text.substring(cursor)));
  return spans;
}

class SearchText extends StatelessWidget {
  const SearchText(
    this.text, {
    super.key,
    this.query,
    this.style,
    this.maxLines,
    this.overflow,
  });
  final String text;
  final String? query;
  final TextStyle? style;
  final int? maxLines;
  final TextOverflow? overflow;
  @override
  Widget build(BuildContext context) => Text.rich(
    TextSpan(
      children: searchTextSpans(
        text,
        query ?? SearchWords.of(context),
        searchHitStyle(context),
      ),
    ),
    style: style,
    maxLines: maxLines,
    overflow: overflow,
  );
}

/// Annotate text nodes only; attributes, URLs, code and interactive markup keep
/// their original meaning. Never interpolate user words into HTML.
String highlightSearchHtml(String html, String query) {
  final pattern = searchWordPattern(query);
  if (pattern == null) return html;
  final inputCodeUnits = html.length + query.length;
  final cacheKey = inputCodeUnits <= _highlightHtmlMaxEntryCodeUnits
      ? (html, query)
      : null;
  final cached = cacheKey == null
      ? null
      : _highlightedSearchHtml.read(cacheKey);
  if (cached != null) return cached;
  final fragment = html_parser.parseFragment(html);
  void visit(dom.Node node) {
    if (node is dom.Element &&
        const {
          'script',
          'style',
          'code',
          'pre',
          'mark',
        }.contains(node.localName)) {
      return;
    }
    for (final child in node.nodes.toList()) {
      if (child is! dom.Text) {
        visit(child);
        continue;
      }
      final text = child.data;
      var cursor = 0;
      final replacements = <dom.Node>[];
      for (final match in pattern.allMatches(text)) {
        if (match.start > cursor) {
          replacements.add(dom.Text(text.substring(cursor, match.start)));
        }
        replacements.add(
          dom.Element.tag('mark')
            ..classes.add('native-search-hit')
            ..text = match.group(0)!,
        );
        cursor = match.end;
      }
      if (replacements.isEmpty) continue;
      if (cursor < text.length) {
        replacements.add(dom.Text(text.substring(cursor)));
      }
      final at = node.nodes.indexOf(child);
      child.remove();
      node.nodes.insertAll(at, replacements);
    }
  }

  visit(fragment);
  final highlighted = fragment.outerHtml;
  if (cacheKey != null &&
      inputCodeUnits + highlighted.length <= _highlightHtmlMaxEntryCodeUnits) {
    _highlightedSearchHtml.put(cacheKey, highlighted);
  }
  return highlighted;
}

const _highlightHtmlMaxEntryCodeUnits = 256 * 1024;
final _highlightedSearchHtml = BoundedLruCache<(String, String), String>(16);
