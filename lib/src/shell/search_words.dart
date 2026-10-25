import 'dart:async';

import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/foundation.dart';
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
  if (searchWords(query).isEmpty) return html;
  final request = (html: html, query: query);
  final cached = _cachedSearchHtml(request);
  if (cached != null) return cached;
  final highlighted = _highlightSearchHtml(request);
  _cacheSearchHtml(request, highlighted);
  return highlighted;
}

typedef SearchHtmlRequest = ({String html, String query});

final class SearchHtmlPreparation {
  SearchHtmlPreparation({
    required VoidCallback onChanged,
    Future<String> Function(SearchHtmlRequest)? prepare,
  }) : _onChanged = onChanged,
       _prepare = prepare ?? _prepareSearchHtml;

  VoidCallback? _onChanged;
  final Future<String> Function(SearchHtmlRequest) _prepare;
  SearchHtmlRequest? _requested;
  SearchHtmlRequest? _active;
  String? _result;

  String? resolve(String html, String query) {
    final request = (html: html, query: query);
    if (request != _requested) {
      _requested = request;
      _result = null;
    }
    if (_result != null) return _result;
    if (searchWords(query).isEmpty) return _result = html;
    final cached = _cachedSearchHtml(request);
    if (cached != null) return _result = cached;
    if (html.length + query.length < 32 * 1024) {
      return _result = highlightSearchHtml(html, query);
    }
    if (_active == null) _start(request);
    return null;
  }

  void _start(SearchHtmlRequest request) {
    _active = request;
    unawaited(
      Future<String>.sync(() => _prepare(request)).then(
        (highlighted) => _complete(request, highlighted),
        onError: (Object error, StackTrace stack) {
          if (_onChanged == null) return;
          FlutterError.reportError(
            FlutterErrorDetails(
              exception: error,
              stack: stack,
              library: 'search highlighting',
              context: ErrorDescription('while preparing searched post HTML'),
            ),
          );
          _complete(request, request.html, cache: false);
        },
      ),
    );
  }

  void _complete(
    SearchHtmlRequest request,
    String highlighted, {
    bool cache = true,
  }) {
    if (_onChanged == null) return;
    _active = null;
    if (cache) _cacheSearchHtml(request, highlighted);
    if (request == _requested) {
      _result = highlighted;
      _onChanged!();
    } else if (_result == null && _requested != null) {
      _start(_requested!);
    }
  }

  void dispose() {
    _onChanged = null;
    _requested = null;
    _active = null;
    _result = null;
  }
}

Future<String> _prepareSearchHtml(SearchHtmlRequest request) => compute(
  _highlightSearchHtml,
  request,
  debugLabel: 'searchHtmlHighlighting',
);

String? _cachedSearchHtml(SearchHtmlRequest request) =>
    request.html.length + request.query.length <=
        _highlightHtmlMaxEntryCodeUnits
    ? _highlightedSearchHtml.read((request.html, request.query))
    : null;

void _cacheSearchHtml(SearchHtmlRequest request, String highlighted) {
  if (request.html.length + request.query.length + highlighted.length <=
      _highlightHtmlMaxEntryCodeUnits) {
    _highlightedSearchHtml.put((request.html, request.query), highlighted);
  }
}

String _highlightSearchHtml(SearchHtmlRequest request) {
  final (:html, :query) = request;
  final pattern = searchWordPattern(query);
  if (pattern == null) return html;
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
  return fragment.outerHtml;
}

const _highlightHtmlMaxEntryCodeUnits = 256 * 1024;
final _highlightedSearchHtml = BoundedLruCache<(String, String), String>(16);
