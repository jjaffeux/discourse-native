/// Turns source into per-line runs of scoped text.
///
/// `package:highlight` is the Dart port of highlight.js, so the scope names
/// this reports are highlight.js class names. It tokenizes a whole document at
/// once — a string literal or block comment spans lines — while `CodeBlock`
/// draws one line at a time, so the token stream is cut back up on newlines
/// here.
library;

import 'dart:collection';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:highlight/highlight.dart' show highlight, Node;

/// A run of source with one syntactic meaning, or none.
class CodeToken {
  const CodeToken(this.text, [this.scope]);

  final String text;

  /// A highlight.js class name such as `keyword`, `string` or `comment`.
  /// Null for source the highlighter had no opinion about.
  final String? scope;
}

/// Languages tried when the markup says `auto`.
///
/// Real auto-detection parses with all ~190 registered languages, which is
/// slow enough to be visible. Discourse names the language in nearly every
/// case (`lang-rb`, `lang-plaintext`), so `auto` is rare and a short list of
/// what people actually post is enough.
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

/// Language names Discourse emits that highlight.js does not know.
const Map<String, String> languageAliases = {
  'es6': 'javascript',
  'jsx': 'javascript',
  'tsx': 'typescript',
  'hbs': 'handlebars',
  'html.hbs': 'handlebars',
  'gjs': 'javascript',
  'gts': 'typescript',
};

/// Above this, a block is left unhighlighted.
///
/// Highlighting runs when the widget is built, and a `ListView` rebuilds a post
/// every time it scrolls back into view. That is fine for the code people post;
/// it is not fine for a pastebin onebox holding a whole file, where the regex
/// pass is long enough to drop frames. Colour is worth less than a smooth
/// scroll.
const int maxHighlightedChars = 20000;

/// How many highlighted blocks are retained for reuse.
///
/// Every admitted source is already capped by [maxHighlightedChars], so the
/// cache has both an entry bound and a source-size bound. Thirty-two entries
/// cover the blocks likely to be rebuilt while scrolling without turning old
/// topics into an unbounded document cache.
@visibleForTesting
const int syntaxHighlightCacheCapacity = 32;

typedef _HighlightKey = ({String source, String language});

final LinkedHashMap<_HighlightKey, List<List<CodeToken>>>
_syntaxHighlightCache = LinkedHashMap();

/// Splits [source] into lines of tokens, highlighted as [language].
///
/// Returns one entry per line of [source]. Unknown languages, `plaintext`,
/// anything past [maxHighlightedChars] and anything the highlighter chokes on
/// come back as a single unscoped token per line, which renders as plain
/// monospace rather than as an error.
List<List<CodeToken>> highlightLines(String source, String? language) {
  final lines = source.split('\n');
  final plain = [
    for (final line in lines) [CodeToken(line)],
  ];
  final normalizedLanguage = language?.toLowerCase();
  if (_bypassesParser(source, normalizedLanguage)) return plain;

  final key = (source: source, language: normalizedLanguage!);
  if (_syntaxHighlightCache.remove(key) case final cached?) {
    // Removing and reinserting promotes the entry to most-recently used.
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

/// Whether a [highlightLines] call would have to run the parser.
///
/// False when the plain path answers — no language, `plaintext`, past
/// [maxHighlightedChars] — or when the cache already holds this exact body.
/// Either way the call costs a split, not a parse, so a caller deciding
/// whether to take tokenization off the current frame can ask this first.
bool highlightNeedsParse(String source, String? language) {
  final normalizedLanguage = language?.toLowerCase();
  if (_bypassesParser(source, normalizedLanguage)) return false;
  return !_syntaxHighlightCache.containsKey((
    source: source,
    language: normalizedLanguage!,
  ));
}

/// The inputs [highlightLines] answers with unscoped lines and no parse.
bool _bypassesParser(String source, String? normalizedLanguage) =>
    source.length > maxHighlightedChars ||
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

/// Clears process-wide highlighting state so cache behavior is deterministic
/// in focused tests.
@visibleForTesting
void clearSyntaxHighlightCacheForTesting() => _syntaxHighlightCache.clear();

/// Keeps callers' list containers independent while safely reusing the
/// immutable [CodeToken] values produced by the expensive parser pass.
List<List<CodeToken>> _copyLines(List<List<CodeToken>> lines) => [
  for (final line in lines) List<CodeToken>.of(line),
];

List<List<CodeToken>> _freezeLines(List<List<CodeToken>> lines) =>
    List<List<CodeToken>>.unmodifiable([
      for (final line in lines) List<CodeToken>.unmodifiable(line),
    ]);

/// Resolves what the markup said into a language the highlighter registered,
/// or null to leave the source alone.
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

/// Picks the candidate that parses with the highest relevance, hljs-style.
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

/// Walks the node tree into a flat run of tokens.
///
/// Nodes nest — a `title` inside a `function` — and the innermost scope is the
/// specific one, so children inherit only where they have nothing of their own.
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

/// Cuts a token run into one list per line, splitting tokens that span them.
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
