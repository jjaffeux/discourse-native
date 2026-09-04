library;

import 'dart:collection';

import 'package:flutter/foundation.dart' show compute, visibleForTesting;
import 'package:highlight/highlight.dart' show highlight, Mode, Node;
import 'package:highlight/languages/all.dart' show allLanguages;

class CodeToken {
  const CodeToken(this.text, [this.scope]);

  final String text;

  final String? scope;
}

const List<String> autoDetectCandidates = [
  'javascript',
  'ruby',
  'python',
  'json',
  'yaml',
  'bash',
  'sql',
  'html',
  'css',
  'dart',
  'java',
  'go',
  'rust',
  'php',
  'diff',
];

const Map<String, String> languageAliases = {
  'es6': 'javascript',
  'jsx': 'javascript',
  'tsx': 'typescript',
  'hbs': 'handlebars',
  'html.hbs': 'handlebars',
  'gjs': 'javascript',
  'gts': 'typescript',
};

const int maxHighlightedChars = 20000;

/// Auto detection runs every candidate grammar. Past this point plain text is
/// a better trade than fifteen parser passes over content being laid out.
const int maxAutoDetectedChars = 4000;

/// Larger explicitly-labelled blocks are highlighted after their first paint.
const int backgroundSyntaxHighlightThreshold = 2000;

@visibleForTesting
const int syntaxHighlightCacheCapacity = 32;

typedef _HighlightKey = ({String source, String language});

final LinkedHashMap<_HighlightKey, List<List<CodeToken>>>
_syntaxHighlightCache = LinkedHashMap();

List<List<CodeToken>> highlightLines(String source, String? language) {
  final lines = source.split('\n');
  final plain = [
    for (final line in lines) [CodeToken(line)],
  ];
  final normalizedLanguage = language?.toLowerCase();
  if (_bypassesParser(source, normalizedLanguage)) return plain;

  final key = (source: source, language: normalizedLanguage!);
  if (_syntaxHighlightCache.remove(key) case final cached?) {
    _syntaxHighlightCache[key] = cached;
    return _copyLines(cached);
  }

  final resolved = _resolve(normalizedLanguage, source);
  if (resolved == null) return _remember(key, plain);

  final List<Node>? nodes;
  try {
    nodes = highlight.parse(source, language: resolved).nodes;
  } catch (_) {
    // A highlighter that trips over one post must not take the post with it.
    return _remember(key, plain);
  }
  if (nodes == null) return _remember(key, plain);

  final highlighted = _splitOnNewlines(_flatten(nodes, null));

  // Highlighting must not change the text. If it somehow did, the line numbers
  // and selection would no longer line up, so prefer the unhighlighted source.
  final result = highlighted.length == lines.length ? highlighted : plain;
  return _remember(key, result);
}

bool highlightNeedsParse(String source, String? language) {
  final normalizedLanguage = language?.toLowerCase();
  if (_bypassesParser(source, normalizedLanguage)) return false;
  return !_syntaxHighlightCache.containsKey((
    source: source,
    language: normalizedLanguage!,
  ));
}

bool highlightShouldRunInBackground(String source, String? language) =>
    source.length > backgroundSyntaxHighlightThreshold &&
    highlightNeedsParse(source, language);

/// The grammar used by editor-style code surfaces.
///
/// The highlighter accepts aliases such as `rb`, but [allLanguages] is keyed by
/// canonical names, so resolve aliases here before handing a [Mode] to clients.
Mode? highlightMode(String source, String? language) {
  final resolved = _resolve(language, source);
  if (resolved == null) return null;

  final direct = allLanguages[resolved];
  if (direct != null) return direct;

  for (final mode in allLanguages.values) {
    if (mode.aliases?.contains(resolved) ?? false) return mode;
  }
  return null;
}

List<List<CodeToken>> cacheHighlightedLines(
  String source,
  String? language,
  List<List<CodeToken>> lines,
) {
  final normalizedLanguage = language?.toLowerCase();
  if (_bypassesParser(source, normalizedLanguage) ||
      lines.map((line) => line.map((token) => token.text).join()).join('\n') !=
          source) {
    return lines;
  }
  return _remember((source: source, language: normalizedLanguage!), lines);
}

