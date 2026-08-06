/// Turns source into per-line runs of scoped text.
///
/// `package:highlight` is the Dart port of highlight.js, so the scope names
/// this reports are highlight.js class names. It tokenizes a whole document at
/// once — a string literal or block comment spans lines — while `CodeBlock`
/// draws one line at a time, so the token stream is cut back up on newlines
/// here.
library;

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
  if (source.length > maxHighlightedChars) return plain;

  final resolved = _resolve(language, source);
  if (resolved == null) return plain;

  final List<Node>? nodes;
  try {
    nodes = highlight.parse(source, language: resolved).nodes;
  } catch (_) {
    // A highlighter that trips over one post must not take the post with it.
    return plain;
  }
  if (nodes == null) return plain;

  final highlighted = _splitOnNewlines(_flatten(nodes, null));

  // Highlighting must not change the text. If it somehow did, the line numbers
  // and selection would no longer line up, so prefer the unhighlighted source.
  if (highlighted.length != lines.length) return plain;
  return highlighted;
}

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