Future<List<List<CodeToken>>> highlightLinesInBackground(
  String source,
  String? language,
) async {
  final portable = await compute<_HighlightRequest, _PortableHighlight>(
    _portableHighlight,
    (source: source, language: language),
    debugLabel: 'Discourse syntax highlight',
  );
  return cacheHighlightedLines(source, language, [
    for (final line in portable)
      [for (final token in line) CodeToken(token.text, token.scope)],
  ]);
}

typedef _HighlightRequest = ({String source, String? language});
typedef _PortableToken = ({String text, String? scope});
typedef _PortableHighlight = List<List<_PortableToken>>;

_PortableHighlight _portableHighlight(_HighlightRequest request) => [
  for (final line in highlightLines(request.source, request.language))
    [for (final token in line) (text: token.text, scope: token.scope)],
];

bool _bypassesParser(String source, String? normalizedLanguage) =>
    source.length > maxHighlightedChars ||
    (normalizedLanguage == 'auto' && source.length > maxAutoDetectedChars) ||
    normalizedLanguage == null ||
    normalizedLanguage.isEmpty ||
    normalizedLanguage == 'plaintext' ||
    normalizedLanguage == 'text' ||
    normalizedLanguage == 'nohighlight';

List<List<CodeToken>> _remember(
  _HighlightKey key,
  List<List<CodeToken>> lines,
) {
  final cached = _freezeLines(lines);
  _syntaxHighlightCache[key] = cached;
  if (_syntaxHighlightCache.length > syntaxHighlightCacheCapacity) {
    _syntaxHighlightCache.remove(_syntaxHighlightCache.keys.first);
  }
  return _copyLines(cached);
}

@visibleForTesting
void clearSyntaxHighlightCacheForTesting() => _syntaxHighlightCache.clear();

List<List<CodeToken>> _copyLines(List<List<CodeToken>> lines) => [
  for (final line in lines) List<CodeToken>.of(line),
];

List<List<CodeToken>> _freezeLines(List<List<CodeToken>> lines) =>
    List<List<CodeToken>>.unmodifiable([
      for (final line in lines) List<CodeToken>.unmodifiable(line),
    ]);

String? _resolve(String? language, String source) {
  final name = language?.toLowerCase();
  if (name == null || name.isEmpty) return null;
  if (name == 'plaintext' || name == 'text' || name == 'nohighlight') {
    return null;
  }
  if (name == 'auto') return _detect(source);

  // A name the highlighter does not know parses as plaintext, which is exactly
  // the fallback we want — so there is nothing to validate here. Aliases
  // highlight.js registers itself, such as `rb` for Ruby, also just work; the
  // table above is only for names Discourse uses that it does not.
  return languageAliases[name] ?? name;
}

String? _detect(String source) {
  String? best;
  var bestRelevance = 0;

  for (final candidate in autoDetectCandidates) {
    try {
      final relevance = highlight.parse(source, language: candidate).relevance;
      if (relevance != null && relevance > bestRelevance) {
        bestRelevance = relevance;
        best = candidate;
      }
    } catch (_) {
      continue;
    }
  }
  return best;
}

List<CodeToken> _flatten(List<Node> nodes, String? inherited) {
  final tokens = <CodeToken>[];

  for (final node in nodes) {
    final scope = node.className ?? inherited;
    if (node.value case final value?) {
      tokens.add(CodeToken(value, scope));
    }
    if (node.children case final children?) {
      tokens.addAll(_flatten(children, scope));
    }
  }
  return tokens;
}

List<List<CodeToken>> _splitOnNewlines(List<CodeToken> tokens) {
  final lines = <List<CodeToken>>[];
  var current = <CodeToken>[];

  for (final token in tokens) {
    final parts = token.text.split('\n');
    for (final (index, part) in parts.indexed) {
      if (index > 0) {
        lines.add(current);
        current = <CodeToken>[];
      }
      if (part.isNotEmpty) current.add(CodeToken(part, token.scope));
    }
  }
  lines.add(current);

  return lines;
}
